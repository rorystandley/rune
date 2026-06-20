#!/usr/bin/env bash
# Regenerate Rune's brand PNGs from the Algiz rune geometry.
#
# ImageMagick's SVG parser silently drops stroked paths, so we draw with its
# native -draw (MVG) instead. This script — not the .svg files — is the source
# of truth for the PNGs; the .svg mirrors are for vector editing (browser/Inkscape).
# After running this, regenerate platform assets:
#   dart run flutter_launcher_icons
#   dart run flutter_native_splash:create
set -euo pipefail
cd "$(dirname "$0")/../../assets/branding"

cap="stroke-linecap round stroke-linejoin round"
# Algiz rune (vertical stem + two arms to the top corners), white, on a 1024 canvas.
full="fill none stroke white stroke-width 70 $cap line 512,784 512,240 line 512,434 328,240 line 512,434 696,240"  # full size
s082="fill none stroke white stroke-width 57 $cap line 512,735 512,289 line 512,448 361,289 line 512,448 663,289"  # 0.82 (Android safe zone)
s05="fill none stroke white stroke-width 35 $cap line 512,648 512,376 line 512,473 420,376 line 512,473 604,376"   # 0.50 (splash logo)

magick -size 1024x1024 xc:"#E8B520" -draw "$full" -depth 8 PNG32:icon_master.png            # iOS/macOS/Windows + Android legacy
magick -size 1024x1024 xc:none      -draw "$full" -depth 8 PNG32:icon_dark_transparent.png   # iOS 18 dark
magick -size 1024x1024 xc:none      -draw "$s082" -depth 8 PNG32:icon_foreground.png         # Android adaptive foreground
magick -size 1024x1024 xc:none      -draw "$s082" -depth 8 PNG32:icon_monochrome.png         # Android themed (monochrome)
magick -size 1024x1024 xc:none      -draw "$s05"  -depth 8 PNG32:splash_logo.png             # native splash

echo "regenerated brand PNGs in assets/branding/"
