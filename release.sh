#!/bin/bash
#
# Builds Recall, zips it, and publishes a GitHub Release with the zip + installer.
# One-time setup:  gh auth login    (choose GitHub.com > HTTPS > login with browser)
# Then run:        ./release.sh 1.0.0
#
set -euo pipefail

VERSION="${1:?usage: ./release.sh <version>   e.g. ./release.sh 1.0.0}"
REPO="sameer-soni/Recall"
SCHEME="clipboard"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
mkdir -p "$DIST"

echo "→ Building Release…"
xcodebuild -project "$ROOT/clipboard.xcodeproj" -scheme "$SCHEME" \
  -configuration Release -derivedDataPath "$BUILD" build >/dev/null

APP="$BUILD/Build/Products/Release/Recall.app"
[ -d "$APP" ] || { echo "✗ Recall.app not found after build"; exit 1; }

echo "→ Zipping…"
rm -f "$DIST/Recall.zip"
ditto -c -k --keepParent "$APP" "$DIST/Recall.zip"

echo "→ Creating GitHub release v$VERSION…"
gh release create "v$VERSION" "$DIST/Recall.zip" "$ROOT/install.sh" \
  --repo "$REPO" \
  --title "Recall $VERSION" \
  --notes "Fast, keyboard-first clipboard history for macOS.

**Install with one command:**
\`\`\`
curl -fsSL https://github.com/$REPO/releases/latest/download/install.sh | bash
\`\`\`

Or download \`Recall.zip\`, drag Recall.app into Applications, and right-click → Open on first launch.

- Press ⌘⇧V anywhere to open the panel
- macOS 13+, Apple Silicon & Intel"

echo "✓ Released. Assets live at:"
echo "  https://github.com/$REPO/releases/latest/download/Recall.zip"
echo "  https://github.com/$REPO/releases/latest/download/install.sh"
