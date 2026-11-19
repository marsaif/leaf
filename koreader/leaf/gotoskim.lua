--[[
    Leaf "Go to" and "Skim" sheets (prototype overlays "goto" and "skim", js/screens/reader-panels.js).

    Go to (ReaderGoto:onShowGotoDialog): a 480px bottom sheet
      head:   Go to        [Page | Percent]  ⋮  ×
      field:  big value (the current page, greyed, until you type) + caret + "of 343" / "%"
      hint:   "You are on page 12 · Chapter I"  /  "↳ Page 40 · Chapter III"  /  "Enter a page between 1 and 343"
      keypad: 1-9, (. in percent mode), 0, ⌫
      foot:   Skim                                   Cancel  [Go]
    "⋮" opens KOReader's own dialog (pin / go to pinned page, relative +n / -n jumps, page labels,
    [x]y flow syntax). Books with reference page labels or hidden flows open KOReader's dialog
    directly, as those need its text syntax.

    Skim (SkimToWidget): a bottom sheet
      head:   Page 12 of 343 / chapter      [↶ Back to 12]  🔖  ×
      track:  chapter ticks, bookmark marks, a large slider (tap or drag; jumps on release)
      row:    |◁ Chapter · « −10 · ‹ −1 · +1 › · +10 » · Chapter ▷|
      row:    🔖 Previous bookmark · 🔖 Next bookmark
    Every KOReader action stays: the title opens Go to (hold: back to where you started), the
    chapter buttons jump to the first / last page on hold, the bookmark buttons to the first / last
    bookmark on hold, the bookmark toggle shows the bookmark list on hold. Navigation goes through
    SkimToWidget's own goToPage / goToByEvent / goToOrigPage (location stack included).
    Devices without a touch screen keep KOReader's widgets (keyboard focus layout).
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
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

local function use_leaf()
    return Device:isTouchDevice()
end

function M.apply(L)
    local T = L.T
    local Kit = require("leaf/widgets/kit")
    local geom = Kit.geom
    local hair = T.px("hairline")

    local function chapter_of(ui, page)
        local t = ui.toc and ui.toc.getTocTitleByPage and ui.toc:getTocTitleByPage(page) or ""
        return t or ""
    end

    -- a bordered key / button (.rd-keypad button, .rd-skim-btn)
    local function boxed(o)
        return Kit.Tap:new{ width = o.width, height = o.height, content = CenterContainer:new{ dimen = geom(o.width, o.height), o.content },
            bg = T.color(o.fn and "surface-2" or "surface"), border = hair, border_color = T.color("border"), radius = T.px("r-md"),
            callback = o.callback, hold_callback = o.hold_callback }
    end

    ------------------------------------------------------------------ GO TO
    local Goto = InputContainer:extend{ ui = nil, mode = "page", value = "", _leaf_wants_scrim = true }

    function Goto:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end

    function Goto:target()
        local total = self.ui.document:getPageCount()
        local v = tonumber(self.value)
        if self.value == "" or not v then return nil end
        if self.mode == "page" then
            if v < 1 or v > total or v ~= math.floor(v) then return nil end
            return v
        end
        if v < 0 or v > 100 then return nil end
        return math.max(1, math.min(total, math.floor(v / 100 * total + 0.5)))
    end

    function Goto:leaf_key(k)
        if k == "del" then
            self.value = self.value:sub(1, -2)
        elseif #self.value < 5 then
            if k == "." and (self.mode ~= "pct" or self.value:find("%.")) then return end
            self.value = self.value .. k
        end
        self:refresh()
    end

    function Goto:go()
        local t = self:target()
        if not t then return end
        local ui = self.ui
        UIManager:close(self)
        if ui.link then ui.link:addCurrentLocationToStack() end
        if self.mode == "pct" then
            ui:handleEvent(Event:new("GotoPercent", tonumber(self.value)))
        else
            ui:handleEvent(Event:new("GotoPage", t))
        end
    end

    function Goto:build()
        local ui = self.ui
        local W = Screen:getWidth()
        local sheet_w = math.min(W, Screen:scaleBySize(480 * T.scale))
        local inner = Kit.inner(sheet_w)
        local pad = T.px("sp-5")
        local total = ui.document:getPageCount()
        local cur = ui:getCurrentPage()

        -- head: Go to · [Page | Percent] · ⋮ · ×
        local LeafSeg = require("leaf/widgets/seg")
        local seg = LeafSeg:new{ width = Screen:scaleBySize(136 * T.scale), selected = self.mode,
            items = { { label = _("Page"), key = "page" }, { label = _("Percent"), key = "pct" } },
            on_select = function(key) self.mode = key; self.value = ""; self:refresh() end }
        local more = Kit.icon_button("leaf.more.v", function()
            UIManager:close(self)
            M.orig_goto(ui.gotopage)
        end, self)
        local head = Kit.head{ width = inner, title = _("Go to"), parent = self,
            actions = { seg, HorizontalSpan:new{ width = T.px("sp-1") }, more },
            on_close = function() UIManager:close(self) end }

        -- field
        local body_w = inner - 2 * pad
        local empty = self.value == ""
        local t = self:target()
        local bad = not empty and not t
        local shown = empty and (self.mode == "page" and tostring(cur) or tostring(math.floor(cur / total * 100 + 0.5))) or self.value
        local field_h = Screen:scaleBySize(72 * T.scale)
        local val = TextWidget:new{ text = shown, face = L.face("ui-semibold", "fs-3xl"), fgcolor = T.color(empty and "text-3" or "text") }
        local caret = require("ui/widget/linewidget"):new{ dimen = geom(T.px("bw-lg"), Screen:scaleBySize(34 * T.scale)), background = T.color("accent") }
        local unit = TextWidget:new{ text = self.mode == "page" and T_(_("of %1"), total) or "%", face = L.face("ui", "fs-md"), fgcolor = T.color("text-3") }
        local field_row = HorizontalGroup:new{ align = "center", val, HorizontalSpan:new{ width = T.px("sp-half") }, caret,
            HorizontalSpan:new{ width = T.px("sp-2") }, unit }
        local field = Kit.Tap:new{ width = body_w, height = field_h, radius = T.px("r-lg"), bg = T.color("surface"),
            border = hair, border_color = T.color(bad and "danger" or "border-strong"),
            content = CenterContainer:new{ dimen = geom(body_w, field_h), field_row } }

        -- hint
        local hint_text, hint_icon
        if empty then
            local ch = chapter_of(ui, cur)
            hint_text = ch ~= "" and T_(_("You are on page %1 · %2"), cur, ch) or T_(_("You are on page %1"), cur)
        elseif t then
            local ch = chapter_of(ui, t)
            hint_text = ch ~= "" and T_(_("Page %1 · %2"), t, ch) or T_(_("Page %1"), t)
            hint_icon = "leaf.mi.goto"
        else
            hint_text = self.mode == "page" and T_(_("Enter a page between 1 and %1"), total) or _("Enter a value between 0 and 100")
        end
        local hint_g = HorizontalGroup:new{ align = "center" }
        if hint_icon then
            table.insert(hint_g, Kit.icon(hint_icon, "icon-sm"))
            table.insert(hint_g, HorizontalSpan:new{ width = T.px("sp-1h") })
        end
        table.insert(hint_g, TextWidget:new{ text = hint_text, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"),
            max_width = body_w - T.px("icon-sm") - T.px("sp-2") })
        local hint = CenterContainer:new{ dimen = geom(body_w, Screen:scaleBySize(34 * T.scale)), hint_g }

        -- keypad
        local gap = T.px("sp-2")
        local kw = math.floor((body_w - 2 * gap) / 3)
        local kh = Screen:scaleBySize(52 * T.scale)
        local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", self.mode == "pct" and "." or "", "0", "del" }
        local pad_g = VerticalGroup:new{ align = "left" }
        local rowg
        for i, k in ipairs(keys) do
            if (i - 1) % 3 == 0 then
                if rowg then
                    table.insert(pad_g, rowg)
                    table.insert(pad_g, VerticalSpan:new{ width = gap })
                end
                rowg = HorizontalGroup:new{ align = "center" }
            else
                table.insert(rowg, HorizontalSpan:new{ width = gap })
            end
            if k == "" then
                table.insert(rowg, HorizontalSpan:new{ width = kw })
            else
                local content = k == "del" and Kit.icon("leaf.kb.backspace", "icon-lg")
                    or TextWidget:new{ text = k, face = L.face("ui-medium", "fs-xl") }
                table.insert(rowg, boxed{ width = kw, height = kh, content = content, fn = k == "del",
                    callback = function() self:leaf_key(k) end,
                    hold_callback = k == "del" and function() self.value = ""; self:refresh() end or nil })
            end
        end
        table.insert(pad_g, rowg)

        -- foot: Skim · · · Cancel [Go]
        local foot_h = T.px("h-control") + 2 * T.px("sp-3")
        local fl = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = T.px("sp-4") },
            Kit.icon_label_button{ icon = "leaf.rd.columns", label = _("Skim"), kind = "ghost", callback = function()
                UIManager:close(self)
                ui.gotopage:onShowSkimtoDialog()
            end } }
        local fr = HorizontalGroup:new{ align = "center",
            Kit.button{ label = _("Cancel"), kind = "ghost", parent = self, callback = function() UIManager:close(self) end },
            HorizontalSpan:new{ width = T.px("sp-2") },
            Kit.button{ label = _("Go"), kind = "primary", parent = self, enabled = t ~= nil, callback = function() self:go() end },
            HorizontalSpan:new{ width = T.px("sp-4") } }
        local foot = OverlapGroup:new{ dimen = geom(inner, foot_h),
            LeftContainer:new{ dimen = geom(inner, foot_h), fl },
            RightContainer:new{ dimen = geom(inner, foot_h), fr } }

        local body = VerticalGroup:new{ align = "left",
            head,
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, VerticalGroup:new{ align = "left",
                VerticalSpan:new{ width = T.px("sp-2") }, field, hint, pad_g, VerticalSpan:new{ width = T.px("sp-3") } } },
            Kit.line(inner),
            foot }
        local frame, container = Kit.sheet{ width = sheet_w, content = body }
        self._frame = frame
        self[1] = container
    end

    function Goto:refresh()
        self:build()
        UIManager:setDirty(self, "ui", self._frame.dimen)
    end
    function Goto:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then UIManager:close(self) end
        return true
    end
    function Goto:onClose()
        UIManager:close(self)
        return true
    end
    function Goto:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function Goto:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end
    M.Goto = Goto

    local ReaderGoto = require("apps/reader/modules/readergoto")
    M.orig_goto = ReaderGoto.onShowGotoDialog
    L.wrap(ReaderGoto, "onShowGotoDialog", function(orig, self)
        local doc = self.document or self.ui.document
        local labels = self.ui.pagemap and self.ui.pagemap:wantsPageLabels()
        if not use_leaf() or labels or (doc.hasHiddenFlows and doc:hasHiddenFlows()) then
            return orig(self)
        end
        UIManager:show(Goto:new{ ui = self.ui })
        return true
    end, "ReaderGoto:onShowGotoDialog")

    ------------------------------------------------------------------ SKIM
    local SkimToWidget = require("ui/widget/skimtowidget")
    local LeafSlider = require("leaf/widgets/slider")

    -- the skim slider is bigger than the standard one: 6px track, 28px knob (.rd-skim-track)
    local SkimSlider = LeafSlider:extend{}
    function SkimSlider:init()
        LeafSlider.init(self)
        self.knob_r = math.floor(Screen:scaleBySize(28 * T.scale) / 2)
    end
    function SkimSlider:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local x0, tw = self:_track()
        local th = Screen:scaleBySize(6 * T.scale)
        local cy = y + math.floor(self.dimen.h / 2)
        local r = math.floor(th / 2)
        local frac = math.max(0, math.min(1, self.pct))
        if self.invert then frac = 1 - frac end
        bb:paintRoundedRect(x0, cy - r, tw, th, T.color("surface-3"), r)
        local kx = x0 + math.floor(tw * frac + 0.5)
        if self.invert then
            if kx < x0 + tw then bb:paintRoundedRect(kx, cy - r, x0 + tw - kx, th, T.color("accent"), r) end
        elseif kx > x0 then
            bb:paintRoundedRect(x0, cy - r, kx - x0, th, T.color("accent"), r)
        end
        -- chapter ticks over the track (.rd-scrub-ticks: 1px x 10px, --border-strong)
        if self.ticks then
            local tick_h = Screen:scaleBySize(10 * T.scale)
            for _i, f in ipairs(self.ticks) do
                if self.invert then f = 1 - f end
                bb:paintRect(x0 + math.floor(tw * f + 0.5), cy - math.floor(tick_h / 2), math.max(1, hair), tick_h, T.color("border-strong"))
            end
        end
        bb:paintCircle(kx, cy, self.knob_r, T.color("surface"))
        bb:paintCircle(kx, cy, self.knob_r, T.color("accent"), T.px("bw-lg"))
    end
    function SkimSlider:_from(ges, final)
        if not ges or not ges.pos then return true end
        local x0, tw = self:_track()
        local frac = tw > 0 and (ges.pos.x - x0) / tw or 0
        frac = math.max(0, math.min(1, frac))
        if self.invert then frac = 1 - frac end
        if self.on_change then self.on_change(frac, final) end
        return true
    end

    -- bookmark marks above the track (.rd-skim-bms: 8x11 bookmark shapes in --text-2)
    local Marks = Widget:extend{}
    function Marks:init()
        self.dimen = geom(self.width, self.height)
        local s = Screen:scaleBySize(11 * T.scale)
        self._icon = IconWidget:new{ icon = "leaf.rd.bookmarked", width = s, height = s, alpha = true }
    end
    function Marks:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local s = self._icon:getSize().w
        for _i, f in ipairs(self.fracs or {}) do
            if self.invert then f = 1 - f end
            self._icon:paintTo(bb, x + self.x0 + math.floor(self.tw * f + 0.5) - math.floor(s / 2), y)
        end
    end

    local function bookmark_pages(ui)
        local out = {}
        for _i, a in ipairs(ui.annotation and ui.annotation.annotations or {}) do
            if not a.drawer then
                local p = a.pageno or a.page
                if ui.rolling and type(a.page) == "string" then p = ui.document:getPageFromXPointer(a.page) end
                if type(p) == "number" then table.insert(out, p) end
            end
        end
        return out
    end

    function SkimToWidget:leafBuild()
        local ui = self.ui
        local W = Screen:getWidth()
        local position = G_reader_settings:readSetting("skim_dialog_position")
        local sheet_w = math.min(W, Screen:scaleBySize(640 * T.scale))
        local inner = Kit.inner(sheet_w)
        local pad = T.px("sp-5")
        local total = self.page_count
        local cur = self.curr_page
        local invert = ui.view:shouldInvertBiDiLayoutMirroring()

        -- head
        local label = tostring(cur)
        if ui.pagemap and ui.pagemap:wantsPageLabels() then label = ui.pagemap:getCurrentPageLabel(true) or label end
        local title = HorizontalGroup:new{ align = "bottom",
            TextWidget:new{ text = T_(_("Page %1"), label), face = L.face("ui-semibold", "fs-head") },
            TextWidget:new{ text = " " .. T_(_("of %1"), total), face = L.face("ui", "fs-head"), fgcolor = T.color("text-3") } }
        local ch = chapter_of(ui, cur)
        local actions = {}
        if self.orig_page_added_to_stack and self.leaf_orig_page and self.leaf_orig_page ~= cur then
            local chip_text = TextWidget:new{ text = T_(_("Back to %1"), self.leaf_orig_page), face = L.face("ui-medium", "fs-sm") }
            local chip_g = HorizontalGroup:new{ align = "center", Kit.icon("leaf.sk.back", "icon-sm"), HorizontalSpan:new{ width = T.px("sp-1h") }, chip_text }
            local cw = chip_g:getSize().w + 2 * T.px("sp-3")
            chip_g:resetLayout()
            local chh = T.px("h-chip")
            table.insert(actions, Kit.Tap:new{ width = cw, height = chh, radius = math.floor(chh / 2),
                bg = T.color("surface"), border = hair, border_color = T.color("border-strong"),
                content = CenterContainer:new{ dimen = geom(cw, chh), chip_g },
                callback = function() self:goToOrigPage() end })
            table.insert(actions, HorizontalSpan:new{ width = T.px("sp-1") })
        end
        local marked = ui.view.dogear_visible
        local bm_btn = Kit.icon_button(marked and "leaf.sk.bmcheck" or "leaf.rd.bookmark", function()
            ui:handleEvent(Event:new("ToggleBookmark"))
            self:update()
        end, self)
        bm_btn.hold_callback = function()
            ui:handleEvent(Event:new("ShowBookmark"))
            UIManager:close(self)
        end
        table.insert(actions, bm_btn)
        local head = Kit.head{ width = inner, title_widget = title, sub = ch ~= "" and ch or nil, actions = actions, parent = self,
            on_title_tap = function() if self.callback_switch_to_goto then self.callback_switch_to_goto() end end,
            on_title_hold = function() self:goToOrigPage() end,
            on_close = function() self:onClose() end }

        -- track
        local track_w = inner - 2 * pad
        local slider
        slider = SkimSlider:new{ width = track_w, pct = total > 1 and (cur - 1) / (total - 1) or 0, show_parent = self, invert = invert,
            on_change = function(frac, final)
                local page = math.max(1, math.min(total, math.floor(1 + frac * (total - 1) + 0.5)))
                if final then
                    self:goToPage(page)
                else
                    slider:setPct(total > 1 and (page - 1) / (total - 1) or 0)
                end
            end }
        local ticks = {}
        for _i, p in ipairs(ui.toc:getTocTicksFlattened() or {}) do
            if p > 1 then table.insert(ticks, (p - 1) / math.max(1, total - 1)) end
        end
        slider.ticks = ticks
        local fracs = {}
        for _i, p in ipairs(bookmark_pages(ui)) do table.insert(fracs, (p - 1) / math.max(1, total - 1)) end
        local x0 = slider.knob_r
        local marks_h = Screen:scaleBySize(11 * T.scale)
        local marks = Marks:new{ width = track_w, height = marks_h, fracs = fracs, x0 = x0, tw = track_w - 2 * x0, invert = invert }
        local track_h = T.px("hit")
        local track = OverlapGroup:new{ dimen = geom(track_w, track_h + marks_h),
            marks,
            VerticalGroup:new{ VerticalSpan:new{ width = marks_h - T.px("sp-1") }, slider } }

        -- buttons
        local gap6 = T.px("sp-1h")
        local row_w = inner - 2 * T.px("sp-4")
        local bw = math.floor((row_w - 5 * gap6) / 6)
        local bh = Screen:scaleBySize(52 * T.scale)
        local function btn(icon, text, cb, hold)
            local g = VerticalGroup:new{ align = "center", Kit.icon(icon, "icon-md"), VerticalSpan:new{ width = T.px("sp-half") },
                TextWidget:new{ text = text, face = L.face("ui", "fs-xs"), fgcolor = T.color("text-2"), max_width = bw - T.px("sp-1") } }
            return boxed{ width = bw, height = bh, content = g, callback = cb, hold_callback = hold }
        end
        local prev_ch = function()
            local p = ui.toc:getPreviousChapter(self.curr_page)
            if p and p >= 1 and p <= total then self:goToPage(p) end
        end
        local next_ch = function()
            local p = ui.toc:getNextChapter(self.curr_page)
            if p and p >= 1 and p <= total then self:goToPage(p) end
        end
        local items = {
            btn("leaf.rd.prev", _("Chapter"), prev_ch, function() self:goToPage(1) end),
            btn("leaf.sk.left10", "−10", function() self:goToPage(self.curr_page - 10) end),
            btn("chevron.left", "−1", function() self:goToPage(self.curr_page - 1) end),
            btn("chevron.right", "+1", function() self:goToPage(self.curr_page + 1) end),
            btn("leaf.sk.right10", "+10", function() self:goToPage(self.curr_page + 10) end),
            btn("leaf.rd.next", _("Chapter"), next_ch, function() self:goToPage(total) end),
        }
        if invert then
            -- page turns run right to left: the buttons follow the page direction
            local rev = {}
            for i = #items, 1, -1 do table.insert(rev, items[i]) end
            items = rev
        end
        local row1 = HorizontalGroup:new{ align = "center" }
        for i, b in ipairs(items) do
            if i > 1 then table.insert(row1, HorizontalSpan:new{ width = gap6 }) end
            table.insert(row1, b)
        end
        local bw2 = math.floor((row_w - gap6) / 2)
        local bh2 = T.px("hit")
        local function btn2(text, cb, hold)
            local g = HorizontalGroup:new{ align = "center", Kit.icon("leaf.rd.bookmark", "icon-md"), HorizontalSpan:new{ width = T.px("sp-2") },
                TextWidget:new{ text = text, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"), max_width = bw2 - T.px("icon-md") - T.px("sp-4") } }
            return boxed{ width = bw2, height = bh2, content = g, callback = cb, hold_callback = hold }
        end
        local row2 = HorizontalGroup:new{ align = "center",
            btn2(_("Previous bookmark"), function() self:goToByEvent("GotoPreviousBookmarkFromPage") end,
                function() self:goToByEvent("GotoFirstBookmark") end),
            HorizontalSpan:new{ width = gap6 },
            btn2(_("Next bookmark"), function() self:goToByEvent("GotoNextBookmarkFromPage") end,
                function() self:goToByEvent("GotoLastBookmark") end) }

        local side = T.px("sp-4")
        local body = VerticalGroup:new{ align = "left",
            head,
            VerticalSpan:new{ width = T.px("sp-1") },
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, track },
            VerticalSpan:new{ width = T.px("sp-2") },
            HorizontalGroup:new{ HorizontalSpan:new{ width = side }, row1 },
            VerticalSpan:new{ width = gap6 },
            HorizontalGroup:new{ HorizontalSpan:new{ width = side }, row2 },
            VerticalSpan:new{ width = T.px("sp-3") } }
        local frame, container = Kit.sheet{ width = sheet_w, content = body, top = position == "top" }
        if position == "top" then
            container = require("ui/widget/container/topcontainer"):new{ dimen = geom(W, Screen:getHeight()), frame }
        end
        self.skimto_frame = frame
        self[1] = container
    end

    L.wrap(SkimToWidget, "init", function(orig, self)
        if not use_leaf() then return orig(self) end
        if self.ui.paging then self.ui.paging:enterSkimMode() end
        local W, H = Screen:getWidth(), Screen:getHeight()
        if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
        self.ges_events.TapProgress = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = W, h = H } } }
        self.curr_page = self.ui:getCurrentPage()
        self.leaf_orig_page = self.curr_page
        self.page_count = self.ui.document:getPageCount()
        self.layout = {}
        self.leaf = true
        self:leafBuild()
    end, "SkimToWidget:init")

    L.wrap(SkimToWidget, "update", function(orig, self)
        if not self.leaf then return orig(self) end
        if self.curr_page <= 0 then self.curr_page = 1 end
        if self.curr_page > self.page_count then self.curr_page = self.page_count end
        self:leafBuild()
        UIManager:setDirty(self, "ui", self.skimto_frame.dimen)
    end, "SkimToWidget:update")

    L.wrap(SkimToWidget, "onTapProgress", function(orig, self, arg, ges)
        if not self.leaf then return orig(self, arg, ges) end
        local f = self.skimto_frame and self.skimto_frame.dimen
        if f and ges.pos:notIntersectWith(f) then self:onClose() end
        return true
    end, "SkimToWidget:onTapProgress")
end

return M
