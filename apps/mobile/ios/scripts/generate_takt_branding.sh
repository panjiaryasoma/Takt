#!/bin/sh
set -eu

SOURCE="$SRCROOT/../assets/icon/takt_app_icon_1024.jpg"
APPICON_DIR="$SRCROOT/Runner/Assets.xcassets/AppIcon.appiconset"
OUTPUT="$APPICON_DIR/takt_app_icon_1024.png"

if [ ! -f "$SOURCE" ]; then
  echo "error: Takt iOS app icon source not found at $SOURCE" >&2
  exit 1
fi

WIDTH="$(/usr/bin/sips -g pixelWidth "$SOURCE" | /usr/bin/awk '/pixelWidth/ {print $2}')"
HEIGHT="$(/usr/bin/sips -g pixelHeight "$SOURCE" | /usr/bin/awk '/pixelHeight/ {print $2}')"

if [ "$WIDTH" != "1024" ] || [ "$HEIGHT" != "1024" ]; then
  echo "error: Takt iOS app icon must be exactly 1024x1024, got ${WIDTH}x${HEIGHT}" >&2
  exit 1
fi

mkdir -p "$APPICON_DIR"
/usr/bin/sips -s format png "$SOURCE" --out "$OUTPUT" >/dev/null

HAS_ALPHA="$(/usr/bin/sips -g hasAlpha "$OUTPUT" | /usr/bin/awk '/hasAlpha/ {print $2}')"
if [ "$HAS_ALPHA" != "no" ]; then
  echo "error: generated Takt iOS app icon contains an alpha channel" >&2
  exit 1
fi

echo "Generated opaque iOS AppIcon from $SOURCE"
