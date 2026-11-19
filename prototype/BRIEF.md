# Leaf — KOReader redesign prototype (HTML)

The goal is an interactive HTML prototype of a **complete redesign of KOReader** (the e-reader app), used to
validate the design before it is reimplemented as KOReader Lua patches. The user wants a *great* app,
**nothing kept from the old KOReader look** (no boxed icon-tab bars, no grids of grey buttons, no
centred ButtonDialogs), and **every real option present**. Book text is random placeholder prose.

Open `index.html` in a browser. The left designer panel lists every state (`App.demo(...)`); the
switches there toggle Dark / Paper theme, E-ink grayscale preview, and device size.

## Design language (from the user's concept — images in `concept/`: overview.png and page-01..15.png)
- Typography-forward, calm, premium. UI font **Inter**; display/serif accents **Playfair Display**;
  book text **Literata**. Arabic: **Noto Naskh Arabic**.
- Dark theme default: near-black background, slightly lighter cards, hairline borders, warm **peach accent**
  (`--accent`) used sparingly: active tab underline, progress fill, primary button, selected state.
- Thin 2–3px progress lines; small % badges on covers; generous spacing; 44px min touch targets.
- Floating panels anchored to the button that opened them (`.ko-popover`), bottom sheets that slide up
  (`.ko-sheet`) for reader controls, centred dialogs only for confirm/input (`.ko-dialog`), full pages for
  deep content (`.ko-page`).
- **Sliders** (big, tappable) instead of tiny +/- buttons; segmented controls for small choice sets;
  toggles for on/off; radio rows for single choice in lists.
- Thin Lucide icons (`App.icon("name")`, names from lucide.dev).
- **E-ink safe**: must still read perfectly in the E-ink grayscale preview — never rely on colour alone,
  solid fills (no meaningful gradients), strong text contrast, no essential animation.
- Both themes must look intentional. Only use tokens from `css/tokens.css` (see **Design system** below), never raw colours
  (exception: cover art and the reading page, which use `--page`, `--page-ink`).

## Files
Foundation (read them; components and tokens are documented in **Design system** below; if you truly need a core change, put a helper in your own file
and mention it in your report):
- `css/tokens.css` — every token. `css/components.css` + `js/ui.js` — the component library (see **Design system**; catalog at `#/catalog`: rows, toggles,
  slider, seg, sheet, popover, dialog, page, tabs, chips, cover, badges, pager, bottom nav, empty).
- `js/core.js` — router + overlay stack + click delegation. Read its header comment. Key API:
  `App.screen(name,{render})`, `App.overlay(name,{render, layer:"popover"|"sheet"|"dialog"|"page", clear, mount})`,
  `App.action(name, fn)`, `App.go / App.open / App.close / App.closeAll / App.refresh / App.toast`,
  `App.get/App.set` (persisted state), helpers `App.icon, App.toggle, App.radio, App.check, App.progress,
  App.slider(pct, 'data-slide="actionName"'), App.statusBar(), App.bottomNav(on), App.esc`.
  `App.demo(group, label, hash)` registers a state in the designer panel — **register every state you build**.
- `js/data/books.js` — `DB` (BOOKS, FOLDERS, LOOSE_FILES, COLLECTIONS, HISTORY, STATS, HIGHLIGHTS, QUOTES,
  SEARCH_HISTORY, DICTIONARIES, book(id)), `Cover.html(book,{badge})`, `TextGen.chapter(id, idx)`,
  `TextGen.chapters(id)`, `TextGen.synopsis(book)`.
- `js/data/menus.js` — `KO_MENUS`, the **real** KOReader option trees dumped from KOReader v2026.07.1:
  - `fm_menu` / `reader_menu`: `[{icon, items:[node]}]` — one entry per top-menu tab
    (icons: appbar.filebrowser, appbar.navigation, appbar.typeset, appbar.settings, appbar.tools, appbar.search, appbar.menu).
  - node: `{text, kind?: "submenu"|"check"|"radio", checked?, disabled?, separator? (line after it), help?, items?: [node] | {ref:id}}`.
    `{ref:id}` points into `KO_MENUS.shared[id]` (deduplicated repeated subtrees, e.g. gesture actions).
  - `reader_menu_pdf`, `reader_config_pdf`, `reader_highlight_pdf`: same, when a PDF/DjVu/CBZ is open.
  - `fm_plus` (the "+" menu rows), `fm_filedialog` (long-press on a book: `{title, buttons:[[labels]]}`),
    `reader_config` (bottom typesetting panel: `[{icon, options:[{name,title,labels,values,kind,help}]}]`),
    `reader_highlight` (text-selection popup buttons).
- Shell: `index.html` (already includes every screen file below; don't edit).

## Ownership (each agent edits ONLY its own files)
| Agent | JS | CSS | Screens / overlays it must provide |
|---|---|---|---|
| Library | `js/screens/home.js`, `js/screens/library.js` | `css/screens/home.css`, `css/screens/library.css` | screens `home`, `library` (params `tab`: library/favorites/collections, `view`: grid/list/detail, `folder`), `history`, `folder` (folder browser), `collection` ({name}); overlays `book-details` (page, {id}), `book-actions` (sheet, {id}), `plus` (popover), `sort` (popover: sort + view + filter), `book-status` |
| Reader | `js/screens/reader.js`, `js/screens/reader-panels.js` | `css/screens/reader.css` | screen `reader` ({id, page, chrome}); overlays `reader-chrome`, `typeset` (sheet, {tab}), `toc`, `bookmarks`, `annotations`, `goto`, `skim`, `bookmap`, `pagebrowser`, `hl-popup`, `dict`, `translate`, `wiki`, `book-end` |
| Menus | `js/screens/menus.js` | `css/screens/menus.css` | overlay `main-menu` ({ctx:"fm"\|"reader", tab, path}) — the full top menu; screen `settings` ({section, path}); overlays `menu-help` |
| Tools | `js/screens/search.js`, `js/screens/stats.js`, `js/screens/dialogs.js` | `css/screens/search.css`, `stats.css`, `dialogs.css` | screens `search` ({q, scope}), `stats`; overlays `input` ({title, hint, value, ok, action}), `confirm` ({title, body, ok, danger}), `info`, `keyboard`, `frontlight` (sheet), `quick` (sheet: quick settings), `wifi`, `sleep` (screensaver preview), `about`; helper `App.keyboardHTML(opts)` |

Cross-links are by name only — e.g. Library opens `main-menu` with `{ctx:"fm"}`, Reader opens
`main-menu` with `{ctx:"reader"}` and `dict`, the Library header search opens screen `search`,
"New folder" opens `input`. If the target isn't built yet it simply won't open; that's fine.

## Done means
- Every state registered with `App.demo`, every KOReader option from `KO_MENUS` relevant to your area reachable.
- Verified with screenshots: `./shot.sh "#/library?tab=favorites" shots/<agent>-x.png dark` (and `paper`,
  and once with `600x800 eink`). **Look at the PNGs** and iterate until they look like a premium product.
- No console errors (check with `google-chrome --headless=new --enable-logging=stderr --v=0 --dump-dom ...` or by
  reading your code carefully).

## Shared pattern rules (added after user review)
- **Numeric settings use `UI.sliderRow({...})`** (js/ui.js; `App.sliderRow` is the same function): label, −, slider, +, value on ONE line, value same size as the label. Never put the value above the slider, never use big/serif numbers for setting values, never use big round ± buttons.
- Selected state = accent. Values never larger than their labels. No raw KOReader engineering labels where a human name works.
- **Dialogs are compact**: no decorative icon circle; title 17px semibold; body 14px `--text-2`; actions right-aligned, 40px high: build them with `UI.dialog({title, body, actions:[{label, kind}]})` — secondary = `kind:"ghost"`, primary = `kind:"primary"`, destructive = `kind:"danger"`. One button style system everywhere (`.ko-btn` + modifiers).
- **Results/confirmations of something that already happened are toasts** (`App.toast`), not dialogs with an OK button. Dialogs only when the user must decide or type.

### Shared pattern rules — QA pass (enforced by `tools/audit.py`; run it before handing work back)
1. **Selection has one language: the accent.** Selected tabs, chips, segments, pills, icon toggles, crumbs use `--accent` (text, outline, `--accent-soft` fill or underline). In e-ink it must survive without colour: add weight or a 2px `--text` outline under `.eink` (see `.ko-seg button.on`). Favourite = **filled vs outline heart** (shape, not colour).
2. **Titles:** Playfair (`.ko-header .title.display`, 26px) only for top-level screens — Home greeting, Library (all its tabs), History, Settings home, Stats, Welcome — plus the Book details / book-end book title and book titles in hero cards. Every level-2 page, sheet, drawer and dialog header is **Inter 17–18px semibold** (`--fs-head` / `--fs-lg`). Metrics (35m, 4h 6m, 62%) are Inter everywhere; only the Stats hero number may be Playfair.
3. **Sheet header = `.ko-sheet-head`**: `.title` (17px semibold Inter) + optional `.sub` (13px `--text-3`) + actions + a **close button always on the right**. A sheet's on/off switch is its first body row, not a header control. No serif dates/titles as sheet headers.
4. **Buttons:** there is one button, `.ko-btn` (`UI.button`), **40px** in every variant (dialogs included). Two buttons side by side never differ in height. (Exception: the keyboard strip's Done key matches the 48px keys.)
5. **Hit areas ≥ 44px.** `App.hitAreas()` (core, runs after every render) gives any smaller control an invisible `.ko-hit` expander (or transparent padding when it clips), so visuals can stay small (stars, steppers, crumbs, chips, map cells). Don't put `overflow: hidden` + a background on small controls — that defeats the expander.
6. **E-ink:** never colour alone. Highlights get an underline under `.eink`; highlight colours come only from `--hl-c-*` tokens; colour choices always show the colour **name** (no dot-only controls).
7. **No overflow:** nothing extends past the screen or pokes out of its container; chip rows are single-line horizontal scrollers (with an edge fade) or a grid, never wrapping; truncated row text must still show any "+N more" badge.
8. **Human labels:** KOReader engineering names get a human label with the original shown as small help text (`KOReader: Render Mode`). Strip KOReader private-use glyphs and the `()` they leave.
9. **No redundant controls in one panel** (e.g. a Presets pill *and* a Presets tab; a keyboard key repeating the dialog's button label — the keyboard's enter key says "Done").
10. **Rows in one group:** all have a leading icon or none (a section label or divider starts a new group). List rows are `--row-h` (48px), popover rows 44px.
11. **Type scale:** only the tokens `--fs-2xs` 10.5 · `--fs-xs` 11 · `--fs-sm` 13 · `--fs-md` 15 · `--fs-head` 17 · `--fs-lg` 18 · `--fs-xl` 22 · `--fs-2xl` 30 (+ display/hero sizes). No 12/12.5/14px. Text larger than 17px must be a title, a card heading or a deliberate hero metric. Bold inside UI text is semibold (600).
12. **Dense content belongs in a sheet or page, not a floating card** (e.g. History options is a sheet; the rest lives behind "More history settings").
13. **Sliders:** every numeric setting is an `App.sliderRow`; a standalone `.ko-slider` is only allowed for page-position scrubbers (reader chrome, skim).


## Design system (read this before writing any screen code)

The prototype is the spec for the KOReader Lua port, so every visual value lives in **one** place.
Catalog of every token and component in every state: **`#/catalog`** (designer group *Design system*: Tokens, Controls,
Rows & lists, Containers & overlays, Feedback), each sample with the helper call that produces it.

### Tokens (`css/tokens.css`, every token has a one-line comment)
- **Type:** families `--font-ui` Inter, `--font-display` Playfair, `--font-book` Literata, `--font-arabic`, `--font-mono`, `--font-scan`.
  UI scale `--fs-2xs` 10.5 · `--fs-xs` 11 · `--fs-sm` 13 · `--fs-md` 15 · `--fs-head` 17 · `--fs-lg` 18 · `--fs-xl` 22 · `--fs-glyph` 24 ·
  `--fs-display` 26 · `--fs-2xl` 30 · `--fs-3xl` 40 · `--fs-hero` 44 · `--fs-jumbo` 52; content sizes (`--fs-folio`, `--fs-reading`, `--fs-key`, `--fs-scan`, cover art).
  Weights `--fw-regular/medium/semibold/bold`; line heights `--lh-none/tight/head/body/para/book`; tracking `--ls-caps/tag/title/metric/wide`.
- **Spacing** `--sp-half` 2 · `--sp-1` 4 · `--sp-1h` 6 · `--sp-2` 8 · `--sp-2h` 10 · `--sp-3` 12 · `--sp-3h` 14 · `--sp-4` 16 · `--sp-5` 20 · `--sp-6` 24 · `--sp-8` 32 · `--sp-10` 40.
- **Radii** `--r-tick` 2 · `--r-thumb` 3 · `--r-cover` 4 · `--r-check` 5 · `--r-sm` 6 · `--r-inner` 7 · `--r-md` 10 · `--r-mark` 12 · `--r-lg` 14 · `--r-xl` 20 · `--r-pill`.
- **Borders** `--hairline` 1 · `--bw-md` 1.5 · `--bw-lg` 2 · `--bw-xl` 3. **Heights** `--h-control` 40 · `--h-row` 48 · `--h-row-compact` 44 · `--h-chip` 32 · `--h-seg` 34 ·
  `--h-input` 44 · `--h-header` 56 · `--h-status` 26 · `--h-nav` 60 · `--h-badge` 20 · `--hit` 44 (aliases `--row-h`, `--touch`).
- **Icons** `--icon-2xs` 12 · `xs` 14 · `sm` 16 · `tile` 18 · `md` 20 · `key` 22 · `lg` 24 · `xl` 28 · `2xl` 40; strokes `--stroke-hair/light/(default)/strong/bold`.
- **Layers / motion** `--z-raised/sticky/badge/layer/toast`, `--ease`, `--dur`, `--dur-page`, `--dur-sheet`.
- **Colour** per theme (`.theme-dark`, `.theme-paper`): `--bg … --surface-3`, `--border(-strong)`, `--text(-2/-3)`, `--disabled`, `--accent(-ink/-soft)`, `--danger(-ink)`,
  `--scrim`, `--page`, `--page-ink`, `--page-2`, shadows `--shadow`, `--shadow-cover`. **Every color-mix is a named token** resolved per theme:
  `--accent-tint`, heatmap `--heat-0…4`, highlight list tints `--hl-tint-*`, page tints `--hl-yellow…`, `--sel`, `--hl-eink` (e-ink highlight = grey + `--hl-underline`),
  page art `--page-tint/scan/rule/line/tick/ornament/skeleton…`. Highlight palette `--hl-c-*` (+ underline inks `--hl-u-*`). Fixed colours for art: `--on-cover`,
  `--cover-scrim`, `--qr-*`, `--scan-*`. Rings / edge bars as box-shadow tokens: `--ring`, `--ring-strong`, `--ring-inset(-strong)`, `--ring-accent`, `--ring-eink`,
  `--ring-selected`, `--cutout`, `--bar-accent`, `--bar-eink`, `--underline-accent`, `--shadow-sm/xs/key/knob/thumb`.

### Components (`css/components.css`) and their helpers (`js/ui.js`, all return HTML strings)
One class per component, `--modifier` classes for variants, state classes `.on` (selected), `.sel`, `.active`, `.disabled`/`:disabled`.
`attrs` is a raw attribute string or `{action, arg, open, params, go, close, …}`.

| Component | Class (modifiers) | Helper |
|---|---|---|
| Button | `.ko-btn` (`--primary --ghost --danger --sm --icon --block`) · link `.ko-link` | `UI.button({label, kind:"primary\|secondary\|ghost\|danger\|link", icon, size:"sm", square, block, disabled, attrs})` |
| Icon button | `.ko-icon-btn` (`--sm`, `.active`, `.on`) · `.ko-help-btn` | `UI.iconButton({icon, label, size, active, disabled, attrs})`, `UI.closeButton()` |
| Segmented control | `.ko-seg` (`--block --icons --sm --roomy`) | `UI.seg(items[{label, icon, on, attrs}], {block, size})` |
| Tabs | `.ko-tabs` (`--sm`) / `.ko-tab` | `UI.tabs(items[{label, on, n, attrs}], {cls})` |
| Chip / chip row | `.ko-chip` (`--lg --add`, `.on`, `.n` count) / `.ko-chips` | `UI.chip({label, icon, on, n, size, add})`, `UI.chipRow(chips)` |
| Toggle · check · radio | `.ko-toggle` `.ko-check` `.ko-radio` · `.ko-check-row` | `UI.toggle(on)`, `UI.check(on)`, `UI.radio(on)`, `UI.checkRow({label, on, attrs})` |
| Stars | `.ko-stars` (`--lg`) | `UI.stars(n, {size, attrs:(i)=>…})` |
| Slider row | `.ko-sr` (+ `.ko-slider` for page scrubbers only) | `UI.sliderRow({label, icon, pct, value, unit, slide, step, minIcon, maxIcon})` = `App.sliderRow` |
| Row / group / list | `.ko-row` (`--danger`, `.sel`, `.disabled`) / `.ko-group` (`--sunken`) / `.ko-list` | `UI.row({icon\|tile, label, sub, value, trailing:"chevron\|toggle\|radio\|check\|stepper\|none", on, disabled, danger})`, `UI.group(rows)`, `UI.list(rows)` |
| Icon tile | `.ko-icon-tile` (`--lg --xl --plain --raised --accent`) | `UI.iconTile(name, {size, accent, raised})` |
| Section label / eyebrow | `.ko-section-label` / `.ko-eyebrow` (`--accent --strong`) | `UI.sectionLabel(text)`, `UI.eyebrow(text, {accent, strong, icon})` |
| Tool (icon over label) | `.ko-tool` (`--lg --danger`) | `UI.tool({icon, label, size, danger, disabled})` |
| Screen / page header | `.ko-header` (`.title.display` top-level only, `.title.l2`; `--page --rule`) · `.ko-crumbs` | `UI.screenHead({title, display, count, back, actions})`, `UI.pageHead({title, crumbs, back, actions, rule})` |
| Sheet / sheet head | `.ko-sheet` (`--phone`) · `.ko-sheet-head` (`--rule`) | `UI.sheetHead({title, sub, lead, actions, close})` |
| Dialog | `.ko-dialog` (`--scroll`) · `-title -sub -body -actions` · `.ko-kv` | `UI.dialog({title, icon, danger, sub, body, bodyHtml, actions})`, `UI.kv(pairs)` |
| Card | `.ko-card` (`--flush --sm --tap --accent --dashed --sunken`, `.on`) | `UI.card(html, {flush, sm, tap, accent, dashed, sunken, on})` |
| Popover, page, toast, pager, bottom nav | `.ko-popover` `.ko-page` `.ko-toast` `.ko-pager` `.ko-nav` | `App.open(…)`, `App.toast(text)`, `App.bottomNav(on)` |
| Input / keyboard field | `.ko-input` (`--card`) · `.kb-field` (`--compact --lg`) + `.kb-field-help` | `UI.input({icon, placeholder, card})`, `App.kbField(target, opts)` |
| Badge · pill | `.ko-badge` (`--accent`) · `.ko-pill` (`--accent --current --soft --tint --caps --sm`) | `UI.badge(text, {accent})`, `UI.pill(text, {kind, caps, sm})` |
| Progress · meter · stats | `.ko-progress` (`--thin --md`) · `.ko-meter` · `.ko-stats` (`--card --center`) / `.ko-stat` | `UI.progress(pct, {size})`, `UI.meter(parts, {head, legend})`, `UI.stats(tiles)`, `UI.statTile({value, label})` |
| Cover · selection mark · empty · spinner | `.ko-cover` (`--thumb`) · `.ko-selmark` · `.ko-empty` · `.ko-spin` | `UI.cover(book, {badge, accent})`, `UI.empty({icon, title, text, action})` |

### Screen CSS rules (`css/screens/*.css`, enforced by `tools/audit.py` and `tools/lintcss.py`)
1. Screen CSS only **lays out** components: display/grid/flex, gaps and paddings from `--sp-*`, positioning, sizing of layout regions, and screen typography with tokens.
2. **No raw values:** colours (hex/rgb/hsl, unnamed `color-mix`), px `font-size`, `font-family`/`font-weight` literals, `border-radius` or `box-shadow` literals.
   Use the tokens above; add a named token to `css/tokens.css` (with a comment) if a new value is really needed.
3. **No component re-definitions:** a rule that paints (background/border/radius/shadow) a button, row, chip, segment, toggle, pill or tag must use the component or one of its
   `--modifiers` (add a modifier to `css/components.css` + the helper option if a real variant is missing).
4. **Truly screen-specific visuals** (book page typography, cover art, the tap-zone diagram, charts, keyboard keys, the PDF scan look, illustrations) live in a section
   opened by `/* screen-specific: why */` and closed by `/* end screen-specific */`; raw shapes are allowed there (colours still come from tokens).
5. Prefer the `UI.*` helpers when writing markup; add new states to the catalog (`js/screens/catalog.js`) when you add a component or variant.
6. Before handing back: `tools/.venv/bin/python tools/snap.py && tools/.venv/bin/python tools/diff.py` (visual diff vs `shots/baseline`, explain intentional
   changes in `tools/diff-notes.json`), `tools/audit.py`, `tools/flows.py`.
