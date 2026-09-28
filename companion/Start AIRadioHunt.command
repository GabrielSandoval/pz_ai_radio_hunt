#!/bin/bash
cd "$(dirname "$0")"

if [ "$(uname -m)" = "arm64" ]; then
  BIN="dist/ai-radio-hunt-companion-macos-arm64"
else
  BIN="dist/ai-radio-hunt-companion-macos-x64"
fi

if [ ! -f "$BIN" ]; then
  echo "Could not find $BIN"
  echo "Make sure this file stays next to the dist/ folder it came with."
  echo
  read -n 1 -s -r -p "Press any key to close this window..."
  exit 1
fi

chmod +x "$BIN" 2>/dev/null

echo "Starting AI Radio Hunt companion..."
echo "Leave this window open while you play. Close the window to stop it."
echo

"$BIN"

echo
read -n 1 -s -r -p "Companion stopped. Press any key to close this window..."
