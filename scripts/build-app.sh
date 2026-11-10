#!/bin/bash
# Builds dist/Charms.app from the SwiftPM package: copies Info.plist and the
# generated character catalogue into the bundle, generates the icon from the
# committed master, signs the app and verifies the signature.
#
#   scripts/build-app.sh [--debug] [--universal]
#
# --debug builds the Debug configuration (scripts/build.sh --debug reaches this
# through lkm-build's swiftpm kind). --universal builds a fat arm64+x86_64
# binary; the default is the host architecture, which is faster for local runs.
# CHARMS_BUILD_DIR and/or CHARMS_OUTPUT_DIR override the build and output
# directories.
#
# Set CODE_SIGN_IDENTITY to a stable identity ("Apple Development") for local
# use: macOS ties the Accessibility grant to the signature, and an ad-hoc
# signature is different in every build, so the grant would be lost each time.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${CHARMS_BUILD_DIR:-$PROJECT_ROOT/.build}"
OUTPUT_DIR="${CHARMS_OUTPUT_DIR:-$PROJECT_ROOT/dist}"
APP_PATH="$OUTPUT_DIR/Charms.app"

CONFIGURATION=release
ARCH_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIGURATION=debug ;;
    --universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
    *) echo "error: unknown option '$arg' (expected --debug or --universal)" >&2; exit 2 ;;
  esac
done

CATALOG="$PROJECT_ROOT/Resources/catalog.txt"
[[ -s "$CATALOG" ]] || { echo "error: $CATALOG is missing; run 'swift run CharmsCatalogTool generate'" >&2; exit 1; }

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/module-cache"

cd "$PROJECT_ROOT"
SWIFT_ARGS=(--product Charms --configuration "$CONFIGURATION" --scratch-path "$BUILD_DIR" --cache-path "$BUILD_DIR/package-cache" --disable-sandbox ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"})
swift build "${SWIFT_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

# Start from an empty bundle so a file removed from the build never lingers.
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/Charms" "$APP_PATH/Contents/MacOS/Charms"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$CATALOG" "$APP_PATH/Contents/Resources/catalog.txt"
cp "$PROJECT_ROOT/THIRD_PARTY_NOTICES.md" "$APP_PATH/Contents/Resources/THIRD_PARTY_NOTICES.md"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

# Regenerate the iconset from the committed master so the shipped icon always
# matches assets/Charms-icon.png, which media-sources/icon.swift makes from the
# artwork in media-sources/icon.png.
swift "$PROJECT_ROOT/scripts/make-icon.swift" "$PROJECT_ROOT/assets/Charms-icon.png" "$BUILD_DIR/Charms.iconset"
/usr/bin/iconutil -c icns "$BUILD_DIR/Charms.iconset" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --sign "$CODE_SIGN_IDENTITY" "$APP_PATH"
else
    codesign --force --sign - "$APP_PATH"
fi
codesign --verify --strict --verbose=2 "$APP_PATH"
printf '\nBuilt %s\n' "$APP_PATH"
