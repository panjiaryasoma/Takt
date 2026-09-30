#!/bin/sh
set -eu

SOURCE="$SRCROOT/../assets/branding/logo.png"
APPICON_DIR="$SRCROOT/Runner/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
  echo "error: Takt branding source not found at $SOURCE" >&2
  exit 1
fi

mkdir -p "$APPICON_DIR"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

WIDTH="$(/usr/bin/sips -g pixelWidth "$SOURCE" | /usr/bin/awk '/pixelWidth/ {print $2}')"
HEIGHT="$(/usr/bin/sips -g pixelHeight "$SOURCE" | /usr/bin/awk '/pixelHeight/ {print $2}')"

if [ -z "$WIDTH" ] || [ -z "$HEIGHT" ]; then
  echo "error: could not read Takt logo dimensions" >&2
  exit 1
fi

SIDE="$WIDTH"
if [ "$HEIGHT" -lt "$WIDTH" ]; then
  SIDE="$HEIGHT"
fi

SQUARE="$WORK_DIR/takt-square.jpg"
/usr/bin/sips --cropToHeightWidth "$SIDE" "$SIDE" "$SOURCE" --out "$SQUARE" >/dev/null

make_icon() {
  NAME="$1"
  PIXELS="$2"
  /usr/bin/sips -s format png -z "$PIXELS" "$PIXELS" "$SQUARE" \
    --out "$APPICON_DIR/$NAME" >/dev/null
}

make_icon "Icon-App-20x20@1x.png" 20
make_icon "Icon-App-20x20@2x.png" 40
make_icon "Icon-App-20x20@3x.png" 60
make_icon "Icon-App-29x29@1x.png" 29
make_icon "Icon-App-29x29@2x.png" 58
make_icon "Icon-App-29x29@3x.png" 87
make_icon "Icon-App-40x40@1x.png" 40
make_icon "Icon-App-40x40@2x.png" 80
make_icon "Icon-App-40x40@3x.png" 120
make_icon "Icon-App-60x60@2x.png" 120
make_icon "Icon-App-60x60@3x.png" 180
make_icon "Icon-App-76x76@1x.png" 76
make_icon "Icon-App-76x76@2x.png" 152
make_icon "Icon-App-83.5x83.5@2x.png" 167
make_icon "Icon-App-1024x1024@1x.png" 1024
