# Leaf coverage audit: every KOReader surface vs. the prototype

Generated 2026-11-19 against KOReader v2026.07.1 (`$KOREADER_DIR/lib/koreader`), the Project: Title plugin and the user patches in `~/.config/koreader/`, and the prototype in `js/screens/*.js` + `js/data/menus.js`.

**Goal:** after the Lua port, no screen, dialog, toast or piece of chrome may still show the old KOReader look. This file is the checklist; `inventory.json` holds every surface (`surfaces`) and every widget construction site found in the source (`sites`, each tagged with the surface it belongs to).

## How it was built

- Scanned all Lua in `frontend/`, `plugins/`, Project: Title and the patches for constructions of visible widgets (`InfoMessage:new`, `ConfirmBox:new`, `ButtonDialog:new`, `SpinWidget:new`, `Notification:notify`, … 60 widget types) and `UIManager:show(` calls: **1183 construction sites, 1146 show calls**.
- Grouped them into **270 surfaces** (trivial variants are one surface: the 395 `InfoMessage` texts are one 'info message' type, notable ones are listed separately). Every site is assigned: explicitly to a curated surface, or by widget type to its base-widget surface (`assigned` field).
- Added persistent chrome that is drawn, not shown as a widget (footer, dog-ear, flipping indicator, highlights, link box, crop box, page gaps, Project: Title grid/list/title bar/footer).
- Mapped each surface to the prototype: overlays/screens registered with `App.screen/App.overlay`, states registered with `App.demo`, menu-row links in `App.menuSpecial`, and the generic menu engine for plain `KO_MENUS` rows (not counted as gaps).

Legend: **designed** = a Leaf screen/overlay designs it · **generic** = no dedicated design, but a designed Leaf component covers it *once the base widget is restyled globally in the port* · **partial** = designed in part, a state or sub-surface is missing · **missing** = nothing covers it. Priority (gaps only): **P1** daily reading/library use, **P2** occasional, **P3** rare/power-user. Kindle = relevant on a touch Kindle (Kindle 11: frontlight, no warmth, no keys, Kindle handles USB itself).

## Totals

| Surfaces | Designed | Generic | Partial | Missing | Kindle-relevant gaps (partial + missing) |
|---:|---:|---:|---:|---:|---:|
| 270 | 122 | 96 | 15 | 37 | 49 |

## Summary per area

| Area | Total | Designed | Generic | Partial | Missing | Kindle gaps |
|---|---:|---:|---:|---:|---:|---:|
| Base widgets (generic types) | 37 | 7 | 18 | 2 | 10 | 11 |
| Library & file manager | 27 | 16 | 9 | 0 | 2 | 2 |
| History, collections, shortcuts, file search | 25 | 14 | 7 | 2 | 2 | 4 |
| Reader: page & persistent chrome | 17 | 8 | 2 | 2 | 5 | 6 |
| Reader: selection, highlights, links, footnotes | 18 | 6 | 7 | 0 | 5 | 5 |
| Reader: navigation panels | 31 | 13 | 10 | 2 | 6 | 8 |
| Reader: typesetting & document | 14 | 8 | 5 | 1 | 0 | 1 |
| Reader: dictionary, Wikipedia, translation | 12 | 8 | 2 | 1 | 1 | 2 |
| Menus & settings | 21 | 10 | 10 | 0 | 1 | 0 |
| System, network, device | 14 | 10 | 3 | 0 | 1 | 1 |
| Plugins | 50 | 20 | 22 | 4 | 4 | 8 |
| Project: Title plugin | 4 | 2 | 1 | 1 | 0 | 1 |

Note: the 'Base widgets' row counts widget *types*. Its gaps are the most important ones, because each type is shown from many places (see the site counts in the safety-net table).

## Gaps (missing and partial), by priority

Each line: id · what · KOReader file:line · trigger · widget · design suggestion (Leaf component/pattern to use).

### P1 (4 Kindle-relevant)

- **Footer mode cycling (tap footer) & hidden footer** (`rd.footer.modes`, partial)  
  KOReader: `frontend/apps/reader/modules/readerfooter.lua:2423`, `frontend/apps/reader/modules/readerfooter.lua:2485` · Trigger: tap the footer · Widget: ReaderFooter. Leaf today: only one footer layout is shown.  
  Design: Define each single-item mode and the progress-bar-only/hidden state with the same `.rd-foot` typography; cycle on tap.
- **Page-flipping mode (indicator icon + flipping behaviour) and re-rendering indicator** (`rd.flipping`, missing)  
  KOReader: `frontend/apps/reader/modules/readerflipping.lua:17`, `frontend/apps/reader/modules/readerflipping.lua:58` · Trigger: tap top-left corner (default gesture!), or CRE background re-render after a font change · Widget: ReaderFlipping.  
  Design: Small 24px Lucide icon chip (gallery-horizontal / loader) in the top-left with `--text` stroke, plus a thin banner 'Flipping mode · swipe to skim, tap to exit'.
- **Footnote / endnote popup** (`rd.footnote`, missing)  
  KOReader: `frontend/apps/reader/modules/readerlink.lua:1584`, `frontend/apps/reader/modules/readerlink.lua:373`, `frontend/apps/reader/modules/readerlink.lua:396` · Trigger: tap a footnote link · Widget: FootnoteWidget (+ font-size SpinWidgets).  
  Design: Bottom `.ko-sheet` (no grip) with the note in Literata at reading size, hairline top border, link 'Open in book' and close; e-ink safe.
- **Dictionary popup states: no results / no dictionaries / interrupted** (`dc.empty`, missing)  
  KOReader: `frontend/apps/reader/modules/readerdictionary.lua:1383`, `frontend/apps/reader/modules/readerdictionary.lua:1411`, `frontend/apps/reader/modules/readerdictionary.lua:1618` (+1 more) · Trigger: lookup of a name/unknown word; fresh install · Widget: DictQuickLookup state + InputDialog. Leaf today: dict demo always has a definition.  
  Design: Same `dict` sheet with `.ko-empty` body: 'No definition for “X”' + actions Edit word, Wikipedia, Translate; no-dictionary state links to `dict-manager` catalog.

### P2 (20 Kindle-relevant)

- **Number spinner dialog (− value + , Default, Apply)** (`w.spinwidget`, missing, 74 construction sites of this type)  
  KOReader: `frontend/ui/widget/spinwidget.lua:1`, `frontend/ui/widget/numberpickerwidget.lua:132`, `frontend/ui/widget/numberpickerwidget.lua:184` (+3 more) · Trigger: ≈74 sites: every numeric menu setting (items per page, font sizes, margins, intervals), hold on config options; tapping the value opens an 'Enter number' InputDialog with range errors · Widget: SpinWidget (+NumberPickerWidget).  
  Design: One compact centred dialog: title (17px), one App.sliderRow (label − slider + value) or stepper for unbounded values, help text, actions Default · Cancel · Set. Tap on value → `input` numeric layout. Highest leak count after InfoMessage/ConfirmBox: restyle globally.
- **Double number spinner (two values)** (`w.doublespinwidget`, missing, 14 construction sites of this type)  
  KOReader: `frontend/ui/widget/doublespinwidget.lua:1` · Trigger: 13 sites: mosaic columns×rows, battery thresholds, refresh, hyphenation limits, info-list items, location lat/long · Widget: DoubleSpinWidget.  
  Design: Same dialog as the SpinWidget design with two App.sliderRow lines (left/right labels).
- **Date / time picker** (`w.datetimewidget`, partial, 12 construction sites of this type)  
  KOReader: `frontend/ui/widget/datetimewidget.lua:8`, `frontend/ui/widget/datetimewidget.lua:24`, `frontend/ui/widget/datetimewidget.lua:40` · Trigger: 12 sites: read timer alarm, autoturn, autosuspend, profiles schedule, autowarmth, stats day start, set clock · Widget: DateTimeWidget. Leaf today: `read-timer` sheet uses Hour/Minute stepper rows.  
  Design: Generic dialog with Hour / Minute (and Y/M/D) stepper columns like read-timer's rows; Cancel · Set.
- **Sort / arrange list (move up/down, drag)** (`w.sortwidget`, partial, 10 construction sites of this type)  
  KOReader: `frontend/ui/widget/sortwidget.lua:432`, `frontend/ui/widget/sortwidget.lua:553` · Trigger: 9 sites: arrange collections, books in collection, status bar items, dispatcher actions, dictionaries, vocabulary book filter, cloud servers · Widget: SortWidget. Leaf today: dict-manager order list (Dictionaries · Arabic books order) is the only designed arrange list.  
  Design: Generic 'Arrange' page: rows with a drag handle and up/down steppers, footer Cancel · Save; its overflow ButtonDialog (move to top/bottom) → action sheet.
- **Folder / file chooser** (`w.pathchooser`, missing, 20 construction sites of this type)  
  KOReader: `frontend/ui/widget/pathchooser.lua:128`, `frontend/ui/widget/pathchooser.lua:157`, `frontend/ui/downloadmgr.lua:48` · Trigger: 20 sites: set HOME folder, download folder, screensaver folder, custom cover, collections folder, cloud, text editor open · Widget: PathChooser (FileChooser subclass).  
  Design: Reuse the `folder` screen with a pinned bottom bar: current path + 'Use this folder' (accent) / Cancel; files greyed when choosing a folder; shortcuts button opens `lib-shortcuts`.
- **Image viewer (zoom/pan/rotate, buttons)** (`w.imageviewer`, missing, 8 construction sites of this type)  
  KOReader: `frontend/ui/widget/imageviewer.lua:908` · Trigger: 8 sites: book cover, image in book (hold), screenshot preview, archive images, OPDS page streaming · Widget: ImageViewer.  
  Design: Full black page, image fitted, thin top bar (title, close) and a bottom toolbar (rotate, zoom fit, save); e-ink: no gradients.
- **Keyboard key long-press popup (accents / alternates, swipe keys)** (`w.virtualkeypopup`, missing, 2 construction sites of this type)  
  KOReader: `frontend/ui/widget/virtualkeyboard.lua:107`, `frontend/ui/widget/virtualkeyboard.lua:181` · Trigger: long-press a key · Widget: VirtualKeyPopup.  
  Design: Small `.ko-popover` above the key with 44px cells, accent outline on the hovered character.
- **Book cover viewer** (`bi.cover`, missing)  
  KOReader: `frontend/apps/filemanager/filemanagerbookinfo.lua:448`, `frontend/apps/filemanager/filemanagerbookinfo.lua:455` · Trigger: tap the cover in book info · Widget: ImageViewer. Leaf today: only an `info` text card.  
  Design: ImageViewer design (full-bleed cover, close/rotate/save).
- **Manual PDF crop (bounding-box editor)** (`rd.crop`, missing)  
  KOReader: `frontend/apps/reader/modules/readercropping.lua:98`, `frontend/apps/reader/modules/readercropping.lua:108` · Trigger: PDF typeset › Crop › Manual · Widget: BBoxWidget + ButtonTable. Leaf today: typeset Crop tab shows auto-crop margins only.  
  Design: Full page with four accent corner handles, dimmed outside area (solid, not gradient), bottom bar: Cancel · Reset · Apply.
- **Image in book viewer** (`rd.image`, missing)  
  KOReader: `frontend/ui/widget/textboxwidget.lua:2379`, `frontend/apps/reader/modules/readerhighlight.lua:1625`, `frontend/apps/reader/modules/readerhighlight.lua:1666` · Trigger: long-press an illustration · Widget: ImageViewer.  
  Design: ImageViewer design.
- **Tapped-link feedback box** (`rd.linkbox`, missing)  
  KOReader: `frontend/apps/reader/modules/readerlink.lua:689` · Trigger: tap any internal link · Widget: LinkBox.  
  Design: 1.5px `--page-ink` rounded underline/box flash (no fill).
- **External link dialog** (`rd.link.external`, missing)  
  KOReader: `frontend/apps/reader/modules/readerlink.lua:980` · Trigger: tap an http link · Widget: ButtonDialog.  
  Design: Action sheet with the URL as `.ko-sheet-head .sub`.
- **Bookmark item long-press / tap actions** (`rd.bookmarks.longpress`, partial)  
  KOReader: `frontend/apps/reader/modules/readerbookmark.lua:1062` · Trigger: long-press an item in the list · Widget: ButtonDialog. Leaf today: rows have only a trash icon; annotation tap → hl-popup.  
  Design: Action sheet headed by the snippet: Go to, Edit note, Edit text, Remove, Select…; same for annotations rows.
- **In-page search navigation bar (⌛ wait, ◁◁ ◁ ↺ ▷ ▷▷, back to results / original page)** (`rd.search.nav`, missing)  
  KOReader: `frontend/apps/reader/modules/readersearch.lua:525`, `frontend/apps/reader/modules/readersearch.lua:545`, `frontend/apps/reader/modules/readersearch.lua:866` (+1 more) · Trigger: after jumping to a search hit · Widget: ButtonDialog (small, bottom).  
  Design: Floating bottom pill (like reader chrome scrubber): ‹ prev · '3 of 41' · next ›, 'Results' and close; e-ink solid.
- **Gesture quick menu (multiple actions on one gesture)** (`rd.quickmenu`, missing)  
  KOReader: `frontend/dispatcher.lua:1446` · Trigger: a gesture set to 'Show as quick menu' · Widget: ButtonDialog.  
  Design: Anchored/bottom `.ko-popover` of icon rows (same as `reader-more`), title = gesture name.
- **Current book statistics** (`pl.stats.current`, missing)  
  KOReader: `plugins/statistics.koplugin/main.lua:1262`, `plugins/statistics.koplugin/main.lua:2979` · Trigger: stats › Current book; gesture 'Book statistics' · Widget: KeyValuePage. Leaf today: stats-menu › Current book is a toast.  
  Design: Book-details style page with a hero (time read, % done) + KV rows; reachable from reader chrome.
- **Calendar view (month grid with book bars)** (`pl.stats.calendar`, partial)  
  KOReader: `plugins/statistics.koplugin/main.lua:2749`, `plugins/statistics.koplugin/calendarview.lua:1226` · Trigger: stats › Calendar view · Widget: CalendarView. Leaf today: year heatmap only (`stats?range=year`).  
  Design: Month grid page (7 columns, day number + thin per-book bars in `--text-2`, today outlined), swipe months.
- **Day timeline (hour-by-hour)** (`pl.stats.day`, missing)  
  KOReader: `plugins/statistics.koplugin/calendarview.lua:1453`, `plugins/statistics.koplugin/calendarview.lua:1493` · Trigger: calendar › tap a day; stats › Today's timeline · Widget: CalendarDayView.  
  Design: Vertical 24h timeline with session blocks per book (solid fills, book titles), header with day total.
- **Read timer (set, running, time's up)** (`pl.readtimer`, partial)  
  KOReader: `plugins/readtimer.koplugin/main.lua:66`, `plugins/readtimer.koplugin/main.lua:77`, `plugins/readtimer.koplugin/main.lua:95` (+7 more) · Trigger: Tools › Read timer; alarm fires · Widget: DateTimeWidget / ConfirmBox / InfoMessage / Notification. Leaf today: `read-timer` sheet (set + running); the expiry alert itself not designed.  
  Design: Expiry: `confirm`-style dialog with the timer message, actions 'Repeat 20 min' (primary) · Close.
- **Project: Title grid/list size dialogs** (`pt.spins`, partial)  
  KOReader: `~/.config/koreader/plugins/projecttitle.koplugin/main.lua:462`, `~/.config/koreader/plugins/projecttitle.koplugin/main.lua:510`, `~/.config/koreader/plugins/projecttitle.koplugin/main.lua:560` · Trigger: settings › Items per page · Widget: DoubleSpinWidget / SpinWidget. Leaf today: View sheet · grid & list settings shows inline steppers.  
  Design: Covered once the DoubleSpin/Spin generic exists.

### P3 (25 Kindle-relevant)

- **Keyboard layout switcher** (`w.keyboardlayoutdialog`, missing, 2 construction sites of this type)  
  KOReader: `frontend/ui/widget/virtualkeyboard.lua:111`, `frontend/ui/widget/virtualkeyboard.lua:347`, `frontend/ui/widget/keyboardlayoutdialog.lua:1` · Trigger: long-press the globe key · Widget: KeyboardLayoutDialog.  
  Design: Anchored popover of radio rows (language names), 'Keyboard settings…' link at the bottom.
- **Text-field clipboard menu / snippets** (`w.clipboard`, missing)  
  KOReader: `frontend/ui/widget/inputtext.lua:366`, `frontend/ui/widget/inputtext.lua:415`, `frontend/ui/widget/inputtext.lua:454` (+2 more) · Trigger: hold on a text field · Widget: ButtonDialog + MultiInputDialog.  
  Design: Anchored `.ko-popover` row of actions above the field; snippets as a sheet list.
- **Scroll bars in scrollable text** (`w.scrollbar`, missing)  
  KOReader: `frontend/ui/widget/verticalscrollbar.lua:1`, `frontend/ui/widget/scrolltextwidget.lua:1`, `frontend/ui/widget/scrollhtmlwidget.lua:1` (+1 more) · Trigger: long InfoMessage/TextViewer/dictionary definitions · Widget: VerticalScrollBar.  
  Design: Thin 3px `--text-3` track-less bar on the right (Leaf relies on native scrolling; define one style).
- **Open with… dialog** (`w.openwith`, missing, 1 construction sites of this type)  
  KOReader: `frontend/apps/filemanager/filemanager.lua:1606`, `frontend/apps/filemanager/filemanager.lua:1578`, `frontend/apps/filemanager/filemanager.lua:1588` · Trigger: book long-press › Open with… · Widget: OpenWithDialog (InputDialog subclass) + ConfirmBox. Leaf today: `book-actions` › Open with… is only a toast.  
  Design: Sheet of radio rows (engine names) + two check rows (this file / all .epub) + Open; 'Always open with' confirms → `confirm`.
- **Show selected files list** (`fm.select.list`, missing)  
  KOReader: `frontend/apps/filemanager/filemanager.lua:1459` · Trigger: select mode › Show selected files list · Widget: BookList.  
  Design: List page (detailed list rows) with 'Deselect' trailing action.
- **Screenshot taken (preview + saved dialog)** (`fm.screenshot`, missing)  
  KOReader: `frontend/apps/filemanager/filemanager.lua:400`, `frontend/apps/reader/readerui.lua:240`, `frontend/ui/widget/screenshoter.lua:90` (+1 more) · Trigger: two-finger diagonal swipe / gesture action · Widget: Screenshoter → ImageViewer + ButtonDialog.  
  Design: Toast 'Screenshot saved' with a 'View' action; viewing uses the ImageViewer design.
- **Arrange collections / books in collection** (`co.arrange`, partial)  
  KOReader: `frontend/apps/filemanager/filemanagercollection.lua:779`, `frontend/apps/filemanager/filemanagercollection.lua:793`, `frontend/apps/filemanager/filemanagercollection.lua:1453` · Trigger: collection menu › Arrange / Sort · Widget: SortWidget / ButtonDialog. Leaf today: sort radios designed; manual arrange list not.  
  Design: Generic Arrange page (see SortWidget).
- **Collection auto-folders (add folder, file types)** (`co.folders`, partial)  
  KOReader: `frontend/apps/filemanager/filemanagercollection.lua:1083`, `frontend/apps/filemanager/filemanagercollection.lua:1117`, `frontend/apps/filemanager/filemanagercollection.lua:1139` (+5 more) · Trigger: collection menu › Connect folders · Widget: Menu + PathChooser + InputDialog + ButtonSelector. Leaf today: 'Add a folder…' is a toast in `lib-coll-menu`.  
  Design: List page of folders + PathChooser design + `input` for file types.
- **Edit book metadata / custom cover / reset** (`bi.metadata`, missing)  
  KOReader: `frontend/apps/filemanager/filemanagerbookinfo.lua:518`, `frontend/apps/filemanager/filemanagerbookinfo.lua:596`, `frontend/apps/filemanager/filemanagerbookinfo.lua:673` (+2 more) · Trigger: book info › hold a field / Set custom cover · Widget: ButtonDialog + InputDialog + PathChooser + ConfirmBox. Leaf today: book-details shows Ignore cover / Ignore metadata toggles only.  
  Design: In book-details: tap a value → action sheet (Edit, Reset, Copy) → `input`; 'Custom cover' row → PathChooser.
- **Kindle activity indicator (native spinner)** (`rd.activity`, missing)  
  KOReader: `frontend/apps/reader/modules/readeractivityindicator.lua:43` · Trigger: long operations on Kindle · Widget: Kindle lipc spinner.  
  Design: Native Kindle framework widget, cannot be restyled in Lua; disable it and show a Leaf toast instead if desired.
- **Continuous / scroll mode page gaps** (`rd.pagegap`, partial)  
  KOReader: `frontend/apps/reader/modules/readerview.lua:372`, `frontend/apps/reader/modules/readerview.lua:445`, `frontend/apps/reader/modules/readerscrolling.lua:156` (+1 more) · Trigger: View mode: continuous · Widget: ReaderView / ReaderScrolling. Leaf today: PDF continuous designed (page_scroll); EPUB scroll mode not shown.  
  Design: Same page with a hairline/`--page` gap between pages; no chrome change.
- **Perception expander guide lines** (`rd.perception`, missing)  
  KOReader: `plugins/perceptionexpander.koplugin/main.lua:103`, `plugins/perceptionexpander.koplugin/main.lua:182` · Trigger: plugin enabled · Widget: Widget (lines on page) + MultiInputDialog.  
  Design: 1px `--page-ink` 30% lines; settings via form sheet.
- **Overlapping highlights chooser** (`rd.hl.multiple`, missing)  
  KOReader: `frontend/apps/reader/modules/readerhighlight.lua:1279` · Trigger: tap where 2+ highlights overlap · Widget: ButtonDialog (menu_style list).  
  Design: Anchored `.ko-popover` listing each highlight (swatch + snippet).
- **Bookmark details viewer (prev/next)** (`rd.bookmarks.view`, missing)  
  KOReader: `frontend/apps/reader/modules/readerbookmark.lua:1362` · Trigger: tap ⓘ on a bookmark / hold · Widget: TextViewer.  
  Design: Sheet with full quote + note, prev/next arrows in the head.
- **Bookmark list select mode & bulk removes** (`rd.bookmarks.select`, partial)  
  KOReader: `frontend/apps/reader/modules/readerbookmark.lua:871`, `frontend/apps/reader/modules/readerbookmark.lua:900`, `frontend/apps/reader/modules/readerbookmark.lua:1320` · Trigger: list menu › Select · Widget: ConfirmBox.  
  Design: Reuse library select bar inside the sheet; confirms → `confirm`.
- **Pinned page (remove pinned page)** (`rd.pin`, missing)  
  KOReader: `frontend/apps/reader/modules/readergoto.lua:65` · Trigger: skim › pin; go to dialog · Widget: ConfirmBox. Leaf today: no pinned-page concept in skim/goto.  
  Design: Pin chip in `skim` + `confirm`.
- **Book map / page browser options & help** (`rd.bookmap.menu`, missing)  
  KOReader: `frontend/ui/widget/bookmapwidget.lua:1491`, `frontend/ui/widget/bookmapwidget.lua:1524`, `frontend/ui/widget/bookmapwidget.lua:1557` (+4 more) · Trigger: title-bar menu / hold · Widget: ButtonDialog / InfoMessage.  
  Design: Anchored popover with seg/slider rows (columns, thumbnails), help as `menu-help`.
- **Stable / publisher page numbers** (`rd.pagemap`, missing)  
  KOReader: `frontend/apps/reader/modules/readerpagemap.lua:90`, `frontend/apps/reader/modules/readerpagemap.lua:280`, `frontend/apps/reader/modules/readerpagemap.lua:412` (+5 more) · Trigger: settings › Stable page numbers · Widget: Menu / InfoMessage / SpinWidget / ConfirmBox.  
  Design: List page like TOC (page labels), settings via generics.
- **Style tweaks: CSS info, book-specific editor, suggestions** (`rd.styletweak`, partial)  
  KOReader: `frontend/apps/reader/modules/readerstyletweak.lua:241`, `frontend/apps/reader/modules/readerstyletweak.lua:497`, `frontend/apps/reader/modules/readerstyletweak.lua:559` (+12 more) · Trigger: long-press a tweak; Book-specific tweak · Widget: TweakInfoWidget / InputDialog / ButtonDialog / Notification. Leaf today: tweaks menu designed (Drill · Style tweaks › Text); TweakInfoWidget not.  
  Design: TweakInfoWidget → `menu-help` style sheet with monospace CSS block + Copy; editor → `text-editor`.
- **Dictionary popup extra menus (hold buttons, more…)** (`dc.buttons`, partial)  
  KOReader: `frontend/ui/widget/dictquicklookup.lua:892`, `frontend/ui/widget/dictquicklookup.lua:1929`, `frontend/ui/widget/dictquicklookup.lua:2020` (+4 more) · Trigger: hold Highlight/Search/Wikipedia buttons, title menu · Widget: ButtonDialog.  
  Design: Anchored popover from the pressed button.
- **Screensaver lock ('swipe/tap to unlock')** (`sy.screensaver.lock`, missing)  
  KOReader: `frontend/ui/screensaver.lua:654`, `frontend/ui/widget/screensaverlockwidget.lua:104` · Trigger: wake when 'delay' = gesture to exit · Widget: ScreenSaverLockWidget.  
  Design: Small bottom pill on the sleep screen: 'Swipe up to unlock'.
- **Time-range statistics & drill-downs** (`pl.stats.range`, partial)  
  KOReader: `plugins/statistics.koplugin/main.lua:1305`, `plugins/statistics.koplugin/main.lua:1314`, `plugins/statistics.koplugin/main.lua:1331` (+16 more) · Trigger: stats › Time range › Last week / by month / Books read in… · Widget: KeyValuePage. Leaf today: dashboard month/year cards; the per-day/per-book lists are not.  
  Design: KV generic list pages with the stats header; tap a day → day timeline.
- **All books statistics list & reset** (`pl.stats.books`, partial)  
  KOReader: `plugins/statistics.koplugin/main.lua:2318`, `plugins/statistics.koplugin/main.lua:2418`, `plugins/statistics.koplugin/main.lua:2436` (+3 more) · Trigger: stats › All books; Reset statistics · Widget: KeyValuePage / ConfirmBox. Leaf today: per-book section in stats + reset confirm.  
  Design: List page of books (cover, time, pages) → current-book stats page.
- **OPDS page streaming (PSE) viewer** (`pl.opds.pse`, missing)  
  KOReader: `plugins/opds.koplugin/opdspse.lua:46`, `plugins/opds.koplugin/opdspse.lua:74`, `plugins/opds.koplugin/opdspse.lua:133` (+2 more) · Trigger: OPDS › Page stream (Komga, Kavita) · Widget: ImageViewer / InputDialog.  
  Design: ImageViewer design + page `input`.
- **Archive viewer (.zip contents)** (`pl.archiveviewer`, missing)  
  KOReader: `plugins/archiveviewer.koplugin/main.lua:69`, `plugins/archiveviewer.koplugin/main.lua:97`, `plugins/archiveviewer.koplugin/main.lua:234` (+5 more) · Trigger: tap a .zip in the library · Widget: BookList / ButtonDialog / ImageViewer / TextViewer / InfoMessage.  
  Design: Folder-browser screen with the archive as a folder (zip icon in crumbs), action sheet for Extract; images → ImageViewer.

### Not needed on a touch Kindle

- Focus highlight for key navigation (`w.focus`, P3) · `frontend/ui/widget/focusmanager.lua:1` · devices with keys / D-pad only
- Keyboard text selection indicator (`rd.keyselection`, P3) · `frontend/apps/reader/modules/readerkeyselection.lua:234`, `frontend/apps/reader/modules/readerkeyselection.lua:287` (+1 more) · non-touch devices
- Set device time / date (`mn.datetime`, P3) · `frontend/ui/elements/common_settings_menu_table.lua:159`, `frontend/ui/elements/common_settings_menu_table.lua:168` (+4 more) · settings › Time and date (devices that allow it)

## Surfaces covered only by a generic component

These have no dedicated design. They stay in the old look unless the base widget in the right-hand column is restyled globally (see the safety net below).

| Surface | Base widget(s) | Leaf component to mirror |
|---|---|---|
| Multi-choice confirm (3 buttons) (`w.multiconfirmbox`) | MultiConfirmBox | overlay `paste-conflict` layout (title, body, 3 actions) · Library extras › Paste conflict |
| Button dialog (centred grid of buttons) (`w.buttondialog`) | ButtonDialog | action sheet (`book-actions`/`folder-actions` .ko-sheet + .ko-row) or anchored `.ko-popover` (plus, reader-more) |
| Button selector (pick one value) (`w.buttonselector`) | ButtonSelector | radio-row sheet (`sort` sheet) / hl-popup style row |
| Multi-line text editor in InputDialog (fullscreen, with Find / Go to line / Save/Discard) (`w.inputdialog.multiline`) | InputDialog (fullscreen, allow_newline) | overlay `text-editor` (page) · Library extras › Text editor · editing notes.txt |
| Multi-field form dialog (`w.multiinputdialog`) | MultiInputDialog | form sheets `kosync` (log in), `wallabag` (setup), `ex-opds-edit` |
| Text viewer (scrollable long text, Find, font size, Top/Bottom) (`w.textviewer`) | TextViewer | `translate` sheet, `view-html` page, `menu-help`, `info` (short text) |
| Key / value page (paginated two-column list) (`w.keyvaluepage`) | KeyValuePage | `book-details` page rows (label left, value right) |
| Menu (paginated list with title bar + page footer) (`w.menu`) | Menu | list page (`.ko-page` + `.ko-row`, `.ko-pager`) e.g. dict-history, bookmark-browser, folder screens |
| Book list (Menu subclass with book status/progress) (`w.booklist`) | BookList | library detailed list rows (`library?view=detail`) |
| Progress bar dialog (download) (`w.progressbardialog`) | ProgressbarDialog | OPDS · downloading / Update · Downloading progress states |
| Trap widget (invisible 'tap to cancel' layer) (`w.trapwidget`) | TrapWidget | `info`/toast with a Cancel affordance |
| Radio button dialog (`w.radiobuttonwidget`) | RadioButtonWidget | radio rows (`App.radio`) in a dialog/sheet |
| Radio button table (inside dialogs) (`w.radiobuttontable`) | RadioButtonTable | radio rows |
| Title bar (all full-screen widgets and many dialogs) (`w.titlebar`) | TitleBar | `.ko-header` (screens) / `.ko-sheet-head` / `.dl-title` |
| Buttons / button tables (`w.button`) | Button, ButtonTable, IconButton | `.ko-btn` / `.dl-btn` (40px), `.ko-icon-btn` |
| Toggle switch / segmented buttons (`w.toggleswitch`) | ToggleSwitch, ButtonProgressWidget | `.ko-seg`, App.sliderRow |
| Font chooser dialog (`w.fontchooser`) | FontChooser | fonts list (Settings › Fonts / typeset font tab radio rows) |
| HTML box (dictionary definitions, footnotes) (`w.htmlbox`) | HtmlBoxWidget/ScrollHtmlWidget | dict body typography |
| Set as HOME folder confirm (`fm.sethome`) | ConfirmBox | `confirm` |
| Open random file (`fm.random`) | MultiConfirmBox | paste-conflict 3-action layout |
| File not found / failed operations (`fm.notfound`) | InfoMessage | App.toast / `info` (error) / `error` overlay |
| Convert document (md ↔ html) (`fm.converter`) | ButtonDialog + ConfirmBox | action sheet + `confirm` |
| Status/reset of selected docs, run script, open unsupported file (`fm.utils`) | ConfirmBox / InfoMessage / PathChooser / ButtonDialog | `confirm`, toast, `book-status` |
| Open last / previous document (`fm.lastdoc`) | InfoMessage / ConfirmBox | `confirm` |
| Clear cache / clear deleted history (`fm.cache`) | ConfirmBox | `confirm` + toast 'Cache cleared' |
| Flat 'File manager menu' / 'Document menu' list (`fm.fmlist.menu`) | Menu | menu engine (Settings pages) |
| Advanced settings (defaults.lua editor) (`fm.defaults`) | Menu + InputDialog/MultiInputDialog | menu engine list + `input`; restart `confirm` |
| Clear history of deleted files (`hi.cleardeleted`) | ConfirmBox | `confirm` + toast |
| Search in collections (`co.search`) | InputDialog / InfoMessage | `search` screen / `input` + toasts |
| Shortcut long-press, rename, add (`sc.dialogs`) | ButtonDialog / InputDialog / PathChooser | action sheet + `input`; adding uses PathChooser (see w.pathchooser) |
| Book description viewer (`bi.desc`) | TextViewer / InfoMessage | `info` (from book-actions › Book description) |
| Move metadata location (sdr/doc/hash) (`bi.metaloc`) | PathChooser/ButtonDialog/ConfirmBox/TextViewer | `confirm` / toast / text page |
| Book metadata archive (deleted books' sidecars) (`bi.archive`) | BookList + ConfirmBox + ButtonDialog | list page + action sheet + `confirm` |
| Restore metadata from archive on reopen (`bi.restore`) | ConfirmBox | `confirm` |
| Footer hold → status bar settings menu (`rd.footer.hold`) | TouchMenu | menu engine › Settings · Status bar |
| Status bar settings dialogs (`rd.footer.settings`) | SpinWidget / SortWidget / MultiInputDialog / FontChooser | spinner/arrange/form generics (see base widgets) |
| Edit highlighted text (`rd.hl.edittext`) | InputDialog | `input` |
| Select mode (extend highlight across pages) (`rd.hl.selectmode`) | ConfirmBox | toast 'Tap the word where the selection should end' + `confirm` |
| Copied / misc highlight notifications (`rd.hl.copy`) | Notification / InfoMessage | App.toast |
| Highlight settings spinners (`rd.hl.settings`) | SpinWidget | spinner generic (w.spinwidget) |
| Write highlights into PDF (`rd.hl.pdfwrite`) | ConfirmBox / Notification / InfoMessage | `confirm` / toast |
| Local document link confirm / invalid link (`rd.link.local`) | ConfirmBox / InfoMessage | `confirm` / toast |
| Location history (go back) messages (`rd.link.history`) | Notification / ConfirmBox | App.toast / `confirm` |
| TOC entry long-press (full title message) (`rd.toc.hold`) | InfoMessage | `info` (or tooltip-style popover) |
| TOC search (`rd.toc.search`) | InputDialog / InfoMessage | `input` + toast |
| Alternative TOC confirms (`rd.toc.alt`) | ConfirmBox | `confirm` |
| TOC entries per page / font size (`rd.toc.settings`) | SpinWidget | spinner generic |
| Custom TOC & hidden flows (`rd.handmade`) | InfoMessage / ConfirmBox / InputDialog | `input` / `confirm` |
| Bookmark settings & import messages (`rd.bookmarks.misc`) | SpinWidget / InfoMessage | spinner generic / toast |
| Search progress / no results / too many hits (`rd.search.progress`) | InfoMessage / Notification | toast / Search · no results |
| Search settings spinners (`rd.search.settings`) | SpinWidget | spinner generic |
| End of document messages / next file (`rd.end.msgs`) | InfoMessage / FileChooser | App.toast |
| Reset / save document settings, invert UI layout (`rd.menu.confirms`) | ConfirmBox / MultiConfirmBox | `confirm` / 3-action layout |
| Config option hold: 'Set default X to Y?' (`rd.config.default`) | ConfirmBox | `confirm` (typeset also has Save as default) |
| Config option fine-tune (⋯ button) (`rd.config.fine`) | SpinWidget / DoubleSpinWidget / ButtonProgressWidget | typeset uses App.sliderRow inline; the dialog = spinner generic |
| Typography language & hyphenation dialogs (`rd.typography`) | MultiConfirmBox / DoubleSpinWidget / TextViewer / InfoMessage | Settings · Typography language + generics |
| Reload / re-render prompts (`rd.reload`) | ConfirmBox / MultiConfirmBox / InfoMessage | `confirm` / `opening` (cache phase) / toast |
| Encrypted document password (`rd.password`) | InputDialog (password) | `input` (masked) |
| Look up a word (typed) (`dc.input`) | InputDialog | `input` |
| Dictionary settings dialogs (`dc.settings`) | SpinWidget / SortWidget / ConfirmBox | spinner / arrange generics |
| Slow menu action 'tap to cancel' (`mn.trap`) | TrapWidget | toast with cancel |
| Numeric settings from menus (`mn.numeric`) | SpinWidget / DoubleSpinWidget | prototype shows inline steppers; port = spinner generic (w.spinwidget) |
| Gesture intervals (`mn.gestureintervals`) | KeyValuePage / SpinWidget | KV page + spinner generics |
| Page-turn / invert prompts (`mn.pageturns`) | MultiConfirmBox / DoubleSpinWidget | 3-action layout / spinner |
| Plugin manager dialogs (`mn.plugins`) | ButtonDialog / ConfirmBox / InfoMessage | action sheet + `confirm`; list via menu engine |
| Patch management messages (`mn.patches`) | InfoMessage | `info` / `error` |
| Keyboard settings (`mn.keyboard`) | InfoMessage / InputDialog | toast / `input` numeric |
| UI font fallbacks (`mn.fontfallbacks`) | InfoMessage | toast |
| Settings explanations (metadata location, hash docs…) (`mn.settings.info`) | InfoMessage | `menu-help` / `info` |
| Past notifications viewer (`mn.notifhist`) | TextViewer | text page (view-html style) |
| Wi-Fi state messages & prompts (`sy.wifi.msgs`) | InfoMessage / ConfirmBox / MultiConfirmBox | `confirm` / toast; 'no Wi-Fi' prompt via `confirm` |
| Trapper (interruptible long jobs) (`sy.trapper`) | ConfirmBox / InfoMessage / TrapWidget | toast + `confirm` |
| Android-only prompts (`sy.android`) | InfoMessage / ConfirmBox | `confirm` |
| Statistics settings, DB & sync messages (`pl.stats.misc`) | ConfirmBox / InfoMessage / DoubleSpin / Spin / DateTime / ButtonDialog | toast / `confirm` / spinner generics |
| Export target setup (Joplin, Nextcloud, Readwise, XMNote) (`pl.exporter.targets`) | MultiInputDialog / InputDialog / InfoMessage | form sheet / `input` |
| Search catalog (`pl.opds.search`) | InputDialog | `input` / `search` scope OPDS |
| OPDS sync / download all (`pl.opds.sync`) | ButtonDialog / ConfirmBox / SpinWidget / InputDialog / TextViewer / InfoMessage | generics (action sheet, confirm, spinner, toast) |
| Calibre metadata search (`pl.calibre.search`) | InputDialog / BookList / ConfirmBox | `search` screen results (menu link goes to search; no calibre-specific scope) |
| Cloud storage file & server dialogs (`pl.cloud.dialogs`) | ButtonDialog / ConfirmBox / InputDialog / MultiInputDialog / PathChooser / ProgressbarDialog / SortWidget | action sheet, form sheet, `confirm`, progress; folder choice → PathChooser (missing) |
| Auto warmth / auto night mode (`pl.autowarmth`) | RadioButtonWidget / SpinWidget / DoubleSpinWidget / DateTimeWidget / InputDialog / ConfirmBox | menu engine + generics (no dedicated design) |
| Auto dim (dimmed screen + tap to undim) (`pl.autodim`) | SpinWidget / TrapWidget | spinner generic; dim = no UI |
| Auto suspend / shutdown timeouts (`pl.autosuspend`) | DateTimeWidget / InfoMessage | date/time generic (partial) + toast |
| Auto standby (`pl.autostandby`) | SpinWidget | spinner generic |
| Battery statistics (`pl.batterystat`) | KeyValuePage / ConfirmBox | KV generic (book-details pattern) |
| System statistics (`pl.systemstat`) | KeyValuePage | KV generic |
| Move to archive (`pl.movetoarchive`) | ConfirmBox | `confirm` + toast |
| Book shortcuts (gesture to open a file) (`pl.bookshortcuts`) | PathChooser / ConfirmBox | PathChooser (missing) + `confirm` |
| HTTP inspector (`pl.httpinspector`) | InfoMessage / InputDialog | toast / `input` |
| Keep alive (`pl.keepalive`) | ConfirmBox | `confirm` |
| Folder default settings tweak (`pl.docsettingtweak`) | InputDialog (multi-line) | `text-editor` |
| Japanese support (`pl.japanese`) | SpinWidget / InfoMessage | spinner |
| External keyboard messages (`pl.externalkeyboard`) | InfoMessage | toast |
| Hello plugin (sample) (`pl.hello`) | InfoMessage | `info` |
| Cover image (system screensaver file) (`pl.coverimage`) | InfoMessage / PathChooser / InputDialog / SpinWidget / ConfirmBox | generics |
| Hotkeys (keyboard shortcuts) (`pl.hotkeys`) | TouchMenu | menu engine |
| Project: Title cache & indexing messages (`pt.cache`) | InfoMessage / ConfirmBox | toast with progress / `confirm`; plus › Cache book info |

## Global safety net (restyle these base widgets in the Lua port)

Restyling each of these once gives the Leaf look to every use, including surfaces never designed individually. Counts are construction sites found in KOReader + plugins + Project: Title (direct `:new`/`notify` calls; subclasses inherit on top).

| # | Base widget / global (file) | Sites | Inherited by / used inside | Leaf target | Status of the Leaf design |
|---:|---|---:|---|---|---|
| 1 | Font map & sizes (`frontend/ui/font.lua` `Font.fontmap`, `Font.sizemap`) | all | every TextWidget/TextBoxWidget in every widget | Inter (UI), Playfair Display (top-level titles), Literata (book), Noto Naskh Arabic; type scale tokens 10.5–30 | designed (tokens.css); existing patch `2-font-override.lua` swaps to Source Sans: replace it |
| 2 | Sizes (`frontend/ui/size.lua`: radius, border, padding, margin, line, item heights) | all | every FrameContainer, separators, menu rows | radius tokens, hairline borders, 48px rows, 44px popover rows, 40px buttons | designed; `2-clean-menus.lua` sets `Size.radius.window = 0`: conflicts with Leaf's rounded sheets/dialogs, revise |
| 3 | Colours (`Blitbuffer.COLOR_*` greys) + night mode | all | frames, separators, greyed text, highlight greys | map to tokens; Leaf Dark on e-ink = KOReader night mode (whole-screen inversion of the Paper theme), so design Paper first and check the inverted result | designed (tokens) — inversion behaviour must be checked |
| 4 | Icons (`frontend/ui/widget/iconwidget.lua`: user icons dir `koreader/icons/` is searched before `resources/icons/mdlight`) | all | title bars, menus, top-menu tabs, footer, dialogs, file browser | drop Lucide SVGs named like the mdlight files (appbar.*, chevron.*, star.*, …) into `koreader/icons/` | designed (Lucide set); zero-code global win |
| 5 | Button / ButtonTable / IconButton (`ui/widget/button.lua`, `buttontable.lua`, `iconbutton.lua`) | 87+ | ButtonDialog, ConfirmBox, MultiConfirmBox, InputDialog, Spin/DoubleSpin/DateTime, TextViewer, ImageViewer, KeyboardLayoutDialog, RadioButtonWidget, FontChooser, crop dialog, DictQuickLookup, BookStatusWidget, KeyValuePage, Menu, TouchMenu, SkimTo, SortWidget, CalendarView, FrontLightWidget | `.ko-btn`/`.dl-btn` 40px: ghost secondary, small accent primary, danger; actions right-aligned, no grid lines | designed |
| 6 | TitleBar (`ui/widget/titlebar.lua`) | 28 | Menu, KeyValuePage, TextViewer, SortWidget, InputDialog, Spin/DoubleSpin/DateTime, BookMap, PageBrowser, ImageViewer, CalendarView, ReaderProgress, FileManager, BookStatusWidget, DictQuickLookup, FontChooser, FrontLight/NaturalLight, RadioButtonWidget, KeyboardLayoutDialog | `.ko-header` (screens: back, title, actions) / `.ko-sheet-head` (17px semibold + sub + close right) / `.dl-title` | designed |
| 7 | Dialog frame: MovableContainer + FrameContainer defaults | 16 widgets | ButtonDialog, ConfirmBox, DictQuickLookup, DoubleSpin, FontChooser, InfoMessage, InputDialog, KeyboardLayoutDialog, MultiConfirmBox, OpenWithDialog, RadioButtonWidget, style-tweak editor, SkimTo, SpinWidget, TextViewer | `.ko-dialog` (centred, compact) or `.ko-sheet` (bottom) frame, hairline border, card surface | designed |
| 8 | InfoMessage (`ui/widget/infomessage.lua`) | 395 | every plugin and module | rule: messages with a `timeout` or reporting a finished result → App.toast; errors/explanations needing reading → `info` dialog (no icon circle, 17px title, OK right) | designed |
| 9 | Notification (`ui/widget/notification.lua`) | 113 | copy, font size/frontlight gestures, style changes, location history | App.toast | designed |
| 10 | ConfirmBox (`ui/widget/confirmbox.lua`) | 154 | delete, exit, overwrite, reset, sync prompts, network prompts | `confirm` (danger variant when ok_text is Delete/Remove/Reset) | designed |
| 11 | MultiConfirmBox (`ui/widget/multiconfirmbox.lua`) | 24 | fonts, typography language, OTA failure, page turns, random file, wallabag/news | three-action dialog like `paste-conflict` | designed (pattern) |
| 12 | ButtonDialog + ButtonSelector (`ui/widget/buttondialog.lua`, `buttonselector.lua`) | 88 + 16 | all long-press menus, quick menu, external link, search navigation, filters, selection popup, plus menu | with `anchor` → `.ko-popover`; otherwise bottom action sheet (`book-actions` rows: icon + label, title as sheet head); ButtonSelector → radio rows | designed (pattern) |
| 13 | InputDialog + MultiInputDialog + OpenWithDialog + InputText (`ui/widget/inputdialog.lua`, `multiinputdialog.lua`, `inputtext.lua`) | 79 + 19 | all text entry, password, search, forms, fullscreen editors | `input` (soft filled field, desc, check row, right-aligned actions) / form sheets / `text-editor` for fullscreen | designed; replaces patch `2-dialogs.lua` |
| 14 | VirtualKeyboard + VirtualKeyPopup + KeyboardLayoutDialog (`ui/widget/virtualkeyboard.lua`, `keyboardlayoutdialog.lua`) | 1 + 2 + 2 | every InputDialog | `keyboard` overlay (48px keys, Done key) | keyboard designed; key popup and layout switcher missing |
| 15 | SpinWidget + DoubleSpinWidget + DateTimeWidget + NumberPickerWidget (`ui/widget/spinwidget.lua`, `doublespinwidget.lua`, `datetimewidget.lua`, `numberpickerwidget.lua`) | 74 + 14 + 12 | every numeric setting, ConfigDialog fine-tune, timers, footer/dictionary/TOC/search settings | compact dialog with `App.sliderRow` (one or two) / Hour-Minute steppers; Default · Cancel · Set | **missing — design it first (100 sites)** |
| 16 | TextViewer + ScrollTextWidget (`ui/widget/textviewer.lua`, `scrolltextwidget.lua`) | 22 | descriptions, translation, view HTML, notes, CSS, notifications history, the paragraph-translate patch | `view-html`/`translate` page-or-sheet with header actions (Find, font size) as popover | designed (pattern) |
| 17 | KeyValuePage (`ui/widget/keyvaluepage.lua`) | 34 | book info, all statistics lists, battery/system stats, gesture intervals, RSS feeds, aliases, lookup histories | `book-details` rows (label left in `--text-2`, value right), `.ko-pager` | designed (pattern) |
| 18 | Menu + MenuItem (`ui/widget/menu.lua`) → BookList → FileChooser → PathChooser; CloudStorage, OPDSBrowser, SyncService | 15 + 10 + 4 + 20 | TOC, bookmarks, search results, collections, history, shortcuts, OPDS, cloud, dictionary download list, page map, defaults editor | list page: `.ko-row` 48px, hairline separators, `.ko-pager` (tap → Go to page `input`), status/progress badges like the library list | designed (pattern); PathChooser 'choose' footer missing |
| 19 | SortWidget (`ui/widget/sortwidget.lua`) | 9 | arrange collections/books/footer items/actions/dictionaries/vocab filter/cloud servers | Arrange page (rows with handle + up/down, Save) | partial (dict-manager order only) |
| 20 | TouchMenu + TouchMenuBar + TouchMenuItem (`ui/widget/touchmenu.lua`) | 2 | the whole top menu in library and reader, plus every plugin menu | `main-menu` (tabs as text with accent underline, rows with icons, breadcrumbs, footer) | designed; existing patches `2-menu-panel.lua`, `2-clean-menus.lua` to be superseded |
| 21 | ConfigDialog + ToggleSwitch + ButtonProgressWidget + OptionTextItem/OptionIconItem (`ui/widget/configdialog.lua`) | 1 | bottom typesetting panel (EPUB and PDF) | `typeset` sheet (tabs, sliders, segments) | designed |
| 22 | CheckButton / CheckMark / RadioMark / RadioButtonTable | 37+ | dialogs, menus, OpenWith, search options | `App.check`, `App.toggle`, `App.radio` | designed |
| 23 | ProgressWidget (`ui/widget/progresswidget.lua`) | 14 | footer bar, book map, skim, Project: Title progress bars, ProgressbarDialog | `App.progress` thin 2–3px line, accent fill | designed |
| 24 | ImageViewer (`ui/widget/imageviewer.lua`) | 8 | covers, images in books, screenshots, archives, OPDS streaming | full-bleed image page | **missing** |
| 25 | QRMessage, ProgressbarDialog, TrapWidget/Trapper, RadioButtonWidget | 5 + 3 + 7 + 3 | QR, downloads, tap-to-cancel long jobs, night-mode choice | `qr`, progress states (OPDS/update), toast with Cancel, radio rows | designed (patterns) |
| 26 | VerticalScrollBar / LineWidget | — | scrollable text, separators everywhere | thin bar; hairline `--line` separators | scrollbar style missing (P3) |

### Widgets that draw themselves (a global restyle does NOT reach them; port each one)

They only partly inherit (buttons, title bars, fonts, icons) and need their own Lua work against the named Leaf design:

- ReaderFooter (`frontend/apps/reader/modules/readerfooter.lua`) → `.rd-foot` + footer modes (gap rd.footer.modes)
- ReaderDogear, ReaderFlipping, ReaderView highlight/selection drawing, LinkBox, page gaps → `.rd-dogear`, highlight styles; flipping indicator and link box are gaps
- DictQuickLookup (`ui/widget/dictquicklookup.lua`) → `dict` / `wiki` sheets (+ empty states gap)
- FootnoteWidget (`ui/widget/footnotewidget.lua`) → gap rd.footnote (P1)
- BBoxWidget (`ui/widget/bboxwidget.lua`) crop UI → gap rd.crop
- SkimToWidget, BookMapWidget, PageBrowserWidget → `skim`, `bookmap`, `pagebrowser`
- BookStatusWidget / AltBookStatusWidget (Project: Title) → `book-status`
- FrontLightWidget / NaturalLightWidget → `frontlight`
- ScreenSaverWidget / ScreenSaverLockWidget → `sleep`, `lockscreen` (lock prompt is a gap)
- NetworkSetting (`ui/widget/networksetting.lua`) → `wifi`
- CalendarView / CalendarDayView / ReaderProgress (statistics) → `stats` (month calendar and day timeline are gaps)
- VocabularyBuilderWidget / WordInfoDialog / MenuDialog → `vocab`, `ex-vb-word`, `ex-vb-settings`
- Project: Title MosaicMenu / ListMenu / titlebar / footer, FileManager layout → `library`, `folder`, `history`, `collection`
- TweakInfoWidget, Screenshoter, Terminal (TermInputText), IndicatorOverlay → gaps / `terminal`

## Notes for the port

- **Night mode vs. Dark theme:** KOReader night mode inverts the whole framebuffer. On e-ink, Leaf's Dark theme will in practice be the inverted Paper theme; check every Paper design inverted, including covers and highlight greys (inverted images are re-inverted by KOReader only for some content).
- **Existing user patches overlap the port:** `2-clean-menus.lua` (square corners, non-bold buttons, TouchMenu sizes), `2-menu-panel.lua`, `2-library-panel.lua`, `2-dialogs.lua`, `2-font-override.lua` (Source Sans) and `2-paragraph-translate.lua` (TextViewer translation). Replace or merge them, otherwise two styles fight (e.g. radius 0 vs. Leaf's rounded sheets).
- **Kindle native pieces cannot be restyled from Lua:** the Kindle activity spinner (`readeractivityindicator.lua`, uses lipc) and the Kindle lock/ads screen when the device still has special offers (KOReader's sleep screen only shows if `supportsScreensaver`).
- **Disable the stock Cover browser plugin** (Project: Title replaces it) so its mosaic/list and its spinner dialogs never appear.
- **One-time / first-run surfaces** to test on a clean profile: quickstart guide, 'Gestures have been upgraded' (`plugins/gestures.koplugin/main.lua:1310`), first multiswipe prompt (`:1334`), 'Restore metadata from archive?' (`frontend/apps/reader/readerui.lua:649`), Project: Title first indexing progress, 'No dictionaries installed' dictionary state.
- **Gesture-only surfaces** in this audit: footer tap (modes) and hold (settings menu), top-left tap (flipping mode), top-right tap (dog-ear), long-press on word/image/link/TOC entry/bookmark/collection/history item/menu row/config option/key/globe key/text field, two-finger diagonal swipe (screenshot), pinch/spread (zoom / font-size notification), swipe left edge (frontlight notification), quick-menu gestures.

