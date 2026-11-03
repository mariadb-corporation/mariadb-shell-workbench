#!/bin/bash
# Installs MariaDB's dev plugin (dev@mariadb, https://github.com/mariadb/ai-plugins) into
# MariaDB Shell Agent for the user running the IDE (~/.mariadb-shell-agent/extensions/dev). Runs before every
# start (systemd ExecStartPre, npm prestart, run-dev.sh) and does nothing when the plugin is
# already installed from GitHub. An install from another source (a local checkout) is replaced.
#
# Installed from GitHub, the plugin records its commit, so later commits are picked up with:
#   node plugins/mariadb.mariadb-shell-agent/extension/dist/qwen-cli/cli.js extensions update dev
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE=https://github.com/mariadb/ai-plugins
CLI=plugins/mariadb.mariadb-shell-agent/extension/dist/qwen-cli/cli.js
[ -f "$CLI" ] || { echo "MariaDB Shell Agent is not in plugins/ (npm run plugin:mariadb-shell-agent); dev@mariadb not installed" >&2; exit 0; }

META=${QWEN_HOME:-$HOME/.mariadb-shell-agent}/extensions/dev/.qwen-extension-install.json
INSTALLED=$([ -f "$META" ] && node -p "require(process.argv[1]).source" "$META" || true)
[ "$INSTALLED" = "$SOURCE" ] && exit 0

[ -n "$INSTALLED" ] && node "$CLI" extensions uninstall dev
node "$CLI" extensions install "$SOURCE:dev" --consent
