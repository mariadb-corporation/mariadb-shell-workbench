#!/bin/sh
# Copyright (c) 2026, MariaDB plc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1335 USA

#
# MariaDB Shell Workbench installer for macOS.
#
#   curl -fsSL https://github.com/mariadb-corporation/mariadb-shell-workbench/raw/main/install.sh | MARIADB_SHELL_WORKBENCH_TAG=v26.11.0 bash
#
# Picks the package for this Mac's CPU (Apple silicon or Intel) from the release, verifies it
# against the release's SHA256SUMS, unpacks it into /Applications (or ~/Applications when
# /Applications is not writable), and clears its extended attributes. The app is not signed yet;
# without the last step macOS would refuse to open it ("damaged" or "cannot be verified").
#
# POSIX sh on purpose, as MariaDB Shell's install.sh: no arrays, no [[ ]], no local.
#
# Environment overrides:
#   MARIADB_SHELL_WORKBENCH_TAG     install a specific release tag instead of the newest
#   MARIADB_SHELL_WORKBENCH_APPDIR  where the app goes (default /Applications, else ~/Applications)
#   MARIADB_SHELL_WORKBENCH_REPO    owner/repo to install from; it has to be public
#
# Options:
#   --pre-release  install the newest release even if it is a prerelease
#
set -eu

REPO="${MARIADB_SHELL_WORKBENCH_REPO:-mariadb-corporation/mariadb-shell-workbench}"
APP_NAME="MariaDB Shell Workbench.app"

die() { printf 'install.sh: %s\n' "$*" >&2; exit 1; }
info() { echo "==> $*"; }
need() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

ENABLE_PRERELEASE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --pre-release) ENABLE_PRERELEASE=1 ;;
    -h|--help)
      cat <<'USAGE'
MariaDB Shell Workbench installer for macOS.

  install.sh [--pre-release]
  curl -fsSL <url> | bash -s -- [--pre-release]

  --pre-release  install the newest release even if it is a prerelease.
                 Without it, prereleases are skipped, exactly as
                 /releases/latest/ skips them.

Environment: MARIADB_SHELL_WORKBENCH_TAG, MARIADB_SHELL_WORKBENCH_APPDIR,
MARIADB_SHELL_WORKBENCH_REPO. A pinned tag wins over --pre-release.
USAGE
      exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ "$(uname -s)" = Darwin ] ||
  die "this installer is for macOS; for Linux and Windows download the package from https://github.com/$REPO/releases"

case "$(uname -m)" in
  arm64)  ARCH=arm64 ;;
  x86_64) ARCH=x64 ;;
  *) die "unsupported CPU architecture: $(uname -m)" ;;
esac
# Under Rosetta, uname -m says x86_64 on Apple silicon; the native package is the one to take.
[ "$ARCH" = x64 ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" = 1 ] && ARCH=arm64

need curl
need shasum
need ditto
need xattr

# ---------------------------------------------------------------------------
# The release. A pinned tag and the newest stable release are plain download
# URLs; the newest prerelease is invisible to /releases/latest, so it is looked
# up through the API (the listing is newest first; drafts are not listed).
# ---------------------------------------------------------------------------
if [ -n "${MARIADB_SHELL_WORKBENCH_TAG:-}" ]; then
  TAG="$MARIADB_SHELL_WORKBENCH_TAG"
elif [ "$ENABLE_PRERELEASE" = 1 ]; then
  TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=1" |
    sed -n 's/^ *"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
  [ -n "$TAG" ] || die "could not find a release of $REPO"
else
  # /releases/latest redirects to the newest stable release's page; its last path part is the tag.
  TAG=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" | sed 's|.*/||')
  case "$TAG" in
    v*) ;;
    *) die "$REPO has no stable release yet. Every release so far is a prerelease: install the
  newest one with --pre-release, or name one outright:

      export MARIADB_SHELL_WORKBENCH_TAG=<tag>" ;;
  esac
fi
VERSION=${TAG#v}
BASE="https://github.com/$REPO/releases/download/$TAG"
ZIP="mariadb-shell-workbench-$VERSION-mac-$ARCH.zip"
info "Installing MariaDB Shell Workbench $VERSION ($ARCH)"

# ---------------------------------------------------------------------------
# Where the app goes.
# ---------------------------------------------------------------------------
if [ -n "${MARIADB_SHELL_WORKBENCH_APPDIR:-}" ]; then
  APPDIR="$MARIADB_SHELL_WORKBENCH_APPDIR"
elif [ -w /Applications ]; then
  APPDIR=/Applications
else
  APPDIR="$HOME/Applications"
fi
mkdir -p "$APPDIR" || die "could not create $APPDIR"
TARGET="$APPDIR/$APP_NAME"

# Replacing the bundle under a running app breaks it; ask to quit it first.
if pgrep -f "$TARGET/Contents/MacOS/" >/dev/null 2>&1; then
  die "MariaDB Shell Workbench is running from $TARGET; quit it and run this again"
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------------------
# Download and verify.
# ---------------------------------------------------------------------------
curl -fsSL -o "$TMP/SHA256SUMS" "$BASE/SHA256SUMS" ||
  die "could not download SHA256SUMS of release $TAG of $REPO (is the tag right?)"
EXPECTED=$(awk -v f="$ZIP" '$2 == f || $2 == "*" f {print $1}' "$TMP/SHA256SUMS")
[ -n "$EXPECTED" ] || die "release $TAG has no $ZIP"
info "Downloading $ZIP"
curl -fL --progress-bar -o "$TMP/$ZIP" "$BASE/$ZIP" || die "could not download $BASE/$ZIP"
ACTUAL=$(shasum -a 256 "$TMP/$ZIP" | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || die "checksum mismatch for $ZIP (expected $EXPECTED, got $ACTUAL)"
info "Checksum OK"

# ---------------------------------------------------------------------------
# Unpack and install. ditto keeps the bundle's symlinks and permissions, which the
# frameworks inside it rely on. The new copy is unpacked next to the target and
# swapped in, so a failure leaves the installed app as it was.
# ---------------------------------------------------------------------------
ditto -x -k "$TMP/$ZIP" "$TMP/unpacked" || die "could not unpack $ZIP"
[ -d "$TMP/unpacked/$APP_NAME" ] || die "$ZIP does not contain $APP_NAME"
# Unsigned: clear the quarantine flag and every other attribute, or Gatekeeper refuses it.
xattr -cr "$TMP/unpacked/$APP_NAME"

STAGE="$APPDIR/.$APP_NAME.installing.$$"
rm -rf "$STAGE"
ditto "$TMP/unpacked/$APP_NAME" "$STAGE" || { rm -rf "$STAGE"; die "could not copy the app into $APPDIR"; }
if [ -e "$TARGET" ]; then
  OLD="$APPDIR/.$APP_NAME.old.$$"
  mv "$TARGET" "$OLD" || { rm -rf "$STAGE"; die "could not move the installed app aside"; }
  mv "$STAGE" "$TARGET" || { mv "$OLD" "$TARGET"; die "could not install into $TARGET"; }
  rm -rf "$OLD"
else
  mv "$STAGE" "$TARGET" || { rm -rf "$STAGE"; die "could not install into $TARGET"; }
fi
# The copy may have picked attributes up again (a quarantined parent folder); clear them once more.
xattr -cr "$TARGET"

info "Installed $TARGET"
echo
echo "Open it from $APPDIR, or with:"
echo
echo "    open \"$TARGET\""
