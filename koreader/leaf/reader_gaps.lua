--[[
    Leaf reader gaps (prototype group "Gaps", js/screens/gaps.js): the reader surfaces the first port
    did not cover. Each one keeps KOReader's callbacks and settings; only the drawing is Leaf's.

      ReaderFlipping   .gp-flipmark pill (icon + "Flipping" / "Bookmarks" / "Selecting" / "Re-rendering" /
                       "Layout ready") top-left on the page, and a .gp-banner popover above the status bar
                       with the mode's help and its way out (Exit / Cancel / Use now).
      LinkBox          the tapped PDF link: a --bw-md --page-ink outline with --r-sm corners around the link.
      External link    ButtonDialog -> action sheet (.ko-sheet-head--rule with a link / globe tile, the
                       URL as sub; rows: Read online, Read the saved EPUB, Open in browser, Copy link,
                       Show QR code, plugin rows such as Add to Wallabag).
      QuickMenu        Dispatcher._showAsMenu -> .gp-qm popover: GESTURE / PROFILE eyebrow, title, Run all
                       actions (profiles), icon rows, dividers where the user put separators.
      Overlapping highlights   ReaderHighlight:showChooseHighlightDialog -> .gp-hlm popover: "n highlights
                       here", one row per highlight (style swatch, quoted text, "Highlight · Yellow · has a note").
      Screenshot saved Screenshoter's ButtonDialog -> action sheet (thumbnail lead, path, View / Set as book
                       cover / Set as sleep screen, Delete screenshot, gesture note).
      Busy toast       StartActivityIndicator / StopActivityIndicator (the Kindle's native spinner, PDF
                       reflow) -> a Leaf toast "Reflowing page…" with a loader icon.
      Perception expander  guide lines in --page-ink; its settings dialog -> a Leaf sheet (toggle, four
                       slider rows, About).
      Read timer       "Time is up" title over the expiry message, and the interval note.
    Book images in the image viewer: title / sub for leaf/imageviewer.lua (the shared viewer restyle).
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local Kit = require("leaf/widgets/kit")
    local geom = K.geom

    ------------------------------------------------------------------ shared pieces
    -- a .ko-btn--sm (40px, --fs-sm, --sp-3 padding): secondary = --surface-2, primary = --accent
    local function small_button(label, cb, kind)
        local primary = kind == "primary"
        local t = K.text(label, primary and "ui-semibold" or "ui-medium", "fs-sm", primary and "accent-ink" or "text")
        local w = t:getSize().w + 2 * T.px("sp-3")
        local h = T.px("h-control")
        return Kit.Tap:new{ width = w, height = h, radius = T.px("r-md"), bg = T.color(primary and "accent" or "surface-2"),
            content = CenterContainer:new{ dimen = geom(w, h), t }, callback = cb }
    end
    M.small_button = small_button

    -- .ko-group: rows in a --surface card (--r-lg, --border hairline), --sp-4 from the sheet edges,
    -- hairlines between rows from --sp-4 to the right edge
    local function group(rows, W)
        local gw = W - 2 * T.px("sp-4")
        local list = VerticalGroup:new{ align = "left" }
        for i, r in ipairs(rows) do
            if i > 1 then
                table.insert(list, HorizontalGroup:new{ K.hspan("sp-4"), K.line(gw - 2 * T.px("hairline") - T.px("sp-4")) })
            end
            table.insert(list, r)
        end
        local card = FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = 0, list }
        return HorizontalGroup:new{ K.hspan("sp-4"), card }
    end
    -- a row inside a group (padding --sp-4), icon --text-2
    local function grow(W, o)
        o.width = W - 2 * T.px("sp-4") - 2 * T.px("hairline")
        o.pad = T.px("sp-4")
        if o.enabled == false then o.dim = true end
        if o.icon and not o.lead then -- .ko-row .ko-i: --text-2 (--disabled when off, --danger on danger rows)
            o.lead = Kit.TintIcon:new{ icon = o.icon, size_token = "icon-md",
                color = T.color(o.enabled == false and "disabled" or (o.danger and "danger" or "text-2")) }
            o.icon = nil
        end
        local cb = o.callback
        if o.enabled == false then o.callback = function() end end
        local r = K.row(o)
        if o.enabled == false and cb then r.callback = nil end
        return r
    end
    M.group, M.group_row = group, grow

    -- .ko-sheet-head (--rule when there is a lead): [lead] title / sub … ×
    local function sheet_head(W, o)
        local pad_l, pad_r = T.px("sp-5"), T.px("sp-3")
        local close = K.icon_button("close", o.close, o.parent)
        local cw = close:getSize().w
        local lead_w = o.lead and (o.lead:getSize().w + T.px("sp-3")) or 0
        local tw = W - pad_l - pad_r - cw - lead_w - T.px("sp-2")
        local col = VerticalGroup:new{ align = "left", K.text(o.title, "ui-semibold", "fs-head", "text", tw) }
        if o.sub and o.sub ~= "" then
            table.insert(col, K.vspan(1))
            table.insert(col, K.text(o.sub, "ui", "fs-sm", "text-3", tw))
        end
        local ch = col:getSize().h
        col:resetLayout()
        local rule = o.lead ~= nil
        local top, bottom = T.px(rule and "sp-1" or "sp-2"), T.px(rule and "sp-3" or "sp-2")
        local h = math.max(T.px("h-header"), ch + top + bottom)
        local left = HorizontalGroup:new{ align = "center", K.hspan(pad_l) }
        if o.lead then table.insert(left, o.lead) table.insert(left, K.hspan("sp-3")) end
        table.insert(left, col)
        local head = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), left },
            RightContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ close, K.hspan(pad_r - T.px("sp-1")) } } }
        if not rule then return head end
        return VerticalGroup:new{ head, K.line(W) }
    end
    M.sheet_head = sheet_head

    --[[ Leaf action sheet: { title, sub, lead (widget), groups = { {rows...}, ... }, note = {icon, text},
         on_close } — rows: { icon, label, sub, danger, enabled, callback, hold } ]]
    local ActionSheet = InputContainer:extend{ _leaf_wants_scrim = true, is_always_active = true }
    function ActionSheet:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(W, H)
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        local inner = Kit.inner(W)
        local g = VerticalGroup:new{ align = "left" }
        table.insert(g, sheet_head(inner, { title = self.title, sub = self.sub, lead = self.lead, parent = self,
            close = function() self:onClose() end }))
        for i, rows in ipairs(self.groups or {}) do
            table.insert(g, K.vspan(i == 1 and (self.lead and "sp-2" or "sp-1") or "sp-3"))
            local built = {}
            for _j, r in ipairs(rows) do
                local cb = r.callback
                table.insert(built, grow(inner, { icon = r.icon, label = r.label, sub = r.sub, danger = r.danger,
                    enabled = r.enabled, hold = r.hold, callback = cb and function() cb(self) end }))
            end
            table.insert(g, group(built, inner))
        end
        if self.note then
            table.insert(g, K.vspan("sp-3"))
            local iw = T.px("icon-sm")
            local tw = inner - 2 * T.px("sp-5") - iw - T.px("sp-2")
            table.insert(g, HorizontalGroup:new{ align = "top", K.hspan("sp-5"),
                Kit.TintIcon:new{ icon = self.note.icon, size_token = "icon-sm", color = T.color("text-3") }, K.hspan("sp-2"),
                K.textbox(self.note.text, "ui", "fs-xs", "text-3", tw, "bg-raised") })
        end
        table.insert(g, K.vspan("sp-4"))
        local frame, container = Kit.sheet{ content = g }
        self._frame = frame
        self[1] = container
    end
    function ActionSheet:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then self:onClose() end
        return true
    end
    function ActionSheet:onClose()
        UIManager:close(self)
        if self.on_close then self.on_close() end
        return true
    end
    function ActionSheet:onShow() UIManager:setDirty(self, "ui") return true end
    function ActionSheet:onCloseWidget() UIManager:setDirty(nil, "ui") end
    M.ActionSheet = ActionSheet

    --[[ Leaf popover (.ko-popover): --surface, --border-strong hairline, --r-lg, --sp-2 above and below.
         { width, content, x, y (top-left; centred horizontally when x is nil) } ]]
    local Popover = InputContainer:extend{ is_always_active = true }
    function Popover:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(W, H)
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        local frame = FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border-strong"),
            background = T.color("surface"), radius = T.px("r-lg"), padding = 0,
            VerticalGroup:new{ align = "left", K.vspan("sp-2"), self.content, K.vspan("sp-2") } }
        self._frame = frame
        local fs = frame:getSize()
        self._x = self.x or math.floor((W - fs.w) / 2)
        self._y = math.max(0, math.min(self.y or math.floor((H - fs.h) / 2), H - fs.h))
        self[1] = frame
    end
    function Popover:paintTo(bb, x, y)
        self[1]:paintTo(bb, x + self._x, y + self._y)
    end
    function Popover:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then self:onClose() end
        return true
    end
    function Popover:onClose()
        UIManager:close(self)
        if self.on_close then self.on_close() end
        return true
    end
    function Popover:onShow() UIManager:setDirty(self, "ui", self._frame.dimen) return true end
    function Popover:onCloseWidget() UIManager:setDirty(nil, "ui", self._frame.dimen) end
    M.Popover = Popover

    -- a popover row (.ko-popover .ko-row: 44px, --sp-4 sides, no separators)
    local function prow(W, o)
        o.width, o.pad, o.height = W, T.px("sp-4"), T.px("h-row-compact")
        if o.enabled == false then
            o.dim = true
            o.callback = nil
        end
        if o.icon then
            o.lead = Kit.TintIcon:new{ icon = o.icon, size_token = "icon-md", color = T.color(o.enabled == false and "disabled" or "text-2") }
            o.icon = nil
        end
        return K.row(o)
    end
    local function divider(W)
        return VerticalGroup:new{ K.vspan("sp-2"), K.line(W), K.vspan("sp-2") }
    end

    -- show a function's ButtonDialog through Leaf: run fn with UIManager:show catching the first
    -- ButtonDialog it shows; returns it (not shown), or nil
    local ButtonDialog = require("ui/widget/buttondialog")
    local function capture(fn)
        local caught
        local show = UIManager.show
        UIManager.show = function(um, w, ...)
            if not caught and type(w) == "table" and getmetatable(w) and w.buttons and w.onClose == ButtonDialog.onClose then
                caught = w
                return
            end
            return show(um, w, ...)
        end
        local ok, err = pcall(fn)
        UIManager.show = show
        if not ok then error(err, 0) end
        return caught
    end
    local function each_button(dialog)
        local out = {}
        for _i, row in ipairs(dialog.buttons or {}) do
            for _j, b in ipairs(row) do
                if b.text or b.text_func then table.insert(out, b) end
            end
        end
        return out
    end
    local function btext(b) return b.text_func and b.text_func() or b.text or "" end

    ------------------------------------------------------------------ ReaderFlipping: mark + banner
    local ReaderFlipping = require("apps/reader/modules/readerflipping")
    local FLIP = {
        flip = { icon = "leaf.gr.book-open", label = _("Flipping"),
            banner = _("Flipping mode · drag sideways to skip pages, up or down to move through the book. Tap the status bar to jump."), exit = _("Exit") },
        bm = { icon = "leaf.gr.bookmark", label = _("Bookmarks"),
            banner = _("Bookmark flipping · swipe left or right to go to the next or previous bookmark."), exit = _("Exit") },
        select = { icon = "leaf.gr.text-select", label = _("Selecting"),
            banner = _("Tap the word where the selection should end. It can be on another page."), exit = _("Cancel") },
        render = { icon = "leaf.gr.loader-circle", label = _("Re-rendering"), soft = true,
            banner = _("Laying out the book with the new font in the background. You can keep reading.") },
        partial = { icon = "leaf.gr.loader-circle", label = _("Re-rendering"), soft = true },
        ready = { icon = "leaf.gr.refresh-cw", label = _("Layout ready"),
            banner = _("The new layout is ready and is used from the next page turn."), exit = _("Use now") },
        reload = { icon = "leaf.gr.refresh-cw", label = _("Reloading"), soft = true },
    }
    local function flip_kind(self)
        local ui = self.ui
        if ui.paging and self.view.flipping_visible then
            return ui.paging.bookmark_flipping_mode and "bm" or "flip"
        elseif ui.highlight and ui.highlight.select_mode then
            return "select"
        elseif ui.highlight and ui.highlight.long_hold_reached then
            return nil, true
        elseif ui.rolling and ui.rolling.rendering_state then
            local S = ui.rolling.RENDERING_STATE or {}
            local st = ui.rolling.rendering_state
            if st == S.FULL_RENDERING_IN_BACKGROUND then return "render"
            elseif st == S.FULL_RENDERING_READY then return "ready"
            elseif st == S.RELOADING_DOCUMENT then return "reload"
            elseif st == S.PARTIALLY_RERENDERED then return "partial" end
        end
    end
    M.FLIP = FLIP

    local function flip_exit(self, kind)
        local ui = self.ui
        if kind == "flip" then ui.paging:onTogglePageFlipping()
        elseif kind == "bm" then ui.paging:onToggleBookmarkFlipping()
        elseif kind == "select" then
            local hl = ui.highlight
            hl.select_mode = false
            local a = ui.annotation.annotations[hl.highlight_idx]
            if a and a.is_tmp then hl:deleteHighlight(hl.highlight_idx) end
            UIManager:setDirty(self.view.dialog, "ui")
        elseif kind == "ready" then
            local r = ui.rolling
            if r._stepRerenderingAutomation then r._stepRerenderingAutomation(r.RENDERING_STATE.RELOADING_DOCUMENT) end
        end
    end

    -- the pill: icon + label, --fs-2xs semibold, --page background, --page-ink hairline ring
    local function paint_mark(bb, x, y, f)
        local col = T.color(f.soft and "page-2" or "page-ink")
        local icon = Kit.TintIcon:new{ icon = f.icon, size_token = "icon-xs", color = col }
        local t = K.text(f.label, "ui-semibold", "fs-2xs", f.soft and "page-2" or "page-ink")
        local is = T.px("icon-xs")
        local pv = Screen:scaleBySize(2 * T.scale)
        local h = math.max(is, t:getSize().h) + 2 * pv
        local w = T.px("sp-1h") + is + T.px("sp-1") + t:getSize().w + T.px("sp-2")
        local mx, my = x + T.px("sp-2"), y + Screen:scaleBySize(3 * T.scale)
        local r = math.floor(h / 2)
        bb:paintRoundedRect(mx, my, w, h, T.color("page-ink"), r)
        local hair = T.px("hairline")
        bb:paintRoundedRect(mx + hair, my + hair, w - 2 * hair, h - 2 * hair, T.color("page"), r - hair)
        icon:paintTo(bb, mx + T.px("sp-1h"), my + math.floor((h - is) / 2))
        t:paintTo(bb, mx + T.px("sp-1h") + is + T.px("sp-1"), my + math.floor((h - t:getSize().h) / 2))
        icon:free() t:free()
        return geom(w, h)
    end

    -- the banner (.ko-popover.gp-float.gp-banner): --sp-4 from the sides, 56px above the bottom edge
    local function banner_widget(self, kind, f)
        local W = Screen:getWidth()
        local w = math.min(W - 2 * T.px("sp-4"), Screen:scaleBySize(560 * T.scale))
        local hair = T.px("hairline")
        local is = T.px("icon-md")
        local btn
        if f.exit then btn = small_button(f.exit, function() flip_exit(self, kind) end) end
        local bw = btn and (btn:getSize().w + T.px("sp-2")) or 0
        local tw = w - 2 * hair - T.px("sp-4") - is - T.px("sp-2") - bw - (btn and T.px("sp-2") or T.px("sp-4"))
        local text = K.textbox(f.banner, "ui", "fs-sm", "text-2", tw, "surface")
        local row = HorizontalGroup:new{ align = "center", K.hspan("sp-4"),
            Kit.TintIcon:new{ icon = f.icon, size_token = "icon-md", color = T.color("text") }, K.hspan("sp-2"), text }
        local h = math.max(row:getSize().h, btn and btn:getSize().h or 0) + 2 * T.px("sp-2")
        row:resetLayout()
        local inner_w = w - 2 * hair
        local body = OverlapGroup:new{ dimen = geom(inner_w, h - 2 * hair),
            LeftContainer:new{ dimen = geom(inner_w, h - 2 * hair), row } }
        if btn then
            table.insert(body, RightContainer:new{ dimen = geom(inner_w, h - 2 * hair), HorizontalGroup:new{ btn, K.hspan("sp-2") } })
        end
        local frame = FrameContainer:new{ bordersize = hair, color = T.color("border-strong"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = 0, body }
        frame._leaf_btn = btn
        return frame
    end

    L.wrap(ReaderFlipping, "paintTo", function(orig, self, bb, x, y)
        local kind, stock = flip_kind(self)
        if stock or not kind then
            self._leaf_banner = nil
            if stock then return orig(self, bb, x, y) end
            return
        end
        local f = FLIP[kind]
        paint_mark(bb, x, y, f)
        if f.banner and not self._leaf_no_banner then
            if not (self._leaf_banner and self._leaf_banner_kind == kind) then
                self._leaf_banner = banner_widget(self, kind, f)
                self._leaf_banner_kind = kind
            end
            local b = self._leaf_banner
            local sz = b:getSize()
            local W, H = Screen:getWidth(), Screen:getHeight()
            local bx = x + math.floor((W - sz.w) / 2)
            local by = y + H - Screen:scaleBySize(56 * T.scale) - sz.h
            b:paintTo(bb, bx, by)
            self._leaf_banner_rect = geom(sz.w, sz.h)
            self._leaf_banner_rect.x, self._leaf_banner_rect.y = bx, by
        else
            self._leaf_banner = nil
            self._leaf_banner_rect = nil
        end
    end, "ReaderFlipping:paintTo")

    L.wrap(ReaderFlipping, "getRefreshRegion", function(orig, self)
        return geom(Screen:getWidth(), Screen:getHeight())
    end, "ReaderFlipping:getRefreshRegion")

    -- taps on the banner: its button runs the way out, the rest of the banner swallows the tap
    local ReaderUI = require("apps/reader/readerui")
    local function hook_flip_taps(ui)
        if not (ui and ui.registerTouchZones and ui.view and ui.view.flipping) then return end
        local fl = ui.view.flipping
        ui:registerTouchZones({ {
            id = "leaf_flip_banner",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            overrides = { "tap_forward", "tap_backward", "readerfooter_tap", "readermenu_tap", "readermenu_ext_tap",
                "readerconfigmenu_tap", "readerconfigmenu_ext_tap", "readerhighlight_tap", "tap_link", "paging_swipe",
                "leaf_chrome_tap", "readerhighlight_tap_select_mode", "readerfooter_hold" },
            handler = function(ges)
                local r = fl._leaf_banner_rect
                if not (fl._leaf_banner and r and ges.pos and ges.pos:intersectWith(r)) then return false end
                local btn = fl._leaf_banner._leaf_btn
                if btn and btn.dimen and ges.pos:intersectWith(btn.dimen) then btn.callback() end
                return true
            end,
        } })
    end
    L.wrap(ReaderUI, "init", function(orig, self, ...)
        orig(self, ...)
        pcall(hook_flip_taps, self)
    end, "ReaderUI:init (flip banner)")

    ------------------------------------------------------------------ LinkBox
    local LinkBox = require("ui/widget/linkbox")
    L.wrap(LinkBox, "paintTo", function(orig, self, bb)
        local b = self.box
        local px, py = T.px("sp-1"), Screen:scaleBySize(3 * T.scale)
        bb:paintBorder(b.x - px, b.y - py, b.w + 2 * px, b.h + 2 * py, T.px("bw-md"), T.color("page-ink"), T.px("r-sm"))
    end, "LinkBox:paintTo")
    L.wrap(LinkBox, "onShow", function(orig, self)
        local b = self.box
        local px, py = T.px("sp-1") + 2, Screen:scaleBySize(3 * T.scale) + 2
        local r = geom(b.w + 2 * px, b.h + 2 * py)
        r.x, r.y = b.x - px, b.y - py
        self._leaf_area = r
        local ret = orig(self)
        UIManager:setDirty(self, function() return "ui", r end)
        return ret
    end, "LinkBox:onShow")
    L.wrap(LinkBox, "onCloseWidget", function(orig, self)
        orig(self)
        if self._leaf_area then UIManager:setDirty(nil, function() return "partial", self._leaf_area end) end
    end, "LinkBox:onCloseWidget")

    ------------------------------------------------------------------ external link
    local ReaderLink = require("apps/reader/modules/readerlink")
    local LINK_ROWS = { -- KOReader / plugin button text -> Leaf row
        [_("Read online")] = { icon = "leaf.gr.globe", label = _("Read online"), sub = _("Opens the article in the Wikipedia reader"), order = 1 },
        [_("Read EPUB")] = { icon = "leaf.gr.book-open", label = _("Read the saved EPUB"), order = 2 },
        [_("Open in browser")] = { icon = "leaf.gr.external-link", label = _("Open in browser"), order = 3 },
        [_("Copy")] = { icon = "leaf.gr.copy", label = _("Copy link"), order = 4 },
        [_("Show QR code")] = { icon = "leaf.gr.qr-code", label = _("Show QR code"), sub = _("Scan it with your phone"), order = 5 },
        [_("Add to Wallabag")] = { icon = "leaf.gr.inbox", order = 6 },
    }
    -- readerlink.lua's local is_wiki_page(url) -> lang, page, saved epub path (from a button closure)
    local is_wiki_page
    local function find_is_wiki(link_obj)
        if is_wiki_page then return is_wiki_page end
        local fn = link_obj._external_link_buttons and link_obj._external_link_buttons["40_wiki_lookup"]
        if not fn then return end
        local b = fn(link_obj, "")
        local f = b and b.show_in_dialog_func
        local i = 1
        while f do
            local name, value = debug.getupvalue(f, i)
            if not name then break end
            if name == "is_wiki_page" then is_wiki_page = value break end
            i = i + 1
        end
        return is_wiki_page
    end
    function M.show_external_link(link_obj, link_url)
        local buttons = link_obj:getButtonsForExternalLinkDialog(link_url)
        local wiki, epub
        pcall(function()
            local f = find_is_wiki(link_obj)
            if f then
                local lang, page, path = f(link_url)
                wiki = lang ~= nil and page ~= nil
                epub = path
            end
        end)
        local rows = {}
        for _i, row in ipairs(buttons) do
            for _j, b in ipairs(row) do
                local text = btext(b)
                if text ~= _("Cancel") then
                    local spec = LINK_ROWS[text] or {}
                    local sub = spec.sub
                    if text == _("Read EPUB") and epub then
                        local lfs = require("libs/libkoreader-lfs")
                        local mod = lfs.attributes(epub, "modification")
                        local short = epub:match("([^/]+/[^/]+)$") or epub
                        sub = mod and T_(_("Saved on %1 · %2"), os.date("%b %d", mod):gsub(" 0", " "), short) or short
                    end
                    table.insert(rows, { order = spec.order or 50, icon = spec.icon or "leaf.gr.link", label = spec.label or text,
                        sub = sub, enabled = b.enabled ~= false, callback = function() if b.callback then b.callback() end end,
                        hold = b.hold_callback })
                end
            end
        end
        table.sort(rows, function(a, b) return a.order < b.order end)
        local sheet = ActionSheet:new{
            title = wiki and _("Wikipedia article") or _("External link"),
            sub = (link_url:gsub("^https?://", "")),
            lead = K.tile(wiki and "leaf.gr.globe" or "leaf.gr.link"),
            groups = { rows },
        }
        link_obj.external_link_dialog = sheet
        UIManager:show(sheet)
        return true
    end
    L.wrap(ReaderLink, "onGoToExternalLink", function(orig, self, link_url)
        return M.show_external_link(self, link_url)
    end, "ReaderLink:onGoToExternalLink")

    ------------------------------------------------------------------ quick menu (Dispatcher._showAsMenu)
    local Dispatcher = require("dispatcher")
    local QM_ICONS = {
        { "night", "leaf.gr.moon" }, { "frontlight", "leaf.gr.sun" }, { "light", "leaf.gr.sun" },
        { "book_map", "leaf.gr.map" }, { "bookmark", "leaf.gr.bookmark" }, { "toc", "leaf.gr.list" },
        { "pin", "leaf.gr.map-pin" }, { "translat", "leaf.gr.languages" }, { "stat", "leaf.gr.chart-column" },
        { "search", "leaf.gr.search" }, { "dictionary", "leaf.gr.book-a" }, { "wikipedia", "leaf.gr.globe" },
        { "screenshot", "leaf.gr.camera" }, { "rotat", "leaf.gr.rotate-cw" }, { "font", "leaf.gr.type" },
        { "highlight", "leaf.gr.highlighter" }, { "note", "leaf.gr.sticky-note" }, { "settings", "leaf.gr.settings-2" },
        { "profile_exec", "leaf.gr.play" },
    }
    -- Leaf's shorter names for common actions (a name the user gave an action always wins)
    local QM_NAMES = { night_mode = _("Night mode"), show_frontlight_dialog = _("Frontlight"), translate_page = _("Translate this page"),
        book_statistics = _("Book statistics") }
    local function qm_icon(key)
        for _i, p in ipairs(QM_ICONS) do
            if key:find(p[1], 1, true) then return p[2] end
        end
        return "leaf.gr.zap"
    end
    local DIRS = { north = _("up"), south = _("down"), east = _("right"), west = _("left"),
        northeast = _("up-right"), northwest = _("up-left"), southeast = _("down-right"), southwest = _("down-left") }
    local GES = { swipe = _("Swipe"), two_finger_swipe = _("Two-finger swipe"), tap = _("Tap"), hold = _("Long-press"),
        double_tap = _("Double tap"), two_finger_tap = _("Two-finger tap"), multiswipe = _("Multiswipe"),
        spread = _("Spread"), pinch = _("Pinch"), rotate = _("Rotate") }
    local function gesture_name(ges)
        if type(ges) ~= "table" or not ges.ges then return nil end
        local n = GES[ges.ges] or ges.ges:gsub("_", " ")
        if ges.direction and DIRS[ges.direction] then n = n .. " " .. DIRS[ges.direction] end
        return n
    end
    M.gesture_name = gesture_name

    L.wrap(Dispatcher, "_showAsMenu", function(orig, settings, exec_props, rename_callback, rename_hold_callback)
        if rename_callback then return orig(settings, exec_props, rename_callback, rename_hold_callback) end
        local util = require("util")
        local display_list = Dispatcher.getDisplayList(settings)
        local W = math.min(Screen:scaleBySize(340 * T.scale), math.floor(Screen:getWidth() * 0.88))
        local inner = W - 2 * T.px("hairline")
        local gesture = exec_props and gesture_name(exec_props.gesture)
        local eyebrow = gesture and _("Gesture") or _("Profile")
        local title = settings.settings and settings.settings.name or gesture or _("Quick menu")
        local keep_open = settings.settings and settings.settings.keep_open_on_apply
        local pop
        local g = VerticalGroup:new{ align = "left" }
        local tw = inner - 2 * T.px("sp-4")
        table.insert(g, VerticalGroup:new{ align = "left", K.vspan("sp-2"),
            HorizontalGroup:new{ K.hspan("sp-4"), K.text(eyebrow:upper(), "ui-semibold", "fs-xs", "text-3", tw) },
            K.vspan("sp-half"),
            HorizontalGroup:new{ K.hspan("sp-4"), K.text(title, "ui-semibold", "fs-head", "text", tw) },
            K.vspan("sp-2") })
        if exec_props and exec_props.qm_show then
            table.insert(g, prow(inner, { icon = "leaf.gr.play", label = _("Run all actions"), callback = function()
                UIManager:close(pop)
                Dispatcher:execute(settings, { qm_show = false })
            end }))
            table.insert(g, divider(inner))
        end
        local n = #display_list
        for i, v in ipairs(display_list) do
            local text = util.tableGetValue(settings, "settings", "quickmenu_action_names", v.key) or QM_NAMES[v.key] or v.text
            local enabled = Dispatcher:isActionEnabled(Dispatcher.settingsList and Dispatcher.settingsList[v.key] or nil)
            local sub
            if v.key == "go_to_pinned_page" and not enabled then sub = _("No pinned page in this book") end
            table.insert(g, prow(inner, { icon = qm_icon(v.key), label = text, sub = sub, enabled = enabled ~= false,
                callback = function()
                    UIManager:close(pop)
                    Dispatcher:execute({ [v.key] = settings[v.key] })
                    if keep_open and not util.stringStartsWith(v.key, "touch_input") then
                        UIManager:show(pop)
                    end
                end,
                hold = function()
                    if v.key:sub(1, 13) == "profile_exec_" then
                        UIManager:close(pop)
                        local item = Dispatcher.settingsList and Dispatcher.settingsList[v.key]
                        if item then UIManager:sendEvent(Event:new(item.event, item.arg, { qm_show = true })) end
                    end
                end }))
            local seps = settings.settings and settings.settings.quickmenu_separators
            if seps and seps[v.key] and i < n then table.insert(g, divider(inner)) end
        end
        local x, y
        local pos = settings.settings and settings.settings.quickmenu_position
        local anchor = exec_props and exec_props.qm_anchor
        if anchor then x, y = anchor.x, anchor.y
        elseif pos then
            x = pos.x == 0 and T.px("sp-1") or nil
            y = pos.y == 0 and T.px("sp-1") or (pos.y == 1 and Screen:getHeight()) or nil
        else
            y = math.floor(Screen:getHeight() * 0.16)
        end
        if x and x + W > Screen:getWidth() then x = Screen:getWidth() - W - T.px("sp-1") end
        pop = Popover:new{ content = VerticalGroup:new{ align = "left", K.hspan(inner), g }, x = x, y = y, _leaf_wants_scrim = true }
        UIManager:show(pop)
    end, "Dispatcher._showAsMenu")
    -- Dispatcher.settingsList is local to dispatcher.lua: reach it for isActionEnabled
    pcall(function()
        local i = 1
        while true do
            local name, value = debug.getupvalue(Dispatcher.getDisplayList, i)
            if not name then break end
            if name == "settingsList" then Dispatcher.settingsList = value break end
            i = i + 1
        end
    end)

    ------------------------------------------------------------------ overlapping highlights chooser
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local STYLE = { lighten = _("Highlight"), underscore = _("Underline"), strikeout = _("Strikeout"), invert = _("Invert") }
    local function cap(s) return s and (s:sub(1, 1):upper() .. s:sub(2)) or "" end
    -- the style swatch (.gp-sw): 6x32, --r-tick, the highlight colour (e-ink: its grey)
    local Swatch = Widget:extend{}
    function Swatch:init() self.dimen = geom(Screen:scaleBySize(6 * T.scale), Screen:scaleBySize(32 * T.scale)) end
    function Swatch:paintTo(bb, x, y)
        local ok, c = pcall(T.color, "hl-c-" .. (self.color or "yellow"))
        bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, ok and c or T.color("hl-c-gray"), T.px("r-tick"))
    end
    L.wrap(ReaderHighlight, "showChooseHighlightDialog", function(orig, self, highlights)
        if #highlights <= 1 then return orig(self, highlights) end
        local W = math.min(Screen:scaleBySize(380 * T.scale), math.floor(Screen:getWidth() * 0.9))
        local inner = W - 2 * T.px("hairline")
        local pop
        local g = VerticalGroup:new{ align = "left",
            K.vspan("sp-1"),
            HorizontalGroup:new{ K.hspan("sp-4"), K.text(T_(_("%1 highlights here"), #highlights):upper(), "ui-semibold", "fs-xs", "text-3") },
            K.vspan("sp-1") }
        for _i, index in ipairs(highlights) do
            local item = self.ui.annotation.annotations[index]
            if item then
                local text = (item.text or ""):gsub("%s+", " ")
                local sub = (STYLE[item.drawer] or _("Highlight")) .. (item.color and (" · " .. cap(item.color)) or "")
                if item.note then sub = sub .. " · " .. _("has a note") end
                -- .gp-hlm row: swatch · quote / "Highlight · Yellow" (compact: the swatch sets the height)
                local tw = inner - 2 * T.px("sp-4") - Screen:scaleBySize(6 * T.scale) - T.px("sp-3")
                local col = VerticalGroup:new{ align = "left", K.text("“" .. text .. "”", "ui", "fs-md", "text", tw),
                    K.text(sub, "ui", "fs-sm", "text-3", tw) }
                local sw = Swatch:new{ color = item.color }
                local h = math.max(col:getSize().h, sw:getSize().h) + 2 * T.px("sp-1")
                col:resetLayout()
                table.insert(g, Kit.Tap:new{ width = inner, height = h, callback = function()
                        UIManager:close(pop)
                        self:showHighlightNoteOrDialog(index)
                    end,
                    content = LeftContainer:new{ dimen = geom(inner, h),
                        HorizontalGroup:new{ align = "center", K.hspan("sp-4"), sw, K.hspan("sp-3"), col } } })
            end
        end
        -- under the tapped highlights (or at the top when they are not on screen)
        local y = T.px("sp-1")
        pcall(function()
            for _i, box in ipairs(self.view.highlight.visible_boxes or {}) do
                if box.index == highlights[1] then
                    local r = self.view:pageToScreenTransform(self.ui.paging and box.page or self.ui:getCurrentPage(), box.rect)
                    if r then y = r.y + r.h + T.px("sp-1") end
                    break
                end
            end
        end)
        pop = Popover:new{ content = VerticalGroup:new{ align = "left", K.hspan(inner), g }, x = T.px("sp-2"), y = y }
        UIManager:show(pop)
        return true
    end, "ReaderHighlight:showChooseHighlightDialog")

    ------------------------------------------------------------------ screenshot saved
    local Screenshoter = require("ui/widget/screenshoter")
    -- the screenshot thumbnail lead (.gp-shot-thumb): 40x54, --r-thumb
    local Thumb = Widget:extend{}
    function Thumb:init()
        self.dimen = geom(Screen:scaleBySize(40 * T.scale), Screen:scaleBySize(54 * T.scale))
        local ok, iw = pcall(function()
            return require("ui/widget/imagewidget"):new{ file = self.file, width = self.dimen.w, height = self.dimen.h,
                scale_factor = 0, file_do_cache = false }
        end)
        self._img = ok and iw or nil
    end
    function Thumb:paintTo(bb, x, y)
        local w, h = self.dimen.w, self.dimen.h
        bb:paintRoundedRect(x, y, w, h, T.color("border"), T.px("r-thumb"))
        if self._img then
            local ok = pcall(function()
                local s = self._img:getSize()
                self._img:paintTo(bb, x + math.floor((w - s.w) / 2), y + math.floor((h - s.h) / 2))
            end)
            if not ok then self._img = nil end
        end
    end
    function Thumb:free() if self._img then self._img:free() end end
    L.wrap(Screenshoter, "onScreenshot", function(orig, self, screenshot_name, caller_callback)
        local dialog = capture(function() orig(self, screenshot_name, caller_callback) end)
        if not dialog then return true end
        local path = screenshot_name or (dialog.title or ""):match("\n\n(.-)\n?$") or ""
        -- BD.filepath() wraps the path in bidi isolates: drop them
        path = path:gsub("\226\129[\166-\169]", ""):gsub("\226\128[\142\143\170-\174]", "")
        local name = path:match("([^/]+)$") or path
        local by = {}
        for _i, b in ipairs(each_button(dialog)) do by[btext(b)] = b end
        local sheet
        local function run(b)
            return function()
                if not b then return end
                if b.callback then b.callback() end
            end
        end
        dialog.onClose = function()
            if sheet then UIManager:close(sheet) end
            if dialog.tap_close_callback then dialog.tap_close_callback() end
            return true
        end
        local doc = self.ui and self.ui.document
        local title = doc and self.ui.doc_props and self.ui.doc_props.display_title
        local rows = {}
        local view = by[_("View")]
        if view then
            M._shot_view = function()
                require("leaf/imageviewer").next = { title = _("Screenshot"), sub = name, no_save = true, ring = true, fullscreen = true }
                run(view)()
            end
            table.insert(rows, { icon = "leaf.gr.eye", label = _("View"), callback = M._shot_view })
        end
        local cover = by[_("Set as book cover")]
        if cover then
            table.insert(rows, { icon = "leaf.gr.image", label = _("Set as book cover"),
                sub = cover.enabled == false and _("Open a book to use this") or (title and T_(_("Replaces the cover of %1"), title)),
                enabled = cover.enabled ~= false, callback = run(cover) })
        end
        local wall = by[_("Set as wallpaper")]
        if wall then
            table.insert(rows, { icon = "leaf.gr.monitor-smartphone", label = _("Set as sleep screen"), callback = run(wall) })
        end
        local known = { [_("View")] = true, [_("Set as book cover")] = true, [_("Set as wallpaper")] = true, [_("Delete")] = true }
        for _i, b in ipairs(each_button(dialog)) do
            if not known[btext(b)] then table.insert(rows, { icon = "leaf.gr.zap", label = btext(b), callback = run(b) }) end
        end
        local groups = { rows }
        if by[_("Delete")] then
            table.insert(groups, { { icon = "leaf.gr.trash-2", label = _("Delete screenshot"), danger = true, callback = run(by[_("Delete")]) } })
        end
        sheet = ActionSheet:new{
            title = _("Screenshot saved"), sub = path,
            lead = Thumb:new{ file = path },
            groups = groups,
            note = { icon = "leaf.gr.hand", text = _("Two-finger diagonal swipe takes a screenshot. Change the folder in Settings › Screenshots.") },
            on_close = function() if dialog.tap_close_callback then dialog.tap_close_callback() end end,
        }
        UIManager:show(sheet)
        return true
    end, "Screenshoter:onScreenshot")

    ------------------------------------------------------------------ busy toast (activity indicator)
    local Toast = Widget:extend{ text = "" }
    function Toast:init()
        local t = K.text(self.text, "ui", "fs-sm", "bg")
        local is = T.px("icon-sm")
        local h = math.max(t:getSize().h, is) + 2 * T.px("sp-2h")
        local w = T.px("sp-4") + is + T.px("sp-2") + t:getSize().w + T.px("sp-4")
        self._t = t
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(w, h)
        self.dimen.x = math.floor((W - w) / 2)
        self.dimen.y = H - Screen:scaleBySize(72 * T.scale) - h
        self._icon = Kit.TintIcon:new{ icon = "leaf.gr.loader-circle", size_token = "icon-sm", color = T.color("bg") }
    end
    function Toast:paintTo(bb)
        local d = self.dimen
        bb:paintRoundedRect(d.x, d.y, d.w, d.h, T.color("text"), math.floor(d.h / 2))
        local is = T.px("icon-sm")
        self._icon:paintTo(bb, d.x + T.px("sp-4"), d.y + math.floor((d.h - is) / 2))
        self._t:paintTo(bb, d.x + T.px("sp-4") + is + T.px("sp-2"), d.y + math.floor((d.h - self._t:getSize().h) / 2))
    end
    M.Toast = Toast
    function M.busy_start(ui)
        if M._busy then return end
        local t = Toast:new{ text = _("Reflowing page…") }
        t._leaf_toast = true
        M._busy = t
        UIManager:show(t, "ui", t.dimen)
        UIManager:forceRePaint()
    end
    function M.busy_stop()
        if M._busy then
            local t = M._busy
            M._busy = nil
            UIManager:close(t, "ui", t.dimen)
        end
    end
    local Indicator = require("apps/reader/modules/readeractivityindicator")
    L.wrap(Indicator, "onStartActivityIndicator", function(orig, self)
        M.busy_start(self.ui)
        return true
    end, "ReaderActivityIndicator:onStartActivityIndicator")
    L.wrap(Indicator, "onStopActivityIndicator", function(orig, self)
        M.busy_stop()
        return true
    end, "ReaderActivityIndicator:onStopActivityIndicator")
    -- no native indicator registered (every device but a Kindle): listen on ReaderView instead
    local ReaderView = require("apps/reader/modules/readerview")
    if not ReaderView.onStartActivityIndicator then
        function ReaderView:onStartActivityIndicator()
            if self.ui.document and self.ui.document.configurable and self.ui.document.configurable.text_wrap == 1 then
                M.busy_start(self.ui)
            end
        end
    end
    if not ReaderView.onStopActivityIndicator then
        function ReaderView:onStopActivityIndicator() M.busy_stop() end
    end
    if Indicator.isStub and not Indicator:isStub() then
        L.wrap(Indicator, "init", function(orig, self) orig(self) end, "ReaderActivityIndicator:init")
    end

    ------------------------------------------------------------------ read timer
    -- "Time is up" title over the expiry message (KOReader's default message gets a Leaf body), and
    -- for the interval dialog a "Read timer · interval" note and "Repeat · 20 min"
    local DEFAULT_TIP = _("Time is up")
    local function timer_text(text, interval_min)
        if text and text ~= "" and text ~= DEFAULT_TIP then
            if text:find("\n") then return text end
            return DEFAULT_TIP .. "\n" .. text
        end
        if interval_min then
            return DEFAULT_TIP .. "\n" .. T_(_("You've been reading for %1 minutes. Time for a break?"), interval_min)
        end
        return DEFAULT_TIP .. "\n" .. T_(_("Your %1 alarm."), os.date("%H:%M"))
    end
    local function interval_minutes()
        local mins
        pcall(function()
            local rt = require("apps/reader/readerui").instance.readtimer
            mins = rt and rt.last_interval_time and math.floor(rt.last_interval_time / 60 + 0.5)
        end)
        return mins and mins > 0 and mins or nil
    end
    local ConfirmBox = require("ui/widget/confirmbox")
    L.wrap(ConfirmBox, "init", function(orig, self, ...)
        if self.ok_text == _("Repeat") and self.cancel_text == _("Done") and not self._leaf_timer then
            self._leaf_timer = true
            local mins = interval_minutes()
            if mins then self.ok_text = T_(_("Repeat · %1 min"), mins) end
            self.text = timer_text(self.text, mins or 0)
            local note = HorizontalGroup:new{ align = "center",
                Kit.TintIcon:new{ icon = "leaf.gr.timer", size_token = "icon-sm", color = T.color("text-3") }, K.hspan("sp-1h"),
                K.text(_("Read timer · interval"), "ui", "fs-sm", "text-3") }
            self._added_widgets = { note }
        end
        return orig(self, ...)
    end, "ConfirmBox:init (read timer)")
    local InfoMessage = require("ui/widget/infomessage")
    L.wrap(InfoMessage, "init", function(orig, self, ...)
        local sym
        pcall(function() sym = require("apps/reader/readerui").instance.readtimer.timer_symbol end)
        if self.name and sym and self.name == sym and not self._leaf_timer then
            self._leaf_timer = true
            self.text = timer_text(self.text)
        end
        return orig(self, ...)
    end, "InfoMessage:init (read timer)")

    ------------------------------------------------------------------ book images: titles for the viewer
    function M.book_image_next(ui)
        local chapter
        pcall(function()
            local page = ui:getCurrentPage()
            chapter = ui.toc and ui.toc:getTocTitleByPage(page)
        end)
        local title = ui.doc_props and ui.doc_props.display_title
        return { title = title or _("Image"), sub = chapter and chapter ~= "" and T_(_("Image in book · %1"), chapter) or _("Image in book"),
            paper = true }
    end
    L.wrap(ReaderHighlight, "onHold", function(orig, self, arg, ges)
        local IV = require("leaf/imageviewer")
        IV.next = M.book_image_next(self.ui)
        local ok, ret = pcall(orig, self, arg, ges)
        IV.next = nil
        if not ok then error(ret, 0) end
        return ret
    end, "ReaderHighlight:onHold (image titles)")

    ------------------------------------------------------------------ generic Leaf sheet with a foot
    --[[ Sheet:new{ title, sub, body = function(sheet, inner) -> widget, foot = function(sheet, inner) -> widget|nil }
         .ko-sheet.gp-sheet: grip, head (no rule), body, then .gp-foot (hairline above, --bg-raised) ]]
    local Sheet = InputContainer:extend{ _leaf_wants_scrim = true, is_always_active = true }
    function Sheet:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(W, H)
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end
    function Sheet:build()
        local W = Screen:getWidth()
        local inner = Kit.inner(W)
        local g = VerticalGroup:new{ align = "left" }
        table.insert(g, sheet_head(inner, { title = self.title, sub = self.sub, parent = self, close = function() self:onClose() end }))
        table.insert(g, self.body(self, inner))
        local f = self.foot and self.foot(self, inner)
        if f then
            table.insert(g, K.line(inner))
            local fh = f:getSize().h + 2 * T.px("sp-3")
            table.insert(g, OverlapGroup:new{ dimen = geom(inner, fh),
                LeftContainer:new{ dimen = geom(inner, fh), HorizontalGroup:new{ K.hspan("sp-4"), f } } })
        else
            table.insert(g, K.vspan("sp-3"))
        end
        local frame, container = Kit.sheet{ content = g }
        self._frame = frame
        self[1] = container
    end
    function Sheet:refresh()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    Sheet.onTapClose = ActionSheet.onTapClose
    Sheet.onClose = ActionSheet.onClose
    Sheet.onShow = ActionSheet.onShow
    Sheet.onCloseWidget = ActionSheet.onCloseWidget
    M.Sheet = Sheet

    -- .gp-foot row: left widgets … right widgets, on the sheet's inner width minus the --sp-4 sides
    local function foot_row(inner, left, right)
        local w = inner - 2 * T.px("sp-4")
        local h = T.px("h-control")
        local g = OverlapGroup:new{ dimen = geom(w, h) }
        if left then table.insert(g, LeftContainer:new{ dimen = geom(w, h), left }) end
        if right then table.insert(g, RightContainer:new{ dimen = geom(w, h), right }) end
        return g
    end
    local function buttons_row(list)
        local g = HorizontalGroup:new{ align = "center" }
        for i, b in ipairs(list) do
            if i > 1 then table.insert(g, K.hspan("sp-2")) end
            table.insert(g, b)
        end
        return g
    end
    M.foot_row, M.buttons_row = foot_row, buttons_row

    -- .ko-section-label inside a sheet: CAPS --fs-xs semibold --text-3, --sp-4 above, --sp-2 below
    local function section(text, inner)
        return VerticalGroup:new{ align = "left", K.vspan("sp-4"),
            HorizontalGroup:new{ K.hspan("sp-5"), K.text(text:upper(), "ui-semibold", "fs-xs", "text-3") }, K.vspan("sp-2") }
    end
    local function help_text(text, inner, bg)
        return VerticalGroup:new{ align = "left", K.vspan("sp-3"),
            HorizontalGroup:new{ K.hspan("sp-5"), K.textbox(text, "ui", "fs-sm", "text-3", inner - 2 * T.px("sp-5"), bg or "bg-raised") },
            K.vspan("sp-3") }
    end
    M.section, M.help_text = section, help_text

    ------------------------------------------------------------------ menu items -> Leaf sheet rows
    -- KOReader menu items (text/text_func, checked_func, enabled_func, callback(touchmenu), sub_item_table)
    -- as rows of a group: checks become toggles, "Label: value" becomes label + value ›. `spec` per item text:
    -- { label, sub, icon, invert (toggle shows the opposite of the check), skip }
    local function item_text(it)
        local t = it.text_func and it.text_func() or it.text or ""
        return t
    end
    function M.menu_rows(sheet, inner, items, specs)
        local rows = {}
        -- the spec's order first (items without one keep KOReader's order, after them)
        local sorted = {}
        for i, it in ipairs(items) do
            local text = item_text(it)
            local spec = specs[(text:gsub(":%s.*$", ""))] or specs[text] or {}
            table.insert(sorted, { it = it, k = spec.order or (100 + i) })
        end
        table.sort(sorted, function(a, b) return a.k < b.k end)
        items = {}
        for _i, e in ipairs(sorted) do table.insert(items, e.it) end
        local fake_tm = { updateItems = function() sheet:refresh() end, closeMenu = function() end }
        for _i, it in ipairs(items) do
            local text = item_text(it)
            local key = text:gsub(":%s.*$", "")
            local spec = specs[key] or specs[text] or {}
            if not spec.skip and not it.sub_item_table then
                local label, value = text:match("^(.-):%s+(.+)$")
                label = spec.label or label or text
                local enabled = it.enabled_func == nil or it.enabled_func()
                if it.enabled == false then enabled = false end
                local o = { icon = spec.icon, label = label, sub = spec.sub, enabled = enabled }
                if it.checked_func then
                    local on = it.checked_func() and true or false
                    if spec.invert then on = not on end
                    o.trailing = require("leaf/widgets/toggle"):new{ on = on, enabled = enabled }
                    o.callback = function()
                        if it.callback then it.callback(fake_tm) end
                        sheet:refresh()
                    end
                else
                    o.value = value and (spec.value_map and spec.value_map[value] or value) or nil
                    if o.value then
                        o.trailing = HorizontalGroup:new{ align = "center", K.text(o.value, "ui", "fs-sm", "text-3"), K.hspan("sp-2"),
                            Kit.TintIcon:new{ icon = "leaf.gr.chevron-right", size_token = "icon-sm", color = T.color("text-3") } }
                    else
                        o.trailing = Kit.TintIcon:new{ icon = "leaf.gr.chevron-right", size_token = "icon-sm", color = T.color("text-3") }
                    end
                    o.callback = function()
                        if spec.close then sheet:onClose() end
                        if it.callback then it.callback(fake_tm) end
                    end
                end
                o.hold = it.hold_callback and function() it.hold_callback(fake_tm) end
                table.insert(rows, grow(inner, o))
            end
        end
        return rows
    end

    ------------------------------------------------------------------ stable page numbers
    local ReaderPageMap = require("apps/reader/modules/readerpagemap")
    local PM_SPECS = {
        [_("About stable page numbers")] = { skip = true },
        [_("Use stable page numbers")] = { order = 1, icon = "leaf.gr.hash", sub = _("In the status bar, Go to and notes") },
        [_("Show stable page numbers in margin")] = { order = 2, icon = "leaf.gr.panel-left", label = _("Show them in the margin") },
        [_("Publisher page numbers source info")] = { order = 3, icon = "leaf.gr.book-open", label = _("Numbers come from") },
        [_("Characters per page")] = { order = 4, icon = "leaf.gr.type", value_map = { [_("disabled")] = _("Off") } },
        [_("Stable page number list")] = { order = 5, icon = "leaf.gr.list-ordered", label = _("Page number list"), close = true },
        [_("Override publisher page numbers")] = { order = 3, icon = "leaf.gr.book-open", label = _("Prefer publisher page numbers"),
            sub = _("When the book has them"), invert = true },
        [_("Prompt when publisher page numbers available")] = { order = 4, icon = "leaf.gr.circle-help", label = _("Ask before using publisher numbers") },
        [_("Page numbers font size")] = { skip = true }, -- the Number size slider under the group
    }
    local NEW_SPECS = {}
    for k, v in pairs(PM_SPECS) do NEW_SPECS[k] = v end
    NEW_SPECS[_("Use stable page numbers")] = { order = 1, icon = "leaf.gr.hash" }
    NEW_SPECS[_("Characters per page")] = { order = 5, icon = "leaf.gr.type", value_map = { [_("disabled")] = _("Off") } }

    function M.pagemap_settings(pm, sub)
        sub = sub or pm._leaf_menu_sub
        if not sub then
            local items = {}
            pm._leaf_menu_sub = nil
            ReaderPageMap._leaf_orig_addToMainMenu(pm, items)
            sub = items.page_map and items.page_map.sub_item_table
            pm._leaf_menu_sub = sub
        end
        if not sub then return end
        local about
        for _i, it in ipairs(sub) do if item_text(it) == _("About stable page numbers") then about = it end end
        UIManager:show(Sheet:new{
            title = _("Stable page numbers"), sub = _("Page numbers that don't change with the font"),
            body = function(sheet, inner)
                local g = VerticalGroup:new{ align = "left" }
                local book, new = {}, nil
                for _i, it in ipairs(sub) do
                    if it.sub_item_table then new = it.sub_item_table else table.insert(book, it) end
                end
                table.insert(g, section(_("This book"), inner))
                table.insert(g, group(M.menu_rows(sheet, inner, book, PM_SPECS), inner))
                if new then
                    table.insert(g, section(_("New books"), inner))
                    table.insert(g, group(M.menu_rows(sheet, inner, new, NEW_SPECS), inner))
                end
                -- Number size (KOReader: "Page numbers font size", 8–20, saved for every book)
                local lo, hi = 8, 20
                local function set_size(v)
                    v = math.max(lo, math.min(hi, math.floor(v + 0.5)))
                    pm.label_font_size = v
                    G_reader_settings:saveSetting("pagemap_label_font_size", v)
                    pm:resetLayout()
                    pm:updateVisibleLabels()
                    UIManager:setDirty(pm.view.dialog, "partial")
                    sheet:refresh()
                end
                local size = pm.label_font_size or pm.label_default_font_size or 14
                table.insert(g, K.vspan("sp-2"))
                table.insert(g, Kit.slider_row{ width = inner, label = _("Number size"), pct = (size - lo) / (hi - lo), value = size, parent = sheet,
                    on_change = function(f, final) if final then set_size(lo + f * (hi - lo)) end end,
                    on_step = function(dir) set_size(size + (dir > 0 and 1 or -1) * math.max(1, math.abs(dir) > 1 and 2 or 1)) end })
                if about then
                    table.insert(g, K.vspan("sp-3"))
                    table.insert(g, group({ grow(inner, { icon = "leaf.gr.info", label = _("About stable page numbers"),
                        trailing = Kit.TintIcon:new{ icon = "leaf.gr.chevron-right", size_token = "icon-sm", color = T.color("text-3") },
                        callback = function() about.callback() end }) }, inner))
                end
                return g
            end,
        })
    end
    ReaderPageMap._leaf_orig_addToMainMenu = ReaderPageMap.addToMainMenu
    L.wrap(ReaderPageMap, "addToMainMenu", function(orig, self, menu_items)
        orig(self, menu_items)
        local item = menu_items.page_map
        if item and item.sub_item_table then
            self._leaf_menu_sub = item.sub_item_table
            local sub = item.sub_item_table
            item.sub_item_table = nil
            item.callback = function() M.pagemap_settings(self, sub) end
        end
    end, "ReaderPageMap:addToMainMenu")

    -- the publisher prompt: title, the edition's pages and source, "Use them" / "Not now"
    L.wrap(ConfirmBox, "init", function(orig, self, ...)
        local q = _("Do you want to use them?")
        local t = self.text or ""
        if not self._leaf_pm and t:sub(-#q) == q and t:find(_("Publisher page numbers available."), 1, true) then
            self._leaf_pm = true
            local first, last = t:match(":%s*(%S+)%s*%-%s*(%S+)")
            local src = t:match("\n([^\n]+)\n\n" .. q:gsub("%p", "%%%0") .. "$")
            local body = _("This book has the page numbers of its print edition")
            if src and src ~= _("N/A") then body = body .. " (" .. src .. (first and (" · " .. T_(_("pages %1–%2"), first, last)) or "") .. ")"
            elseif first then body = body .. " (" .. T_(_("pages %1–%2"), first, last) .. ")" end
            self.text = _("Publisher page numbers available") .. "\n" .. body .. ". " .. _("Use them instead of Leaf's own?")
            self.ok_text = self.ok_text == _("OK") and _("Use them") or self.ok_text
            self.cancel_text = self.cancel_text == _("Cancel") and _("Not now") or self.cancel_text
        end
        return orig(self, ...)
    end, "ConfirmBox:init (publisher page numbers)")
    function M.publisher_prompt(pm)
        UIManager:show(ConfirmBox:new{
            text = pm:showDocumentProvidedInfo(true) .. "\n\n" .. _("Do you want to use them?"),
            ok_callback = function() end,
        })
    end

    -- the page list (.gp-pm page): ← crumbs / "Stable page numbers" ⚙, "Page 12 · 26 on screen" rows
    -- (the current one .sel with a "You are here" pill), foot "Page 12 of the print edition" · Go to a page…
    local function band_w(w, h, content)
        return OverlapGroup:new{ dimen = geom(w, h), Kit.Tap:new{ width = w, height = h, bg = T.color("bg") }, content }
    end
    local PageList = K.Page:extend{}
    function PageList:build()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pm = self.pm
        local ui = pm.ui
        local list = ui.document:getPageMap() or {}
        local cur = ui.document:getCurrentPage()
        local cur_idx = 1
        for k, v in ipairs(list) do if v.page <= cur then cur_idx = k end end
        self.cur_idx = cur_idx
        -- .ko-header--page: crumbs over the title (UI.pageHead)
        local title = ui.doc_props and ui.doc_props.display_title or ""
        local hh = T.px("h-header") + T.px("sp-2")
        local back = K.icon_button("leaf.gr.arrow-left", function() self:onClose() end, self)
        local gear = K.icon_button("leaf.gr.settings-2", function() self:onClose() M.pagemap_settings(pm) end, self)
        local tw = W - back:getSize().w - gear:getSize().w - 3 * T.px("sp-2")
        local col = VerticalGroup:new{ align = "left", K.text(title, "ui", "fs-xs", "text-3", tw),
            K.text(_("Stable page numbers"), "ui-semibold", "fs-lg", "text", tw) }
        local head = OverlapGroup:new{ dimen = geom(W, hh),
            LeftContainer:new{ dimen = geom(W, hh), HorizontalGroup:new{ align = "center", K.hspan("sp-1"), back, K.hspan("sp-1"), col } },
            RightContainer:new{ dimen = geom(W, hh), HorizontalGroup:new{ align = "center", gear, K.hspan("sp-2") } } }
        local top = VerticalGroup:new{ align = "left", band_w(W, T.px("h-status"), Kit.status_strip(W)), head, K.line(W) }
        local foot_label = list[cur_idx] and T_(pm.has_pagemap_document_provided and _("Page %1 of the print edition") or _("Stable page %1"), list[cur_idx].label) or ""
        local go = Kit.icon_label_button{ icon = "leaf.gr.hash", label = _("Go to a page…"), kind = "secondary", callback = function()
            self:onClose()
            ui:handleEvent(Event:new("ShowGotoDialog"))
        end }
        local fh = go:getSize().h + 2 * T.px("sp-3")
        local foot = VerticalGroup:new{ K.line(W), OverlapGroup:new{ dimen = geom(W, fh),
            Kit.Tap:new{ width = W, height = fh, bg = T.color("bg-raised") },
            LeftContainer:new{ dimen = geom(W, fh), HorizontalGroup:new{ K.hspan("sp-4"), K.text(foot_label, "ui", "fs-sm", "text-3") } },
            RightContainer:new{ dimen = geom(W, fh), HorizontalGroup:new{ go, K.hspan("sp-4") } } } }
        local avail = H - top:getSize().h - foot:getSize().h
        local rh = T.px("h-row")
        local per = math.max(1, math.floor(avail / rh))
        self.per = per
        if not self.page_start then self.page_start = math.max(1, cur_idx - math.floor(per / 2)) end
        local rows = VerticalGroup:new{ align = "left" }
        for i = self.page_start, math.min(#list, self.page_start + per - 1) do
            local v = list[i]
            local here = i == cur_idx
            local trailing = HorizontalGroup:new{ align = "center", K.text(T_(_("%1 on screen"), v.page), "ui", "fs-sm", "text-3") }
            if here then
                table.insert(trailing, K.hspan("sp-2"))
                table.insert(trailing, M.pill(_("You are here"), { sm = true }))
            end
            local row = K.row{ width = W, label = T_(_("Page %1"), v.label), label_role = here and "ui-semibold" or "ui", trailing = trailing,
                callback = function()
                    self:onClose()
                    ui.link:addCurrentLocationToStack()
                    if ui.rolling then ui.rolling:onGotoXPointer(v.xpointer) else ui:handleEvent(Event:new("GotoPage", v.page)) end
                end }
            if here then row = OverlapGroup:new{ dimen = geom(W, rh), Kit.Tap:new{ width = W, height = rh, bg = T.color("surface-3") }, row } end
            if i > self.page_start then table.insert(rows, HorizontalGroup:new{ K.hspan("sp-5"), K.line(W - T.px("sp-5")) }) end
            table.insert(rows, row)
        end
        self.n = #list
        self:frame(VerticalGroup:new{ align = "left", top, rows }, foot)
        self.ges_events = { Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } } }
    end
    function PageList:onSwipe(arg, ges)
        local d = ges.direction
        if d == "west" or d == "north" then self.page_start = math.min(math.max(1, self.n - self.per + 1), self.page_start + self.per)
        elseif d == "east" or d == "south" then self.page_start = math.max(1, self.page_start - self.per)
        else return end
        self:rebuild()
        return true
    end
    M.PageList = PageList
    L.wrap(ReaderPageMap, "onShowPageList", function(orig, self)
        UIManager:show(PageList:new{ pm = self })
        return true
    end, "ReaderPageMap:onShowPageList")

    ------------------------------------------------------------------ perception expander
    -- .ko-pill--current: --fs-2xs semibold --text, --accent hairline outline, no fill; sm = 16px high
    function M.pill(text, o)
        o = o or {}
        local t = K.text(text, "ui-semibold", "fs-2xs", "text")
        local h = o.sm and Screen:scaleBySize(16 * T.scale) or T.px("h-badge")
        local pad = T.px(o.sm and "sp-1h" or "sp-2")
        local hair = T.px("hairline")
        return FrameContainer:new{ bordersize = hair, color = T.color("accent"), radius = math.floor(h / 2), padding = 0,
            padding_left = pad - hair, padding_right = pad - hair,
            CenterContainer:new{ dimen = geom(t:getSize().w, h - 2 * hair), t } }
    end

    local function pe_sheet(pe)
        local v = { on = pe.is_enabled and true or false, thick = pe.line_thickness or 2, margin = pe.margin or 0.1,
            dark = math.floor((pe.line_color_intensity or 0.3) * 10 + 0.5), shift = pe.shift_each_pages or 100 }
        local RANGES = { thick = { 1, 8 }, margin = { 0, 0.37 }, dark = { 1, 10 }, shift = { 0, 500 } }
        local function frac(k) local r = RANGES[k] return (v[k] - r[1]) / (r[2] - r[1]) end
        local function set(k, f)
            local r = RANGES[k]
            local x = r[1] + f * (r[2] - r[1])
            if k == "margin" then x = math.floor(x * 100 + 0.5) / 100 else x = math.floor(x + 0.5) end
            v[k] = x
        end
        local sheet
        sheet = Sheet:new{
            title = _("Perception expander"), sub = _("Speed reading guides"),
            body = function(sh, inner)
                local g = VerticalGroup:new{ align = "left", K.vspan("sp-1") }
                table.insert(g, group({ grow(inner, { icon = "leaf.gr.columns-2", label = _("Show guide lines"),
                    trailing = require("leaf/widgets/toggle"):new{ on = v.on }, callback = function() v.on = not v.on sh:refresh() end }) }, inner))
                table.insert(g, section(_("Lines"), inner))
                local function slider(k, label, shown, unit, step)
                    return Kit.slider_row{ width = inner, label = label, pct = frac(k), value = shown, unit = unit, parent = sh,
                        on_change = function(f, final) set(k, f) if final then sh:refresh() end end,
                        on_step = function(dir)
                            local r = RANGES[k]
                            v[k] = math.max(r[1], math.min(r[2], v[k] + dir * step))
                            sh:refresh()
                        end }
                end
                table.insert(g, slider("thick", _("Thickness"), v.thick, "px", 1))
                table.insert(g, slider("margin", _("From edges"), math.floor(v.margin * 100 + 0.5), "%", 0.01))
                table.insert(g, slider("dark", _("Darkness"), v.dark, "/10", 1))
                table.insert(g, slider("shift", _("Move in after"), v.shift, "pg", 10))
                table.insert(g, help_text(_("Every time you read that many pages the guides move 3% closer together, up to 37% from each edge. Set it to 0 to keep them still."), inner))
                table.insert(g, group({ grow(inner, { icon = "leaf.gr.info", label = _("About perception expander"),
                    trailing = Kit.TintIcon:new{ icon = "leaf.gr.chevron-right", size_token = "icon-sm", color = T.color("text-3") },
                    callback = function()
                        UIManager:show(require("ui/widget/infomessage"):new{ text = _("For more information see wiki page Perception Expander Plugin") })
                    end }) }, inner))
                table.insert(g, K.vspan("sp-1"))
                return g
            end,
            foot = function(sh, inner)
                return foot_row(inner,
                    Kit.button{ label = _("Cancel"), kind = "ghost", callback = function() sh:onClose() end, parent = sh },
                    Kit.button{ label = _("Apply"), kind = "primary", parent = sh, callback = function()
                        sh:onClose()
                        pe.is_enabled = v.on
                        pe:saveSettings({ tostring(v.thick), tostring(v.margin), tostring(v.dark), tostring(v.shift) })
                        UIManager:setDirty(pe.view and pe.view.dialog or "all", "ui")
                    end })
            end,
        }
        UIManager:show(sheet)
    end
    M.perception_sheet = pe_sheet

    -- the banner shown when the guides are turned on: help + Settings
    local Banner = InputContainer:extend{ is_always_active = true }
    function Banner:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(W, H)
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        local f = { icon = self.icon, banner = self.text, exit = self.button }
        local fake = { ui = {} }
        local b = banner_widget(fake, nil, f)
        if b._leaf_btn then b._leaf_btn.callback = function() UIManager:close(self) if self.callback then self.callback() end end end
        self._b = b
        local sz = b:getSize()
        self._x = math.floor((W - sz.w) / 2)
        self._y = H - Screen:scaleBySize(56 * T.scale) - sz.h
        self[1] = b
    end
    function Banner:paintTo(bb, x, y) self[1]:paintTo(bb, x + self._x, y + self._y) end
    function Banner:onTapClose(arg, ges)
        local btn = self._b._leaf_btn
        if btn and btn.dimen and ges.pos:intersectWith(btn.dimen) then btn.callback() return true end
        UIManager:close(self)
        return false
    end
    function Banner:onShow() UIManager:setDirty(self, "ui", self._b.dimen) return true end
    function Banner:onCloseWidget() UIManager:setDirty(nil, "ui", self._b.dimen) end
    M.Banner = Banner
    function M.perception_banner(pe)
        UIManager:show(Banner:new{ icon = "leaf.gr.columns-2", button = _("Settings"),
            text = _("Perception expander · read each line between the guides, without moving your eyes to the edges."),
            callback = function() pe:showSettingsDialog() end })
    end

    local function hook_perception(pe)
        local cls = getmetatable(pe)
        if not cls or cls._leaf_hooked or type(cls.showSettingsDialog) ~= "function" then return end
        cls._leaf_hooked = true
        L.wrap(cls, "showSettingsDialog", function(orig, self) pe_sheet(self) end, "PerceptionExpander:showSettingsDialog")
        -- guide lines in --page-ink (the plugin's grey becomes the page ink at the chosen darkness)
        L.wrap(cls, "createUI", function(orig, self, ...)
            orig(self, ...)
            local lw = self.left_line and self.left_line[1]
            if lw then
                local ink = T.gray and T.gray("page-ink") or 0x22
                local level = self.line_color_intensity or 0.3
                lw.background = Blitbuffer.Color8(math.floor(0xff - (0xff - ink) * level + 0.5))
            end
        end, "PerceptionExpander:createUI")
    end
    L.wrap(ReaderUI, "init", function(orig, self, ...)
        orig(self, ...)
        if self.perceptionexpander then pcall(hook_perception, self.perceptionexpander) end
    end, "ReaderUI:init (perception expander)")

    ------------------------------------------------------------------ style tweaks: tweak info (hold)
    local ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
    local Font = require("ui/font")
    local function mono(size_token) return Font:getFace("infont", T.fs(size_token or "fs-sm")) end
    local function upvalue(fn, wanted)
        local i = 1
        while fn do
            local name, value = debug.getupvalue(fn, i)
            if not name then return end
            if name == wanted then return value end
            i = i + 1
        end
    end
    local TweakInfoWidget = upvalue(ReaderStyleTweak.init, "TweakInfoWidget")
    -- "Text › Hyphenation": the categories above a tweak in css_tweaks.lua
    local function tweak_path(id)
        local ok, CssTweaks = pcall(require, "ui/data/css_tweaks")
        if not ok then return end
        local function walk(t, path)
            for _i, e in ipairs(t) do
                if type(e) == "table" then
                    if e.id == id then return path end
                    if e.title and #e > 0 then
                        local p = { unpack(path) }
                        table.insert(p, e.title)
                        local r = walk(e, p)
                        if r then return r end
                    end
                end
            end
        end
        local r = walk(CssTweaks, {})
        return r and #r > 0 and table.concat(r, " › ") or nil
    end
    -- the CSS block (.gp-code): --surface-2, --r-md, mono --fs-sm, a copy button in the corner
    local function code_block(text, w, on_copy, parent)
        local pad = T.px("sp-3")
        local copy = on_copy and K.icon_button("leaf.gr.copy", on_copy, parent, { size = "icon-sm" })
        local cw = copy and copy:getSize().w or 0
        local tb = TextBoxWidget:new{ text = text, face = mono("fs-sm"), width = w - T.px("sp-4") - math.max(T.px("sp-10"), cw),
            fgcolor = T.color("text"), bgcolor = T.color("surface-2"), para_direction_rtl = false }
        local h = tb:getSize().h + 2 * pad
        local box = OverlapGroup:new{ dimen = geom(w, h),
            Kit.Tap:new{ width = w, height = h, bg = T.color("surface-2"), radius = T.px("r-md") },
            LeftContainer:new{ dimen = geom(w, h), HorizontalGroup:new{ K.hspan("sp-4"), tb } } }
        if copy then
            table.insert(box, RightContainer:new{ dimen = geom(w, cw + 2 * T.px("sp-1h") - T.px("sp-2")),
                HorizontalGroup:new{ copy, K.hspan(T.px("sp-1h") - T.px("sp-2")) } })
        end
        return box
    end
    if TweakInfoWidget then
        local function build_info(self)
            local W = Screen:getWidth()
            local inner = Kit.inner(W)
            local tweak = self.tweak or {}
            local path = tweak_path(tweak.id)
            local g = VerticalGroup:new{ align = "left" }
            table.insert(g, sheet_head(inner, { title = tweak.title or "", sub = path and T_(_("Style tweak · %1"), path) or _("Style tweak"),
                parent = self, close = function() UIManager:close(self) end }))
            local cw = inner - 2 * T.px("sp-4")
            local body = VerticalGroup:new{ align = "left" }
            if tweak.description then
                table.insert(body, K.vspan("sp-3"))
                table.insert(body, K.textbox(tweak.description, "ui", "fs-sm", "text-3", cw, "bg-raised"))
            end
            local css = tweak.css
            if not css and tweak.css_path then
                local f = io.open(tweak.css_path, "r")
                if f then css = f:read("*all") f:close() end
            end
            self.css_text = require("util").trim(css or "")
            table.insert(body, K.vspan("sp-3"))
            table.insert(body, code_block(self.css_text, cw, Device:hasClipboard() and function() self:copyTextToClipboard(self.css_text) end, self))
            table.insert(body, K.vspan("sp-3"))
            table.insert(g, HorizontalGroup:new{ K.hspan("sp-4"), body })
            local rows = {
                grow(inner, { icon = "leaf.gr.globe", label = _("Use on all books"), sub = _("Otherwise only on this book"),
                    trailing = require("leaf/widgets/toggle"):new{ on = self.is_global_default and true or false },
                    callback = function()
                        self.toggle_global_default_callback()
                        self.is_global_default = not self.is_global_default
                        build_info(self)
                        UIManager:setDirty(self, "ui")
                    end }),
                grow(inner, { icon = "leaf.gr.hand", label = _("Show in the gesture action list"),
                    trailing = require("leaf/widgets/toggle"):new{ on = self.is_tweak_in_dispatcher and true or false },
                    callback = function()
                        self.toggle_tweak_in_dispatcher_callback()
                        self.is_tweak_in_dispatcher = not self.is_tweak_in_dispatcher
                        build_info(self)
                        UIManager:setDirty(self, "ui")
                    end }),
            }
            table.insert(g, group(rows, inner))
            table.insert(g, K.vspan("sp-3"))
            table.insert(g, K.line(inner))
            local close = Kit.button{ label = _("Close"), kind = "primary", parent = self, callback = function() UIManager:close(self) end }
            local fh = close:getSize().h + 2 * T.px("sp-3")
            table.insert(g, OverlapGroup:new{ dimen = geom(inner, fh),
                LeftContainer:new{ dimen = geom(inner, fh), HorizontalGroup:new{ K.hspan("sp-4"),
                    self.is_global_default and M.pill(_("On in all books")) or K.hspan(0) } },
                RightContainer:new{ dimen = geom(inner, fh), HorizontalGroup:new{ close, K.hspan("sp-4") } } })
            local frame, container = Kit.sheet{ content = g }
            self._leaf_frame = frame
            self.movable = frame -- KOReader's onTap tests self.movable.dimen
            self[1] = container
        end
        L.wrap(TweakInfoWidget, "init", function(orig, self)
            self._leaf_wants_scrim = true
            if Device:isTouchDevice() then
                self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = geom(Screen:getWidth(), Screen:getHeight()) } }
            end
            self:registerKeyEvents()
            self.layout = {}
            build_info(self)
        end, "TweakInfoWidget:init")
        L.wrap(TweakInfoWidget, "onTap", function(orig, self, arg, ges)
            local f = self._leaf_frame and self._leaf_frame.dimen
            if f and ges.pos:notIntersectWith(f) then UIManager:close(self) end
            return true
        end, "TweakInfoWidget:onTap")
        L.wrap(TweakInfoWidget, "onShow", function(orig, self)
            UIManager:setDirty(self, "ui")
            return true
        end, "TweakInfoWidget:onShow")
        L.wrap(TweakInfoWidget, "onCloseWidget", function(orig, self)
            UIManager:setDirty(nil, "ui")
        end, "TweakInfoWidget:onCloseWidget")
    end
    function M.tweak_info_demo(st)
        if not TweakInfoWidget then return end
        local item = st.tweaks_by_id and st.tweaks_by_id["hyphenate_all_auto"]
        UIManager:show(TweakInfoWidget:new{ tweak = item or { title = "Tweak", css = "* {}" }, is_global_default = true,
            toggle_global_default_callback = function() end, is_tweak_in_dispatcher = false,
            toggle_tweak_in_dispatcher_callback = function() end })
    end

    ------------------------------------------------------------------ style tweaks: book-specific editor
    --[[ The book tweak editor (.gp-twe page): ← "Book · Style tweaks" / "Book style tweak" ↺ ⋮,
         Prettify · CSS snippets … "Ln 6 · 12 lines", the CSS with line numbers (current line on
         --surface-2), foot "Applies only to this book" Close · Apply. KOReader's InputDialog is built
         as usual but not shown: Leaf drives it (its text, its buttons and callbacks); a tap on the CSS
         opens it for typing (keyboard, find, go to line), the ⋮ menu lists its other buttons. ]]
    local InputDialog = require("ui/widget/inputdialog")
    local TweakEditor = K.Page:extend{}
    function TweakEditor:build()
        local ed = self.editor
        local W, H = Screen:getWidth(), Screen:getHeight()
        local bt = ed.button_table
        local function by_id(id) return bt and bt:getButtonById(id) end
        local hair = T.px("hairline")
        -- head: back, crumbs over the title, restore (history) + more
        local back = K.icon_button("leaf.gr.arrow-left", function() self:leafAskClose() end, self)
        local actions = HorizontalGroup:new{ align = "center" }
        local reset = by_id("reset")
        if reset then
            table.insert(actions, K.icon_button("leaf.gr.history", function()
                if reset.enabled then reset.callback() end
                UIManager:scheduleIn(0.2, function() self:rebuild() end)
            end, self))
        end
        table.insert(actions, K.icon_button("leaf.more.v", function() self:leafMore() end, self))
        table.insert(actions, K.hspan("sp-2"))
        local book = self.book_title or ""
        local tw = W - back:getSize().w - actions:getSize().w - 2 * T.px("sp-2")
        actions:resetLayout()
        local col = VerticalGroup:new{ align = "left", K.text(book ~= "" and (book .. " › " .. _("Style tweaks")) or _("Style tweaks"), "ui", "fs-xs", "text-3", tw),
            K.text(_("Book style tweak"), "ui-semibold", "fs-lg", "text", tw) }
        local hh = T.px("h-header") + T.px("sp-2")
        local head = OverlapGroup:new{ dimen = geom(W, hh),
            LeftContainer:new{ dimen = geom(W, hh), HorizontalGroup:new{ align = "center", K.hspan("sp-1"), back, K.hspan("sp-1"), col } },
            RightContainer:new{ dimen = geom(W, hh), actions } }
        local top = VerticalGroup:new{ align = "left",
            OverlapGroup:new{ dimen = geom(W, T.px("h-status")), Kit.Tap:new{ width = W, height = T.px("h-status"), bg = T.color("bg") }, Kit.status_strip(W) },
            head, K.line(W) }
        -- tools: Prettify / Use sample / Condense, CSS snippets, Ln n · m lines
        local tweak_b = by_id("editBookTweakButton")
        local css_b = by_id("css_suggestions_button_id")
        local tools = HorizontalGroup:new{ align = "center", K.hspan("sp-4") }
        local pretty
        if tweak_b then
            pretty = Kit.icon_label_button{ icon = "leaf.gr.wand-sparkles", label = tweak_b.text, kind = "secondary", callback = function()
                tweak_b.callback()
                self:rebuild()
            end }
            table.insert(tools, pretty)
            table.insert(tools, K.hspan("sp-2"))
        end
        local snip
        if css_b then
            snip = Kit.icon_label_button{ icon = "leaf.gr.list", label = _("CSS snippets"), kind = "secondary", callback = function() self:leafShowSnippets() end }
            table.insert(tools, snip)
        end
        local it = ed._input_widget
        local cur, total = 1, 1
        pcall(function() cur, total = it:getLineNums() end)
        local pos = K.text(T_(_("Ln %1 · %2 lines"), cur, total), "ui", "fs-xs", "text-3")
        local th = math.max(T.px("h-control"), tools:getSize().h) + 2 * T.px("sp-2")
        tools:resetLayout()
        local toolbar = VerticalGroup:new{ OverlapGroup:new{ dimen = geom(W, th),
            LeftContainer:new{ dimen = geom(W, th), tools },
            RightContainer:new{ dimen = geom(W, th), HorizontalGroup:new{ pos, K.hspan("sp-4") } } }, K.line(W) }
        local top_h = top:getSize().h
        top:resetLayout()
        -- where the snippets popover anchors (the button is painted later)
        if snip and css_b then
            local x = T.px("sp-4") + (pretty and (pretty:getSize().w + T.px("sp-2")) or 0)
            local y = top_h + math.floor((th - snip:getSize().h) / 2)
            self._snip_dimen = Geom:new{ x = x, y = y, w = snip:getSize().w, h = snip:getSize().h }
        end
        -- foot: "Applies only to this book" · Close · Apply
        local save = by_id("save")
        local close = by_id("close")
        local fb = HorizontalGroup:new{ align = "center",
            Kit.button{ label = close and close.text or _("Close"), kind = "ghost", parent = self, callback = function() self:leafAskClose() end },
            K.hspan("sp-2"),
            Kit.button{ label = save and save.text or _("Apply"), kind = "primary", parent = self, enabled = not save or save.enabled,
                callback = function() if save and save.enabled then save.callback() end end } }
        local fh = fb:getSize().h + 2 * T.px("sp-3")
        fb:resetLayout()
        local foot = VerticalGroup:new{ K.line(W), OverlapGroup:new{ dimen = geom(W, fh),
            Kit.Tap:new{ width = W, height = fh, bg = T.color("bg-raised") },
            LeftContainer:new{ dimen = geom(W, fh), HorizontalGroup:new{ K.hspan("sp-4"), K.text(_("Applies only to this book"), "ui", "fs-sm", "text-3") } },
            RightContainer:new{ dimen = geom(W, fh), HorizontalGroup:new{ fb, K.hspan("sp-4") } } } }
        -- the CSS, one row per line: number (--text-3, right-aligned) · code; the cursor's line on --surface-2
        local avail = H - top_h - th - hair - fh - hair
        local face = mono("fs-md") -- KOReader's mono runs small: --fs-md matches the prototype's --fs-sm mono
        local probe = TextWidget:new{ text = "0", face = face }
        local lh = math.floor(probe:getSize().h * 1.1 + 0.5)
        probe:free()
        local text = ed:getInputText() or ""
        local lines = {}
        for l in (text .. "\n"):gmatch("(.-)\n") do table.insert(lines, l) end
        local per = math.max(1, math.floor((avail - 2 * T.px("sp-3")) / lh))
        self.first = math.max(1, math.min(self.first or 1, math.max(1, #lines - per + 1)))
        local doc = VerticalGroup:new{ align = "left", K.vspan("sp-3") }
        local num_w = T.px("sp-6")
        local code_w = W - 2 * T.px("sp-4") - num_w - T.px("sp-3")
        for i = self.first, math.min(#lines, self.first + per - 1) do
            local row = HorizontalGroup:new{ align = "center", K.hspan("sp-4"),
                RightContainer:new{ dimen = geom(num_w, lh), TextWidget:new{ text = tostring(i), face = face, fgcolor = T.color("text-3") } },
                K.hspan("sp-3"),
                LeftContainer:new{ dimen = geom(code_w, lh), TextWidget:new{ text = lines[i] ~= "" and lines[i] or " ", face = face,
                    fgcolor = T.color("text"), max_width = code_w, para_direction_rtl = false } } }
            if i == cur then
                row = OverlapGroup:new{ dimen = geom(W, lh), Kit.Tap:new{ width = W, height = lh, bg = T.color("surface-2") }, row }
            end
            table.insert(doc, row)
        end
        local body = Kit.Tap:new{ width = W, height = avail, content = doc, callback = function() self:leafType() end }
        self:frame(VerticalGroup:new{ align = "left", top, toolbar, body }, foot)
        self.ges_events = { Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } } }
        self.per = per
        self.nlines = #lines
    end
    function TweakEditor:onSwipe(arg, ges)
        if ges.direction == "north" then self.first = (self.first or 1) + self.per
        elseif ges.direction == "south" then self.first = math.max(1, (self.first or 1) - self.per)
        else return end
        self:rebuild()
        return true
    end
    -- .gp-twm popover: INSERT A SNIPPET, one row per category (icon, name, its first entries), a tip;
    -- a category opens its entries (tap inserts, long-press explains). KOReader's own list as fallback.
    local CSS_SUGGESTIONS = upvalue(ReaderStyleTweak.onEditBookTweak, "CSS_SUGGESTIONS")
    local SNIP = {
        [_("Matching elements")] = { icon = "leaf.gr.crosshair" },
        [_("Common classic properties")] = { icon = "leaf.gr.paintbrush", label = _("Common properties") },
        [_("Private CSS properties")] = { icon = "leaf.gr.cpu", label = _("Reader-only properties") },
        [_("Useful 'content:' values")] = { icon = "leaf.gr.quote", label = _("Useful content: values") },
    }
    local function info(text) UIManager:show(require("ui/widget/infomessage"):new{ text = text }) end
    function TweakEditor:leafSnippetPopover(list, title, x, y, sub_level)
        local W = math.min(Screen:scaleBySize(320 * T.scale), Screen:getWidth() - 2 * T.px("sp-4"))
        local inner = W - 2 * T.px("hairline")
        local ed = self.editor
        local pop
        local g = VerticalGroup:new{ align = "left", K.vspan("sp-1"),
            HorizontalGroup:new{ K.hspan("sp-4"), K.text(title:upper(), "ui-semibold", "fs-xs", "text-3") }, K.vspan("sp-1") }
        local tw = inner - 2 * T.px("sp-4") - T.px("icon-md") - T.px("sp-3") - T.px("icon-sm") - T.px("sp-2")
        for _i, sgg in ipairs(list) do
            local name, payload, info_only = sgg[1], sgg[2], sgg[3]
            if not (info_only and not sub_level) then
                local spec = SNIP[name] or {}
                local sub
                if type(payload) == "table" then
                    local names = {}
                    for k = 1, math.min(3, #payload) do table.insert(names, payload[k][1]) end
                    sub = table.concat(names, ", ") .. "…"
                end
                local col = VerticalGroup:new{ align = "left",
                    sub_level and TextWidget:new{ text = name, face = mono("fs-sm"), fgcolor = T.color(info_only and "text-3" or "text"),
                        max_width = tw, para_direction_rtl = false }
                    or K.text(spec.label or name, "ui", "fs-md", "text", tw) }
                if sub then table.insert(col, K.textbox(sub, "ui", "fs-sm", "text-3", tw, "surface", { height = math.floor(2.5 * T.px("sp-4")) })) end
                local ch = col:getSize().h
                col:resetLayout()
                local h = math.max(T.px("h-row-compact"), ch + 2 * T.px("sp-1"))
                local row = OverlapGroup:new{ dimen = geom(inner, h),
                    LeftContainer:new{ dimen = geom(inner, h), HorizontalGroup:new{ align = "center", K.hspan("sp-4"),
                        sub_level and K.hspan(0) or Kit.TintIcon:new{ icon = spec.icon or "leaf.gr.list", size_token = "icon-md", color = T.color("text-2") },
                        sub_level and K.hspan(0) or K.hspan("sp-3"), col } } }
                if type(payload) == "table" then
                    table.insert(row, RightContainer:new{ dimen = geom(inner, h), HorizontalGroup:new{ align = "center",
                        Kit.TintIcon:new{ icon = "leaf.gr.chevron-right", size_token = "icon-sm", color = T.color("text-3") }, K.hspan("sp-3") } })
                end
                table.insert(g, Kit.Tap:new{ width = inner, height = h, content = row,
                    callback = function()
                        if type(payload) == "table" then
                            UIManager:close(pop)
                            self:leafSnippetPopover(payload, spec.label or name, x, y, true)
                        elseif info_only then
                            info(payload)
                        else
                            UIManager:close(pop)
                            ed:addTextToInput(name)
                            self:rebuild()
                        end
                    end,
                    hold_callback = type(payload) == "string" and function() info(payload) end or nil })
            end
        end
        if not sub_level then
            table.insert(g, HorizontalGroup:new{ K.hspan("sp-4"), K.textbox(_("Tip: long-press an entry to see what it does."), "ui", "fs-xs", "text-3",
                inner - 2 * T.px("sp-4"), "surface") })
            table.insert(g, K.vspan("sp-1"))
        end
        pop = Popover:new{ content = VerticalGroup:new{ align = "left", K.hspan(inner), g }, x = x, y = y }
        UIManager:show(pop)
        return pop
    end
    function TweakEditor:leafShowSnippets()
        local d = self._snip_dimen
        if CSS_SUGGESTIONS and d then
            return self:leafSnippetPopover(CSS_SUGGESTIONS, _("Insert a snippet"), d.x, d.y + d.h + T.px("sp-1"))
        end
        local css_b = self.editor.button_table:getButtonById("css_suggestions_button_id")
        if not css_b then return end
        css_b.dimen = self._snip_dimen or css_b.dimen
        local orig_add = self.editor.addTextToInput
        local page = self
        self.editor.addTextToInput = function(ed, t)
            orig_add(ed, t)
            UIManager:scheduleIn(0.1, function() page:rebuild() end)
        end
        css_b.callback()
    end
    function TweakEditor:leafMarkDirty()
        local ed = self.editor
        ed:setInputText(ed:getInputText() .. "\n", true)
        self:rebuild()
    end
    function TweakEditor:leafAskClose()
        local close = self.editor.button_table:getButtonById("close")
        if close then close.callback() else self:onClose() end
    end
    -- typing: KOReader's editor itself, with the keyboard; back here when it closes
    function TweakEditor:leafType()
        local ed = self.editor
        ed._leaf_typing = true
        UIManager:show(ed)
        ed:onShowKeyboard()
    end
    function TweakEditor:leafMore()
        local known = { editBookTweakButton = true, css_suggestions_button_id = true, reset = true, save = true, close = true }
        local rows = {}
        for _i, row in ipairs(self.editor.buttons or {}) do
            for _j, b in ipairs(row) do
                if b.id ~= nil and known[b.id] then -- luacheck: ignore
                elseif b.text or b.text_func then
                    local text = b.text_func and b.text_func() or b.text
                    if text and text ~= "" and not text:match("^%s*$") then
                        table.insert(rows, { icon = "leaf.gr.zap", label = text, callback = function(sh)
                            UIManager:close(sh)
                            self:leafType()
                            if b.callback then b.callback() end
                        end })
                    end
                end
            end
        end
        table.insert(rows, 1, { icon = "leaf.gr.pencil", label = _("Edit with the keyboard"), callback = function(sh) UIManager:close(sh) self:leafType() end })
        UIManager:show(ActionSheet:new{ title = _("Book style tweak"), groups = { rows } })
    end
    function TweakEditor:onClose()
        self:leafAskClose()
        return true
    end
    function TweakEditor:onCloseWidget()
        M._tweak_editor = nil
        UIManager:setDirty(nil, "full")
    end
    M.TweakEditor = TweakEditor

    -- the editor's own closes (Apply, Discard, Save) also close the Leaf page; typing returns to it
    L.wrap(UIManager, "close", function(orig, self, widget, ...)
        local page = type(widget) == "table" and widget._leaf_tweak_page
        if page then
            local in_stack = false
            for _i, w in ipairs(self._window_stack) do if w.widget == widget then in_stack = true break end end
            local ret = in_stack and orig(self, widget, ...) or nil
            if not (widget._leaf_typing and in_stack) then
                widget._leaf_tweak_page = nil
                orig(self, page)
            else
                -- leaving the keyboard editor: Apply closes the page too, anything else comes back to it
                widget._leaf_typing = nil
                UIManager:nextTick(function()
                    if widget.save_callback_called then
                        widget._leaf_tweak_page = nil
                        orig(self, page)
                    else
                        page:rebuild()
                    end
                end)
            end
            return ret
        end
        return orig(self, widget, ...)
    end, "UIManager:close (book tweak editor)")

    L.wrap(ReaderStyleTweak, "onEditBookTweak", function(orig, self, touchmenu_instance)
        local editor
        local show = UIManager.show
        UIManager.show = function(um, w, ...)
            if not editor and type(w) == "table" and w.save_callback and w.fullscreen and getmetatable(w) and w.getInputText == InputDialog.getInputText then
                editor = w
                -- the caller shows the keyboard right after: not for the Leaf page
                w.onShowKeyboard = function(ed) ed.onShowKeyboard = nil end
                return
            end
            return show(um, w, ...)
        end
        local ok, err = pcall(orig, self, touchmenu_instance)
        UIManager.show = show
        if not ok then error(err, 0) end
        if not editor then return end
        editor.close_unsaved_confirm_text = _("Unsaved changes") .. "\n" .. _("You changed this book's tweak. Apply it before closing?")
        local page = TweakEditor:new{ editor = editor, book_title = self.ui.doc_props and self.ui.doc_props.display_title }
        editor._leaf_tweak_page = page
        M._tweak_editor = page
        UIManager:show(page)
    end, "ReaderStyleTweak:onEditBookTweak")
end

return M
