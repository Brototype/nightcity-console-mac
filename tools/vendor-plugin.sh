#!/bin/bash
# Make a RED4ext plugin self-contained for distribution: copy it + its Homebrew dylib deps into destDir with
# @loader_path references, so it loads on a Mac WITHOUT Homebrew. Re-signs ad-hoc (Developer ID re-signs at
# notarize time). usage: vendor-plugin.sh <srcPlugin.dylib> <destPluginDir>
set -e
SRC="$1"; DEST="$2"; mkdir -p "$DEST"
PLUGIN="$DEST/$(basename "$SRC")"; cp "$SRC" "$PLUGIN"; chmod u+w "$PLUGIN"
LIBS=( "/opt/homebrew/opt/spdlog/lib/libspdlog.1.17.dylib"
       "/opt/homebrew/opt/fmt/lib/libfmt.12.dylib"
       "/opt/homebrew/opt/yaml-cpp/lib/libyaml-cpp.0.9.dylib" )
for L in "${LIBS[@]}"; do
  BN="$(basename "$L")"; cp "$L" "$DEST/$BN"; chmod u+w "$DEST/$BN"
  install_name_tool -id "@loader_path/$BN" "$DEST/$BN"
  install_name_tool -change "$L" "@loader_path/$BN" "$PLUGIN"
done
# spdlog internally references fmt -> point it at the sibling copy
install_name_tool -change "/opt/homebrew/opt/fmt/lib/libfmt.12.dylib" "@loader_path/libfmt.12.dylib" "$DEST/libspdlog.1.17.dylib"
for f in "$PLUGIN" "$DEST"/lib*.dylib; do codesign --force -s - "$f" 2>/dev/null || true; done
LEFT=$(otool -L "$PLUGIN" "$DEST"/lib*.dylib 2>/dev/null | grep -c /opt/homebrew || true)
echo "vendored $(basename "$SRC") -> $DEST ($(ls "$DEST"|wc -l|tr -d ' ') files) | remaining /opt/homebrew refs: $LEFT"
