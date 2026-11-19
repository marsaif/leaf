--[[
    Leaf top menu (safety-net item 20): KOReader's TouchMenu (the whole menu tree, in the library
    and in the reader, plus every plugin menu). Target: prototype overlay "main-menu".

    A tall bottom sheet (84% of the screen, --bg-raised, --r-xl top corners):
      grip · head: "Menu" + context ("Library" / "Reading · <book>") with Quick settings (Leaf
      sheet), All settings (the Settings tab) and ×; in a submenu: ← title [value pill], the crumbs
      (tab › parents) under it, ×, and no tabs
      · text tabs with an accent underline (.ko-tabs), top level only
      · a shortcut card on well-known submenus (Reading statistics -> stats, Network -> Wi-Fi,
        Screen -> frontlight, Device -> sleep screen; prototype heroFor)
      · groups of rows as cards (.ko-group): icon tile (first two levels; the prototype's icon per
      label, menu_icons.lua), label (human name + "KOReader: …" for engineering labels), an (i)
      help button when KOReader has help text, value on the right ("Sort by: name" -> Sort by …
      Name), and a chevron (submenu), a toggle (check items), a leading radio mark (radio items,
      selected = semibold), ↗ (rows that open a screen) or a pencil (a value you edit).
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
local T_ = require("ffi/util").template
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
    text = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
    local label, value = text:match("^(.-):%s+(.+)$")
    if label and label ~= "" and #value <= 28 and not value:find("\n") then
        value = value:gsub("^%l", string.upper)
        return label, value
    end
    return text, nil
end

-- engineering labels shown with a human name; KOReader's name stays as small help text
-- (prototype menus.js HUMAN)
local HUMAN = {
    ["Speed reading module - perception expander"] = _("Speed-reading guide"),
    ["Cloud storage+"] = _("Cloud storage (extended)"),
    ["Hide non-linear fragments"] = _("Skip non-linear sections"),
    ["Screen DPI"] = _("Screen density"),
    ["Panel zoom (manga/comic)"] = _("Zoom into comic panels"),
}

-- rows that open a Leaf screen rather than a list (prototype menus.js SPECIAL): an ↗ mark
local SPECIAL = {}
for _i, l in ipairs({ "open last document", "open previous document", "exit", "restart koreader", "network info",
        "table of contents", "bookmarks", "go to page", "skim document", "book map", "page browser",
        "bookmark browser", "dictionary lookup", "translate current page", "wikipedia lookup", "history",
        "favorites", "collections", "book information", "book status", "fulltext search",
        "last fulltext search results", "bookmark search", "file search", "last file search results",
        "calibre metadata search", "menu search", "version", "about", "current book", "reading progress",
        "time range", "calendar view", "today's timeline" }) do SPECIAL[l] = true end

local ICONS
--- the row's icon: the prototype's exact choice, else the first matching keyword
local function row_icon(label)
    ICONS = ICONS or require("leaf/menu_icons")
    local l = label:lower()
    local exact = ICONS.EXACT[l]
    if exact then return "leaf.mn." .. exact end
    for _i, pair in ipairs(ICONS.KEYWORDS) do
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
        local gap = T.px("sp-3")
        local label, value = label_value(item)
        local ko_label
        if HUMAN[label] then ko_label, label = label, HUMAN[label] end
        -- icon tiles on the first two levels only (prototype: icons when path.length <= 1)
        local icons = self.menu and self.menu._leaf_icons ~= false

        -- kind of row
        local sub = item.sub_item_table ~= nil or item.sub_item_table_func ~= nil
        local checkable = item.checked_func ~= nil
        local checked = item.checked_func and item.checked_func() or item.checked
        local radio = checkable and item.radio
        local special = not sub and not checkable and SPECIAL[label:lower()]

        -- trailing control
        local trailing
        local s = T.px("icon-md")
        if radio then
            trailing = nil -- the radio mark leads the row (.mn-row.is-radio)
        elseif checkable then
            trailing = LeafToggle:new{ on = checked and true or false, enabled = enabled }
        elseif sub then
            trailing = IconWidget:new{ icon = "chevron.right", width = s, height = s, alpha = true, dim = true }
        elseif special then
            trailing = IconWidget:new{ icon = "leaf.mn.arrow-up-right", width = T.px("icon-sm"), height = T.px("icon-sm"), alpha = true, dim = true }
        elseif value then
            trailing = IconWidget:new{ icon = "leaf.mn.pencil", width = T.px("icon-sm"), height = T.px("icon-sm"), alpha = true, dim = true }
        end
        local trailing_w = trailing and trailing:getSize().w or 0

        -- help: an (i) button before the trailing control (.mn-help); hold still shows it too
        local help
        if item.help_text or item.help_text_func then
            local hs = T.px("icon-sm")
            local hp = math.floor((T.px("hit") - hs) / 2)
            help = IconButton:new{ icon = "leaf.mn.info", width = hs, height = hs, padding = hp,
                padding_left = T.px("sp-1"), padding_right = T.px("sp-1"), show_parent = self.show_parent,
                callback = function()
                    local text = item.help_text_func and item.help_text_func(self.menu) or item.help_text
                    if text then UIManager:show(require("ui/widget/infomessage"):new{ text = text }) end
                end }
        end
        local help_w = help and (help:getSize().w + T.px("sp-1")) or 0

        -- lead: radio mark, or an icon tile (.ko-icon-tile: 32px, --r-md, --bg on the white card)
        local lead
        local tile_s = T.px("h-chip")
        if radio then
            local rs = T.px("icon-md")
            lead = IconWidget:new{ icon = checked and "leaf.radio.on" or "leaf.radio.off", width = rs, height = rs, alpha = true, dim = not enabled }
        elseif icons then
            local icon_s = T.px("icon-tile")
            lead = FrameContainer:new{
                bordersize = hair, color = T.color("border"), background = T.color("bg"),
                radius = T.px("r-md"), padding = 0,
                CenterContainer:new{ dimen = Geom:new{ w = tile_s - 2 * hair, h = tile_s - 2 * hair },
                    IconWidget:new{ icon = row_icon(ko_label or label), width = icon_s, height = icon_s, alpha = true, dim = not enabled } },
            }
        end
        local lead_w = lead and (lead:getSize().w + gap) or 0

        local value_widget, value_w = nil, 0
        if value then
            value_widget = TextWidget:new{ text = value, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"),
                max_width = math.floor(w * 0.42) }
            value_w = value_widget:getSize().w + T.px("sp-2")
        end
        local label_w = w - 2 * pad - lead_w - value_w - help_w - (trailing and (trailing_w + T.px("sp-2")) or 0)
        label_w = math.max(label_w, T.px("h-row"))
        local label_widget = TextWidget:new{
            text = label, face = L.face((radio and checked) and "ui-semibold" or "ui", "fs-md"), max_width = label_w,
            fgcolor = T.color(enabled and "text" or "disabled"),
        }
        self.text_truncated = label_widget:isTruncated()
        local label_col = label_widget
        if ko_label then
            label_col = VerticalGroup:new{ align = "left", label_widget,
                TextWidget:new{ text = T_(_("KOReader: %1"), ko_label), face = L.face("ui", "fs-xs"),
                    fgcolor = T.color("text-3"), max_width = label_w } }
        end

        local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad } }
        if lead then
            table.insert(left, lead)
            table.insert(left, HorizontalSpan:new{ width = gap })
        end
        table.insert(left, label_col)
        local right = HorizontalGroup:new{ align = "center" }
        if help then
            table.insert(right, help)
            table.insert(right, HorizontalSpan:new{ width = T.px("sp-1") })
        end
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
        self._leaf_toggle_x = (checkable and not radio) and (w - pad - trailing_w - T.px("sp-2")) or nil
        -- the help button: taps on it show the help, not select the row
        self._leaf_help_x = help and (w - pad - trailing_w - (trailing and T.px("sp-2") or 0) - value_w - help_w) or nil
        self._leaf_help_w = help and help:getSize().w or 0
        self._leaf_help = help
    end, "TouchMenuItem:init")

    -- a tap on the toggle of an item with a checkmark_callback acts on the checkmark only
    L.wrap(TouchMenuItem, "onTapSelect", function(orig, self, arg, ges)
        if self._leaf_help and ges and ges.pos and self.dimen then
            local dx = ges.pos.x - self.dimen.x
            if dx >= self._leaf_help_x - T.px("sp-1") and dx <= self._leaf_help_x + self._leaf_help_w + T.px("sp-1") then
                self._leaf_help.callback()
                return true
            end
        end
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
        local l, v = label_value(item)
        self._leaf_pending = { label = HUMAN[l] or l, value = v }
        local ok, ret = pcall(orig, self, item, tap_on_checkmark)
        self._leaf_pending = nil
        if not ok then error(ret, 0) end
        return ret
    end, "TouchMenu:onMenuSelect")
    local function sync_titles(self)
        self._leaf_titles = self._leaf_titles or {}
        local depth = #(self.item_table_stack or {})
        while #self._leaf_titles > depth do table.remove(self._leaf_titles) end
        while #self._leaf_titles < depth do table.insert(self._leaf_titles, self._leaf_pending or { label = "" }) end
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
            local t = props.display_title or props.title or (rui.document.file or ""):match("([^/]+)$") or ""
            -- "Reading · Animal Farm" (prototype ctxLabel: the title without a trailing "(...)")
            return T_(_("Reading · %1"), (t:gsub("%s*%b()%s*$", "")))
        end
        return _("Library")
    end

    -- the value of the open submenu, as a pill after its title (.mn-value)
    local function value_pill(text)
        local tw = TextWidget:new{ text = text, face = L.face("ui-medium", "fs-xs"), fgcolor = T.color("text-2") }
        local ph = Screen:scaleBySize(22 * T.scale)
        return FrameContainer:new{
            bordersize = hair, color = T.color("border-strong"), background = T.color("surface-2"),
            radius = math.floor(ph / 2), padding = 0, padding_left = T.px("sp-2"), padding_right = T.px("sp-2"),
            CenterContainer:new{ dimen = Geom:new{ w = tw:getSize().w, h = ph - 2 * hair }, tw },
        }
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
        local title, sub, value
        if depth > 0 and titles[#titles] then
            title, value = titles[#titles].label, titles[#titles].value
            -- crumbs: tab › parents (.mn-crumbs)
            local crumbs = { TAB_LABEL[(self.tab_item_table[self.cur_tab] or {}).icon] or "" }
            for i = 1, #titles - 1 do table.insert(crumbs, titles[i].label) end
            sub = table.concat(crumbs, "  ›  ")
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
            -- Quick settings (Leaf sheet) and All settings (the Settings tab), as the prototype head
            table.insert(right, icon_button("leaf.mn.sliders-horizontal", function()
                self:closeMenu()
                UIManager:nextTick(function() require("leaf/system").show_quick() end)
            end))
            for i, tab in ipairs(self.tab_item_table) do
                if tab.icon == "appbar.settings" then
                    table.insert(right, icon_button("leaf.mn.settings", function()
                        if i ~= self.cur_tab then self.bar:switchToTab(i) end
                    end))
                end
            end
        end
        table.insert(right, icon_button("close", function() self:closeMenu() end))
        table.insert(right, HorizontalSpan:new{ width = T.px("sp-3") - btn_pad })
        local text_w = W - left:getSize().w - right:getSize().w - T.px("sp-2")
        local title_row = HorizontalGroup:new{ align = "center" }
        local pill = value and value_pill(value)
        local pill_w = pill and (pill:getSize().w + T.px("sp-1h")) or 0
        table.insert(title_row, TextWidget:new{ text = title, face = L.face("ui-semibold", "fs-head"),
            max_width = math.max(T.px("h-row"), text_w - pill_w) })
        if pill and pill_w < text_w / 2 then
            table.insert(title_row, HorizontalSpan:new{ width = T.px("sp-1h") })
            table.insert(title_row, pill)
        end
        local texts = VerticalGroup:new{ align = "left", title_row }
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

    --- shortcut card at the top of well-known submenus (prototype heroFor: .mn-hero)
    local function hero(self, W)
        local titles = self._leaf_titles or {}
        local depth = #(self.item_table_stack or {})
        if depth ~= 1 or not titles[1] then return end
        local t = tostring(titles[1].label or ""):lower()
        local icon, a, b, cb
        local close_then = function(fn) return function() self:closeMenu() UIManager:nextTick(fn) end end
        if t == _("reading statistics"):lower() or t == "reading statistics" then
            local st
            for _i, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
                local cls = package.loaded[mod]
                if cls and cls.instance and cls.instance.statistics then st = cls.instance.statistics break end
            end
            if not (st and st.onShowReaderProgress) then return end
            icon, a, b = "leaf.mn.chart-column", _("Open reading statistics"), _("This week, calendar and today's timeline")
            cb = close_then(function() st:onShowReaderProgress() end)
        elseif t == _("network"):lower() or t == "network" then
            local NetworkMgr = require("ui/network/manager")
            icon, a = "leaf.mn.wifi", _("Wi-Fi")
            local ok, connected = pcall(function() return NetworkMgr:isConnected() end)
            b = (ok and connected) and _("Connected · networks nearby") or _("Not connected · networks nearby")
            cb = close_then(function()
                if Device:hasWifiToggle() then
                    NetworkMgr:reconnectOrShowNetworkMenu(nil, true)
                else -- (no Wi-Fi hardware, e.g. the desktop emulator: the sheet with what is known)
                    UIManager:show(require("ui/widget/networksetting"):new{
                        network_list = rawget(_G, "LEAF_FAKE_NETWORKS") and LEAF_FAKE_NETWORKS() or {} })
                end
            end)
        elseif t == _("screen"):lower() or t == "screen" then
            if not Device:hasFrontlight() then return end
            icon, a, b = "leaf.mn.sun", _("Frontlight & warmth"), _("Brightness and colour temperature")
            cb = close_then(function() require("leaf/frontlight").show() end)
        elseif t == _("device"):lower() or t == "device" then
            icon, a, b = "leaf.mn.moon-star", _("Sleep screen"), _("What the screen shows while the device sleeps")
            cb = close_then(function() require("leaf/system").show_sleep() end)
        else
            return
        end
        local side = T.px("sp-3")
        local cw = W - 2 * side
        local pad_l, pad_r = T.px("sp-3"), T.px("sp-4")
        local tile_s = T.px("h-chip")
        local tile = FrameContainer:new{ bordersize = hair, color = T.color("accent"), background = T.color("surface"),
            radius = T.px("r-md"), padding = 0,
            CenterContainer:new{ dimen = Geom:new{ w = tile_s - 2 * hair, h = tile_s - 2 * hair },
                IconWidget:new{ icon = icon, width = T.px("icon-tile"), height = T.px("icon-tile"), alpha = true } } }
        local arrow_s = T.px("icon-sm")
        local text_w = cw - 2 * hair - pad_l - pad_r - tile_s - T.px("sp-3") - arrow_s - T.px("sp-3")
        local texts = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = a, face = L.face("ui-semibold", "fs-md"), max_width = text_w },
            VerticalSpan:new{ width = T.px("sp-half") },
            TextWidget:new{ text = b, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"), max_width = text_w } }
        local ih = math.max(tile_s, texts:getSize().h) + 2 * T.px("sp-3")
        local iw = cw - 2 * hair
        local content = OverlapGroup:new{ dimen = Geom:new{ w = iw, h = ih },
            LeftContainer:new{ dimen = Geom:new{ w = iw, h = ih },
                HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad_l }, tile,
                    HorizontalSpan:new{ width = T.px("sp-3") }, texts } },
            RightContainer:new{ dimen = Geom:new{ w = iw, h = ih },
                HorizontalGroup:new{ align = "center",
                    IconWidget:new{ icon = "leaf.mn.arrow-up-right", width = arrow_s, height = arrow_s, alpha = true },
                    HorizontalSpan:new{ width = pad_r } } } }
        local card = FrameContainer:new{ bordersize = hair, color = T.color("accent"), background = T.color("accent-soft"),
            radius = T.px("r-lg"), padding = 0, content }
        local InputContainer = require("ui/widget/container/inputcontainer")
        local tap = InputContainer:new{ dimen = Geom:new{ w = cw, h = ih + 2 * hair }, card }
        tap.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return tap.dimen end } } }
        tap.onTap = function() cb() return true end
        return VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-3") },
            HorizontalGroup:new{ HorizontalSpan:new{ width = side }, tap } }
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

        local depth = #(self.item_table_stack or {})
        self._leaf_icons = depth <= 1
        local top = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = Geom:new{ w = W - 2 * hair, h = T.px("sp-1") }, Grip:new{} },
            VerticalSpan:new{ width = T.px("sp-1") },
            head(self, W - 2 * hair),
        }
        -- tabs on the top level only (a submenu shows its crumbs instead)
        if depth == 0 then table.insert(top, tabs(self, W - 2 * hair)) end
        local card_top = hero(self, W - 2 * hair)
        if card_top then table.insert(top, card_top) end
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
                local inset = T.px("sp-4") + (self._leaf_icons and (T.px("h-chip") + T.px("sp-3")) or 0)
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
