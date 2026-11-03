#!/bin/bash
# Unpacks the MariaDB Shell Agent VS Code extension into plugins/, the way "theia download:plugins"
# unpacks the Open VSX ones.
#
#   scripts/add-mariadb-shell-agent-extension.sh [path/to/extension.vsix]
#
# Without an argument it takes the newest universal .vsix in the fork's mariadb/dist, checked out as
# ../mariadb-shell-agent (build one there with: mariadb/build-vsix.sh universal). The universal build
# runs on the Pi (linux arm64); the platform builds carry a macOS or x64 node-pty.
set -euo pipefail
cd "$(dirname "$0")/.."

VSIX=${1:-$(ls -t ../mariadb-shell-agent/mariadb/dist/mariadb-shell-agent-*-universal.vsix 2>/dev/null | head -1 || true)}
[ -n "$VSIX" ] && [ -f "$VSIX" ] || { echo "no .vsix found; pass its path or run 'mariadb/build-vsix.sh universal' in ../mariadb-shell-agent" >&2; exit 1; }

ID=$(unzip -p "$VSIX" extension/package.json | node -e "const p=JSON.parse(require('fs').readFileSync(0)); console.log((p.publisher+'.'+p.name).toLowerCase())")
DEST=plugins/$ID
# The extension was called MariaDB Code (mariadb.mariadb-code) before; only one of them is deployed.
rm -rf "$DEST" plugins/mariadb.mariadb-code
mkdir -p "$DEST"
unzip -q "$VSIX" -d "$DEST"
# In the IDE the MariaDB Shell Agent view lives in the secondary side bar (right), above the Outline view
# (rank from the plugin-ext patch); local VS Code keeps it in the activity bar.
node -e '
const fs = require("fs");
const file = process.argv[1];
const p = JSON.parse(fs.readFileSync(file, "utf8"));
const c = p.contributes.viewsContainers;
c.secondarySidebar = [...(c.secondarySidebar ?? []), ...c.activitybar];
delete c.activitybar;
fs.writeFileSync(file, JSON.stringify(p, null, 2));
' "$DEST/extension/package.json"
echo "unpacked $(basename "$VSIX") into $DEST ($(node -p "require('./$DEST/extension/package.json').version"))"
