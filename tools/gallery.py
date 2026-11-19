#!/usr/bin/env python3
"""Side-by-side gallery: every Leaf sandbox scene next to its prototype screen, like for like.

    tools/ko-sandbox.sh --shots .sandbox/shots/gallery        # Leaf scenes (Kindle size, e-ink)
    python3 tools/gallery.py .sandbox/shots/gallery [--out .sandbox/gallery] [--only a,b] [--refresh]

The prototype is shot with prototype/shot.sh in the Paper theme with the e-ink preview (greyscale, as
the Kindle 11 shows it), 600x800, then scaled to the Kindle width. Pairs: <out>/pairs/<scene>.png
(Leaf left, prototype right); index: <out>/index.html. Mapping: tools/gallery_map.json.
Prototype shots are cached in <out>/proto/ (use --refresh after prototype changes).
"""
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent
MAP = json.loads((REPO / "tools/gallery_map.json").read_text())
MAP.pop("_comment", None)


def proto_shot(hash_, out):
    subprocess.run([str(REPO / "prototype/shot.sh"), hash_, str(out), "paper", "600x800", "eink"],
                   cwd=REPO / "prototype", check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def pair(leaf_png, proto_png, out, title):
    a = Image.open(leaf_png).convert("RGB")
    b = Image.open(proto_png).convert("RGB")
    b = b.resize((a.width, round(b.height * a.width / b.width)))
    h = max(a.height, b.height)
    gap, head = 24, 56
    m = Image.new("RGB", (a.width * 2 + gap, h + head), "white")
    m.paste(a, (0, head))
    m.paste(b, (a.width + gap, head))
    d = ImageDraw.Draw(m)
    d.text((12, 16), f"LEAF (KOReader)  ·  {title}", fill=(0, 0, 0))
    d.text((a.width + gap + 12, 16), "PROTOTYPE (spec, e-ink preview)", fill=(0, 0, 0))
    m.save(out)


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    shots = Path(args[0])
    out = Path(args[args.index("--out") + 1]) if "--out" in args else REPO / ".sandbox/gallery"
    only = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
    refresh = "--refresh" in args
    (out / "proto").mkdir(parents=True, exist_ok=True)
    (out / "pairs").mkdir(parents=True, exist_ok=True)
    rows, missing = [], []
    for scene, hash_ in MAP.items():
        if only and scene not in only:
            continue
        leaf = shots / f"{scene}.png"
        if not leaf.exists():
            missing.append(scene)
            continue
        proto = out / "proto" / f"{scene}.png"
        if refresh or not proto.exists():
            proto_shot(hash_, proto)
        dst = out / "pairs" / f"{scene}.png"
        pair(leaf, proto, dst, scene)
        rows.append((scene, hash_, dst.name))
    html = ["<!doctype html><meta charset=utf-8><title>Leaf vs prototype</title>",
            "<style>body{font:14px system-ui;margin:24px;background:#eee}figure{margin:0 0 32px}"
            "img{width:100%;max-width:1400px;border:1px solid #ccc;background:#fff}code{color:#555}</style>",
            f"<h1>Leaf vs prototype · {len(rows)} pairs</h1>"]
    for scene, hash_, name in rows:
        html.append(f"<figure><h3>{scene} <code>{hash_}</code></h3><img src='pairs/{name}' loading=lazy></figure>")
    (out / "index.html").write_text("\n".join(html))
    print(f"{len(rows)} pairs -> {out}/index.html")
    if missing:
        print("no Leaf shot for:", ", ".join(missing))


if __name__ == "__main__":
    main()
