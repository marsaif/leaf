#!/usr/bin/env python3
"""Fast static-only run of the screen-CSS rules of tools/audit.py (no browser).
  tools/.venv/bin/python tools/lintcss.py [file-substring]"""
import importlib.util, sys, collections
from pathlib import Path
spec = importlib.util.spec_from_file_location("audit", Path(__file__).with_name("audit.py"))
a = importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
iss = [i for i in a.static_scan() if len(sys.argv) < 2 or sys.argv[1] in i["file"]]
for i in iss: print(f"{i['sev'][0]} {i['file']}:{i['line']} {i['rule']} `{i['sel']}` — {i['msg'][:120]}")
print(dict(collections.Counter(i["sev"] for i in iss)))
