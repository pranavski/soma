#!/usr/bin/env bash
# Render DesignAssets sources into Soma/Assets.xcassets.
#
# The app icon master is a 1024x1024 PNG with a transparent rounded-rect
# margin (DesignAssets/master/app-icon-1024.png). iOS masks the corners
# itself and App Store validation rejects any alpha, so we crop to the
# artwork's rounded rect, scale it back to 1024, and flatten onto the paper
# background.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT/DesignAssets/master/app-icon-1024.png"
ICONSET="$ROOT/Soma/Assets.xcassets/AppIcon.appiconset"

mkdir -p "$ICONSET"

python3 - "$MASTER" "$ICONSET/AppIcon-1024.png" <<'PY'
import sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")

# The designed icon is the rounded rect, not the padded canvas — crop to it so
# the artwork fills the frame iOS actually renders.
bbox = img.getchannel("A").getbbox()
if bbox and bbox != (0, 0, *img.size):
    img = img.crop(bbox)
if img.size != (1024, 1024):
    img = img.resize((1024, 1024), Image.LANCZOS)

# Flatten onto the paper background the artwork already sits on, so the
# corners iOS rounds away are the same cream as the rest of the icon.
paper = img.getpixel((img.width // 2, 8))[:3]
flat = Image.new("RGB", img.size, paper)
flat.paste(img, mask=img.getchannel("A"))
flat.save(out)

print(f"icon: {flat.size} {flat.mode} on #{'%02X%02X%02X' % paper}")
PY

echo "done"
