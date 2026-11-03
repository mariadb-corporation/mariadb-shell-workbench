#!/bin/bash
# Builds the desktop app (electron/) and starts it from the tree, without packaging it:
#
#   scripts/start-standalone.sh   (npm run start:standalone)
#
# The extensions come from plugins/ as they are unpacked there (download:plugins, plugin:mariadb,
# plugin:mariadb-shell-agent). For the .dmg/.zip/AppImage, use build-standalone.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d plugins/vscode.git ] || npm run download:plugins

cd electron
# Install when the lock file changed since the last install (or there is none yet); a fresh install
# brings back the Node builds of the native modules, so they are rebuilt for Electron after it.
if [ ! -f package-lock.json ] || [ ! -f node_modules/.package-lock.json ] \
  || [ package-lock.json -nt node_modules/.package-lock.json ]; then
  if [ -f package-lock.json ]; then npm ci; else npm install; fi
  rm -rf .browser_modules
fi
npm run icons
npx theia build --mode production
[ -d .browser_modules ] || npx theia rebuild:electron
# Started from inside VS Code, the environment can carry ELECTRON_RUN_AS_NODE=1 from its extension
# host, which makes Electron a plain Node.js (no app, no window).
unset ELECTRON_RUN_AS_NODE
npx electron .
