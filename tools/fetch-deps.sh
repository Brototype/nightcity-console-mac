#!/bin/bash
# Populate deps/ without overwriting existing binaries or modifying a game install.
# Import a verified release ZIP explicitly, or fill gaps from a local Steam/GOG install.
# See docs/DEPENDENCIES.md for provenance and optional TweakXL limitations.
set -euo pipefail
cd "$(dirname "$0")/.."

ZIP=""
if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 2 ] || [ "$1" != "--from-zip" ]; then
    echo "Usage: $0 [--from-zip /path/to/NightCity-Console-for-Mac.zip]" >&2
    exit 1
  fi
  ZIP="$2"
fi

mkdir -p deps
REQUIRED=(RED4ext.dylib FridaGadget.dylib TweakXL.dylib)

copy_if_missing() {
  local src="$1" name="$2"
  if [ ! -f "deps/$name" ] && [ -f "$src" ]; then
    cp "$src" "deps/$name"
    echo "  got $name from $src"
  fi
}

echo "Collecting runtime deps into deps/ ..."
if [ -n "$ZIP" ]; then
  [ -f "$ZIP" ] || { echo "Release ZIP not found: $ZIP" >&2; exit 1; }
  # GitHub release asset digest for v1.5.0-beta.2, verified against our source ZIP.
  EXPECTED="19f83a8546819cf09091bb836e585940eaed23a87447009184249d5d2f031151"
  ACTUAL=$(shasum -a 256 "$ZIP" | awk '{print $1}')
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "ZIP checksum mismatch: expected the official v1.5.0-beta.2 release. See docs/DEPENDENCIES.md." >&2
    exit 1
  fi
  TEMP_FILE=""
  trap 'if [ -n "$TEMP_FILE" ]; then rm -f -- "$TEMP_FILE"; fi' EXIT
  for name in "${REQUIRED[@]}"; do
    if [ -f "deps/$name" ]; then
      echo "  keeping existing $name"
      continue
    fi
    entry="NightCity Console.app/Contents/Resources/$name"
    if [ "$name" = "TweakXL.dylib" ]; then
      entry="NightCity Console.app/Contents/Resources/plugins/TweakXL/$name"
    fi
    # Stream only the three named entries; do not unpack or execute the application.
    TEMP_FILE=$(mktemp "deps/.import.XXXXXX")
    unzip -p "$ZIP" "$entry" > "$TEMP_FILE"
    [ -s "$TEMP_FILE" ] || { echo "Empty dependency in ZIP: $entry" >&2; exit 1; }
    chmod 644 "$TEMP_FILE"
    mv "$TEMP_FILE" "deps/$name"
    TEMP_FILE=""
    echo "  imported $name from verified v1.5.0-beta.2 ZIP"
  done
else
  if [ -n "${CP2077_DIR:-}" ]; then
    GAME_DIRS=("$CP2077_DIR")
  else
    GAME_DIRS=("$HOME/Library/Application Support/Steam/steamapps/common/Cyberpunk 2077" "/Applications/Cyberpunk 2077")
  fi
  for game_dir in "${GAME_DIRS[@]}"; do
    copy_if_missing "$game_dir/red4ext/RED4ext.dylib" RED4ext.dylib
    copy_if_missing "$game_dir/red4ext/FridaGadget.dylib" FridaGadget.dylib
    copy_if_missing "$game_dir/red4ext/plugins/TweakXL/TweakXL.dylib" TweakXL.dylib
  done
fi

MISSING=0
for name in "${REQUIRED[@]}"; do
  if [ ! -s "deps/$name" ]; then
    echo "  MISSING or empty: deps/$name"
    MISSING=1
  fi
done
if [ "$MISSING" -ne 0 ]; then
  echo "Download the official v1.5.0-beta.2 NightCity-Console-for-Mac.zip, then run:"
  echo "  ./tools/fetch-deps.sh --from-zip /path/to/NightCity-Console-for-Mac.zip"
  echo "Source, checksums, and all three dependencies: docs/DEPENDENCIES.md"
  exit 1
fi
echo "deps ready (files present; optional TweakXL runtime compatibility is not checked)."
