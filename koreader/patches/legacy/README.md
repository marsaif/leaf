Pre-Leaf style patches, kept for reference. KOReader only runs patches directly in `patches/`,
so nothing in this folder is loaded. Leaf replaces them:

- `2-clean-menus.lua` (square corners, TouchMenu sizes) -> leaf sizes + TouchMenu restyle
- `2-font-override.lua` (Source Sans UI) -> leaf/fonts.lua (Inter)
- `2-dialogs.lua` (input dialog look) -> the InputDialog restyle
- `2-menu-panel.lua` (floating menu card, keyword icons) -> leaf/menu.lua + leaf/menu_icons.lua
- `2-library-panel.lua` ("+" drop-down panel) -> leaf/plus.lua
