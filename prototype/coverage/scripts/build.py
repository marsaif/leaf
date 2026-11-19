import os
def _x(p): return os.path.expanduser(os.path.expandvars(p))  # paths use $KOREADER_DIR and ~
import json, os, sys, collections, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from entries import E

KO = _x("$KOREADER_DIR/lib/koreader/")
PFX = {
    "fm/": "frontend/apps/filemanager/", "rm/": "frontend/apps/reader/modules/", "w/": "frontend/ui/widget/",
    "ui/": "frontend/ui/", "el/": "frontend/ui/elements/", "dev/": "frontend/device/", "app/": "frontend/apps/",
    "pl/": "plugins/", "pt/": "~/.config/koreader/plugins/projecttitle.koplugin/", "pa/": "~/.config/koreader/patches/",
}
def expand(r):
    for k, v in PFX.items():
        if r.startswith(k):
            return v + r[len(k):]
    return r.replace("frontend/frontend/", "frontend/")
def abspath(f):
    return _x(f) if f.startswith("~") else KO + f

STATUS = {"D": "designed", "G": "generic", "P": "partial", "M": "missing"}
raw = json.load(open(os.path.join(os.path.dirname(__file__), "raw2.json")))
sites = [x for x in raw if x["widget"] != "UIManager:show"]
shows = [x for x in raw if x["widget"] == "UIManager:show"]

surfaces, bad = [], []
for (sid, area, title, refs, widget, trigger, example, cat, st, folio, kindle, prio, sugg) in E:
    rl = [expand(r.strip()) for r in refs.split(",") if r.strip()]
    for r in rl:
        f, _, ln = r.rpartition(":")
        p = abspath(f)
        if not os.path.exists(p):
            bad.append((sid, r, "no file"))
        else:
            n = sum(1 for _ in open(p, encoding="utf-8", errors="replace"))
            if not ln.isdigit() or int(ln) > n:
                bad.append((sid, r, "line"))
    surfaces.append({
        "id": sid, "area": area, "title": title, "koreader_refs": rl, "widget": widget, "trigger": trigger,
        "example": example, "category": cat, "status": STATUS[st], "folio": folio, "kindle_relevant": kindle,
        "priority": prio if st in ("M", "P") else None, "suggestion": sugg, "site_count": 0,
    })
if bad:
    print("BAD REFS", bad)

byref = {}
for s in surfaces:
    for r in s["koreader_refs"]:
        byref.setdefault(r, s["id"])
WMAP = {"InfoMessage": "w.infomessage", "Notification": "w.notification", "ConfirmBox": "w.confirmbox",
        "MultiConfirmBox": "w.multiconfirmbox", "ButtonDialog": "w.buttondialog", "ButtonSelector": "w.buttonselector",
        "InputDialog": "w.inputdialog", "MultiInputDialog": "w.multiinputdialog", "SpinWidget": "w.spinwidget",
        "DoubleSpinWidget": "w.doublespinwidget", "DateTimeWidget": "w.datetimewidget", "TextViewer": "w.textviewer",
        "KeyValuePage": "w.keyvaluepage", "Menu": "w.menu", "BookList": "w.booklist", "FileChooser": "w.booklist",
        "SortWidget": "w.sortwidget", "SortItemWidget": "w.sortwidget", "PathChooser": "w.pathchooser",
        "ImageViewer": "w.imageviewer", "QRMessage": "w.qrmessage", "ProgressbarDialog": "w.progressbardialog",
        "TrapWidget": "w.trapwidget", "RadioButtonWidget": "w.radiobuttonwidget", "VirtualKeyPopup": "w.virtualkeypopup",
        "KeyboardLayoutDialog": "w.keyboardlayoutdialog", "ButtonProgressWidget": "w.toggleswitch", "OpenWithDialog": "w.openwith",
        "FontChooser": "w.fontchooser", "BookMapWidget": "rd.bookmap", "PageBrowserWidget": "rd.pagebrowser", "SetDefaultsWidget": "fm.defaults", "FileManagerHistory": "hi.list", "FileManagerCollection": "co.list", "FileManagerShortcuts": "sc.list", "NetworkSetting": "sy.wifi.list"}
unassigned = collections.Counter()
for x in sites:
    key = x["file"] + ":" + str(x["line"])
    sid = byref.get(key)
    how = "explicit"
    if not sid:
        sid = WMAP.get(x["widget"])
        how = "by widget type"
    if not sid:
        unassigned[x["widget"]] += 1
        sid = "unassigned"
    x["surface"] = sid
    x["assigned"] = how
    x.pop("fn", None) if False else None
sid_count = collections.Counter(x["surface"] for x in sites)
wtot = collections.Counter(x["widget"] for x in sites)
for s in surfaces:
    s["assigned_site_count"] = sid_count.get(s["id"], 0)
    s.pop("site_count", None)
    if s["id"].startswith("w."):
        s["all_sites_of_this_widget_type"] = sum(n for w, n in wtot.items() if WMAP.get(w) == s["id"])
print("unassigned:", unassigned)

# ---- summaries
areas = []
for s in surfaces:
    if s["area"] not in areas:
        areas.append(s["area"])
summary = []
for a in areas:
    ss = [s for s in surfaces if s["area"] == a]
    c = collections.Counter(s["status"] for s in ss)
    km = sum(1 for s in ss if s["status"] in ("missing", "partial") and s["kindle_relevant"])
    summary.append({"area": a, "total": len(ss), "designed": c["designed"], "generic": c["generic"], "partial": c["partial"], "missing": c["missing"], "kindle_relevant_gaps": km})
tot = {k: sum(r[k] for r in summary) for k in ("total", "designed", "generic", "partial", "missing", "kindle_relevant_gaps")}
wcount = collections.Counter(x["widget"] for x in sites)

out = {
    "generated": str(datetime.date.today()),
    "koreader_version": "v2026.07.1",
    "sources": ["$KOREADER_DIR/lib/koreader/frontend", "$KOREADER_DIR/lib/koreader/plugins",
                "~/.config/koreader/plugins/projecttitle.koplugin", "~/.config/koreader/patches", "./js/screens/*.js"],
    "legend": {"designed": "a Folio screen/overlay designs this surface (see folio + demo)",
               "generic": "no dedicated design, but a designed Folio component covers it once the KOReader base widget is restyled globally",
               "partial": "designed in part; a state or sub-surface is missing",
               "missing": "nothing in Folio covers it",
               "priority": "P1 daily reading/library use, P2 occasional, P3 rare/power-user (gaps only)"},
    "totals": tot,
    "summary_by_area": summary,
    "widget_site_counts": dict(wcount.most_common()),
    "uimanager_show_calls": len(shows),
    "surfaces": surfaces,
    "sites": [{"file": x["file"], "line": x["line"], "widget": x["widget"], "text": x["text"], "function": x.get("fn", ""), "surface": x["surface"], "assigned": x["assigned"]} for x in sites],
}
dst = "./coverage/inventory.json"
json.dump(out, open(dst, "w"), indent=1, ensure_ascii=False)
print("surfaces", len(surfaces), "sites", len(sites), "shows", len(shows), tot)
