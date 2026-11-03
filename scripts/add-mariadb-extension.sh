#!/bin/bash
# Unpacks the MariaDB VS Code extension into plugins/, the way "theia download:plugins"
# unpacks the Open VSX ones.
#
#   scripts/add-mariadb-extension.sh [path/to/extension.vsix]
#
# Without an argument it takes the newest .vsix in ../vscode-extension
# (build one there with: npm run package).
set -euo pipefail
cd "$(dirname "$0")/.."

VSIX=${1:-$(ls -t ../vscode-extension/*.vsix 2>/dev/null | head -1)}
[ -n "$VSIX" ] && [ -f "$VSIX" ] || { echo "no .vsix found; pass its path or run 'npm run package' in ../vscode-extension" >&2; exit 1; }

# Folder named <publisher>.<name> like the Open VSX plugins; earlier MariaDB builds are removed
# so that only one copy of the extension is deployed (the extension was renamed once already).
# MariaDB Shell Agent (scripts/add-mariadb-shell-agent-extension.sh) is a separate extension and stays.
ID=$(unzip -p "$VSIX" extension/package.json | node -e "const p=JSON.parse(require('fs').readFileSync(0)); console.log((p.publisher+'.'+p.name).toLowerCase())")
for d in plugins/mariadb.*; do
  [ "$d" = plugins/mariadb.mariadb-shell-agent ] || rm -rf "$d"
done
DEST=plugins/$ID
mkdir -p "$DEST"
unzip -q "$VSIX" -d "$DEST"
echo "unpacked $(basename "$VSIX") into $DEST ($(node -p "require('./$DEST/extension/package.json').version"))"
