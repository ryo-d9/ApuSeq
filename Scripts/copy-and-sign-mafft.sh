#!/bin/sh
set -eu

VENDOR_MAFFT_DIR="${SRCROOT}/Vendor/MAFFT/mafft-mac"
BUNDLE_HELPERS_DIR="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Helpers"
BUNDLE_MAFFT_DIR="${BUNDLE_HELPERS_DIR}/MAFFT"
BUNDLE_MAFFT_RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/MAFFT"
ENTITLEMENTS="${SRCROOT}/Signing/MAFFTHelper.entitlements"
INPUT_FILE_LIST="${SRCROOT}/Scripts/mafft-input-files.xcfilelist"

if [ ! -d "$VENDOR_MAFFT_DIR" ]; then
    echo "error: Missing bundled MAFFT directory: $VENDOR_MAFFT_DIR"
    exit 1
fi

mkdir -p "$BUNDLE_HELPERS_DIR"
mkdir -p "$BUNDLE_MAFFT_DIR/mafftdir/libexec"
mkdir -p "$BUNDLE_MAFFT_RESOURCES_DIR/mafftdir/bin"
rm -f "$BUNDLE_MAFFT_DIR/in"
rm -f "$BUNDLE_MAFFT_DIR/mafft.bat"
rm -f "$BUNDLE_MAFFT_DIR/mafftdir/bin/mafft"
rm -f "$BUNDLE_MAFFT_DIR/mafftdir/libexec/"*.1
rm -f "$BUNDLE_MAFFT_DIR/mafftdir/libexec/"*.pl
rm -f "$BUNDLE_MAFFT_RESOURCES_DIR/mafft.bat"

while IFS= read -r sourceFile; do
    case "$sourceFile" in
        ""|\#*) continue ;;
    esac
    case "$sourceFile" in
        "\$(SRCROOT)"*) sourceFile="${SRCROOT}${sourceFile#"\$(SRCROOT)"}" ;;
    esac
    case "$sourceFile" in
        "$VENDOR_MAFFT_DIR/in"|"$VENDOR_MAFFT_DIR/mafft.bat"|"$VENDOR_MAFFT_DIR"/mafftdir/libexec/*.1|"$VENDOR_MAFFT_DIR"/mafftdir/libexec/*.pl) continue ;;
    esac
    relativePath=${sourceFile#"$VENDOR_MAFFT_DIR/"}
    case "$relativePath" in
        mafftdir/bin/mafft) destinationFile="$BUNDLE_MAFFT_RESOURCES_DIR/$relativePath" ;;
        *) destinationFile="$BUNDLE_MAFFT_DIR/$relativePath" ;;
    esac
    mkdir -p "$(dirname "$destinationFile")"
    cp -X -f "$sourceFile" "$destinationFile"
    case "$relativePath" in
        mafftdir/bin/mafft)
            case "$(head -n 1 "$destinationFile")" in
                "#!"*)
                    temporaryFile="${TARGET_TEMP_DIR:-/tmp}/apuseq-mafft-$(basename "$destinationFile").tmp"
                    tail -n +2 "$destinationFile" > "$temporaryFile"
                    mv "$temporaryFile" "$destinationFile"
                    ;;
            esac
            ;;
    esac
    xattr -c "$destinationFile" 2>/dev/null || true
    xattr -d com.apple.quarantine "$destinationFile" 2>/dev/null || true
done < "$INPUT_FILE_LIST"

# Keep the shell driver as a signed app resource, not nested executable code.
# ApuSeq invokes it through /bin/bash.
chmod -x "$BUNDLE_MAFFT_RESOURCES_DIR/mafftdir/bin/mafft"

if [ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" ]; then
    exit 0
fi

if [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    echo "warning: Skipping MAFFT helper signing because EXPANDED_CODE_SIGN_IDENTITY is empty."
    exit 0
fi

find "$BUNDLE_MAFFT_DIR/mafftdir" -type f | while IFS= read -r file; do
    if file "$file" | grep -q "Mach-O"; then
        chmod +x "$file"
        codesign --force \
            --options runtime \
            --entitlements "$ENTITLEMENTS" \
            --sign "$EXPANDED_CODE_SIGN_IDENTITY" \
            "$file"
    fi
done
