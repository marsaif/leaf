--[[
    Leaf reader lists and their menus (prototype "Gaps" group, js/screens/gaps.js): the KOReader
    surfaces around the bookmark list, the in-book search, Go to, the book map / page browser and
    the dictionary popup that the first pass left stock.

      Bookmarks
        * long-press a bookmark or a highlight in the Leaf bookmark sheet (booksheet.lua) -> an action
          sheet (bm-actions): head (tile, "Page 12 · Chapter III", the quote or "Bookmark · Nov 18", ×),
          Go to page · View details · Add/Edit note · [Edit highlighted text · Reset to the original
          text · Style and colour] | Select several… · Remove. Everything is ReaderBookmark's /
          ReaderHighlight's own code (gotoBookmark, setBookmarkNote, editHighlightedText,
          setHighlightedText, removeItem, showHighlightDialog).
        * ReaderBookmark:showBookmarkDetails (KOReader's TextViewer) -> a details sheet (bm-view):
          "2 of 8" · ‹ › (hold: first / last) · ×, chapter eyebrow, date · page · style · colour, the
          quote, the note card; foot: Remove · Edit text · Reset text · Add/Edit note · Go to.
          Same callbacks, confirm and refresh logic as KOReader's viewer (also when opened from
          KOReader's own list behind "Manage…").
        * select mode (bm-select): a sheet of check rows over every bookmark and highlight with All /
          This page / None, Done, Delete notes · n, Remove n (KOReader's deleteItemNote / removeItem).
      Search in book (ReaderSearch)
        * the ◁ ▷ dialog (onShowSearchDialog), the result navigation of "All results"
          (gotoResultsItem) and the "⌛" wait button -> one floating pill (search-nav) above the
          footer: icon buttons with KOReader's callbacks (hold = first / last kept), the query or
          "3 of 41 results" in the middle, a close ×. KOReader still builds its dialogs; this module
          takes their buttons and shows the pill instead.
      Go to: the pinned page row (goto-pin) lives in gotoskim.lua (M.pin_row below builds it).
      Book map / page browser (bookmap.lua)
        * ⋮ -> "Book map options" / "Page browser options" sheets (bookmap-menu, pb-menu): every item
          of KOReader's menus (tap opens the page browser, alternative theme, grid / flat, current /
          initial view, chapter levels, page-slot width, 10-page markers; preload thumbnails,
          columns, rows, page numbers, chapter levels; About; Gestures). Hold ⋮: KOReader's widget.
        * long-press a page thumbnail -> page actions sheet (pb-hold): bookmark, custom chapter,
          hidden flow (ReaderHandMade).
      Dictionary popup (DictQuickLookup)
        * results menu (onShowResultsMenu) -> popover: RESULTS, word / dictionary rows with radios,
          First / Last dictionary, Look up another word…
        * look up a word (lookupInputWord) -> "Look up a word" dialog: the field, a sunken group (Find
          in this definition · Translate · Search Wikipedia · Search with a preset) and Cancel /
          Look up (KOReader's enter default).
        * Wikipedia language (the wiki "Language ≡" button, or a tap on the article title) ->
          popover: WIKIPEDIA LANGUAGE radio rows + Wikipedia languages… (KOReader's language setting).
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local function short_date(dt)
    local y, m, d = tostring(dt or ""):match("^(%d+)-(%d+)-(%d+)")
    if not y then return nil end
    return (MONTHS[tonumber(m)] or m) .. " " .. tonumber(d)
end
M.short_date = short_date

local function cap(s) s = tostring(s or "") return s:sub(1, 1):upper() .. s:sub(2) end
-- highlight styles by their reader-facing names (prototype STYLE)
local STYLE = { lighten = "Highlight", underscore = "Underline", strikeout = "Strikeout", invert = "Invert" }

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local Kit = require("leaf/widgets/kit")
    local geom = K.geom
    local hair = T.px("hairline")
    local function sc(n) return Screen:scaleBySize(n * (T.scale or 1)) end

    ------------------------------------------------------------------ shared bits
    local function chev() return K.icon("chevron.right", "icon-sm") end
    local function value_chev(v)
        return HorizontalGroup:new{ align = "center", K.text(v, "ui", "fs-sm", "text-3"), K.hspan("sp-2"), chev() }
    end
    local function tint(icon, size, color)
        return Kit.TintIcon:new{ icon = icon, size_token = size or "icon-md", color = T.color(color or "text") }
    end
    -- a 44px icon button drawn in a token colour (--text-2, --disabled when off)
    local function icon_tap(icon, enabled, cb, hold, color)
        local hit = T.px("hit")
        return Kit.Tap:new{ width = hit, height = hit, enabled = enabled and true or false,
            content = CenterContainer:new{ dimen = geom(hit, hit), tint(icon, "icon-md", enabled and (color or "text-2") or "disabled") },
            callback = cb, hold_callback = hold }
    end

    -- a .ko-group card of rows (inset hairlines), --sp-4 from the sheet edges
    local function group(rows, W, o)
        o = o or {}
        local gw = o.flush and W or (W - 2 * T.px("sp-4"))
        local inner = gw - 2 * hair
        local built = {}
        for _i, r in ipairs(rows) do
            if r.widget then
                table.insert(built, r.widget)
            else
                local trailing = r.trailing
                if not trailing and r.value then trailing = r.chev and value_chev(r.value) or K.text(r.value, "ui", "fs-sm", "text-3")
                elseif not trailing and r.chev then trailing = chev() end
                table.insert(built, K.row{ width = inner, icon = r.icon, label = r.label, sub = r.sub, trailing = trailing,
                    dim = r.dim, danger = r.danger, pad = T.px("sp-4"), height = r.height,
                    callback = not r.dim and r.callback or nil, hold = not r.dim and r.hold or nil })
            end
        end
        local list = K.list(built, inner, { inset = T.px("sp-4") })
        local card = K.card(gw, list, { flush = true, bg = o.bg })
        if o.flush then return card end
        return HorizontalGroup:new{ K.hspan("sp-4"), card }
    end
    M.group = group

    -- a toggle row inside a group (.ko-row + .ko-toggle)
    local function toggle_row(o)
        local Toggle = require("leaf/widgets/toggle")
        return { icon = o.icon, label = o.label, sub = o.sub, trailing = Toggle:new{ on = o.on }, callback = o.callback }
    end

    -- .ko-sheet-head: [tile] title / sub ··· actions ×
    local function head(o)
        local W = o.width
        local pad = T.px("sp-5")
        local right = HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(o.actions or {}) do table.insert(right, a) end
        if o.close then table.insert(right, Kit.icon_button("close", o.close, o.parent)) end
        table.insert(right, K.hspan("sp-2"))
        local rw = right:getSize().w
        right:resetLayout()
        local left = HorizontalGroup:new{ align = "center", K.hspan(pad) }
        local lead_w = 0
        if o.lead then
            table.insert(left, o.lead)
            table.insert(left, K.hspan("sp-3"))
            lead_w = o.lead:getSize().w + T.px("sp-3")
        end
        local tw = W - pad - lead_w - rw - T.px("sp-2")
        local col = VerticalGroup:new{ align = "left", K.text(o.title, "ui-semibold", "fs-head", "text", tw) }
        if o.sub and o.sub ~= "" then
            table.insert(col, K.vspan("sp-half"))
            table.insert(col, K.text(o.sub, "ui", "fs-sm", "text-3", tw))
        end
        table.insert(left, col)
        local h = math.max(T.px("h-header"), col:getSize().h + 2 * T.px("sp-3"))
        col:resetLayout()
        left:resetLayout()
        local g = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), left },
            RightContainer:new{ dimen = geom(W, h), right } }
        if not o.rule then return g end
        return VerticalGroup:new{ align = "left", g, K.line(W) }
    end
    M.head = head

    -- the 32px icon tile at the start of an action sheet head (.ko-icon-tile)
    local function lead_tile(icon) return K.tile(icon, { icon = "icon-sm", bg = "bg-raised" }) end

    -- a sheet foot: hairline, then left widgets ··· right widgets
    local function foot(W, left, right)
        local h = T.px("h-control") + 2 * T.px("sp-3")
        local lg = HorizontalGroup:new{ align = "center", K.hspan("sp-4") }
        for _i, w in ipairs(left or {}) do table.insert(lg, w) end
        local rg = HorizontalGroup:new{ align = "center" }
        for i, w in ipairs(right or {}) do
            if i > 1 then table.insert(rg, K.hspan("sp-2")) end
            table.insert(rg, w)
        end
        table.insert(rg, K.hspan("sp-4"))
        return VerticalGroup:new{ align = "left", K.line(W),
            OverlapGroup:new{ dimen = geom(W, h),
                LeftContainer:new{ dimen = geom(W, h), lg },
                RightContainer:new{ dimen = geom(W, h), rg } } }
    end

    ------------------------------------------------------------------ Sheet: a Leaf bottom sheet
    -- subclasses implement :content(inner_width) -> a VerticalGroup (under the grip)
    local Sheet = InputContainer:extend{ _leaf_wants_scrim = true, width = nil }
    function Sheet:init()
        self.dimen = geom(Screen:getWidth(), Screen:getHeight())
        self.ges_events = {
            TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } },
            SwipeSheet = { GestureRange:new{ ges = "swipe", range = self.dimen } },
        }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end
    function Sheet:build()
        local W = self.width or Screen:getWidth()
        local frame, container = Kit.sheet{ width = W, content = self:content(Kit.inner(W)) }
        self._frame = frame
        self[1] = container
    end
    function Sheet:refresh()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function Sheet:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then self:onClose() end
        return true
    end
    function Sheet:onSwipeSheet(arg, ges)
        if ges.direction == "south" then self:onClose() return true end
        if self.onSwipeLR and (ges.direction == "west" or ges.direction == "east") then
            self:onSwipeLR(ges.direction == "west" and 1 or -1)
        end
        return true
    end
    function Sheet:onClose()
        UIManager:close(self)
        if self.close_callback then self.close_callback() end
        return true
    end
    function Sheet:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function Sheet:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end
    M.Sheet = Sheet

    ------------------------------------------------------------------ Popover: anchored, no scrim
    -- {x, y (top) or bottom, width, build = function(inner) -> VerticalGroup }
    local Popover = InputContainer:extend{}
    function Popover:init()
        self.dimen = geom(Screen:getWidth(), Screen:getHeight())
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        local W = self.width
        local content = self.build(W - 2 * hair)
        local frame = FrameContainer:new{ bordersize = hair, color = T.color("border-strong"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = 0, padding_top = T.px("sp-1h"), padding_bottom = T.px("sp-1h"),
            VerticalGroup:new{ align = "left", HorizontalSpan:new{ width = W - 2 * hair }, content } }
        local sz = frame:getSize()
        local SW, SH = Screen:getWidth(), Screen:getHeight()
        local m = T.px("sp-2")
        local y = self.y or (SH - (self.bottom or m) - sz.h)
        y = math.max(m, math.min(y, SH - m - sz.h))
        local x = math.max(m, math.min(self.x or m, SW - m - sz.w))
        self._frame = frame
        self[1] = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = y },
            HorizontalGroup:new{ HorizontalSpan:new{ width = x }, frame } }
    end
    function Popover:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then self:onClose() end
        return true
    end
    function Popover:onClose()
        UIManager:close(self)
        if self.close_callback then self.close_callback() end
        return true
    end
    function Popover:onShow() UIManager:setDirty(self, "ui") return true end
    function Popover:onCloseWidget() UIManager:setDirty(nil, "ui") end
    M.Popover = Popover

    -- popover rows (44px)
    local function pop_label(text, W)
        local h = T.px("h-control")
        return LeftContainer:new{ dimen = geom(W, h - T.px("sp-1")), HorizontalGroup:new{ K.hspan("sp-4"),
            K.text(text:upper(), "ui-semibold", "fs-xs", "text-3") } }
    end
    local function pop_row(W, o)
        local trailing
        if o.radio ~= nil then
            trailing = K.icon(o.radio and "leaf.radio.on" or "leaf.radio.off", "icon-md")
        end
        return K.row{ width = W, icon = o.icon, label = o.label, sub = o.sub, trailing = trailing, pad = T.px("sp-4"),
            height = T.px("h-row-compact"), callback = o.callback, hold = o.hold }
    end
    local function pop_divider(W)
        return VerticalGroup:new{ K.vspan("sp-1"), K.line(W), K.vspan("sp-1") }
    end

    ------------------------------------------------------------------ bookmarks
    local function ann_index(ui, item)
        local list = ui.annotation.annotations
        for i, a in ipairs(list) do if a == item then return i end end
        return ui.annotation:getItemIndex(item)
    end
    local function page_of(ui, item)
        if item.pageno then return item.pageno end
        if ui.rolling and type(item.page) == "string" then return ui.document:getPageFromXPointer(item.page) end
        return item.page
    end
    local function page_str(ui, item)
        local ok, s = pcall(function() return ui.bookmark:getBookmarkPageString(item.page) end)
        return ok and s or tostring(page_of(ui, item))
    end
    local function chapter_of(ui, item)
        local c = item.chapter
        if not c or c == "" then
            local p = page_of(ui, item)
            c = p and ui.toc and ui.toc:getTocTitleByPage(p) or ""
        end
        return c or ""
    end
    local function chapter_label(c)
        local bs = package.loaded["leaf/booksheet"]
        if bs and bs.split_title then
            local lbl, ttl = bs.split_title(c)
            return lbl or ttl or c, ttl
        end
        return c
    end
    local function item_text(ui, item, n)
        local t = item.drawer and (item.text_orig or item.text) or nil
        if not t then
            local doc = ui.document
            if doc.getTextFromXPointer and type(item.page) == "string" then
                pcall(function() t = doc:getTextFromXPointer(item.page) end)
            end
            if t and n and #t > n then t = t:sub(1, n):gsub("[\128-\191]*$", ""):gsub("%s+%S*$", "") .. "…" end
        end
        return t and t:gsub("%s+", " ") or ""
    end

    local function notify(text)
        local N = require("ui/widget/notification")
        N:notify(text, N.SOURCE_ALWAYS_SHOW)
    end

    -- bm-actions -----------------------------------------------------
    local BmActions = Sheet:extend{}
    function BmActions:content(W)
        local ui, item = self.ui, self.item
        local hl = item.drawer ~= nil
        local idx = function() return ann_index(ui, item) end
        local pg = page_str(ui, item)
        local lbl = chapter_label(chapter_of(ui, item))
        local after = function() if self.on_change then self.on_change() end end
        local function close_then(fn) return function() self:onClose() fn() end end
        local g1 = {
            { icon = "leaf.gl.arrow", label = T_(_("Go to page %1"), pg), callback = close_then(function()
                if ui.link then ui.link:addCurrentLocationToStack() end
                ui.bookmark:gotoBookmark(item.page, item.pos0)
            end) },
            { icon = "leaf.gl.panel", label = _("View details"), callback = close_then(function()
                ui.bookmark:showBookmarkDetails(idx())
            end) },
            { icon = "leaf.gl.note", label = item.note and _("Edit note") or _("Add note"), callback = close_then(function()
                ui.bookmark:setBookmarkNote(idx(), nil, nil, after)
            end) },
        }
        if hl then
            table.insert(g1, { icon = "leaf.gl.textcursor", label = _("Edit highlighted text"), sub = _("Fix OCR or hyphenation mistakes"),
                callback = close_then(function() ui.bookmark:editHighlightedText(idx(), after) end) })
            table.insert(g1, { icon = "leaf.gl.reset", label = _("Reset to the original text"), dim = not item.text_edited,
                callback = close_then(function() ui.bookmark:setHighlightedText(idx(), nil, after) end) })
            local style = _(STYLE[item.drawer] or cap(item.drawer))
            local color = item.color and ui.highlight:getHighlightColorString(item.color) or nil
            table.insert(g1, { icon = "leaf.gl.palette", label = _("Style and colour"),
                value = color and (style .. " · " .. color) or style, chev = true,
                callback = close_then(function()
                    -- the highlight popover is anchored on the page: show the highlight first
                    ui.bookmark:gotoBookmark(item.page, item.pos0)
                    UIManager:nextTick(function() ui.highlight:showHighlightDialog(idx()) end)
                end) })
        end
        local g2 = {
            { icon = "leaf.gl.listchecks", label = _("Select several…"), callback = close_then(function()
                M.show_select(ui, { [idx()] = true })
            end) },
            { icon = "leaf.gl.trash", label = hl and _("Remove highlight") or _("Remove bookmark"), danger = true,
                callback = close_then(function()
                    ui.bookmark:removeItem(item)
                    after()
                    notify(hl and _("Highlight removed") or _("Bookmark removed"))
                end) },
        }
        local sub = hl and ("“" .. item_text(ui, item) .. "”") or (_("Bookmark") .. (short_date(item.datetime) and (" · " .. short_date(item.datetime)) or ""))
        return VerticalGroup:new{ align = "left",
            head{ width = W, lead = lead_tile(hl and "leaf.gl.highlighter" or "leaf.gl.bookmark"),
                title = T_(_("Page %1"), pg) .. (lbl ~= "" and (" · " .. lbl) or ""), sub = sub, close = function() self:onClose() end,
                parent = self, rule = true },
            K.vspan("sp-2"), group(g1, W), K.vspan("sp-3"), group(g2, W), K.vspan("sp-1") }
    end

    -- long-press on a bookmark / highlight row of the bookmark sheet
    function M.show_actions(ui, item, on_change)
        UIManager:show(BmActions:new{ ui = ui, item = item, on_change = on_change })
    end

    -- bm-view ---------------------------------------------------------
    local BmView = Sheet:extend{}
    function BmView:content(W)
        local ui, item, o = self.ui, self.item, self.o
        local hl = item.drawer ~= nil
        local pad = T.px("sp-5")
        local cw = W - 2 * pad
        local nav = {
            icon_tap("leaf.gl.prev", o.idx > 1, function() o.show(o.idx - 1) end, function() o.show(1) end),
            icon_tap("leaf.gl.next", o.idx < o.n, function() o.show(o.idx + 1) end, function() o.show(o.n) end),
        }
        local ch = chapter_of(ui, item)
        local meta = { short_date(item.datetime), T_(_("Page %1"), page_str(ui, item)) }
        if hl then
            table.insert(meta, _(STYLE[item.drawer] or cap(item.drawer)))
            if item.color then table.insert(meta, ui.highlight:getHighlightColorString(item.color)) end
        else
            table.insert(meta, _("Page bookmark"))
        end
        local metas = {}
        for _i, m in ipairs(meta) do if m and m ~= "" then table.insert(metas, m) end end
        local quote = item_text(ui, item, 140)
        local qw = cw - T.px("bw-lg") - T.px("sp-3")
        local qbox = TextBoxWidget:new{ text = quote, face = L.face("book", "fs-md"), width = qw, fgcolor = T.color("text"),
            bgcolor = T.color("bg-raised"), height = sc(110), height_adjust = true, height_overflow_show_ellipsis = true }
        local qh = qbox:getSize().h
        local quote_w = HorizontalGroup:new{ align = "top",
            LineWidget:new{ dimen = geom(T.px("bw-lg"), qh), background = T.color("border-strong") },
            K.hspan("sp-3"), qbox }
        local note = item.note and item.note ~= ""
        local nw = cw - 2 * T.px("sp-3") - T.px("icon-sm") - T.px("sp-2")
        local note_text = note and TextBoxWidget:new{ text = item.note, face = L.face("ui", "fs-md"), width = nw,
                fgcolor = T.color("text"), bgcolor = T.color("surface-2"), height = sc(80), height_adjust = true,
                height_overflow_show_ellipsis = true }
            or K.text(_("No note yet"), "ui", "fs-md", "text-3")
        local note_card = FrameContainer:new{ bordersize = 0, background = T.color("surface-2"), radius = T.px("r-md"),
            padding = T.px("sp-3"), width = cw,
            HorizontalGroup:new{ align = "top", VerticalGroup:new{ K.vspan("sp-half"), tint("leaf.gl.penline", "icon-sm", "text-2") },
                K.hspan("sp-2"), note_text } }
        local body = VerticalGroup:new{ align = "left",
            K.text(ch:upper(), "ui-semibold", "fs-xs", "text-3", cw), K.vspan("sp-1h"),
            HorizontalGroup:new{ align = "center", tint(hl and "leaf.gl.highlighter" or "leaf.gl.bookmark", "icon-xs", "text-3"),
                K.hspan("sp-1h"), K.text(table.concat(metas, " · "), "ui", "fs-xs", "text-3", cw - T.px("icon-xs")) },
            K.vspan("sp-3"), HorizontalGroup:new{ K.hspan("sp-3"), quote_w }, K.vspan("sp-3"), note_card, K.vspan("sp-3") }
        local left = { icon_tap("leaf.gl.trash", o.remove ~= nil, o.remove) }
        if hl then
            table.insert(left, icon_tap("leaf.gl.textcursor", o.edit_text ~= nil, o.edit_text))
            table.insert(left, icon_tap("leaf.gl.reset", o.reset_text ~= nil, o.reset_text))
        end
        local right = {
            Kit.button{ label = note and _("Edit note") or _("Add note"), kind = "secondary", parent = self, enabled = o.note ~= nil,
                callback = o.note },
            Kit.button{ label = _("Go to"), kind = "primary", parent = self, enabled = o.go ~= nil, callback = o.go },
        }
        return VerticalGroup:new{ align = "left",
            head{ width = W, title = T_(_("%1 of %2"), o.idx, o.n), sub = hl and _("Highlight") or _("Bookmark"),
                actions = nav, close = function() self:onClose() end, parent = self },
            HorizontalGroup:new{ K.hspan(pad), body },
            foot(W, left, right) }
    end
    function BmView:onSwipeLR(d) self.o.show(self.o.idx + d) end

    -- select mode ------------------------------------------------------
    local BmSelect = Sheet:extend{ page = 1 }
    function BmSelect:content(W)
        local ui = self.ui
        local list = ui.annotation.annotations
        self.sel = self.sel or {}
        local n, notes = 0, 0
        for i, a in ipairs(list) do
            if self.sel[i] then
                n = n + 1
                if a.note and a.note ~= "" then notes = notes + 1 end
            end
        end
        local function link(label, cb)
            return K.tap(CenterContainer:new{ dimen = geom(K.text(label, "ui-medium", "fs-sm"):getSize().w + 2 * T.px("sp-2"), T.px("hit")),
                K.text(label, "ui-medium", "fs-sm", "text-2") }, cb)
        end
        local cur = ui:getCurrentPage()
        local hd = head{ width = W, title = n > 0 and T_(_("%1 selected"), n) or _("None selected"),
            sub = T_(_("Bookmarks & highlights · %1"), #list), parent = self, close = function() self:onClose() end,
            actions = {
                link(_("All"), function() for i = 1, #list do self.sel[i] = true end self:refresh() end),
                link(_("This page"), function()
                    self.sel = {}
                    for i, a in ipairs(list) do if page_of(ui, a) == cur then self.sel[i] = true end end
                    self:refresh()
                end),
                link(_("None"), function() self.sel = {} self:refresh() end),
            } }
        -- rows (paged when they don't fit)
        local row_h = T.px("h-row") + T.px("sp-2")
        local per = math.max(3, math.floor((Screen:getHeight() * 0.72 - 2 * T.px("h-header")) / (row_h + hair)))
        local pages = math.max(1, math.ceil(#list / per))
        self.page = math.max(1, math.min(self.page, pages))
        self._pages = pages
        local rows = VerticalGroup:new{ align = "left" }
        local pad = T.px("sp-5")
        for i = (self.page - 1) * per + 1, math.min(#list, self.page * per) do
            local a = list[i]
            local on = self.sel[i] and true or false
            local p = page_str(ui, a)
            local label = a.drawer and ("“" .. item_text(ui, a) .. "”") or T_(_("Page %1 bookmark"), p)
            local bits = { T_(_("Page %1"), p) }
            if short_date(a.datetime) then table.insert(bits, short_date(a.datetime)) end
            if a.note and a.note ~= "" then table.insert(bits, _("note")) end
            local r = K.row{ width = W, icon = a.drawer and "leaf.gl.highlighter" or "leaf.gl.bookmark", label = label,
                sub = table.concat(bits, " · "), trailing = K.icon(on and "leaf.check.on" or "leaf.check.off", "icon-md"),
                height = row_h, pad = pad,
                callback = function() self.sel[i] = not self.sel[i] or nil self:refresh() end }
            if #rows > 0 then
                table.insert(rows, HorizontalGroup:new{ K.hspan(pad + T.px("icon-md") + T.px("sp-3")),
                    K.line(W - pad - T.px("icon-md") - T.px("sp-3")) })
            end
            if on then
                table.insert(rows, FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("surface-2"), r })
            else
                table.insert(rows, r)
            end
        end
        local left = { Kit.button{ label = _("Done"), kind = "ghost", parent = self, callback = function() self:onClose() end } }
        if pages > 1 then
            table.insert(left, Kit.icon_button("chevron.left", function() self:onSwipeLR(-1) end, self, "icon-sm"))
            table.insert(left, K.text(T_("%1 / %2", self.page, pages), "ui", "fs-sm", "text-3"))
            table.insert(left, Kit.icon_button("chevron.right", function() self:onSwipeLR(1) end, self, "icon-sm"))
        end
        local ConfirmBox = require("ui/widget/confirmbox")
        local right = {
            Kit.button{ label = notes > 0 and T_(_("Delete notes · %1"), notes) or _("Delete notes"), kind = "secondary",
                parent = self, enabled = notes > 0, callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Delete the notes of the selected items?") .. "\n" .. _("The highlights stay; only their notes are removed."),
                        ok_text = _("Delete"), ok_callback = function()
                            for i, a in ipairs(list) do
                                if self.sel[i] and a.note then ui.bookmark:deleteItemNote(a) end
                            end
                            self:refresh()
                        end })
                end },
            Kit.button{ label = n > 0 and T_(_("Remove %1"), n) or _("Remove"), kind = "danger", parent = self,
                enabled = n > 0, callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = T_(_("Remove %1 selected items?"), n) .. "\n" .. _("Bookmarks, highlights and their notes are deleted."),
                        ok_text = _("Remove"), ok_callback = function()
                            for i = #list, 1, -1 do
                                if self.sel[i] then ui.bookmark:removeItem(list[i], i) end
                            end
                            self.sel = {}
                            self:refresh()
                        end })
                end },
        }
        return VerticalGroup:new{ align = "left", hd, K.line(W), rows, foot(W, left, right) }
    end
    function BmSelect:onSwipeLR(d)
        local p = math.max(1, math.min(self._pages or 1, self.page + d))
        if p ~= self.page then self.page = p self:refresh() end
    end
    function M.show_select(ui, sel)
        UIManager:show(BmSelect:new{ ui = ui, sel = sel or {} })
    end

    local ReaderBookmark = require("apps/reader/modules/readerbookmark")
    L.wrap(ReaderBookmark, "showBookmarkDetails", function(orig, self, item_or_index)
        if not Device:isTouchDevice() then return orig(self, item_or_index) end
        local item_table, item, item_idx
        local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
        if bm_menu then
            item_table = bm_menu.item_table
            item = item_or_index
            item_idx = item.idx
        else
            item_table = self.ui.annotation.annotations
            item_idx = item_or_index
            item = item_table[item_idx]
        end
        if not item then return orig(self, item_or_index) end
        local items_nb = #item_table
        local not_select_mode = not (bm_menu and bm_menu.select_count) and not self.ui.highlight.select_mode
        local view
        local function show(idx)
            if idx < 1 or idx > items_nb or idx == item_idx then return end
            UIManager:close(view)
            if bm_menu then
                self:updateBookmarkList(nil, idx)
                self:showBookmarkDetails(item_table[idx])
            else
                self:showBookmarkDetails(idx)
            end
        end
        local function edit_details_callback()
            self.details_updated = true
            UIManager:close(view)
            self:showBookmarkDetails(item_or_index)
        end
        local function close_callback()
            if self.details_updated then
                self.details_updated = nil
                if bm_menu then
                    if self.show_edited_only then
                        for i = items_nb, 1, -1 do
                            if not item_table[i].text_edited then table.remove(item_table, i) end
                        end
                    end
                    self:updateBookmarkList(item_table, -1)
                elseif self.view.highlight.note_mark then
                    UIManager:setDirty(self.dialog, "ui")
                end
            end
        end
        -- the raw annotation (bm_menu items carry formatted text)
        local raw = bm_menu and (self.ui.annotation.annotations[self:getBookmarkItemIndex(item)] or item) or item
        local shown = setmetatable({ text = raw.text, text_orig = raw.text }, { __index = item })
        local o = { idx = item_idx, n = items_nb, show = show }
        if not_select_mode then
            o.remove = function()
                UIManager:show(require("ui/widget/confirmbox"):new{
                    text = _("Remove this bookmark?"), ok_text = _("Remove"),
                    ok_callback = function()
                        UIManager:close(view)
                        self:removeItem(item, not bm_menu and item_idx)
                        if bm_menu then
                            table.remove(item_table, item_idx)
                            self:updateBookmarkList(item_table, -1)
                        end
                    end })
            end
            o.note = function() self:setBookmarkNote(item_or_index, nil, nil, edit_details_callback) end
            if item.drawer then o.edit_text = function() self:editHighlightedText(item_or_index, edit_details_callback) end end
            if item.text_edited then o.reset_text = function() self:setHighlightedText(item_or_index, nil, edit_details_callback) end end
        end
        if not (bm_menu and bm_menu.select_count) then
            o.go = function()
                UIManager:close(view)
                self.ui.link:addCurrentLocationToStack()
                self:gotoBookmark(item.page, item.pos0)
                if bm_menu then bm_menu.close_callback() end
            end
        end
        view = BmView:new{ ui = self.ui, item = shown, o = o, close_callback = close_callback }
        UIManager:show(view)
        return true
    end, "ReaderBookmark:showBookmarkDetails")

    ------------------------------------------------------------------ search bar (floating pill)
    local Pill = InputContainer:extend{}
    function Pill:init()
        self.dimen = geom(Screen:getWidth(), Screen:getHeight())
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        -- ButtonDialog API used by ReaderSearch's closures
        self.movable = { getMovedOffset = function() return Geom:new{ x = 0, y = 0 } end, setMovedOffset = function() end }
        self:build()
    end
    function Pill:build()
        local g = HorizontalGroup:new{ align = "center", K.hspan("sp-1") }
        for _i, w in ipairs(self.items(self)) do table.insert(g, w) end
        table.insert(g, K.hspan("sp-1"))
        local frame = FrameContainer:new{ bordersize = hair, color = T.color("border-strong"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = 0, padding_top = T.px("sp-half"), padding_bottom = T.px("sp-half"), g }
        local SW, SH = Screen:getWidth(), Screen:getHeight()
        -- above the status bar: like the prototype's .gp-float
        local bottom = sc(56)
        self._frame = frame
        self[1] = BottomContainer:new{ dimen = geom(SW, SH - bottom), CenterContainer:new{ dimen = geom(SW, frame:getSize().h), frame } }
    end
    function Pill:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then
            UIManager:close(self)
            if self.tap_close_callback then self.tap_close_callback() end
        end
        return not self.pass_through
    end
    function Pill:onClose()
        UIManager:close(self)
        return true
    end
    function Pill:onShow() UIManager:setDirty(self, "ui") return true end
    function Pill:onCloseWidget() UIManager:setDirty(nil, "ui", self._frame and self._frame.dimen) end
    M.Pill = Pill

    local function sep()
        return HorizontalGroup:new{ align = "center", K.hspan("sp-1"),
            LineWidget:new{ dimen = geom(hair, T.px("icon-lg")), background = T.color("border") }, K.hspan("sp-1") }
    end
    local function ibtn(icon, b, parent)
        local enabled = b and b.enabled ~= false and (not b.enabled_func or b.enabled_func())
        local hit = T.px("hit")
        return Kit.Tap:new{ width = hit, height = hit, enabled = enabled and true or false,
            content = CenterContainer:new{ dimen = geom(hit, hit), tint(icon, "icon-md", enabled and "text-2" or "disabled") },
            callback = b and b.callback, hold_callback = b and b.hold_callback }
    end
    local function midtext(widget, cb)
        local sz = widget:getSize()
        local w = sz.w + 2 * T.px("sp-3")
        return Kit.Tap:new{ width = w, height = T.px("hit"), content = CenterContainer:new{ dimen = geom(w, T.px("hit")), widget }, callback = cb }
    end

    -- the ButtonDialog that ReaderSearch just showed on top, if any
    local function top_dialog()
        local stack = UIManager._window_stack
        local top = stack[#stack] and stack[#stack].widget
        if top and type(top.buttons) == "table" and top.buttons[1] then return top end
    end
    local function close_btn(pill_ref, rs)
        return ibtn("leaf.gl.close", { callback = function()
            UIManager:close(pill_ref())
            rs:restorePageView()
        end })
    end

    local ReaderSearch = require("apps/reader/modules/readersearch")
    -- result navigation: ↺ ‹ "3 / 41" › 🔍
    L.wrap(ReaderSearch, "gotoResultsItem", function(orig, self, index)
        orig(self, index)
        if not Device:isTouchDevice() then return end
        local d = top_dialog()
        if not d then return end
        local b = d.buttons[1]
        if not (b and #b == 5) then return end
        UIManager:close(d)
        local n = #self.result_menu.item_table
        local pill
        pill = Pill:new{ tap_close_callback = d.tap_close_callback, items = function(p)
            return {
                ibtn("leaf.gl.undo", { callback = function() UIManager:close(p) self:onGoToStartPage() self:restorePageView() end }),
                sep(),
                ibtn("leaf.gl.prev", { enabled = b[2].enabled, callback = function() UIManager:close(p) self:gotoResultsItem(index - 1) end,
                    hold_callback = function() UIManager:close(p) self:gotoResultsItem(1) end }),
                midtext(HorizontalGroup:new{ align = "center", K.text(T_(_("%1 of %2"), index, n), "ui-medium", "fs-md", "text"),
                    K.hspan("sp-1h"), K.text(_("results"), "ui", "fs-xs", "text-3") }, function()
                    UIManager:close(p)
                    self.findall_results_item_index = index
                    self:onShowFindAllResults()
                end),
                ibtn("leaf.gl.next", { enabled = b[4].enabled, callback = function() UIManager:close(p) self:gotoResultsItem(index + 1) end,
                    hold_callback = function() UIManager:close(p) self:gotoResultsItem(n) end }),
                sep(),
                ibtn("leaf.gl.search", { callback = function() UIManager:close(p) self:onShowFulltextSearchInput() end }),
                close_btn(function() return pill end, self),
            }
        end }
        UIManager:show(pill)
    end, "ReaderSearch:gotoResultsItem")

    -- the "⌛" wait button -> "Searching for “x”…  Cancel"
    function M.wait_pill(text)
        local pill
        pill = Pill:new{ items = function(p)
            return {
                K.hspan("sp-2"), tint("leaf.gl.loader", "icon-md", "text-2"), K.hspan("sp-2"),
                K.text(T_(_("Searching for “%1”…"), text or ""), "ui", "fs-sm", "text-2", sc(200)), K.hspan("sp-2"),
                Kit.button{ label = _("Cancel"), kind = "secondary", parent = p, callback = function() UIManager:close(p) end },
                K.hspan("sp-1"),
            }
        end }
        return pill
    end

    -- the ◁ ▷ dialog: |◁ ◁ 🔍 query ▷ ▷| ×
    L.wrap(ReaderSearch, "onShowSearchDialog", function(orig, self, text, direction, search_type, case_insensitive)
        local res = orig(self, text, direction, search_type, case_insensitive)
        if not Device:isTouchDevice() then return res end
        local d = self.search_dialog
        local b = d and d.buttons and d.buttons[1]
        if not (b and #b == 5) then return res end
        local stack = UIManager._window_stack
        local shown_d, shown_w
        for _i, w in ipairs(stack) do
            if w.widget == d then shown_d = true end
            if w.widget == self.wait_button then shown_w = true end
        end
        local wait = M.wait_pill(text)
        local old_wait = self.wait_button
        self.wait_button = wait
        if shown_w then
            UIManager:close(old_wait)
            UIManager:show(wait)
        end
        local pill
        pill = Pill:new{ tap_close_callback = d.tap_close_callback, pass_through = false, items = function()
            return {
                ibtn("leaf.gl.first", b[1]), ibtn("leaf.gl.prev", b[2]),
                midtext(HorizontalGroup:new{ align = "center", tint("leaf.gl.search", "icon-sm", "text-2"), K.hspan("sp-1h"),
                    K.text(text or "", "ui", "fs-md", "text", sc(140)) }, b[3].callback),
                ibtn("leaf.gl.next", b[4]), ibtn("leaf.gl.last", b[5]),
                sep(),
                close_btn(function() return pill end, self),
            }
        end }
        self.search_dialog = pill
        if shown_d then
            UIManager:close(d)
            UIManager:show(pill)
        end
        return res
    end, "ReaderSearch:onShowSearchDialog")

    ------------------------------------------------------------------ Go to: the pinned page row
    -- (used by gotoskim.lua's Go to sheet) inner = sheet content width; close = closes the sheet
    function M.pin_row(ui, inner, close)
        local gp = ui.gotopage
        local pinned
        pcall(function() if ui.doc_settings:has("pinned_page") then pinned = gp:getPinnedPageNumber() end end)
        local pad = T.px("sp-4")
        local h = T.px("h-control") + T.px("sp-3")
        local left = HorizontalGroup:new{ align = "center", K.hspan(pad), tint("leaf.gl.pin", "icon-xs", "text-3"), K.hspan("sp-1"),
            K.text(_("Pinned page"):upper(), "ui-semibold", "fs-2xs", "text-3") }
        local right = HorizontalGroup:new{ align = "center" }
        if pinned then
            table.insert(right, K.chip{ label = T_(_("Go to page %1"), pinned), icon = "leaf.gl.goto", callback = function()
                close()
                gp:onGoToPinnedPage()
            end })
            table.insert(right, K.hspan("sp-2"))
        end
        table.insert(right, K.chip{ label = pinned and _("Pin this page instead") or _("Pin this page"), icon = "leaf.gl.pin",
            callback = function()
                close()
                gp:onPinPage()
            end })
        if pinned then
            local hit = T.px("hit")
            table.insert(right, Kit.Tap:new{ width = sc(32), height = hit,
                content = CenterContainer:new{ dimen = geom(sc(32), hit), tint("leaf.gl.pinoff", "icon-sm", "text-2") },
                callback = function()
                    UIManager:show(require("ui/widget/confirmbox"):new{
                        text = _("Remove the pinned page?") .. "\n" .. T_(_("Page %1 stays as it is; only the pin is removed."), pinned),
                        ok_text = _("Remove"), ok_callback = function()
                            close()
                            gp:onPinPage(nil, true)
                        end })
                end })
        else
            table.insert(right, K.hspan("sp-2"))
        end
        table.insert(right, K.hspan("sp-1"))
        return OverlapGroup:new{ dimen = geom(inner, h),
            LeftContainer:new{ dimen = geom(inner, h), left },
            RightContainer:new{ dimen = geom(inner, h), right } }
    end

    ------------------------------------------------------------------ book map / page browser options
    local function seg_row(W, label, items, selected, on_select)
        local LeafSeg = require("leaf/widgets/seg")
        local h = T.px("h-row")
        local pad = T.px("sp-5")
        -- sized to its labels (.ko-seg--sm), not stretched
        local sw = 2 * T.px("sp-1")
        for _i, it in ipairs(items) do sw = sw + K.text(it.label, "ui-semibold", "fs-sm"):getSize().w + 2 * T.px("sp-3") end
        local seg = LeafSeg:new{ width = sw, items = items, selected = selected, on_select = on_select }
        return OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ K.hspan(pad), K.text(label, "ui", "fs-md") } },
            RightContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", seg, K.hspan(pad) } } }
    end
    local function info(title, text)
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = text })
    end

    local MapOptions = Sheet:extend{}
    function MapOptions:content(W)
        local ui = self.ui
        local BookMapWidget = require("ui/widget/bookmapwidget")
        local bmw = self.bmw
        if not bmw then
            bmw = BookMapWidget:new{ ui = ui }
            self.bmw = bmw
        end
        local function upd() self.changed = true self:refresh() end
        local tap_pb = G_reader_settings:nilOrTrue("book_map_tap_to_page_browser")
        local alt = G_reader_settings:isTrue("book_map_alt_theme")
        local initial = not bmw.flat_map and bmw.toc_depth == bmw.max_toc_depth and bmw.pages_per_row == bmw.fit_pages_per_row
        local has_toc = (bmw.max_toc_depth or 0) > 0
        local g1 = group({
            toggle_row{ icon = "leaf.gl.grid", label = _("Tapping a page opens the page browser"), on = tap_pb, callback = function()
                G_reader_settings:flipNilOrTrue("book_map_tap_to_page_browser") upd() end },
            toggle_row{ icon = "leaf.gl.contrast", label = _("Alternative look"), sub = _("Outlined cells instead of filled ones"), on = alt,
                callback = function() G_reader_settings:flipTrue("book_map_alt_theme") bmw.editable_stuff_edited = true upd() end },
        }, W)
        local choices = VerticalGroup:new{ align = "left",
            seg_row(W, _("Layout"), { { label = _("Grid"), key = "grid" }, { label = _("Flat"), key = "flat" } },
                bmw.flat_map and "flat" or "grid", function(k)
                    if not has_toc then return end
                    bmw.flat_map = k == "flat"
                    bmw:saveSettings()
                    upd()
                end),
            HorizontalGroup:new{ K.hspan("sp-5"), K.line(W - 2 * T.px("sp-5")) },
            seg_row(W, _("Open at"), { { label = _("Current page"), key = "cur" }, { label = _("Where I started"), key = "init" } },
                initial and "init" or "cur", function()
                    if not has_toc then return end
                    pcall(function() bmw:toggleDefaultSettings() end)
                    upd()
                end) }
        local function slider(label, v, vmin, vmax, shown, set)
            local span = math.max(1, vmax - vmin)
            return Kit.slider_row{ width = W, label = label, label_w = sc(130), pct = (v - vmin) / span, value = shown or tostring(v), parent = self,
                on_step = function(d)
                    local nv = math.max(vmin, math.min(vmax, v + (d > 0 and 1 or -1)))
                    if nv ~= v then set(nv) upd() end
                end,
                on_change = function(frac, final)
                    if not final then return end
                    local nv = math.floor(vmin + frac * span + 0.5)
                    if nv ~= v then set(nv) upd() end
                end }
        end
        -- page-slot width as a 1-10 level: 100 / pages per row (wider slots = higher)
        local ppr_max, ppr_min = bmw.max_pages_per_row or 100, bmw.min_pages_per_row or 10
        local width_v = math.max(1, math.min(10, math.floor(100 / math.max(1, bmw.pages_per_row or 100) + 0.5)))
        local sliders = VerticalGroup:new{ align = "left",
            slider(_("Chapter levels"), bmw.toc_depth or 0, 0, math.max(1, bmw.max_toc_depth or 1), nil, function(nv)
                pcall(function() bmw:updateTocDepth(nv, bmw.flat_map) end)
            end),
            slider(_("Page width"), width_v, 1, 10, nil, function(nv)
                local ppr = math.max(ppr_min, math.min(ppr_max, math.floor(100 / nv + 0.5)))
                pcall(function() bmw:updatePagesPerRow(ppr) end)
            end),
            slider(_("10-page marks"), bmw.ten_pages_markers or 0, 0, 3, nil, function(nv)
                bmw.ten_pages_markers = nv
                G_reader_settings:saveSetting("book_map_ten_pages_markers", nv)
            end) }
        local g2 = group({
            { icon = "leaf.gl.info", label = _("About the book map"), chev = true, callback = function() bmw:showAbout() end },
            { icon = "leaf.gl.hand", label = _("Gestures"), chev = true, callback = function() bmw:showGestures() end },
        }, W)
        return VerticalGroup:new{ align = "left",
            head{ width = W, title = _("Book map options"), close = function() self:onClose() end, parent = self },
            g1, K.vspan("sp-4"), choices, K.vspan("sp-4"), sliders, K.vspan("sp-4"), g2, K.vspan("sp-1") }
    end
    function MapOptions:onCloseWidget()
        if self.bmw then pcall(function() self.bmw:free() end) self.bmw = nil end
        UIManager:setDirty(nil, "ui")
    end
    function M.show_map_options(ui, on_close)
        UIManager:show(MapOptions:new{ ui = ui, close_callback = on_close })
    end

    local PAGENUMS = { [0] = _("None"), _("Some"), _("All") }
    local PagesOptions = Sheet:extend{}
    function PagesOptions:content(W)
        local ui = self.ui
        local ds = ui.doc_settings
        local function upd() self.changed = true self:refresh() end
        local handmade = ui.handmade and ui.handmade:isHandmadeTocEnabled()
        local toc_key = handmade and "page_browser_toc_depth_handmade_toc" or "page_browser_toc_depth"
        local max_depth = handmade and 1 or (ui.toc.toc_depth or 1)
        local cols = ds:readSetting("page_browser_nb_cols") or G_reader_settings:readSetting("page_browser_nb_cols") or 3
        local rows = ds:readSetting("page_browser_nb_rows") or G_reader_settings:readSetting("page_browser_nb_rows") or 3
        local nums = ds:readSetting("page_browser_thumbnails_pagenums") or G_reader_settings:readSetting("page_browser_thumbnails_pagenums") or 2
        local depth = ds:readSetting(toc_key) or max_depth
        local function save(key, v, global)
            ds:saveSetting(key, v)
            if global then G_reader_settings:saveSetting(key, v) end
        end
        local function slider(label, v, vmin, vmax, shown, set)
            local span = math.max(1, vmax - vmin)
            return Kit.slider_row{ width = W, label = label, label_w = sc(130), pct = (v - vmin) / span, value = shown or tostring(v), parent = self,
                on_step = function(d)
                    local nv = math.max(vmin, math.min(vmax, v + (d > 0 and 1 or -1)))
                    if nv ~= v then set(nv) upd() end
                end,
                on_change = function(frac, final)
                    if not final then return end
                    local nv = math.floor(vmin + frac * span + 0.5)
                    if nv ~= v then set(nv) upd() end
                end }
        end
        local g1 = group({
            toggle_row{ icon = "leaf.gl.images", label = _("Prepare next and previous thumbnails"), sub = _("Faster paging, uses more memory"),
                on = G_reader_settings:isTrue("page_browser_preload_thumbnails"), callback = function()
                    G_reader_settings:flipTrue("page_browser_preload_thumbnails") upd() end },
        }, W)
        local sliders = VerticalGroup:new{ align = "left",
            slider(_("Columns"), cols, 1, 6, nil, function(nv) save("page_browser_nb_cols", nv, true) end),
            slider(_("Rows"), rows, 1, 6, nil, function(nv) save("page_browser_nb_rows", nv, true) end),
            slider(_("Page numbers"), nums, 0, 2, PAGENUMS[nums], function(nv) save("page_browser_thumbnails_pagenums", nv, true) end),
            slider(_("Chapter levels"), depth, 0, math.max(1, max_depth), nil, function(nv) save(toc_key, nv) end) }
        local PBW = require("ui/widget/pagebrowserwidget")
        local g2 = group({
            { icon = "leaf.gl.info", label = _("About the page browser"), chev = true, callback = function() PBW.showAbout({ ui = ui }) end },
            { icon = "leaf.gl.hand", label = _("Gestures"), chev = true, callback = function() PBW.showGestures({ ui = ui }) end },
        }, W)
        return VerticalGroup:new{ align = "left",
            head{ width = W, title = _("Page browser options"), close = function() self:onClose() end, parent = self },
            g1, K.vspan("sp-4"), sliders, K.vspan("sp-4"), g2, K.vspan("sp-1") }
    end
    function M.show_pages_options(ui, on_close)
        local s
        s = PagesOptions:new{ ui = ui, close_callback = function() if on_close then on_close(s.changed) end end }
        UIManager:show(s)
    end

    -- long-press a page thumbnail (PageBrowserWidget:onThumbnailHold)
    local PageHold = Sheet:extend{}
    function PageHold:content(W)
        local ui, page = self.ui, self.page
        local hm = ui.handmade
        local after = function() if self.on_change then self.on_change() end end
        local function close_then(fn) return function() self:onClose() fn() end end
        local ConfirmBox = require("ui/widget/confirmbox")
        local marked = ui.bookmark:isPageBookmarked(ui.rolling and ui.document:getPageXPointer(page) or page)
        local has_toc = hm and hm:isHandmadeTocEnabled() and hm:hasPageTocItem(page)
        local hidden = hm and hm:isHandmadeHiddenFlowsEnabled() and hm:isInHiddenFlow(page)
        local rows = {
            { icon = marked and "leaf.gl.bmminus" or "leaf.gl.bmplus", label = marked and _("Remove the bookmark") or _("Bookmark this page"),
                callback = close_then(function()
                    ui.bookmark:toggleBookmark(page)
                    after()
                    notify(marked and T_(_("Page %1 bookmark removed"), page) or T_(_("Page %1 bookmarked"), page))
                end) },
        }
        if hm then
            table.insert(rows, { icon = "leaf.gl.listplus", label = has_toc and _("Edit or remove the chapter here") or _("Start a chapter here"),
                sub = _("Adds an entry to your own table of contents"), callback = close_then(function()
                    local function go() hm:addOrEditPageTocItem(page, after) end
                    if hm:isHandmadeTocEnabled() then
                        if not hm:isHandmadeTocEditEnabled() then hm.toc_edit_enabled = true end
                        return go()
                    end
                    UIManager:show(ConfirmBox:new{
                        text = _("Use your own table of contents?") .. "\n" .. _("KOReader's custom table of contents replaces the book's own for this book. You can turn it off in Settings › Custom layout features."),
                        ok_text = _("Use it"), ok_callback = function() hm:onToggleHandmadeToc() go() end })
                end) })
            table.insert(rows, { icon = hidden and "leaf.gl.eye" or "leaf.gl.eyeoff", label = hidden and _("Show pages from here") or _("Hide pages from here"),
                sub = hidden and _("Restarts the regular flow") or _("Starts a hidden flow (e.g. notes, index)"), callback = close_then(function()
                    local function go() hm:toggleHiddenFlow(page) after() end
                    if hm:isHandmadeHiddenFlowsEnabled() then
                        if not hm:isHandmadeHiddenFlowsEditEnabled() then hm.flows_edit_enabled = true end
                        return go()
                    end
                    UIManager:show(ConfirmBox:new{
                        text = _("Turn on hidden flows?") .. "\n" .. _("Pages in a hidden flow are skipped while reading. You can turn it off in Settings › Custom layout features."),
                        ok_text = _("Turn on"), ok_callback = function() hm:onToggleHandmadeFlows() go() end })
                end) })
        end
        local ch = ui.toc and ui.toc:getTocTitleByPage(page) or ""
        local lbl, ttl = chapter_label(ch)
        local sub = (ttl and lbl ~= ttl) and (lbl .. " · " .. ttl) or ch
        return VerticalGroup:new{ align = "left",
            head{ width = W, lead = lead_tile("leaf.gl.file"), title = T_(_("Page %1"), page), sub = sub,
                close = function() self:onClose() end, parent = self, rule = true },
            K.vspan("sp-2"), group(rows, W), K.vspan("sp-1") }
    end
    function M.show_page_hold(ui, page, on_change)
        UIManager:show(PageHold:new{ ui = ui, page = page, on_change = on_change })
    end

    ------------------------------------------------------------------ dictionary popup menus
    local DQL = require("ui/widget/dictquicklookup")
    -- where the popovers sit: the sheet's left edge / just under its head
    local function dql_frame(dql)
        local f = dql.dict_frame and dql.dict_frame.dimen
        if f and f.w and f.w > 0 then return f end
        local SH = Screen:getHeight()
        return Geom:new{ x = 0, y = math.floor(SH * 0.4), w = Screen:getWidth(), h = math.floor(SH * 0.6) }
    end

    L.wrap(DQL, "onShowResultsMenu", function(orig, self)
        if not Device:isTouchDevice() or self.is_wiki then return orig(self) end
        local pop
        local f = dql_frame(self)
        pop = Popover:new{ x = f.x + T.px("sp-4"), bottom = T.px("sp-2"), width = sc(290), build = function(W)
            local g = VerticalGroup:new{ align = "left", pop_label(_("Results"), W) }
            for idx, r in ipairs(self.results or {}) do
                table.insert(g, pop_row(W, { label = r.word or "", sub = r.dict, radio = idx == self.dict_index,
                    callback = function() UIManager:close(pop) self:changeDictionary(idx) end,
                    hold = function() self.ui:handleEvent(Event:new("LookupWord", r.word)) end }))
            end
            table.insert(g, pop_divider(W))
            table.insert(g, pop_row(W, { icon = "leaf.gl.firsts", label = _("First dictionary"), callback = function()
                UIManager:close(pop) self:changeToFirstDict() end }))
            table.insert(g, pop_row(W, { icon = "leaf.gl.lasts", label = _("Last dictionary"), callback = function()
                UIManager:close(pop) self:changeToLastDict() end }))
            table.insert(g, pop_row(W, { icon = "leaf.gl.pencil", label = _("Look up another word…"), callback = function()
                UIManager:close(pop) self:onLookupInputWord(self.word) end }))
            return g
        end }
        UIManager:show(pop)
        return true
    end, "DictQuickLookup:onShowResultsMenu")

    -- Wikipedia language names: native · English
    local LANG = { en = "English", ar = "العربية · Arabic", fr = "Français · French", de = "Deutsch · German",
        es = "Español · Spanish", it = "Italiano · Italian", pt = "Português · Portuguese", ru = "Русский · Russian",
        zh = "中文 · Chinese", ja = "日本語 · Japanese", nl = "Nederlands · Dutch", pl = "Polski · Polish",
        tr = "Türkçe · Turkish", fa = "فارسی · Persian", he = "עברית · Hebrew", uk = "Українська · Ukrainian",
        sv = "Svenska · Swedish", ko = "한국어 · Korean", el = "Ελληνικά · Greek" }
    function M.wiki_lang_menu(dql)
        local pop
        local f = dql_frame(dql)
        local langs = dql.wiki_languages or {}
        local cur = (dql.lang or langs[1] or ""):lower()
        local lead = sc(36) + T.px("sp-3") + T.px("sp-5")
        pop = Popover:new{ x = f.x + lead, y = f.y + T.px("h-header") - T.px("sp-2"), width = sc(290), build = function(W)
            local g = VerticalGroup:new{ align = "left", pop_label(_("Wikipedia language"), W) }
            for _i, l in ipairs(langs) do
                local code = l:lower()
                table.insert(g, pop_row(W, { label = LANG[code] or code:upper(), radio = code == cur, callback = function()
                    UIManager:close(pop)
                    dql.ui.wikipedia:setLastSelectedLanguage(l)
                    dql:lookupWikipedia(false, nil, nil, l)
                    dql:onClose(true)
                end }))
            end
            table.insert(g, pop_divider(W))
            table.insert(g, pop_row(W, { icon = "leaf.gl.settings", label = _("Wikipedia languages…"), callback = function()
                UIManager:close(pop)
                local items = {}
                dql.ui.wikipedia:addToMainMenu(items)
                local set = items.wikipedia_settings and items.wikipedia_settings.sub_item_table
                for _i, it in ipairs(set or {}) do
                    if it.text == _("Set Wikipedia languages") and it.callback then it.callback() break end
                end
            end }))
            return g
        end }
        UIManager:show(pop)
    end
    L.wrap(DQL, "_getButtonPool", function(orig, self, ...)
        local pool = orig(self, ...)
        if self.is_wiki and pool and pool.search and Device:isTouchDevice() then
            pool.search.callback = function() M.wiki_lang_menu(self) end
        end
        return pool
    end, "DictQuickLookup:_getButtonPool")

    -- "Look up a word"
    L.wrap(DQL, "lookupInputWord", function(orig, self, hint)
        if not Device:isTouchDevice() then return orig(self, hint) end
        local InputDialog = require("ui/widget/inputdialog")
        local Translator = require("ui/translator")
        local Presets = require("ui/presets")
        local dlg
        local function txt()
            local t = dlg:getInputText()
            if t == "" or t:match("^%s*$") then return nil end
            return t
        end
        local function search_dict()
            local t = txt()
            if not t then return end
            UIManager:close(dlg)
            self.is_wiki = false
            self.ui:handleEvent(Event:new("LookupWord", t, true))
        end
        local function search_wiki()
            local t = txt()
            if not t then return end
            UIManager:close(dlg)
            self.is_wiki = true
            self:lookupWikipedia(false, t, true)
        end
        -- the keyboard's Enter key reads "Look up" (leaf/keyboard.lua reads it when it builds the keys)
        local InputText = require("ui/widget/inputtext")
        InputText._leaf_enter_label = _("Look up")
        local ok_new, err_new = pcall(function() dlg = InputDialog:new{
            title = _("Look up a word"), input = hint, input_hint = _("Word or phrase"),
            buttons = { {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
                { text = _("Look up"), is_enter_default = true, callback = self.is_wiki and search_wiki or search_dict },
            } },
        } end)
        InputText._leaf_enter_label = nil
        if not ok_new then error(err_new) end
        self.input_dialog = dlg
        local W = dlg.width - 2 * T.px("sp-5")
        local rows = {
            { icon = "leaf.gl.textsearch", label = _("Find in this definition"), callback = function()
                local t = txt()
                if t then UIManager:close(dlg) self:searchInDefinition(t) end
            end },
            { icon = "leaf.gl.languages", label = _("Translate"), callback = function()
                local t = txt()
                if t then UIManager:close(dlg) Translator:showTranslation(t, true) end
            end },
            self.is_wiki and { icon = "leaf.lk.dict", label = _("Search dictionary"), callback = search_dict }
                or { icon = "leaf.gl.globe", label = _("Search Wikipedia"), callback = search_wiki },
        }
        local preset_names = Presets.getPresets(self.ui.dictionary.preset_obj)
        if preset_names and #preset_names > 0 then
            table.insert(rows, { icon = "leaf.gl.sliders", label = _("Search with a preset"),
                value = #preset_names == 1 and preset_names[1] or T_(_("%1 presets"), #preset_names), chev = true,
                callback = function()
                    local t = txt()
                    if not t then return end
                    local ButtonDialog = require("ui/widget/buttondialog")
                    local current = self.ui.dictionary:buildPreset()
                    local bd, buttons = nil, {}
                    for _i, name in ipairs(preset_names) do
                        table.insert(buttons, { { text = name, align = "left", callback = function()
                            self.ui.dictionary:loadPreset(self.ui.dictionary.preset_obj.presets[name], true)
                            UIManager:close(bd)
                            UIManager:close(dlg)
                            self.ui:handleEvent(Event:new("LookupWord", t, true, nil, nil, nil, function()
                                self.ui.dictionary:loadPreset(current, true)
                            end))
                        end } })
                    end
                    bd = ButtonDialog:new{ title = _("Search with a preset"), buttons = buttons }
                    dlg:onCloseKeyboard()
                    UIManager:show(bd)
                end })
        end
        -- the sunken group (.ko-group--sunken), dialog-wide minus its padding
        local fw = dlg._input_widget and dlg._input_widget:getSize().w or W
        local g = group(rows, fw, { bg = "surface-2", flush = true })
        dlg:addWidget(VerticalGroup:new{ align = "left", K.vspan("sp-3"), g })
        if dlg._input_widget then dlg._input_widget._leaf_enter_label = _("Look up") end
        InputText._leaf_enter_label = _("Look up")
        UIManager:show(dlg)
        dlg:onShowKeyboard()
        InputText._leaf_enter_label = nil
    end, "DictQuickLookup:lookupInputWord")
end

return M
