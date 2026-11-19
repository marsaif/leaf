#!/usr/bin/env python3
"""Build koreader/icons/ from Lucide (lucide-static, ISC licence) with Leaf's stroke.

    python3 tools/build-icons.py            # (re)write the icons, print a report
    python3 tools/build-icons.py --dry-run  # report only

KOReader looks for icons in koreader/icons/ before its own resources/icons/mdlight, so an SVG
named like a stock icon replaces it everywhere (title bars, menus, dialogs, file browser).

1. MAP below: stock KOReader icon name -> Lucide icon (first existing name wins).
2. Icons already in koreader/icons/ that came from Lucide (Project: Title's pt_*, the earlier
   overrides) are matched back to their Lucide source by their drawing and re-stroked, so every
   icon shares one stroke width.
3. Stock icons listed in KEEP_STOCK are deliberately not replaced (diagrams with no faithful
   Lucide equivalent, page chrome that gets its own port); any stock icon in neither list is
   reported as unmapped.

Stroke width = --stroke from prototype/css/tokens.css; colour is hardcoded black (KOReader's SVG
renderer does not resolve currentColor, and night mode inverts the screen anyway).
"""
import io
import json
import re
import sys
import tarfile
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "koreader/icons"
TOKENS = REPO / "prototype/css/tokens.css"
STOCK = Path.home() / "Applications/koreader-linux/lib/koreader/resources/icons/mdlight"
LUCIDE_VERSION = "1.76.0"
LUCIDE_URL = f"https://registry.npmjs.org/lucide-static/-/lucide-static-{LUCIDE_VERSION}.tgz"

# stock name -> Lucide name(s) (first that exists), or (names, {"fill": colour}) for solid shapes
MAP = {
    # top menu tabs: same choices as the prototype (js/screens/menus.js TAB_META)
    "appbar.filebrowser": "library-big",
    "appbar.navigation": "compass",
    "appbar.typeset": "type",
    "appbar.settings": "settings-2",
    "appbar.tools": "wrench",
    "appbar.search": "search",
    "appbar.menu": "menu",
    # bottom typesetting panel tabs (ConfigDialog)
    "appbar.pageview": "book-open",
    "appbar.textsize": "a-large-small",
    "appbar.contrast": "contrast",
    "appbar.crop": "crop",
    "appbar.rotation": "rotate-cw",
    "appbar.pagefit": "scan",
    "appbar.pokeball": "sliders-horizontal",
    # text alignment
    "align.auto": ["text-align-start", "align-left"],
    "align.left": ["text-align-start", "align-left"],
    "align.center": ["text-align-center", "align-center"],
    "align.right": ["text-align-end", "align-right"],
    "align.justify": ["text-align-justify", "align-justify"],
    # columns
    "column.one": ["columns-1", "square"],
    "column.two": "columns-2",
    "column.three": "columns-3",
    # navigation and actions
    "chevron.left": "chevron-left",
    "chevron.right": "chevron-right",
    "chevron.up": "chevron-up",
    "chevron.first": ["chevron-first", "chevrons-left"],
    "chevron.last": ["chevron-last", "chevrons-right"],
    "control.expand": "chevron-down",
    "control.expand.alpha": "chevron-down",
    "control.collapse": "chevron-up",
    "move.up": "arrow-up",
    "move.down": "arrow-down",
    "back.top": "undo-2",
    "back.top.rtl": "redo-2",
    "close": "x",
    "cancel": "x",
    "check": "check",
    "plus": "plus",
    "leaf.minus": "minus",  # Leaf's own: slider-row step button (KOReader has no minus icon)
    # Leaf's own: on-screen keyboard function keys (prototype keyboardHTML)
    "leaf.trash": "trash-2",
    # Leaf's own: book details (prototype overlay "book-details")
    "leaf.heart": "heart",
    "leaf.heart.on": (["heart"], {"fill": "#000000"}),
    "leaf.more.v": "ellipsis-vertical",
    "leaf.play": "book-open",
    # Leaf's own: reader chrome (prototype overlay "reader-chrome")
    "leaf.rd.prev": "skip-back",
    "leaf.rd.next": "skip-forward",
    "leaf.rd.contents": "list-ordered",
    "leaf.rd.typeset": "a-large-small",
    "leaf.rd.light": "sun",
    "leaf.rd.notes": "pen-line",
    "leaf.rd.more": "ellipsis",
    "leaf.rd.bookmark": "bookmark",
    "leaf.rd.bookmarked": (["bookmark"], {"fill": "#000000"}),
    # Leaf's own: the library "+" popover (prototype overlay "plus")
    "leaf.plus.select": "square-check",
    "leaf.plus.newfolder": "folder-plus",
    "leaf.plus.paste": "clipboard-paste",
    "leaf.plus.sethome": "house",
    "leaf.plus.gohome": "folder-root",
    "leaf.plus.random": "shuffle",
    "leaf.plus.shortcuts": "folder-symlink",
    "leaf.plus.addshortcut": "bookmark-plus",
    "leaf.plus.delshortcut": "bookmark-minus",
    "leaf.plus.cache": "database-zap",
    "leaf.plus.settings": "settings",
    "leaf.plus.action": "circle-dot",
    # Leaf's own: menu rows the keyword table had no icon for
    "leaf.mi.play": "play",
    "leaf.mi.toc": "list-tree",
    "leaf.mi.goto": "corner-down-right",
    "leaf.mi.skim": "gallery-horizontal",
    "leaf.mi.map": "map",
    "leaf.mi.proxy": "network",  # Leaf's own: destructive confirm title (UI.dialog danger icon)
    "leaf.kb.shift": "arrow-big-up",
    "leaf.kb.caps": "arrow-big-up-dash",
    "leaf.kb.backspace": "delete",
    "leaf.kb.globe": "globe",
    "leaf.kb.left": "arrow-left",
    "leaf.kb.right": "arrow-right",
    "leaf.kb.enter": "corner-down-left",
    "edit": "pencil",
    "exit": "log-out",
    "home": "house",
    "bookmark": "bookmark",
    "book.opened": "book-open",
    # notices
    "info": "info",
    "notice-info": "info",
    "notice-question": "circle-help",
    "notice-warning": "triangle-alert",
    # stars (filled vs outline is shape, not colour: e-ink safe)
    "star.empty": "star",
    "star.full": (["star"], {"fill": "#000000"}),
    "star.white": (["star"], {"fill": "#ffffff"}),
    # wifi strength (open networks)
    "wifi": "wifi",
    "wifi.open.0": "wifi-zero",
    "wifi.open.25": "wifi-low",
    "wifi.open.50": "wifi-high",
    "wifi.open.75": "wifi-high",
    "wifi.open.100": "wifi",
    # lookup scenes: text selection popup, dictionary, Wikipedia, translation, footnotes (leaf/lookup.lua)
    "leaf.lk.select": "text-select",
    "leaf.lk.highlight": "highlighter",
    "leaf.lk.copy": "copy",
    "leaf.lk.note": "notebook-pen",
    "leaf.lk.wiki": "globe",
    "leaf.lk.dict": "book-a",
    "leaf.lk.translate": "languages",
    "leaf.lk.share": "share-2",
    "leaf.lk.html": "code-xml",
    "leaf.lk.hyphen": "scissors",
    "leaf.lk.link": "link",
    "leaf.lk.search": "search",
    "leaf.lk.qr": "qr-code",
    "leaf.lk.vocab": "graduation-cap",
    "leaf.lk.download": "download",
    "leaf.lk.external": "external-link",
    "leaf.lk.details": "file-text",
    "leaf.lk.arrow": "arrow-right",
    "leaf.lk.pointer": "pointer",
    "leaf.lk.inline": "rows-3",
    "leaf.lk.plugin": "puzzle",
    "leaf.lk.footnote": "message-square-text",
    "leaf.lk.follow": "corner-down-right",
    "leaf.lk.results": "list",
    # library area: bottom nav (".on" = --stroke-strong, the active tab), view switch, home, cells
    "leaf.nav.home": "house",
    "leaf.nav.home.on": (["house"], {"stroke": "strong"}),
    "leaf.nav.library": "library-big",
    "leaf.nav.library.on": (["library-big"], {"stroke": "strong"}),
    "leaf.nav.history": "history",
    "leaf.nav.history.on": (["history"], {"stroke": "strong"}),
    "leaf.nav.settings": "settings",
    "leaf.nav.settings.on": (["settings"], {"stroke": "strong"}),
    "leaf.view.grid": "layout-grid",
    "leaf.view.grid.on": (["layout-grid"], {"stroke": "strong"}),
    "leaf.view.detail": "rows-3",
    "leaf.view.detail.on": (["rows-3"], {"stroke": "strong"}),
    "leaf.view.list": "list",
    "leaf.view.list.on": (["list"], {"stroke": "strong"}),
    "leaf.lib.sun": "sun-medium",
    "leaf.lib.clock": "clock",
    "leaf.lib.bookmark": "bookmark",
    "leaf.lib.bookopen": "book-open",
    "leaf.lib.flame": "flame",
    "leaf.lib.filetext": "file-text",
    "leaf.lib.gauge": "gauge",
    "leaf.lib.folder": "folder",
}

KEEP_STOCK = {
    # reading-direction / orientation / zoom diagrams: no faithful Lucide shape; redesigned with their panels
    **{n: "diagram" for n in (
        "direction.BTLR direction.BTRL direction.LRBT direction.LRTB direction.RLBT direction.RLTB "
        "direction.TBLR direction.TBRL rotation.0UR rotation.180UD rotation.90CCW rotation.90CW "
        "rotation.L.0UR rotation.L.180UD rotation.L.90CCW rotation.L.90CW rotation.P.0UR "
        "rotation.P.180UD rotation.P.90CCW rotation.P.90CW zoom.column zoom.content zoom.manual "
        "zoom.page zoom.row").split()},
    # page chrome drawn on the book page: ported with the reader (rd-dogear, position marker)
    **{n: "page chrome" for n in (
        "dogear.abandoned dogear.abandoned.rtl dogear.alpha dogear.complete dogear.complete.rtl "
        "dogear.opaque dogear.reading position.marker position.marker.top").split()},
    # secured networks: Lucide has no wifi+lock at every strength; keep until the wifi screen port
    **{f"wifi.secure.{p}": "wifi + lock" for p in (0, 25, 50, 75, 100)},
    # small status glyphs and placeholders
    "cre.render.partial": "status glyph", "cre.render.ready": "status glyph",
    "cre.render.reload": "status glyph", "cre.render.reload.alpha": "status glyph",
    "cre.render.working": "status glyph", "texture-box": "placeholder pattern", "triangle": "status glyph",
}


def stroke_width(variant=None):
    name = "stroke" if not variant else f"stroke-{variant}"
    m = re.search(rf"--{name}:\s*([\d.]+);", TOKENS.read_text())
    return m.group(1)


def fetch_lucide():
    """-> {name: svg text} from the pinned lucide-static tarball."""
    data = urllib.request.urlopen(LUCIDE_URL, timeout=60).read()
    icons = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for m in tar.getmembers():
            mm = re.fullmatch(r"package/icons/([a-z0-9-]+)\.svg", m.name)
            if mm and m.isfile():
                icons[mm.group(1)] = tar.extractfile(m).read().decode()
    return icons


def body(svg):
    """the drawing elements only, whitespace-normalised (to match icons back to Lucide)"""
    inner = re.search(r"<svg[^>]*>(.*)</svg>", svg, re.S).group(1)
    inner = inner.replace("currentColor", "#000000")
    return re.sub(r"\s+", " ", inner).strip()


def render(lucide_svg, name, sw, fill="none"):
    inner = re.search(r"<svg[^>]*>(.*)</svg>", lucide_svg, re.S).group(1).strip("\n")
    inner = inner.replace("currentColor", "#000000")  # KOReader's SVG renderer: no currentColor
    return (f"<!-- Leaf: lucide-static v{LUCIDE_VERSION} \"{name}\" (ISC), stroke {sw}; built by tools/build-icons.py -->\n"
            f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" '
            f'fill="{fill}" stroke="#000000" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">\n'
            f"{inner}\n</svg>\n")


def paper(name):
    """a colour token of the Paper theme (the e-ink theme) from tokens.css"""
    block = re.search(r"\.theme-paper \{(.*?)\n\}", TOKENS.read_text(), re.S).group(1)
    return re.search(rf"--{name}:\s*(#[0-9a-fA-F]{{6}});", block).group(1)


def controls():
    """Leaf's check box and radio (.ko-check / .ko-radio): 20px, --bw-md outline in --border-strong;
    selected = accent fill + accent-ink tick / accent ring + dot. Shape differs too (e-ink safe)."""
    line, accent, ink = paper("border-strong"), paper("accent"), paper("accent-ink")
    head = '<!-- Leaf control mark, colours from tokens.css (paper); built by tools/build-icons.py -->\n'
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20">\n{}\n</svg>\n'
    return {
        "leaf.check.off.svg": head + svg.format(
            f'<rect x=".75" y=".75" width="18.5" height="18.5" rx="5" fill="none" stroke="{line}" stroke-width="1.5"/>'),
        "leaf.check.on.svg": head + svg.format(
            f'<rect x=".75" y=".75" width="18.5" height="18.5" rx="5" fill="{accent}" stroke="{accent}" stroke-width="1.5"/>\n'
            f'<path d="M5.5 10.4 8.6 13.4 14.6 6.8" fill="none" stroke="{ink}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>'),
        "leaf.radio.off.svg": head + svg.format(
            f'<circle cx="10" cy="10" r="9.25" fill="none" stroke="{line}" stroke-width="1.5"/>'),
        "leaf.radio.on.svg": head + svg.format(
            f'<circle cx="10" cy="10" r="9.25" fill="none" stroke="{accent}" stroke-width="1.5"/>\n'
            f'<circle cx="10" cy="10" r="5" fill="{accent}"/>'),
    }


def main():
    dry = "--dry-run" in sys.argv
    sw = stroke_width()
    lucide = fetch_lucide()
    by_body = {body(svg): n for n, svg in lucide.items()}
    out, report = {}, {"mapped": [], "restroked": [], "unknown": [], "missing_lucide": [], "unmapped_stock": []}

    for stock, spec in MAP.items():
        names, opts = (spec if isinstance(spec, tuple) else ([spec] if isinstance(spec, str) else spec, {}))
        names = [names] if isinstance(names, str) else names
        hit = next((n for n in names if n in lucide), None)
        if not hit:
            report["missing_lucide"].append(f"{stock} -> {names}")
            continue
        w = stroke_width(opts["stroke"]) if "stroke" in opts else sw
        out[f"{stock}.svg"] = render(lucide[hit], hit, w, opts.get("fill", "none"))
        report["mapped"].append(f"{stock} -> {hit}")

    out.update(controls())
    for f in sorted(OUT.glob("*.svg")):
        if f.name in out:
            continue
        text = f.read_text()
        m = re.search(r'Leaf: lucide-static v[\d.]+ "([a-z0-9-]+)"', text)
        src = m.group(1) if m else by_body.get(body(text))
        if src and src in lucide:
            fill = re.search(r'<svg[^>]*\bfill="([^"]+)"', text)
            out[f.name] = render(lucide[src], src, sw, fill.group(1) if fill else "none")
            report["restroked"].append(f"{f.stem} <- {src}")
        else:
            report["unknown"].append(f.name)

    if STOCK.exists():
        for f in sorted(STOCK.glob("*.svg")):
            if f.stem not in MAP and f.stem not in KEEP_STOCK:
                report["unmapped_stock"].append(f.stem)

    if not dry:
        for name, svg in out.items():
            (OUT / name).write_text(svg)
    print(f"lucide-static {LUCIDE_VERSION}: {len(lucide)} icons; stroke-width {sw}")
    print(f"{'would write' if dry else 'wrote'} {len(out)} icons to {OUT.relative_to(REPO)}: "
          f"{len(report['mapped'])} stock names mapped, {len(report['restroked'])} existing re-stroked, "
          f"{len(controls())} control marks")
    print(f"kept stock on purpose: {len(KEEP_STOCK)} ({', '.join(sorted(set(KEEP_STOCK.values())))})")
    for k in ("missing_lucide", "unknown", "unmapped_stock"):
        if report[k]:
            print(f"!! {k}: {', '.join(report[k])}")
    if "--verbose" in sys.argv:
        print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
