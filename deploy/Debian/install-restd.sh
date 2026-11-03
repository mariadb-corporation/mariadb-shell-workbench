#!/bin/bash
# Installs the MariaDB REST daemon (mariadb-restd) for all users, next to MariaDB Shell:
# /opt/mariadb-restd/<version>, its programs linked into /usr/local/bin, where MariaDB Shell finds
# it (PATH first). Run as root with a release tarball and the release's SHA256SUMS from
# https://github.com/mariadb-corporation/rest-daemon/releases, e.g. on the server:
#
#   gh release download v26.10.0 -R mariadb-corporation/rest-daemon \
#     -p 'mariadb-restd-26.10.0-linux-aarch64.tar.gz' -p SHA256SUMS      # or linux-x86_64
#   ./install-restd.sh mariadb-restd-26.10.0-linux-aarch64.tar.gz SHA256SUMS
set -euo pipefail
TARBALL=${1:?usage: $0 <mariadb-restd-...tar.gz> <SHA256SUMS>}
SUMS=${2:?usage: $0 <mariadb-restd-...tar.gz> <SHA256SUMS>}

NAME=$(basename "$TARBALL" .tar.gz)
VERSION=$(echo "$NAME" | sed -E 's/^mariadb-restd-([0-9][^-]*)-.*/\1/')
(cd "$(dirname "$TARBALL")" && grep " $NAME.tar.gz\$" "$(realpath "$SUMS")" | sha256sum -c --quiet)

TMP=$(mktemp -d)
tar -xzf "$TARBALL" -C "$TMP"
install -d /opt/mariadb-restd
rm -rf "/opt/mariadb-restd/$VERSION"
mv "$TMP/$NAME" "/opt/mariadb-restd/$VERSION"
chown -R root:root "/opt/mariadb-restd/$VERSION"
rm -rf "$TMP"
for bin in /opt/mariadb-restd/"$VERSION"/bin/*; do
  ln -sfn "$bin" "/usr/local/bin/$(basename "$bin")"
done
mariadb-restd --version
