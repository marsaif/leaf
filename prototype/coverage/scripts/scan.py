import os
def _x(p): return os.path.expanduser(os.path.expandvars(p))  # paths use $KOREADER_DIR and ~
import os, re, json, sys
ROOTS = [("ko", _x("$KOREADER_DIR/lib/koreader"), ["frontend", "plugins"]),
         ("pt", _x("~/.config/koreader/plugins"), ["projecttitle.koplugin"]),
         ("patch", _x("~/.config/koreader"), ["patches"])]
TYPES = ["InfoMessage","ConfirmBox","MultiConfirmBox","ButtonDialog","ButtonDialogTitle","InputDialog","MultiInputDialog",
 "SpinWidget","DoubleSpinWidget","DateTimeWidget","TextViewer","KeyValuePage","Menu","BookList","ImageViewer","FootnoteWidget",
 "Notification","QRMessage","ProgressbarDialog","PathChooser","SortWidget","RadioButtonWidget","OpenWithDialog","KeyboardLayoutDialog",
 "FrontLightWidget","NaturalLightWidget","ScreenSaverWidget","ScreenSaverLockWidget","Screenshoter","SkimToWidget","PageBrowserWidget",
 "BookMapWidget","TouchMenu","ConfigDialog","VirtualKeyboard","ButtonSelector","BookStatusWidget","DictQuickLookup","FontChooser",
 "LinkBox","BBoxWidget","TrapWidget","CalendarView","CalendarDayView","ReaderProgress","VocabularyBuilderWidget","MenuDialog",
 "TweakInfoWidget","WordInfoDialog","SetDefaultsWidget","NetworkSetting","CloudStorage","OPDSBrowser","SyncService","BookmarkBrowser",
 "BookMetadataArchive","FileChooser","IndicatorOverlay","ButtonProgressWidget","TermInputText","VirtualKeyPopup","PhysicalKeyboard",
 "BookInfo","FileManagerShortcuts","FileManagerCollection","FileManagerHistory","SortItemWidget","AltBookStatusWidget"]
pat = re.compile(r"\b(" + "|".join(TYPES) + r")\s*:\s*new\s*[{(]")
showpat = re.compile(r"UIManager\s*:\s*show\s*\(")
strpat = re.compile(r'(text|title|info_text|description|input_hint|title_text|ok_text)\s*=\s*(?:T\()?\s*_?\(?\s*(\[\[.*?\]\]|"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')')
out = []
for tag, base, subs in ROOTS:
  for s in subs:
    for dp, dn, fns in os.walk(os.path.join(base, s)):
      for fn in fns:
        if not fn.endswith(".lua"): continue
        p = os.path.join(dp, fn); rel = os.path.relpath(p, base)
        if tag == "patch": rel = "~/.config/koreader/" + rel
        elif tag == "pt": rel = "~/.config/koreader/plugins/" + rel
        try: L = open(p, encoding="utf-8", errors="replace").read().split("\n")
        except Exception: continue
        for i, line in enumerate(L):
          if line.strip().startswith("--"): continue
          for m in pat.finditer(line):
            if re.search(r"local\s+\w+\s*=\s*require", line): continue
            win = "\n".join(L[i:i+10])
            sm = strpat.search(win)
            txt = sm.group(2)[1:-1][:140] if sm else ""
            if sm and sm.group(2).startswith("[["): txt = sm.group(2)[2:-2][:140]
            out.append({"file": rel, "line": i+1, "widget": m.group(1), "text": txt.replace("\\n"," ")})
          if re.search(r"Notification\s*:\s*notify\s*\(", line):
            m2 = re.search(r'notify\((?:T\()?\s*_?\(?\s*("(?:[^"\\]|\\.)*")', line)
            out.append({"file": rel, "line": i+1, "widget": "Notification", "text": (m2.group(1)[1:-1] if m2 else line.strip())[:140]})
          m3 = re.search(r'require\("ui/widget/(infomessage|notification|textviewer|doublespinwidget|radiobuttonwidget|networksetting)"\)\s*:\s*new', line)
          if m3:
            W = {"infomessage":"InfoMessage","notification":"Notification","textviewer":"TextViewer","doublespinwidget":"DoubleSpinWidget","radiobuttonwidget":"RadioButtonWidget","networksetting":"NetworkSetting"}[m3.group(1)]
            out.append({"file": rel, "line": i+1, "widget": W, "text": line.strip()[:140]})
          if showpat.search(line):
            out.append({"file": rel, "line": i+1, "widget": "UIManager:show", "text": line.strip()[:140]})
json.dump(out, open(sys.argv[1], "w"), indent=0)
print(len(out))
