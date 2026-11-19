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
