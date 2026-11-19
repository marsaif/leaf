## Visual review — Phase 2 status (2026-11-19)

Phase 2 fixed every item below that is marked ✅; contact sheets (dark, paper, paper + e-ink) were regenerated and re-read.
✅ 1 title systems (rule: Playfair only for top-level + book titles) · ✅ 2 metrics in Inter (Stats hero stays Playfair) · ✅ 3 sheet headers (`.ko-sheet-head`, close always present) ·
✅ 4 status-bar screen labels removed · ✅ 5–7 one accent selection language, e-ink outlines · ✅ 8–9 e-ink highlight underline, colour chips named, `--hl-c-*` tokens ·
✅ 10 stats heatmap · ✅ 11 PDF page (crop is by design; demos now pinned to the same page) · ✅ 12 "+N more" · ✅ 13 History options → sheet ·
✅ 15 button heights · ✅ 16 icon/no-icon rows · ✅ 17 human labels with "KOReader: …" help text · ✅ 18 private-use glyphs · ✅ 19 redundant controls ·
✅ 21 "Alt status bar" kept in Typeset › Style (it is KOReader's reader_config option; left) · ✅ 22 truncated values now low · ✅ 23 chip rows ·
✅ 24 Wikipedia "W" → icon tile, author monograms Inter · ✅ 25–26 Extras/System now styled and audited.
Left on purpose: 14 selection popup density (all controls are real KOReader options; now 44px hit areas), 20 font previews in the Settings › Fonts list (menu rows are KOReader text lists; the typeset Font tab is the visual picker).

### Phase 1 review (for reference)

#### Visual review (manual, from screenshots)

Reviewed 2026-11-19 from contact sheets of every state: dark, paper + E-ink preview, at 600x800
(`tools/.venv/bin/python tools/contact.py [--theme paper] [--eink] [--group X]` writes `shots/qa-sheet-*.png`).
The linter can't catch these. The library **View & sort** sheet (`#/library?view=grid&o=sort…`) is skipped
because it's being redesigned. **Library extras & tools** and **System** were still being built while I
reviewed them. The first renders had no styles at all (extras.css and system.css were empty), so treat
the notes on those groups as provisional.

### Hierarchy and typography
1. **Two title systems side by side.** Home ("Good afternoon"), Settings level 1 (`#/settings`, `#/settings?section=reading`), the main-menu drawer ("Library", "Tools") and Stats ("Reading stats") use **Playfair 24–30px** titles. Library (`#/library`), History, Files, Settings level 2 (`#/settings?section=display&path=[1]` "Screen"), Page browser and Book map use **Inter 18–22px semibold**. Tabs in the same bottom nav (Home → Library → History → Settings) change title style on every tap. Pick one: serif only for the Home greeting and book titles, or serif for every top-level screen.
2. **The same metric in two fonts.** "35m today" is Inter on Home (`.hm-big`) and Playfair on Stats (`.st-time`). Stats KPIs (`.st-kpi-v`) are Playfair too. Book details progress "8%" (`.lbd-prow .big`) is Inter. Hero numbers should share one style.
3. **Sheet headers are inconsistent.** Typeset uses a 15px title, an 11px subtitle, a "Presets" pill and ×. Book status and Add to collections use an 18px title and ×. Wi-Fi (`#/home?o=wifi`) and Frontlight (`#/home?o=frontlight`) have **no close button** and put a toggle where × would be. Quick settings uses a **serif date** as its title plus a gear. Skim uses a 22px "Page 1 of 67" as its header. Define one `.ko-sheet-head` pattern (title 18/600, optional subtitle, × always on the right) and put toggles in the body.
4. **Settings pages say "Settings" three times.** On `#/settings?section=display` it appears in the status-bar label (top left), in the breadcrumb above the title, and on the bottom-nav tab. Stats ("Statistics") and Search ("Search") also put a screen name in the status bar, but Home and Library don't. Drop the status-bar label.

### Selected states (the user's "grey instead of peach")
5. **Six different selected styles.** Accent underline (`.ko-tab`), accent-soft fill with an accent border (history and annotations chips, preset cards, rotation tiles), accent text (typeset tab bar), **grey raised pill** (`.ko-seg button.on`, used in ~25 places: typeset Text/Page/Contrast/Style, Display & E-ink "Full refresh every / Waveform", Stats range, Book details status, Goto, Wiki language, Page browser columns, Update channel), a **white inverted pill** (Search scopes `#/search`), and the grey Library view switcher. The root cause is the foundation rule `.ko-seg button.on` in css/components.css. It needs an accent treatment (accent-soft fill plus accent text, or a 2px accent underline), and it also has to survive e-ink (see 7).
6. **Favourite heart** in Book details (`#/library?view=grid&o=book-details&o.id=animal-farm`): peach #e8a898 and the unselected grey #b4b4bd become the **same grey in e-ink**. A filled heart versus an outline heart would fix it.
7. **In e-ink, grey segmented selection disappears.** In the paper + e-ink sheet, typeset "Render mode: book" and "Zoom: 96" look selected only by a faint white lift. That's a contrast difference of about 4%.

### E-ink
8. **Yellow "lighten" highlights vanish in e-ink**, on the page and in the PDF chrome (`#/reader?id=animal-farm&ch=1`, `#/reader?id=pride&o=reader-chrome`). The difference is 17–19/255 grey. KOReader draws highlights as grey boxes on e-ink, so the e-ink preview should map `--hl-*` to a visible grey, or add a 1px underline.
9. **Highlight colour chips** (selection popup `#/reader?id=animal-farm&o=hl-popup&o.demo=1`, bookmark browser colour filter): Blue, Purple, Red and Gray become the same grey. The chips have text labels, so the choice still works, but the dots themselves are meaningless in e-ink. A pattern (hatch, dot, ring) per colour would help.

### Layout and spacing
10. **Stats calendar heatmap runs 60px off the right edge** (`#/stats?range=today`, "Reading calendar"). The month labels Oct and Nov are cut off. It needs to scroll horizontally or show fewer weeks.
11. **The PDF scanned page is clipped and off-centre** (`#/reader?id=pride`). The 420px scan is positioned 61px past the right edge, and the text block fills only the top third. "PDF · chrome" shows a *different* page (a reflowed "The Narrow Road" chapter), so the chrome isn't laid over the page it belongs to.
12. **Settings search "+7 more" runs off screen** (`#/settings?q=font`, `.set-more-n`): it's inside a nowrap sub-line, 96px past the edge.
13. **The History options popover is too dense for a floating card** (`#/history?o=lib-hist-menu`). It has 12 rows, 4 toggle labels wrap to 2 lines, and it mixes actions (Clear history), unrelated settings ("Show filename in Open last/previous menu items" is a menu setting) and a display-mode link. Make it a sheet, or a "History settings" page plus a short actions popover. *(Coordinator checks f, g)*
14. **The selection popup is 4 tiers deep** (style, colour, 4 labelled actions, 8 unlabelled icon actions) in a floating card about 400px wide. The bottom row (select, copy, wiki, html, cut, link, QR, search) has no labels, so discoverability is poor, and copy and cut look alike at this size. Consider 2 tiers plus a "More" sheet. *(g)*
15. **Home hero buttons don't match**: "Resume" is 42px tall and "Details" is 40px (`.hm-hero-actions`). The Welcome footer ("Back" 40 vs "Continue" 44) and Skim (52px step buttons vs 44px bookmark buttons) have the same problem.
16. **Rows in one group start at different x positions.** Some rows have icons and others don't, so the text doesn't line up. Examples: the History options popover (icon rows, then toggle rows without icons, then an icon row), Settings › Status bar (`#/settings?section=reading&path=[1]`: icon rows, then a toggle group without icons), Settings › Taps and gestures (the "Ignore long-press / Disable double tap" group without icons sits between icon groups), the Collection manage menu (radio rows without icons between icon rows), and the Dictionary settings page (no icons at all, while every sibling settings page has them). *(d)*

### Labels and content
17. **Raw KOReader engineering labels shown to users** *(a)*:
    - Typeset: "Render mode: legacy / flat / book / web" → "Layout engine: Simple / Flat / Book / Web" with one-line help. "Zoom (dpi): off 48 96 167 212 300" → "Text scale: Small / Default / Large / …". "Font hinting: off / native / auto" → "Sharpen text: Off / Font's own / Auto". "Font kerning: off / fast / good / best" and "Image scaling: fast / best" → "Letter fitting" and "Image quality".
    - PDF: "Writing direction LTR / RTL / TBRTL" → "Left to right / Right to left / Vertical (CJK)". "Reflow speckle ignore size", "Dewatermark", "Forced OCR".
    - Menus: "Speed reading module - perception expander", "Cloud storage+", "Hide non-linear fragments", "Screen DPI: Auto DPI, Small (120), Medium (160)".
    - History layout radio list: "KOReader: Detailed list with cover images and metadata" (this belongs to the sort-panel family, so I'm only noting it).
18. **Missing glyphs.** Settings › Status bar items (`#/settings?section=reading&path=[1,2]`) shows "Battery percentage ()", "Bookmark count ()" and "KOReader memory usage ()". The KOReader icon-font symbols don't render in Inter. Swap them for Lucide icons, or drop the brackets.
19. **Redundant controls in one panel** *(b)*:
    - Typeset sheet: "Presets" pill in the header *and* a "Presets" tab in the tab bar.
    - Quick settings: a Frontlight tile *and* Brightness and Warmth sliders in the same sheet.
    - Input dialogs: a dialog "Create" / "Rename" button *and* the keyboard's action key labelled the same (`#/home?o=input…`).
    - Main menu: a "Settings" row inside the Library, Search and Navigation tabs, next to the "Settings" rail tab.
20. **Text lists used where a visual preview would work** *(c)*:
    - Settings › Fonts (`#/settings?section=typography&path=[0,3]`) and the menu "Fonts list" show font names in Inter, but the typeset Font tab previews each face. Use the same previews.
    - Settings › Screen "Rotation" is a text row, but typeset Layout has rotation tiles.
    - Typography "Style: None / Auto / Traditional book look" and "Status bar presets" would be clearer as thumbnails.
21. **Unrelated settings in contextual panels** *(f)*:
    - Typeset › Style contains "Alt status bar" (a status-bar setting, not typesetting).
    - Library menu › Library tab ends with "Start with: File browser" (an app start-up setting).
    - Reader menu › Navigation contains toggles ("Hide non-linear fragments", "Autoturn") between navigation actions.
22. **Truncated values** *(h)*: Settings rows (`.mn-row .label .sub`, 10 states) truncate their summary lines, for example "From bottom menu icons, From bottom menu toggles, …". Settings search breadcrumbs cut off "Reflowable books (EPUB, FB2, TXT)" mid-word. These need wrapping to 2 lines or a shorter summary ("3 options").
23. **Chip rows wrapping** *(e)*:
    - Read timer presets (`#/reader?id=animal-farm&o=read-timer&o.mode=after`): 8 chips on 2 lines.
    - Bookmark browser colour filter: "Gray" alone on a second line.
    - Use a horizontal scroller or fewer presets.

### Icons
24. Icons are consistently thin Lucide, except:
    - The typeset tab bar uses a typographic "Aa" glyph (Playfair 19px) as one of its "icons".
    - Wikipedia has a serif "W" roundel.
    - Search authors use serif initials avatars.
    - About and Update use a Playfair "K" mark.

    These are fine individually, but there are three different "logo badge" styles. Icon-only header buttons are 44px, while card-header icon buttons (Home quote, Quick settings tile chevrons) are 32px.

### Panels that look like a different app
25. **Library extras & tools / System** were unstyled at review time: raw block HTML, 100%-width covers in the OPDS, bookmark browser and vocabulary states, and inline "Label**Value**" runs with no spacing. Re-audit them once extras.css and system.css land. The linter picks the new groups up automatically.
26. **Terminal / Text editor / Calibre / OPDS** (Library extras): inline label/value runs without separators ("Size3.9 MB", "LanguageEnglish") and icons glued to text ("⊙Connected"), at least in the first renders — check again after styling.
