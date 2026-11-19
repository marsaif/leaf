--[[
    Leaf list pages (safety-net items 17, 18): Menu / MenuItem (table of contents, bookmarks,
    search results, dictionary and OPDS lists, history fallback...). KeyValuePage: leaf/kvpages.lua.

    * Menu: Leaf title (TitleBar left-aligned, --fs-head, Menu's own big title face dropped);
      no dot leaders; row text Inter --fs-md, the right-hand text (page numbers) --fs-sm.
    Row heights, paging and every callback stay KOReader's; the bespoke reader sheets
    (contents / bookmarks / notes with the book header) are their own port.
--]]
local M = {}

function M.apply(L)
    local T = L.T
    local fonts = require("leaf/fonts")
    local Menu = require("ui/widget/menu")
    local TitleBar = require("ui/widget/titlebar")
    local ui = fonts.FILES["ui"]

    -- MenuItem is local to menu.lua: reach it through Menu.updateItems' upvalues
    local MenuItem
    for _, fn in ipairs({ Menu.updateItems, Menu._updateItemsBuildUI, Menu.init }) do
        if type(fn) == "function" and not MenuItem then
            local i = 1
            while true do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                if name == "MenuItem" then MenuItem = value break end
                i = i + 1
            end
        end
    end

    L.wrap(Menu, "init", function(orig, self)
        self.with_dots = false
        local orig_new = TitleBar.new
        TitleBar.new = function(class, o)
            o = o or {}
            o.align = "left"
            o.title_face = nil -- Leaf's --fs-head title
            return orig_new(class, o)
        end
        local ok, err = pcall(orig, self)
        TitleBar.new = orig_new
        if not ok then error(err, 0) end
    end, "Menu:init")

    if MenuItem then
        L.wrap(MenuItem, "init", function(orig, self)
            self.with_dots = false
            self.font = ui
            self.font_size = T.fs("fs-md")
            self.infont = ui
            self.infont_size = T.fs("fs-sm")
            return orig(self)
        end, "MenuItem:init")
    else
        L.err("lists: MenuItem not found, rows keep KOReader's fonts")
    end
end

return M
