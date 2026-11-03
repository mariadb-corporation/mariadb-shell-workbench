#!/bin/bash
# TLS for <host> and webview.<host>, Keycloak under https://<host>/sso with its data in the local
# MariaDB server, and the MariaDB login theme. Run as root after setup-base.sh, from a copy of this
# folder (keycloak.container and keycloak-theme/ next to this script). Idempotent.
#
# The login theme mariadb-shell-workbench extends MariaDB Shell's mariadb-mcp, taken from the MariaDB
# Shell that setup-base.sh installed, or from MARIADB_MCP_THEME=<folder> for a newer one (the
# mcp_plugin/keycloak-theme/mariadb-mcp folder of mariadb-shell-plugins).
#
#   ./setup-keycloak.sh <host>
set -euo pipefail
HOST=${1:?usage: $0 <host>}
# A relative MARIADB_MCP_THEME is relative to where this was started.
[ -n "${MARIADB_MCP_THEME:-}" ] && MARIADB_MCP_THEME=$(realpath "$MARIADB_MCP_THEME")
cd "$(dirname "$0")"
CONF=/etc/mariadb-shell-workbench
install -d -m 700 "$CONF"

rand() { openssl rand -hex 24; }

# --- TLS: port-80 vhost for the ACME challenge, then one certificate for both names.
install -d /var/www/acme
cat > /etc/nginx/sites-available/workbench-http <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $HOST webview.$HOST;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
ln -sf ../sites-available/workbench-http /etc/nginx/sites-enabled/workbench-http
rm -f /etc/nginx/sites-enabled/default
nginx -t -q && systemctl reload nginx
if [ ! -d "/etc/letsencrypt/live/$HOST" ]; then
  certbot certonly --webroot -w /var/www/acme -d "$HOST" -d "webview.$HOST" \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --deploy-hook "systemctl reload nginx"
fi

# --- Keycloak database in the local MariaDB server.
[ -f "$CONF/keycloak-db-password" ] || { rand > "$CONF/keycloak-db-password"; chmod 600 "$CONF/keycloak-db-password"; }
DBPW=$(cat "$CONF/keycloak-db-password")
mariadb <<EOF
CREATE DATABASE IF NOT EXISTS keycloak CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'keycloak'@'127.0.0.1' IDENTIFIED BY '$DBPW';
ALTER USER 'keycloak'@'127.0.0.1' IDENTIFIED BY '$DBPW';
GRANT ALL PRIVILEGES ON keycloak.* TO 'keycloak'@'127.0.0.1';
EOF

# --- Keycloak: environment (secrets), themes, quadlet.
[ -f "$CONF/keycloak-admin-password" ] || { rand > "$CONF/keycloak-admin-password"; chmod 600 "$CONF/keycloak-admin-password"; }
install -m 600 /dev/null "$CONF/keycloak.env"
cat > "$CONF/keycloak.env" <<EOF
KC_HOSTNAME=https://$HOST/sso
KC_DB_PASSWORD=$DBPW
KC_BOOTSTRAP_ADMIN_USERNAME=admin
KC_BOOTSTRAP_ADMIN_PASSWORD=$(cat "$CONF/keycloak-admin-password")
EOF
install -d "$CONF/keycloak-themes"
MCP_THEME=${MARIADB_MCP_THEME:-$(dirname "$(readlink -f "$(command -v mariadb-shell)")")/../lib/mariadb-shell/plugins/mcp_plugin/keycloak-theme/mariadb-mcp}
[ -f "$MCP_THEME/login/theme.properties" ] || { echo "no mariadb-mcp theme in $MCP_THEME" >&2; exit 1; }
rsync -a --delete "$(realpath "$MCP_THEME")" keycloak-theme/mariadb-shell-workbench "$CONF/keycloak-themes/"
install -m 644 keycloak.container /etc/containers/systemd/keycloak.container
systemctl daemon-reload
systemctl restart keycloak

# --- nginx: HTTPS vhost. setup-workbench.sh replaces it with the full one (login, routing).
[ -f /etc/nginx/sites-available/workbench ] || cat > /etc/nginx/sites-available/workbench <<EOF
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $HOST;
    ssl_certificate     /etc/letsencrypt/live/$HOST/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$HOST/privkey.pem;
    location /sso/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
    }
    location / { return 503; }
}
EOF
ln -sf ../sites-available/workbench /etc/nginx/sites-enabled/workbench
nginx -t -q && systemctl reload nginx

echo -n "waiting for Keycloak"
for _ in $(seq 1 90); do
  curl -sf -o /dev/null http://127.0.0.1:9000/sso/health/ready && { echo " ready"; exit 0; }
  echo -n .; sleep 2
done
echo " not ready; journalctl -u keycloak" >&2
exit 1
