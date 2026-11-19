--[[
    Leaf information and text pages.

    KeyValuePage (Book information list, statistics, battery / system stats, lookup histories)
    -> a Leaf level-2 page (prototype .ko-page + .ko-group + .ko-kv + .ko-pager):
      header:  ‹ title (Inter --fs-head semibold) · KOReader's left icon (if any) · ✕ when ‹ goes back
      body:    KOReader's sections (separator = true, "----" entries) as .ko-group cards; rows
               --h-row, key in --text-2 regular on the left, value in --text medium on the right,
               --hairline separators; a row with a tap action gets a chevron, a customised book
               property a small pencil (KOReader marks them with a private-use glyph).
      footer:  .ko-pager: "Page x of y" (tap: go to page) · ‹ › (hold: first / last page).
    Every KOReader callback stays: tap / hold on rows (callback, hold_callback, "show the full
    value" for truncated rows), swipes, keys, callback_return, close_callback.

    TextViewer (book description "More", notes, CSS / HTML views, lookup results...)
    -> a Leaf text page: --bg page, KOReader's (Leaf) title bar, the text on a .ko-card
       (surface, hairline, --r-lg), Inter (book texts: Literata) at --fs-md scaled by the
       viewer's font-size setting, a thin scrollbar, the button rows on a footer with a hairline.
       Small viewers (a caller's height under 60% of the screen) stay a centred dialog.

    VerticalScrollBar (every scrolling text): thin --border track, --text-3 rounded thumb.

    The paragraph-translate patch panel (koreader/patches/2-paragraph-translate.lua): restyled as a
    Leaf sheet (prototype overlay "translate"), hooked after the patches have loaded.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
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
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

-- KOReader private-use glyphs (U+E000-U+F8FF) in labels: stripped (rule 8)
local function strip_pua(s)
    s = s:gsub("\xEE[\x80-\xBF][\x80-\xBF]", ""):gsub("\xEF[\x80-\xA3][\x80-\xBF]", "")
    return s
end

local function has_pua(s)
    return s:find("\xEE[\x80-\xBF][\x80-\xBF]") or s:find("\xEF[\x80-\xA3][\x80-\xBF]")
end

local function getupvalue(fn, wanted)
    if type(fn) ~= "function" then return end
    local i = 1
    while true do
        local name, value = debug.getupvalue(fn, i)
        if not name then return end
        if name == wanted then return value end
        i = i + 1
    end
end

function M.apply(L)
    local T = L.T
    local IconButton = require("ui/widget/iconbutton")
    local Button = require("ui/widget/button")
    local KeyValuePage = require("ui/widget/keyvaluepage")
    local KeyValueItem = getupvalue(KeyValuePage._populateItems, "KeyValueItem")
        or getupvalue(KeyValuePage.init, "KeyValueItem")
    local hair = T.px("hairline")

    local function icon_button(icon, cb, hold, parent)
        local s = T.px("icon-md")
        local p = math.floor((T.px("hit") - s) / 2)
        return IconButton:new{ icon = icon, width = s, height = s, padding = p, callback = cb,
            hold_callback = hold, show_parent = parent, allow_flash = false }
    end

    ---------------------------------------------------------------- KeyValuePage
    local function clean_key(key)
        key = tostring(key or "")
        local edited = has_pua(key) and true or false
        key = strip_pua(key):gsub("^%s+", ""):gsub("%s*:%s*$", "")
        return key, edited
    end

    if KeyValueItem then
        L.wrap(KeyValueItem, "init", function(orig, self)
            if not self._leaf then return orig(self) end
            self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
            local w, h = self.width, self.height
            local fs = self._leaf_fs or "fs-md"
            local key, edited = clean_key(self.key)
            local tvalue = tostring(self.value or ""):gsub("\n", " · "):gsub("\t", " ")
            local tappable = self.callback ~= nil
            local empty = tvalue == ""

            local gap = T.px("sp-3")
            local s_ic = T.px("icon-sm")
            local trailing = tappable and (T.px("sp-1") + s_ic) or 0
            local edit_w = edited and (T.px("sp-1h") + T.px("icon-xs")) or 0
            local avail = w - trailing - edit_w - (empty and 0 or gap)

            local key_widget = TextWidget:new{ text = key, face = L.face("ui", fs),
                fgcolor = T.color((empty and tappable) and "text" or "text-2"), max_width = avail }
            local value_widget = not empty and TextWidget:new{ text = tvalue, face = L.face("ui-medium", fs),
                fgcolor = T.color("text"), lang = self.value_lang, max_width = avail } or nil
            local kw = key_widget:getWidth()
            local vw = value_widget and value_widget:getWidth() or 0
            if value_widget and kw + vw > avail then
                -- the key keeps its width when it is the short one, else both share the row
                if kw <= avail / 2 then
                    value_widget:setMaxWidth(avail - kw)
                elseif vw <= avail / 2 then
                    key_widget:setMaxWidth(avail - vw)
                else
                    key_widget:setMaxWidth(math.floor(avail / 2))
                    value_widget:setMaxWidth(avail - math.floor(avail / 2))
                end
                self.is_truncated = true
            end

            self.ges_events.Tap = { require("ui/gesturerange"):new{ ges = "tap", range = self.dimen } }
            self.ges_events.Hold = { require("ui/gesturerange"):new{ ges = "hold", range = self.dimen } }

            local left = HorizontalGroup:new{ align = "center", key_widget }
            if edited then
                table.insert(left, HorizontalSpan:new{ width = T.px("sp-1h") })
                table.insert(left, IconWidget:new{ icon = "edit", width = T.px("icon-xs"), height = T.px("icon-xs"), alpha = true, dim = true })
            end
            local right = HorizontalGroup:new{ align = "center" }
            if value_widget then table.insert(right, value_widget) end
            if tappable then
                table.insert(right, HorizontalSpan:new{ width = T.px("sp-1") })
                table.insert(right, IconWidget:new{ icon = "chevron.right", width = s_ic, height = s_ic, alpha = true, dim = true })
            end
            local area = Geom:new{ w = w, h = h }
            self[1] = FrameContainer:new{
                padding = 0, bordersize = 0, focusable = true,
                focus_border_size = require("ui/size").border.thin, focus_inner_border = true,
                OverlapGroup:new{ dimen = area:copy(),
                    LeftContainer:new{ dimen = area:copy(), left },
                    RightContainer:new{ dimen = area:copy(), right },
                },
            }
        end, "KeyValueItem:init")
    else
        L.err("kvpages: KeyValueItem not found, rows keep KOReader's look")
    end

    -- the page frame; KOReader's own widgets (page_info_text, chevrons, return button) are still
    -- created so its methods (and its _populateItems, if Leaf's ever fails) find them
    L.wrap(KeyValuePage, "init", function(orig, self)
        if not KeyValueItem then return orig(self) end
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.show_parent = self.show_parent or self
        self.kv_pairs = self.kv_pairs or {}
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width or W, h = self.height or H }
        if self.dimen.w == W and self.dimen.h == H then self.covers_fullscreen = true end
        local GestureRange = require("ui/gesturerange")
        local Input = Device.input
        if Device:hasKeys() then
            self.key_events.CloseWithKey = { { Input.group.Back } }
            self.key_events.NextPage = { { Input.group.PgFwd } }
            self.key_events.PrevPage = { { Input.group.PgBack } }
        end
        if Device:isTouchDevice() then
            self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
            self.ges_events.MultiSwipe = { GestureRange:new{ ges = "multiswipe", range = self.dimen } }
            self.ges_events.Pan = { GestureRange:new{ ges = "pan", range = self.dimen } }
        end

        -- KOReader's page widgets (kept for its methods)
        local function ko_btn(icon, cb) return Button:new{ icon = icon, callback = cb, bordersize = 0, show_parent = self.show_parent } end
        self.page_return_arrow = self.page_return_arrow or ko_btn("back.top", function() self:onReturn() end)
        self.page_info_left_chev = self.page_info_left_chev or ko_btn("chevron.left", function() self:prevPage() end)
        self.page_info_right_chev = self.page_info_right_chev or ko_btn("chevron.right", function() self:nextPage() end)
        self.page_info_first_chev = self.page_info_first_chev or ko_btn("chevron.first", function() self:goToPage(1) end)
        self.page_info_last_chev = self.page_info_last_chev or ko_btn("chevron.last", function() self:goToPage(self.pages) end)
        self.page_info_text = self.page_info_text or Button:new{
            text = "", _leaf_kind = "caption", bordersize = 0, padding = 0, padding_h = 0,
            background = T.color("bg"),
            hold_input = {
                title = _("Enter page number"), input_type = "number",
                hint_func = function() return string.format("(1 - %s)", self.pages) end,
                callback = function(input)
                    local page = tonumber(input)
                    if page and page >= 1 and page <= self.pages then self:goToPage(page) end
                end,
                ok_text = _("Go to page"),
            },
            call_hold_input_on_tap = true,
            show_parent = self.show_parent,
        }
        self.return_button = HorizontalGroup:new{ self.page_return_arrow }
        self.page_info = HorizontalGroup:new{ self.page_info_first_chev, self.page_info_left_chev,
            self.page_info_text, self.page_info_right_chev, self.page_info_last_chev }
        self.main_content = VerticalGroup:new{}

        -- geometry
        self._leaf_side = T.px("sp-4")
        self._leaf_rowpad = T.px("sp-4")
        self.item_width = self.dimen.w - 2 * self._leaf_side - 2 * hair - 2 * self._leaf_rowpad
        self._leaf_header_h = T.px("h-header")
        self._leaf_pager_h = self.single_page and 0 or (T.px("h-row") + hair)
        self._leaf_gap = T.px("sp-3")
        local available = self.dimen.h - self._leaf_header_h - self._leaf_pager_h - 2 * self._leaf_gap
        self._leaf_available = available

        local n = #self.kv_pairs
        local row_h = T.px("h-row")
        local per
        if self.single_page then
            per = math.max(1, n)
            local need = self:_leafHeight(1, n, row_h)
            if need > available then
                local fixed = need - self:_leafRows(1, n) * row_h
                row_h = math.max(T.px("sp-6"), math.floor((available - fixed) / math.max(1, self:_leafRows(1, n))))
            end
        else
            per = math.max(1, math.floor(available / (row_h + hair)))
            local _land, portrait = KeyValuePage.getCurrentItemsPerPage()
            if G_reader_settings:readSetting("keyvalues_per_page") then per = math.min(per, portrait) end
            while per > 1 do
                local fits = true
                for first = 1, n, per do
                    if self:_leafHeight(first, math.min(n, first + per - 1), row_h) > available then fits = false break end
                end
                if fits then break end
                per = per - 1
            end
        end
        self.items_per_page = per
        self.item_height = row_h
        self._leaf_fs = row_h < T.px("h-row-compact") and "fs-sm" or "fs-md"
        self.items_font_size = T.fs(self._leaf_fs)
        self.pages = math.ceil(n / per)
        self.textviewer_width = W
        self.textviewer_height = H
        self:_populateItems()
    end, "KeyValuePage:init")

    -- number of real rows in [first, last], and the height they take on a page
    function KeyValuePage:_leafRows(first, last)
        local c = 0
        for i = first, last do if type(self.kv_pairs[i]) == "table" then c = c + 1 end end
        return c
    end
    function KeyValuePage:_leafHeight(first, last, row_h)
        local h, groups, in_group = 0, 0, false
        for i = first, last do
            local e = self.kv_pairs[i]
            if type(e) == "table" then
                if not in_group then groups = groups + 1 in_group = true else h = h + hair end
                h = h + row_h
                if e.separator then in_group = false end
            else
                in_group = false
            end
        end
        return h + groups * 2 * hair + math.max(0, groups - 1) * self._leaf_gap
    end

    function KeyValuePage:_leafHeader()
        local W = self.dimen.w
        local hh = self._leaf_header_h
        local back = self.callback_return and function() self:onReturn() end or function() self:onClose() end
        local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = T.px("sp-2") },
            icon_button("chevron.left", back, nil, self.show_parent) }
        local right = HorizontalGroup:new{ align = "center" }
        if self.title_bar_left_icon then
            local ic = self.title_bar_left_icon
            table.insert(right, icon_button(ic, function()
                if self.title_bar_left_icon_tap_callback then self.title_bar_left_icon_tap_callback() end
            end, function()
                if self.title_bar_left_icon_hold_callback then self.title_bar_left_icon_hold_callback() end
            end, self.show_parent))
        end
        if self.callback_return then
            table.insert(right, icon_button("close", function() self:onClose() end, nil, self.show_parent))
        end
        table.insert(right, HorizontalSpan:new{ width = T.px("sp-2") })
        local title_w = W - left:getSize().w - right:getSize().w - T.px("sp-2")
        table.insert(left, TextWidget:new{ text = strip_pua(tostring(self.title or "")), face = L.face("ui-semibold", "fs-head"),
            max_width = title_w })
        left:resetLayout()
        return OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, left },
            RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, right } }
    end

    function KeyValuePage:_leafPager()
        local W = self.dimen.w
        local h = T.px("h-row")
        local text
        if self.pages >= 1 then
            text = T_(_("Page %1 of %2"), self.show_page, self.pages)
        else
            text = _("No items")
        end
        self.page_info_text:setText(text, self.page_info_text.width)
        if self.pages > 1 then self.page_info_text:enable() else self.page_info_text:disableWithoutDimming() end
        local pf = self.page_info_text.frame -- (the caption kind has no fill: sit on the page colour)
        if pf then pf.background = T.color("bg") pf.color = T.color("bg") end
        if self.page_info_text.label_widget then
            self.page_info_text.label_widget.fgcolor = T.color("text-3")
            if self.page_info_text.label_widget.update then self.page_info_text.label_widget:update() end
        end
        local prev = icon_button("chevron.left", function() self:prevPage() end, function() self:goToPage(1) end, self.show_parent)
        local nxt = icon_button("chevron.right", function() self:nextPage() end, function() self:goToPage(self.pages) end, self.show_parent)
        -- disabled ends keep their place but are not drawn: ImageWidget's dim lightens the whole
        -- square (a visible box on --bg / in night mode)
        local function off(b) b.enabled = false b.image.paintTo = function() end end
        if self.show_page <= 1 then off(prev) end
        if self.show_page >= self.pages then off(nxt) end
        local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = T.px("sp-5") }, self.page_info_text }
        local right = HorizontalGroup:new{ align = "center", prev, nxt, HorizontalSpan:new{ width = T.px("sp-3") - T.px("sp-2h") } }
        return VerticalGroup:new{
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") },
            OverlapGroup:new{ dimen = Geom:new{ w = W, h = h },
                LeftContainer:new{ dimen = Geom:new{ w = W, h = h }, left },
                RightContainer:new{ dimen = Geom:new{ w = W, h = h }, right } } }
    end

    L.wrap(KeyValuePage, "_populateItems", function(orig, self)
        if not self._leaf_header_h then return orig(self) end
        local FocusManager = require("ui/widget/focusmanager")
        local W, H = self.dimen.w, self.dimen.h
        self.layout = {}
        self.main_content:clear()
        local per = self.items_per_page
        local first = (self.show_page - 1) * per + 1
        local last = math.min(#self.kv_pairs, first + per - 1)
        local row_w = self.item_width
        local card_w = row_w + 2 * self._leaf_rowpad
        local body = VerticalGroup:new{ align = "left" }
        local card
        local function close_card()
            if card then
                if #body > 0 then table.insert(body, VerticalSpan:new{ width = self._leaf_gap }) end
                table.insert(body, HorizontalGroup:new{ HorizontalSpan:new{ width = self._leaf_side },
                    FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface"),
                        radius = T.px("r-lg"), padding = 0, card } })
                card = nil
            end
        end
        for idx = first, last do
            local entry = self.kv_pairs[idx]
            if type(entry) == "table" then
                if card then
                    table.insert(card, HorizontalGroup:new{ HorizontalSpan:new{ width = self._leaf_rowpad },
                        LineWidget:new{ dimen = Geom:new{ w = card_w - self._leaf_rowpad, h = hair }, background = T.color("border") } })
                else
                    card = VerticalGroup:new{ align = "left" }
                end
                local item = KeyValueItem:new{
                    _leaf = true, _leaf_fs = self._leaf_fs,
                    height = self.item_height, width = row_w,
                    key = entry[1], value = entry[2], value_lang = self.values_lang,
                    callback = entry.callback, hold_callback = entry.hold_callback,
                    textviewer_width = self.textviewer_width, textviewer_height = self.textviewer_height,
                    kv_pairs_idx = idx, kv_page = self, show_parent = self.show_parent,
                }
                table.insert(card, HorizontalGroup:new{ HorizontalSpan:new{ width = self._leaf_rowpad }, item,
                    HorizontalSpan:new{ width = self._leaf_rowpad } })
                table.insert(self.main_content, item)
                table.insert(self.layout, { item })
                if entry.separator then close_card() end
            else
                close_card()
            end
        end
        close_card()

        local parts = VerticalGroup:new{ align = "left", self:_leafHeader(), VerticalSpan:new{ width = self._leaf_gap }, body }
        local page = OverlapGroup:new{ dimen = Geom:new{ w = W, h = H }, allow_mirroring = false, parts }
        if not self.single_page then
            table.insert(page, BottomContainer:new{ dimen = Geom:new{ w = W, h = H }, self:_leafPager() })
        end
        self[1] = FrameContainer:new{ width = W, height = H, padding = 0, margin = 0, bordersize = 0,
            background = T.color("bg"), page }
        pcall(function() self:moveFocusTo(1, 1, bit.bor(FocusManager.FOCUS_ONLY_ON_NT, FocusManager.NOT_UNFOCUS)) end)
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end, "KeyValuePage:_populateItems")

    L.wrap(KeyValuePage, "setTitleBarLeftIcon", function(orig, self, icon)
        if not self._leaf_header_h then return orig(self, icon) end
        self.title_bar_left_icon = icon
        self:_populateItems()
    end, "KeyValuePage:setTitleBarLeftIcon")

    ---------------------------------------------------------------- scroll bar
    local VerticalScrollBar = require("ui/widget/verticalscrollbar")
    local ScrollTextWidget = require("ui/widget/scrolltextwidget")
    ScrollTextWidget.scroll_bar_width = T.px("sp-1")
    ScrollTextWidget.text_scroll_span = T.px("sp-3")
    L.wrap(VerticalScrollBar, "paintTo", function(orig, self, bb, x, y)
        if not self.enable then return end
        self.touch_dimen = Geom:new{ x = x - self.extra_touch_on_side, y = y,
            w = self.width + 2 * self.extra_touch_on_side, h = self.height }
        local w = self.width
        local track = math.max(1, T.px("bw-lg"))
        bb:paintRect(x + math.floor((w - track) / 2), y, track, self.height, T.color("border"))
        local th = math.max(math.floor(self.height * (self.high - self.low)), T.px("sp-6"))
        local ty = y + math.floor(self.low * self.height)
        if ty + th > y + self.height then ty = y + self.height - th end
        bb:paintRoundedRect(x, ty, w, th, T.color("text-3"), math.floor(w / 2))
    end, "VerticalScrollBar:paintTo")

    ---------------------------------------------------------------- TextViewer
    local TextViewer = require("ui/widget/textviewer")
    local fonts = require("leaf/fonts")
    local BOOK_TYPES = { book_info = true, bookmark = true }

    L.wrap(ScrollTextWidget, "init", function(orig, self)
        local tv = self.dialog
        if type(tv) == "table" and tv._leaf_face then self.face = tv._leaf_face end
        return orig(self)
    end, "ScrollTextWidget:init")

    L.wrap(TextViewer, "init", function(orig, self, reinit)
        local W, H = Screen:getWidth(), Screen:getHeight()
        if not reinit then
            self._leaf_page = not (self.height and self.height < H * 0.6)
        end
        local page = self._leaf_page
        if type(self.title) == "string" then self.title = self.title:gsub("%s*:%s*$", "") end
        local text_types = G_reader_settings:readSetting("textviewer_text_types")
        local ts = text_types and text_types[self.text_type] or self.text_types[self.text_type] or {}
        local mono = self.monospace_font
        if mono == nil then mono = ts.monospace_font end
        local size = self.text_font_size or ts.font_size or 20
        local base = mono and 16 or 20
        if not mono then
            local role = BOOK_TYPES[self.text_type] and "book" or "ui"
            self._leaf_face = require("ui/font"):getFace(fonts.FILES[role],
                math.floor(T.fs("fs-md") * size / base + 0.5))
        else
            -- (the fontmap file, not its key: a key would be moved onto the Leaf scale again)
            local Font = require("ui/font")
            self._leaf_face = Font:getFace(Font.fontmap["smallinfont"] or "smallinfont",
                math.floor(T.fs("fs-sm") * size / base + 0.5))
        end
        local foot_extra = 2 * T.px("sp-2") + hair
        if page then
            self.width = W
            self.height = H - foot_extra
        else
            self.height = self.height and (self.height - foot_extra) or nil
        end
        self.text_margin = T.px("sp-4")
        self.text_padding = T.px("sp-4") - hair
        orig(self, reinit)

        -- frame: a Leaf page (or a Leaf dialog for small viewers)
        local f = self.frame
        f.background = T.color(page and "bg" or "surface")
        f.radius = page and 0 or T.px("r-lg")
        f.bordersize = page and 0 or hair
        f.color = T.color("border-strong")
        -- text on a card
        local tw = self.textw
        tw.background = T.color("surface")
        tw.bordersize = hair
        tw.color = T.color("border")
        tw.radius = T.px("r-lg")
        tw.margin = 0 -- (a FrameContainer paints its background over its margin: the centring keeps the gap)
        -- default buttons: human labels instead of arrows
        for _i, id in ipairs({ "top", "bottom" }) do
            local b = self.button_table and self.button_table:getButtonById(id)
            if b and (b.text == "⇱" or b.text == "⇲") then
                b:setText(id == "top" and _("Top") or _("Bottom"), b.width)
            end
        end
        -- footer: hairline + padding around the button rows
        local vg = f[1]
        local bt = vg[#vg]
        vg[#vg] = VerticalGroup:new{
            LineWidget:new{ dimen = Geom:new{ w = self.width, h = hair }, background = T.color("border") },
            FrameContainer:new{ bordersize = 0, padding = 0, padding_top = T.px("sp-2"), padding_bottom = T.px("sp-2"),
                background = T.color(page and "bg-raised" or "surface"), bt },
        }
        vg:resetLayout()
    end, "TextViewer:init")

    ---------------------------------------------------------------- translate patch panel
    UIManager:nextTick(function()
        local ok, err = pcall(M.hook_translate, L)
        if not ok then L.err("kvpages: translate panel not restyled:", err) end
    end)
end

--- the paragraph-translate patch keeps its panel local: reach it through its lookup override
function M.hook_translate(L)
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local Panel = getupvalue(ReaderHighlight.lookupDictWord, "Panel")
    if not Panel then return end
    local ok, tr = pcall(require, "leaf/translate")
    if not ok then return end
    tr.restyle(L, Panel, getupvalue(Panel.build, "translate"),
        getupvalue(Panel.build, "neighbor"), getupvalue(Panel.build, "html_escape"))
end

return M
