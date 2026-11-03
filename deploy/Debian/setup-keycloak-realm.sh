#!/bin/bash
# Keycloak realm "workbench" for the multi-user Workbench (run as root after setup-keycloak.sh):
# - login theme mariadb-shell-workbench, brute-force protection, password policy (8 characters: the code is the
#   second factor);
# - browser flow "browser-otp": password AND an authenticator app code (TOTP) for every login
#   (Keycloak's default asks for a code only if the user has set one up; here a login gives a shell
#   on the server);
# - client mariadb-shell-workbench for oauth2-proxy (secret in /etc/mariadb-shell-workbench, mode 600) with
#   audience and groups mappers; group workbench-users (oauth2-proxy --allowed-group);
# - the users given as arguments, in that group, with a temporary password and an authenticator app
#   to set up at first login. New users' passwords: /etc/mariadb-shell-workbench/initial-passwords.
# Secrets reach kcadm through stdin or the environment, never the command line (other users on
# the server can read process lists).
#
#   [FRAME_ANCESTORS="https://console.example.com ..."] ./setup-keycloak-realm.sh <host> <user>...
#
# FRAME_ANCESTORS: the origins, besides the Workbench itself, that may show the login page in an
# iframe (as in setup-workbench.sh, which keeps them in /etc/mariadb-shell-workbench/frame-ancestors).
set -euo pipefail
HOST=${1:?usage: $0 <host> <user>...}
shift
CONF=/etc/mariadb-shell-workbench
[ -n "${FRAME_ANCESTORS+set}" ] && echo "$FRAME_ANCESTORS" > "$CONF/frame-ancestors"
ANCESTORS=$(cat "$CONF/frame-ancestors" 2>/dev/null || true)
CSP="frame-src 'self'; frame-ancestors 'self' https://$HOST${ANCESTORS:+ $ANCESTORS}; object-src 'none';"
REALM=workbench
CLIENT=mariadb-shell-workbench

kc() { podman exec -i keycloak /opt/keycloak/bin/kcadm.sh "$@"; }
podman exec keycloak bash -c 'KC_CLI_PASSWORD=$KC_BOOTSTRAP_ADMIN_PASSWORD /opt/keycloak/bin/kcadm.sh config credentials --server http://127.0.0.1:8080/sso --realm master --user admin' >/dev/null

if ! kc get "realms/$REALM" >/dev/null 2>&1; then
  kc create realms -f - <<EOF
{
  "realm": "$REALM",
  "displayName": "MariaDB Shell Workbench",
  "enabled": true,
  "loginTheme": "mariadb-shell-workbench",
  "bruteForceProtected": true,
  "passwordPolicy": "length(8) and notUsername",
  "otpPolicyType": "totp",
  "otpPolicyAlgorithm": "HmacSHA1",
  "otpPolicyDigits": 6,
  "otpPolicyPeriod": 30,
  "browserSecurityHeaders": {
    "contentSecurityPolicy": "$CSP",
    "xFrameOptions": ""
  }
}
EOF

  # browser-otp: Cookie | (Username Password Form + OTP Form)
  kc create authentication/flows -r "$REALM" -f - <<EOF
{ "alias": "browser-otp", "description": "Password and authenticator app code", "providerId": "basic-flow", "topLevel": true, "builtIn": false }
EOF
  kc create authentication/flows/browser-otp/executions/execution -r "$REALM" -s provider=auth-cookie >/dev/null
  kc create authentication/flows/browser-otp/executions/flow -r "$REALM" -s alias=browser-otp-forms -s type=basic-flow >/dev/null
  kc create authentication/flows/browser-otp-forms/executions/execution -r "$REALM" -s provider=auth-username-password-form >/dev/null
  kc create authentication/flows/browser-otp-forms/executions/execution -r "$REALM" -s provider=auth-otp-form >/dev/null
  # New executions all get priority 0, which leaves their order undefined: Cookie before the forms,
  # password before the code.
  kc get authentication/flows/browser-otp/executions -r "$REALM" |
    jq -c '.[] | {id,
      requirement: (if .level == 0 then "ALTERNATIVE" else "REQUIRED" end),
      priority: ({"Cookie": 10, "browser-otp-forms": 20, "Username Password Form": 10, "OTP Form": 20}[.displayName])}' |
    while read -r exec; do echo "$exec" | kc update authentication/flows/browser-otp/executions -r "$REALM" -f -; done
  kc update "realms/$REALM" -s browserFlow=browser-otp

  kc create groups -r "$REALM" -s name=workbench-users >/dev/null

  [ -f "$CONF/oauth2-proxy-client-secret" ] || { openssl rand -hex 32 | tr -d '\n' > "$CONF/oauth2-proxy-client-secret"; chmod 600 "$CONF/oauth2-proxy-client-secret"; }
  kc create clients -r "$REALM" -f - <<EOF
{
  "clientId": "$CLIENT",
  "name": "MariaDB Shell Workbench",
  "protocol": "openid-connect",
  "publicClient": false,
  "secret": "$(cat "$CONF/oauth2-proxy-client-secret")",
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "rootUrl": "https://$HOST",
  "redirectUris": ["https://$HOST/oauth2/callback"],
  "attributes": { "post.logout.redirect.uris": "https://$HOST/*" },
  "webOrigins": ["https://$HOST"],
  "protocolMappers": [
    { "name": "audience", "protocol": "openid-connect", "protocolMapper": "oidc-audience-mapper",
      "config": { "included.client.audience": "$CLIENT", "id.token.claim": "true", "access.token.claim": "true" } },
    { "name": "groups", "protocol": "openid-connect", "protocolMapper": "oidc-group-membership-mapper",
      "config": { "claim.name": "groups", "full.path": "false", "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true" } }
  ]
}
EOF
  # No email address anywhere: Keycloak cannot verify one (no mail server), and oauth2-proxy fails
  # the login on an unverified email in the token. The profile asks for neither email nor names,
  # and the client's tokens carry no email (oauth2-proxy uses the user name instead).
  kc get users/profile -r "$REALM" |
    jq '.attributes |= map(if .name == "email" or .name == "firstName" or .name == "lastName" then del(.required) else . end)' |
    kc update users/profile -r "$REALM" -f - >/dev/null
  CLIENT_ID=$(kc get clients -r "$REALM" -q clientId="$CLIENT" | jq -r '.[0].id')
  EMAIL_SCOPE=$(kc get client-scopes -r "$REALM" | jq -r '.[] | select(.name == "email") | .id')
  kc delete "clients/$CLIENT_ID/default-client-scopes/$EMAIL_SCOPE" -r "$REALM"
  echo "realm $REALM created"
fi

# A login lasts a working day (15 h), even with long breaks: Keycloak's defaults (30 minutes idle,
# 10 h at most) ended the session between two of oauth2-proxy's hourly refreshes (--cookie-refresh),
# so users had to log in again about every hour. oauth2-proxy's --cookie-expire matches.
# Set on every run, so an existing realm gets it too.
kc update "realms/$REALM" -s ssoSessionIdleTimeout=54000 -s ssoSessionMaxLifespan=54000
# Who may frame the login page: kept in step with FRAME_ANCESTORS on every run.
jq -n --arg csp "$CSP" '{browserSecurityHeaders: {contentSecurityPolicy: $csp, xFrameOptions: ""}}' |
  kc update "realms/$REALM" -f -

GROUP_ID=$(kc get groups -r "$REALM" -q search=workbench-users | jq -r '.[0].id')
install -m 600 /dev/null "$CONF/initial-passwords.new"
[ -f "$CONF/initial-passwords" ] && cat "$CONF/initial-passwords" > "$CONF/initial-passwords.new"
for USER in "$@"; do
  if [ "$(kc get users -r "$REALM" -q username="$USER" -q exact=true | jq length)" != 0 ]; then
    echo "user $USER exists"; continue
  fi
  PW=$(openssl rand -base64 18)
  kc create users -r "$REALM" -f - <<EOF
{
  "username": "$USER",
  "enabled": true,
  "requiredActions": ["UPDATE_PASSWORD", "CONFIGURE_TOTP"],
  "credentials": [{ "type": "password", "value": "$PW", "temporary": true }]
}
EOF
  USER_ID=$(kc get users -r "$REALM" -q username="$USER" -q exact=true | jq -r '.[0].id')
  kc update "users/$USER_ID/groups/$GROUP_ID" -r "$REALM" -n
  echo "$USER $PW" >> "$CONF/initial-passwords.new"
  echo "user $USER created"
done
mv "$CONF/initial-passwords.new" "$CONF/initial-passwords"
