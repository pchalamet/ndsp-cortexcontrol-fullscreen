#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="${1:-/Applications/Neural DSP/Cortex Control.app}"
TARGET_APP="${2:-/Applications/Neural DSP/Cortex Control Patched.app}"
VENV="$SCRIPT_DIR/.venv"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cortex-fullscreen.XXXXXX")"

cleanup()
{
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Source application not found: $SOURCE_APP" >&2
    exit 1
fi

if [[ "$SOURCE_APP" == "$TARGET_APP" ]]; then
    echo "Source and target must be different; the vendor app is not modified." >&2
    exit 1
fi

for command in xcrun codesign ditto lipo plutil xattr python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Required command is missing: $command" >&2
        exit 1
    fi
done

if [[ ! -x "$VENV/bin/python" ]]; then
    echo "Creating local Python environment..."
    python3 -m venv "$VENV"
fi

if ! "$VENV/bin/python" -c 'import lief' >/dev/null 2>&1; then
    echo "Installing LIEF in $VENV..."
    "$VENV/bin/pip" install 'lief==1.0.0'
fi

WORK_APP="$TEMP_DIR/Cortex Control Patched.app"
echo "Copying the vendor application..."
ditto "$SOURCE_APP" "$WORK_APP"

INFO_PLIST="$WORK_APP/Contents/Info.plist"
EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw "$INFO_PLIST")"
EXECUTABLE="$WORK_APP/Contents/MacOS/$EXECUTABLE_NAME"
PATCHED_EXECUTABLE="$TEMP_DIR/$EXECUTABLE_NAME.patched"
DYLIB="$WORK_APP/Contents/MacOS/libCortexFullscreen.dylib"
ENTITLEMENTS="$TEMP_DIR/entitlements.plist"

if [[ ! -f "$EXECUTABLE" ]]; then
    echo "Executable named by Info.plist was not found: $EXECUTABLE" >&2
    exit 1
fi

ARCH_FLAGS=()
for architecture in $(lipo -archs "$EXECUTABLE"); do
    case "$architecture" in
        arm64|x86_64)
            ARCH_FLAGS+=("-arch" "$architecture")
            ;;
        *)
            echo "Unsupported executable architecture: $architecture" >&2
            exit 1
            ;;
    esac
done

echo "Building fullscreen shim for: $(lipo -archs "$EXECUTABLE")"
xcrun clang -fobjc-arc -dynamiclib -Os \
    "${ARCH_FLAGS[@]}" \
    -framework Cocoa \
    -mmacosx-version-min=10.13 \
    -install_name '@executable_path/libCortexFullscreen.dylib' \
    -o "$DYLIB" \
    "$SCRIPT_DIR/NativeFullscreenShim.m"

echo "Adding the shim load command..."
"$VENV/bin/python" "$SCRIPT_DIR/add_load_command.py" \
    "$EXECUTABLE" "$PATCHED_EXECUTABLE"
install -m 755 "$PATCHED_EXECUTABLE" "$EXECUTABLE"

ORIGINAL_ID="$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
case "$ORIGINAL_ID" in
    *.Patched) PATCHED_ID="$ORIGINAL_ID" ;;
    *) PATCHED_ID="$ORIGINAL_ID.Patched" ;;
esac

plutil -replace CFBundleIdentifier -string "$PATCHED_ID" "$INFO_PLIST"
plutil -replace CFBundleDisplayName -string "Cortex Control Patched" "$INFO_PLIST"
plutil -replace CFBundleName -string "Cortex Control Patched" "$INFO_PLIST"
if plutil -extract NSPrefersDisplaySafeAreaCompatibilityMode raw \
    "$INFO_PLIST" >/dev/null 2>&1; then
    plutil -replace NSPrefersDisplaySafeAreaCompatibilityMode -bool false \
        "$INFO_PLIST"
else
    plutil -insert NSPrefersDisplaySafeAreaCompatibilityMode -bool false \
        "$INFO_PLIST"
fi

if ! codesign -d --entitlements :- "$SOURCE_APP" \
    >"$ENTITLEMENTS" 2>/dev/null \
    || ! plutil -lint "$ENTITLEMENTS" >/dev/null 2>&1; then
    plutil -create xml1 "$ENTITLEMENTS"
fi

echo "Ad-hoc signing the patched copy..."
codesign --force --sign - "$DYLIB"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$WORK_APP"
xattr -dr com.apple.quarantine "$WORK_APP" || true
codesign --verify --deep --strict --verbose=2 "$WORK_APP"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"

if [[ -e "$TARGET_APP" ]]; then
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP_APP="${TARGET_APP%.app}.backup-$TIMESTAMP-$$.app"
    echo "Moving the previous patched copy to:"
    echo "  $BACKUP_APP"
    mv "$TARGET_APP" "$BACKUP_APP"
fi

mkdir -p "$(dirname "$TARGET_APP")"
mv "$WORK_APP" "$TARGET_APP"

echo
echo "Installed Cortex Control Patched $VERSION:"
echo "  $TARGET_APP"
echo
echo "Open it normally, then use the green button or Control-Command-F"
echo "to enter and leave fullscreen. Escape reaches Cortex without exiting."
