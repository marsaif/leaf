--[[
    Leaf typesetting panel (safety-net item 21; prototype overlay "typeset", js/screens/reader.js +
    css/screens/reader.css): KOReader's ConfigDialog (bottom panel in the reader, EPUB and PDF/DjVu).

    * Sheet: --bg-raised, --r-xl top corners, grip, .ko-sheet-head (tab title --fs-head semibold +
      "EPUB · reflowable · using your defaults" --fs-sm --text-3, close), a hairline, the scrolling
      body (60% of the screen, like .rd-ts), a hairline, then the tab bar (icon over an --fs-2xs
      label, the active one in accent).
    * Tabs, EPUB: Presets · Text · Font · Margins · Page · Layout · Contrast · Style. KOReader's
      groups are regrouped as the prototype's RD.tsTabs (line spacing and font weight move to Text);
      Presets and Font are Leaf tabs. PDF/DjVu: KOReader's groups, renamed (Rotate · Crop · Zoom ·
      Page · Reflow · Contrast · Document). Every KOReader option stays in exactly one tab.
    * Options in a card (.rd-card): icon tile + left-aligned label (+ (i) help where KOReader has
      help text, shown inline) + control:
        - stepped numbers (buttonprogress, font size) = slider row (label, −, slider, +, value);
          − / + are KOReader's fine-tune (or one step), tapping the value opens KOReader's "⋮" dialog;
        - on/off toggles = switch row; small choice sets = segmented control (inline when it fits,
          stacked under the label otherwise), with KOReader's "⋮" as the last segment;
        - rotation = four device cards; PDF zoom direction = the eight direction diagrams.
      Hold a value / segment / − / + = KOReader's "Set as default"; hold a label = KOReader's value list.
    * Font tab: ReaderFont's font list (category chips, radio, name in its own face, "Ag" sample;
      hold = KOReader's default/fallback choice), its two main font settings and a link to KOReader's
      font settings menu. Presets tab: Default / Comfort / Compact / Large print + saved presets,
      Save as default · Save as preset · Reset (KOReader has no typesetting presets).
    * Text tab links to KOReader's typography menu, Style tab lists the style sheets (ReaderTypeset)
      and links to the other style sheets and to Style tweaks.
    KOReader's events, settings, defaults and hold-to-set-default are used as they are.
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
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

---------------------------------------------------------------- data (prototype reader.js)
-- KOReader group icon -> { tab key, label, Lucide icon }
local TAB_META = {
    epub = {
        ["appbar.rotation"] = { "layout", _("Layout"), "smartphone" },
        ["appbar.crop"] = { "margins", _("Margins"), "square-dashed" },
        ["appbar.pageview"] = { "page", _("Page"), "book-open" },
        ["appbar.textsize"] = { "text", _("Text"), "a-large-small" },
        ["appbar.contrast"] = { "contrast", _("Contrast"), "contrast" },
        ["appbar.settings"] = { "style", _("Style"), "sliders-horizontal" },
    },
    pdf = {
        ["appbar.rotation"] = { "rotate", _("Rotate"), "smartphone" },
        ["appbar.crop"] = { "crop", _("Crop"), "crop" },
        ["appbar.pagefit"] = { "zoom", _("Zoom"), "scan" },
        ["appbar.pageview"] = { "page", _("Page"), "book-open" },
        ["appbar.textsize"] = { "reflow", _("Reflow"), "wrap-text" },
        ["appbar.contrast"] = { "contrast", _("Contrast"), "contrast" },
        ["appbar.settings"] = { "doc", _("Document"), "file-cog" },
    },
}
local EPUB_ORDER = { "presets", "text", "font", "margins", "page", "layout", "contrast", "style" }
local MOVE = { line_spacing = "text", font_base_weight = "text" } -- EPUB only
local TEXT_PRI = { "font_size", "font_fine_tune", "line_spacing", "font_base_weight", "word_spacing", "word_expansion", "cjk_width_scaling" }
local PDF_PRI = { "text_wrap", "zoom_mode_genus", "zoom_mode_type", "zoom_range_number", "zoom_factor", "zoom_direction", "zoom_overlap_h", "zoom_overlap_v" }

local TITLES = {
    font_size = _("Font size"), cjk_width_scaling = _("CJK width scaling"), zoom_range_number = _("Columns / rows"),
    visible_pages = _("Two columns"), status_line = _("Alt status bar"), font_gamma = _("Contrast"), sw_dithering = _("Dithering"),
    hw_dithering = _("Dithering"), h_page_margins = _("Side margins"), t_page_margin = _("Top margin"), b_page_margin = _("Bottom margin"),
    sync_t_b_page_margins = _("Sync top & bottom"), zoom_mode_genus = _("Zoom to"), zoom_mode_type = _("Fit"),
    zoom_direction = _("Direction"), max_columns = _("Columns"), rotation_mode = _("Rotation"), trim_page = _("Page crop"),
    page_margin = _("Margin"), text_wrap = _("Reflow"),
}
-- engineering names -> human names (+ value labels); the KOReader name is shown under the label
local HUMAN = {
    block_rendering_mode = { _("Layout engine"), { _("Simple"), _("Flat"), _("Book"), _("Web") } },
    render_dpi = { _("Content zoom"), { _("Device"), "½×", "1×", "1.7×", "2.2×", "3×" } },
    font_hinting = { _("Sharpen text"), { _("Off"), _("Font's own"), _("Auto") } },
    font_kerning = { _("Letter fitting"), { _("Off"), _("Fast"), _("Good"), _("Best") } },
    smooth_scaling = { _("Image quality"), { _("Fast"), _("Smooth") } },
    writing_direction = { _("Writing direction"), { _("Left to right"), _("Right to left"), _("Vertical (CJK)") } },
    defect_size = { _("Ignore specks smaller than"), { _("Small"), _("Medium"), _("Large") } },
    page_opt = { _("Remove watermarks") },
    forced_ocr = { _("Always use OCR") },
}
local SUBS = {
    embedded_css = _("Publisher stylesheets"), embedded_fonts = _("Publisher fonts"), nightmode_images = _("Invert images in night mode"),
    sync_t_b_page_margins = _("Keep text vertically centred"), text_wrap = _("Extract the text and reflow it to the screen"),
    page_opt = _("Remove watermarks and grey backgrounds"), background_cleanup = _("Black & white essentials only"),
    sw_dithering = _("Smoother greys on e-ink"), hw_dithering = _("Smoother greys on e-ink"),
    forced_ocr = _("OCR even when a text layer exists"), detect_indent = _("Keep paragraph indents when reflowing"),
    nightmode_document = _("Invert pages in night mode"), status_line = _("Time and battery in the page header"),
    visible_pages = _("Two pages side by side"),
}
local OPT_ICONS = {
    font_size = "a-large-small", line_spacing = "rows-3", font_base_weight = "bold", word_spacing = "space", word_expansion = "move-horizontal",
    cjk_width_scaling = "languages", h_page_margins = "move-horizontal", t_page_margin = "arrow-up-to-line", b_page_margin = "arrow-down-to-line",
    sync_t_b_page_margins = "link", view_mode = "scroll-text", block_rendering_mode = "layers", render_dpi = "zoom-in", font_gamma = "contrast",
    font_hinting = "grid-3x3", font_kerning = "baseline", status_line = "panel-top", embedded_css = "file-code", embedded_fonts = "type",
    smooth_scaling = "image", nightmode_images = "image-off", visible_pages = "columns-2", trim_page = "crop", page_margin = "square-dashed",
    auto_straighten = "ruler", zoom_overlap_h = "move-horizontal", zoom_overlap_v = "move-vertical", zoom_mode_type = "maximize",
    zoom_range_number = "columns-3", zoom_factor = "zoom-in", zoom_mode_genus = "scan", zoom_direction = "route", page_scroll = "scroll-text",
    page_gap_height = "separator-horizontal", justification = "align-justify", text_wrap = "wrap-text", contrast = "contrast",
    saturation = "palette", white_threshold = "sun-dim", page_opt = "eraser", background_cleanup = "sparkles", hw_dithering = "grip",
    sw_dithering = "grip", quality = "gauge", doc_language = "languages", forced_ocr = "scan-text", writing_direction = "arrow-left-right",
    defect_size = "sparkle", detect_indent = "indent-increase", nightmode_document = "moon", max_columns = "columns-3", rotation_mode = "rotate-cw",
    line_spacing_pdf = "rows-3",
}
local UNITS = {
    font_size = function(pdf) return pdf and "×" or "pt" end, line_spacing = function(pdf) return pdf and "" or "%" end,
    h_page_margins = "px", t_page_margin = "px", b_page_margin = "px", cjk_width_scaling = "%", page_gap_height = "px",
    zoom_overlap_h = "px", zoom_overlap_v = "px",
}
-- built-in presets (KOReader units; margins are KOReader's {left, right} tables)
local PRESETS = {
    { _("Default"), {} },
    { _("Comfort"), { font_size = 24, line_spacing = 115, h_page_margins = { 30, 30 }, t_page_margin = 20, b_page_margin = 20 } },
    { _("Compact"), { font_size = 20, line_spacing = 90, h_page_margins = { 10, 10 }, t_page_margin = 10, b_page_margin = 10 } },
    { _("Large print"), { font_size = 34, line_spacing = 110, h_page_margins = { 15, 15 }, font_base_weight = 0.5, font_gamma = 25 } },
}

local function upvalue(fn, wanted)
    local i = 1
    while true do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value end
        i = i + 1
    end
end

local function indexof(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
end

local function scalar(v)
    if type(v) == "table" then v = v[1] end
    return type(v) == "number" and v or tonumber(v)
end

local function same(a, b)
    if type(a) == "table" or type(b) == "table" then
        if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    if type(a) == "number" and type(b) == "number" then return math.abs(a - b) < 1e-6 end
    return a == b
end

local function fmt_num(v)
    v = scalar(v) or v
    if type(v) ~= "number" then return tostring(v or "") end
    if v == math.floor(v) then return string.format("%d", v) end
    return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function cap(s)
    s = tostring(s or "")
    return (s:gsub("^%l", string.upper))
end

local function sentence(s)
    -- "Line Spacing" -> "Line spacing" (keeps acronyms: "OCR", "L/R")
    local out, first = {}, true
    for w in tostring(s or ""):gmatch("%S+") do
        if first or (w:match("^[%u/]+$") and #w > 1) then table.insert(out, w) else table.insert(out, w:lower()) end
        first = false
    end
    return table.concat(out, " ")
end

---------------------------------------------------------------- regrouping (RD.tsTabs)
local function regroup(src, pdf)
    local kind = pdf and "pdf" or "epub"
    local tabs, by = {}, {}
    local function tab(key, label, icon)
        if not by[key] then
            by[key] = { leaf_key = key, leaf_label = label, icon = "leaf.ts." .. icon, options = {} }
            table.insert(tabs, by[key])
        end
        return by[key]
    end
    local function meta(g)
        local m = TAB_META[kind][g.icon]
        if m then return m end
        local k = tostring(g.icon or "more"):gsub("^appbar%.", "")
        return { k, cap(k), "sliders-horizontal" }
    end
    if not pdf then
        tab("presets", _("Presets"), "sparkles")
        tab("font", _("Font"), "type")
    end
    for __, g in ipairs(src) do local m = meta(g); tab(m[1], m[2], m[3]) end
    for __, g in ipairs(src) do
        for __, o in ipairs(g.options or {}) do
            local key = (not pdf and MOVE[o.name]) or meta(g)[1]
            table.insert(by[key].options, o)
        end
    end
    local function stable_sort(list, rank)
        local idx = {}
        for i, o in ipairs(list) do idx[o] = i end
        table.sort(list, function(a, b)
            local ra, rb = rank(a), rank(b)
            if ra ~= rb then return ra < rb end
            return idx[a] < idx[b]
        end)
    end
    if pdf then
        for __, t in ipairs(tabs) do stable_sort(t.options, function(o) return indexof(PDF_PRI, o.name) or 99 end) end
    else
        if by.text then stable_sort(by.text.options, function(o) return indexof(TEXT_PRI, o.name) or 99 end) end
        stable_sort(tabs, function(t) return indexof(EPUB_ORDER, t.leaf_key) or 99 end)
        if by.text then by.text.leaf_title = _("Text & spacing") end
    end
    local out = { prefix = src.prefix, _leaf_src = src, _leaf_pdf = pdf }
    for i, t in ipairs(tabs) do out[i] = t end
    return out
end

---------------------------------------------------------------- module
function M.apply(L)
    local T = L.T
    local fonts = require("leaf/fonts")
    local ConfigDialog = require("ui/widget/configdialog")
    local ToggleSwitch = require("ui/widget/toggleswitch")
    local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
    local IconButton = require("ui/widget/iconbutton")
    local Button = require("ui/widget/button")
    local LeafSlider = require("leaf/widgets/slider")
    local LeafToggle = require("leaf/widgets/toggle")
    local Notification = require("ui/widget/notification")
    local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    local Font = require("ui/font")
    local hair = T.px("hairline")
    local ui_face = fonts.FILES["ui"]
    -- raw CSS px from the prototype (reader.css) -> device px
    local function px(n) return Screen:scaleBySize(n * T.scale) end
    -- selection = accent; on e-ink (greys) the accent is too light: --text + a 2px outline (.eink .ko-seg button.on)
    local function eink() return not Screen:isColorEnabled() end
    local function SEL() return eink() and "text" or "accent" end
    local function SEL_BW() return eink() and T.px("bw-lg") or T.px("bw-md") end

    local MenuBar = upvalue(ConfigDialog.update, "MenuBar")
    local ConfigPanel = upvalue(ConfigDialog.update, "ConfigPanel")
    local ConfigOption = ConfigPanel and upvalue(ConfigPanel.init, "ConfigOption")

    ---------------------------------------------------------------- fallback restyle (KOReader's own widgets)
    if ConfigOption then
        L.wrap(ConfigOption, "init", function(orig, self)
            for __, opt in ipairs(self.options or {}) do
                if not opt.name_font_face then
                    opt.name_font_face = ui_face
                    opt.name_font_size = T.fs("fs-md")
                end
            end
            return orig(self)
        end, "ConfigOption:init")
    end
    L.wrap(ToggleSwitch, "init", function(orig, self)
        self.font_face = ui_face
        self.font_size = T.fs("fs-sm")
        orig(self)
        local f = self.toggle_frame
        f.background = T.color("surface-2")
        f.color = T.color("border")
        f.radius = T.px("r-md")
    end, "ToggleSwitch:init")
    L.wrap(ToggleSwitch, "update", function(orig, self)
        orig(self)
        local pos = self.position
        for i = 1, #self.toggle_content do
            local row = self.toggle_content[i]
            for j = 1, #row do
                local cell = row[j]
                local on = pos == (i - 1) * self.n_pos + j
                cell.radius = T.px("r-inner")
                cell.background = T.color(on and "surface" or "surface-2")
                cell.color = T.color(on and "accent" or "surface-2")
                local label = cell[1] and cell[1][1]
                if label then label.fgcolor = T.color(on and "accent" or "text-2") end
            end
        end
    end, "ToggleSwitch:update")
    L.wrap(ButtonProgressWidget, "update", function(orig, self)
        self.font_face = ui_face
        self.font_size = T.fs("fs-md")
        orig(self)
        local c = self.buttonprogress_content
        for k = 1, #c do
            local b = c[k]
            local f = b and b.frame
            if f and b.text ~= nil then
                f.invert = false
                if b.text == "" then
                    local on = b.preselect or b.no_focus
                    f.background = T.color(on and "accent" or "surface-3")
                    f.color = f.background
                    f.radius = T.px("r-tick")
                else
                    f.background = nil
                    f.color = T.color("border")
                    f.radius = T.px("r-sm")
                    if b.label_widget then b.label_widget.fgcolor = T.color("text-2") end
                end
            end
        end
    end, "ButtonProgressWidget:update")

    ---------------------------------------------------------------- small widgets
    -- a tappable / holdable box around one child
    local Tap = InputContainer:extend{ callback = nil, hold_callback = nil, enabled = true }
    function Tap:init()
        local sz = self[1]:getSize()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.w or sz.w, h = self.h or sz.h }
        local range = function() return self.dimen end
        self.ges_events = {
            TapLeaf = { GestureRange:new{ ges = "tap", range = range } },
            HoldLeaf = { GestureRange:new{ ges = "hold", range = range } },
        }
    end
    function Tap:getSize() return self.dimen end
    function Tap:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        self[1]:paintTo(bb, x, y)
    end
    function Tap:onTapLeaf()
        if not self.callback then return end
        if self.enabled then self.callback() end
        return true
    end
    function Tap:onHoldLeaf()
        if self.hold_callback then self.hold_callback() return true end
    end

    -- a box drawn by a function (rounded rects, discs, diagrams)
    local Paint = Widget:extend{ w = 0, h = 0, draw = nil }
    function Paint:init() self.dimen = Geom:new{ x = 0, y = 0, w = self.w, h = self.h } end
    function Paint:getSize() return self.dimen end
    function Paint:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        self.draw(bb, x, y, self.w, self.h)
    end

    local function hline(w)
        return LineWidget:new{ dimen = Geom:new{ w = w, h = hair }, background = T.color("border") }
    end

    local function icon(name, size, dim)
        return IconWidget:new{ icon = name, width = size, height = size, alpha = true, dim = dim }
    end

    -- filled rounded rect with a border of width bw
    local function box(bb, x, y, w, h, r, fill, edge, bw)
        bb:paintRoundedRect(x, y, w, h, edge, r)
        bb:paintRoundedRect(x + bw, y + bw, w - 2 * bw, h - 2 * bw, fill, math.max(0, r - bw))
    end

    -- a tick drawn in pixels (.ko-selmark): two thick strokes
    local function tick(bb, cx, cy, s, color)
        local t = math.max(2, math.floor(s / 7))
        local function seg(x0, y0, x1, y1)
            local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
            for i = 0, n do
                local x = x0 + math.floor((x1 - x0) * i / n + 0.5)
                local y = y0 + math.floor((y1 - y0) * i / n + 0.5)
                bb:paintRect(x - math.floor(t / 2), y - math.floor(t / 2), t, t, color)
            end
        end
        local h = math.floor(s / 2)
        seg(cx - h, cy, cx - math.floor(h / 3), cy + math.floor(h * 2 / 3))
        seg(cx - math.floor(h / 3), cy + math.floor(h * 2 / 3), cx + h, cy - math.floor(h * 2 / 3))
    end

    -- .ko-icon-tile: 32px, --r-md, --surface-2, hairline --border, 18px icon
    local function tile(name, enabled)
        local s = T.px("h-chip")
        return FrameContainer:new{
            bordersize = hair, color = T.color("border"), background = T.color("surface-2"),
            radius = T.px("r-md"), padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = s - 2 * hair, h = s - 2 * hair },
                icon("leaf.ts." .. (name or "sliders-horizontal"), T.px("icon-tile"), enabled == false) },
        }
    end

    -- row frame: fixed width and height, left group and optional right group
    local function lr(w, h, left, right)
        local g = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h },
            LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, left } }
        if right then table.insert(g, RightContainer:new{ dimen = Geom:new{ w = w, h = h }, right }) end
        return g
    end

    local function text(s, role, size, color, max_w)
        return TextWidget:new{ text = s, face = L.face(role, size), fgcolor = T.color(color or "text"),
            max_width = max_w and math.max(max_w, px(40)) or nil }
    end
    local function text_w(s, role, size)
        local tw = TextWidget:new{ text = s, face = L.face(role, size) }
        local w = tw:getSize().w
        tw:free()
        return w
    end

    -- title (+ small line under it)
    local function label_block(title, sub, max_w, o)
        o = o or {}
        local g = VerticalGroup:new{ align = "left",
            text(title, o.role or "ui-medium", "fs-md", o.enabled == false and "disabled" or "text", max_w) }
        if sub and sub ~= "" then
            table.insert(g, VerticalSpan:new{ width = T.px("sp-half") })
            table.insert(g, text(sub, "ui", o.sub_size or "fs-sm", "text-3", max_w))
        end
        return g
    end

    ---------------------------------------------------------------- KOReader option plumbing
    local function opt_enabled(d, o)
        if o.enabled_func then return o.enabled_func(d.configurable, d.document) and true or false end
        return true
    end
    local function opt_shown(d, o)
        if o.show == false then return false end
        if o.show_func then return o.show_func(d.configurable, d.document) and true or false end
        return true
    end
    local function name_text(d, o)
        return o.name_text_func and o.name_text_func(d.configurable, d.document) or o.name_text or o.alt_name_text
    end
    local function opt_title(d, o)
        return (HUMAN[o.name] and HUMAN[o.name][1]) or TITLES[o.name] or sentence(name_text(d, o) or o.name)
    end
    local function ko_name(d, o)
        if HUMAN[o.name] then return T_(_("KOReader: %1"), name_text(d, o) or o.name) end
    end
    local function current_value(d, o)
        if o.current_func then return o.current_func() end
        return d.configurable[o.name]
    end
    -- KOReader's ConfigOption logic: exact match or the nearest value -> index, exact
    local function current_index(d, o)
        local val = current_value(d, o)
        if o.values and #o.values > 0 then
            local best, best_diff
            for i, v in ipairs(o.values) do
                if same(val, v) then return i, true end
                local a, b = scalar(val), scalar(v)
                local diff = (a and b) and math.abs(a - b) or 1
                if not best_diff or diff <= best_diff then best, best_diff = i, diff end
            end
            return best, false
        elseif o.args then
            for i, a in ipairs(o.args) do if same(a, val) then return i, true end end
        end
        return nil, false
    end
    local function choose(d, o, pos, source)
        if not opt_enabled(d, o) then return end
        Notification:setNotifySource(source or Notification.SOURCE_BOTTOM_MENU_TOGGLE)
        d:onConfigChoose(o.values, o.name, o.event, o.args, pos, o.hide_on_apply)
        UIManager:tickAfterNext(function() Notification:resetNotifySource() end)
    end
    local function make_default(d, o, pos, labels)
        if pos then d:onMakeDefault(o.name, name_text(d, o), o.values or o.args, labels or o.labels or o.values or o.args, pos) end
    end
    local function more(d, o)
        if not o.more_options then return end
        if o.show_true_value_func and o.more_options_param and not o.more_options_param.show_true_value_func then
            o.more_options_param.show_true_value_func = o.show_true_value_func
        end
        Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_MORE)
        local dvo = o.default_value
        local p = o.more_options_param
        if p and p.names then
            local o1, o2 = d:findOptionByName(p.names[1]), d:findOptionByName(p.names[2])
            dvo = { o1 and o1.default_value, o2 and o2.default_value }
        end
        d:onConfigMoreChoose(o.values, dvo, o.name, o.event, "⋮", name_text(d, o), p)
        UIManager:tickAfterNext(function() Notification:resetNotifySource() end)
    end
    local function show_values(d, o)
        if o.name_text_hold_callback then
            o.name_text_hold_callback(d.configurable, o, d.config_options.prefix, d.document)
        end
    end
    local function refresh(d)
        d:update()
        UIManager:setDirty(d, "ui", d.dialog_frame.dimen)
    end
    -- KOReader's default for an option (as ConfigOption reads it)
    local function default_of(d, o)
        local v = G_reader_settings:readSetting(d.config_options.prefix .. "_" .. o.name)
        if v == nil then v = o.default_value end
        return v
    end
    local function all_options(d)
        local list = {}
        for __, g in ipairs(d.config_options) do
            for __, o in ipairs(g.options) do
                if o.name and o.values and #o.values > 0 and not o.current_func and o.name ~= "font_fine_tune" then
                    table.insert(list, o)
                end
            end
        end
        return list
    end
    local function font_default(d)
        return G_reader_settings:readSetting("cre_font") or (d.document and d.document.default_font)
    end
    local function differing(d)
        local n = 0
        for __, o in ipairs(all_options(d)) do
            local dv = default_of(d, o)
            if dv ~= nil and d.configurable[o.name] ~= nil and not same(d.configurable[o.name], dv) then n = n + 1 end
        end
        if not d.config_options._leaf_pdf and d.ui and d.ui.font and d.ui.font.font_face then
            local def = font_default(d)
            if def and def ~= d.ui.font.font_face then n = n + 1 end
        end
        return n
    end
    -- apply a value from outside the controls (presets / reset): the calls onConfigChoose makes
    local function apply_value(d, o, v)
        local pos
        for i, x in ipairs(o.values or {}) do if same(x, v) then pos = i end end
        local arg = v
        if pos and o.args then arg = o.args[pos] end
        if o.values then d:onConfigChoice(o.name, v) end
        if o.event then d:onConfigEvent(o.event, arg) end
    end

    -- open a reader main menu entry of the typeset tab, e.g. { "style_tweaks" } or { "change_font", 1 }
    local function open_menu(d, path)
        local ui = d.ui
        if not (ui and ui.menu) then return end
        d:closeDialog()
        UIManager:nextTick(function()
            ui.menu:onShowMenu()
            local tm = ui.menu.menu_container and ui.menu.menu_container[1]
            if not (tm and tm.tab_item_table and tm.bar) then return end
            for i, tab in ipairs(tm.tab_item_table) do
                if tab.icon == "appbar.typeset" then tm.bar:switchToTab(i) end
            end
            for __, step in ipairs(path) do
                local hit
                if type(step) == "number" then hit = tm.item_table[step]
                else
                    for __, item in ipairs(tm.item_table) do if item.id == step then hit = item end end
                end
                if not hit then return end
                tm:onMenuSelect(hit)
            end
        end)
    end

    ---------------------------------------------------------------- segmented control
    -- .ko-seg: --surface-2 track (--r-md, 3px padding, --sp-half gaps); on = --surface, accent outline + label
    local Seg = InputContainer:extend{ items = nil, width = nil, stretch = false, enabled = true }
    function Seg:init()
        local pad, gap = px(3), T.px("sp-half")
        local h = T.px("h-seg")
        local cell_pad = T.px("sp-2h")
        local min_w = px(38)
        local n = #self.items
        local widths = {}
        local natural = 2 * pad + (n - 1) * gap
        for i, it in ipairs(self.items) do
            widths[i] = math.max(min_w, text_w(it.label, "ui-semibold", "fs-sm") + 2 * cell_pad)
            natural = natural + widths[i]
        end
        self.natural_w = natural
        local W = self.width or natural
        if self.stretch or natural > W then
            local each = math.floor((W - 2 * pad - (n - 1) * gap) / n)
            for i = 1, n do widths[i] = each end
        end
        local row = HorizontalGroup:new{ align = "center" }
        self.cells = {}
        local bw = SEL_BW()
        for i, it in ipairs(self.items) do
            local on = it.on
            local fg = not self.enabled and "disabled" or (on and SEL() or "text-2")
            local cw = widths[i]
            local enabled = self.enabled
            local cell = Paint:new{ w = cw, h = h, draw = function(bb, x, y, w, hh)
                if on then box(bb, x, y, w, hh, T.px("r-inner"), T.color("surface"), T.color(enabled and SEL() or "disabled"), bw) end
            end }
            local label = TextWidget:new{ text = it.label, face = L.face(on and "ui-semibold" or "ui", "fs-sm"), fgcolor = T.color(fg),
                max_width = cw - T.px("sp-1") }
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
            table.insert(row, OverlapGroup:new{ dimen = Geom:new{ w = cw, h = h }, cell,
                CenterContainer:new{ dimen = Geom:new{ w = cw, h = h }, label } })
            self.cells[i] = cell
        end
        local total = 2 * pad + (n - 1) * gap
        for i = 1, n do total = total + widths[i] end
        local th = h + 2 * pad
        self.dimen = Geom:new{ x = 0, y = 0, w = total, h = th }
        self[1] = OverlapGroup:new{ dimen = Geom:new{ w = total, h = th },
            Paint:new{ w = total, h = th, draw = function(bb, x, y, w, hh)
                bb:paintRoundedRect(x, y, w, hh, T.color("surface-2"), T.px("r-md"))
            end },
            CenterContainer:new{ dimen = Geom:new{ w = total, h = th }, row } }
        local range = function() return self.dimen end
        self.ges_events = {
            TapSeg = { GestureRange:new{ ges = "tap", range = range } },
            HoldSeg = { GestureRange:new{ ges = "hold", range = range } },
        }
    end
    function Seg:getSize() return self.dimen end
    function Seg:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        InputContainer.paintTo(self, bb, x, y)
    end
    function Seg:_hit(ges)
        for i, c in ipairs(self.cells) do
            local dm = c.dimen
            if dm and ges and ges.pos and ges.pos.x >= dm.x and ges.pos.x < dm.x + dm.w then return i end
        end
    end
    function Seg:onTapSeg(__, ges)
        local i = self:_hit(ges)
        if i and self.enabled and self.on_tap then self.on_tap(i) end
        return true
    end
    function Seg:onHoldSeg(__, ges)
        local i = self:_hit(ges)
        if i and self.on_hold then self.on_hold(i) end
        return true
    end

    ---------------------------------------------------------------- the body builder
    -- ctx = { d = dialog, pdf, w = body width, cw = card inner width, fine_tune = font_fine_tune option }
    local B = {}

    local function help_button(ctx, o)
        if not o.help_text then return nil end
        local on = ctx.d._leaf_help == o.name
        local s = px(30)
        return Tap:new{ w = s, h = s,
            callback = function()
                ctx.d._leaf_help = (ctx.d._leaf_help ~= o.name) and o.name or nil
                refresh(ctx.d)
            end,
            OverlapGroup:new{ dimen = Geom:new{ w = s, h = s },
                Paint:new{ w = s, h = s, draw = function(bb, x, y, w, h)
                    if on then bb:paintCircle(x + math.floor(w / 2), y + math.floor(h / 2), math.floor(w / 2), T.color("accent-soft")) end
                end },
                CenterContainer:new{ dimen = Geom:new{ w = s, h = s }, icon("info", T.px("icon-sm"), not on) } } }
    end
    local function help_body(ctx, o)
        if not (o.help_text and ctx.d._leaf_help == o.name) then return nil end
        local p = T.px("sp-3")
        return VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = T.px("sp-1") },
            FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface"),
                radius = T.px("r-md"), padding = p, margin = 0,
                TextBoxWidget:new{ text = o.help_text, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"),
                    bgcolor = T.color("surface"), width = ctx.cw - 2 * p - 2 * hair } },
            VerticalSpan:new{ width = T.px("sp-3") } }
    end
    local function with_help(ctx, o, row)
        local hb = help_body(ctx, o)
        if not hb then return row end
        return VerticalGroup:new{ align = "left", row, hb }
    end
    -- the left part of an option row: tile, label (+ KOReader name), help
    local function head(ctx, o, max_w)
        local en = opt_enabled(ctx.d, o)
        local gap = T.px("sp-3")
        local hb = help_button(ctx, o)
        local hb_w = hb and (hb:getSize().w + T.px("sp-1")) or 0
        local tw = max_w - T.px("h-chip") - gap - hb_w
        local lb = label_block(opt_title(ctx.d, o), ko_name(ctx.d, o), tw, { enabled = en, sub_size = "fs-xs" })
        local g = HorizontalGroup:new{ align = "center", tile(OPT_ICONS[o.name], en), HorizontalSpan:new{ width = gap },
            Tap:new{ hold_callback = function() show_values(ctx.d, o) end, lb } }
        if hb then
            table.insert(g, HorizontalSpan:new{ width = T.px("sp-1") })
            table.insert(g, hb)
        end
        return g
    end

    -- slider row (.ko-sr in .rd-num): label column, −, slider, +, value
    function B.slider(ctx, o)
        local d = ctx.d
        local values = o.values
        local n = #values
        local pos, exact = current_index(d, o)
        pos = pos or 1
        local cur = current_value(d, o)
        local en = opt_enabled(d, o)
        -- knob position: interpolated between the stepped values (they may be descending)
        local f0 = pos - 1
        local cv = scalar(cur)
        if not exact and cv then
            local asc = (scalar(values[n]) or 0) >= (scalar(values[1]) or 0)
            local function norm(v) return asc and v or -v end
            f0 = norm(cv) > norm(scalar(values[n])) and (n - 1) or 0
            for i = 1, n - 1 do
                local lo, hi = norm(scalar(values[i])), norm(scalar(values[i + 1]))
                if norm(cv) >= lo and norm(cv) <= hi then
                    f0 = i - 1 + (norm(cv) - lo) / ((hi - lo) ~= 0 and (hi - lo) or 1)
                    break
                end
            end
        end
        local pct = n > 1 and f0 / (n - 1) or 0
        local function shown(i, is_exact)
            if not is_exact then return fmt_num(cur) end
            if o.labels and o.labels[i] ~= nil then return fmt_num(o.labels[i]) end
            return fmt_num(values[i])
        end
        local unit = UNITS[o.name]
        if type(unit) == "function" then unit = unit(ctx.pdf) end
        local fine = o.name == "font_size" and ctx.fine_tune or nil -- KOReader's decrease/increase toggle
        local title = opt_title(d, o)

        local gap = T.px("sp-2")
        local step_w, val_w = px(36), px(54)
        local hb = help_button(ctx, o)
        local hb_w = hb and (hb:getSize().w + T.px("sp-1")) or 0
        local lbl_w = math.max(px(172), T.px("h-chip") + T.px("sp-3") + text_w(title, "ui", "fs-md") + hb_w + gap)
        local slider_w = ctx.cw - lbl_w - 2 * step_w - val_w - 3 * gap
        if slider_w < px(80) then
            lbl_w = lbl_w - (px(80) - slider_w)
            slider_w = px(80)
        end
        local left = HorizontalGroup:new{ align = "center", tile(OPT_ICONS[o.name], en), HorizontalSpan:new{ width = T.px("sp-3") },
            Tap:new{ hold_callback = function() show_values(d, fine or o) end,
                text(title, "ui", "fs-md", en and "text" or "disabled", lbl_w - T.px("h-chip") - T.px("sp-3") - hb_w - gap) } }
        if hb then table.insert(left, HorizontalSpan:new{ width = T.px("sp-1") }); table.insert(left, hb) end

        local value_text = TextWidget:new{ text = shown(pos, exact), face = L.face("ui-medium", "fs-md"), fgcolor = T.color(en and "text" or "disabled") }
        local value_group = HorizontalGroup:new{ align = "bottom", value_text }
        if unit and unit ~= "" then
            table.insert(value_group, HorizontalSpan:new{ width = px(1) })
            table.insert(value_group, text(unit, "ui", "fs-xs", "text-3"))
        end
        local hit = T.px("hit")
        local value = Tap:new{ w = val_w, h = hit,
            callback = function() more(d, fine or o) end,
            hold_callback = function()
                if fine then d:onMakeFineTuneDefault("font_size", _("Font Size"), fine.values or fine.args, fine.toggle, "+")
                else make_default(d, o, pos) end
            end,
            RightContainer:new{ dimen = Geom:new{ w = val_w, h = hit }, value_group } }

        local slider
        slider = LeafSlider:new{ width = slider_w, pct = pct, enabled = en, show_parent = d,
            on_change = function(frac, final)
                local i = 1 + math.floor(frac * (n - 1) + 0.5)
                if final then
                    if not (exact and i == pos) then choose(d, o, i, Notification.SOURCE_BOTTOM_MENU_PROGRESS) end
                    return
                end
                value_text:setText(shown(i, true))
                slider:setPct(n > 1 and (i - 1) / (n - 1) or 0)
                UIManager:setDirty(d, "ui", value.dimen)
            end }

        local function step(dir)
            if fine then
                choose(d, fine, dir < 0 and 1 or 2, Notification.SOURCE_BOTTOM_MENU_FINE)
            elseif o.fine_tune then
                if not en then return end
                Notification:setNotifySource(Notification.SOURCE_BOTTOM_MENU_FINE)
                d:onConfigFineTuneChoose(o.values, o.name, o.event, o.args, dir < 0 and "-" or "+", o.hide_on_apply, o.fine_tune_param)
                UIManager:tickAfterNext(function() Notification:resetNotifySource() end)
            else
                -- one step along KOReader's list; between two steps go to the neighbour on that side
                local t0
                if exact then t0 = f0 + dir
                elseif dir < 0 then t0 = math.floor(f0)
                else t0 = math.ceil(f0) end
                local i = math.max(1, math.min(n, t0 + 1))
                if i ~= pos or not exact then choose(d, o, i, Notification.SOURCE_BOTTOM_MENU_PROGRESS) end
            end
        end
        local function step_hold(dir)
            if fine then
                d:onMakeFineTuneDefault("font_size", _("Font Size"), fine.values or fine.args, fine.toggle, dir < 0 and "-" or "+")
            elseif o.fine_tune then
                d:onMakeFineTuneDefault(o.name, name_text(d, o), o.values, o.labels or o.args, dir < 0 and "-" or "+")
            else
                make_default(d, o, pos)
            end
        end
        local function step_btn(name, dir)
            return Tap:new{ w = step_w, h = hit, enabled = en,
                callback = function() step(dir) end, hold_callback = function() step_hold(dir) end,
                CenterContainer:new{ dimen = Geom:new{ w = step_w, h = hit }, icon(name, T.px("icon-sm"), true) } }
        end
        local big = o.name == "font_size" and not ctx.pdf
        local minus = step_btn(big and "leaf.ts.a-arrow-down" or "leaf.minus", -1)
        local plus = step_btn(big and "leaf.ts.a-arrow-up" or "plus", 1)

        local h = T.px("h-row")
        local row = HorizontalGroup:new{ align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = lbl_w, h = h }, left },
            minus, HorizontalSpan:new{ width = gap }, slider, HorizontalSpan:new{ width = gap }, plus, HorizontalSpan:new{ width = gap }, value }
        local p = T.px("sp-1")
        return with_help(ctx, o, VerticalGroup:new{ align = "left", VerticalSpan:new{ width = p }, row, VerticalSpan:new{ width = p } })
    end

    local function value_labels(o)
        if o.name == "max_columns" then return { _("1 column"), _("2 columns"), _("3 columns") } end
        local l = HUMAN[o.name] and HUMAN[o.name][2]
        local src = o.toggle or o.labels or o.item_text
        if l and src and #l == #src then return l end
        local out = {}
        if src then
            for i, s in ipairs(src) do out[i] = cap(type(s) == "number" and fmt_num(s) or s) end
        elseif o.values then
            for i, v in ipairs(o.values) do out[i] = fmt_num(v) end
        end
        return out
    end

    -- segmented row (.rd-opt): head + seg inline when it fits, stacked under it otherwise
    function B.seg(ctx, o)
        local d = ctx.d
        local labels = value_labels(o)
        local pos = current_index(d, o)
        local en = opt_enabled(d, o)
        local items = {}
        for i, l in ipairs(labels) do items[i] = { label = l, on = i == pos } end
        if o.more_options then table.insert(items, { label = "⋮" }) end
        local n_vals = #labels
        local function tap(i)
            if i > n_vals then more(d, o) else choose(d, o, i) end
        end
        local function hold(i)
            if i <= n_vals then make_default(d, o, i, labels) end
        end
        local probe = Seg:new{ items = items }
        local kn = ko_name(d, o)
        local hw = T.px("h-chip") + T.px("sp-3") + math.max(text_w(opt_title(d, o), "ui-medium", "fs-md"), kn and text_w(kn, "ui", "fs-xs") or 0)
            + (o.help_text and (px(30) + T.px("sp-1")) or 0)
        local inline = #labels <= 6 and hw + T.px("sp-3") + probe.natural_w <= ctx.cw
        probe:free()
        local p = T.px("sp-3")
        if inline then
            local seg = Seg:new{ items = items, enabled = en, on_tap = tap, on_hold = hold }
            local h = math.max(seg:getSize().h, T.px("h-chip"))
            local body = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = p },
                lr(ctx.cw, h, head(ctx, o, ctx.cw - seg:getSize().w - T.px("sp-3")), seg), VerticalSpan:new{ width = p } }
            return with_help(ctx, o, body)
        end
        local seg = Seg:new{ items = items, width = ctx.cw, stretch = true, enabled = en, on_tap = tap, on_hold = hold }
        local body = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = p },
            lr(ctx.cw, T.px("h-seg"), head(ctx, o, ctx.cw)) }
        local hb = help_body(ctx, o)
        table.insert(body, hb or VerticalSpan:new{ width = T.px("sp-2") })
        table.insert(body, seg)
        table.insert(body, VerticalSpan:new{ width = p })
        return body
    end

    local function on_position(o)
        local t = o.toggle
        if not (t and #t == 2) then return nil end
        local a, b = tostring(t[1]):lower(), tostring(t[2]):lower()
        local off, on = _("off"):lower(), _("on"):lower()
        if (a == off or a == "off") and (b == on or b == "on") then return 2 end
        if (a == on or a == "on") and (b == off or b == "off") then return 1 end
    end

    -- switch row (.rd-switch): tile, label + sub, toggle, (i)
    function B.switch(ctx, o, on_pos)
        local d = ctx.d
        local pos = current_index(d, o)
        local on = pos == on_pos
        local en = opt_enabled(d, o)
        local sub = SUBS[o.name]
        if o.name == "visible_pages" then
            if not en then sub = _("Not available in continuous mode") elseif not on then sub = _("Single page") end
        end
        local kn = ko_name(d, o)
        if kn then sub = sub and (sub .. " · " .. kn) or kn end
        local hb = help_button(ctx, o)
        local right = HorizontalGroup:new{ align = "center", LeafToggle:new{ on = on, enabled = en } }
        if hb then table.insert(right, HorizontalSpan:new{ width = T.px("sp-1") }); table.insert(right, hb) end
        local right_w = right:getSize().w
        right:resetLayout()
        local gap = T.px("sp-3")
        local lw = ctx.cw - T.px("h-chip") - gap - right_w - gap
        local left = HorizontalGroup:new{ align = "center", tile(OPT_ICONS[o.name], en), HorizontalSpan:new{ width = gap },
            label_block(opt_title(d, o), sub, lw, { enabled = en }) }
        local h = math.max(px(54), left:getSize().h + 2 * T.px("sp-1"))
        left:resetLayout()
        local row = Tap:new{ w = ctx.cw, h = h, enabled = en,
            callback = function() choose(d, o, on and (3 - on_pos) or on_pos) end,
            hold_callback = function() if pos then make_default(d, o, pos) end end,
            lr(ctx.cw, h, left, right) }
        return with_help(ctx, o, row)
    end

    -- rotation: four device cards (.rd-rots)
    function B.rotation(ctx, o)
        local d = ctx.d
        local pos = current_index(d, o)
        local DEG = { "90°", "0°", "90°", "180°" }
        local SIDE = { _("Left"), _("Upright"), _("Right"), _("Flipped") }
        local gap = T.px("sp-2")
        local n = #o.values
        local cw = math.floor((ctx.cw - (n - 1) * gap) / n)
        local ch = px(98)
        local dev_top = T.px("sp-3") + px(2)
        local row = HorizontalGroup:new{ align = "top" }
        for i, v in ipairs(o.values) do
            local on = i == pos
            local land = (v == 1 or v == 3)
            local dw, dh = px(land and 30 or 20), px(land and 20 or 30)
            local card = Paint:new{ w = cw, h = ch, draw = function(bb, x, y, w, h)
                box(bb, x, y, w, h, T.px("r-lg"), T.color(on and "accent-soft" or "surface"), T.color(on and SEL() or "border"), on and SEL_BW() or hair)
                local dx, dy = x + math.floor((w - dw) / 2), y + dev_top + math.floor((px(30) - dh) / 2)
                local ink = T.color(on and "text" or "text-2")
                box(bb, dx, dy, dw, dh, T.px("r-check"), T.color(on and "accent-soft" or "surface"), ink, T.px("bw-md"))
                -- the notch marks the device's top edge
                local nl, nt = px(6), math.max(2, px(1.6))
                if v == 0 then bb:paintRect(dx + math.floor((dw - nl) / 2), dy + px(4), nl, nt, ink)
                elseif v == 2 then bb:paintRect(dx + math.floor((dw - nl) / 2), dy + dh - px(4) - nt, nl, nt, ink)
                elseif v == 3 then bb:paintRect(dx + px(4), dy + math.floor((dh - nl) / 2), nt, nl, ink)
                else bb:paintRect(dx + dw - px(4) - nt, dy + math.floor((dh - nl) / 2), nt, nl, ink) end
            end }
            local labels = VerticalGroup:new{ align = "center",
                text(DEG[i] or fmt_num(v), "ui-semibold", "fs-sm", "text"),
                VerticalSpan:new{ width = T.px("sp-half") },
                text(SIDE[i] or "", "ui", "fs-xs", on and "text-2" or "text-3") }
            local content = OverlapGroup:new{ dimen = Geom:new{ w = cw, h = ch }, card,
                VerticalGroup:new{ align = "center", VerticalSpan:new{ width = dev_top + px(30) + T.px("sp-2") },
                    CenterContainer:new{ dimen = Geom:new{ w = cw, h = labels:getSize().h }, labels } } }
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
            table.insert(row, Tap:new{ w = cw, h = ch, callback = function() choose(d, o, i, Notification.SOURCE_BOTTOM_MENU_ICON) end,
                hold_callback = function() make_default(d, o, i, o.labels) end, content })
        end
        local p = T.px("sp-3")
        local note = text(ctx.pdf and _("Page orientation") or _("Screen orientation"), "ui", "fs-sm", "text-3")
        local hd = lr(ctx.cw, T.px("h-seg"), head(ctx, o, ctx.cw - note:getSize().w - T.px("sp-3")), note)
        local g = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = p }, hd }
        table.insert(g, help_body(ctx, o) or VerticalSpan:new{ width = T.px("sp-2") })
        table.insert(g, row)
        table.insert(g, VerticalSpan:new{ width = p })
        return g
    end

    -- PDF zoom direction: KOReader's eight reading-path diagrams (.rd-dirs) + caption
    function B.directions(ctx, o)
        local d = ctx.d
        local pos = current_index(d, o)
        local icons = o.item_icons or {}
        local n = #o.values
        local gap = T.px("sp-1h")
        local s = math.min(px(58), math.floor((ctx.cw - (n - 1) * gap) / n))
        local en = opt_enabled(d, o)
        local row = HorizontalGroup:new{ align = "center" }
        for i = 1, n do
            local on = i == pos
            local bg = Paint:new{ w = s, h = s, draw = function(bb, x, y, w, h)
                -- KOReader's diagrams are opaque (white): keep the tile --surface, the outline marks the selection
                box(bb, x, y, w, h, T.px("r-md"), T.color("surface"), T.color(on and SEL() or "border"), on and SEL_BW() or hair)
            end }
            local ic = icons[i] and IconWidget:new{ icon = icons[i], width = math.floor(s * 0.7), height = math.floor(s * 0.7), alpha = true, dim = not on or not en }
                or text(tostring(i), "ui", "fs-sm")
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
            table.insert(row, Tap:new{ w = s, h = s, enabled = en,
                callback = function() choose(d, o, i, Notification.SOURCE_BOTTOM_MENU_ICON) end,
                hold_callback = function() make_default(d, o, i) end,
                OverlapGroup:new{ dimen = Geom:new{ w = s, h = s }, bg, CenterContainer:new{ dimen = Geom:new{ w = s, h = s }, ic } } })
        end
        local p = T.px("sp-3")
        local labels = o.labels or {}
        local g = VerticalGroup:new{ align = "center", VerticalSpan:new{ width = p },
            lr(ctx.cw, T.px("h-seg"), head(ctx, o, ctx.cw)) }
        table.insert(g, help_body(ctx, o) or VerticalSpan:new{ width = T.px("sp-2") })
        table.insert(g, CenterContainer:new{ dimen = Geom:new{ w = ctx.cw, h = s }, row })
        table.insert(g, VerticalSpan:new{ width = T.px("sp-2") })
        table.insert(g, text(cap(labels[pos] or ""), "ui", "fs-sm", "text-2"))
        table.insert(g, VerticalSpan:new{ width = p })
        return g
    end

    -- link row (.rd-linkrow): tile, label + sub, value, chevron
    function B.link(ctx, ico, label, sub, value, callback)
        local gap = T.px("sp-3")
        local right = HorizontalGroup:new{ align = "center" }
        if value then
            table.insert(right, value)
            table.insert(right, HorizontalSpan:new{ width = T.px("sp-2") })
        end
        table.insert(right, icon("chevron.right", T.px("icon-sm"), true))
        local rw = right:getSize().w
        right:resetLayout()
        local left = HorizontalGroup:new{ align = "center", tile(ico), HorizontalSpan:new{ width = gap },
            label_block(label, sub, ctx.cw - T.px("h-chip") - 2 * gap - rw) }
        local h = math.max(px(54), left:getSize().h + 2 * T.px("sp-1"))
        left:resetLayout()
        return Tap:new{ w = ctx.cw, h = h, callback = callback, lr(ctx.cw, h, left, right) }
    end

    -- switch row for a KOReader setting that is not a ConfigDialog option (font settings)
    function B.setting_switch(ctx, ico, label, sub, on, callback)
        local gap = T.px("sp-3")
        local tg = LeafToggle:new{ on = on }
        local lw = ctx.cw - T.px("h-chip") - 2 * gap - tg:getSize().w
        local left = HorizontalGroup:new{ align = "center", tile(ico), HorizontalSpan:new{ width = gap }, label_block(label, sub, lw) }
        local h = math.max(px(54), left:getSize().h + 2 * T.px("sp-1"))
        left:resetLayout()
        return Tap:new{ w = ctx.cw, h = h, callback = callback, lr(ctx.cw, h, left, tg) }
    end

    -- radio row (.rd-radio-row)
    function B.radio(ctx, label, on, enabled, callback, hold)
        local s = T.px("icon-md")
        local h = T.px("hit")
        local g = HorizontalGroup:new{ align = "center",
            IconWidget:new{ icon = on and "leaf.radio.on" or "leaf.radio.off", width = s, height = s, alpha = true, dim = not enabled },
            HorizontalSpan:new{ width = T.px("sp-3") },
            text(label, "ui", "fs-md", enabled and "text" or "disabled", ctx.cw - s - T.px("sp-3")) }
        local r = Tap:new{ w = ctx.cw, h = h, enabled = enabled, callback = callback, hold_callback = hold, lr(ctx.cw, h, g) }
        r._leaf_nosep = true
        return r
    end

    -- one KOReader option -> a row (nil: hidden, or merged into another row)
    function B.option(ctx, o)
        local d = ctx.d
        if o.name == "font_fine_tune" then return nil end
        if not opt_shown(d, o) then return nil end
        if o.name == "rotation_mode" and o.values then return B.rotation(ctx, o) end
        if o.name == "zoom_direction" and o.values then return B.directions(ctx, o) end
        if o.values and #o.values > 1 and (o.buttonprogress or (o.item_text and o.name == "font_size")) then
            return B.slider(ctx, o)
        end
        local on_pos = on_position(o)
        if on_pos then return B.switch(ctx, o, on_pos) end
        if o.toggle or o.item_icons or o.item_icons_func or o.item_text then return B.seg(ctx, o) end
        return nil
    end

    -- margins / crop: a small page with the text block inset by the margins (.rd-mdia)
    function B.margin_diagram(ctx)
        local c = ctx.d.configurable
        local s = 0.14
        local pw, ph = px(60), px(80)
        local l, r, t, b
        local dashed = true
        if ctx.pdf then
            local m = (tonumber(c.page_margin) or 0.1) * 12
            l, r, t, b = px(m + 4), px(m + 4), px(m + 4), px(m + 4)
            dashed = tonumber(c.trim_page) ~= 3
        else
            local hm = type(c.h_page_margins) == "table" and c.h_page_margins or { 15, 15 }
            l = px((10 + (hm[1] or 15) * 1.2) * s)
            r = px((10 + (hm[2] or hm[1] or 15) * 1.2) * s)
            t = px((6 + (tonumber(c.t_page_margin) or 15) * 0.8) * s + 2)
            b = px((6 + (tonumber(c.b_page_margin) or 15) * 0.8) * s + 2)
        end
        local page = Paint:new{ w = pw, h = ph, draw = function(bb, x, y, w, h)
            box(bb, x, y, w, h, T.px("r-check"), T.color("page"), T.color("border-strong"), hair)
            local ix, iy, iw, ih = x + l, y + t, w - l - r, h - t - b
            local lines = ctx.pdf and 10 or 8
            local lh = math.max(1, px(1.2))
            local step = (ih - lh) / (lines - 1)
            for i = 0, lines - 1 do
                local lw = (i == lines - 1) and math.floor(iw * 0.5) or iw
                bb:paintRect(ix, iy + math.floor(i * step), lw, lh, T.color("text-3"))
            end
            if dashed then
                local ac = T.color("accent")
                local dash, gp = px(3), px(2)
                local ox, oy, ow, oh = ix - px(2), iy - px(2), iw + px(4), ih + px(4)
                local k = 0
                while k < ow do
                    local len = math.min(dash, ow - k)
                    bb:paintRect(ox + k, oy, len, hair, ac)
                    bb:paintRect(ox + k, oy + oh, len, hair, ac)
                    k = k + dash + gp
                end
                k = 0
                while k < oh do
                    local len = math.min(dash, oh - k)
                    bb:paintRect(ox, oy + k, hair, len, ac)
                    bb:paintRect(ox + ow, oy + k, hair, len, ac)
                    k = k + dash + gp
                end
            end
        end }
        local p = T.px("sp-3")
        return VerticalGroup:new{ align = "center", VerticalSpan:new{ width = p },
            CenterContainer:new{ dimen = Geom:new{ w = ctx.cw, h = ph }, page }, VerticalSpan:new{ width = p } }
    end

    ---------------------------------------------------------------- font tab
    local function font_category(name, mono)
        if mono then return "mono" end
        for __, k in ipairs({ "Arabic", "Naskh", "Kufi", "Amiri", "Nastaliq" }) do if name:find(k, 1, true) then return "arabic" end end
        for __, k in ipairs({ "Sans", "Inter", "Roboto", "Atkinson", "Lato", "Arial", "Helvetica", "Verdana", "Grotesk" }) do
            if name:find(k, 1, true) then return "sans" end
        end
        return "serif"
    end
    local function own_face(fn, fi, size)
        if not (fn and fi) then return nil end
        local ok, f = pcall(Font.getFace, Font, fn, size, fi)
        return ok and f or nil
    end
    function B.font_tab(ctx)
        local d = ctx.d
        local rf = d.ui and d.ui.font
        local cards = {}
        if not rf then return cards end
        if not rf.face_table or rf.face_table.needs_refresh then rf:setupFaceMenuTable() end
        local cre = require("document/credocument"):engineInit()
        local FontList = require("fontlist")
        local def = font_default(d)
        local fallback = G_reader_settings:readSetting("fallback_font") or (d.document.fallback_fonts and d.document.fallback_fonts[1])
        local monofont = G_reader_settings:readSetting("monospace_font") or d.document.monospace_font
        local use_own = G_reader_settings:nilOrTrue("font_menu_use_font_face")
        local cat = d._leaf_font_cat or "all"

        -- category chips (.rd-fontcats / .ko-chip)
        local chips = HorizontalGroup:new{ align = "center" }
        for i, c in ipairs({ { "all", _("All") }, { "serif", _("Serif") }, { "sans", _("Sans") }, { "mono", _("Mono") }, { "arabic", _("Arabic") } }) do
            local on = c[1] == cat
            local lbl = text(c[2], on and "ui-medium" or "ui", "fs-sm", on and "text" or "text-2")
            local w = lbl:getSize().w + 2 * T.px("sp-3")
            local h = T.px("h-chip")
            local chip = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h },
                Paint:new{ w = w, h = h, draw = function(bb, x, y, ww, hh)
                    box(bb, x, y, ww, hh, math.floor(hh / 2), T.color(on and "accent-soft" or "surface-2"), T.color(on and SEL() or "border"), on and SEL_BW() or hair)
                end },
                CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, lbl } }
            if i > 1 then table.insert(chips, HorizontalSpan:new{ width = T.px("sp-1h") }) end
            table.insert(chips, Tap:new{ w = w, h = h, callback = function() d._leaf_font_cat = c[1]; refresh(d) end, chip })
        end
        local chip_row = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-3") }, chips, VerticalSpan:new{ width = T.px("sp-1") } }
        chip_row._leaf_nosep = true
        local rows = { chip_row }

        local s = T.px("icon-md")
        local smp_w = px(56)
        local tw = ctx.cw - s - 2 * T.px("sp-3") - smp_w
        -- the book's current font first (the prototype lists it at the top, selected)
        local ordered = {}
        for __, item in ipairs(rf.face_table) do
            if item.menu_item_id and item.menu_item_id == rf.font_face then table.insert(ordered, 1, item) else table.insert(ordered, item) end
        end
        for __, item in ipairs(ordered) do
            local v = item.menu_item_id
            if v then
                local fn, fi, mono = cre.getFontFaceFilenameAndFaceIndex(v)
                if not fn then fn, fi, mono = cre.getFontFaceFilenameAndFaceIndex(v, nil, true) end
                local nm = v
                if fn and fi then nm = FontList:getLocalizedFontName(fn, fi) or v end
                if cat == "all" or font_category(nm, mono) == cat then
                    local notes = {}
                    if v == def then table.insert(notes, _("Default")) end
                    if v == fallback then table.insert(notes, _("Fallback")) end
                    if v == monofont then table.insert(notes, _("Monospace")) elseif mono then table.insert(notes, _("Monospace font")) end
                    local on = v == rf.font_face
                    local name_face = use_own and own_face(fn, fi, T.fs("fs-lg")) or L.face("ui", "fs-lg")
                    local txt = VerticalGroup:new{ align = "left",
                        TextWidget:new{ text = nm, face = name_face, fgcolor = T.color("text"), max_width = tw } }
                    if #notes > 0 then
                        table.insert(txt, VerticalSpan:new{ width = px(1) })
                        table.insert(txt, text(table.concat(notes, " · "), "ui", "fs-xs", "text-3", tw))
                    end
                    local left = HorizontalGroup:new{ align = "center",
                        IconWidget:new{ icon = on and "leaf.radio.on" or "leaf.radio.off", width = s, height = s, alpha = true },
                        HorizontalSpan:new{ width = T.px("sp-3") }, txt }
                    local h = math.max(px(58), left:getSize().h + 2 * T.px("sp-1"))
                    left:resetLayout()
                    local smp = TextWidget:new{ text = "Ag", face = own_face(fn, fi, T.fs("fs-display")) or L.face("book", "fs-display"),
                        fgcolor = T.color(on and "text" or "text-3") }
                    table.insert(rows, Tap:new{ w = ctx.cw, h = h,
                        callback = function()
                            if item.callback then item.callback() end
                            UIManager:setDirty("all", "ui")
                            refresh(d)
                        end,
                        hold_callback = function() if item.hold_callback then item.hold_callback() end end,
                        lr(ctx.cw, h, left, smp) })
                end
            end
        end
        table.insert(cards, { rows = rows })

        -- font settings (ReaderFont:getFontSettingsTable)
        local set = {}
        table.insert(set, B.setting_switch(ctx, "type", _("Display font names with their own font"), nil, use_own, function()
            G_reader_settings:flipNilOrTrue("font_menu_use_font_face")
            refresh(d)
        end))
        local fb = d.document.fallback_fonts or {}
        local fb_sub = #fb > 0 and (fb[1] .. (fb[2] and (", " .. fb[2]) or "") .. "…") or nil
        table.insert(set, B.setting_switch(ctx, "layers", _("Use additional fallback fonts"), fb_sub,
            G_reader_settings:nilOrTrue("additional_fallback_fonts"), function()
                G_reader_settings:flipNilOrTrue("additional_fallback_fonts")
                d.document:setupFallbackFontFaces()
                d.ui:handleEvent(Event:new("UpdatePos"))
                refresh(d)
            end))
        table.insert(set, B.link(ctx, "folder-open", _("More font settings"), _("Sorting, fallback sizes, font-family fonts"), nil,
            function() open_menu(d, { "change_font", 1 }) end))
        table.insert(cards, { sep = _("Font settings"), rows = set })
        return cards
    end

    ---------------------------------------------------------------- presets tab
    local function preset_matches(d, p)
        for __, o in ipairs(all_options(d)) do
            local want = p[o.name]
            if want == nil then want = default_of(d, o) end
            if want ~= nil and d.configurable[o.name] ~= nil and not same(d.configurable[o.name], want) then return false end
        end
        return true
    end
    local function apply_preset(d, p)
        for __, o in ipairs(all_options(d)) do
            local want = p[o.name]
            if want == nil then want = default_of(d, o) end
            if want ~= nil and not same(d.configurable[o.name], want) then apply_value(d, o, want) end
        end
        UIManager:setDirty("all", "ui")
        refresh(d)
    end
    function B.presets_tab(ctx)
        local d = ctx.d
        local gap = T.px("sp-3")
        local cw2 = math.floor((ctx.w - gap) / 2)
        local face_name = d.ui and d.ui.font and d.ui.font.font_face or ""
        local mine = G_reader_settings:readSetting("leaf_typeset_presets") or {}
        local list = {}
        for __, p in ipairs(PRESETS) do table.insert(list, { name = p[1], values = p[2] }) end
        for i, p in ipairs(mine) do table.insert(list, { name = p.name, values = p.values or {}, mine = i }) end

        local function card(p)
            local vals = p.values
            local function val(name)
                local v = vals[name]
                if v == nil then
                    local o = d:findOptionByName(name)
                    v = o and default_of(d, o)
                end
                return v
            end
            local on = preset_matches(d, vals)
            local fsz = scalar(val("font_size")) or 22
            local ls = scalar(val("line_spacing")) or 100
            local hm = scalar(val("h_page_margins")) or 15
            local fw = scalar(val("font_base_weight")) or 0
            local pv_h = px(86)
            local inner_w = cw2 - 2 * T.px("sp-2")
            local pm = px(4 + hm / 5)
            local aa = TextWidget:new{ text = "Aa", face = Font:getFace(fonts.FILES[fw > 0 and "book-bold" or "book"], math.floor(fsz * 1.1 * T.scale)),
                fgcolor = T.color("page-ink") }
            local aw = aa:getSize().w
            local g = px((ls / 100) * 4 + fsz / 12)
            local preview = Paint:new{ w = inner_w, h = pv_h, draw = function(bb, x, y, w, h)
                box(bb, x, y, w, h, T.px("r-md"), T.color("page"), T.color("border"), hair)
                local lx = x + pm + aw + T.px("sp-2h")
                local lw = x + w - pm - lx
                local lh = px(3)
                local ly = y + math.floor((h - (4 * lh + 3 * g)) / 2)
                for i = 0, 3 do
                    bb:paintRoundedRect(lx, ly + math.floor(i * (lh + g)), i == 3 and math.floor(lw * 0.62) or lw, lh, T.color("page-skeleton"), T.px("r-tick"))
                end
            end }
            local pv = OverlapGroup:new{ dimen = Geom:new{ w = inner_w, h = pv_h }, preview,
                LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = pv_h }, HorizontalGroup:new{ HorizontalSpan:new{ width = pm }, aa } } }
            local meta = T_("%1 · %2 pt · %3%", (face_name:match("^(%S+)") or face_name), fmt_num(fsz), fmt_num(ls))
            local ind = T.px("sp-2") + T.px("sp-1")
            local body = VerticalGroup:new{ align = "left",
                VerticalSpan:new{ width = T.px("sp-2") },
                HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-2") }, pv },
                VerticalSpan:new{ width = T.px("sp-2") + T.px("sp-half") },
                HorizontalGroup:new{ HorizontalSpan:new{ width = ind }, text(p.name, "ui-semibold", "fs-md", "text", inner_w - T.px("sp-2")) },
                VerticalSpan:new{ width = T.px("sp-half") },
                HorizontalGroup:new{ HorizontalSpan:new{ width = ind }, text(meta, "ui", "fs-xs", on and "text-2" or "text-3", inner_w - T.px("sp-2")) },
                VerticalSpan:new{ width = T.px("sp-3") } }
            local ch = body:getSize().h
            body:resetLayout()
            local bg = Paint:new{ w = cw2, h = ch, draw = function(bb, x, y, w, h)
                box(bb, x, y, w, h, T.px("r-lg"), T.color(on and "accent-soft" or "surface"), T.color(on and SEL() or "border"), on and SEL_BW() or hair)
            end }
            local mark = Paint:new{ w = cw2, h = ch, draw = function(bb, x, y, w, h)
                if not on then return end
                -- .ko-selmark: 24px accent disc with a tick, top right over the preview
                local sz = px(24)
                local cx, cy = x + w - T.px("sp-3h") - math.floor(sz / 2), y + T.px("sp-3h") + math.floor(sz / 2)
                bb:paintCircle(cx, cy, math.floor(sz / 2) + px(2), T.color("surface"))
                bb:paintCircle(cx, cy, math.floor(sz / 2), T.color("accent"))
                tick(bb, cx, cy, math.floor(sz * 0.55), T.color("accent-ink"))
            end }
            return Tap:new{ w = cw2, h = ch,
                callback = function()
                    apply_preset(d, vals)
                    Notification:notify(T_(_("%1 applied"), p.name), Notification.SOURCE_ALWAYS_SHOW)
                end,
                hold_callback = p.mine and function()
                    UIManager:show(require("ui/widget/confirmbox"):new{
                        text = T_(_("Delete preset “%1”?"), p.name), ok_text = _("Delete"),
                        ok_callback = function()
                            local cur = G_reader_settings:readSetting("leaf_typeset_presets") or {}
                            table.remove(cur, p.mine)
                            G_reader_settings:saveSetting("leaf_typeset_presets", cur)
                            refresh(d)
                        end })
                end or nil,
                OverlapGroup:new{ dimen = Geom:new{ w = cw2, h = ch }, bg, body, mark } }
        end

        local grid = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-4") } }
        for i = 1, #list, 2 do
            local row = HorizontalGroup:new{ align = "top", card(list[i]) }
            if list[i + 1] then table.insert(row, HorizontalSpan:new{ width = gap }); table.insert(row, card(list[i + 1])) end
            if i > 1 then table.insert(grid, VerticalSpan:new{ width = gap }) end
            table.insert(grid, row)
        end

        -- actions (.rd-ts-actions)
        local n = differing(d)
        local function btn(label, kind, enabled, cb)
            return Button:new{ text = label, _leaf_kind = kind, enabled = enabled, bordersize = 0, padding_h = T.px("sp-4"),
                height = T.px("h-control") - 2 * require("ui/size").padding.button,
                callback = cb, show_parent = d }
        end
        local function save_default()
            local prefix = d.config_options.prefix
            for __, o in ipairs(all_options(d)) do
                local cur = d.configurable[o.name]
                if cur ~= nil and not same(cur, default_of(d, o)) then G_reader_settings:saveSetting(prefix .. "_" .. o.name, cur) end
            end
            if not ctx.pdf and d.ui.font and d.ui.font.font_face then G_reader_settings:saveSetting("cre_font", d.ui.font.font_face) end
            Notification:notify(_("Saved as default for all books"), Notification.SOURCE_ALWAYS_SHOW)
            refresh(d)
        end
        local function save_preset()
            local dlg
            dlg = require("ui/widget/inputdialog"):new{
                title = _("Save as preset"), input = T_(_("My preset %1"), #mine + 1),
                buttons = { {
                    { text = _("Cancel"), id = "close", callback = function() UIManager:close(dlg) end },
                    { text = _("Save"), is_enter_default = true, callback = function()
                        local name = dlg:getInputText()
                        UIManager:close(dlg)
                        if not name or name == "" then return end
                        local values = {}
                        for __, o in ipairs(all_options(d)) do
                            if d.configurable[o.name] ~= nil then values[o.name] = d.configurable[o.name] end
                        end
                        local cur = G_reader_settings:readSetting("leaf_typeset_presets") or {}
                        table.insert(cur, { name = name, values = values })
                        G_reader_settings:saveSetting("leaf_typeset_presets", cur)
                        Notification:notify(_("Preset saved"), Notification.SOURCE_ALWAYS_SHOW)
                        refresh(d)
                    end },
                } },
            }
            UIManager:show(dlg)
            dlg:onShowKeyboard()
        end
        local function reset()
            apply_preset(d, {})
            if not ctx.pdf and d.ui.font then
                local def = font_default(d)
                if def and def ~= d.ui.font.font_face then d.ui.font:onSetFont(def) end
            end
            Notification:notify(_("Book reset to your defaults"), Notification.SOURCE_ALWAYS_SHOW)
            refresh(d)
        end
        table.insert(grid, VerticalSpan:new{ width = T.px("sp-4") })
        table.insert(grid, HorizontalGroup:new{ align = "center",
            btn(_("Save as default"), "primary", n > 0, save_default), HorizontalSpan:new{ width = T.px("sp-2") },
            btn(_("Save as preset"), "secondary", true, save_preset), HorizontalSpan:new{ width = T.px("sp-2") },
            btn(_("Reset"), "ghost", n > 0, reset) })
        local foot = n > 0 and T_(n == 1 and _("%1 setting in this book differs from your default. Save as default applies it to every book.")
                or _("%1 settings in this book differ from your default. Save as default applies them to every book."), n)
            or _("This book follows your default settings. Changes you make apply to this book only, until you save them as the default.")
        table.insert(grid, VerticalSpan:new{ width = T.px("sp-3") })
        table.insert(grid, TextBoxWidget:new{ text = foot, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"),
            bgcolor = T.color("bg-raised"), width = ctx.w })
        return { { raw = grid } }
    end

    ---------------------------------------------------------------- tab bodies
    local function style_tweaks_count(ui)
        local st = ui and ui.styletweak
        if not (st and st.isTweakEnabled) then return nil end
        local seen, n = {}, 0
        for __, t in ipairs({ st.global_tweaks or {}, st.doc_tweaks or {} }) do
            for id in pairs(t) do
                if not seen[id] then
                    seen[id] = true
                    local ok, on = pcall(st.isTweakEnabled, st, id)
                    if ok and on then n = n + 1 end
                end
            end
        end
        return n
    end

    -- -> list of { sep = "SECTION"?, rows = { widget… }, note = text? } | { raw = widget }
    function B.tab_cards(ctx, tab)
        local d = ctx.d
        local key = tab.leaf_key
        if key == "presets" then return B.presets_tab(ctx) end
        if key == "font" then return B.font_tab(ctx) end
        local rows = {}
        if key == "text" and not ctx.pdf and d.ui and d.ui.font then
            local fi
            for i, t in ipairs(d.config_options) do if t.leaf_key == "font" then fi = i end end
            local ff = d.ui.font.font_face or ""
            local nm_face
            local ok, cre = pcall(function() return require("document/credocument"):engineInit() end)
            if ok and cre then
                local fn, idx = cre.getFontFaceFilenameAndFaceIndex(ff)
                nm_face = own_face(fn, idx, T.fs("fs-head"))
            end
            local val = TextWidget:new{ text = ff, face = nm_face or L.face("book", "fs-head"), fgcolor = T.color("text-2"), max_width = math.floor(ctx.cw * 0.5) }
            table.insert(rows, B.link(ctx, "type", _("Font"), nil, val, function() if fi then d:onShowConfigPanel(fi) end end))
        end
        if key == "margins" or key == "crop" then table.insert(rows, B.margin_diagram(ctx)) end
        for __, o in ipairs(tab.options) do
            local w = B.option(ctx, o)
            if w then table.insert(rows, w) end
        end
        local cards = { { rows = rows } }
        if ctx.pdf and key == "reflow" and tonumber(d.configurable.text_wrap) ~= 1 then
            cards[1].note_before = _("Font size, word gap, line spacing and alignment take effect when Reflow is on.")
        end
        if key == "text" and not ctx.pdf then
            table.insert(cards, { sep = _("Paragraphs"), rows = {
                B.link(ctx, "scissors", _("Hyphenation & typography"), _("Hyphenation, language rules, ligatures"), nil,
                    function() open_menu(d, { "typography" }) end),
            } })
        end
        if key == "style" and not ctx.pdf and d.ui and d.ui.typeset and d.ui.typeset.genStyleSheetMenu then
            local srows = {}
            local ok, items = pcall(d.ui.typeset.genStyleSheetMenu, d.ui.typeset)
            if ok and items then
                for __, it in ipairs(items) do
                    if not it.sub_item_table and not it.sub_item_table_func and it.callback then
                        local label = it.text or (it.text_func and it.text_func()) or ""
                        local en = not it.enabled_func or it.enabled_func()
                        table.insert(srows, B.radio(ctx, label, it.checked_func and it.checked_func() or false, en,
                            function() it.callback(); UIManager:setDirty("all", "ui"); refresh(d) end,
                            it.hold_callback and function() it.hold_callback(nil) end))
                    end
                end
            end
            if #srows > 0 then srows[#srows]._leaf_nosep = nil end
            table.insert(srows, B.link(ctx, "file-code", _("More style sheets"), _("Obsolete and your own style sheets"), nil,
                function() open_menu(d, { "set_render_style" }) end))
            local nt = style_tweaks_count(d.ui)
            table.insert(srows, B.link(ctx, "wand-sparkles", _("Style tweaks"), _("Pages, paragraphs, footnotes, images…"),
                nt and text(T_(_("%1 active"), nt), "ui", "fs-sm", "text-3") or nil, function() open_menu(d, { "style_tweaks" }) end))
            table.insert(cards, { sep = _("Style sheet"), rows = srows })
        end
        return cards
    end

    -- cards -> the scrolling content (.rd-ts-body)
    function B.body(d, tab, w)
        local cpad = T.px("sp-4")
        local ctx = { d = d, pdf = d.config_options._leaf_pdf, w = w }
        ctx.cw = ctx.w - 2 * cpad - 2 * hair
        for __, o in ipairs(tab.options) do if o.name == "font_fine_tune" then ctx.fine_tune = o end end
        local vg = VerticalGroup:new{ align = "left" }
        local function note(s)
            local p = T.px("sp-3")
            local is = T.px("icon-sm")
            table.insert(vg, VerticalSpan:new{ width = p })
            table.insert(vg, FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface"),
                radius = T.px("r-md"), padding = p, margin = 0,
                HorizontalGroup:new{ align = "top", icon("info", is, true), HorizontalSpan:new{ width = T.px("sp-2") },
                    TextBoxWidget:new{ text = s, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"), bgcolor = T.color("surface"),
                        width = ctx.w - 2 * p - 2 * hair - is - T.px("sp-2") } } })
        end
        for __, c in ipairs(B.tab_cards(ctx, tab)) do
            if c.sep then
                table.insert(vg, VerticalSpan:new{ width = T.px("sp-5") })
                table.insert(vg, HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-1") },
                    text(c.sep:upper(), "ui-semibold", "fs-xs", "text-3") })
                table.insert(vg, VerticalSpan:new{ width = T.px("sp-1") })
            end
            if c.note_before then note(c.note_before) end
            if c.raw then
                table.insert(vg, c.raw)
            elseif c.rows and #c.rows > 0 then
                local inner = VerticalGroup:new{ align = "left" }
                for i, r in ipairs(c.rows) do
                    if i > 1 and not c.rows[i - 1]._leaf_nosep then table.insert(inner, hline(ctx.cw)) end
                    table.insert(inner, r)
                end
                if not c.sep then table.insert(vg, VerticalSpan:new{ width = T.px("sp-3") }) end
                table.insert(vg, FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface"),
                    radius = T.px("r-lg"), padding = 0, padding_left = cpad, padding_right = cpad, margin = 0, inner })
            end
        end
        table.insert(vg, VerticalSpan:new{ width = T.px("sp-4") })
        return vg
    end

    ---------------------------------------------------------------- dialog wiring
    local SBW = px(3) -- scroll bar width (ScrollableContainer reserves 3x it when scrolling)
    if ConfigPanel then
        L.wrap(ConfigPanel, "init", function(orig, self)
            local d = self.config_dialog
            if not (d.config_options and d.config_options._leaf_src) then return orig(self) end
            local tab = d.config_options[self.index] or d.config_options[1]
            local W = Screen:getWidth()
            local pad = T.px("sp-5")
            self.background = T.color("bg-raised")
            self.padding = 0
            -- content width W - 3*SBW (no horizontal scrolling), cards centred on the screen
            self.padding_left = pad
            self.padding_right = pad - 3 * SBW
            self[1] = B.body(d, tab, W - 2 * pad)
        end, "ConfigPanel:init")
    end

    -- regroup KOReader's tabs once per dialog
    L.wrap(ConfigDialog, "init", function(orig, self)
        if self.config_options and not self.config_options._leaf_src and #self.config_options > 0 then
            local pdf = self.document and self.document.koptinterface ~= nil
            self.config_options = regroup(self.config_options, pdf)
        end
        return orig(self)
    end, "ConfigDialog:init")

    -- the doc settings remember a Leaf tab index: allow the Leaf tab count (KOReader clamps to its own)
    local ok_rc, ReaderConfig = pcall(require, "apps/reader/modules/readerconfig")
    if ok_rc and ReaderConfig then
        L.wrap(ReaderConfig, "onReadSettings", function(orig, self, config)
            orig(self, config)
            local idx = config:readSetting("config_panel_index")
            if idx and self.options then
                local n = #regroup(self.options, self.document and self.document.koptinterface ~= nil)
                self.last_panel_index = math.max(1, math.min(idx, n))
            end
        end, "ReaderConfig:onReadSettings")
    end

    ---------------------------------------------------------------- tab bar: icon over label
    local Tab = InputContainer:extend{}
    function Tab:init()
        local s = T.px("icon-md")
        local top
        if self.aa then
            -- .rd-aa: the Text tab shows "Aa" in the display face
            top = CenterContainer:new{ dimen = Geom:new{ w = s * 2, h = s },
                TextWidget:new{ text = "Aa", face = L.face("display-semibold", "fs-lg"), fgcolor = T.color(self.active and SEL() or "text-2") } }
        else
            top = IconWidget:new{ icon = self.icon, width = s, height = s, alpha = true, dim = not self.active }
        end
        local g = VerticalGroup:new{ align = "center", top,
            VerticalSpan:new{ width = T.px("sp-1") },
            TextWidget:new{ text = self.label, face = L.face(self.active and (eink() and "ui-semibold" or "ui-medium") or "ui", "fs-2xs"),
                fgcolor = T.color(self.active and SEL() or "text-3"), max_width = self.width - T.px("sp-1") } }
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
        self[1] = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, g }
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    function Tab:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        InputContainer.paintTo(self, bb, x, y)
    end
    function Tab:onTap()
        if self.callback then self.callback() end
        return true
    end

    local function tab_label(opt)
        if opt.leaf_label then return opt.leaf_label end
        return (tostring(opt.icon or ""):gsub("^appbar%.", ""):gsub("^%l", string.upper))
    end

    if MenuBar then
        L.wrap(MenuBar, "init", function(orig, self)
            local dialog = self.config_dialog
            local opts = dialog.config_options
            local W = Screen:getWidth()
            -- KOReader's IconButtons stay the focus layout (keys); the touch bar is Leaf's
            if not self.menu_items then
                self.menu_items = {}
                for c = 1, #opts do
                    self.menu_items[c] = IconButton:new{ show_parent = dialog, icon = opts[c].icon,
                        width = T.px("icon-md"), height = T.px("icon-md"),
                        callback = function() dialog:handleEvent(Event:new("ShowConfigPanel", c)) end }
                end
            end
            table.insert(dialog.layout, self.menu_items)
            -- .rd-ts-tabs: padding sp-1h sp-2 sp-2; each tab: sp-2 / 7px padding, icon, sp-1, label
            local side = T.px("sp-2")
            local tw = math.floor((W - 2 * side) / math.max(1, #opts))
            local lh = TextWidget:new{ text = "Ag", face = L.face("ui", "fs-2xs") }
            local th = T.px("sp-2") + T.px("icon-md") + T.px("sp-1") + lh:getSize().h + px(7)
            lh:free()
            local bar = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = side } }
            for c = 1, #opts do
                table.insert(bar, Tab:new{ icon = opts[c].icon, label = tab_label(opts[c]), width = tw, height = th,
                    aa = opts[c].leaf_key == "text", active = c == self.panel_index,
                    callback = function() dialog:handleEvent(Event:new("ShowConfigPanel", c)) end })
            end
            self.background = T.color("bg-raised")
            self.padding = 0
            self.dimen = Geom:new{ x = 0, y = 0, w = W, h = th + T.px("sp-1h") + T.px("sp-2") }
            table.insert(self, VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-1h") }, bar, VerticalSpan:new{ width = T.px("sp-2") } })
        end, "ConfigDialog MenuBar:init")
    end

    ---------------------------------------------------------------- the sheet
    local function sub_line(d)
        local doc = d.document
        local ext = doc and doc.file and doc.file:match("%.([^.]+)$")
        local parts = { ext and ext:upper() or "" }
        if d.config_options._leaf_pdf then
            table.insert(parts, tonumber(d.configurable.text_wrap) == 1 and _("reflowed") or _("fixed layout"))
        else
            table.insert(parts, _("reflowable"))
        end
        local n = differing(d)
        table.insert(parts, n > 0 and T_(_("%1 custom for this book"), n) or _("using your defaults"))
        return table.concat(parts, " · ")
    end

    L.wrap(ConfigDialog, "update", function(orig, self)
        -- keep the scroll position when the same tab is rebuilt (after a value change)
        local keep
        if self._leaf_scroll and self._leaf_scroll_tab == self.panel_index then
            keep = self._leaf_scroll:getScrolledOffset()
        end
        if self._leaf_scroll then self._leaf_scroll:onCloseWidget() end
        orig(self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local frame = self.dialog_frame
        local inner = frame[1] -- VerticalGroup{ config_panel, config_menubar }
        local panel, menubar = inner[1], inner[2]
        local r = T.px("r-xl")
        local pad = T.px("sp-5")
        local s = T.px("icon-md")
        local bp = math.floor((T.px("hit") - s) / 2)
        local opt = self.config_options[self.panel_index] or {}
        local leaf = self.config_options._leaf_src ~= nil

        -- head (.ko-sheet-head): title + sub, close
        local tg = VerticalGroup:new{ align = "left", text(opt.leaf_title or tab_label(opt), "ui-semibold", "fs-head", "text", W - 2 * pad - T.px("hit")) }
        if leaf then
            table.insert(tg, VerticalSpan:new{ width = T.px("sp-half") })
            table.insert(tg, text(sub_line(self), "ui", "fs-sm", "text-3", W - 2 * pad - T.px("hit")))
        end
        local close = IconButton:new{ icon = "close", width = s, height = s, padding = bp, show_parent = self,
            callback = function() self:closeDialog() end }
        local hh = math.max(T.px("h-header"), tg:getSize().h + 2 * T.px("sp-3"))
        tg:resetLayout()
        local head = OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, tg } },
            RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, HorizontalGroup:new{ close, HorizontalSpan:new{ width = T.px("sp-3") - bp } } } }
        local grip = Paint:new{ w = px(36), h = T.px("sp-1"), draw = function(bb, x, y, w, h)
            bb:paintRoundedRect(x, y, w, h, T.color("border-strong"), math.floor(h / 2))
        end }
        local top = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = Geom:new{ w = W, h = T.px("sp-1") }, grip },
            head,
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") } }

        local body = panel
        if leaf then
            -- .rd-ts: height min(60%, 480px of 800) -> 60% of the screen; the body scrolls
            local sheet_h = math.floor(H * 0.6)
            local body_h = sheet_h - top:getSize().h - hair - menubar:getSize().h
            top:resetLayout()
            local sc = ScrollableContainer:new{ dimen = Geom:new{ w = W, h = body_h }, show_parent = self, scroll_bar_width = SBW, panel }
            if keep then
                sc:initState()
                if sc._is_scrollable then
                    keep.y = math.min(keep.y, sc._max_scroll_offset_y)
                    keep.x = 0
                    sc:setScrolledOffset(keep)
                    sc:_updateScrollBars()
                end
            end
            self._leaf_scroll, self._leaf_scroll_tab = sc, self.panel_index
            self.cropping_widget = sc
            body = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg-raised"),
                width = W, height = body_h, sc }
        end
        frame[1] = VerticalGroup:new{ align = "center",
            top,
            body,
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") },
            menubar,
        }
        frame.background = T.color("bg-raised")
        frame.radius = r
        frame.bordersize = hair
        frame.color = T.color("border-strong")
        frame.padding = 0
        frame.padding_bottom = r
        -- corners below the screen edge: only the top ones show
        self[1] = BottomContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H + r }, frame }
    end, "ConfigDialog:update")
end

return M
