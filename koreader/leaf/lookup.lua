--[[
    Leaf lookup: everything that opens when text is selected in a book.

      * Text-selection popup (ReaderHighlight:onShowHighlightMenu) and the tap-on-a-highlight menu
        (showHighlightDialog / showHighlightNoteOrDialog) -> one compact popover (prototype
        "hl-popup", .rd-hl), anchored under (or over) the selection with a caret:
            quote (2 lines) · "7 words" / "Chapter · Nov 18"
            [the note, on a highlight that has one: tap = KOReader's note viewer]
            style segment (Highlight / Underline / Strikeout / Invert, each with its "Ab" sample)
            colour chips (6; hold a chip = KOReader's full colour list)
            main tools: Highlight (Delete on a highlight) · Add/Edit note · Dictionary · Translate
            icon strip: every other button of ReaderHighlight._highlight_buttons, plugins included
              (Select/Extend, Copy, Wikipedia, View HTML, Hyphenate, Follow link, Share, Search, ...);
              hold an icon = its name
            on a highlight: ‹ Start › ‹ End › (KOReader's boundary nudges; hold = by character)
              and Details
        A new selection: tap a style = highlight in that style; tap a colour = colour for it.
        A highlight: style / colour change it in place, as KOReader's Style / Color dialogs do.
      * Dictionary and Wikipedia (DictQuickLookup) -> bottom sheet (prototype "dict" / "wiki"):
        grip, head (word · edit · results · ×), dictionary tabs, the definition (KOReader's own
        scroll widget: text selection, links, images, search keep working), "Oxford · 1 of 4
        dictionaries", tools row (Highlight, Wikipedia, Search, plugin buttons, Close).
        No dictionary installed -> empty state with "Download dictionaries".
        Wikipedia: globe tile, title, "From Wikipedia, the free encyclopedia", language segment,
        footer (Highlight, Dictionary, Full article / Save as EPUB).
      * Footnote popup (FootnoteWidget) -> compact sheet: grip, "FOOTNOTE" eyebrow, Go to note, ×,
        hairline, the note in the book face (Literata unless "use book font" is set).
      * The paragraph translation panel of patches/2-paragraph-translate.lua calls
        M.build_translate(panel) (prototype "translate").
    KOReader still does the work: callbacks, settings, events and plugins are the stock ones.
--]]
local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
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
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

local function has_arabic(s)
    return s and s:find("[\216-\219][\128-\191]") ~= nil
end

function M.apply(L)
    local T = L.T
    local hair = T.px("hairline")
    local IconButton = require("ui/widget/iconbutton")
    local Notification = require("ui/widget/notification")

    ------------------------------------------------------------------ small shared widgets
    local function hline(w, color)
        return LineWidget:new{ dimen = Geom:new{ w = w, h = hair }, background = T.color(color or "border") }
    end
    local function text(s, role, size, color, max_w, lang)
        return TextWidget:new{ text = s or "", face = L.face(role, size), fgcolor = T.color(color or "text"),
            max_width = max_w, lang = lang }
    end
    local function icon(name, size, enabled)
        local s = T.px(size or "icon-md")
        return IconWidget:new{ icon = name, width = s, height = s, alpha = true, dim = enabled == false or nil }
    end
    local function icon_button(name, cb, hold_cb, show_parent)
        local s = T.px("icon-md")
        return IconButton:new{ icon = name, width = s, height = s, padding = math.floor((T.px("hit") - s) / 2),
            callback = cb, hold_callback = hold_cb, show_parent = show_parent }
    end
    local function toast(s)
        UIManager:show(Notification:new{ text = s })
    end

    -- a tappable box of a fixed size, content centred (or left with align = "left")
    local Tap = InputContainer:extend{ width = nil, height = nil, bg = nil, border = nil, border_w = nil,
        radius = 0, callback = nil, hold_callback = nil, enabled = true, align = "center" }
    function Tap:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
        local c = self.content
        if self.align == "left" then
            self[1] = LeftContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, c }
        else
            self[1] = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, c }
        end
        self.ges_events = {
            LeafTap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
            LeafHold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
        }
    end
    function Tap:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local w, h = self.width, self.height
        if self.border then
            bb:paintRoundedRect(x, y, w, h, self.border, self.radius)
            local b = self.border_w or hair
            bb:paintRoundedRect(x + b, y + b, w - 2 * b, h - 2 * b, self.bg or T.color("surface"), math.max(0, self.radius - b))
        elseif self.bg then
            bb:paintRoundedRect(x, y, w, h, self.bg, self.radius)
        end
        self[1]:paintTo(bb, x, y)
    end
    function Tap:onLeafTap()
        if self.enabled and self.callback then self.callback() end
        return true
    end
    function Tap:onLeafHold()
        if self.enabled and self.hold_callback then self.hold_callback() return true end
        return false
    end

    -- paints its child at (ox, oy) on a full-screen layer; `after` paints extras (the caret)
    local Placer = WidgetContainer:extend{ ox = 0, oy = 0, after = nil }
    function Placer:paintTo(bb, x, y)
        self[1]:paintTo(bb, x + self.ox, y + self.oy)
        if self.after then self.after(bb, x + self.ox, y + self.oy) end
    end

    local Grip = Widget:extend{}
    function Grip:init() self.dimen = Geom:new{ w = Screen:scaleBySize(36 * T.scale), h = T.px("sp-1") } end
    function Grip:paintTo(bb, x, y)
        bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, T.color("border-strong"), math.floor(self.dimen.h / 2))
    end
    local function grip_block(w)
        return VerticalGroup:new{
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = T.px("sp-1") }, Grip:new{} },
            VerticalSpan:new{ width = T.px("sp-1") },
        }
    end

    -- a button (.ko-btn): optional icon + label, kinds primary / secondary / ghost
    local function btn(label, kind, cb, icon_name, enabled, hold_cb)
        enabled = enabled ~= false
        local fg = ({ primary = "accent-ink", ghost = "text-2", secondary = "text" })[kind] or "text"
        if not enabled then fg = "disabled" end
        local face = kind == "primary" and "ui-semibold" or "ui-medium"
        local g = HorizontalGroup:new{ align = "center" }
        if icon_name then
            table.insert(g, icon(icon_name, "icon-sm", enabled))
            table.insert(g, HorizontalSpan:new{ width = T.px("sp-1h") })
        end
        table.insert(g, text(label, face, "fs-md", fg))
        local w = g:getSize().w + 2 * T.px("sp-4")
        g:resetLayout()
        local bg
        if kind == "primary" and enabled then bg = T.color("accent")
        elseif kind == "secondary" then bg = T.color("surface-2") end
        return Tap:new{ width = w, height = T.px("h-control"), content = g, bg = bg, radius = T.px("r-md"),
            border = kind == "secondary" and T.color("border") or nil, callback = cb, hold_callback = hold_cb, enabled = enabled }
    end

    -- the bottom-sheet frame (.ko-sheet): --bg-raised, --border-strong hairline, --r-xl top corners
    local function sheet_frame(content, top)
        local r = T.px("r-xl")
        return FrameContainer:new{ bordersize = hair, color = T.color("border-strong"), background = T.color("bg-raised"),
            radius = r, padding = 0, padding_bottom = (not top) and r or 0, padding_top = top and r or 0, content }
    end

    -- head (.ko-sheet-head): [lead] title / sub ... [right widgets]
    local function sheet_head(inner, opts)
        local pad = T.px("sp-5")
        local right = HorizontalGroup:new{ align = "center" }
        for __, w in ipairs(opts.right or {}) do table.insert(right, w) end
        table.insert(right, HorizontalSpan:new{ width = T.px("sp-3") - math.floor((T.px("hit") - T.px("icon-md")) / 2) })
        local lead_w = 0
        local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad } }
        if opts.lead then
            table.insert(left, opts.lead)
            table.insert(left, HorizontalSpan:new{ width = T.px("sp-3") })
            lead_w = opts.lead:getSize().w + T.px("sp-3")
        end
        local tw = inner - pad - lead_w - right:getSize().w - T.px("sp-2")
        right:resetLayout()
        local col = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = opts.title or "", face = L.face("ui-semibold", "fs-head"), max_width = tw, lang = opts.lang } }
        if opts.sub and opts.sub ~= "" then
            table.insert(col, VerticalSpan:new{ width = T.px("sp-half") })
            table.insert(col, opts.sub_widget or text(opts.sub, "ui", "fs-sm", "text-3", tw))
        elseif opts.sub_widget then
            table.insert(col, VerticalSpan:new{ width = T.px("sp-1") })
            table.insert(col, opts.sub_widget)
        end
        table.insert(left, col)
        local h = math.max(T.px("h-header"), col:getSize().h + 2 * T.px("sp-2"))
        left:resetLayout()
        col:resetLayout()
        return OverlapGroup:new{ dimen = Geom:new{ w = inner, h = h },
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = h }, left },
            RightContainer:new{ dimen = Geom:new{ w = inner, h = h }, right } }
    end

    -- a toolbar tool (.ko-tool): icon over a label
    local function tool(icon_name, label, w, h, cb, opts)
        opts = opts or {}
        local enabled = opts.enabled ~= false
        local fg = enabled and (opts.danger and "danger" or opts.color or "text-2") or "disabled"
        local g = VerticalGroup:new{ align = "center",
            icon(icon_name, "icon-md", enabled),
            VerticalSpan:new{ width = T.px("sp-1") },
            text(label, opts.face or "ui", opts.size or "fs-xs", fg, w - T.px("sp-1")) }
        return Tap:new{ width = w, height = h, content = g, callback = cb, hold_callback = opts.hold, enabled = enabled,
            bg = opts.on and T.color("surface-2") or nil, radius = T.px("r-md") }
    end

    -- dictionary / tab strip (.ko-tabs--sm): labels at their width, an accent bar under the current
    local function tabs(inner, items, current, on_tap)
        local pad, gap = T.px("sp-5"), T.px("sp-4")
        local cells, widths = {}, {}
        for i, label in ipairs(items) do
            local on = i == current
            local tw = text(label, on and "ui-medium" or "ui", "fs-sm", on and "text" or "text-3", math.floor(inner * 0.6))
            widths[i] = tw:getSize().w
            cells[i] = tw
        end
        -- scroll the strip so the current tab is visible
        local first, avail = 1, inner - 2 * pad
        local function span(a, b)
            local s = 0
            for i = a, b do s = s + widths[i] + (i > a and gap or 0) end
            return s
        end
        while first < (current or 1) and span(first, current or 1) > avail do first = first + 1 end
        local h = T.px("sp-2") + cells[1]:getSize().h + T.px("sp-2h")
        local row = HorizontalGroup:new{ align = "bottom", HorizontalSpan:new{ width = pad } }
        local used = pad
        for i = first, #items do
            if used + widths[i] > inner then break end
            local on = i == current
            local col = VerticalGroup:new{ align = "left",
                CenterContainer:new{ dimen = Geom:new{ w = widths[i], h = h - T.px("bw-lg") }, cells[i] },
                on and LineWidget:new{ dimen = Geom:new{ w = widths[i], h = T.px("bw-lg") }, background = T.color("accent") }
                    or VerticalSpan:new{ width = T.px("bw-lg") } }
            if i > first then table.insert(row, HorizontalSpan:new{ width = gap }) end
            table.insert(row, Tap:new{ width = widths[i], height = h, content = col, callback = function() on_tap(i) end })
            used = used + widths[i] + gap
        end
        return VerticalGroup:new{ align = "left", row, hline(inner) }
    end

    ------------------------------------------------------------------ 1. text-selection popup
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")

    local STYLE_LABEL = { lighten = _("Highlight"), underscore = _("Underline"), strikeout = _("Strikeout"), invert = _("Invert") }
    local COLORS = { "yellow", "green", "blue", "red", "purple", "gray" }
    local PRIMARY = { ["02_highlight"] = 1, ["04_add_note"] = 2, ["06_dictionary"] = 3, ["07_translate"] = 4 }
    local ICONS = {
        { "select", "leaf.lk.select" }, { "highlight", "leaf.lk.highlight" }, { "copy", "leaf.lk.copy" },
        { "note", "leaf.lk.note" }, { "wikipedia", "leaf.lk.wiki" }, { "dictionary", "leaf.lk.dict" },
        { "translate", "leaf.lk.translate" }, { "share", "leaf.lk.share" }, { "html", "leaf.lk.html" },
        { "user_dict", "leaf.lk.hyphen" }, { "hyphen", "leaf.lk.hyphen" }, { "link", "leaf.lk.link" },
        { "search", "leaf.lk.search" }, { "qr", "leaf.lk.qr" }, { "vocab", "leaf.lk.vocab" },
    }
    local function icon_for(key)
        key = tostring(key):lower()
        for __, p in ipairs(ICONS) do
            if key:find(p[1], 1, true) then return p[2] end
        end
        return "leaf.lk.plugin"
    end
    local SHORT = { ["09_view_html"] = _("View HTML"), ["10_user_dict"] = _("Hyphenate"), ["11_follow_link"] = _("Follow link") }

    -- "Ab" sample of a highlight style
    local Sample = Widget:extend{ style = "lighten" }
    function Sample:init()
        self.tw = TextWidget:new{ text = "Ab", face = L.face("book", "fs-sm"),
            fgcolor = T.color(self.style == "invert" and "surface" or "text") }
        local s = self.tw:getSize()
        self.pad = T.px("sp-half") + math.floor(hair / 2) + 1
        self.dimen = Geom:new{ w = s.w + 2 * self.pad, h = s.h }
    end
    function Sample:paintTo(bb, x, y)
        local w, h = self.dimen.w, self.dimen.h
        if self.style == "lighten" then
            bb:paintRoundedRect(x, y, w, h, T.color("surface-3"), T.px("r-thumb"))
            bb:paintRect(x, y + math.floor(h * 0.45), w, h - math.floor(h * 0.45), T.color("accent-tint"))
        elseif self.style == "invert" then
            bb:paintRoundedRect(x, y, w, h, T.color("text-2"), T.px("r-thumb"))
        end
        self.tw:paintTo(bb, x + self.pad, y)
        local lw = T.px("bw-md")
        if self.style == "underscore" then
            bb:paintRect(x + self.pad, y + self.tw:getBaseline() + T.px("sp-half"), w - 2 * self.pad, lw, T.color("text"))
        elseif self.style == "strikeout" then
            bb:paintRect(x + self.pad, y + math.floor(h * 0.55), w - 2 * self.pad, lw, T.color("text"))
        end
    end

    local Dot = Widget:extend{ color = nil }
    function Dot:init() local d = Screen:scaleBySize(11 * T.scale); self.dimen = Geom:new{ w = d, h = d } end
    function Dot:paintTo(bb, x, y)
        local d = self.dimen.w
        bb:paintRoundedRect(x, y, d, d, T.color("border-strong"), math.floor(d / 2))
        bb:paintRoundedRect(x + 1, y + 1, d - 2, d - 2, self.color, math.floor((d - 2) / 2))
    end

    local HlPopup = InputContainer:extend{ hl = nil, index = nil }

    function HlPopup:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self.move_by_char = false
        self:build()
    end

    function HlPopup:item()
        return self.index and self.hl.ui.annotation.annotations[self.index]
    end

    -- the selection's (or highlight's) boxes on screen
    function HlPopup:boxes()
        local hl = self.hl
        local boxes
        if self.index then
            boxes = hl:getHighlightVisibleBoxes(self.index)
        elseif hl.selected_text then
            boxes = hl.selected_text.sboxes or hl.selected_text.pboxes
        end
        if not boxes or #boxes == 0 then return nil end
        local out = {}
        for i, b in ipairs(boxes) do
            if hl.ui.paging then
                local page = self.index and hl.ui.annotation.annotations[self.index].pos0.page or hl.selected_text.pos0.page
                b = hl.view:pageToScreenTransform(page, b)
            end
            if b then out[#out + 1] = b end
        end
        return #out > 0 and out or nil
    end

    function HlPopup:buttons()
        local hl = self.hl
        local main, more = {}, {}
        for key, fn in require("ffi/util").orderedPairs(hl._highlight_buttons) do
            local ok, b = pcall(fn, hl, self.index)
            if ok and b and (not b.show_in_highlight_dialog_func or b.show_in_highlight_dialog_func()) then
                b._key = key
                if PRIMARY[key] then main[PRIMARY[key]] = b else table.insert(more, b) end
            end
        end
        return main, more
    end

    function HlPopup:close(keep)
        if self.hl.highlight_dialog == self then
            self.hl:onClose(keep)
        else
            UIManager:close(self)
        end
    end

    -- run a KOReader highlight button the way its dialog would
    function HlPopup:run(b)
        if b.enabled == false or not b.callback then return end
        b.callback()
    end

    -- style / colour of an existing highlight, as editHighlightStyle / editHighlightColor do
    function HlPopup:setItem(field, value)
        local hl, item = self.hl, self:item()
        hl:writePdfAnnotation("delete", item)
        item[field] = value
        if hl.ui.paging then
            hl:writePdfAnnotation("save", item)
            if item.note then hl:writePdfAnnotation("content", item, item.note) end
        end
        UIManager:setDirty(hl.dialog, "ui")
        hl.ui:handleEvent(Event:new("AnnotationsModified", { item }))
        self:rebuild()
    end

    function HlPopup:build()
        local hl = self.hl
        local item = self:item()
        local existing = item ~= nil
        local W, H = Screen:getWidth(), Screen:getHeight()
        local edge = T.px("sp-3")
        local pw = math.min(Screen:scaleBySize(400 * T.scale), W - 2 * edge)
        local inner = pw - 2 * hair
        local pad4, pad3 = T.px("sp-4"), T.px("sp-3")
        local sel = hl.selected_text or {}
        local quote = util.cleanupSelectedText((existing and item.text) or sel.text or ""):gsub("%s+", " ")
        local vg = VerticalGroup:new{ align = "left" }

        -- quote + meta
        local meta
        if existing then
            local bits = {}
            if item.chapter and item.chapter ~= "" then table.insert(bits, item.chapter) end
            local y, m, d = tostring(item.datetime or ""):match("^(%d+)-(%d+)-(%d+)")
            if y then
                local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
                table.insert(bits, (MONTHS[tonumber(m)] or m) .. " " .. tonumber(d))
            end
            meta = table.concat(bits, " · ")
        else
            local n = select(2, quote:gsub("%S+", ""))
            meta = n == 1 and _("1 word") or T_(_("%1 words"), n)
        end
        local meta_w = text(meta, "ui", "fs-xs", "text-3", math.floor(inner * 0.4))
        local qw = inner - 2 * pad4 - meta_w:getSize().w - pad3
        local ar = has_arabic(quote)
        local qopts = { text = existing and ("“" .. quote .. "”") or quote, width = qw, fgcolor = T.color("text-2"),
            bgcolor = T.color("surface"), face = ar and L.face("arabic", "fs-md") or L.face("ui", "fs-sm"),
            para_direction_rtl = ar or nil, alignment = ar and "right" or "left" }
        local q = TextBoxWidget:new(qopts)
        if q:getAllLineCount() > 2 then
            local lh = q:getLineHeight()
            q:free()
            qopts.height = 2 * lh
            qopts.height_overflow_show_ellipsis = true
            q = TextBoxWidget:new(qopts)
        end
        table.insert(vg, VerticalSpan:new{ width = pad3 })
        table.insert(vg, HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = pad4 }, q,
            HorizontalSpan:new{ width = pad3 }, VerticalGroup:new{ VerticalSpan:new{ width = T.px("sp-half") }, meta_w } })
        table.insert(vg, VerticalSpan:new{ width = T.px("sp-2") })

        -- the note (a highlight with a note): tap = KOReader's note viewer
        if existing and item.note and item.note ~= "" then
            local nw = inner - 2 * pad4
            local tb = TextBoxWidget:new{ text = item.note:gsub("%s+", " "), face = L.face("ui", "fs-sm"),
                width = nw - 2 * pad3 - T.px("icon-sm") - T.px("sp-2"), bgcolor = T.color("surface-2"),
                height = nil }
            if tb:getAllLineCount() > 3 then
                local lh = tb:getLineHeight()
                tb:free()
                tb = TextBoxWidget:new{ text = item.note:gsub("%s+", " "), face = L.face("ui", "fs-sm"),
                    width = nw - 2 * pad3 - T.px("icon-sm") - T.px("sp-2"), bgcolor = T.color("surface-2"),
                    height = 3 * lh, height_overflow_show_ellipsis = true }
            end
            local row = HorizontalGroup:new{ align = "top", icon("leaf.rd.notes", "icon-sm"), HorizontalSpan:new{ width = T.px("sp-2") }, tb }
            local nh = row:getSize().h + 2 * T.px("sp-2")
            row:resetLayout()
            local index = self.index
            table.insert(vg, HorizontalGroup:new{ HorizontalSpan:new{ width = pad4 },
                Tap:new{ width = nw, height = nh, bg = T.color("surface-2"), radius = T.px("r-md"), align = "left",
                    content = HorizontalGroup:new{ HorizontalSpan:new{ width = pad3 }, row },
                    callback = function()
                        self:close(true)
                        M.orig_note_or_dialog(hl, index)
                    end } })
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-2") })
        end

        -- styles
        local cur_style = existing and item.drawer or sel.drawer or hl.view.highlight.saved_drawer or "lighten"
        local cur_color = existing and item.color or sel.color or hl.view.highlight.saved_color or "yellow"
        local sw = inner - 2 * pad3
        local track_pad = T.px("sp-half")
        local styles = ReaderHighlight.getHighlightStyles()
        local cell_w = math.floor((sw - 2 * track_pad - (#styles - 1) * T.px("sp-half")) / #styles)
        local cell_h = T.px("h-seg")
        local seg = HorizontalGroup:new{ align = "center" }
        for i, st in ipairs(styles) do
            local key = st[2]
            local on = key == cur_style
            local smp = Sample:new{ style = key }
            local room = cell_w - smp.dimen.w - T.px("sp-1") - 2 * T.px("sp-half")
            local lbl = text(STYLE_LABEL[key] or st[1], on and "ui-semibold" or "ui", "fs-sm", on and "text" or "text-2")
            if lbl:getSize().w > room then
                lbl:free()
                lbl = text(STYLE_LABEL[key] or st[1], on and "ui-semibold" or "ui", "fs-xs", on and "text" or "text-2", room)
            end
            local g = HorizontalGroup:new{ align = "center", smp, HorizontalSpan:new{ width = T.px("sp-1") }, lbl }
            if i > 1 then table.insert(seg, HorizontalSpan:new{ width = T.px("sp-half") }) end
            table.insert(seg, Tap:new{ width = cell_w, height = cell_h, content = g, radius = T.px("r-inner"),
                bg = on and T.color("surface") or nil, border = on and T.color("accent") or nil, border_w = T.px("bw-md"),
                callback = function()
                    if existing then
                        self:setItem("drawer", key)
                    else
                        -- highlight now, in this style (and the colour picked below)
                        sel.drawer = key
                        hl.selected_text = sel
                        self:close(true)
                        hl:saveHighlight(true)
                        hl:clear()
                    end
                end })
        end
        table.insert(vg, HorizontalGroup:new{ HorizontalSpan:new{ width = pad3 },
            FrameContainer:new{ bordersize = 0, background = T.color("surface-2"), radius = T.px("r-md"), padding = track_pad, seg } })
        table.insert(vg, VerticalSpan:new{ width = T.px("sp-2") })

        -- colours (6 columns); KOReader's rule: every style but Invert takes a colour
        local color_on = cur_style ~= "invert"
        local gap = T.px("sp-1")
        local chip_w = math.floor((sw - 5 * gap) / 6)
        local chips = HorizontalGroup:new{ align = "center" }
        local names = {}
        for __, c in ipairs(hl.highlight_colors or {}) do names[c[2]] = c[1] end
        local function full_colors()
            if existing then
                self:close(true)
                hl:editHighlightColor(self.index)
            else
                hl:showHighlightPrompt(nil, "color")
            end
        end
        for i, c in ipairs(COLORS) do
            local on = color_on and c == cur_color
            local g = HorizontalGroup:new{ align = "center", Dot:new{ color = T.color("hl-c-" .. c) },
                HorizontalSpan:new{ width = T.px("sp-1") },
                text(names[c] or c, "ui", "fs-xs", color_on and (on and "text" or "text-2") or "disabled", chip_w - Screen:scaleBySize(20 * T.scale)) }
            if i > 1 then table.insert(chips, HorizontalSpan:new{ width = gap }) end
            table.insert(chips, Tap:new{ width = chip_w, height = T.px("h-chip"), content = g, radius = math.floor(T.px("h-chip") / 2),
                border = T.color(on and "accent" or "border"), bg = on and T.color("accent-soft") or T.color("surface"),
                enabled = color_on, hold_callback = full_colors,
                callback = function()
                    if existing then
                        self:setItem("color", c)
                    else
                        sel.color = c
                        self:rebuild()
                    end
                end })
        end
        table.insert(vg, HorizontalGroup:new{ HorizontalSpan:new{ width = pad3 }, chips })
        table.insert(vg, VerticalSpan:new{ width = pad3 })

        -- main tools
        local main, more = self:buttons()
        local mains = {}
        for i = 1, 4 do if main[i] then table.insert(mains, main[i]) end end
        local index = self.index
        if existing then
            -- KOReader's edit menu: trash, note (the selection-only ones are replaced)
            for i, b in ipairs(mains) do
                if b._key == "02_highlight" then
                    mains[i] = { _key = b._key, text = _("Delete"), _icon = "leaf.trash", _danger = true,
                        callback = function() self:close(true); hl:deleteHighlight(index) end }
                elseif b._key == "04_add_note" then
                    mains[i] = { _key = b._key, text = (item.note and item.note ~= "") and _("Edit note") or _("Add note"),
                        callback = function() self:close(true); hl:editNote(index) end }
                end
            end
        end
        if #mains > 0 then
            table.insert(vg, hline(inner))
            local mrow = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad3 } }
            local mw = math.floor((sw - (#mains - 1) * gap) / #mains)
            for i, b in ipairs(mains) do
                if i > 1 then table.insert(mrow, HorizontalSpan:new{ width = gap }) end
                local label = b.text_func and b.text_func() or b.text or ""
                table.insert(mrow, tool(b._icon or icon_for(b._key), label, mw, Screen:scaleBySize(58 * T.scale),
                    function() self:run(b) end,
                    { enabled = b.enabled, danger = b._danger, size = "fs-sm", color = "text", hold = b.hold_callback }))
            end
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-2") })
            table.insert(vg, mrow)
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-2") })
        end

        -- icon strip
        if existing then
            table.insert(more, { _key = "details", text = _("Details"), _icon = "leaf.lk.details",
                callback = function() self:close(true); hl.ui.bookmark:showBookmarkDetails(index) end })
        end
        if #more > 0 then
            table.insert(vg, hline(inner))
            local srow = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad3 } }
            local n = #more
            local per_row = math.max(1, math.floor((sw + T.px("sp-half")) / (T.px("hit") + T.px("sp-half"))))
            local rows = math.ceil(n / per_row)
            local cols = math.ceil(n / rows)
            local cw = math.floor((sw - (cols - 1) * T.px("sp-half")) / cols)
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-1") })
            for i, b in ipairs(more) do
                if (i - 1) % cols == 0 and i > 1 then
                    table.insert(vg, srow)
                    srow = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad3 } }
                elseif i > 1 then
                    table.insert(srow, HorizontalSpan:new{ width = T.px("sp-half") })
                end
                local label = b.text_func and b.text_func() or b.text or ""
                label = SHORT[b._key] or label
                table.insert(srow, Tap:new{ width = cw, height = T.px("hit"), radius = T.px("r-md"),
                    content = icon(b._icon or icon_for(b._key), "icon-md", b.enabled ~= false),
                    enabled = b.enabled ~= false,
                    callback = function() self:run(b) end,
                    hold_callback = function()
                        if b.hold_callback then b.hold_callback() else toast(label) end
                    end })
            end
            table.insert(vg, srow)
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-2") })
        end

        -- highlight boundaries (KOReader's ◁▒▒ ▷☓▒ ▒☓◁ ▒▒▷), hold = by character
        if existing then
            local can = not item.text_edited
            local function nudge(side, dir)
                return function()
                    hl:updateHighlight(index, side, dir, self.move_by_char)
                    self:rebuild()
                end
            end
            local function nudge_char(side, dir)
                return function()
                    self.move_by_char = not self.move_by_char
                    hl:updateHighlight(index, side, dir, true)
                    self:rebuild()
                end
            end
            local s = T.px("icon-sm")
            local function arrow(name, side, dir)
                return Tap:new{ width = T.px("hit"), height = T.px("hit"), radius = T.px("r-md"), enabled = can,
                    content = IconWidget:new{ icon = name, width = s, height = s, alpha = true, dim = (not can) or nil },
                    callback = nudge(side, dir), hold_callback = nudge_char(side, dir) }
            end
            local left_name, right_name = "chevron.left", "chevron.right"
            if BD.mirroredUILayout() then left_name, right_name = right_name, left_name end
            local function group(label, side)
                return HorizontalGroup:new{ align = "center", arrow(left_name, side, -1),
                    text(label, "ui", "fs-xs", can and "text-2" or "disabled"), arrow(right_name, side, 1) }
            end
            table.insert(vg, hline(inner))
            local brow = HorizontalGroup:new{ align = "center", group(_("Start"), 0), HorizontalSpan:new{ width = T.px("sp-6") }, group(_("End"), 1) }
            table.insert(vg, CenterContainer:new{ dimen = Geom:new{ w = inner, h = T.px("hit") }, brow })
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-1") })
        end

        local frame = FrameContainer:new{ bordersize = hair, color = T.color("border-strong"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = 0, vg }
        self.frame = frame
        local ph = frame:getSize().h

        -- position: KOReader's setting (top / bottom), else next to the selection, below if it fits
        local position = G_reader_settings:readSetting("highlight_dialog_position", "center")
        local left, top = math.floor((W - pw) / 2), H - ph - T.px("sp-4")
        local caret_x, caret_up
        local gap_y = T.px("sp-5")
        local boxes = self:boxes()
        if position == "top" then
            top = T.px("sp-2")
        elseif position == "bottom" then
            top = H - ph - T.px("sp-2")
        elseif boxes then
            local y0, y1, x0, x1 = math.huge, -math.huge, math.huge, -math.huge
            for __, b in ipairs(boxes) do
                y0, y1 = math.min(y0, b.y), math.max(y1, b.y + b.h)
                x0, x1 = math.min(x0, b.x), math.max(x1, b.x + b.w)
            end
            local cx = math.floor((x0 + x1) / 2)
            -- with a multi-line selection, point at the line the popup sits next to
            if y1 + gap_y + ph < H - T.px("sp-2") then
                top, caret_up = y1 + gap_y, true
                local last = boxes[#boxes]
                if #boxes > 1 then cx = math.floor(last.x + last.w / 2) end
            elseif y0 - gap_y - ph > T.px("sp-2") then
                top, caret_up = y0 - gap_y - ph, false
                if #boxes > 1 then cx = math.floor(boxes[1].x + boxes[1].w / 2) end
            else
                top = H - ph - T.px("sp-2")
            end
            left = math.max(edge, math.min(W - pw - edge, cx - math.floor(pw / 2)))
            if caret_up ~= nil then
                caret_x = math.max(left + T.px("sp-6"), math.min(left + pw - T.px("sp-6"), cx))
            end
        end
        self.frame_rect = Geom:new{ x = left, y = top, w = pw, h = ph }
        local ch = Screen:scaleBySize(9 * T.scale)
        local fill, line = T.color("surface"), T.color("border-strong")
        self[1] = Placer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H }, ox = left, oy = top, frame,
            after = caret_x and function(bb, fx, fy)
                local cx = fx + caret_x - left
                for i = 0, ch do
                    local yy = caret_up and (fy - ch + i) or (fy + ph - 1 + ch - i)
                    bb:paintRect(cx - i, yy, 2 * i + 1, 1, fill)
                    if i < ch then
                        bb:paintRect(cx - i, yy, hair, 1, line)
                        bb:paintRect(cx + i - hair + 1, yy, hair, 1, line)
                    end
                end
            end or nil }
    end

    function HlPopup:rebuild()
        self:build()
        UIManager:setDirty(self.hl.dialog, "ui")
        UIManager:setDirty(self, "ui")
    end

    function HlPopup:onTapClose(arg, ges)
        local r = self.frame_rect
        if r and ges.pos:notIntersectWith(r) then
            if self.hl.highlight_dialog == self then
                self.hl.highlight_dialog = nil
            end
            UIManager:close(self)
            if self.tap_close_callback then self.tap_close_callback() end
            return true
        end
        return true
    end
    function HlPopup:onClose()
        self:close()
        return true
    end
    function HlPopup:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function HlPopup:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end

    local function show_popup(hl, index)
        local popup = HlPopup:new{ hl = hl, index = index,
            tap_close_callback = function()
                if hl.hold_pos or index then hl:clear() end
            end }
        hl.highlight_dialog = popup
        UIManager:show(popup, "[ui]")
        return popup
    end
    M.show_popup = show_popup

    L.wrap(ReaderHighlight, "onShowHighlightMenu", function(orig, self, index)
        if not self.selected_text then return end
        show_popup(self, index)
    end, "ReaderHighlight:onShowHighlightMenu")

    L.wrap(ReaderHighlight, "showHighlightDialog", function(orig, self, index)
        local item = self.ui.annotation.annotations[index]
        if not item then return orig(self, index) end
        self.selected_text = util.tableDeepCopy(item)
        show_popup(self, index)
    end, "ReaderHighlight:showHighlightDialog")

    -- a highlight with a note opens the same popover (the note is in it; tap it for KOReader's viewer)
    M.orig_note_or_dialog = ReaderHighlight.showHighlightNoteOrDialog
    L.wrap(ReaderHighlight, "showHighlightNoteOrDialog", function(orig, self, index)
        self:showHighlightDialog(index)
    end, "ReaderHighlight:showHighlightNoteOrDialog")

    ------------------------------------------------------------------ 2/3. dictionary and Wikipedia
    local DictQuickLookup = require("ui/widget/dictquicklookup")

    local DICT_ICONS = { highlight = "leaf.lk.highlight", wikipedia = "leaf.lk.wiki", search = "leaf.lk.search",
        close = "close", translate = "leaf.lk.translate", save = "leaf.lk.download", text_selection = "leaf.lk.select",
        link = "leaf.lk.link" }
    local SKIP = { prev_dict = true, next_dict = true }

    -- dictionaries found on the device (ReaderDictionary's local `available_ifos`)
    local function installed_count()
        local RD = require("apps/reader/modules/readerdictionary")
        for i = 1, 60 do
            local name, val = debug.getupvalue(RD.init, i)
            if not name then break end
            if name == "available_ifos" then return type(val) == "table" and #val or 0 end
        end
        return 0
    end
    -- -> nil, "none" (nothing installed) or "disabled" (all switched off)
    local function is_empty(self)
        if self.is_wiki or not self.results or #self.results ~= 1 then return nil end
        local r = self.results[1]
        if r.dict == "" then return "none" end
        if r.no_result and r.dict == _("Not available") then
            return installed_count() == 0 and "none" or "disabled"
        end
    end

    -- vertical room the Leaf sheet needs around the definition
    local function overhead(self)
        local fixed = T.px("sp-2") + 2 * T.px("sp-1") + T.px("h-header") + 2 * hair + T.px("r-xl")
        if self.is_wiki then
            return fixed + T.px("sp-4") * 2 + T.px("h-control") + 2 * T.px("sp-3")
        end
        return fixed + T.px("hit") + T.px("sp-3") * 3 + T.px("hit") + Screen:scaleBySize(58 * T.scale) + T.px("sp-3")
    end

    L.wrap(DictQuickLookup, "_instantiateScrollWidget", function(orig, self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.width = W
        self.content_width = W - 2 * hair - 2 * T.px("sp-5")
        if not G_reader_settings:has("dict_font_size") then
            self.content_face = L.face(self.is_wiki and "book" or "ui", "fs-md")
        end
        -- fit the Leaf sheet: at most 72% of the screen (74% for Wikipedia), or all of it in large mode
        local large = self.is_wiki_fullpage or G_reader_settings:isTrue("dict_largewindow") or self.temp_large_window
        local max_h = math.floor(H * (large and 0.94 or (self.is_wiki and 0.74 or 0.72))) - overhead(self)
        if self.definition_height and self.definition_line_height and self.definition_height > max_h then
            self.definition_height = math.max(self.definition_line_height,
                math.floor(max_h / self.definition_line_height) * self.definition_line_height)
        end
        if self.definition_height and not large and not self.is_wiki then
            -- the definition area of the prototype: about 30% of the screen
            self.definition_height = math.min(self.definition_height, max_h)
        end
        return orig(self)
    end, "DictQuickLookup:_instantiateScrollWidget")

    local function dict_layout(self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local inner = W - 2 * hair
        local pad = T.px("sp-5")
        local vg = VerticalGroup:new{ align = "left", grip_block(inner) }
        local empty = is_empty(self)

        -- buttons KOReader built for this window (its layout, plugins included)
        local defs = {}
        for __, row in ipairs(self.button_table and self.button_table.buttons or {}) do
            for __, b in ipairs(row) do
                if b.id and not SKIP[b.id] then table.insert(defs, b) end
            end
        end
        local function label_of(b)
            if b.id == "highlight" then return self.save_highlight and _("Unhighlight") or _("Highlight") end
            return b.text_func and b.text_func() or b.text or ""
        end
        local function run(b)
            if b.enabled == false or not b.callback then return end
            if b.id == "highlight" then
                self.save_highlight = not self.save_highlight
                dict_layout(self)
                UIManager:setDirty(self, "ui")
                return
            end
            b.callback()
        end

        local close = icon_button("close", function()
            if self.in_definition_search then self:endFindInDefinition() return end
            self:onClose()
        end, function() self:onHoldClose() end, self)

        if self.is_wiki then
            ---------------------------------------------------- Wikipedia head
            local tile = FrameContainer:new{ bordersize = 0, background = T.color("surface-2"), radius = T.px("r-md"), padding = 0,
                CenterContainer:new{ dimen = Geom:new{ w = Screen:scaleBySize(36 * T.scale), h = Screen:scaleBySize(36 * T.scale) },
                    icon("leaf.lk.wiki", "icon-md") } }
            local right = {}
            local langs = self.wiki_languages or {}
            local cur = (self.lang or langs[1] or ""):lower()
            if #langs > 1 and #langs <= 4 then
                local items = {}
                for __, l in ipairs(langs) do table.insert(items, { label = l:upper(), key = l:lower() }) end
                local LeafSeg = require("leaf/widgets/seg")
                table.insert(right, LeafSeg:new{ width = #items * Screen:scaleBySize(44 * T.scale), items = items, selected = cur,
                    on_select = function(key)
                        self.ui.wikipedia:setLastSelectedLanguage(key)
                        self:lookupWikipedia(false, nil, nil, key)
                        self:onClose(true)
                    end })
                table.insert(right, HorizontalSpan:new{ width = T.px("sp-2") })
            end
            if #(self.results or {}) > 1 or self.is_wiki_fullpage then
                table.insert(right, icon_button("leaf.lk.results", function()
                    if self.is_wiki_fullpage then self:showWikiFullOtherLangsMenu() else self:showWikiResultsMenu() end
                end, nil, self))
            end
            table.insert(right, close)
            local sub = _("From Wikipedia, the free encyclopedia")
            if #(self.results or {}) > 1 then sub = T_(_("%1 · result %2 of %3"), sub, self.dict_index, #self.results) end
            table.insert(vg, sheet_head(inner, { lead = tile, title = self.displayword or self.lookupword, sub = sub, right = right, lang = self.lang_in }))
            table.insert(vg, hline(inner))
        else
            ---------------------------------------------------- dictionary head + tabs
            local right = {
                icon_button("edit", function() self:onLookupInputWord(self.word) end,
                    function() self:onLookupInputWord(self.lookupword) end, self),
                icon_button("leaf.lk.results", function() self:onShowResultsMenu() end,
                    function() self:showResultsAltMenu() end, self),
                close,
            }
            table.insert(vg, sheet_head(inner, { title = self.displayword or self.word, right = right, lang = self.lang_in }))
            if not empty then
                local names = {}
                for i, r in ipairs(self.results) do names[i] = r.dict ~= "" and r.dict or _("Dictionary") end
                table.insert(vg, tabs(inner, names, self.dict_index, function(i)
                    if i == self.dict_index then
                        -- KOReader: tap the dictionary name = make it (or not) the preferred one
                        self.ui:handleEvent(Event:new("TogglePreferredDict", self.dictionary))
                    end
                    self:changeDictionary(i)
                end))
            else
                table.insert(vg, hline(inner))
            end
        end

        ---------------------------------------------------- body
        local def = self.definition_widget
        def.padding_left, def.padding_right = pad, pad
        if empty then
            local eg = VerticalGroup:new{ align = "center",
                icon("leaf.lk.dict", "icon-2xl"),
                VerticalSpan:new{ width = T.px("sp-3") },
                text(empty == "none" and _("No dictionaries installed") or _("No dictionaries enabled"), "ui-semibold", "fs-lg", "text"),
                VerticalSpan:new{ width = T.px("sp-2") },
                TextBoxWidget:new{ text = empty == "none"
                        and _("Download a dictionary to look up words while you read, or use Wikipedia.")
                        or _("Every dictionary is switched off. Turn one on in the dictionary settings."),
                    face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), bgcolor = T.color("bg-raised"),
                    width = inner - 4 * T.px("sp-6"), alignment = "center" },
                VerticalSpan:new{ width = T.px("sp-4") },
                empty == "disabled" and btn(_("Dictionary settings"), "primary", function()
                    self:onClose(true)
                    self.ui.dictionary:showDictionariesMenu()
                end, "appbar.settings") or btn(_("Download dictionaries"), "primary", function()
                    local Menu = require("ui/widget/menu")
                    local menu
                    menu = Menu:new{ title = _("Download dictionaries"), item_table = self.ui.dictionary:_genDownloadDictionariesMenu(),
                        covers_fullscreen = true, is_borderless = true, is_popout = false,
                        close_callback = function() UIManager:close(menu) end }
                    UIManager:show(menu)
                end, "leaf.lk.download") }
            local eh = math.max(eg:getSize().h + 2 * T.px("sp-6"), math.floor(H * 0.3))
            eg:resetLayout()
            table.insert(vg, CenterContainer:new{ dimen = Geom:new{ w = inner, h = eh }, eg })
        else
            table.insert(vg, VerticalSpan:new{ width = self.is_wiki and T.px("sp-4") or T.px("sp-3") })
            table.insert(vg, def)
            if not self.is_wiki then
                table.insert(vg, VerticalSpan:new{ width = T.px("sp-4") })
                local n = #self.results
                local src = self.displaydictname or ""
                src = n > 1 and T_(_("%1 · %2 of %3 dictionaries"), src, self.dict_index, n) or src
                table.insert(vg, HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad },
                    icon("leaf.lk.dict", "icon-sm"), HorizontalSpan:new{ width = T.px("sp-1h") },
                    text(src, "ui", "fs-xs", "text-3", inner - 2 * pad - T.px("icon-sm") - T.px("sp-1h")) })
            end
            table.insert(vg, VerticalSpan:new{ width = self.is_wiki and T.px("sp-4") or T.px("sp-3") })
        end

        ---------------------------------------------------- actions
        table.insert(vg, hline(inner))
        if self.is_wiki then
            -- footer (.rd-sheet-foot): ghost actions on the left, Dictionary, Full article (primary)
            local fl = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = T.px("sp-4") } }
            local fr = HorizontalGroup:new{ align = "center" }
            local ghosts = {}
            for __, b in ipairs(defs) do
                local id = b.id
                if id == "wikipedia" then
                    -- added last (primary, right)
                elseif id == "search" and #(self.wiki_languages or {}) > 1 and #(self.wiki_languages or {}) <= 4 then
                    -- the language segment in the head does this
                elseif id ~= "close" then
                    table.insert(ghosts, b)
                end
            end
            if not self:isDocless() and self.ui.dictionary then
                table.insert(fr, btn(_("Dictionary"), "secondary", function()
                    local word = self.word
                    self:onClose(true)
                    self.ui.dictionary:onLookupWord(word, false, self.word_boxes, self.highlight)
                end, "leaf.lk.dict"))
                table.insert(fr, HorizontalSpan:new{ width = T.px("sp-2") })
            end
            for __, b in ipairs(defs) do
                if b.id == "wikipedia" then
                    table.insert(fr, btn(label_of(b), "primary", function() run(b) end, "leaf.lk.external", b.enabled))
                end
            end
            table.insert(fr, HorizontalSpan:new{ width = T.px("sp-4") })
            -- ghost actions on the left: with their label when they all fit, else icon only (hold = name)
            local room = inner - fr:getSize().w - T.px("sp-4") - T.px("sp-2")
            fr:resetLayout()
            local labelled = {}
            local need = 0
            for i, b in ipairs(ghosts) do
                labelled[i] = btn(label_of(b), "ghost", function() run(b) end, DICT_ICONS[b.id] or icon_for(b.id), b.enabled, b.hold_callback)
                need = need + labelled[i]:getSize().w + T.px("sp-1")
            end
            for i, b in ipairs(ghosts) do
                if need <= room then
                    table.insert(fl, labelled[i])
                else
                    local label = label_of(b)
                    table.insert(fl, Tap:new{ width = T.px("h-control"), height = T.px("h-control"), radius = T.px("r-md"),
                        content = icon(DICT_ICONS[b.id] or icon_for(b.id), "icon-md", b.enabled ~= false), enabled = b.enabled ~= false,
                        callback = function() run(b) end,
                        hold_callback = function() if b.hold_callback then b.hold_callback() else toast(label) end end })
                end
                table.insert(fl, HorizontalSpan:new{ width = T.px("sp-1") })
            end
            local fh = T.px("h-control") + T.px("sp-3") * 2
            table.insert(vg, OverlapGroup:new{ dimen = Geom:new{ w = inner, h = fh },
                LeftContainer:new{ dimen = Geom:new{ w = inner, h = fh }, fl },
                RightContainer:new{ dimen = Geom:new{ w = inner, h = fh }, fr } })
        else
            -- tools row (.rd-dict-acts): up to 6 per row
            local per = math.min(6, math.max(5, #defs))
            local tw = math.floor((inner - 2 * T.px("sp-2")) / per)
            local row
            for i, b in ipairs(defs) do
                if (i - 1) % per == 0 then
                    if row then table.insert(vg, row) end
                    row = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = T.px("sp-2") } }
                end
                table.insert(row, tool(DICT_ICONS[b.id] or icon_for(b.id), label_of(b), tw, Screen:scaleBySize(58 * T.scale),
                    function() run(b) end,
                    { enabled = b.enabled, hold = b.hold_callback, on = b.id == "highlight" and self.save_highlight or nil }))
            end
            if row then
                table.insert(vg, VerticalSpan:new{ width = T.px("sp-1") })
                table.insert(vg, row)
                table.insert(vg, VerticalSpan:new{ width = T.px("sp-2") })
            end
        end

        ---------------------------------------------------- place the sheet
        -- at the bottom; at the top when it would hide the looked-up word
        local probe = sheet_frame(vg, false)
        local fh = probe:getSize().h - T.px("r-xl")
        local top = false
        if self.word_boxes and #self.word_boxes > 0 and not self.is_wiki_fullpage then
            local y0, y1 = math.huge, -math.huge
            for __, b in ipairs(self.word_boxes) do y0, y1 = math.min(y0, b.y), math.max(y1, b.y + b.h) end
            if y1 > H - fh and y0 > fh then top = true end
        end
        local frame = top and sheet_frame(vg, true) or probe
        self.dict_frame = frame
        self.movable[1] = frame
        local r = T.px("r-xl")
        self[1] = Placer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H }, ox = 0, oy = top and -r or (H - fh), self.movable }
        self._leaf_top = top
        -- the stock title bar is not shown: keep its tap area off screen
        if self.dict_title then self.dict_title.dimen = Geom:new{ x = -10, y = -10, w = 1, h = 1 } end
    end
    M.dict_layout = dict_layout

    L.wrap(DictQuickLookup, "init", function(orig, self)
        self.width = Screen:getWidth()
        orig(self)
        dict_layout(self)
    end, "DictQuickLookup:init")

    L.wrap(DictQuickLookup, "update", function(orig, self)
        orig(self)
        dict_layout(self)
        UIManager:setDirty(self, "ui")
    end, "DictQuickLookup:update")

    L.wrap(DictQuickLookup, "getInitialVisibleArea", function(orig, self)
        local s = self.dict_frame:getSize()
        local H = Screen:getHeight()
        local r = T.px("r-xl")
        return Geom:new{ x = 0, y = self._leaf_top and 0 or (H - s.h + r), w = s.w, h = s.h - r }
    end, "DictQuickLookup:getInitialVisibleArea")

    -- dictionary / Wikipedia sheets dim the page behind them (like .ko-sheet over .ko-scrim)
    local Scrim = Widget:extend{ name = "LeafScrim" }
    function Scrim:init() self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } end
    function Scrim:paintTo(bb)
        local a = T.colors.paper.scrim.alpha or 0.28
        if Screen.night_mode then bb:lightenRect(0, 0, Screen:getWidth(), Screen:getHeight(), a)
        else bb:darkenRect(0, 0, Screen:getWidth(), Screen:getHeight(), a) end
    end
    L.wrap(UIManager, "show", function(orig, self, widget, ...)
        if type(widget) == "table" and widget._leaf_scrim == nil and getmetatable(widget) == DictQuickLookup then
            local s = Scrim:new{}
            widget._leaf_scrim = s
            orig(self, s, "ui", s.dimen)
        end
        return orig(self, widget, ...)
    end, "UIManager:show (lookup scrim)")

    ------------------------------------------------------------------ 4. footnote popup
    local FootnoteWidget = require("ui/widget/footnotewidget")

    local book_font_path
    local function find_book_font()
        if book_font_path ~= nil then return book_font_path end
        book_font_path = false
        pcall(function()
            local FontList = require("fontlist")
            for __, p in ipairs(FontList:getFontList() or {}) do
                if p:match("/Literata%-Regular%.ttf$") then book_font_path = p break end
            end
        end)
        return book_font_path
    end

    L.wrap(FootnoteWidget, "init", function(orig, self)
        if not G_reader_settings:isTrue("footnote_popup_use_book_font") then
            local path = find_book_font()
            if path then
                local italic = path:gsub("Literata%-Regular", "Literata-Italic")
                local bold = path:gsub("Literata%-Regular", "Literata-Bold")
                self.css = (self.css or "") .. T_("\n@font-face { font-family: 'LeafBook'; src: url('%1'); }"
                    .. "\n@font-face { font-family: 'LeafBook'; src: url('%2'); font-style: italic; }"
                    .. "\n@font-face { font-family: 'LeafBook'; src: url('%3'); font-weight: bold; }"
                    .. "\nbody { font-family: 'LeafBook'; line-height: 1.45; }\n", path, italic, bold)
            end
        end
        orig(self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local inner = W - 2 * hair
        local html = self.htmlwidget
        local single = html:getSinglePageHeight()
        local close = icon_button("close", function() self:onClose() end, nil, self)
        local right = {}
        if self.follow_callback then
            table.insert(right, btn(_("Go to note"), "ghost", function() self:onFollow() end, "leaf.lk.follow"))
            table.insert(right, HorizontalSpan:new{ width = T.px("sp-1") })
        end
        table.insert(right, close)
        local rg = HorizontalGroup:new{ align = "center" }
        for __, w in ipairs(right) do table.insert(rg, w) end
        table.insert(rg, HorizontalSpan:new{ width = T.px("sp-3") - math.floor((T.px("hit") - T.px("icon-md")) / 2) })
        local hh = T.px("hit") + T.px("sp-1")
        local head = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = hh }, HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = T.px("sp-5") }, icon("leaf.lk.footnote", "icon-sm"), HorizontalSpan:new{ width = T.px("sp-1h") },
                TextWidget:new{ text = _("FOOTNOTE"), face = L.face("ui-semibold", "fs-xs"), fgcolor = T.color("text-3") } } },
            RightContainer:new{ dimen = Geom:new{ w = inner, h = hh }, rg } }
        local body_h = single or html.height
        local body = HorizontalGroup:new{ align = "top", html }
        local pad_r = W - html.width
        if pad_r > 0 then table.insert(body, HorizontalSpan:new{ width = pad_r - 2 * hair }) end
        local body_box = single and CenterContainer:new{ dimen = Geom:new{ w = inner, h = body_h }, ignore = "height", body } or body
        local vg = VerticalGroup:new{ align = "left", grip_block(inner), head, hline(inner),
            VerticalSpan:new{ width = T.px("sp-3") }, body_box, VerticalSpan:new{ width = T.px("sp-4") } }
        local frame = sheet_frame(vg, false)
        local fh = frame:getSize().h - T.px("r-xl")
        self.container = frame
        self.height = fh
        self[1] = Placer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H }, ox = 0, oy = H - fh, frame }
    end, "FootnoteWidget:init")

    ------------------------------------------------------------------ paragraph translation panel
    -- called by patches/2-paragraph-translate.lua's Panel:build() when Leaf is on:
    -- panel = { ui, doc, block, para, word, arabic, src, has_book, prev_ok, next_ok,
    --           go(delta), onClose(), setSource(src), define(word) }
    function M.build_translate(panel)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local inner = W - 2 * hair
        local pad = T.px("sp-5")
        local ui = panel.ui
        local vg = VerticalGroup:new{ align = "left", grip_block(inner) }

        -- head: Translation / Chapter · paragraph n · English → العربية · ×
        local chapter = ""
        pcall(function() chapter = ui.toc:getTocTitleByPage(panel.block) or "" end)
        local pnum = tonumber((panel.block or ""):match("%[(%d+)%]$")) or 1
        local sub = chapter ~= "" and T_(_("%1 · paragraph %2"), chapter, pnum) or T_(_("Paragraph %1"), pnum)
        local pill_g = HorizontalGroup:new{ align = "center",
            text(_("English"), "ui", "fs-sm", "text-2"), HorizontalSpan:new{ width = T.px("sp-1h") },
            icon("leaf.lk.arrow", "icon-sm"), HorizontalSpan:new{ width = T.px("sp-1h") },
            text("العربية", "arabic", "fs-md", "text") }
        local pill_h = Screen:scaleBySize(30 * T.scale)
        local pill = Tap:new{ width = pill_g:getSize().w + 2 * T.px("sp-3"), height = pill_h, content = pill_g,
            bg = T.color("surface-2"), radius = math.floor(pill_h / 2) }
        pill_g:resetLayout()
        local close = icon_button("close", function() panel:onClose() end, nil, panel)
        table.insert(vg, sheet_head(inner, { title = _("Translation"), sub = sub,
            right = { pill, HorizontalSpan:new{ width = T.px("sp-2") }, close } }))

        -- source: In this edition / Machine (only when the book has its own translation)
        if panel.has_book then
            local LeafSeg = require("leaf/widgets/seg")
            local sw = Screen:scaleBySize(260 * T.scale)
            local seg = LeafSeg:new{ width = sw, selected = panel.src,
                items = { { label = _("In this edition"), key = "book" }, { label = _("Machine"), key = "machine" } },
                on_select = function(key) panel:setSource(key) end }
            table.insert(vg, HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad }, seg,
                HorizontalSpan:new{ width = T.px("sp-3") },
                text(panel.src == "book" and _("From the book") or _("Google Translate · online"), "ui", "fs-sm", "text-3") })
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-3") })
        end
        table.insert(vg, hline(inner))

        -- body: EN paragraph (tap a word = dictionary), dashed rule, Arabic
        local badge_s = Screen:scaleBySize(22 * T.scale)
        local function badge(s, role, size)
            return FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface-2"),
                radius = T.px("r-sm"), padding = 0,
                CenterContainer:new{ dimen = Geom:new{ w = badge_s - 2 * hair, h = badge_s - 2 * hair },
                    TextWidget:new{ text = s, face = L.face(role, size), fgcolor = T.color("text-2") } } }
        end
        local gutter = Screen:scaleBySize(34 * T.scale)
        local tw = inner - 2 * pad - gutter
        local en = TextBoxWidget:new{ text = panel.para or "", face = L.face("book", "fs-reading"), width = tw,
            line_height = 0.6, bgcolor = T.color("bg-raised"), lang = "en" }
        -- tap a word -> look it up
        local en_tap = InputContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = tw, h = en:getSize().h }, en }
        en_tap.ges_events = { TapWord = { GestureRange:new{ ges = "tap", range = function() return en_tap.dimen end } } }
        function en_tap:paintTo(bb, x, y) self.dimen.x, self.dimen.y = x, y; self[1]:paintTo(bb, x, y) end
        function en_tap:onTapWord(__, ges)
            local ok, pos = pcall(en.getCharPosAtXY, en, ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y)
            if not ok or not pos then return true end
            local cl = util.splitToChars(panel.para or "")
            local function is_word(c) return c and not c:match("^[%s%p]$") end
            if not is_word(cl[pos]) then return true end
            local a, b = pos, pos
            while a > 1 and is_word(cl[a - 1]) do a = a - 1 end
            while b < #cl and is_word(cl[b + 1]) do b = b + 1 end
            local w = table.concat(cl, "", a, b)
            if w ~= "" then panel:define(w) end
            return true
        end
        local en_block = HorizontalGroup:new{ align = "top", VerticalGroup:new{ VerticalSpan:new{ width = Screen:scaleBySize(3 * T.scale) }, badge("EN", "ui-semibold", "fs-2xs") },
            HorizontalSpan:new{ width = gutter - badge_s }, en_tap }
        local body = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-4") },
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, en_block }, VerticalSpan:new{ width = T.px("sp-4") } }
        -- dashed rule
        local Dash = Widget:extend{}
        function Dash:init() self.dimen = Geom:new{ w = inner - 2 * pad, h = hair } end
        function Dash:paintTo(bb, x, y)
            local d = T.px("sp-1")
            for xx = 0, self.dimen.w - 1, 2 * d do
                bb:paintRect(x + xx, y, math.min(d, self.dimen.w - xx), hair, T.color("border-strong"))
            end
        end
        table.insert(body, HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, Dash:new{} })
        table.insert(body, VerticalSpan:new{ width = T.px("sp-4") })
        local ar_text = panel.arabic or (panel.src == "machine"
            and _("No machine translation: this needs an internet connection.")
            or _("No translation available (needs internet for this book)."))
        local ar = TextBoxWidget:new{ text = ar_text, face = panel.arabic and L.face("arabic", "fs-reading-ar") or L.face("ui", "fs-sm"),
            fgcolor = T.color(panel.arabic and "text" or "text-3"), width = tw, line_height = panel.arabic and 0.55 or 0.3,
            bgcolor = T.color("bg-raised"), para_direction_rtl = panel.arabic and true or nil,
            alignment = panel.arabic and "right" or "left", justified = panel.arabic and true or nil, lang = panel.arabic and "ar" or nil }
        table.insert(body, HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = pad }, ar,
            HorizontalSpan:new{ width = gutter - badge_s },
            VerticalGroup:new{ VerticalSpan:new{ width = Screen:scaleBySize(3 * T.scale) }, badge("ع", "arabic", "fs-sm") } })
        table.insert(body, VerticalSpan:new{ width = T.px("sp-4") })
        table.insert(body, HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad },
            icon("leaf.lk.pointer", "icon-sm"), HorizontalSpan:new{ width = T.px("sp-1h") },
            text(_("Tap any English word to look it up."), "ui", "fs-sm", "text-3") })
        table.insert(body, VerticalSpan:new{ width = T.px("sp-4") })

        -- footer: ‹ Previous · copy · define · Next ›
        local fh = T.px("h-control") + T.px("sp-2") + T.px("sp-3")
        local mid = HorizontalGroup:new{ align = "center",
            icon_button("leaf.lk.copy", function()
                if Device:hasClipboard() and panel.arabic then
                    Device.input.setClipboardText(panel.arabic)
                    toast(_("Translation copied"))
                end
            end, nil, panel),
            icon_button("leaf.lk.dict", function() panel:define(panel.word) end, nil, panel) }
        local prev = btn(_("Previous"), "secondary", function() panel:go(-1) end, "chevron.left", panel.prev_ok)
        local nxt_g = HorizontalGroup:new{ align = "center", text(_("Next"), "ui-medium", "fs-md", panel.next_ok and "text" or "disabled"),
            HorizontalSpan:new{ width = T.px("sp-1h") }, icon("chevron.right", "icon-sm", panel.next_ok) }
        local nxt = Tap:new{ width = nxt_g:getSize().w + 2 * T.px("sp-4"), height = T.px("h-control"), content = nxt_g,
            bg = T.color("surface-2"), border = T.color("border"), radius = T.px("r-md"), enabled = panel.next_ok,
            callback = function() panel:go(1) end }
        nxt_g:resetLayout()
        local foot = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = fh },
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = fh }, HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-4") }, prev } },
            CenterContainer:new{ dimen = Geom:new{ w = inner, h = fh }, mid },
            RightContainer:new{ dimen = Geom:new{ w = inner, h = fh }, HorizontalGroup:new{ nxt, HorizontalSpan:new{ width = T.px("sp-4") } } } }

        -- the body scrolls when the paragraph is long; the sheet is at most 66% of the screen
        local fixed = vg:getSize().h + hair + fh + T.px("r-xl")
        vg:resetLayout()
        local max_body = math.floor(H * 0.66) - fixed
        local bh = body:getSize().h
        body:resetLayout()
        if bh > max_body then
            local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
            local sc = ScrollableContainer:new{ dimen = Geom:new{ w = inner, h = max_body }, show_parent = panel, body }
            panel.cropping_widget = sc
            table.insert(vg, sc)
        else
            panel.cropping_widget = nil
            table.insert(vg, body)
        end
        table.insert(vg, hline(inner))
        table.insert(vg, foot)
        local frame = sheet_frame(vg, false)
        local sh = frame:getSize().h - T.px("r-xl")
        panel.frame = frame
        panel[1] = Placer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H }, ox = 0, oy = H - sh, frame }
        panel.frame_rect = Geom:new{ x = 0, y = H - sh, w = W, h = sh }
    end
end

return M
