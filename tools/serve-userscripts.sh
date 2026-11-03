#!/bin/bash
# Serves private/demos/ on http://127.0.0.1:8765 (localhost only), so Tampermonkey can install and update
# the userscripts from a URL, e.g. http://127.0.0.1:8765/mariadb-cloud/app-platform.user.js
#
# The scripts show the Workbench at IDE_URL, https://workbench.example.com/ as committed. Where
# private/userscripts.conf exists (lines <vendor>/<script>.user.js=<IDE URL>), they are served from a
# copy with those addresses filled in.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=$ROOT/private/demos
CONF=$ROOT/private/userscripts.conf
if [ -f "$CONF" ]; then
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  cp -R "$DIR"/. "$TMP"/
  while IFS='=' read -r script url; do
    case $script in ''|'#'*) continue ;; esac
    [ -f "$TMP/$script" ] || { echo "$CONF: no private/demos/$script" >&2; exit 1; }
    URL=$url perl -pi -e 's/const IDE_URL = \x27[^\x27]*\x27;/const IDE_URL = \x27$ENV{URL}\x27;/' "$TMP/$script"
    echo "$script -> $url"
  done < "$CONF"
  DIR=$TMP
fi
python3 -m http.server "${PORT:-8765}" --bind 127.0.0.1 --directory "$DIR"
