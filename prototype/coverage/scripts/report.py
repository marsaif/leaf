import json, collections
D = json.load(open("./coverage/inventory.json"))
S = D["surfaces"]; W = D["widget_site_counts"]; T = D["totals"]
L = []
P = L.append
def refs(s, n=3):
    r = s["koreader_refs"][:n]
    more = len(s["koreader_refs"]) - n
    return ", ".join(f"`{x}`" for x in r) + (f" (+{more} more)" if more > 0 else "")

P("# Folio coverage audit: every KOReader surface vs. the prototype")
P("")
P(f"Generated {D['generated']} against KOReader {D['koreader_version']} (`$KOREADER_DIR/lib/koreader`), "
  "the Project: Title plugin and the user patches in `~/.config/koreader/`, and the prototype in `js/screens/*.js` + `js/data/menus.js`.")
P("")
P("**Goal:** after the Lua port, no screen, dialog, toast or piece of chrome may still show the old KOReader look. "
  "This file is the checklist; `inventory.json` holds every surface (`surfaces`) and every widget construction site found in the source (`sites`, each tagged with the surface it belongs to).")
P("")
P("## How it was built")
P("")
P(f"- Scanned all Lua in `frontend/`, `plugins/`, Project: Title and the patches for constructions of visible widgets (`InfoMessage:new`, `ConfirmBox:new`, `ButtonDialog:new`, `SpinWidget:new`, `Notification:notify`, … 60 widget types) and `UIManager:show(` calls: **{sum(W.values())} construction sites, {D['uimanager_show_calls']} show calls**.")
P(f"- Grouped them into **{T['total']} surfaces** (trivial variants are one surface: the 395 `InfoMessage` texts are one 'info message' type, notable ones are listed separately). Every site is assigned: explicitly to a curated surface, or by widget type to its base-widget surface (`assigned` field).")
P("- Added persistent chrome that is drawn, not shown as a widget (footer, dog-ear, flipping indicator, highlights, link box, crop box, page gaps, Project: Title grid/list/title bar/footer).")
P("- Mapped each surface to the prototype: overlays/screens registered with `App.screen/App.overlay`, states registered with `App.demo`, menu-row links in `App.menuSpecial`, and the generic menu engine for plain `KO_MENUS` rows (not counted as gaps).")
P("")
P("Legend: **designed** = a Folio screen/overlay designs it · **generic** = no dedicated design, but a designed Folio component covers it *once the base widget is restyled globally in the port* · **partial** = designed in part, a state or sub-surface is missing · **missing** = nothing covers it. Priority (gaps only): **P1** daily reading/library use, **P2** occasional, **P3** rare/power-user. Kindle = relevant on a touch Kindle (Kindle 11: frontlight, no warmth, no keys, Kindle handles USB itself).")
P("")
P("## Totals")
P("")
P(f"| Surfaces | Designed | Generic | Partial | Missing | Kindle-relevant gaps (partial + missing) |")
P("|---:|---:|---:|---:|---:|---:|")
P(f"| {T['total']} | {T['designed']} | {T['generic']} | {T['partial']} | {T['missing']} | {T['kindle_relevant_gaps']} |")
P("")
P("## Summary per area")
P("")
P("| Area | Total | Designed | Generic | Partial | Missing | Kindle gaps |")
P("|---|---:|---:|---:|---:|---:|---:|")
for r in D["summary_by_area"]:
    P(f"| {r['area']} | {r['total']} | {r['designed']} | {r['generic']} | {r['partial']} | {r['missing']} | {r['kindle_relevant_gaps']} |")
P("")
P("Note: the 'Base widgets' row counts widget *types*. Its gaps are the most important ones, because each type is shown from many places (see the site counts in the safety-net table).")
P("")

gaps = [s for s in S if s["status"] in ("missing", "partial")]
P("## Gaps (missing and partial), by priority")
P("")
P("Each line: id · what · KOReader file:line · trigger · widget · design suggestion (Folio component/pattern to use).")
P("")
for pr in ("P1", "P2", "P3"):
    g = [s for s in gaps if s["priority"] == pr and s["kindle_relevant"]]
    if not g:
        continue
    P(f"### {pr} ({len(g)} Kindle-relevant)")
    P("")
    for s in g:
        st = "partial" if s["status"] == "partial" else "missing"
        have = f" Folio today: {s['folio']}." if s["folio"] else ""
        n = s.get("all_sites_of_this_widget_type")
        P(f"- **{s['title']}** (`{s['id']}`, {st}{f', {n} construction sites of this type' if n else ''})  ")
        P(f"  KOReader: {refs(s)} · Trigger: {s['trigger']} · Widget: {s['widget']}.{have}  ")
        P(f"  Design: {s['suggestion']}")
    P("")
ng = [s for s in gaps if not s["kindle_relevant"]]
if ng:
    P("### Not needed on a touch Kindle")
    P("")
    for s in ng:
        P(f"- {s['title']} (`{s['id']}`, {s['priority']}) · {refs(s, 2)} · {s['trigger']}")
    P("")

P("## Surfaces covered only by a generic component")
P("")
P("These have no dedicated design. They stay in the old look unless the base widget in the right-hand column is restyled globally (see the safety net below).")
P("")
P("| Surface | Base widget(s) | Folio component to mirror |")
P("|---|---|---|")
for s in S:
    if s["status"] == "generic":
        P(f"| {s['title']} (`{s['id']}`) | {s['widget']} | {s['folio']} |")
P("")

P("## Global safety net (restyle these base widgets in the Lua port)")
P("")
P("Restyling each of these once gives the Folio look to every use, including surfaces never designed individually. Counts are construction sites found in KOReader + plugins + Project: Title (direct `:new`/`notify` calls; subclasses inherit on top).")
P("")
P("| # | Base widget / global (file) | Sites | Inherited by / used inside | Folio target | Status of the Folio design |")
P("|---:|---|---:|---|---|---|")
rows = [
 ("Font map & sizes (`frontend/ui/font.lua` `Font.fontmap`, `Font.sizemap`)", "all", "every TextWidget/TextBoxWidget in every widget", "Inter (UI), Playfair Display (top-level titles), Literata (book), Noto Naskh Arabic; type scale tokens 10.5–30", "designed (tokens.css); existing patch `2-font-override.lua` swaps to Source Sans: replace it"),
 ("Sizes (`frontend/ui/size.lua`: radius, border, padding, margin, line, item heights)", "all", "every FrameContainer, separators, menu rows", "radius tokens, hairline borders, 48px rows, 44px popover rows, 40px buttons", "designed; `2-clean-menus.lua` sets `Size.radius.window = 0`: conflicts with Folio's rounded sheets/dialogs, revise"),
 ("Colours (`Blitbuffer.COLOR_*` greys) + night mode", "all", "frames, separators, greyed text, highlight greys", "map to tokens; Folio Dark on e-ink = KOReader night mode (whole-screen inversion of the Paper theme), so design Paper first and check the inverted result", "designed (tokens) — inversion behaviour must be checked"),
 ("Icons (`frontend/ui/widget/iconwidget.lua`: user icons dir `koreader/icons/` is searched before `resources/icons/mdlight`)", "all", "title bars, menus, top-menu tabs, footer, dialogs, file browser", "drop Lucide SVGs named like the mdlight files (appbar.*, chevron.*, star.*, …) into `koreader/icons/`", "designed (Lucide set); zero-code global win"),
 ("Button / ButtonTable / IconButton (`ui/widget/button.lua`, `buttontable.lua`, `iconbutton.lua`)", str(W.get('Button', 87)) + "+", "ButtonDialog, ConfirmBox, MultiConfirmBox, InputDialog, Spin/DoubleSpin/DateTime, TextViewer, ImageViewer, KeyboardLayoutDialog, RadioButtonWidget, FontChooser, crop dialog, DictQuickLookup, BookStatusWidget, KeyValuePage, Menu, TouchMenu, SkimTo, SortWidget, CalendarView, FrontLightWidget", "`.ko-btn`/`.dl-btn` 40px: ghost secondary, small accent primary, danger; actions right-aligned, no grid lines", "designed"),
 ("TitleBar (`ui/widget/titlebar.lua`)", "28", "Menu, KeyValuePage, TextViewer, SortWidget, InputDialog, Spin/DoubleSpin/DateTime, BookMap, PageBrowser, ImageViewer, CalendarView, ReaderProgress, FileManager, BookStatusWidget, DictQuickLookup, FontChooser, FrontLight/NaturalLight, RadioButtonWidget, KeyboardLayoutDialog", "`.ko-header` (screens: back, title, actions) / `.ko-sheet-head` (17px semibold + sub + close right) / `.dl-title`", "designed"),
 ("Dialog frame: MovableContainer + FrameContainer defaults", "16 widgets", "ButtonDialog, ConfirmBox, DictQuickLookup, DoubleSpin, FontChooser, InfoMessage, InputDialog, KeyboardLayoutDialog, MultiConfirmBox, OpenWithDialog, RadioButtonWidget, style-tweak editor, SkimTo, SpinWidget, TextViewer", "`.ko-dialog` (centred, compact) or `.ko-sheet` (bottom) frame, hairline border, card surface", "designed"),
 ("InfoMessage (`ui/widget/infomessage.lua`)", str(W["InfoMessage"]), "every plugin and module", "rule: messages with a `timeout` or reporting a finished result → App.toast; errors/explanations needing reading → `info` dialog (no icon circle, 17px title, OK right)", "designed"),
 ("Notification (`ui/widget/notification.lua`)", str(W["Notification"]), "copy, font size/frontlight gestures, style changes, location history", "App.toast", "designed"),
 ("ConfirmBox (`ui/widget/confirmbox.lua`)", str(W["ConfirmBox"]), "delete, exit, overwrite, reset, sync prompts, network prompts", "`confirm` (danger variant when ok_text is Delete/Remove/Reset)", "designed"),
 ("MultiConfirmBox (`ui/widget/multiconfirmbox.lua`)", str(W["MultiConfirmBox"]), "fonts, typography language, OTA failure, page turns, random file, wallabag/news", "three-action dialog like `paste-conflict`", "designed (pattern)"),
 ("ButtonDialog + ButtonSelector (`ui/widget/buttondialog.lua`, `buttonselector.lua`)", f"{W['ButtonDialog']} + {W['ButtonSelector']}", "all long-press menus, quick menu, external link, search navigation, filters, selection popup, plus menu", "with `anchor` → `.ko-popover`; otherwise bottom action sheet (`book-actions` rows: icon + label, title as sheet head); ButtonSelector → radio rows", "designed (pattern)"),
 ("InputDialog + MultiInputDialog + OpenWithDialog + InputText (`ui/widget/inputdialog.lua`, `multiinputdialog.lua`, `inputtext.lua`)", f"{W['InputDialog']} + {W['MultiInputDialog']}", "all text entry, password, search, forms, fullscreen editors", "`input` (soft filled field, desc, check row, right-aligned actions) / form sheets / `text-editor` for fullscreen", "designed; replaces patch `2-dialogs.lua`"),
 ("VirtualKeyboard + VirtualKeyPopup + KeyboardLayoutDialog (`ui/widget/virtualkeyboard.lua`, `keyboardlayoutdialog.lua`)", "1 + 2 + 2", "every InputDialog", "`keyboard` overlay (48px keys, Done key)", "keyboard designed; key popup and layout switcher missing"),
 ("SpinWidget + DoubleSpinWidget + DateTimeWidget + NumberPickerWidget (`ui/widget/spinwidget.lua`, `doublespinwidget.lua`, `datetimewidget.lua`, `numberpickerwidget.lua`)", f"{W['SpinWidget']} + {W['DoubleSpinWidget']} + {W['DateTimeWidget']}", "every numeric setting, ConfigDialog fine-tune, timers, footer/dictionary/TOC/search settings", "compact dialog with `App.sliderRow` (one or two) / Hour-Minute steppers; Default · Cancel · Set", "**missing — design it first (100 sites)**"),
 ("TextViewer + ScrollTextWidget (`ui/widget/textviewer.lua`, `scrolltextwidget.lua`)", str(W["TextViewer"]), "descriptions, translation, view HTML, notes, CSS, notifications history, the paragraph-translate patch", "`view-html`/`translate` page-or-sheet with header actions (Find, font size) as popover", "designed (pattern)"),
 ("KeyValuePage (`ui/widget/keyvaluepage.lua`)", str(W["KeyValuePage"]), "book info, all statistics lists, battery/system stats, gesture intervals, RSS feeds, aliases, lookup histories", "`book-details` rows (label left in `--text-2`, value right), `.ko-pager`", "designed (pattern)"),
 ("Menu + MenuItem (`ui/widget/menu.lua`) → BookList → FileChooser → PathChooser; CloudStorage, OPDSBrowser, SyncService", f"{W['Menu']} + {W['BookList']} + {W['FileChooser']} + {W['PathChooser']}", "TOC, bookmarks, search results, collections, history, shortcuts, OPDS, cloud, dictionary download list, page map, defaults editor", "list page: `.ko-row` 48px, hairline separators, `.ko-pager` (tap → Go to page `input`), status/progress badges like the library list", "designed (pattern); PathChooser 'choose' footer missing"),
 ("SortWidget (`ui/widget/sortwidget.lua`)", str(W["SortWidget"]), "arrange collections/books/footer items/actions/dictionaries/vocab filter/cloud servers", "Arrange page (rows with handle + up/down, Save)", "partial (dict-manager order only)"),
 ("TouchMenu + TouchMenuBar + TouchMenuItem (`ui/widget/touchmenu.lua`)", "2", "the whole top menu in library and reader, plus every plugin menu", "`main-menu` (tabs as text with accent underline, rows with icons, breadcrumbs, footer)", "designed; existing patches `2-menu-panel.lua`, `2-clean-menus.lua` to be superseded"),
 ("ConfigDialog + ToggleSwitch + ButtonProgressWidget + OptionTextItem/OptionIconItem (`ui/widget/configdialog.lua`)", "1", "bottom typesetting panel (EPUB and PDF)", "`typeset` sheet (tabs, sliders, segments)", "designed"),
 ("CheckButton / CheckMark / RadioMark / RadioButtonTable", f"{W.get('CheckButton', 37)}+", "dialogs, menus, OpenWith, search options", "`App.check`, `App.toggle`, `App.radio`", "designed"),
 ("ProgressWidget (`ui/widget/progresswidget.lua`)", "14", "footer bar, book map, skim, Project: Title progress bars, ProgressbarDialog", "`App.progress` thin 2–3px line, accent fill", "designed"),
 ("ImageViewer (`ui/widget/imageviewer.lua`)", str(W["ImageViewer"]), "covers, images in books, screenshots, archives, OPDS streaming", "full-bleed image page", "**missing**"),
 ("QRMessage, ProgressbarDialog, TrapWidget/Trapper, RadioButtonWidget", f"{W['QRMessage']} + {W['ProgressbarDialog']} + {W['TrapWidget']} + {W['RadioButtonWidget']}", "QR, downloads, tap-to-cancel long jobs, night-mode choice", "`qr`, progress states (OPDS/update), toast with Cancel, radio rows", "designed (patterns)"),
 ("VerticalScrollBar / LineWidget", "—", "scrollable text, separators everywhere", "thin bar; hairline `--line` separators", "scrollbar style missing (P3)"),
]
for i, r in enumerate(rows, 1):
    P(f"| {i} | {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} |")
P("")
P("### Widgets that draw themselves (a global restyle does NOT reach them; port each one)")
P("")
P("They only partly inherit (buttons, title bars, fonts, icons) and need their own Lua work against the named Folio design:")
P("")
selfdrawn = [
 ("ReaderFooter (`frontend/apps/reader/modules/readerfooter.lua`)", "`.rd-foot` + footer modes (gap rd.footer.modes)"),
 ("ReaderDogear, ReaderFlipping, ReaderView highlight/selection drawing, LinkBox, page gaps", "`.rd-dogear`, highlight styles; flipping indicator and link box are gaps"),
 ("DictQuickLookup (`ui/widget/dictquicklookup.lua`)", "`dict` / `wiki` sheets (+ empty states gap)"),
 ("FootnoteWidget (`ui/widget/footnotewidget.lua`)", "gap rd.footnote (P1)"),
 ("BBoxWidget (`ui/widget/bboxwidget.lua`) crop UI", "gap rd.crop"),
 ("SkimToWidget, BookMapWidget, PageBrowserWidget", "`skim`, `bookmap`, `pagebrowser`"),
 ("BookStatusWidget / AltBookStatusWidget (Project: Title)", "`book-status`"),
 ("FrontLightWidget / NaturalLightWidget", "`frontlight`"),
 ("ScreenSaverWidget / ScreenSaverLockWidget", "`sleep`, `lockscreen` (lock prompt is a gap)"),
 ("NetworkSetting (`ui/widget/networksetting.lua`)", "`wifi`"),
 ("CalendarView / CalendarDayView / ReaderProgress (statistics)", "`stats` (month calendar and day timeline are gaps)"),
 ("VocabularyBuilderWidget / WordInfoDialog / MenuDialog", "`vocab`, `ex-vb-word`, `ex-vb-settings`"),
 ("Project: Title MosaicMenu / ListMenu / titlebar / footer, FileManager layout", "`library`, `folder`, `history`, `collection`"),
 ("TweakInfoWidget, Screenshoter, Terminal (TermInputText), IndicatorOverlay", "gaps / `terminal`"),
]
for a, b in selfdrawn:
    P(f"- {a} → {b}")
P("")
P("## Notes for the port")
P("")
P("- **Night mode vs. Dark theme:** KOReader night mode inverts the whole framebuffer. On e-ink, Folio's Dark theme will in practice be the inverted Paper theme; check every Paper design inverted, including covers and highlight greys (inverted images are re-inverted by KOReader only for some content).")
P("- **Existing user patches overlap the port:** `2-clean-menus.lua` (square corners, non-bold buttons, TouchMenu sizes), `2-menu-panel.lua`, `2-library-panel.lua`, `2-dialogs.lua`, `2-font-override.lua` (Source Sans) and `2-paragraph-translate.lua` (TextViewer translation). Replace or merge them, otherwise two styles fight (e.g. radius 0 vs. Folio's rounded sheets).")
P("- **Kindle native pieces cannot be restyled from Lua:** the Kindle activity spinner (`readeractivityindicator.lua`, uses lipc) and the Kindle lock/ads screen when the device still has special offers (KOReader's sleep screen only shows if `supportsScreensaver`).")
P("- **Disable the stock Cover browser plugin** (Project: Title replaces it) so its mosaic/list and its spinner dialogs never appear.")
P("- **One-time / first-run surfaces** to test on a clean profile: quickstart guide, 'Gestures have been upgraded' (`plugins/gestures.koplugin/main.lua:1310`), first multiswipe prompt (`:1334`), 'Restore metadata from archive?' (`frontend/apps/reader/readerui.lua:649`), Project: Title first indexing progress, 'No dictionaries installed' dictionary state.")
P("- **Gesture-only surfaces** in this audit: footer tap (modes) and hold (settings menu), top-left tap (flipping mode), top-right tap (dog-ear), long-press on word/image/link/TOC entry/bookmark/collection/history item/menu row/config option/key/globe key/text field, two-finger diagonal swipe (screenshot), pinch/spread (zoom / font-size notification), swipe left edge (frontlight notification), quick-menu gestures.")
P("")
open("./coverage/coverage-report.md", "w").write("\n".join(L) + "\n")
print("ok", len(L))
