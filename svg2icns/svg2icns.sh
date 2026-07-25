#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

usage() {
    echo "Usage: $0 -i <input.svg> -o <output.icns>" >&2
    exit 1
}

INPUT=""
OUTPUT=""

while getopts ":i:o:" opt; do
    case $opt in
        i) INPUT="$OPTARG" ;;
        o) OUTPUT="$OPTARG" ;;
        :) echo "Error: option -$OPTARG requires an argument" >&2; usage ;;
        \?) echo "Error: unknown option -$OPTARG" >&2; usage ;;
    esac
done

[[ -z "$INPUT" || -z "$OUTPUT" ]] && { echo "Error: -i and -o are required" >&2; usage; }
[[ -f "$INPUT" ]] || { echo "Error: source file '$INPUT' does not exist" >&2; exit 1; }
mkdir -p "$(dirname -- "$OUTPUT")" || { echo "Error: failed to create the output directory" >&2; exit 1; }

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/svg2icns.XXXXXX") || { echo "Error: failed to create the temporary directory" >&2; exit 1; }
FITTED_PNG="${TEMP_DIR}/fitted.png"
EXTENDED_PNG="${TEMP_DIR}/extended.png"
ICONSET="${TEMP_DIR}/AppIcon.iconset"

mkdir -p "$ICONSET" || { echo "Error: failed to create the iconset directory" >&2; exit 1; }

# Fit the SVG into a 1024x1024 PNG while preserving aspect ratio.
if ! rsvg-convert \
    --format=png \
    --width=1024 \
    --height=1024 \
    --keep-aspect-ratio \
    "$INPUT" > "$FITTED_PNG"
then
    echo "Error: failed to convert SVG to PNG" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

[[ -s "$FITTED_PNG" ]] || { echo "Error: fitted PNG is empty" >&2; rm -rf "$TEMP_DIR"; exit 1; }

# Extend the fitted PNG to 1024x1024 with transparent background.
if ! magick "$FITTED_PNG" \
    -background none \
    -gravity center \
    -extent 1024x1024 \
    "$EXTENDED_PNG"
then
    echo "Error: failed to create the 1024x1024 PNG" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

WIDTH=$(sips -g pixelWidth "$EXTENDED_PNG" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')
HEIGHT=$(sips -g pixelHeight "$EXTENDED_PNG" 2>/dev/null | awk '/pixelHeight:/ { print $2 }')

if [[ "$WIDTH" != "1024" || "$HEIGHT" != "1024" ]]; then
    echo "Error: extended PNG is not 1024x1024 (actual size: ${WIDTH:-unknown}x${HEIGHT:-unknown})" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Create the iconset by generating PNGs of various sizes.
for SIZE in 16 32 128 256 512; do
    RETINA_SIZE=$((SIZE * 2))

    sips \
        -z "$SIZE" "$SIZE" \
        "$EXTENDED_PNG" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}.png" \
        >/dev/null

    sips \
        -z "$RETINA_SIZE" "$RETINA_SIZE" \
        "$EXTENDED_PNG" \
        --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" \
        >/dev/null
done

# Create the ICNS file from the iconset.
if ! iconutil \
    -c icns \
    -o "$OUTPUT" \
    "$ICONSET"
then
    echo "Error: failed to create the ICNS file" >&2
    rm -rf "$TEMP_DIR"
    exit 1
fi

[[ -s "$OUTPUT" ]] || { echo "Error: output ICNS file is empty" >&2; rm -rf "$TEMP_DIR"; exit 1; }

rm -rf "$TEMP_DIR"
