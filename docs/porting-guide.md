# Leaf porting guide (for anyone porting a KOReader surface to the Leaf design)

Leaf restyles stock KOReader v2026.07.1 **without touching KOReader's files**: one user patch
(`koreader/patches/2-leaf.lua`) loads `koreader/leaf/core.lua`, which applies the modules listed in
`L.MODULES` (in `core.lua`). Each module is `return { apply = function(L) ... end }`.
The design spec is the HTML prototype in `prototype/` (read `prototype/BRIEF.md`, open
`prototype/index.html`, catalog at `#/catalog`). **The prototype is the spec: match it.**

## The Leaf API (inside `apply(L)`)
- `L.T` = generated tokens (`koreader/leaf/tokens.lua`, from `prototype/css/tokens.css`; never edit
  tokens.lua by hand, run `python3 tools/tokens2lua.py`).
  - `T.px("sp-4")` scaled pixels; `T.fs("fs-md")` font size for `Font:getFace`; `T.color("accent")`
    Blitbuffer colour (Paper theme, e-ink greys); token names = CSS names without `--`.
- `L.face(role, size_token)` → a font face. Roles: `ui`, `ui-medium`, `ui-semibold`, `ui-bold`,
  `display`, `display-semibold`, `display-italic`, `book`, `book-italic`, `book-bold`, `arabic`.
- `L.wrap(Class, "method", function(orig, self, ...) ... end, "label")` replaces a method; if the
  new code throws, Leaf logs it and uses KOReader's original from then on. **Every override goes
  through L.wrap.** `L.log(...)`, `L.err(...)`.
- Existing Leaf widgets you can reuse: `leaf/widgets/slider.lua` (LeafSlider), `toggle.lua`
  (LeafToggle), `seg.lua` (LeafSeg); button kinds in `leaf/buttons.lua` (set `_leaf_kind` on a
  Button: `primary`, `secondary`, `ghost`, `danger`, `row`, `row-danger`, `caption`); see how
  `leaf/menu.lua`, `leaf/booksheet.lua`, `leaf/bookdetails.lua`, `leaf/reader_chrome.lua` build
  sheets, heads, tabs, rows, toolbars — copy their patterns.
- Local classes inside a KOReader file (e.g. `MenuItem`, `TouchMenuItem`, `VirtualKey`) are reached
  with `debug.getupvalue` on a function of the same file (see `leaf/menu.lua`, `leaf/typeset.lua`).
- Project: Title (the library plugin) loads **after** the patches: `leaf/library.lua` hooks its
  modules from a `require` watcher (`hooks = { titlebar = ..., covermenu = ... }`). PT's files live
  in the user's config (copied into the sandbox at `.sandbox/home/plugins/projecttitle.koplugin`);
  read them there, never edit them.

## Crash traps (these crash KOReader *outside* L.wrap, at paint time)
1. A widget's `dimen` must be a real `Geom` (`Geom:new{...}`). `HorizontalGroup:getSize()` returns
   a plain table: wrap it (`Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }`).
2. After calling `:getSize()` on a Horizontal/VerticalGroup, inserting more children requires
   `group:resetLayout()`, or paint indexes a missing offset.
3. Never name a loop variable `_` in a file that uses gettext's `_()`.
4. Never compare a cdata colour with `nil` (`c ~= nil` calls its `__eq`): test truthiness.
5. Text boxes (`TextBoxWidget`) paint a white background: pass `bgcolor = T.color("bg")` (or the
   surface they sit on) when not on white.

## Run and check (always look at the screenshots)
- `tools/ko-sandbox.sh --shots DIR [--scenes a,b] [--night]` renders offscreen at the Kindle 11 size
  (1072x1448), one PNG per scene, and fails if KOReader logged an ERROR (see `.sandbox/last-run.log`).
  Scenes live in `koreader/patches/2-autoshot.lua`; **add a scene for every surface you port**.
- `--reset` rebuilds the sandbox. Each git worktree has its own `.sandbox/`.
- Prototype screenshots: `cd prototype && ./shot.sh "#/reader?id=animal-farm&o=toc" shots/x.png paper`
  (600x800). Find the right hash in the designer panel list (`App.demo(...)` calls in
  `prototype/js/screens/*.js`). Compare side by side (PIL montage), fix, repeat.
- Run the full scene set before you finish: zero `ERROR` lines.

## Rules
- Keep KOReader's behaviour: callbacks, settings, events. Redraw; don't remove features (if a
  KOReader feature has no place in the design, keep it reachable, e.g. a "⋮"/"Manage…" that opens
  KOReader's original screen).
- Tokens only (no raw colours/sizes) except where the prototype CSS itself uses a raw value.
- Register your module in `L.MODULES` (core.lua) **at the end of the list**; put your scenes in a
  block marked `-- <your area> scenes`; new icons go in `tools/build-icons.py` MAP in a block marked
  with your area, then run `python3 tools/build-icons.py` (needs network for lucide-static).
- Commit on your branch with a clear message. **No `Co-Authored-By` trailer** (commits go out under
  the repo owner's name). **Do not push.**
