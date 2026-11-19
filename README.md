# Leaf

A complete redesign of the [KOReader](https://github.com/koreader/koreader) interface for Kindle,
built as a plugin plus user patches on top of stock KOReader (no fork).

## Layout
- `koreader/` mirrors the `koreader/` folder on the device (`/mnt/us/koreader` on Kindle,
  `~/.config/koreader` on desktop Linux): `patches/`, `icons/`, `plugins/`, `fonts/`.
- `prototype/`: the interactive HTML prototype that is the design spec. Open `prototype/index.html` in a browser.
  Design rules and the design system are in `prototype/BRIEF.md`; QA tools in `prototype/tools/`
  (`python3 -m venv prototype/tools/.venv && prototype/tools/.venv/bin/pip install -r prototype/tools/requirements.txt`).

Tested against KOReader **v2026.07.1**.

## Desktop sandbox
`tools/ko-sandbox.sh` runs the desktop KOReader (`~/Applications/koreader-linux`) with `KO_HOME=.sandbox/home`,
so the real `~/.config/koreader` is never touched. The repo's `koreader/` patches, icons, `leaf/` and fonts are
symlinked in; books, Project: Title and its config are copied once (`--reset` rebuilds it).

- `tools/ko-sandbox.sh`: window at half the Kindle 11 size (536x724; same layout, sizes scale by the short side). `--full` 1072x1448, `--proto` 600x800 (the prototype's 6″ frame).
- `tools/ko-sandbox.sh --shots DIR [--scenes fm,menu,...] [--night]`: renders offscreen at 1072x1448, screenshots every scene of `koreader/patches/2-autoshot.lua`, quits, and fails on Lua errors.

## Leaf runtime
`koreader/patches/2-leaf.lua` is the only entry point; the code is in `koreader/leaf/` (`core.lua` explains the rules).
Each module loads under `pcall`, and overridden methods fall back to KOReader's original if they ever error.
**Turn Leaf off** without deleting anything: create an empty file `koreader/leaf.disabled` (on the Kindle: `/mnt/us/koreader/leaf.disabled`).
`koreader/leaf/tokens.lua` is generated: edit `prototype/css/tokens.css`, then run `python3 tools/tokens2lua.py`.
The pre-Leaf style patches are kept, not loaded, in `koreader/patches/legacy/`.
