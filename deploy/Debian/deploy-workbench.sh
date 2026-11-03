#!/bin/bash
# Copies the working tree and the local MariaDB extensions (plugins/mariadb.*) to the server, into
# /opt/mariadb-shell-workbench, and runs setup-workbench.sh there (build, units, oauth2-proxy, nginx).
#
#   deploy/Debian/deploy-workbench.sh <host> [--no-build]
#
# <host> is the Workbench's public name. SSH_TARGET says where to log in (root@<host> by default); a
# user with password-less sudo works too, e.g. SSH_TARGET=admin@<host>. FRAME_ANCESTORS, when set,
# is handed on to setup-workbench.sh. SETUP=Raspberry-Pi-OS runs that folder's setup-workbench.sh
# instead (deploy/Raspberry-Pi-OS/deploy-workbench.sh does), with the arguments after <host>.
set -euo pipefail
cd "$(dirname "$0")/../.."
HOST=${1:?usage: $0 <host> [setup-workbench.sh arguments...]}
shift
TARGET=${SSH_TARGET:-root@$HOST}
SETUP=${SETUP:-Debian}
APP=/opt/mariadb-shell-workbench
SUDO=
[ "${TARGET%%@*}" = root ] || SUDO=sudo
ls -d plugins/mariadb.mariadb-shell plugins/mariadb.mariadb-shell-agent >/dev/null ||
  { echo "unpack both MariaDB extensions first (npm run plugin:mariadb, plugin:mariadb-shell-agent)" >&2; exit 1; }

# The Open VSX plugins are downloaded on the server; tools/ (its Firefox profile holds logins),
# private/ and .claude/ never leave this machine; electron/ is the desktop app.
ssh "$TARGET" "$SUDO mkdir -p $APP"
rsync -az --delete --chown=root:root ${SUDO:+--rsync-path="sudo rsync"} \
  --exclude /node_modules/ --exclude /lib/ --exclude /src-gen/ --exclude '/gen-*' \
  --exclude /esbuild.mjs --exclude /.git/ --exclude '/*.log' --exclude /plugins/ --exclude /tools/ \
  --exclude /private/ --exclude /electron/ --exclude /.claude/ \
  ./ "$TARGET:$APP/"
ssh "$TARGET" "$SUDO mkdir -p $APP/plugins && $SUDO rm -rf $APP/plugins/mariadb.*"
rsync -az --chown=root:root ${SUDO:+--rsync-path="sudo rsync"} plugins/mariadb.* "$TARGET:$APP/plugins/"
ssh "$TARGET" "$SUDO ${FRAME_ANCESTORS+FRAME_ANCESTORS=$(printf %q "$FRAME_ANCESTORS")} $APP/deploy/$SETUP/setup-workbench.sh $HOST $*"
