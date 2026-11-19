"""Cut one static instance out of a variable font and give it proper family/style names.

    instance.py SRC.ttf DST.ttf "Family" "Style" wght=600 [opsz=12]
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont, OverlapMode
src, dst, family, style = sys.argv[1:5]
axes = dict(a.split("=") for a in sys.argv[5:])
axes = {k: float(v) for k, v in axes.items()}
f = TTFont(src)
inst = instantiateVariableFont(f, axes, overlap=OverlapMode.REMOVE, updateFontNames=False)
# names: family + style so FreeType / KOReader see distinct faces
name = inst["name"]
full = f"{family} {style}".replace(" Regular", "") if style != "Regular" else family
ps = f"{family.replace(' ', '')}-{style.replace(' ', '')}"
for rec in list(name.names):
    if rec.nameID in (16, 17, 21, 22, 25):
        name.removeNames(nameID=rec.nameID)
for pid, eid, lid in ((3, 1, 0x409), (1, 0, 0)):
    ribbi = style in ("Regular", "Italic", "Bold", "Bold Italic")
    name.setName(family if ribbi else f"{family} {style}", 1, pid, eid, lid)
    name.setName(style if ribbi else "Regular", 2, pid, eid, lid)
    name.setName(f"{family} {style}", 4, pid, eid, lid)
    name.setName(ps, 6, pid, eid, lid)
    name.setName(family, 16, pid, eid, lid)
    name.setName(style, 17, pid, eid, lid)
inst.save(dst)
print("wrote", dst)
