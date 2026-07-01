#!/bin/bash
# Sign (Developer ID + hardened runtime), notarize, and package "NightCity Console.app" into a .dmg and a .zip.
# YOU run this with YOUR Apple Developer ID - it never asks the assistant for credentials.
#
# One-time setup (stores your notary credentials in the keychain):
#   xcrun notarytool store-credentials cyberconsole-notary \
#     --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
#
# Then run:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="cyberconsole-notary" \
#   ./tools/sign-notarize.sh
set -e
cd "$(dirname "$0")/.."
APP="build/NightCity Console.app"
DMG="dist/NightCity-Console-for-Mac.dmg"
ZIP="dist/NightCity-Console-for-Mac.zip"          # distributable zip (made from the stapled app)
SUBZIP="dist/_notarize.zip"     # temporary zip used only for the notarization upload

: "${SIGN_IDENTITY:?set SIGN_IDENTITY to 'Developer ID Application: NAME (TEAMID)'}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to your notarytool keychain profile name}"

echo "==> building app (ad-hoc), then re-signing with Developer ID"
./launcher/build-app.sh

# The bundled nctool is a self-contained .NET helper that JITs. Under hardened runtime CoreCLR SIGKILLs the
# instant it writes executable memory unless these entitlements are present (validated locally: JIT + a full
# Kraken rawrepack run clean with them). Entitlements apply to the apphost EXECUTABLE, not the dylibs.
NCTOOL_ENTS="$(mktemp -t nctool-ents)"
cat > "$NCTOOL_ENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict></plist>
PLIST
NCTOOL_EXE="$APP/Contents/Resources/nctool/nctool"

# Sign every nested Mach-O inside-out with hardened runtime + secure timestamp (required for notarization).
# This is ALL Mach-O, not just *.dylib: the nctool bundle also ships helper executables (createdump) and the
# .NET runtime dylibs. The nctool apphost is skipped here and signed next, with the JIT entitlements.
find "$APP/Contents/Resources" -type f | while IFS= read -r f; do
  [ "$f" = "$NCTOOL_EXE" ] && continue
  if file "$f" | grep -q "Mach-O"; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$f"
  fi
done
codesign --force --options runtime --timestamp --entitlements "$NCTOOL_ENTS" --sign "$SIGN_IDENTITY" "$NCTOOL_EXE"
rm -f "$NCTOOL_ENTS"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> notarizing the app"
mkdir -p dist
rm -f "$SUBZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$SUBZIP"
xcrun notarytool submit "$SUBZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"          # staple the ticket onto the app on disk
rm -f "$SUBZIP"

echo "==> packaging the stapled app (.zip + .dmg)"
# 1) distributable .zip: the app inside is stapled, so it passes Gatekeeper offline
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
# 2) .dmg with an /Applications shortcut + drag-here layout, then notarize + staple
#    the dmg itself so the downloaded image also passes Gatekeeper offline.
rm -f "$DMG"
VOL="NightCity Console"; STAGE="build/dmg"; APPNAME="$(basename "$APP")"
# Pre-clean any stale mounts left by an interrupted prior run (they pile up as "NightCity Console 1/2/..."
# and make the old hdiutil convert fail with "Resource temporarily unavailable").
for v in /Volumes/"$VOL"*; do [ -d "$v" ] && hdiutil detach "$v" -force >/dev/null 2>&1 || true; done
rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APPNAME"
ln -s /Applications "$STAGE/Applications"            # the drag-here shortcut
# Create the compressed .dmg DIRECTLY from the staging folder - no attach/Finder-style/convert dance (that was
# flaky on macOS 27's deprecated hdiutil and accumulated stale /Volumes mounts). Reliable; the Applications
# shortcut conveys "drag the app here" (the fancy icon layout is dropped for a build that always succeeds).
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "done (signed, notarized, stapled - no Gatekeeper warnings):"
echo "  $DMG"
echo "  $ZIP"
