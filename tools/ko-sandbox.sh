#!/usr/bin/env bash
# Run desktop KOReader against a throw-away KO_HOME so the real ~/.config/koreader is never touched.
#
#   tools/ko-sandbox.sh                 # window at half Kindle 11 size (536x724): fits a 1080p screen,
#                                       # same layout as the device (sizes scale by the short side)
#   tools/ko-sandbox.sh --full          # real Kindle 11 geometry (1072x1448 @ 300 dpi) in a window
#   tools/ko-sandbox.sh --proto         # 600x800, 1:1 with the HTML prototype's 6" frame
#   tools/ko-sandbox.sh --reset         # wipe the sandbox first (fresh settings, books, plugin copy)
#   tools/ko-sandbox.sh --shots DIR [--scenes fm,menu,...] [--night]
#                                       # no window: render offscreen at full Kindle size (unless --proto),
#                                       # screenshot each scene into DIR and quit
#                                       # (scene list: koreader/patches/2-autoshot.lua)
#   tools/ko-sandbox.sh --stock         # Leaf off (LEAF_DISABLE=1): the same sandbox with stock-looking UI
#   tools/ko-sandbox.sh -- FILE         # anything after -- is passed to KOReader (e.g. a book to open)
#
# The repo's koreader/{patches,icons,leaf} and defaults.custom.lua are SYMLINKED in and fonts/leaf is
# copied on every launch (see the fonts note below): edits show up on the next launch. Books and the Project: Title plugin are COPIED once,
# because KOReader writes sidecars / caches next to them.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
KO_APP="${KO_APP:-$HOME/Applications/koreader-linux/bin/koreader}"
SB="$(realpath -m "${LEAF_SANDBOX:-$REPO/.sandbox}")"  # LEAF_SANDBOX=dir: a second, independent sandbox (made absolute: KOReader cds)
HOME_DIR="$SB/home"
BOOKS="$SB/books"
REAL="$HOME/.config/koreader"

W=536 H=724 DPI=150 GEOM=""
RESET=0 SHOTS="" SCENES="" NIGHT=0 STOCK=0 ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --proto) GEOM=proto ;;
        --full) GEOM=full ;;
        --reset) RESET=1 ;;
        --shots) SHOTS="$(realpath -m "$2")"; shift ;;
        --scenes) SCENES="$2"; shift ;;
        --night) NIGHT=1 ;;
        --stock) STOCK=1 ;;
        --) shift; ARGS=("$@"); break ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# screenshots render offscreen, so they can always use the real device size
[ -n "$SHOTS" ] && [ -z "$GEOM" ] && GEOM=full
case "$GEOM" in
    full) W=1072 H=1448 DPI=300 ;;
    proto) W=600 H=800 DPI=160 ;;
esac

[ "$RESET" = 1 ] && rm -rf "$SB"

if [ ! -d "$HOME_DIR" ]; then
    echo "creating sandbox in $SB"
    mkdir -p "$HOME_DIR/plugins" "$HOME_DIR/fonts" "$HOME_DIR/settings" "$BOOKS"

    # test books (copies: KOReader writes .sdr sidecars next to them)
    for b in "$HOME/Books/Animal Farm.epub" \
             "$HOME/animal-farm-ar/Animal Farm.epub:Animal Farm (EN-AR).epub" \
             "$HOME/Downloads/KOReader UI Redesign Concept.pdf"; do
        src="${b%%:*}"; name="${b#*:}"; [ "$name" = "$b" ] && name="$(basename "$src")"
        [ -f "$src" ] && cp "$src" "$BOOKS/$name"
    done
    mkdir -p "$BOOKS/Folder A" "$BOOKS/Folder B"

    # Project: Title (copy: it keeps caches/settings around its own files)
    [ -d "$REAL/plugins/projecttitle.koplugin" ] && cp -r "$REAL/plugins/projecttitle.koplugin" "$HOME_DIR/plugins/"
    # Source Sans/Serif used by Project: Title and the legacy patches
    [ -d "$REAL/fonts/source" ] && cp -r "$REAL/fonts/source" "$HOME_DIR/fonts/"
    # Project: Title keeps its settings (display mode, grid size...) in its own SQLite file:
    # take a copy with the user's config rows only, the book cache emptied
    if [ -f "$REAL/settings/PT_bookinfo_cache.sqlite3" ]; then
        python3 - "$REAL/settings/PT_bookinfo_cache.sqlite3" "$HOME_DIR/settings/PT_bookinfo_cache.sqlite3" <<'PY'
import shutil, sqlite3, sys
src = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
dst = sqlite3.connect(sys.argv[2])
src.backup(dst)
dst.execute("DELETE FROM bookinfo")
dst.commit()
dst.execute("VACUUM")
PY
    fi

    # minimal settings: start in the library, greyscale like the Kindle, skip first-run prompts
    cat > "$HOME_DIR/settings.reader.lua" <<EOF
return {
    ["home_dir"] = "$BOOKS",
    ["lastdir"] = "$BOOKS",
    ["start_with"] = "filemanager",
    ["color_rendering"] = false,
    ["night_mode"] = false,
    ["plugins_disabled"] = { ["coverbrowser"] = true },
    ["quickstart_shown_version"] = 999999999999,
    ["aaaProjectTitle_initial_default_setup_done2"] = true,
}
EOF
fi

# repo links (refreshed every launch; dangling ones are fine until that step lands)
link() { rm -rf "$2"; ln -s "$1" "$2"; }
link "$REPO/koreader/patches" "$HOME_DIR/patches"
link "$REPO/koreader/icons" "$HOME_DIR/icons"
link "$REPO/koreader/leaf" "$HOME_DIR/leaf"
# fonts: on the Kindle the data dir IS the install dir, so koreader/fonts/leaf is in KOReader's own
# font folder. Desktop KOReader only scans $XDG_DATA_HOME/fonts (+ system fonts) for extra fonts,
# so the sandbox gets its own XDG_DATA_HOME with a COPY (the scanner skips symlinked folders).
XDG="$SB/xdg"
mkdir -p "$XDG/fonts"
rm -rf "$XDG/fonts/leaf"; cp -r "$REPO/koreader/fonts/leaf" "$XDG/fonts/leaf"
[ -d "$HOME_DIR/fonts/source" ] && [ ! -d "$XDG/fonts/source" ] && cp -r "$HOME_DIR/fonts/source" "$XDG/fonts/source"
export XDG_DATA_HOME="$XDG"
link "$REPO/koreader/defaults.custom.lua" "$HOME_DIR/defaults.custom.lua"

export KO_HOME="$HOME_DIR"
[ "$STOCK" = 1 ] && export LEAF_DISABLE=1
export LEAF_DEBUG=1          # leaf/core.lua: log extra diagnostics
export KO_SANDBOX_KINDLE=1   # koreader/patches/2-sandbox-kindle.lua: no keyboard, like the Kindle
export EMULATE_READER_W=$W EMULATE_READER_H=$H EMULATE_READER_DPI=$DPI
if [ -n "$SHOTS" ]; then
    mkdir -p "$SHOTS"
    export KO_AUTOSHOT="$SHOTS"
    export SDL_VIDEODRIVER=offscreen
    [ -n "$SCENES" ] && export KO_AUTOSHOT_SCENES="$SCENES"
    [ "$NIGHT" = 1 ] && export KO_AUTOSHOT_NIGHT=1
fi

: > "$HOME_DIR/crash.log" 2>/dev/null || true
set +e
"$KO_APP" "${ARGS[@]}" 2>&1 | tee "$SB/last-run.log" | grep -E "ERROR|error|Lua|traceback" | grep -v "^$" | head -40
set -e

# fail loudly on Lua errors (stock KOReader logs harmless warnings too: only show errors)
if grep -qE "ERROR|stack traceback" "$SB/last-run.log"; then
    echo "!! errors in $SB/last-run.log" >&2
    exit 1
fi
[ -n "$SHOTS" ] && ls "$SHOTS"
exit 0
