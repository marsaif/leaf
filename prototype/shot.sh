#!/bin/sh
# Usage: ./shot.sh "#/library?tab=history" out.png [dark|paper] [600x800] [eink]
# Renders one prototype state headlessly (no designer panel) to a PNG.
DIR="$(cd "$(dirname "$0")" && pwd)"
HASH="${1:-#/home}"; OUT="${2:-$DIR/shots/shot.png}"; THEME="${3:-dark}"; SIZE="${4:-600x800}"; EINK="${5:-}"
W="${SIZE%x*}"; H="${SIZE#*x}"
E=""; [ "$EINK" = "eink" ] && E="&eink=1"
PROFILE="$(mktemp -d)"
google-chrome --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$PROFILE" \
  --window-size="$W,$H" --virtual-time-budget=4000 --screenshot="$OUT" \
  "file://$DIR/index.html?bare&theme=$THEME&size=$SIZE$E$HASH" >/dev/null 2>&1
rm -rf "$PROFILE"
echo "$OUT"
