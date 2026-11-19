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
| 270 | 169 | 96 | 0 | 5 | 2 |

## Summary per area

| Area | Total | Designed | Generic | Partial | Missing | Kindle gaps |
|---|---:|---:|---:|---:|---:|---:|
| Base widgets (generic types) | 37 | 18 | 18 | 0 | 1 | 0 |
| Library & file manager | 27 | 18 | 9 | 0 | 0 | 0 |
| History, collections, shortcuts, file search | 25 | 18 | 7 | 0 | 0 | 0 |
| Reader: page & persistent chrome | 17 | 14 | 2 | 0 | 1 | 0 |
| Reader: selection, highlights, links, footnotes | 18 | 10 | 7 | 0 | 1 | 1 |
| Reader: navigation panels | 31 | 21 | 10 | 0 | 0 | 0 |
| Reader: typesetting & document | 14 | 9 | 5 | 0 | 0 | 0 |
| Reader: dictionary, Wikipedia, translation | 12 | 9 | 2 | 0 | 1 | 1 |
| Menus & settings | 21 | 10 | 10 | 0 | 1 | 0 |
| System, network, device | 14 | 11 | 3 | 0 | 0 | 0 |
| Plugins | 50 | 28 | 22 | 0 | 0 | 0 |
| Project: Title plugin | 4 | 3 | 1 | 0 | 0 | 0 |

Note: the 'Base widgets' row counts widget *types*. Its gaps are the most important ones, because each type is shown from many places (see the site counts in the safety-net table).

## Gaps (missing and partial), by priority

Each line: id · what · KOReader file:line · trigger · widget · design suggestion (Leaf component/pattern to use).

### P1 (2 Kindle-relevant)

- **Footnote / endnote popup** (`rd.footnote`, missing)  
  KOReader: `frontend/apps/reader/modules/readerlink.lua:1584`, `frontend/apps/reader/modules/readerlink.lua:373`, `frontend/apps/reader/modules/readerlink.lua:396` · Trigger: tap a footnote link · Widget: FootnoteWidget (+ font-size SpinWidgets).  
  Design: Bottom `.ko-sheet` (no grip) with the note in Literata at reading size, hairline top border, link 'Open in book' and close; e-ink safe.
- **Dictionary popup states: no results / no dictionaries / interrupted** (`dc.empty`, missing)  
  KOReader: `frontend/apps/reader/modules/readerdictionary.lua:1383`, `frontend/apps/reader/modules/readerdictionary.lua:1411`, `frontend/apps/reader/modules/readerdictionary.lua:1618` (+1 more) · Trigger: lookup of a name/unknown word; fresh install · Widget: DictQuickLookup state + InputDialog. Leaf today: dict demo always has a definition.  
  Design: Same `dict` sheet with `.ko-empty` body: 'No definition for “X”' + actions Edit word, Wikipedia, Translate; no-dictionary state links to `dict-manager` catalog.

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
| Cloud storage file & server dialogs (`pl.cloud.dialogs`) | ButtonDialog / ConfirmBox / InputDialog / MultiInputDialog / PathChooser / ProgressbarDialog / SortWidget | action sheet, form sheet, `confirm`, progress; folder choice → PathChooser (`path-chooser`) |
| Auto warmth / auto night mode (`pl.autowarmth`) | RadioButtonWidget / SpinWidget / DoubleSpinWidget / DateTimeWidget / InputDialog / ConfirmBox | menu engine + generics (no dedicated design) |
| Auto dim (dimmed screen + tap to undim) (`pl.autodim`) | SpinWidget / TrapWidget | spinner generic; dim = no UI |
| Auto suspend / shutdown timeouts (`pl.autosuspend`) | DateTimeWidget / InfoMessage | date/time generic (`datetime` {k: suspend}) + toast |
| Auto standby (`pl.autostandby`) | SpinWidget | spinner generic |
| Battery statistics (`pl.batterystat`) | KeyValuePage / ConfirmBox | KV generic (book-details pattern) |
| System statistics (`pl.systemstat`) | KeyValuePage | KV generic |
| Move to archive (`pl.movetoarchive`) | ConfirmBox | `confirm` + toast |
| Book shortcuts (gesture to open a file) (`pl.bookshortcuts`) | PathChooser / ConfirmBox | PathChooser (`path-chooser`) + `confirm` |
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
| 14 | VirtualKeyboard + VirtualKeyPopup + KeyboardLayoutDialog (`ui/widget/virtualkeyboard.lua`, `keyboardlayoutdialog.lua`) | 1 + 2 + 2 | every InputDialog | `keyboard` overlay (48px keys, Done key) | designed (`keyboard`; Gaps › `key-popup`, `kb-layouts`) |
| 15 | SpinWidget + DoubleSpinWidget + DateTimeWidget + NumberPickerWidget (`ui/widget/spinwidget.lua`, `doublespinwidget.lua`, `datetimewidget.lua`, `numberpickerwidget.lua`) | 74 + 14 + 12 | every numeric setting, ConfigDialog fine-tune, timers, footer/dictionary/TOC/search settings | compact dialog with `App.sliderRow` (one or two) / Hour-Minute steppers; Default · Cancel · Set | designed (Gaps › `spin`, `spin2`, `datetime`, `number`) |
| 16 | TextViewer + ScrollTextWidget (`ui/widget/textviewer.lua`, `scrolltextwidget.lua`) | 22 | descriptions, translation, view HTML, notes, CSS, notifications history, the paragraph-translate patch | `view-html`/`translate` page-or-sheet with header actions (Find, font size) as popover | designed (pattern) |
| 17 | KeyValuePage (`ui/widget/keyvaluepage.lua`) | 34 | book info, all statistics lists, battery/system stats, gesture intervals, RSS feeds, aliases, lookup histories | `book-details` rows (label left in `--text-2`, value right), `.ko-pager` | designed (pattern) |
| 18 | Menu + MenuItem (`ui/widget/menu.lua`) → BookList → FileChooser → PathChooser; CloudStorage, OPDSBrowser, SyncService | 15 + 10 + 4 + 20 | TOC, bookmarks, search results, collections, history, shortcuts, OPDS, cloud, dictionary download list, page map, defaults editor | list page: `.ko-row` 48px, hairline separators, `.ko-pager` (tap → Go to page `input`), status/progress badges like the library list | designed (pattern); PathChooser = Gaps › `path-chooser` |
| 19 | SortWidget (`ui/widget/sortwidget.lua`) | 9 | arrange collections/books/footer items/actions/dictionaries/vocab filter/cloud servers | Arrange page (rows with handle + up/down, Save) | designed (Gaps › `arrange`; dict-manager order list) |
| 20 | TouchMenu + TouchMenuBar + TouchMenuItem (`ui/widget/touchmenu.lua`) | 2 | the whole top menu in library and reader, plus every plugin menu | `main-menu` (tabs as text with accent underline, rows with icons, breadcrumbs, footer) | designed; existing patches `2-menu-panel.lua`, `2-clean-menus.lua` to be superseded |
| 21 | ConfigDialog + ToggleSwitch + ButtonProgressWidget + OptionTextItem/OptionIconItem (`ui/widget/configdialog.lua`) | 1 | bottom typesetting panel (EPUB and PDF) | `typeset` sheet (tabs, sliders, segments) | designed |
| 22 | CheckButton / CheckMark / RadioMark / RadioButtonTable | 37+ | dialogs, menus, OpenWith, search options | `App.check`, `App.toggle`, `App.radio` | designed |
| 23 | ProgressWidget (`ui/widget/progresswidget.lua`) | 14 | footer bar, book map, skim, Project: Title progress bars, ProgressbarDialog | `App.progress` thin 2–3px line, accent fill | designed |
| 24 | ImageViewer (`ui/widget/imageviewer.lua`) | 8 | covers, images in books, screenshots, archives, OPDS streaming | full-bleed image page | designed (Gaps › `image-viewer`) |
| 25 | QRMessage, ProgressbarDialog, TrapWidget/Trapper, RadioButtonWidget | 5 + 3 + 7 + 3 | QR, downloads, tap-to-cancel long jobs, night-mode choice | `qr`, progress states (OPDS/update), toast with Cancel, radio rows | designed (patterns) |
| 26 | VerticalScrollBar / LineWidget | — | scrollable text, separators everywhere | thin bar; hairline `--line` separators | designed (Gaps › `text-viewer` scroll bar: 3px `--text-3` thumb) |

### Widgets that draw themselves (a global restyle does NOT reach them; port each one)

They only partly inherit (buttons, title bars, fonts, icons) and need their own Lua work against the named Leaf design:

- ReaderFooter (`frontend/apps/reader/modules/readerfooter.lua`) → `.rd-foot` + footer modes (Gaps › `footer-mode`)
- ReaderDogear, ReaderFlipping, ReaderView highlight/selection drawing, LinkBox, page gaps → `.rd-dogear`, highlight styles; Gaps › `flipping`, `linkbox`, `scroll-mode` (page gap)
- DictQuickLookup (`ui/widget/dictquicklookup.lua`) → `dict` / `wiki` sheets (+ empty states gap)
- FootnoteWidget (`ui/widget/footnotewidget.lua`) → gap rd.footnote (P1)
- BBoxWidget (`ui/widget/bboxwidget.lua`) crop UI → Gaps › `crop`
- SkimToWidget, BookMapWidget, PageBrowserWidget → `skim`, `bookmap`, `pagebrowser`
- BookStatusWidget / AltBookStatusWidget (Project: Title) → `book-status`
- FrontLightWidget / NaturalLightWidget → `frontlight`
- ScreenSaverWidget / ScreenSaverLockWidget → `sleep`, `lockscreen`; lock prompt = Gaps › `unlock`
- NetworkSetting (`ui/widget/networksetting.lua`) → `wifi`
- CalendarView / CalendarDayView / ReaderProgress (statistics) → `stats`; Gaps › `stats-cal`, `stats-day`, `book-stats`
- VocabularyBuilderWidget / WordInfoDialog / MenuDialog → `vocab`, `ex-vb-word`, `ex-vb-settings`
- Project: Title MosaicMenu / ListMenu / titlebar / footer, FileManager layout → `library`, `folder`, `history`, `collection`
- TweakInfoWidget, Screenshoter, Terminal (TermInputText), IndicatorOverlay → Gaps › `tweak-info`, `screenshot`; `terminal`

## Notes for the port

- **Night mode vs. Dark theme:** KOReader night mode inverts the whole framebuffer. On e-ink, Leaf's Dark theme will in practice be the inverted Paper theme; check every Paper design inverted, including covers and highlight greys (inverted images are re-inverted by KOReader only for some content).
- **Existing user patches overlap the port:** `2-clean-menus.lua` (square corners, non-bold buttons, TouchMenu sizes), `2-menu-panel.lua`, `2-library-panel.lua`, `2-dialogs.lua`, `2-font-override.lua` (Source Sans) and `2-paragraph-translate.lua` (TextViewer translation). Replace or merge them, otherwise two styles fight (e.g. radius 0 vs. Leaf's rounded sheets).
- **Kindle native pieces cannot be restyled from Lua:** the Kindle activity spinner (`readeractivityindicator.lua`, uses lipc) and the Kindle lock/ads screen when the device still has special offers (KOReader's sleep screen only shows if `supportsScreensaver`).
- **Disable the stock Cover browser plugin** (Project: Title replaces it) so its mosaic/list and its spinner dialogs never appear.
- **One-time / first-run surfaces** to test on a clean profile: quickstart guide, 'Gestures have been upgraded' (`plugins/gestures.koplugin/main.lua:1310`), first multiswipe prompt (`:1334`), 'Restore metadata from archive?' (`frontend/apps/reader/readerui.lua:649`), Project: Title first indexing progress, 'No dictionaries installed' dictionary state.
- **Gesture-only surfaces** in this audit: footer tap (modes) and hold (settings menu), top-left tap (flipping mode), top-right tap (dog-ear), long-press on word/image/link/TOC entry/bookmark/collection/history item/menu row/config option/key/globe key/text field, two-finger diagonal swipe (screenshot), pinch/spread (zoom / font-size notification), swipe left edge (frontlight notification), quick-menu gestures.

