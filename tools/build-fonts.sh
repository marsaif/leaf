#!/usr/bin/env bash
# Rebuild koreader/fonts/leaf/ from the official sources (all SIL Open Font License).
#   Inter 4.1 (rsms/inter release, static TTFs as published)
#   Playfair Display, Literata (google/fonts variable fonts -> static instances via fontTools)
# Literata is cut at opsz=12 (text optical size). Needs: curl, unzip, uv.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/koreader/fonts/leaf"
DL="$(mktemp -d)"
trap 'rm -rf "$DL"' EXIT
GF=https://github.com/google/fonts/raw/main/ofl

curl -sSLf -o "$DL/inter.zip" https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip
curl -sSLf -o "$DL/Playfair.ttf" "$GF/playfairdisplay/PlayfairDisplay%5Bwght%5D.ttf"
curl -sSLf -o "$DL/Playfair-Italic.ttf" "$GF/playfairdisplay/PlayfairDisplay-Italic%5Bwght%5D.ttf"
curl -sSLf -o "$DL/Literata.ttf" "$GF/literata/Literata%5Bopsz,wght%5D.ttf"
curl -sSLf -o "$DL/Literata-Italic.ttf" "$GF/literata/Literata-Italic%5Bopsz,wght%5D.ttf"
curl -sSLf -o "$DL/OFL-PlayfairDisplay.txt" "$GF/playfairdisplay/OFL.txt"
curl -sSLf -o "$DL/OFL-Literata.txt" "$GF/literata/OFL.txt"

mkdir -p "$OUT"
unzip -o -q -j "$DL/inter.zip" extras/ttf/Inter-Regular.ttf extras/ttf/Inter-Medium.ttf \
    extras/ttf/Inter-SemiBold.ttf extras/ttf/Inter-Bold.ttf -d "$OUT"
unzip -p "$DL/inter.zip" LICENSE.txt > "$OUT/OFL-Inter.txt"
cp "$DL"/OFL-*.txt "$OUT/"

I="uv run -q --with fonttools==4.55.3 --with skia-pathops python -I $REPO/tools/fonts/instance.py"
$I "$DL/Playfair.ttf" "$OUT/PlayfairDisplay-Regular.ttf" "Playfair Display" Regular wght=400
$I "$DL/Playfair.ttf" "$OUT/PlayfairDisplay-SemiBold.ttf" "Playfair Display" SemiBold wght=600
$I "$DL/Playfair-Italic.ttf" "$OUT/PlayfairDisplay-Italic.ttf" "Playfair Display" Italic wght=400
$I "$DL/Literata.ttf" "$OUT/Literata-Regular.ttf" Literata Regular wght=400 opsz=12
$I "$DL/Literata.ttf" "$OUT/Literata-Bold.ttf" Literata Bold wght=700 opsz=12
$I "$DL/Literata-Italic.ttf" "$OUT/Literata-Italic.ttf" Literata Italic wght=400 opsz=12
$I "$DL/Literata-Italic.ttf" "$OUT/Literata-BoldItalic.ttf" Literata "Bold Italic" wght=700 opsz=12
ls -la "$OUT"
