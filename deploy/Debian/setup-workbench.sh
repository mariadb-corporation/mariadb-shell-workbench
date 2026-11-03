#!/bin/bash
# Builds the Workbench in /opt/mariadb-shell-workbench and installs the multi-user parts: per-user IDE
# unit, spawner, oauth2-proxy, nginx vhost. Run as root after setup-keycloak.sh and
# setup-keycloak-realm.sh (deploy-workbench.sh copies the tree and runs this). Idempotent.
#
#   [FRAME_ANCESTORS="https://console.example.com ..."] \
#     /opt/mariadb-shell-workbench/deploy/Debian/setup-workbench.sh <host> [--no-build]
#
# FRAME_ANCESTORS: the origins, besides the Workbench itself, that may show it in an iframe (a cloud
# console with a userscript). Kept in /etc/mariadb-shell-workbench/frame-ancestors for
# later runs; FRAME_ANCESTORS= (empty) removes them. Set the same in setup-keycloak-realm.sh.
set -euo pipefail
HOST=${1:?usage: $0 <host> [--no-build]}
APP=/opt/mariadb-shell-workbench
HERE=$APP/deploy/Debian
CONF=/etc/mariadb-shell-workbench

if [ "${2:-}" != "--no-build" ]; then
  systemctl stop 'mariadb-shell-workbench@*' 2>/dev/null || true
  cd "$APP"
  npm ci --no-audit --no-fund
  npm run download:plugins
  NODE_OPTIONS=--max-old-space-size=4096 npm run build
fi

[ -n "${FRAME_ANCESTORS+set}" ] && echo "$FRAME_ANCESTORS" > "$CONF/frame-ancestors"
ANCESTORS=$(cat "$CONF/frame-ancestors" 2>/dev/null || true)

getent group workbench >/dev/null || groupadd workbench

# Per-user IDE and spawner.
echo "THEIA_HOSTS=$HOST" > "$CONF/workbench.env"
install -m 644 "$HERE/mariadb-shell-workbench@.service" "$HERE/workbench-spawner.service" /etc/systemd/system/
install -d /usr/local/lib/mariadb-shell-workbench
install -m 755 "$HERE/workbench-spawner.py" /usr/local/lib/mariadb-shell-workbench/

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
systemctl enable --now workbench-spawner.service
systemctl restart workbench-spawner.service oauth2-proxy.service
nginx -t -q && systemctl reload nginx
systemctl is-active workbench-spawner.service oauth2-proxy.service
