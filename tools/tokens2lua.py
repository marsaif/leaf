#!/usr/bin/env python3
"""Generate koreader/leaf/tokens.lua from prototype/css/tokens.css (the single source of truth).

    python3 tools/tokens2lua.py            # write the Lua file + print the e-ink contrast report
    python3 tools/tokens2lua.py --check    # exit 1 if the Lua file is out of date (no write)

What becomes what:
  * px lengths            -> T.size[name] (CSS px at a 600px-wide screen; KOReader's
                             Screen:scaleBySize() uses the same base, so T.px(name) is exact)
  * unitless / em numbers -> T.num[name]   (weights, line heights, strokes, z, tracking in em)
  * font families         -> T.family[name] (first family of the stack)
  * colours               -> T.colors[theme][name] = {rgb = 0xRRGGBB, gray = 0xGG}
                             var() and color-mix() are resolved per theme; alpha is flattened over
                             --surface (UI) or --page (reading page / highlight tokens), because
                             e-ink has no transparency. gray = Rec.601 luma (what KOReader's
                             ColorRGB32:getColor8 does) rounded to the 16 levels of an e-ink panel.
  * rings / edge bars     -> T.rings[name] = { {inset, x, y, spread, color}, ... } (no blur parts)
  * everything else (blurred shadows, motion) is listed at the end of the Lua file as skipped,
    with the reason, so nothing disappears silently.
Every token keeps its tokens.css comment, which is the spec.
"""
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "prototype/css/tokens.css"
OUT = REPO / "koreader/leaf/tokens.lua"

THEMES = ("paper", "dark")
# alpha colours are flattened over this token (e-ink has no transparency)
PAGE_PREFIXES = ("hl-", "page-", "sel", "scan-")


def parse(css):
    """-> {block: [(name, value, comment)]}, blocks: root, dark, paper, derived."""
    blocks, cur = {}, None
    names = {":root": "root", ".theme-dark": "dark", ".theme-paper": "paper", ".theme-dark, .theme-paper": "derived"}
    for line in css.splitlines():
        s = line.strip()
        m = re.match(r"^([^{}/][^{]*?)\s*\{$", s)
        if m:
            cur = names.get(m.group(1))
            if cur:
                blocks.setdefault(cur, [])
            continue
        if s.startswith("}"):
            cur = None
            continue
        m = re.match(r"^--([a-z0-9-]+):\s*(.+?);\s*(?:/\*\s*(.*?)\s*\*/)?$", s)
        if m and cur:
            blocks[cur].append((m.group(1), m.group(2), m.group(3) or ""))
    return blocks


# ---------------------------------------------------------------- colours
def hex_rgba(h):
    h = h.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 1.0)


def luma(rgb):
    r, g, b = rgb[:3]
    return (r * 4897 + g * 9617 + b * 1868) >> 14  # ffi/blitbuffer.lua ColorRGB32:getColor8


def quant16(g):
    return min(255, round(g / 17) * 17)


def flatten(c, base):
    r, g, b, a = c
    if a >= 1:
        return (r, g, b, 1.0)
    br, bg, bb, _ = base
    return (round(r * a + br * (1 - a)), round(g * a + bg * (1 - a)), round(b * a + bb * (1 - a)), 1.0)


class Theme:
    """Resolves colour values for one theme (root + theme block + derived block)."""

    def __init__(self, decls):
        self.raw = decls  # name -> value
        self.cache = {}

    def color(self, name, stack=()):
        if name in self.cache:
            return self.cache[name]
        if name in stack or name not in self.raw:
            return None
        c = self.value(self.raw[name], stack + (name,))
        self.cache[name] = c
        return c

    def value(self, v, stack=()):
        v = v.strip()
        if v == "transparent":
            return (0, 0, 0, 0.0)
        if v.startswith("#"):
            return hex_rgba(v)
        m = re.fullmatch(r"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)", v)
        if m:
            return (int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4) or 1))
        m = re.fullmatch(r"var\(--([a-z0-9-]+)\)", v)
        if m:
            return self.color(m.group(1), stack)
        m = re.fullmatch(r"color-mix\(in srgb,\s*(.+?)\s+([\d.]+)%,\s*(.+)\)", v)
        if m:
            a, p, b = self.value(m.group(1), stack), float(m.group(2)) / 100, self.value(m.group(3), stack)
            if a is None or b is None:
                return None
            # CSS color-mix interpolates premultiplied colours
            aa, ba = a[3] * p, b[3] * (1 - p)
            alpha = aa + ba
            if alpha == 0:
                return (0, 0, 0, 0.0)
            rgb = tuple(round((a[i] * aa + b[i] * ba) / alpha) for i in range(3))
            return rgb + (alpha,)
        return None


# ---------------------------------------------------------------- lengths / shadows
def length(v):
    m = re.fullmatch(r"(-?[\d.]+)px", v.strip())
    return float(m.group(1)) if m else None


def num(v):
    try:
        return float(v)
    except ValueError:
        m = re.fullmatch(r"(-?[\d.]+)em", v.strip())
        return float(m.group(1)) if m else None


def split_top(v):
    parts, depth, cur = [], 0, ""
    for ch in v:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
        else:
            cur += ch
    parts.append(cur.strip())
    return parts


def shadow(v, sizes):
    """-> list of ring parts, or None if it has blur (a real drop shadow) / can't be parsed."""
    def resolve_len(t):
        t = re.sub(r"var\(--([a-z0-9-]+)\)", lambda m: f"{sizes[m.group(1)]}px" if m.group(1) in sizes else m.group(0), t)
        m = re.fullmatch(r"calc\((-?[\d.]+)\s*\*\s*(-?[\d.]+)px\)", t)
        if m:
            return float(m.group(1)) * float(m.group(2))
        return 0.0 if t == "0" else length(t)

    out = []
    for part in split_top(v):
        part = re.sub(r"var\(--([a-z0-9-]+)\)", lambda m: f"{lua_num(sizes[m.group(1)])}px" if m.group(1) in sizes else m.group(0), part)
        toks = re.findall(r"calc\([^)]*\)|var\([^)]*\)|rgba?\([^)]*\)|#[0-9a-fA-F]+|\S+", part)
        inset = toks and toks[0] == "inset"
        toks = toks[1:] if inset else toks
        color = toks[-1]
        lens = [resolve_len(t) for t in toks[:-1]]
        if any(x is None for x in lens) or len(lens) < 2:
            return None
        x, y = lens[0], lens[1]
        blur = lens[2] if len(lens) > 2 else 0
        spread = lens[3] if len(lens) > 3 else 0
        if blur:
            return None
        m = re.fullmatch(r"var\(--([a-z0-9-]+)\)", color)
        out.append({"inset": bool(inset), "x": x, "y": y, "spread": spread,
                    "color": m.group(1) if m else color})
    return out


# ---------------------------------------------------------------- Lua output
def lua_num(x):
    return str(int(x)) if float(x).is_integer() else repr(float(x))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_comment(c):
    return f" -- {c}" if c else ""


def build():
    blocks = parse(SRC.read_text())
    root, derived = blocks["root"], blocks["derived"]
    all_decls = root + blocks["dark"] + blocks["paper"] + derived
    comments = {n: c for n, _, c in all_decls}
    theme_comments = {t: {n: c for n, _, c in root + blocks[t] + derived} for t in THEMES}

    sizes, nums, families, skipped = {}, {}, {}, []
    color_names, ring_decls = [], []
    for n, v, c in root + derived:
        if n.startswith("font-"):
            families[n[5:]] = v.split(",")[0].strip().strip('"')
        elif length(v) is not None:
            sizes[n] = length(v)
        elif num(v) is not None:
            nums[n] = num(v)
        elif re.fullmatch(r"var\(--([a-z0-9-]+)\)", v) and re.fullmatch(r"var\(--([a-z0-9-]+)\)", v).group(1) in sizes:
            sizes[n] = sizes[v[6:-1]]  # alias like --row-h: var(--h-row)
        elif n.startswith(("dur", "ease")):
            skipped.append((n, "motion: e-ink UI does not animate"))
        elif v.startswith(("#", "rgb", "color-mix", "transparent")) or re.fullmatch(r"var\(--[a-z0-9-]+\)", v):
            color_names.append(n)
        else:
            ring_decls.append((n, v))
    for theme in ("dark", "paper"):
        for n, v, c in blocks[theme]:
            if n.startswith(("shadow", "ring")) or " 0 " in f" {v} ":
                ring_decls.append((n, v))
            elif n not in color_names:
                color_names.append(n)

    themes = {}
    for t in THEMES:
        decls = {n: v for n, v, _ in root + blocks[t] + derived}
        themes[t] = Theme(decls)

    colors = {t: {} for t in THEMES}
    for t in THEMES:
        th = themes[t]
        surface, page = th.color("surface"), th.color("page")
        for n in color_names:
            if n not in th.raw:
                continue  # theme-only token (e.g. paper's shadow-key-paper)
            c = th.color(n)
            if c is None:
                skipped.append((n, f"unresolved colour in {t}: {th.raw[n]}"))
                continue
            base = page if n.startswith(PAGE_PREFIXES) else surface
            flat = flatten(c, base)
            colors[t][n] = {"rgb": (flat[0] << 16) | (flat[1] << 8) | flat[2],
                            "gray": quant16(luma(flat)), "alpha": c[3]}

    rings, seen = {}, set()
    for n, v in ring_decls:
        if n in seen:
            continue
        seen.add(n)
        parts = shadow(v, sizes)
        if parts is None:
            skipped.append((n, "drop shadow (has blur): e-ink draws an outline instead (--shadow under .eink = 1px --border-strong)"))
        else:
            rings[n] = parts
    # dedupe skipped
    skipped = list(dict.fromkeys(skipped))
    return sizes, nums, families, colors, rings, skipped, comments, theme_comments


def render(sizes, nums, families, colors, rings, skipped, comments, theme_comments):
    L = ["--[[",
         "    GENERATED by tools/tokens2lua.py from prototype/css/tokens.css: do not edit by hand.",
         "    Leaf design tokens for KOReader. Comments are the spec (copied from tokens.css).",
         "",
         "    T.px(name)         -> scaled size in screen pixels (CSS px are KOReader 600px-base units) x T.scale",
         "    T.fs(name)         -> font size for Font:getFace (unscaled: getFace scales it) x T.scale",
         "    T.scale            -> global UI scale, from the KOReader setting leaf_ui_scale (default 1)",
         "    T.size[name]       -> unscaled CSS px (font sizes go to Font:getFace unscaled: it scales)",
         "    T.color(name)      -> Blitbuffer colour for the current screen (grey on e-ink, RGB on colour)",
         "    T.gray(name)       -> the 16-level grey (0-255) as a number",
         "    T.theme            -> \"paper\" (Leaf Dark on e-ink = KOReader night mode over Paper)",
         "--]]",
         "local T = { theme = \"paper\", scale = 1 }", ""]
    L.append("-- font families (first family of each CSS stack)")
    L.append("T.family = {")
    for k, v in families.items():
        L.append(f"    [{lua_str(k)}] = {lua_str(v)},{lua_comment(comments.get('font-' + k))}")
    L += ["}", "", "-- lengths in CSS px (600px-wide base)", "T.size = {"]
    for k, v in sizes.items():
        L.append(f"    [{lua_str(k)}] = {lua_num(v)},{lua_comment(comments.get(k))}")
    L += ["}", "", "-- unitless numbers: weights, line heights, strokes, z order; tracking (ls-*) in em", "T.num = {"]
    for k, v in nums.items():
        L.append(f"    [{lua_str(k)}] = {lua_num(v)},{lua_comment(comments.get(k))}")
    L += ["}", "",
          "-- colours per theme: rgb = 0xRRGGBB (alpha flattened), gray = 16-level e-ink grey, alpha = CSS alpha",
          "T.colors = {"]
    for t in THEMES:
        L.append(f"    {t} = {{")
        for k, c in colors[t].items():
            alpha = "" if c["alpha"] >= 1 else f", alpha = {round(c['alpha'], 3)}"
            L.append(f"        [{lua_str(k)}] = {{ rgb = 0x{c['rgb']:06x}, gray = 0x{c['gray']:02x}{alpha} }},{lua_comment(theme_comments[t].get(k))}")
        L.append("    },")
    L += ["}", "",
          "-- rings and edge bars (box-shadows without blur): parts drawn as borders / bars;",
          "-- color is a token name in T.colors (or a literal CSS colour)",
          "T.rings = {"]
    for k, parts in rings.items():
        ps = ", ".join("{ inset = %s, x = %s, y = %s, spread = %s, color = %s }" % (
            str(p["inset"]).lower(), lua_num(p["x"]), lua_num(p["y"]), lua_num(p["spread"]), lua_str(p["color"])) for p in parts)
        L.append(f"    [{lua_str(k)}] = {{ {ps} }},{lua_comment(comments.get(k))}")
    L += ["}", "", "-- not ported (and why)", "T.skipped = {"]
    for k, why in skipped:
        L.append(f"    [{lua_str(k)}] = {lua_str(why)},")
    L += ["}", ""] + r'''-- ---------------------------------------------------------------- accessors
local function screen() return require("device").screen end

function T.px(name)
    local v = T.size[name]
    assert(v, "leaf tokens: unknown size " .. tostring(name))
    if v == 0 then return 0 end
    return screen():scaleBySize(v * T.scale)
end

function T.fs(name)
    local v = T.size[name]
    assert(v, "leaf tokens: unknown size " .. tostring(name))
    return v * T.scale
end

local function entry(name, theme)
    local c = T.colors[theme or T.theme][name]
    assert(c, "leaf tokens: unknown colour " .. tostring(name))
    return c
end

function T.gray(name, theme) return entry(name, theme).gray end

function T.color(name, theme)
    local c = entry(name, theme)
    local Blitbuffer = require("ffi/blitbuffer")
    if screen():isColorEnabled() then
        return Blitbuffer.ColorRGB32(bit.rshift(c.rgb, 16), bit.band(bit.rshift(c.rgb, 8), 0xFF), bit.band(c.rgb, 0xFF), 0xFF)
    end
    return Blitbuffer.Color8(c.gray)
end

return T
'''.rstrip("\n").split("\n")
    return "\n".join(L) + "\n"


# ---------------------------------------------------------------- contrast report
def rel_lum(g):
    s = g / 255
    return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4


def contrast(a, b):
    la, lb = rel_lum(a) + 0.05, rel_lum(b) + 0.05
    return max(la, lb) / min(la, lb)


TEXTS = [("text", 4.5), ("text-2", 4.5), ("text-3", 4.5), ("accent", 3.0), ("danger", 3.0), ("disabled", None)]
BGS = ["bg", "bg-raised", "surface", "surface-2", "surface-3"]
PAIRS = [("accent-ink", "accent", 4.5), ("danger-ink", "danger", 4.5), ("page-ink", "page", 4.5), ("page-2", "page", 4.5)]


def report(colors):
    """Contrast of the e-ink greys (paper theme, and its night-mode inversion = same ratios)."""
    c = colors["paper"]
    warn = 0
    print("e-ink contrast, paper theme (16-level greys; night mode inverts, ratios unchanged)")
    print("  " + "".ljust(10) + "".join(b.ljust(11) for b in BGS))
    for t, need in TEXTS:
        row = []
        for b in BGS:
            r = contrast(c[t]["gray"], c[b]["gray"])
            bad = need and r < need
            warn += bool(bad)
            row.append((f"{r:4.1f}" + ("!" if bad else " ")).ljust(11))
        print("  " + t.ljust(10) + "".join(row) + (f"(min {need})" if need else "(disabled: no minimum)"))
    for fg, bg, need in PAIRS:
        r = contrast(c[fg]["gray"], c[bg]["gray"])
        warn += r < need
        print(f"  {fg} on {bg}: {r:.1f}" + ("  ! below " + str(need) if r < need else ""))
    same = [(a, b) for a, b in [("bg", "surface"), ("surface", "surface-2"), ("surface-2", "surface-3"), ("border", "surface"), ("accent", "text"), ("accent", "text-2"), ("accent", "text-3"), ("danger", "text-2")]
            if c[a]["gray"] == c[b]["gray"]]
    for a, b in same:
        print(f"  note: --{a} and --{b} are the same grey (0x{c[a]['gray']:02x}) on e-ink: they must differ by weight / shape, not colour")
    print(f"  {warn} pair(s) below minimum (! marks them; min 4.5 text, 3.0 accent/danger as non-text markers)")
    return warn


def main():
    sizes, nums, families, colors, rings, skipped, comments, theme_comments = build()
    lua = render(sizes, nums, families, colors, rings, skipped, comments, theme_comments)
    if "--check" in sys.argv:
        current = OUT.read_text() if OUT.exists() else ""
        if current != lua:
            print(f"{OUT.relative_to(REPO)} is out of date: run tools/tokens2lua.py")
            sys.exit(1)
        print("tokens.lua is up to date")
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(lua)
    n_col = sum(len(v) for v in colors.values())
    print(f"wrote {OUT.relative_to(REPO)}: {len(sizes)} sizes, {len(nums)} numbers, {len(families)} families, "
          f"{n_col} colours ({', '.join(f'{t} {len(colors[t])}' for t in THEMES)}), {len(rings)} rings, {len(skipped)} skipped")
    report(colors)


if __name__ == "__main__":
    main()
