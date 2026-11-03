#!/bin/bash
# The users' MariaDB REST daemons behind nginx, under a host of their own (run as root after
# setup-keycloak.sh, with that host's DNS name pointing here). Idempotent.
#
#   ./setup-restd-proxy.sh <rest-host> [<first>-<last>] [<offset>]
#
# The REST host has to be outside the Workbench's cookie domain: a sibling such as
# webapps.example.com beside workbench.example.com, never the Workbench's own name or one below it
# (oauth2-proxy's cookie is set for .<workbench host>). Nothing ties a daemon port to a Linux
# user: any user can listen on a stopped daemon's port, and nginx then serves that under the REST
# host's name and certificate - which must therefore carry no Workbench cookie.
#
# Writes:
# - a Let's Encrypt certificate for the REST host;
# - /etc/nginx/sites-available/restd-proxy: per public port (8443-8462 by default) a server
#   block with that certificate passing to 127.0.0.1:<port + offset> (offset 10000 by default),
#   plus a default server per port that rejects the TLS handshake for any other name;
# - /etc/mariadb-restd/proxy.conf: the settings MariaDB Shell's REST tools read for every user
#   (MARIADB_RESTD_PROXY_*), so a new daemon listens on the loopback without TLS.
set -euo pipefail
REST_HOST=${1:?usage: $0 <rest-host> [<first>-<last>] [<offset>]}
PORTS=${2:-8443-8462}
OFFSET=${3:-10000}
FIRST=${PORTS%-*}
LAST=${PORTS#*-}

# Port 80 for the ACME challenge, then the certificate.
install -d /var/www/acme
cat > /etc/nginx/sites-available/restd-http <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $REST_HOST;
    location /.well-known/acme-challenge/ { root /var/www/acme; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
ln -sf ../sites-available/restd-http /etc/nginx/sites-enabled/restd-http
nginx -t -q && systemctl reload nginx
if [ ! -d "/etc/letsencrypt/live/$REST_HOST" ]; then
  certbot certonly --webroot -w /var/www/acme -d "$REST_HOST" \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --deploy-hook "systemctl reload nginx"
fi

# One server block per public port: static, so setting up a daemon needs no reload.
{
  echo "# MariaDB REST daemons on $REST_HOST, written by setup-restd-proxy.sh."
  echo "# Public port P -> 127.0.0.1:P+$OFFSET, where the daemon listens without TLS."
  for ((port = FIRST; port <= LAST; port++)); do
    cat <<EOF

server {
    listen $port ssl default_server;
    listen [::]:$port ssl default_server;
    # Any other name on this port gets no TLS at all.
    ssl_reject_handshake on;
}
server {
    listen $port ssl;
    listen [::]:$port ssl;
    http2 on;
    server_name $REST_HOST;
    ssl_certificate     /etc/letsencrypt/live/$REST_HOST/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$REST_HOST/privkey.pem;
    add_header Strict-Transport-Security "max-age=31536000" always;
    location / {
        proxy_pass http://127.0.0.1:$((port + OFFSET));
        proxy_http_version 1.1;
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;
        error_page 502 = @stopped;
    }
    location @stopped {
        default_type text/plain;
        return 502 "No MariaDB REST daemon is running on port $port.\n";
    }
}
EOF
  done
} > /etc/nginx/sites-available/restd-proxy
ln -sf ../sites-available/restd-proxy /etc/nginx/sites-enabled/restd-proxy

# What MariaDB Shell's REST tools read for every user (restd.PROXY_FILE).
install -d -m 755 /etc/mariadb-restd
cat > /etc/mariadb-restd/proxy.conf <<EOF
# Written by setup-restd-proxy.sh: MariaDB REST daemons behind nginx on $REST_HOST.
MARIADB_RESTD_PROXY_HOST=$REST_HOST
MARIADB_RESTD_PROXY_PORTS=$FIRST-$LAST
MARIADB_RESTD_PROXY_PORT_OFFSET=$OFFSET
EOF
chmod 644 /etc/mariadb-restd/proxy.conf

nginx -t -q && systemctl reload nginx
echo "REST daemons: https://$REST_HOST:$FIRST-$LAST -> 127.0.0.1:$((FIRST + OFFSET))-$((LAST + OFFSET))"
