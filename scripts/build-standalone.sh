#!/bin/bash
# Builds MariaDB Shell Workbench as a desktop application (Electron) for the platform it runs on:
# electron/dist/ gets a .dmg and .zip on macOS, an AppImage and .tar.gz on Linux, an installer on Windows.
#
#   scripts/build-standalone.sh [electron-builder options]   (npm run build:standalone [-- --dir])
#
# The app in electron/ is the same Theia app with the Electron target: its own node_modules (native
# modules rebuilt for Electron), the patches from patches/, and the extensions from plugins/, so run
# download:plugins, plugin:mariadb and plugin:mariadb-shell-agent first. Its version is the root
# package.json's.
#
# MARIADB_EXTENSIONS_FROM=releases takes the two MariaDB extensions from their GitHub releases
# instead (scripts/fetch-extensions.mjs, for CI). MariaDB Shell and the REST daemon for this platform
# are always bundled from their releases (scripts/fetch-bundled-tools.mjs); the tags of all four are
# pinned in those scripts and can be overridden by environment variables.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d plugins/vscode.git ] || npm run download:plugins
[ "${MARIADB_EXTENSIONS_FROM:-}" = releases ] && node scripts/fetch-extensions.mjs
node scripts/fetch-bundled-tools.mjs
for ext in mariadb.mariadb-shell mariadb.mariadb-shell-agent; do
  [ -d "plugins/$ext" ] || echo "warning: plugins/$ext is missing; the app is built without it" >&2
done

VERSION=$(node -p 'require("./package.json").version')
cd electron
# Install when the lock file changed since the last install (or there is none yet).
if [ ! -f package-lock.json ] || [ ! -f node_modules/.package-lock.json ] \
  || [ package-lock.json -nt node_modules/.package-lock.json ]; then
  if [ -f package-lock.json ]; then npm ci; else npm install; fi
fi
npm run icons
# Electron downloads its binary on first use; its LICENSE and LICENSES.chromium.html go into the app.
node -e 'require("electron")' >/dev/null
(cd .. && node scripts/generate-notices.mjs)
npx theia build --mode production
npx theia rebuild:electron
npx electron-builder -c.extraMetadata.version="$VERSION" "$@"
