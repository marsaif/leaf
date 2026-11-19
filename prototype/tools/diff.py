#!/usr/bin/env python3
"""Compare a snap.py run against the baseline and write tools/diff-report.md.

  tools/.venv/bin/python tools/snap.py && tools/.venv/bin/python tools/diff.py
  tools/.venv/bin/python tools/diff.py --cur current --base baseline --threshold 0.5 --notes tools/diff-notes.json

Per state and mode: % of pixels whose RGB differs by more than --tol (default 8/255 on any channel).
Anything above --show (default 0.05%) gets shots/diff/<mode>/<key>.png: baseline | current | diff
(changed pixels in magenta over a dimmed baseline). States above --threshold (default 0.5%) fail unless
tools/diff-notes.json explains them: {"<key or hash>": "reason"} (applies to every mode),
{"<key>@<mode>": "reason"}, or a glob over keys ({"search-stats-search-*": "reason"}).
"""
import argparse, fnmatch, json, sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "shots"


def compare(a, b, tol):
    if a.size != b.size:
        b = b.resize(a.size)
    diff = ImageChops.difference(a, b)
    r, g, bl = diff.split()
    mask = ImageChops.lighter(ImageChops.lighter(r, g), bl).point(lambda v: 255 if v > tol else 0)
    changed = mask.histogram()[255]
    return changed / (a.size[0] * a.size[1]) * 100, mask, mask.getbbox()


def panel(a, b, mask, title):
    w, h = a.size
    dim = Image.blend(a, Image.new("RGB", a.size, (0, 0, 0)), 0.65)
    dim.paste(Image.new("RGB", a.size, (255, 0, 200)), (0, 0), mask)
    out = Image.new("RGB", (w * 3 + 40, h + 30), (40, 40, 40))
    for i, im in enumerate((a, b, dim)): out.paste(im, (10 + i * (w + 10), 30))
    dr = ImageDraw.Draw(out)
    font = ImageFont.load_default(size=14)
    for i, t in enumerate(("baseline", "current", title)): dr.text((10 + i * (w + 10), 8), t, fill=(255, 255, 255), font=font)
    return out


def main(a):
    base, cur = SHOTS / a.base, SHOTS / a.cur
    man = {}
    for d in (base, cur):
        if (d / "manifest.json").exists(): man.update(json.loads((d / "manifest.json").read_text()))
    notes = json.loads(Path(a.notes).read_text()) if Path(a.notes).exists() else {}
    outdir = SHOTS / "diff"
    for old in outdir.glob("*/*.png"): old.unlink()
    rows, missing, new = [], [], []
    for mdir in sorted(p for p in cur.iterdir() if p.is_dir()):
        mode = mdir.name
        for f in sorted(mdir.glob("*.png")):
            key = f.stem
            bf = base / mode / f.name
            if not bf.exists(): new.append((key, mode)); continue
            A, B = Image.open(bf).convert("RGB"), Image.open(f).convert("RGB")
            pct, mask, bbox = compare(A, B, a.tol)
            m = man.get(key, {})
            note = notes.get(f"{key}@{mode}") or notes.get(key) or notes.get(m.get("hash", "\0")) \
                or next((v for k, v in notes.items() if any(ch in k for ch in "*?[") and (fnmatch.fnmatch(key, k) or fnmatch.fnmatch(f"{key}@{mode}", k))), None)
            img = ""
            if pct > a.show:
                (outdir / mode).mkdir(parents=True, exist_ok=True)
                img = f"shots/diff/{mode}/{key}.png"
                panel(A, B, mask, f"{pct:.2f}% changed").save(ROOT / img)
            rows.append({"key": key, "mode": mode, "pct": pct, "bbox": bbox, "img": img, "note": note, **m})
    for mdir in sorted(p for p in base.iterdir() if p.is_dir()):
        for f in mdir.glob("*.png"):
            if not (cur / mdir.name / f.name).exists() and (cur / mdir.name).exists(): missing.append((f.stem, mdir.name))
    fails = [r for r in rows if r["pct"] >= a.threshold and not r["note"]]
    explained = [r for r in rows if r["pct"] >= a.threshold and r["note"]]
    small = [r for r in rows if a.show < r["pct"] < a.threshold]
    L = ["# Visual diff vs baseline\n",
         f"`tools/diff.py --base {a.base} --cur {a.cur}` — {len(rows)} screenshots compared "
         f"({len({r['key'] for r in rows})} states x {len({r['mode'] for r in rows})} modes), pixel tolerance {a.tol}/255, "
         f"threshold {a.threshold}%.\n",
         f"- **Unexplained >= {a.threshold}%: {len(fails)}**",
         f"- Explained (intentional, see reason): {len(explained)}",
         f"- Small (> {a.show}% and < {a.threshold}%): {len(small)}",
         f"- Identical or below {a.show}%: {len(rows) - len(fails) - len(explained) - len(small)}",
         f"- New states (no baseline): {len({k for k, _ in new})}; missing in current: {len({k for k, _ in missing})}\n"]
    def table(title, rs):
        if not rs: return
        L.append(f"## {title}\n")
        L.append("| % changed | mode | state | changed area | reason / image |")
        L.append("|---|---|---|---|---|")
        for r in sorted(rs, key=lambda r: -r["pct"]):
            bb = "x{}-{} y{}-{}".format(r["bbox"][0], r["bbox"][2], r["bbox"][1], r["bbox"][3]) if r["bbox"] else "-"
            L.append(f"| {r['pct']:.2f} | {r['mode']} | {r.get('group', '?')} › {r.get('label', r['key'])} `{r.get('hash', '')}` | {bb} | "
                     + (r["note"] + " " if r["note"] else "") + (f"[diff]({'../' + r['img']})" if r["img"] else "") + " |")
        L.append("")
    table(f"Unexplained changes (>= {a.threshold}%)", fails)
    table("Intentional changes", explained)
    table(f"Small changes (< {a.threshold}%)", small)
    if new:
        L.append("## New states\n")
        for k in sorted({k for k, _ in new}): L.append(f"- {man.get(k, {}).get('group', '?')} › {man.get(k, {}).get('label', k)} `{man.get(k, {}).get('hash', '')}`")
        L.append("")
    if missing:
        L.append("## Missing states (in baseline, not in current)\n")
        for k in sorted({k for k, _ in missing}): L.append(f"- {k}")
        L.append("")
    if a.notes_section and Path(a.notes_section).exists():
        L.append(Path(a.notes_section).read_text().rstrip() + "\n")
    Path(a.report).write_text("\n".join(L) + "\n")
    print(f"{len(rows)} compared; unexplained >= {a.threshold}%: {len(fails)}; explained: {len(explained)}; small: {len(small)}; new: {len({k for k, _ in new})} -> {a.report}")
    for r in sorted(fails, key=lambda r: -r["pct"])[:a.list]:
        print(f"  {r['pct']:6.2f}%  {r['mode']:5}  {r['key']}  {r.get('hash', '')}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="baseline"); ap.add_argument("--cur", default="current")
    ap.add_argument("--tol", type=int, default=8)
    ap.add_argument("--threshold", type=float, default=0.5)
    ap.add_argument("--show", type=float, default=0.05)
    ap.add_argument("--notes", default=str(ROOT / "tools/diff-notes.json"))
    ap.add_argument("--notes-section", default=str(ROOT / "tools/diff-notes.md"), help="markdown appended to the report")
    ap.add_argument("--report", default=str(ROOT / "tools/diff-report.md"))
    ap.add_argument("--list", type=int, default=40)
    main(ap.parse_args())
