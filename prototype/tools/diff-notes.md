## Notes

- `shots/baseline/` was rebuilt from `.backup-before-cleanup/` (the untouched pre-cleanup code) with `tools/snap.py --out baseline --root .backup-before-cleanup`
  after snap.py started giving every `#/reader…` state a fresh page load: the reader keeps module state (last page) between renders, so without the reload a
  reader state showed whatever page the previous demo left behind. Baseline and current use the same procedure; two consecutive runs on unchanged code differ by 0 px.
- "Small" changes (< 0.5%) are the global component unifications: primary/danger buttons semibold, `.ko-icon-tile`/`.ko-crumbs`/`.ko-pill`/`.ko-eyebrow`
  consolidation (icon 13→14px), cover shadow token, page-title line height, sub-pixel antialiasing.
