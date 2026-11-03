#!/bin/bash
# Dev run on 127.0.0.1:3000 (log: theia.log). Stops a running instance first.
# Start it detached over ssh: ssh <pi> "setsid ~/git/mariadb-shell-workbench/scripts/run-dev.sh </dev/null >/dev/null 2>&1"
cd "$(dirname "$0")/.."
pkill -f "[l]ib/backend/main.js" && sleep 3
. ~/.profile
scripts/install-ai-plugins.sh || true
nohup npx theia start ~/ide-workspace --hostname 127.0.0.1 --port 3000 --plugins=local-dir:plugins > theia.log 2>&1 &
