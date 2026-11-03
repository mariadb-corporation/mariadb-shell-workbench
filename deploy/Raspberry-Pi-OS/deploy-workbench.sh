#!/bin/bash
# Copies the working tree and the local MariaDB extensions to the Pi and runs this folder's
# setup-workbench.sh there: ../Debian/deploy-workbench.sh with SETUP=Raspberry-Pi-OS.
#
#   deploy/Raspberry-Pi-OS/deploy-workbench.sh <host> <user> [--no-build]
#
# Logs in as <user>@<host> (Raspberry Pi OS has no root login; its first user has password-less
# sudo); SSH_TARGET overrides that, e.g. SSH_TARGET=pi@raspberrypi.local when <host> is the public
# name the Pi is not reached by from here.
set -euo pipefail
HOST=${1:?usage: $0 <host> <user> [--no-build]}
USER_NAME=${2:?usage: $0 <host> <user> [--no-build]}
SSH_TARGET=${SSH_TARGET:-$USER_NAME@$HOST} SETUP=Raspberry-Pi-OS \
  exec "$(dirname "$0")/../Debian/deploy-workbench.sh" "$@"
