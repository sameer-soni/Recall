#!/bin/bash
#
# Recall installer — https://github.com/sameer-soni/Recall
#
# Downloads the latest Recall release, installs it to /Applications, and opens it.
# Because this file is fetched with curl (not a browser), macOS never applies the
# com.apple.quarantine flag — so there's no Gatekeeper warning to dismiss.
#
# Run it with:
#   curl -fsSL https://github.com/sameer-soni/Recall/releases/latest/download/install.sh | bash
#
set -euo pipefail

REPO="sameer-soni/Recall"
APP="Recall.app"
ZIP_URL="https://github.com/${REPO}/releases/latest/download/Recall.zip"
DEST="/Applications"

echo "→ Downloading Recall…"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$ZIP_URL" -o "$TMP/Recall.zip"

echo "→ Unpacking…"
/usr/bin/ditto -x -k "$TMP/Recall.zip" "$TMP"

if [ ! -d "$TMP/$APP" ]; then
  echo "✗ Couldn't find $APP inside the download. Aborting." >&2
  exit 1
fi

echo "→ Installing to $DEST…"
# Replace any existing copy.
rm -rf "${DEST:?}/$APP"
if ! mv "$TMP/$APP" "$DEST/" 2>/dev/null; then
  # /Applications may need elevated permissions on some setups.
  echo "  (needs permission to write to $DEST)"
  sudo mv "$TMP/$APP" "$DEST/"
fi

# Belt-and-suspenders: clear any quarantine attribute if one exists.
xattr -cr "$DEST/$APP" 2>/dev/null || true

echo "→ Launching Recall…"
open "$DEST/$APP"

echo ""
echo "✓ Recall is installed. Press ⌘⇧V anywhere to open it."
echo "  Tip: right-click the menu-bar icon to enable Launch at Login."
