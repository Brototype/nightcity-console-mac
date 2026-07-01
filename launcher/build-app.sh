#!/bin/bash
# Build "NightCity Console.app" (ad-hoc signed, for dev/testing).
# Bundles the runtime payload into Contents/Resources so the app can install it into the game.
# Release signing + notarization + .dmg is a separate step: tools/sign-notarize.sh
set -e
cd "$(dirname "$0")/.."   # repo root
APP="build/NightCity Console.app"

echo "==> overlay + deps"
./overlay/build.sh
./tools/fetch-deps.sh

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp launcher/Info.plist "$APP/Contents/Info.plist"

echo "==> compiling launcher"
swiftc -O -parse-as-library -target arm64-apple-macos12 \
  -o "$APP/Contents/MacOS/NightCityConsole" \
  launcher/Sources/*.swift

echo "==> bundling payload into Resources"
cp runtime/red4ext_hooks.js runtime/FridaGadget.config runtime/cet_catalog.tsv "$APP/Contents/Resources/"
cp deps/RED4ext.dylib deps/FridaGadget.dylib            "$APP/Contents/Resources/"
cp build/libcyberconsole_overlay.dylib                  "$APP/Contents/Resources/"
# CyberModMan creator payload (TweakXL plugin from deps/ + seed names file; launcher deploys these on install)
cp deps/TweakXL.dylib runtime/cybermodman/cybermodman_names.json "$APP/Contents/Resources/"

echo "==> bundling nctool mod engine (drag-drop installer)"
# nctool is the cp2077 archive/mod engine. Publish it self-contained (multi-file: the single-file variant
# tucks libkraken into a lib/ subfolder the runtime can't find) so the shipped app needs no dotnet; the
# launcher shells out to Resources/nctool/nctool. Set NCTOOL_SRC to override the location.
NCTOOL_SRC="${NCTOOL_SRC:-$HOME/cp2077/_tools/nctool}"
if [ -d "$NCTOOL_SRC" ]; then
  DOTNET="$(command -v dotnet || echo "$HOME/.dotnet/dotnet")"
  rm -rf build/nctool-pub
  "$DOTNET" publish "$NCTOOL_SRC" -c Release -r osx-arm64 --self-contained true \
    -p:PublishSingleFile=false -o build/nctool-pub >/dev/null
  rm -f build/nctool-pub/*.pdb
  # Bundle the whole self-contained publish (exe + .NET runtime + libkraken.dylib) into Resources/nctool/.
  rm -rf "$APP/Contents/Resources/nctool"
  ditto build/nctool-pub "$APP/Contents/Resources/nctool"
  echo "  bundled nctool self-contained ($(ls "$APP/Contents/Resources/nctool" | wc -l | tr -d ' ') files)"
else
  echo "  [warn] nctool source not found at $NCTOOL_SRC - the mod installer will show 'helper missing'."
  echo "         Set NCTOOL_SRC=/path/to/cp2077/_tools/nctool and rebuild to enable drag-drop mod install."
fi

if [ -f assets/icon.png ]; then
  echo "==> generating app icon (AppIcon.icns from assets/icon.png)"
  ICONSET="build/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s"             assets/icon.png --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    sips -z "$((s*2))" "$((s*2))" assets/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

echo "==> ad-hoc signing"
codesign -s - --deep --force "$APP" >/dev/null
echo "built $APP"
echo "Run it:  open \"$APP\"   (first launch may need right-click -> Open until notarized)"
