#!/usr/bin/env python3
"""Deterministic screenshots of every App.demos state, for visual regression (see tools/diff.py).

  tools/.venv/bin/python tools/snap.py                       # -> shots/current/
  tools/.venv/bin/python tools/snap.py --out baseline        # -> shots/baseline/ (the reference)
  tools/.venv/bin/python tools/snap.py --match typeset       # subset (label/hash substring)
  tools/.venv/bin/python tools/snap.py --group Reader --modes dark
  tools/.venv/bin/python tools/snap.py --out baseline --root .backup-before-cleanup   # rebuild the reference from the backup

Modes: dark (dark 600x800), paper (paper 600x800), eink (paper + e-ink preview 600x800).
Determinism: fixed clock (2026-11-19 10:30), animations/transitions/caret off, fresh localStorage per
state, fonts + lucide icons settled, toasts removed. Files: shots/<out>/<mode>/<key>.png plus
shots/<out>/manifest.json (key -> group, label, hash). The key is derived from the hash, so new demo
states never shift existing file names.
"""
import argparse, asyncio, datetime, hashlib, json, re, sys
from pathlib import Path

from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent.parent
CHROME = "/usr/bin/google-chrome"
MODES = {"dark": ("dark", False), "paper": ("paper", False), "eink": ("paper", True)}
FREEZE = "*,*::before,*::after{animation:none!important;transition:none!important;caret-color:transparent!important}"
CLOCK = datetime.datetime(2026, 11, 19, 10, 30, 0)


def key_of(d):
    slug = re.sub(r"[^a-z0-9]+", "-", (d["group"] + " " + d["label"]).lower()).strip("-")[:48]
    return f"{slug}-{hashlib.sha1(d['hash'].encode()).hexdigest()[:6]}"


async def settle(page, h):
    await page.evaluate("""async (h) => {
        localStorage.removeItem('folio.store'); App.store = {};
        App.state = { stack: [] };
        document.querySelectorAll('.ko-toast').forEach(t => t.remove());
        history.replaceState(null, '', h); App.fromHash(); App.render();
        await document.fonts.ready;
        await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
        await new Promise(r => setTimeout(r, 60));
        await document.fonts.ready;
        document.querySelectorAll('.ko-toast').forEach(t => t.remove());
        if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    }""", h)


async def fresh(page, url):
    await page.goto(url, wait_until="networkidle")
    await page.add_style_tag(content=FREEZE)
    await page.wait_for_function("window.lucide && window.App && App.demos.length > 0", timeout=30000)
    await page.evaluate("document.fonts.ready")


async def run_mode(browser, mode, demos, outdir, log, root):
    theme, eink = MODES[mode]
    ctx = await browser.new_context(viewport={"width": 600, "height": 800}, device_scale_factor=1)
    page = await ctx.new_page()
    await page.clock.set_fixed_time(CLOCK)
    errors = {}
    cur = {"k": None}
    page.on("pageerror", lambda e: errors.setdefault(cur["k"] or "boot", []).append(str(e)))
    page.on("console", lambda m: errors.setdefault(cur["k"] or "boot", []).append(m.text) if m.type == "error" else None)
    url = f"file://{root}/index.html?bare&theme={theme}&size=600x800" + ("&eink=1" if eink else "")
    await fresh(page, url)
    d_out = outdir / mode
    d_out.mkdir(parents=True, exist_ok=True)
    for i, d in enumerate(demos):
        cur["k"] = d["key"]
        try:
            # the reader keeps module state (last page, selection) between renders: give its states a fresh page
            if d["hash"].startswith("#/reader"): await fresh(page, url)
            await settle(page, d["hash"])
            await page.locator("#screen").screenshot(path=str(d_out / f"{d['key']}.png"), animations="disabled", caret="hide")
        except Exception as e:
            errors.setdefault(d["key"], []).append(f"snap failed: {e}")
        if (i + 1) % 50 == 0: log(f"  {mode}: {i + 1}/{len(demos)}")
    await ctx.close()
    return errors


async def main(a):
    outdir = ROOT / "shots" / a.out
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=CHROME, args=["--disable-gpu", "--hide-scrollbars", "--font-render-hinting=none"])
        page = await browser.new_page()
        await page.goto(f"file://{a.root}/index.html?bare", wait_until="networkidle")
        await page.wait_for_function("window.App && App.demos.length > 0")
        demos = await page.evaluate("App.demos")
        await page.close()
        if a.group: demos = [d for d in demos if a.group.lower() in d["group"].lower()]
        if a.match: demos = [d for d in demos if a.match.lower() in (d["label"] + d["hash"]).lower()]
        seen = {}
        for d in demos:
            d["key"] = key_of(d)
            if d["key"] in seen: d["key"] += f"-{len(seen)}"
            seen[d["key"]] = d
        modes = a.modes.split(",")
        log = lambda s: print(s, file=sys.stderr, flush=True)
        log(f"{len(demos)} states x {len(modes)} modes -> {outdir}")
        res = await asyncio.gather(*[run_mode(browser, m, demos, outdir, log, a.root) for m in modes])
        await browser.close()
    manifest_path = outdir / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() and (a.group or a.match) else {}
    for d in demos: manifest[d["key"]] = {"group": d["group"], "label": d["label"], "hash": d["hash"]}
    errors = {}
    for m, e in zip(modes, res):
        for k, v in e.items(): errors.setdefault(k, {})[m] = v
    manifest_path.write_text(json.dumps(manifest, indent=1))
    (outdir / "errors.json").write_text(json.dumps(errors, indent=1))
    n_err = sum(len(v) for e in res for v in e.values())
    print(f"{len(demos)} states x {len(modes)} modes -> {outdir}; console errors: {n_err}" + (f" (see {outdir / 'errors.json'})" if n_err else ""))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="current")
    ap.add_argument("--modes", default="dark,paper,eink")
    ap.add_argument("--group"); ap.add_argument("--match")
    ap.add_argument("--root", default=str(ROOT), help="prototype folder to load (e.g. .backup-before-cleanup to rebuild the baseline)")
    asyncio.run(main(ap.parse_args()))
