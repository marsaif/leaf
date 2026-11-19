#!/usr/bin/env python3
"""Folio design linter.

Loads index.html in headless Chrome, visits every state registered in App.demos (dark + paper at
600x800, plus dark at 1000x750), checks computed styles and layout, and writes
tools/audit-report.md, tools/audit.json and shots/qa-*.png.

  tools/.venv/bin/python tools/audit.py                     # everything
  tools/.venv/bin/python tools/audit.py --group Reader      # one designer group (substring, case-insensitive)
  tools/.venv/bin/python tools/audit.py --match typeset     # states whose label/hash contains text
  tools/.venv/bin/python tools/audit.py --quick             # dark 600x800 only, no screenshots
  tools/.venv/bin/python tools/audit.py --no-shots --passes dark@600x800,paper@600x800

Setup (once):  uv venv tools/.venv && uv pip install --python tools/.venv playwright
"""
import argparse, asyncio, collections, json, math, re, sys, time
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
SHOTS = ROOT / "shots"
CHROME = "/usr/bin/google-chrome"

# ---------------------------------------------------------------------------------------------
# Explicit allow-lists (keep these SMALL; every entry is a deliberate design exception)
# ---------------------------------------------------------------------------------------------
CFG = {
    # theme tokens that make up the palette
    "tokens": ["--bg", "--bg-raised", "--surface", "--surface-2", "--surface-3", "--border", "--border-strong",
               "--text", "--text-2", "--text-3", "--disabled", "--accent", "--accent-ink", "--accent-soft",
               "--danger", "--scrim", "--page", "--page-ink", "--page-2",
               "--hl-c-yellow", "--hl-c-green", "--hl-c-blue", "--hl-c-red", "--hl-c-purple", "--hl-c-gray",
               # named blends and fixed colours (css/tokens.css › derived values / fixed colours)
               "--accent-tint", "--heat-0", "--heat-1", "--heat-2", "--heat-3", "--heat-4", "--hl-swatch-yellow",
               "--hl-tint-yellow", "--hl-tint-green", "--hl-tint-blue", "--hl-tint-red", "--hl-tint-purple",
               "--hl-yellow", "--hl-green", "--hl-blue", "--hl-red", "--hl-purple", "--hl-gray", "--hl-ink-blue", "--hl-ink-red",
               "--hl-underline", "--hl-strike", "--hl-eink", "--sel", "--page-tint", "--page-scan", "--page-scan-ink", "--page-dim-ink",
               "--page-rule", "--page-line", "--page-line-fill", "--page-tick", "--page-ornament", "--page-quote-rule", "--page-mark-ring",
               "--page-skeleton", "--page-skeleton-strong", "--on-cover", "--cover-scrim", "--cover-scrim-soft", "--qr-bg", "--qr-ink",
               "--scan-paper", "--scan-ink", "--scan-ink-2", "--scan-ink-soft", "--scan-watermark", "--scan-dirt", "--scan-gutter"],
    # component scales (css/tokens.css): variants on these scales are a deliberate size choice, not drift
    "iconScale": [12, 14, 16, 18, 20, 22, 24, 28, 40],
    "strokeScale": [1.2, 1.3, 1.6, 2, 2.4],
    "progressScale": ["h2", "h3", "h4"],
    "chipScale": ["h32 fs13", "h40 fs15", "h32 fs11"],   # .ko-chip, .ko-chip--lg, reader colour chips (.rd-cchip)
    "labelScale": ["fs11 fw600 ls0.88px", "fs10.5 fw600 ls0.42px"],   # .ko-eyebrow / .ko-section-label, .ko-pill--caps
    "maxText": 17.5,   # anything bigger must be a title or a hero metric
    "maxTitle": 30.5,
    "maxArabic": 26,   # Arabic text may run larger than Latin (Naskh has a small x-height)  # cap even for titles (display hero titles of book details may hit 30)
    "scale": [10.5, 11, 13, 15, 17, 18, 22, 30],  # tokens.css --fs-* (+10.5 for nav/badges in components.css)
    # titles: screen/page/sheet/dialog/card/book titles
    "titles": [".ko-header .title", ".ko-sheet-head .title", ".ko-dialog .title", "h1", "h2",
               "[class*='-title']", "[class*='head'] .title", "[class*='head'] .t", "[class*='head'] .hw",
               ".lbd-title", ".lbd-author", ".ab-name",
               # book titles shown in lists/cards
               ".lb-drow .t", ".rd-end-next .t"],
    # deliberate hero metrics / big numbers
    # cards whose semibold <=18px heading counts as a card title
    "cards": [".ko-card", "[class*='card']", "[class*='hero']", "[class*='empty']", "[class*='-cur']", "[class*='stat']", "[class*='feat']"],
    "hero": ["blockquote", ".hm-big", ".st-time", ".st-big", ".st-kpi-v", ".lbd-prow .big", ".rd-goto-field .val", ".fl-label b",
             ".ab-mark", ".rd-aa",   # .rd-aa = the "Aa" typography glyph used as an icon
             ".rd-map-sum b", ".sy-chg-pct", ".sy-upd-mark", ".sy-wordmark", ".ex-card-w", ".sy-feat-glyph"],  # charging %, app mark, Welcome wordmark, flashcard word, dictionary glyph
    # input fields and keyboards may use larger glyphs
    "inputs": ["input", ".kb-key", ".rd-keypad", ".dl-field", ".sr-field", ".kb-text"],
    # book content: the reading page, covers, page thumbnails, sleep-screen book art
    "book": [".rd-text", ".rd-head", ".rd-foot", ".rd-scan", ".ko-cover", ".rd-thumb .pv", ".rd-mdia .pg",
             ".ss-book", ".rd-preview", ".rd-qr-code", ".cover", "[class*='cover-art']",
             # previews of book typography / device screens (sizes are the point of the preview)
             ".ss", ".rd-preset .pv", ".rd-font .smp", ".rd-hyph-word",
             ".sy-lk", ".sy-read-prev", ".rd-font .nm",
             # user-sized document content: text editor / terminal buffers, translated paragraph
             ".ex-te-doc", ".ex-term-scr", ".rd-tr-body",
             # design-system catalog specimens (type scale, weights, colour panels): the sizes/colours are the point
             ".ct-type", ".ct-weights", ".ct-theme"],   # lock-screen preview, Welcome reading preview
    "swatchScope": ".ko-layer",
    # serif/italic allowed: book-text previews, quotes, Arabic text
    "serifOk": ["blockquote", "q", "[class*='quote']", "[lang='ar']", "[dir='rtl']", ".rd-font", ".rd-aa",
                ".rd-hyph-word", ".rd-tr-ar", ".rd-artr", ".rd-dict-ar", ".kb-ar", ".rd-ann .q", ".rd-note-body .q",
                # quoted book text and style samples
                ".snip", ".rd-qr-txt", ".rd-tr-en", ".smp",
                # reading content shown in panels: dictionary examples (quotes), Wikipedia article body
                ".rd-senses em", ".rd-wiki-body", ".sr-hit-text",
                # vocabulary words and the book sentences they were looked up in
                ".ex-w", ".ex-ctx", ".ex-card-ctx", ".ex-card-w", ".sy-feat-glyph"],
    "serifFamilies": ["Playfair Display", "Literata", "Source Serif 4", "Georgia", "serif", "EB Garamond",
                      "Merriweather", "Noto Serif", "Bitter"],
    "boldOk": [".ko-badge", "mark", "b.hl"],
    "colourOk": [".ko-badge", ".lb-selmark", ".rd-cdot", ".ko-toast", ".set-ramp"],   # .set-ramp: the 16-level e-ink grey ramp (screen-specific art)
    # .rd-scanview: the cropped PDF page is clipped by design; dense chart axes: sparse labels overhang empty neighbours
    "overflowOk": [".ko-scrim", ".rd-scanview", ".st-chart.dense .st-x"],
    "rows": [".ko-row", "[class*='-row']:not([class*='-rows'])"],
    "notRows": [".kb-row", ".kb"],
    "rowLabels": [".label", ".ttl", ".t", ".nm", ".name", ".title", ".lbl", ".ex-dev-h > b", ".grow > b"],
    "rowValues": [".value", ".val", ".num", "[class*='-val']", "[class*='-num']"],
    "contrastOk": [".rd-scan .wm", ".ss"],   # scan watermark is page art; .ss = sleep-screen previews over images
    "controls": [".ko-btn", ".ko-chip", ".ko-tab", ".ko-seg button", "[role='tab']", ".ko-nav button",
                 "[class*='chip']", "[class*='seg'] > button", "[class*='tabs'] > button", "button[class*='pill']",
                 "button:not(.ko-row):not([class*='row'])"],
    "notControls": [".kb-key", "[class*='card']", ".ko-row", "[class*='-row']"],
    "chips": [".ko-chip", "[class*='chip']:not([class*='chips'])"],
    "interactive": ["button", "a[href]", "[data-action]", "[data-go]", "[data-open]", "[data-close]:not(.ko-scrim)",
                    "[role='button']", "input", "[data-slide]", "select"],
    "touchOk": [".ko-scrim"],
    "minTouch": 40,
    "selected": [".on", ".sel", ".active", ".selected", ".current", "[aria-selected='true']",
                 "[aria-pressed='true']", "[aria-checked='true']"],
    "selectedOk": [],
    "buttons": [".ko-btn", "button"],
    "notButtons": [".ko-row", "[class*='-row']", ".ko-chip", "[class*='chip']", ".ko-seg button", "[class*='seg'] button",
                   ".kb-key", ".rd-keypad button", ".ko-tab", "[class*='tabs'] button", ".ko-nav button", ".ko-icon-btn"],
    "toggles": [".ko-toggle", "[class*='toggle']:not(button):not([class*='toggles'])", "[class*='switch']"],
    "segs": [".ko-seg", "[class*='-seg']:not([class*='-seg '] *)"],
    "sheetHeads": [".ko-sheet-head", ".ko-sheet > [class*='head']", ".ko-popover > [class*='head']",
                   ".ko-page > [class*='head']:not(.ko-header)", ".ko-dialog > [class*='head']"],
    "sliders": [".ko-slider", "[class*='slider']:not(.ko-slider *):not([class*='sliders'])"],
    "progress": [".ko-progress", "[class*='progress']:not(.ko-progress *)"],
    "disabledToken": True,
    "buttonHeightOk": [".kb-done"],   # keyboard strip: the Done key matches the 48px keys and field beside it
    "scrubbers": [".rd-scrub-track", ".rd-skim-track"],   # page-position scrubbers (reader chrome, skim)
    # overlays that are sheets but not panels with a header (keyboard, transient chrome)
    "sheetHeadOk": ["keyboard", "reader-chrome", "hl-popup"],
    # top-level screens: title in Playfair; every other screen/page/sheet/drawer header in Inter
    "topLevel": ["home", "library", "history", "stats", "welcome", "settings"],
    "playfairOk": ["book-details", "book-end", "sleep", "lockscreen"],     # book-title heroes / device-screen previews
    "playfairElOk": [".ss", ".sy-lk", ".rd-preset", ".rd-font"],
    "playfairMetricOk": [".st-time"],
}

# Screen CSS rules (css/screens/*.css) — see BRIEF.md › Design system › Screen CSS rules.
# A section opened by a comment containing "screen-specific:" and closed by "end screen-specific" (or the next
# "/* ---" / "/* ===" heading) may draw illustrations: raw radii / shadows in it are reported as info only.
SCREEN_SPECIFIC_OPEN = re.compile(r"screen-specific\s*:", re.I)
SCREEN_SPECIFIC_CLOSE = re.compile(r"end screen-specific|^/\*\s*(-{3,}|={3,})", re.I)
# component vocabulary: a screen rule that paints one of these (background / border / radius / shadow) re-defines a component
COMPONENT_WORDS = re.compile(r"(?:^|[\s>+~])(?:button|[\w.#:-]*(?:btn|chip|seg|toggle|pill|tag|badge)\b)[\w.:()-]*\s*$|\.ko-(?:btn|chip|seg|toggle|pill|row|card|icon-btn|tab|badge|check|radio|input|group)\b[^\s]*\s*$", re.I)
VISUAL_PROPS = {"background", "background-color", "border", "border-color", "border-radius", "box-shadow", "border-width", "border-style"}
KEY_COMPONENTS = ("toggle", "segmented", "sheet-header", "screen-header", "row-height", "slider", "chip", "radio", "checkbox", "button", "icon-button")
SEV_W = {"high": 100, "medium": 10, "low": 1}
RULE_TITLE = {
    "text-size": "Oversized text", "row-value-size": "Row value bigger/heavier than its label",
    "off-scale-size": "Font size not on the type scale", "font-size-count": "Too many font sizes in one state",
    "weight-bold": "Bold UI text", "weight-semibold-long": "Semibold on long text",
    "serif-ui": "Serif font on UI text", "italic-ui": "Italic UI text",
    "raw-colour": "Raw colour in screen CSS/JS", "offpalette": "Computed colour not in the palette",
    "selected-no-accent": "Selected state without --accent", "selected-eink": "Selected state invisible in e-ink",
    "swatch-eink": "Colour swatches identical in e-ink",
    "label-wrap": "Control label wraps", "chip-row-wrap": "Chip row wraps", "offscreen": "Element off screen",
    "overflow-child": "Child overflows its container", "overflow-text": "Text spills out of its box",
    "clipped-text": "Text clipped without ellipsis", "truncated": "Truncated text",
    "touch-target": "Hit area < 40px", "contrast": "Low text contrast", "contrast-eink": "Low contrast in e-ink grayscale",
    "mixed-button-size": "Buttons of different sizes together", "consistency": "Component rendered with different dimensions",
    "console-error": "JS error", "raw-font": "Raw font value in screen CSS", "raw-shape": "Raw radius/shadow in screen CSS",
    "component-redefinition": "Screen CSS re-defines a component", "row-label-wrap": "Row label wraps", "missing-glyph": "Missing/private-use glyph",
    "highlight-eink": "Highlight invisible in e-ink", "sheet-head": "Sheet header not the shared component",
    "title-font": "Title font breaks the title rule", "metric-font": "Metric not in Inter", "mixed-row-icons": "Rows with and without icons in one group", "slider-pattern": "Slider outside App.sliderRow",
}


def owners():
    """screen/overlay name -> js file that registers it"""
    out = {}
    for f in sorted((ROOT / "js/screens").glob("*.js")):
        for m in re.finditer(r"\b\w+\.(?:screen|overlay)\(\s*[\"'`]([\w-]+)[\"'`]", f.read_text()):
            out.setdefault(m.group(1), f"js/screens/{f.name}")
    return out


# ---------------------------------------------------------------------------------------------
# static scan: raw colours in css/screens/*.css and inline styles in js/screens/*.js
# ---------------------------------------------------------------------------------------------
COLOUR = re.compile(r"#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?)\([^)]*\)|(?<![\w-])(?:white|black)(?![\w-])")


def css_rules(text):
    """yield (selector, declarations, line) for innermost rules; comments stripped."""
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    stack, buf, start = [], "", 0
    for i, ch in enumerate(text):
        if ch == "{":
            stack.append((buf.strip(), i)); buf = ""
        elif ch == "}":
            if stack:
                selector, at = stack.pop()
                if buf.strip():
                    yield selector, buf, text.count("\n", 0, at) + 1
            buf = ""
        elif ch == ";" and not stack:
            buf = ""
        else:
            buf += ch


def css_rules_marked(text):
    """yield (selector, declarations, line, screen_specific) — like css_rules, plus the screen-specific section flag"""
    marks, inside = [], False
    for m in re.finditer(r"/\*(.*?)\*/", text, flags=re.S):
        c = m.group(0)
        if SCREEN_SPECIFIC_OPEN.search(c): inside = True
        elif SCREEN_SPECIFIC_CLOSE.search(c): inside = False
        marks.append((m.start(), inside))
    def flag_at(pos):
        f = False
        for at, v in marks:
            if at > pos: break
            f = v
        return f
    lines = text.split("\n")
    offs = [0]
    for l in lines: offs.append(offs[-1] + len(l) + 1)
    for selector, decls, line in css_rules(text):
        yield selector, decls, line, flag_at(offs[line - 1] if line - 1 < len(offs) else 0)


def static_scan():
    """Screen-CSS rules: tokens only (colours, font size/family/weight, radius, shadow) and no component re-definitions."""
    issues = []
    def add(rule, sev, rel, line, sel, msg):
        issues.append({"rule": rule, "sev": sev, "file": rel, "line": line, "sel": sel[:90], "msg": msg, "owner": rel, "static": True})
    TOKVAL = re.compile(r"var\(--[\w-]+\)")
    for f in sorted((ROOT / "css/screens").glob("*.css")):
        rel = f"css/screens/{f.name}"
        for selector, decls, line, special in css_rules_marked(f.read_text()):
            if selector.startswith("@") or re.fullmatch(r"(\d+%\s*,?\s*)+|from|to", selector.strip()): continue   # keyframe steps
            painted = set()
            for d in decls.split(";"):
                if ":" not in d: continue
                prop, val = d.split(":", 1)
                prop, val = prop.strip(), val.strip()
                if prop.startswith("--"): continue
                bare = re.sub(r"url\([^)]*\)", "", val)
                cols = COLOUR.findall(bare)
                if cols:
                    add("raw-colour", "medium", rel, line, selector, f"{prop}: {', '.join(cols)} — raw colour; use a theme token (css/tokens.css)")
                if "color-mix(" in bare and not special:
                    add("raw-colour", "low", rel, line, selector, f"{prop}: unnamed color-mix — name the blend in css/tokens.css")
                if prop == "font-size" and re.search(r"(?<![\w.])\d+(?:\.\d+)?px", TOKVAL.sub("", bare)) and not re.search(r"cqw|em\b|%", bare):
                    add("raw-font", "medium", rel, line, selector, f"font-size: {val} — use a --fs-* token")
                if prop == "font-family" and not re.fullmatch(r"(var\(--[\w-]+\)|inherit)", val):   # --font-* token or a runtime setting var
                    add("raw-font", "medium", rel, line, selector, f"font-family: {val} — use a --font-* token")
                if prop == "font-weight" and not re.fullmatch(r"(var\(--[\w-]+\)|inherit|normal)", val):   # --fw-* token or a runtime setting var
                    add("raw-font", "medium", rel, line, selector, f"font-weight: {val} — use a --fw-* token")
                if prop == "font" and (re.search(r"\d+px|\b[4-7]00\b", val) or '"' in val):
                    add("raw-font", "medium", rel, line, selector, f"font: {val} — use --fs/--fw/--font tokens")
                if prop == "border-radius":
                    rest = re.sub(r"\b0\b|50%|inherit", "", TOKVAL.sub("", val)).strip()
                    if rest:
                        if special or "cqw" in rest: add("raw-shape", "info", rel, line, selector, f"border-radius: {val} (screen-specific art)")
                        else: add("raw-shape", "medium", rel, line, selector, f"border-radius: {val} — use a --r-* token")
                if prop == "box-shadow":
                    rest = re.sub(r"\b0\b|\binset\b|\bnone\b|,", "", TOKVAL.sub("", val)).strip()
                    rest = re.sub(r"calc\([^)]*\)", "", rest).strip()
                    if rest:
                        if special: add("raw-shape", "info", rel, line, selector, f"box-shadow: {val} (screen-specific art)")
                        else: add("raw-shape", "medium", rel, line, selector, f"box-shadow: {val} — use a --shadow-*/--ring-* token")
                if prop in VISUAL_PROPS and val not in ("none", "0", "transparent"):
                    painted.add(prop)
            if painted and not special:
                last = selector.split(",")
                if any(COMPONENT_WORDS.search(x.strip()) for x in last):
                    add("component-redefinition", "medium", rel, line, selector,
                        f"paints a button/row/chip/seg/toggle-like element ({', '.join(sorted(painted))}) — use the component (or its --modifier) from css/components.css, or mark it /* screen-specific: why */")
    for f in sorted((ROOT / "js/screens").glob("*.js")):
        rel = f"js/screens/{f.name}"
        for n, line in enumerate(f.read_text().splitlines(), 1):
            for m in re.finditer(r"style=\\?[\"'][^\"']*?(#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\))", line):
                if re.search(r"cover|Cover|page|hl-", line): continue
                add("raw-colour", "medium", rel, n, "inline style", f"inline style colour {m.group(1)}")
    return [i for i in issues if i["sev"] != "info"]


# ---------------------------------------------------------------------------------------------
# browser pass
# ---------------------------------------------------------------------------------------------
NO_MOTION = "*,*::before,*::after{animation:none!important;transition:none!important}"


async def run_pass(browser, theme, size, demos, js, log):
    w, h = map(int, size.split("x"))
    ctx = await browser.new_context(viewport={"width": w, "height": h}, device_scale_factor=1)
    page = await ctx.new_page()
    errors = []
    page.on("pageerror", lambda e: errors.append(str(e)))
    page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
    await page.goto(f"file://{ROOT}/index.html?bare&theme={theme}&size={size}", wait_until="networkidle")
    await page.add_style_tag(content=NO_MOTION)
    await page.wait_for_function("window.lucide && window.App && App.demos.length > 0", timeout=30000)
    await page.evaluate("document.fonts.ready")
    results = []
    for i, d in enumerate(demos):
        errors.clear()
        try:
            await page.evaluate("""async (h) => {
                localStorage.removeItem('folio.store'); App.store = {};
                document.querySelectorAll('.ko-toast').forEach(t => t.remove());
                history.replaceState(null, '', h); App.fromHash(); App.render();
                await document.fonts.ready;
                await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
                await new Promise(r => setTimeout(r, 40));
                await document.fonts.ready;
            }""", d["hash"])
            r = await page.evaluate(js, CFG)
        except Exception as e:  # keep going; report it
            r = {"issues": [], "metrics": [], "sizes": {}, "distinct": 0, "owner": "?", "screen": "?"}
            errors.append(f"audit failed: {e}")
        r["demo"] = d; r["theme"] = theme; r["size"] = size; r["errors"] = list(errors)
        results.append(r)
        if (i + 1) % 25 == 0: log(f"  {theme}@{size}: {i + 1}/{len(demos)}")
    await ctx.close()
    return results


async def screenshots(browser, picks):
    """picks: list of (fname, theme, size, hash, [locs])"""
    out = []
    by = collections.defaultdict(list)
    for p in picks: by[(p[1], p[2])].append(p)
    for (theme, size), items in by.items():
        w, h = map(int, size.split("x"))
        ctx = await browser.new_context(viewport={"width": w, "height": h})
        page = await ctx.new_page()
        await page.goto(f"file://{ROOT}/index.html?bare&theme={theme}&size={size}", wait_until="networkidle")
        await page.add_style_tag(content=NO_MOTION + ".qa-mark{outline:2px dashed #ff2d55!important;outline-offset:1px!important}")
        await page.wait_for_function("window.lucide && window.App")
        for fname, _, _, hsh, locs in items:
            await page.evaluate("""async ([h, locs]) => {
                history.replaceState(null, '', h); App.fromHash(); App.render();
                await document.fonts.ready; await new Promise(r => setTimeout(r, 60));
                for (const l of locs) { try { const e = document.querySelector(l); if (e) { e.classList.add('qa-mark'); e.scrollIntoView({block: 'center', inline: 'nearest'});
                    for (let c = e; c; c = c.parentElement) if (!/auto|scroll/.test(getComputedStyle(c).overflowX) || c.id === 'stage') c.scrollLeft = 0; } } catch {} }
            }""", [hsh, locs])
            await page.locator("#screen").screenshot(path=str(SHOTS / fname))
            out.append(fname)
        await ctx.close()
    return out


# ---------------------------------------------------------------------------------------------
# aggregation + report
# ---------------------------------------------------------------------------------------------
def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:40]


def aggregate(results, own):
    groups = {}   # key -> aggregated issue
    sizes_by_state = []
    metrics = collections.defaultdict(lambda: collections.defaultdict(list))  # kind/ctx -> key -> occurrences
    for r in results:
        d = r["demo"]
        state_tag = f"{r['theme']}@{r['size']}"
        for e in r["errors"]:
            r["issues"].append({"rule": "console-error", "sev": "high", "sel": "-", "loc": "", "owner": r["owner"],
                                "layer": "-", "msg": e[:200], "text": ""})
        if r["distinct"] > 7 and r.get("screen") != "catalog":   # the catalog shows the whole type scale on purpose
            r["issues"].append({"rule": "font-size-count", "sev": "medium", "sel": "(whole state)", "loc": "", "owner": r["owner"],
                                "layer": "-", "msg": f"{r['distinct']} distinct font sizes: " + ", ".join(
                                    f"{k}px×{v}" for k, v in sorted(r["sizes"].items(), key=lambda x: float(x[0]))), "text": ""})
        sizes_by_state.append({"group": d["group"], "label": d["label"], "hash": d["hash"], "theme": r["theme"], "size": r["size"],
                               "distinct": r["distinct"], "sizes": r["sizes"]})
        for i in r["issues"]:
            # normalise the message so the same problem in other themes/sizes merges
            norm = i["msg"]
            if i["rule"] in ("contrast", "contrast-eink", "offpalette"):
                norm = re.sub(r"[\d.]+:1", "", norm)
            if i["rule"] in ("row-value-size", "text-size", "truncated", "selected-no-accent", "row-label-wrap", "missing-glyph"):
                norm = re.sub(r"\"[^\"]*\"", "", norm)
            if i["rule"] in ("label-wrap", "offscreen", "overflow-child", "overflow-text", "clipped-text", "mixed-button-size", "chip-row-wrap", "touch-target", "font-size-count"):
                norm = ""
            tokpair = i["rule"] in ("contrast", "contrast-eink") and i.get("fgTok") and i.get("bgTok")
            if tokpair:  # same token pair everywhere = one token-level finding
                key = (i["rule"], "tokens", i["fgTok"] + " on " + i["bgTok"], r["theme"])
            elif i["rule"] in ("contrast", "contrast-eink", "offpalette"):
                key = (i["rule"], i["owner"], i["sel"], i.get("fg", "") + i.get("bg", "") + str(i.get("value", "")) + r["theme"])
            else:
                key = (i["rule"], i["owner"], i["sel"], norm)
            g = groups.get(key)
            if not g:
                g = groups[key] = {**{k: v for k, v in i.items() if k not in ("loc",)}, "file": own.get(i["owner"], "core/" + i["owner"]),
                                   "area": d["group"], "areas": set(), "demos": [], "states": set(), "locs": [], "sevs": set(), "examples": []}
                if tokpair:
                    g.update(owner="tokens", file="css/tokens.css", sel=f"{i['fgTok']} on {i['bgTok']} ({r['theme']})")
            g["areas"].add(d["group"])
            ex = f"{i['owner']} `{i['sel']}`"
            if tokpair and ex not in g["examples"] and len(g["examples"]) < 12: g["examples"].append(ex)
            if d["hash"] not in g["demos"]: g["demos"].append(d["hash"])
            g["states"].add(state_tag)
            g["sevs"].add(i["sev"])
            if len(g["locs"]) < 1: g["locs"].append({"hash": d["hash"], "theme": r["theme"], "size": r["size"], "loc": i.get("loc", "")})
            # keep the worst message (e.g. lowest contrast)
            if SEV_W[i["sev"]] > SEV_W[g["sev"]]: g.update(sev=i["sev"], msg=i["msg"], text=i.get("text", ""))
        for m in r["metrics"]:
            metrics[(m["kind"], m["ctx"])][m["key"]].append({"sel": m["sel"], "owner": m["owner"], "hash": d["hash"], "area": d["group"], "loc": m["loc"], "theme": r["theme"], "size": r["size"]})
    # consistency: variants per component kind (600x800 only so the landscape pass doesn't double count)
    consistency = []
    for (kind, ctx), variants in sorted(metrics.items()):
        v = {k: [o for o in occ if o["size"] == "600x800" and o["theme"] == "dark"] or occ for k, occ in variants.items()}
        if len(v) < 2:
            consistency.append({"kind": kind, "ctx": ctx, "variants": [{"key": k, "count": len(o), "sels": sorted({x["sel"] for x in o})[:6]} for k, o in v.items()]})
            continue
        ranked = sorted(v.items(), key=lambda kv: -len(kv[1]))
        consistency.append({"kind": kind, "ctx": ctx, "variants": [{"key": k, "count": len(o), "sels": sorted({x["sel"] for x in o})[:6],
                                                                     "owners": sorted({x["owner"] for x in o})} for k, o in ranked]})
        dominant = ranked[0][0]
        def on_scale(k):
            if kind == "icon":
                m = re.match(r"(\d+)px sw([\d.]+)px", k)
                return bool(m) and int(m.group(1)) in CFG["iconScale"] and float(m.group(2)) in CFG["strokeScale"]
            if kind == "progress": return k in CFG["progressScale"]
            if kind == "chip": return k in CFG["chipScale"]
            if kind == "section-label": return k in CFG["labelScale"]
            return False
        if kind in ("icon", "section-label", "button") and len(ranked) > 6: pass
        if len(ranked[0][1]) < 2: continue
        for k, occ in ranked[1:]:
            if on_scale(k): continue
            sels = sorted({x["sel"] for x in occ})
            o = occ[0]
            key = ("consistency", kind, ctx, k)
            groups[key] = {"rule": "consistency", "sev": "medium" if kind in KEY_COMPONENTS else "low",
                           "sel": ", ".join(sels[:3]) + (f" +{len(sels) - 3}" if len(sels) > 3 else ""), "owner": ", ".join(sorted({x["owner"] for x in occ})[:4]),
                           "layer": ctx, "file": own.get(o["owner"], "core/" + o["owner"]), "area": o["area"], "areas": {x["area"] for x in occ},
                           "msg": f"{kind} ({ctx}) rendered as `{k}` ×{len(occ)}; the common variant is `{dominant}` ×{len(ranked[0][1])}",
                           "text": "", "demos": sorted({x["hash"] for x in occ}), "states": {f"{o['theme']}@{o['size']}"},
                           "locs": [{"hash": o["hash"], "theme": o["theme"], "size": o["size"], "loc": o["loc"]}], "sevs": set(), "examples": []}
    out = list(groups.values())
    for g in out:
        g["states"] = sorted(g["states"]); g["areas"] = sorted(g["areas"]); g.pop("sevs", None)
        g["score"] = SEV_W[g["sev"]] * math.sqrt(len(g["demos"]))
    out.sort(key=lambda g: (-SEV_W[g["sev"]], g["area"], g["file"], g["rule"], -len(g["demos"])))
    return out, sizes_by_state, consistency


def md_report(issues, static, sizes, consistency, shots, demos, passes, elapsed, own):
    L = []
    areas = list(dict.fromkeys(d["group"] for d in demos))
    allissues = issues + static
    L.append("# Folio design audit\n")
    L.append(f"Generated by `tools/audit.py` — {len(demos)} states × passes {', '.join(passes)} in {elapsed:.0f}s. "
             f"Each finding is merged across themes/sizes/states; *states* lists the passes it occurred in, *demos* the number of designer states.\n")
    L.append("Rerun: `tools/.venv/bin/python tools/audit.py [--group Reader] [--match typeset] [--quick]`\n")
    # summary table
    L.append("## Summary per area\n")
    rules_order = list(RULE_TITLE)
    L.append("| Area | States | High | Medium | Low | Top rules |")
    L.append("|---|---|---|---|---|---|")
    for a in areas + ["(static CSS/JS scan)"]:
        its = [i for i in allissues if (a in i.get("areas", [])) or (a.startswith("(static") and i.get("static"))]
        c = collections.Counter(i["sev"] for i in its)
        top = collections.Counter(i["rule"] for i in its if i["sev"] in ("high", "medium")).most_common(4)
        n = sum(1 for d in demos if d["group"] == a)
        L.append(f"| {a} | {n or '-'} | {c['high']} | {c['medium']} | {c['low']} | {', '.join(f'{r} {k}' for r, k in top)} |")
    L.append("")
    L.append("### Findings per rule\n")
    L.append("| Rule | High | Medium | Low |")
    L.append("|---|---|---|---|")
    for r in rules_order:
        c = collections.Counter(i["sev"] for i in allissues if i["rule"] == r)
        if sum(c.values()): L.append(f"| {r} — {RULE_TITLE[r]} | {c['high']} | {c['medium']} | {c['low']} |")
    L.append("")
    # top 15
    L.append("## Top 15\n")
    top = sorted(issues, key=lambda g: -g["score"])[:15]
    for n, g in enumerate(top, 1):
        L.append(f"{n}. **[{g['sev']}] {RULE_TITLE.get(g['rule'], g['rule'])}** — `{g['sel']}` ({g['file']}, {len(g['demos'])} states) — {g['msg']}"
                 + (f" — “{g['text'][:40]}”" if g.get("text") else "") + f" — e.g. `{g['demos'][0]}`")
    L.append("")
    if shots:
        L.append("Screenshots (offending elements outlined in dashed pink): " + ", ".join(f"`shots/{s}`" for s in shots) + "\n")
    # by severity, then file/screen
    for sev in ("high", "medium", "low"):
        its = [i for i in allissues if i["sev"] == sev]
        L.append(f"## {sev.capitalize()} ({len(its)})\n")
        byfile = collections.defaultdict(list)
        for i in its: byfile[i.get("file") or i["owner"]].append(i)
        for f in sorted(byfile):
            L.append(f"### {f}\n")
            for i in sorted(byfile[f], key=lambda x: (x["rule"], x.get("owner", ""), x["sel"])):
                if i.get("static"):
                    L.append(f"- `{i['rule']}` {f}:{i['line']} `{i['sel']}` — {i['msg']}")
                else:
                    extra = f" “{i['text'][:40]}”" if i.get("text") and i["rule"] not in ("font-size-count",) else ""
                    more = f" (+{len(i['demos']) - 1} more)" if len(i["demos"]) > 1 else ""
                    exs = ("; seen in " + ", ".join(i["examples"][:6]) + (" …" if len(i["examples"]) > 6 else "")) if i.get("examples") else ""
                    L.append(f"- `{i['rule']}` **{i['owner']}** `{i['sel']}` — {i['msg']}{extra}{exs} — `{i['demos'][0]}`{more} [{', '.join(i['states'])}]")
            L.append("")
    vr = TOOLS / "visual-review.md"
    if vr.exists():
        L.append(vr.read_text().rstrip() + "\n")
    # font size distribution
    L.append("## Font-size distribution (dark 600x800)\n")
    L.append("| Area | State | # sizes | Sizes (px × count) |")
    L.append("|---|---|---|---|")
    for s in sizes:
        if s["theme"] != "dark" or s["size"] != "600x800": continue
        L.append(f"| {s['group']} | {s['label']} | {s['distinct']}{' ⚠' if s['distinct'] > 7 else ''} | "
                 + ", ".join(f"{k}×{v}" for k, v in sorted(s["sizes"].items(), key=lambda x: float(x[0]))) + " |")
    L.append("")
    L.append("## Component variants (dark 600x800)\n")
    for c in consistency:
        if len(c["variants"]) < 2 and c["kind"] not in ("toggle", "segmented", "sheet-header"): continue
        L.append(f"**{c['kind']}** ({c['ctx']}): " + "; ".join(f"`{v['key']}` ×{v['count']} ({', '.join(v['sels'][:3])})" for v in c["variants"][:8])
                 + (f"; … {len(c['variants']) - 8} more" if len(c["variants"]) > 8 else "") + "\n")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--group", help="only demos whose group contains this (case-insensitive)")
    ap.add_argument("--match", help="only demos whose label or hash contains this")
    ap.add_argument("--passes", default="dark@600x800,paper@600x800,dark@1000x750")
    ap.add_argument("--quick", action="store_true", help="dark@600x800 only, no screenshots")
    ap.add_argument("--no-shots", action="store_true")
    ap.add_argument("--shots", type=int, default=14, help="number of qa-*.png screenshots")
    ap.add_argument("--out", default=str(TOOLS), help="directory for audit-report.md / audit.json")
    a = ap.parse_args()
    passes = ["dark@600x800"] if a.quick else a.passes.split(",")
    js = (TOOLS / "audit.js").read_text()
    own = owners()
    t0 = time.time()
    log = lambda s: print(s, file=sys.stderr, flush=True)

    async def go():
        async with async_playwright() as p:
            browser = await p.chromium.launch(executable_path=CHROME, args=["--disable-gpu", "--hide-scrollbars"])
            page = await browser.new_page()
            await page.goto(f"file://{ROOT}/index.html?bare", wait_until="networkidle")
            await page.wait_for_function("window.App && App.demos.length > 0")
            demos = await page.evaluate("App.demos")
            await page.close()
            if a.group: demos = [d for d in demos if a.group.lower() in d["group"].lower()]
            if a.match: demos = [d for d in demos if a.match.lower() in (d["label"] + d["hash"]).lower()]
            log(f"{len(demos)} states × {len(passes)} passes")
            res = await asyncio.gather(*[run_pass(browser, *ps.split("@"), demos, js, log) for ps in passes])
            results = [r for rr in res for r in rr]
            issues, sizes, consistency = aggregate(results, own)
            shots = []
            if not a.quick and not a.no_shots and a.shots:
                for old in SHOTS.glob("qa-*.png"): old.unlink()
                picks, seen = [], set()
                for g in sorted(issues, key=lambda g: -g["score"]):
                    if g["sev"] != "high" and len(picks) >= a.shots // 2: continue
                    l = g["locs"][0] if g["locs"] else None
                    if not l or not l["loc"] or (g["rule"], g["owner"]) in seen: continue
                    seen.add((g["rule"], g["owner"]))
                    # outline every element of the same state with the same rule
                    fname = f"qa-{len(picks) + 1:02d}-{g['rule']}-{slug(g['owner'])}.png"
                    picks.append((fname, l["theme"], l["size"], l["hash"], [l["loc"]]))
                    g["shot"] = f"shots/{fname}"
                    if len(picks) >= a.shots: break
                shots = await screenshots(browser, picks)
            await browser.close()
            return demos, issues, sizes, consistency, shots

    demos, issues, sizes, consistency, shots = asyncio.run(go())
    static = static_scan() if not (a.group or a.match) else [s for s in static_scan()]
    elapsed = time.time() - t0
    out = Path(a.out)
    (out / "audit.json").write_text(json.dumps({"passes": passes, "states": len(demos), "issues": issues, "static": static,
                                                  "font_sizes": sizes, "components": consistency, "shots": shots}, indent=1, default=list))
    (out / "audit-report.md").write_text(md_report(issues, static, sizes, consistency, shots, demos, passes, elapsed, own))
    c = collections.Counter(i["sev"] for i in issues + static)
    print(f"{len(demos)} states, {elapsed:.0f}s — high {c['high']}, medium {c['medium']}, low {c['low']} → {out / 'audit-report.md'}")


if __name__ == "__main__":
    main()
