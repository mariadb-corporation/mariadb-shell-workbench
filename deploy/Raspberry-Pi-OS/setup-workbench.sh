#!/bin/bash
# Builds the Workbench in /opt/mariadb-shell-workbench and installs the single-user parts on
# Raspberry Pi OS: the IDE as a system unit running as <user>, oauth2-proxy in front of it, the
# nginx vhost. Run as root after ../Debian/setup-base.sh, setup-keycloak.sh and
# setup-keycloak-realm.sh (deploy-workbench.sh copies the tree and runs this). Idempotent.
#
#   [FRAME_ANCESTORS="https://console.example.com ..."] \
#     /opt/mariadb-shell-workbench/deploy/Raspberry-Pi-OS/setup-workbench.sh <host> <user> [--no-build]
#
# <user>: the Linux account the IDE runs as (its terminals, files and workspace ~/workspace).
# FRAME_ANCESTORS: as in ../Debian/setup-workbench.sh, kept in /etc/mariadb-shell-workbench/frame-ancestors.
set -euo pipefail
HOST=${1:?usage: $0 <host> <user> [--no-build]}
USER_NAME=${2:?usage: $0 <host> <user> [--no-build]}
APP=/opt/mariadb-shell-workbench
HERE=$APP/deploy/Raspberry-Pi-OS
CONF=/etc/mariadb-shell-workbench
HOME_DIR=$(getent passwd "$USER_NAME" | cut -d: -f6)
[ -n "$HOME_DIR" ] || { echo "no Linux account $USER_NAME" >&2; exit 1; }

if [ "${3:-}" != "--no-build" ]; then
  systemctl stop mariadb-shell-workbench.service 2>/dev/null || true
  cd "$APP"
  npm ci --no-audit --no-fund
  npm run download:plugins
  NODE_OPTIONS=--max-old-space-size=4096 npm run build
fi

[ -n "${FRAME_ANCESTORS+set}" ] && echo "$FRAME_ANCESTORS" > "$CONF/frame-ancestors"
ANCESTORS=$(cat "$CONF/frame-ancestors" 2>/dev/null || true)

# The IDE, as <user>, in ~/workspace.
install -d -o "$USER_NAME" -g "$(id -gn "$USER_NAME")" "$HOME_DIR/workspace"
echo "THEIA_HOSTS=$HOST" > "$CONF/workbench.env"
sed -e "s/@USER@/$USER_NAME/g" -e "s|@HOME@|$HOME_DIR|g" "$HERE/mariadb-shell-workbench.service" \
  > /etc/systemd/system/mariadb-shell-workbench.service

# oauth2-proxy: its secrets, readable by the image's nonroot user only.
install -d -m 700 -o 65532 -g 65532 "$CONF/oauth2-proxy"
install -m 400 -o 65532 -g 65532 "$CONF/oauth2-proxy-client-secret" "$CONF/oauth2-proxy/client-secret"
[ -f "$CONF/oauth2-proxy/cookie-secret" ] ||
  (umask 077; openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n' > "$CONF/oauth2-proxy/cookie-secret")
chown 65532:65532 "$CONF/oauth2-proxy/cookie-secret"
chmod 400 "$CONF/oauth2-proxy/cookie-secret"
sed "s/@HOST@/$HOST/g" "$HERE/oauth2-proxy.container" > /etc/containers/systemd/oauth2-proxy.container

# nginx: the full vhost replaces the one setup-keycloak.sh wrote.
sed -e "s/@HOST@/$HOST/g" -e "s|@FRAME_ANCESTORS@|$ANCESTORS|g" "$HERE/nginx-workbench.conf" \
  > /etc/nginx/sites-available/workbench
ln -sf ../sites-available/workbench /etc/nginx/sites-enabled/workbench

systemctl daemon-reload
systemctl enable mariadb-shell-workbench.service
systemctl restart mariadb-shell-workbench.service oauth2-proxy.service
nginx -t -q && systemctl reload nginx
systemctl is-active mariadb-shell-workbench.service oauth2-proxy.service
