import os
def _x(p): return os.path.expanduser(os.path.expandvars(p))  # paths use $KOREADER_DIR and ~
import json, re, os, sys
d = json.load(open('raw.json'))
cache = {}
def lines(f):
    if f not in cache:
        p = _x(f) if f.startswith('~') else _x('$KOREADER_DIR/lib/koreader/' + f)
        cache[f] = open(p, encoding='utf-8', errors='replace').read().split('\n')
    return cache[f]
fre = re.compile(r'function\s+([\w.:]+)\s*\(')
for x in d:
    L = lines(x['file'])
    fn = ''
    for i in range(x['line'] - 1, max(-1, x['line'] - 400), -1):
        m = fre.search(L[i])
        if m and not L[i].lstrip().startswith('--') and ('local function' in L[i] or L[i].startswith('function') or re.match(r'^\s*function', L[i])):
            fn = m.group(1); break
    x['fn'] = fn
json.dump(d, open('raw2.json', 'w'), indent=0)
