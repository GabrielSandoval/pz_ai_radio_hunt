#!/bin/bash
# Builds the companion binaries and packages the per-platform Release zips
# exactly as uploaded to GitHub Releases - the single source of truth for
# what's actually shipped to players, so it can't silently drift out of
# sync with what companion/index.js reads from disk at runtime (config.json,
# lore_context.txt, locations_context.txt - all loaded from baseDir, not
# bundled into the pkg snapshot, so they must be copied in here explicitly).
#
# Usage:
#   ./scripts/package-release.sh            # build + package only
#   ./scripts/package-release.sh --upload    # also upload to the v0.1.0 release (gh must be authenticated)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPANION_DIR="$REPO_ROOT/companion"
OUT_DIR="$REPO_ROOT/dist-release"

echo "== Building companion binaries =="
(cd "$COMPANION_DIR" && rm -rf dist && npm run build)
chmod +x "$COMPANION_DIR/dist/ai-radio-hunt-companion-macos-arm64" "$COMPANION_DIR/dist/ai-radio-hunt-companion-macos-x64"

echo "== Packaging per-platform zips =="
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/windows/dist" "$OUT_DIR/macos/dist"

# Everything below this line must match what companion/index.js actually
# reads from `baseDir` at runtime - check loadConfig/loadLoreContext/
# loadLocationsContext in index.js before removing anything from this list.
SHARED_FILES=(config.json lore_context.txt locations_context.txt)

cp "$COMPANION_DIR/dist/ai-radio-hunt-companion-win-x64.exe" "$OUT_DIR/windows/dist/"
cp "$COMPANION_DIR/Start AIRadioHunt.bat" "$OUT_DIR/windows/"
for f in "${SHARED_FILES[@]}"; do cp "$COMPANION_DIR/$f" "$OUT_DIR/windows/"; done

cp "$COMPANION_DIR/dist/ai-radio-hunt-companion-macos-arm64" "$COMPANION_DIR/dist/ai-radio-hunt-companion-macos-x64" "$OUT_DIR/macos/dist/"
cp "$COMPANION_DIR/Start AIRadioHunt.command" "$OUT_DIR/macos/"
for f in "${SHARED_FILES[@]}"; do cp "$COMPANION_DIR/$f" "$OUT_DIR/macos/"; done
chmod +x "$OUT_DIR/macos/dist/ai-radio-hunt-companion-macos-arm64" "$OUT_DIR/macos/dist/ai-radio-hunt-companion-macos-x64" "$OUT_DIR/macos/Start AIRadioHunt.command"

(cd "$OUT_DIR/windows" && zip -qr "$OUT_DIR/AIRadioHunt-Companion-Windows.zip" .)
(cd "$OUT_DIR/macos" && zip -qr "$OUT_DIR/AIRadioHunt-Companion-macOS.zip" .)

echo "== Contents =="
unzip -l "$OUT_DIR/AIRadioHunt-Companion-Windows.zip"
unzip -l "$OUT_DIR/AIRadioHunt-Companion-macOS.zip"

if [[ "${1:-}" == "--upload" ]]; then
    echo "== Uploading to v0.1.0 release =="
    gh release upload v0.1.0 \
        "$OUT_DIR/AIRadioHunt-Companion-Windows.zip" \
        "$OUT_DIR/AIRadioHunt-Companion-macOS.zip" \
        -R GabrielSandoval/pz_ai_radio_hunt \
        --clobber
    echo "Uploaded."
else
    echo "Zips ready at $OUT_DIR - re-run with --upload to publish them to the v0.1.0 release."
fi
