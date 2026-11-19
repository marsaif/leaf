--[[
    Leaf top menu (safety-net item 20): KOReader's TouchMenu (the whole menu tree, in the library
    and in the reader, plus every plugin menu). Target: prototype overlay "main-menu".

    A tall bottom sheet (84% of the screen, --bg-raised, --r-xl top corners):
      grip · head ("Menu" + context, or ← submenu name + parent; gear = Settings tab; ×)
      · text tabs with an accent underline (.ko-tabs) · groups of rows as cards (.ko-group):
      icon tile, label, value on the right ("Sort by: name" -> Sort by … Name), and a chevron
      (submenu), a toggle (check items) or a radio mark (radio items).
      KOReader's separators start a new card. Pages when the list is longer than the sheet,
      with ‹ Page x of y › at the bottom.
    KOReader's logic is kept: tab switching (TouchMenuBar callbacks), submenus (item_table_stack),
    paging, onMenuSelect / hold-for-help, keep_menu_open, check callbacks, search, openMenu.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

-- tab labels, as the prototype's TAB_META
local TAB_LABEL = {
    ["appbar.filebrowser"] = _("Library"),
    ["appbar.navigation"] = _("Navigation"),
    ["appbar.typeset"] = _("Typesetting"),
    ["appbar.settings"] = _("Settings"),
    ["appbar.tools"] = _("Tools"),
    ["appbar.search"] = _("Search"),
    ["appbar.menu"] = _("Main menu"),
}

local Grip = Widget:extend{}
function Grip:init()
    self.T = require("leaf/core").T
    self.dimen = Geom:new{ w = Screen:scaleBySize(36 * self.T.scale), h = self.T.px("sp-1") }
end
function Grip:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, self.T.color("border-strong"), math.floor(self.dimen.h / 2))
end

--- the row's text without KOReader's "▸", split into label and value ("Sort by: name")
local function label_value(item)
    local text = item.text_func and item.text_func() or item.text or ""
    text = tostring(text)
    local label, value = text:match("^(.-):%s+(.+)$")
    if label and label ~= "" and #value <= 28 and not value:find("\n") then
        value = value:gsub("^%l", string.upper)
        return label, value
    end
    return text, nil
end

local ICONS
local function row_icon(label)
    ICONS = ICONS or require("leaf/menu_icons")
    local l = label:lower()
    for _, pair in ipairs(ICONS) do
        if l:find(pair[1], 1, true) then return pair[2] end
    end
    return "pt_i_dot"
end

function M.apply(L)
    local T = L.T
    local TouchMenu = require("ui/widget/touchmenu")
    local IconButton = require("ui/widget/iconbutton")
    local Button = require("ui/widget/button")
    local LeafToggle = require("leaf/widgets/toggle")

    -- TouchMenuItem is local to touchmenu.lua: reach it through updateItems' upvalues
    local TouchMenuItem
    do
        local i = 1
        while true do
            local name, value = debug.getupvalue(TouchMenu.updateItems, i)
            if not name then break end
            if name == "TouchMenuItem" then TouchMenuItem = value end
            i = i + 1
        end
    end
    assert(TouchMenuItem, "TouchMenuItem not found")

    local hair = T.px("hairline")

    ---------------------------------------------------------------- rows
    L.wrap(TouchMenuItem, "init", function(orig, self)
        orig(self) -- gestures, enabled state, checkmark logic
        local item = self.item
        local enabled = self:isEnabled()
        local w, h = self.dimen.w, self.dimen.h
        local pad = T.px("sp-4")
        local label, value = label_value(item)

        -- trailing control
        local trailing
        local sub = item.sub_item_table ~= nil or item.sub_item_table_func ~= nil
        local checkable = item.checked_func ~= nil
        local checked = item.checked_func and item.checked_func() or item.checked
        if checkable and item.radio then
            local s = T.px("icon-md")
            trailing = IconWidget:new{ icon = checked and "leaf.radio.on" or "leaf.radio.off", width = s, height = s, alpha = true, dim = not enabled }
        elseif checkable then
            trailing = LeafToggle:new{ on = checked and true or false, enabled = enabled }
        elseif sub then
            local s = T.px("icon-md")
            trailing = IconWidget:new{ icon = "chevron.right", width = s, height = s, alpha = true, dim = true }
        end
        local trailing_w = trailing and trailing:getSize().w or 0

        -- icon tile (.ko-icon-tile: 32px, --r-md, --surface-2, 18px icon)
        local tile_s = T.px("h-chip")
        local icon_s = T.px("icon-tile")
        local tile = FrameContainer:new{
            bordersize = hair, color = T.color("border"), background = T.color("surface-2"),
            radius = T.px("r-md"), padding = 0,
            CenterContainer:new{ dimen = Geom:new{ w = tile_s - 2 * hair, h = tile_s - 2 * hair },
                IconWidget:new{ icon = row_icon(label), width = icon_s, height = icon_s, alpha = true, dim = not enabled } },
        }

        local value_widget, value_w = nil, 0
        if value then
            value_widget = TextWidget:new{ text = value, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"),
                max_width = math.floor(w * 0.35) }
            value_w = value_widget:getSize().w + T.px("sp-2")
        end
        local gap = T.px("sp-3")
        local label_w = w - 2 * pad - tile_s - gap - value_w - (trailing and (trailing_w + T.px("sp-2")) or 0)
        local label_widget = TextWidget:new{
            text = label, face = L.face("ui", "fs-md"), max_width = math.max(label_w, T.px("h-row")),
            fgcolor = T.color(enabled and "text" or "disabled"),
        }
        self.text_truncated = label_widget:isTruncated()

        local left = HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = pad }, tile, HorizontalSpan:new{ width = gap }, label_widget }
        local right = HorizontalGroup:new{ align = "center" }
        if value_widget then
            table.insert(right, value_widget)
            if trailing then table.insert(right, HorizontalSpan:new{ width = T.px("sp-2") }) end
        end
        if trailing then table.insert(right, trailing) end
        table.insert(right, HorizontalSpan:new{ width = pad })

        self.item_frame = FrameContainer:new{
            width = w, bordersize = 0, padding = 0,
            OverlapGroup:new{ dimen = Geom:new{ w = w, h = h },
                LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, left },
                RightContainer:new{ dimen = Geom:new{ w = w, h = h }, right },
            },
        }
        self[1] = self.item_frame
        -- check items toggle from the switch on the right, not a tap on the left edge
        self.checkmark_tap_width = 0
        self._leaf_toggle_x = trailing and (w - pad - trailing_w - T.px("sp-2")) or nil
    end, "TouchMenuItem:init")

    -- a tap on the toggle of an item with a checkmark_callback acts on the checkmark only
    L.wrap(TouchMenuItem, "onTapSelect", function(orig, self, arg, ges)
        if self.item.checkmark_callback and self._leaf_toggle_x and ges and ges.pos and self.dimen
                and (ges.pos.x - self.dimen.x) >= self._leaf_toggle_x then
            self.menu:onMenuSelect(self.item, true)
            return true
        end
        return orig(self, arg, ges)
    end, "TouchMenuItem:onTapSelect")

    ---------------------------------------------------------------- titles for submenus
    -- the label of the item being opened is remembered; updateItems() keeps the title list in
    -- step with KOReader's own item_table_stack (so going back needs no extra hook)
    L.wrap(TouchMenu, "onMenuSelect", function(orig, self, item, tap_on_checkmark)
        self._leaf_pending = (label_value(item))
        local ok, ret = pcall(orig, self, item, tap_on_checkmark)
        self._leaf_pending = nil
        if not ok then error(ret, 0) end
        return ret
    end, "TouchMenu:onMenuSelect")
    local function sync_titles(self)
        self._leaf_titles = self._leaf_titles or {}
        local depth = #(self.item_table_stack or {})
        while #self._leaf_titles > depth do table.remove(self._leaf_titles) end
        while #self._leaf_titles < depth do table.insert(self._leaf_titles, self._leaf_pending or "") end
    end

    ---------------------------------------------------------------- the sheet
    L.wrap(TouchMenu, "init", function(orig, self)
        self.item_height = T.px("h-row")
        orig(self)
        -- gestures follow the sheet, which sits at the bottom of the screen
        local range = function() return self._leaf_frame and self._leaf_frame.dimen or self.dimen end
        self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = range } }
        self.ges_events.Pan = { GestureRange:new{ ges = "pan", range = range } }
    end, "TouchMenu:init")

    L.wrap(TouchMenu, "onTapCloseAllMenus", function(orig, self, arg, ges_ev)
        local f = self._leaf_frame and self._leaf_frame.dimen
        if f and f.x then
            if ges_ev.pos:notIntersectWith(f) then self:closeMenu() end
            return true
        end
        return orig(self, arg, ges_ev)
    end, "TouchMenu:onTapCloseAllMenus")

    local function context_name()
        local RUI = package.loaded["apps/reader/readerui"]
        local rui = RUI and RUI.instance
        if rui and rui.document then
            local props = rui.doc_props or {}
            return props.display_title or props.title or (rui.document.file or ""):match("([^/]+)$") or ""
        end
        return _("Library")
    end

    local function head(self, W)
        local pad = T.px("sp-5")
        local s = T.px("icon-md")
        local btn_pad = math.floor((T.px("hit") - s) / 2)
        local function icon_button(icon, cb)
            return IconButton:new{ icon = icon, width = s, height = s, padding = btn_pad, callback = cb, show_parent = self.show_parent }
        end
        local titles = self._leaf_titles or {}
        local depth = #(self.item_table_stack or {})
        local title, sub
        if depth > 0 and titles[#titles] then
            title = titles[#titles]
            sub = titles[#titles - 1] or TAB_LABEL[(self.tab_item_table[self.cur_tab] or {}).icon] or ""
        else
            title, sub = _("Menu"), context_name()
        end
        local left = HorizontalGroup:new{ align = "center" }
        if depth > 0 then
            table.insert(left, HorizontalSpan:new{ width = pad - btn_pad })
            table.insert(left, icon_button("leaf.kb.left", function() self:backToUpperMenu(true) end))
            table.insert(left, HorizontalSpan:new{ width = T.px("sp-1") })
        else
            table.insert(left, HorizontalSpan:new{ width = pad })
        end
        local right = HorizontalGroup:new{ align = "center" }
        if depth == 0 then
            for i, tab in ipairs(self.tab_item_table) do
                if tab.icon == "appbar.settings" and i ~= self.cur_tab then
                    table.insert(right, icon_button("appbar.settings", function() self.bar:switchToTab(i) end))
                end
            end
        end
        table.insert(right, icon_button("close", function() self:closeMenu() end))
        table.insert(right, HorizontalSpan:new{ width = T.px("sp-3") - btn_pad })
        local text_w = W - left:getSize().w - right:getSize().w - T.px("sp-2")
        local texts = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = title, face = L.face("ui-semibold", "fs-head"), max_width = text_w } }
        if sub and sub ~= "" then
            table.insert(texts, TextWidget:new{ text = sub, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = text_w })
        end
        table.insert(left, texts)
        left:resetLayout() -- getSize() above cached the offsets: recompute them with the texts
        local hh = math.max(T.px("h-header"), texts:getSize().h + 2 * T.px("sp-2"))
        return OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, left },
            RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, right },
        }
    end

    local function tabs(self, W)
        local pad = T.px("sp-5")
        local function build(size)
            local g = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = pad } }
            for i, tab in ipairs(self.tab_item_table) do
                local on = i == self.cur_tab
                local text = TAB_LABEL[tab.icon] or tostring(tab.icon or ""):gsub("^appbar%.", ""):gsub("^%l", string.upper)
                local tw = TextWidget:new{ text = text, face = L.face(on and "ui-semibold" or "ui", size),
                    fgcolor = T.color(on and "text" or "text-2") }
                local w = tw:getSize().w
                local b = Button:new{ text = text, bordersize = 0, padding = 0, padding_h = 0,
                    text_font_face = require("leaf/fonts").FILES[on and "ui-semibold" or "ui"], text_font_size = T.fs(size),
                    width = w, height = T.px("hit") - T.px("bw-lg"), show_parent = self.show_parent,
                    callback = function() self.bar:switchToTab(i) end }
                if b.label_widget then
                    b.label_widget.fgcolor = T.color(on and "text" or "text-2")
                    if b.label_widget.update then b.label_widget:update() end
                end
                tw:free()
                if i > 1 then table.insert(g, HorizontalSpan:new{ width = T.px("sp-5") }) end
                table.insert(g, VerticalGroup:new{ align = "left", b,
                    on and LineWidget:new{ dimen = Geom:new{ w = w, h = T.px("bw-lg") }, background = T.color("accent") }
                        or VerticalSpan:new{ width = T.px("bw-lg") } })
            end
            return g
        end
        local g = build("fs-md")
        if g:getSize().w > W then g = build("fs-sm") end
        return VerticalGroup:new{ align = "left", g,
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") } }
    end

    --- groups of rows for the items [first, last]; nil height check helper
    local function rows_height(self, first, last, row_h, gap)
        local h, groups = 0, 1
        for i = first, last do
            h = h + row_h + hair
            if self.item_table[i].separator and i < last then groups = groups + 1 end
        end
        return h + groups * (2 * hair) + (groups - 1) * gap
    end

    L.wrap(TouchMenu, "updateItems", function(orig, self, target_page, target_item_id)
        local n = #self.item_table
        if n == 0 then return end
        sync_titles(self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local r = T.px("r-xl")
        local sheet_h = math.floor(H * 0.84)
        local side = T.px("sp-3")
        local card_w = W - 2 * hair - 2 * side
        local row_w = card_w - 2 * hair
        local row_h = T.px("h-row")
        local gap = T.px("sp-3")

        local top = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = Geom:new{ w = W - 2 * hair, h = T.px("sp-1") }, Grip:new{} },
            VerticalSpan:new{ width = T.px("sp-1") },
            head(self, W - 2 * hair),
            tabs(self, W - 2 * hair),
        }
        local footer_h = T.px("hit") + T.px("sp-2")
        local available = sheet_h - top:getSize().h - 2 * gap - footer_h

        -- the largest page size for which every page fits, separators and card gaps included
        local per = math.max(1, math.floor(available / (row_h + hair)))
        while per > 1 do
            local ok = true
            for first = 1, n, per do
                if rows_height(self, first, math.min(n, first + per - 1), row_h, gap) > available then ok = false break end
            end
            if ok then break end
            per = per - 1
        end
        self.perpage = per
        self.page_num = math.ceil(n / per)
        if target_item_id ~= nil then
            for i, v in ipairs(self.item_table) do
                if v.menu_item_id == target_item_id then
                    target_page = math.floor((i - 1) / per) + 1
                    break
                end
            end
        end
        self.page = target_page or self.page or 1
        if self.page > self.page_num then self.page = self.page_num end
        if self.page < 1 then self.page = 1 end

        -- cards
        self.layout = {}
        local body = VerticalGroup:new{ align = "center", VerticalSpan:new{ width = gap } }
        local card
        local function close_card()
            if card then
                table.insert(body, FrameContainer:new{
                    bordersize = hair, color = T.color("border"), background = T.color("surface"),
                    radius = T.px("r-lg"), padding = 0, card })
                card = nil
            end
        end
        local first = (self.page - 1) * per + 1
        local last = math.min(n, first + per - 1)
        for i = first, last do
            local item = self.item_table[i]
            item.idx = i
            if not card then
                if #body > 1 then table.insert(body, VerticalSpan:new{ width = gap }) end
                card = VerticalGroup:new{ align = "left" }
            else
                local inset = T.px("sp-4") + T.px("h-chip") + T.px("sp-3")
                table.insert(card, HorizontalGroup:new{ HorizontalSpan:new{ width = inset },
                    LineWidget:new{ dimen = Geom:new{ w = row_w - inset, h = hair }, background = T.color("border") } })
            end
            local row = TouchMenuItem:new{ item = item, menu = self,
                dimen = Geom:new{ w = row_w, h = row_h }, show_parent = self.show_parent }
            table.insert(card, row)
            if row:isEnabled() then table.insert(self.layout, { row }) end
            if item.separator then close_card() end
        end
        close_card()

        -- pager
        local footer
        if self.page_num > 1 then
            local s = T.px("icon-md")
            local p = math.floor((T.px("hit") - s) / 2)
            local prev = IconButton:new{ icon = "chevron.left", width = s, height = s, padding = p, show_parent = self.show_parent,
                callback = function() self:onPrevPage() end, hold_callback = function() self:onFirstPage() end }
            local nxt = IconButton:new{ icon = "chevron.right", width = s, height = s, padding = p, show_parent = self.show_parent,
                callback = function() self:onNextPage() end, hold_callback = function() self:onLastPage() end }
            if self.page <= 1 then prev.enabled = false end
            if self.page >= self.page_num then nxt.enabled = false end
            footer = CenterContainer:new{ dimen = Geom:new{ w = W - 2 * hair, h = footer_h },
                HorizontalGroup:new{ align = "center", prev,
                    TextWidget:new{ text = require("ffi/util").template(_("Page %1 of %2"), self.page, self.page_num),
                        face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") },
                    nxt } }
        end

        local content = VerticalGroup:new{ align = "center", top, body }
        local frame = FrameContainer:new{
            width = W, height = sheet_h + r,
            bordersize = hair, color = T.color("border-strong"), background = T.color("bg-raised"),
            radius = r, padding = 0,
            OverlapGroup:new{ dimen = Geom:new{ w = W - 2 * hair, h = sheet_h + r - 2 * hair },
                content,
                footer and BottomContainer:new{ dimen = Geom:new{ w = W - 2 * hair, h = sheet_h - hair }, footer } or nil,
            },
        }
        self._leaf_frame = frame
        self.item_group = content
        self[1] = BottomContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H + r }, frame }
        self.dimen.w, self.dimen.h = W, sheet_h
        pcall(function() self:moveFocusTo(1, 1, FocusManager.NOT_FOCUS) end)

        local fresh = self.is_fresh
        self.is_fresh = false
        UIManager:setDirty(self.show_parent, function()
            return fresh and "flashui" or "ui", Geom:new{ x = 0, y = H - sheet_h, w = W, h = sheet_h }
        end)
    end, "TouchMenu:updateItems")
end

return M
