--[[
    Leaf library (prototype screen "library"), drawn through the Project: Title plugin.

    Project: Title (PT) loads after the patches, so its modules are hooked as they are required
    (a `require` watcher for PT's module names; KOReader's own modules have different names).

    Phase 1, the header (PT's titlebar.lua, which is the user's customised one):
      * "Library" (or History / Favorites / Select books) in Playfair SemiBold --fs-display, the
        count in --fs-sm --text-3 (.ko-header .title.display + .count);
      * Lucide icon buttons: search, sort, +, and ☰ which opens the main menu (prototype);
      * Leaf tabs (.ko-tabs): --fs-md, active --text semibold with a --bw-lg accent underline,
        inactive --text-2, a --border hairline under the row.
    Same fields, callbacks and helpers as PT's TitleBar (setCount, getHeight, layouts...).
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local M = {}

local function header_init(L, self)
    local T = L.T
    local IconButton = require("ui/widget/iconbutton")
    local Button = require("ui/widget/button")
    local fonts = require("leaf/fonts")
    local W = Screen:getWidth()
    self.width = W
    local side = T.px("sp-5")
    local s = T.px("icon-md")
    local btn_pad = math.floor((T.px("hit") - s) / 2)
    local function fm() return require("apps/filemanager/filemanager").instance end
    local function icon_button(icon, tap, hold)
        return IconButton:new{ icon = icon, width = s, height = s, padding = btn_pad,
            callback = tap, hold_callback = hold, show_parent = self.show_parent }
    end

    local is_library = self.mode ~= "history" and self.mode ~= "collections"
    local title = self.right1_icon == "check" and "Select books"
        or (self.mode == "history" and "History")
        or (self.mode == "collections" and "Favorites")
        or "Library"
    local title_widget = TextWidget:new{ text = title, face = L.face("display-semibold", "fs-display"), padding = 0 }
    self.count_widget = TextWidget:new{ text = "", face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), padding = 0 }

    local buttons
    if is_library then
        self.right3_button = icon_button("pt_search", function()
            if fm() and fm().filesearcher then fm().filesearcher:onShowFileSearch() end
        end)
        self.right2_button = icon_button("pt_sort", function()
            local UIManager = require("ui/uimanager")
            local ButtonDialog = require("ui/widget/buttondialog")
            local dialog
            local function choice(text, mode)
                return { { text = text, callback = function()
                    UIManager:close(dialog)
                    if fm() then fm():onSetSortBy(mode) end
                end } }
            end
            dialog = ButtonDialog:new{ title = "Sort by", buttons = {
                choice("Title", "strcoll"), choice("Recently read", "access"),
                choice("Date added", "date"), choice("Progress", "percent_unopened_first") } }
            UIManager:show(dialog)
        end)
        self.right1_button = icon_button(self.right1_icon == "plus" and "pt_plus" or self.right1_icon,
            self.right1_icon_tap_callback, self.right1_icon_hold_callback)
        -- ☰ opens the main menu (prototype header), the + already opens the plus popover
        self.settings_button = icon_button("appbar.menu", function()
            if fm() and fm().menu then fm().menu:onShowMenu() end
        end)
        buttons = { self.right3_button, self.right2_button, self.right1_button, self.settings_button }
    else
        self.right2_button = icon_button(self.right2_icon, self.right2_icon_tap_callback, self.right2_icon_hold_callback)
        self.right1_button = icon_button(self.right1_icon, self.right1_icon_tap_callback, self.right1_icon_hold_callback)
        buttons = { self.right2_button, self.right1_button }
    end

    -- row 1: title + count left, actions right (.ko-header: --h-header, --sp-5 sides)
    local hh = math.max(T.px("h-header"), title_widget:getSize().h + 2 * T.px("sp-2"))
    local left = HorizontalGroup:new{ align = "center",
        HorizontalSpan:new{ width = side }, title_widget,
        HorizontalSpan:new{ width = T.px("sp-2") }, self.count_widget }
    local right = HorizontalGroup:new{ align = "center" }
    for _, b in ipairs(buttons) do table.insert(right, b) end
    table.insert(right, HorizontalSpan:new{ width = side - btn_pad })
    local row1 = OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
        LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, left },
        RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, right },
    }

    -- row 2: Leaf tabs (.ko-tabs)
    local function tab(text, active, tap, hold)
        local face = active and fonts.FILES["ui-semibold"] or fonts.FILES["ui"]
        local probe = TextWidget:new{ text = text, face = require("ui/font"):getFace(face, T.fs("fs-md")) }
        local w = probe:getSize().w
        probe:free()
        local b = Button:new{ text = text, bordersize = 0, radius = 0, margin = 0, padding = 0, padding_h = 0,
            text_font_face = face, text_font_size = T.fs("fs-md"), text_font_bold = false,
            width = w, height = T.px("hit") - T.px("bw-lg"),
            callback = tap, hold_callback = hold or nil, show_parent = self.show_parent }
        if b.label_widget then
            b.label_widget.fgcolor = T.color(active and "text" or "text-2")
            if b.label_widget.update then b.label_widget:update() end
        end
        local g = VerticalGroup:new{ align = "left", b,
            active and LineWidget:new{ dimen = Geom:new{ w = w, h = T.px("bw-lg") }, background = T.color("accent") }
                or VerticalSpan:new{ width = T.px("bw-lg") } }
        return b, g
    end
    local t1, t2, t3, t4, g1, g2, g3, g4
    t1, g1 = tab("Library", is_library, self.left1_icon_tap_callback, self.left1_icon_hold_callback)
    t2, g2 = tab("Favorites", self.mode == "collections", self.left2_icon_tap_callback, self.left2_icon_hold_callback)
    t3, g3 = tab("History", self.mode == "history", self.left3_icon_tap_callback, self.left3_icon_hold_callback)
    t4, g4 = tab("Continue reading", false, self.right3_icon_tap_callback, false)
    self.left1_button, self.left2_button, self.left3_button, self.center_button = t1, t2, t3, t4
    local gap = T.px("sp-5")
    local row2 = HorizontalGroup:new{ align = "bottom",
        HorizontalSpan:new{ width = side }, g1, HorizontalSpan:new{ width = gap }, g2,
        HorizontalSpan:new{ width = gap }, g3, HorizontalSpan:new{ width = gap }, g4 }

    local content = VerticalGroup:new{ align = "left",
        row1, row2,
        LineWidget:new{ dimen = Geom:new{ w = W, h = T.px("hairline") }, background = T.color("border") } }
    self.titlebar_height = content:getSize().h
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = self.titlebar_height }
    table.insert(self, content)
    self.left_button = self.left1_button
    self.right_button = self.right1_button
    OverlapGroup.init(self)
end

function M.apply(L)
    local T = L.T
    -- the footer (.lb footer): folder / sort text --fs-sm --text-3, "Page x of y" --fs-sm --text-2
    local function style_footer(menu)
        local cf = menu.cur_folder_text
        if cf and cf.setText then
            cf.face = L.face("ui", "fs-sm")
            cf.fgcolor = T.color("text-3")
            cf:setText(cf.text or "")
        end
        local pt = menu.page_info_text
        if pt and pt.setText and pt._leaf_kind ~= "caption" then
            pt._leaf_kind = "caption"
            pt:setText(pt.text or "", pt.width)
        end
    end
    local hooks = {
        -- PT's header (its titlebar.lua; KOReader's is "ui/widget/titlebar")
        -- PT's list / grid container: footer
        covermenu = function(CoverMenu)
            if type(CoverMenu) ~= "table" or not CoverMenu.menuInit then return end
            L.wrap(CoverMenu, "menuInit", function(orig, self, ...)
                orig(self, ...)
                style_footer(self)
            end, "PT CoverMenu:menuInit")
            L.wrap(CoverMenu, "updatePageInfo", function(orig, self, ...)
                orig(self, ...)
                style_footer(self)
            end, "PT CoverMenu:updatePageInfo")
        end,
        titlebar = function(TitleBar)
            if type(TitleBar) ~= "table" or not TitleBar.setCount then return end -- not PT's
            L.wrap(TitleBar, "init", function(orig, self) header_init(L, self) end, "PT TitleBar:init")
        end,
    }
    local done = {}
    local orig_require = require
    _G.require = function(name, ...)
        local mod = orig_require(name, ...)
        local hook = hooks[name]
        if hook and not done[name] then
            done[name] = true
            local ok, err = pcall(hook, mod)
            if ok then L.log("library: hooked", name) else L.err("library: hook", name, "failed:", err) end
        end
        return mod
    end
end

return M
