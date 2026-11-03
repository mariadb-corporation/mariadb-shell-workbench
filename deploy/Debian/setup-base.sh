#!/bin/bash
# Base system for the MariaDB Shell Workbench on Debian 13 / Ubuntu 24.04, and on Raspberry Pi OS
# (Debian 13 on arm64; deploy/Raspberry-Pi-OS). Run as root or with sudo. Idempotent: safe to run again.
#
#   scp deploy/Debian/setup-base.sh root@<host>: && ssh root@<host> ./setup-base.sh
set -euo pipefail

NODE_VERSION=${NODE_VERSION:-v24.22.1}
MARIADB_SHELL_TAG=${MARIADB_SHELL_TAG:-v26.10.4}
SWAP_SIZE=${SWAP_SIZE:-4G}
export DEBIAN_FRONTEND=noninteractive

# A Theia production build needs about 4 GB of heap; small servers (4 GB RAM) need swap.
if ! swapon --show | grep -q /swapfile; then
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# SSH with keys only: Workbench accounts have no password, and the server is scanned all day.
# 00- sorts first, and sshd keeps the first value it reads (cloud-init's drop-in may say yes).
# Only where the account running this logs in with a key already (a Raspberry Pi set up with a
# password would lock its user out otherwise); SSH_KEYS_ONLY=no leaves sshd alone.
ADMIN_HOME=$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)
if [ "${SSH_KEYS_ONLY:-yes}" = yes ] && [ ! -f /etc/ssh/sshd_config.d/00-workbench.conf ] &&
  [ -s "$ADMIN_HOME/.ssh/authorized_keys" ]; then
  printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\n' \
    > /etc/ssh/sshd_config.d/00-workbench.conf
  sshd -t && systemctl reload ssh
fi

apt-get update -qq
# nginx/certbot: TLS and routing; podman: Keycloak and oauth2-proxy; mariadb-server: a local
# server to connect to; ripgrep: search in Theia and MariaDB Shell Agent; the -dev packages and
# build-essential: Theia's native modules (native-keymap, keytar, node-pty).
apt-get install -qqy --no-install-recommends \
  ca-certificates curl git unzip rsync jq xz-utils \
  nginx certbot python3-certbot-nginx \
  podman \
  mariadb-server \
  ripgrep \
  build-essential python3 pkg-config libx11-dev libxkbfile-dev libsecret-1-dev

# Node.js for all users, from nodejs.org (the distributions ship older versions).
if [ "$(node --version 2>/dev/null)" != "$NODE_VERSION" ]; then
  case $(uname -m) in aarch64) ARCH=arm64 ;; x86_64) ARCH=x64 ;; *) echo "unsupported arch" >&2; exit 1 ;; esac
  TARBALL=node-$NODE_VERSION-linux-$ARCH.tar.xz
  TMP=$(mktemp -d)
  curl -fsSL -o "$TMP/$TARBALL" "https://nodejs.org/dist/$NODE_VERSION/$TARBALL"
  curl -fsSL -o "$TMP/SHASUMS256.txt" "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt"
  (cd "$TMP" && grep " $TARBALL\$" SHASUMS256.txt | sha256sum -c --quiet)
  # --no-same-owner: the tarball's files belong to 1001:1001 (nodejs.org's build user), which
  # root's tar would keep, giving node to whichever account gets that ID.
  tar -xJf "$TMP/$TARBALL" -C /usr/local --strip-components=1 --no-same-owner \
    --exclude CHANGELOG.md --exclude README.md --exclude LICENSE
  rm -rf "$TMP"
fi

# MariaDB Shell for all users, checked against the release's SHA256SUMS. Without it on the PATH
# the MariaDB Shell extension installs its own minimum version into every user's home. The
# releases are prereleases, so there is no "latest" download URL: the tag is pinned.
MSH_VERSION=${MARIADB_SHELL_TAG#v}
if [ "$(mariadb-shell --version 2>/dev/null | awk '{print $3}')" != "$MSH_VERSION" ]; then
  case $(uname -m) in aarch64) MSH_ARCH=arm-64bit ;; x86_64) MSH_ARCH=x86-64bit ;; esac
  MSH_NAME=mariadb-shell-$MSH_VERSION-linux-glibc2.34-$MSH_ARCH
  MSH_URL=https://github.com/mariadb-corporation/mariadb-shell/releases/download/$MARIADB_SHELL_TAG
  TMP=$(mktemp -d)
  curl -fsSL -o "$TMP/$MSH_NAME.tar.gz" "$MSH_URL/$MSH_NAME.tar.gz"
  curl -fsSL -o "$TMP/SHA256SUMS" "$MSH_URL/SHA256SUMS"
  (cd "$TMP" && grep " $MSH_NAME.tar.gz\$" SHA256SUMS | sha256sum -c --quiet)
  install -d /opt/mariadb-shell
  rm -rf "/opt/mariadb-shell/$MSH_VERSION"
  tar -xzf "$TMP/$MSH_NAME.tar.gz" -C "$TMP"
  mv "$TMP/$MSH_NAME" "/opt/mariadb-shell/$MSH_VERSION"
  for bin in mariadb-shell msh mariadb-lsp; do
    ln -sfn "/opt/mariadb-shell/$MSH_VERSION/bin/$bin" "/usr/local/bin/$bin"
  done
  rm -rf "$TMP"
fi

echo "node $(node --version), npm $(npm --version), $(nginx -v 2>&1), $(podman --version), $(mariadb --version | cut -d, -f1)"
mariadb-shell --version
swapon --show
