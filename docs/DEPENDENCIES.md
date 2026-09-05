# Runtime dependencies

This GOG branch builds with three prebuilt libraries in `deps/`: `RED4ext.dylib`,
`FridaGadget.dylib`, and `TweakXL.dylib`. They are ignored by Git and are not downloaded
automatically by `fetch-deps.sh`. Passing the dependency check means the three files are
present and nonempty; it does not prove that every optional plugin can load.

## First build from a clean checkout

Download **NightCity-Console-for-Mac.zip** from the official
[v1.5.0-beta.2 release](https://github.com/ysrdevs/nightcity-console-mac/releases/tag/v1.5.0-beta.2).
This is the archive used for the tested GOG macOS v2.3.1 console and reset commands.
Then run:

```bash
./tools/fetch-deps.sh --from-zip "$HOME/Downloads/NightCity-Console-for-Mac.zip"
./launcher/build-app.sh
```

The importer verifies the entire ZIP against the release asset SHA-256 before importing
the three named entries. It does not execute the downloaded app or install anything into
the game. Existing files in `deps/` are preserved; use a fresh checkout to reproduce the
exact dependency set. The ZIP option is intentionally pinned to this release and rejects
other archives.

Without `--from-zip`, the script fills missing files from `CP2077_DIR` if set; otherwise
it checks the default Steam and GOG installations. This only works if NightCity Console
is already installed there. For example:

```bash
CP2077_DIR="/Applications/Cyberpunk 2077" ./tools/fetch-deps.sh
```

## Verified provenance

Archive SHA-256 (matches the official GitHub release asset digest):

```text
19f83a8546819cf09091bb836e585940eaed23a87447009184249d5d2f031151
```

Paths below are relative to `NightCity Console.app/Contents/Resources/` inside the ZIP:

| Dependency | Archive path | SHA-256 of extracted file |
|---|---|---|
| RED4ext | `RED4ext.dylib` | `ae94730a81d7b9ece32579dec5922198f6b0b9064396b6aaf52037d2753f09da` |
| Frida Gadget | `FridaGadget.dylib` | `b179993600ef63a41c483ca4067567b40da7785480c55ae66eac095dcdcedf8f` |
| TweakXL | `plugins/TweakXL/TweakXL.dylib` | `8599e7de0cea311ac697e3b866044f10ca411f590b6fa6052a80393f9e41b9ee` |

RED4ext and TweakXL are arm64 binaries; the Frida Gadget is a universal binary that
includes arm64. Replacing these with arbitrary current releases is not covered by the
GOG testing reported here.

## Optional TweakXL limitations

The GOG branch's launcher bundles TweakXL for Creator features, so the build script
requires it even though the core inventory and character-reset commands do not use it.
The TweakXL binary from this ZIP targets **macOS 27** and links three sibling libraries:

- `libspdlog.1.17.dylib`
- `libfmt.12.dylib`
- `libyaml-cpp.0.9.dylib`

Those sibling files exist in the release ZIP, but this branch's existing packaging only
copies `TweakXL.dylib`. On the tested macOS 26.6.2 machine, TweakXL failed to load; the
GOG console, money/item grants, and reset commands still worked. The ZIP importer
reproduces that dependency set, not a fully working Creator installation. Supporting
those optional features requires a compatible TweakXL build and its complete dependency
set; this contribution does not claim to fix that separate issue.
