#!/usr/bin/env python3
"""Quick listing of audit.json findings: tools/.venv/bin/python tools/issues.py [file-substring] [--all] [--rule r]"""
import json, sys
from pathlib import Path
d = json.load(open(Path(__file__).parent / "audit.json"))
rule = sys.argv[sys.argv.index("--rule") + 1] if "--rule" in sys.argv else None
args = [a for a in sys.argv[1:] if not a.startswith("--") and a != rule]
show_all = "--all" in sys.argv
rule = sys.argv[sys.argv.index("--rule") + 1] if "--rule" in sys.argv else None
skip = set() if show_all else {"consistency", "off-scale-size", "offpalette", "truncated", "italic-ui"}
for i in d["issues"] + d["static"]:
    if i["sev"] == "low" and not show_all: continue
    if rule and i["rule"] != rule: continue
    if not rule and i["rule"] in skip: continue
    if args and not any(a in (i.get("file", "") + i["owner"]) for a in args): continue
    print(i["sev"][0], i["rule"], "|", i["owner"], "|", i["sel"][:70], "|", i["msg"][:110], "|", (i.get("demos") or [i.get("line", "")])[0])
