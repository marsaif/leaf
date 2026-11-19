#!/usr/bin/env python3
"""Contact sheets for visual review: every App.demos state, grouped by designer group.

  tools/.venv/bin/python tools/contact.py [--theme dark|paper] [--eink] [--group Reader] [--cols 4]
Writes shots/qa-sheet-<theme>[-eink]-<group>-<n>.png (12 states per sheet, captioned).
"""
import argparse, asyncio, io, re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent.parent
NO_MOTION = "*,*::before,*::after{animation:none!important;transition:none!important}"


async def main(a):
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome")
        page = await b.new_page(viewport={"width": 600, "height": 800})
        q = f"?bare&theme={a.theme}&size=600x800" + ("&eink=1" if a.eink else "")
        await page.goto(f"file://{ROOT}/index.html{q}", wait_until="networkidle")
        await page.add_style_tag(content=NO_MOTION)
        await page.wait_for_function("window.lucide && App.demos.length")
        demos = await page.evaluate("App.demos")
        if a.group: demos = [d for d in demos if a.group.lower() in d["group"].lower()]
        if a.match: demos = [d for d in demos if a.match.lower() in (d["label"] + d["hash"]).lower()]
        shots = []
        for d in demos:
            await page.evaluate("""async (h) => { localStorage.removeItem('leaf.store'); App.store = {}; document.querySelectorAll('.ko-toast').forEach(t => t.remove());
              history.replaceState(null,'',h); App.fromHash(); App.render(); await document.fonts.ready;
              await new Promise(r => setTimeout(r, 60)); }""", d["hash"])
            png = await page.locator("#screen").screenshot()
            shots.append((d, Image.open(io.BytesIO(png)).convert("RGB")))
        await b.close()
    font = ImageFont.load_default(size=15)
    per, cols, sc = a.per, a.cols, a.scale
    groups = {}
    for d, im in shots: groups.setdefault(d["group"], []).append((d, im))
    tag = a.theme + ("-eink" if a.eink else "")
    for g, items in groups.items():
        for n in range(0, len(items), per):
            chunk = items[n:n + per]
            w, h = int(600 * sc), int(800 * sc)
            rows = (len(chunk) + cols - 1) // cols
            sheet = Image.new("RGB", (cols * (w + 10) + 10, rows * (h + 34) + 10), (60, 60, 60))
            dr = ImageDraw.Draw(sheet)
            for i, (d, im) in enumerate(chunk):
                x, y = 10 + (i % cols) * (w + 10), 10 + (i // cols) * (h + 34)
                sheet.paste(im.resize((w, h)), (x, y + 24))
                dr.text((x, y + 4), f"{n + i + 1}. {d['label']}"[:60], fill=(255, 255, 255), font=font)
            out = ROOT / "shots" / f"qa-sheet-{tag}-{re.sub(r'[^a-z]+', '-', g.lower()).strip('-')}-{n // per + 1}.png"
            sheet.save(out); print(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", default="dark"); ap.add_argument("--eink", action="store_true")
    ap.add_argument("--group"); ap.add_argument("--match")
    ap.add_argument("--cols", type=int, default=4); ap.add_argument("--per", type=int, default=8)
    ap.add_argument("--scale", type=float, default=0.6)
    asyncio.run(main(ap.parse_args()))
