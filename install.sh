#!/usr/bin/env bash
set -euo pipefail

# Downloads a signed-release-compatible archive from GitHub Releases. Set
# YEEAP_RELEASE_REPO before publishing if the public GitHub repository differs.
REPO="${YEEAP_RELEASE_REPO:-Yeepay-Open-Platform/yeeap-wallet}"
VERSION="${1:-latest}"
INSTALL_DIR="${YEEAP_INSTALL_DIR:-$HOME/.yeeap/bin}"

case "$(uname -s)" in
  Darwin) OS=darwin ;;
  Linux) OS=linux ;;
  *) echo "Unsupported operating system: $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64) ARCH=amd64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$VERSION" = latest ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -n "$VERSION" ] || { echo "Unable to resolve the latest release." >&2; exit 1; }
VERSION="${VERSION#v}"
ARCHIVE="yeeap-cli_${VERSION}_${OS}_${ARCH}.tar.gz"
BASE="https://github.com/$REPO/releases/download/v$VERSION"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$BASE/$ARCHIVE" -o "$TMP/$ARCHIVE"
curl -fsSL "$BASE/checksums.txt" -o "$TMP/checksums.txt"
if command -v shasum >/dev/null 2>&1; then
  (cd "$TMP" && grep "  $ARCHIVE$" checksums.txt | shasum -a 256 -c -)
else
  (cd "$TMP" && grep "  $ARCHIVE$" checksums.txt | sha256sum -c -)
fi
mkdir -p "$INSTALL_DIR"
tar -xzf "$TMP/$ARCHIVE" -C "$TMP"
install -m 0755 "$TMP/yeeap-cli" "$INSTALL_DIR/yeeap-cli"
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
ln -sf "$INSTALL_DIR/yeeap-cli" "$LOCAL_BIN/yeeap-cli"
echo "yeeap-cli $VERSION installed at $INSTALL_DIR/yeeap-cli"
case ":$PATH:" in *":$INSTALL_DIR:"*|*":$LOCAL_BIN:"*) ;; *) echo "Add $LOCAL_BIN to PATH before using yeeap-cli." ;; esac
