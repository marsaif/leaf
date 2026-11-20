--[[
    Leaf number pickers (Gaps › spin, spin2, datetime, number): SpinWidget, DoubleSpinWidget,
    DateTimeWidget and the NumberPickerWidget they all use.

    Dialog (.ko-dialog.gp-spin / .gp-dt): min(92%, 480px) wide, --sp-5 padding, --surface, hairline
    --border-strong, --r-lg. Title (--fs-head semibold), optional sub (--fs-sm --text-3), help text
    (--fs-md --text-2), then the value rows, a meta line ("6–30 · default 14" on the left, an accent
    "⌨ Type a number" link on the right), widgets added by the caller (check boxes), a "KOReader: …"
    note (--fs-xs --text-3, the engineering name when Leaf shows a human title), and the action row
    [Default · 14] … [extra] [Close] [Apply]. Apply is disabled while the value is unchanged, like
    KOReader (ok_always_enabled keeps it on).

    * NumberPickerWidget (leaf_width set by the dialog):
        - slider mode (Spin / DoubleSpin): .ko-sr: [label 112px] [−] [slider] [+] [value + small unit].
        - stepper mode (DateTime, leaf_stepper): a .ko-row in a sunken group: icon, label,
          .ko-stepper [−] value [+] (32px boxes).
      − / + keep KOReader's step and hold-step callbacks; the value (and the meta link) open the Leaf
      "Enter a number" dialog: field, "Between 6 and 30 …" help under it, which becomes the range
      error in place (KOReader showed an InfoMessage). "=" expressions and the ":" debug prefix work
      as in KOReader.
    * Human titles: HUMAN maps a KOReader title to the prototype's wording (title, sub, row labels,
      help, note); unknown titles keep KOReader's text.
    Same fields and callbacks as KOReader's (value_widget, left/right_widget, *_widget, callback,
    extra/option/default callbacks, keep_shown_on_apply, addWidget(), update()).
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local M = {}

local function geom(w, h) return Geom:new{ x = 0, y = 0, w = math.floor(w), h = math.floor(h) } end

local function fmt(self, v)
    if self.value_table then return tostring(v) end
    return string.format(self.precision or "%02d", v)
end

-- the range is a quantity, not a clock reading: no zero padding ("6–24", not "06–24")
local function plain(precision, v)
    local p = precision or "%d"
    if p:match("^%%0%d+d$") then p = "%d" end
    return string.format(p, v)
end

local function pad2(n) return string.format("%02d", n or 0) end

-- "1 h 12 min" / "20 min"
local function dur(min)
    local h, m = math.floor(min / 60), min % 60
    if h > 0 then return string.format("%d h %d min", h, m) end
    return string.format("%d min", m)
end

--[[ KOReader title -> the prototype's wording (gaps.js SPIN / SPIN2 / DT).
     title, label (spin row), labels = {left, right} (spin2), sep, help (false = none), ko, sub,
     clock (singular Hour / Minute), note(values) -> { {text, bold}, ... }, checks = {old = new} ]]
local HUMAN = {
    spin = {
        ["Items per page"] = { label = "Items", ko = "File browser › Items per page",
            help = "How many books or files one page of the library list shows. Fewer items means bigger rows." },
        ["Minimum threshold to hide battery item"] = { title = "Hide battery below", label = "Level",
            help = "The battery item in the status bar only appears when the charge is below this level." },
        ["Characters per page"] = { label = "Characters", ko = "Stable page numbers › Characters per page",
            extra = { ["Use publisher page numbers"] = "Use publisher pages" },
            help = "Stable page numbers are counted every this many characters, so they don't move when you change the font." },
        ["List modes"] = { title = "Books per page in list view", label = "Books",
            ko = "Project: Title › Items per page › List modes", help = "Number of rows on one page of the list views." },
    },
    spin2 = {
        ["Battery level alert thresholds"] = { title = "Battery alerts", sep = " – ",
            help = "Low is checked while the device isn't charging, high while it is charging." },
        ["Hyphenation limits"] = { labels = { "Before break", "After break" }, sep = " / ", ko = "Hyphenation limits (Left / Right)",
            help = "Fewest letters left before and carried after a hyphen. Applies to every book with a hyphenation dictionary." },
        ["Portrait cover grid mode"] = { title = "Grid in portrait", sep = " × ", ko = "Project: Title › Items per page › Portrait cover grid mode",
            help = "Covers per row and rows per page in the portrait cover grid." },
        ["Landscape cover grid mode"] = { title = "Grid in landscape", sep = " × ", ko = "Project: Title › Items per page › Landscape cover grid mode",
            help = "Covers per row and rows per page in the landscape cover grid." },
    },
    datetime = {
        ["Alarm"] = { sub = "Read timer", help = false, clock = true, note = function(v)
            local now = os.date("*t")
            local d = (v.hour * 60 + v.minute) - (now.hour * 60 + now.min)
            if d <= 0 then d = d + 24 * 60 end
            return { { "Rings at " }, { pad2(v.hour) .. ":" .. pad2(v.minute), true }, { " · in " .. dur(d) } }
        end },
        ["Interval"] = { sub = "Read timer", help = false, ko = "Auto-reschedule",
            checks = { ["Auto-reschedule"] = "Repeat when time is up" }, note = function(v)
            local t = os.time() + (v.hour * 60 + v.minute) * 60
            return { { "Time is up at " }, { os.date("%H:%M", t), true } }
        end },
        ["Daily timeline starts at"] = { sub = "Statistics", clock = true,
            help = "Reading past midnight still counts for the evening before when the day starts later, e.g. at 04:00.",
            note = function(v)
                local s = pad2(v.hour) .. ":" .. pad2(v.minute)
                return { { "Days run from " }, { s, true }, { " to " }, { s, true } }
            end },
        ["Timeout for autosuspend"] = { title = "Sleep after", sub = "Auto suspend", ko = "Autosuspend timeout",
            help = "The device goes to sleep when you haven't touched it for this long.", note = function(v)
            local s = (v.day and v.day > 0 and (v.day .. " d ") or "") .. (v.hour or 0) .. " h " .. pad2(v.minute) .. " min"
            return { { "Sleeps after " }, { s, true }, { " without a touch" } }
        end },
    },
}

function M.apply(L)
    local T = L.T
    local _ = require("gettext")
    local fonts = require("leaf/fonts")
    local Kit = require("leaf/widgets/kit")
    local ButtonTable = require("ui/widget/buttontable")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local IconButton = require("ui/widget/iconbutton")
    local LeafSlider = require("leaf/widgets/slider")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local NumberPickerWidget = require("ui/widget/numberpickerwidget")
    local SpinWidget = require("ui/widget/spinwidget")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local value_face = fonts.FILES["ui-medium"]

    local function human(kind, title)
        local t = HUMAN[kind]
        return t and title and (t[title] or t[_(title)]) or {}
    end
    M.human = human

    local function text(s, role, size, color, max_w)
        return TextWidget:new{ text = s or "", face = L.face(role or "ui", size or "fs-md"),
            fgcolor = T.color(color or "text"), max_width = max_w and math.floor(max_w) or nil }
    end
    local function tint(icon, size, color)
        return Kit.TintIcon:new{ icon = icon, size_token = size or "icon-sm", color = T.color(color or "text-3") }
    end

    ---------------------------------------------------------------- "Enter a number"
    -- KOReader's NumberPickerWidget input (numberpickerwidget.lua), the errors shown under the field
    local Help = WidgetContainer:extend{}
    function Help:set(msg, err)
        local w = self.width
        local h = T.px("h-badge") + T.px("sp-1")
        local g = HorizontalGroup:new{ align = "center" }
        if err then
            table.insert(g, tint("leaf.gw.circle-alert", "icon-sm", "danger"))
            table.insert(g, HorizontalSpan:new{ width = T.px("sp-1h") })
        end
        table.insert(g, text(msg, "ui", "fs-xs", err and "danger" or "text-3", w - (err and T.px("icon-sm") + T.px("sp-1h") or 0)))
        self[1] = LeftContainer:new{ dimen = geom(w, h), g }
        self.dimen = geom(w, h)
    end

    local function enter_number(self)
        local InputDialog = require("ui/widget/inputdialog")
        if self.date_month and self.date_year then
            self.value_max = self:getDaysInMonth(self.date_month:getValue(), self.date_year:getValue())
        end
        local cur = self.value_table and tostring(self.value) or plain(self.precision, self.value)
        local sub = self.leaf_input_label and (self.leaf_input_label .. " · " .. _("now") .. " " .. cur) or nil
        local dialog, help
        local hint_text = string.format("%s %s %s %s. %s", _("Between"), plain(self.precision, self.value_min), _("and"),
            plain(self.precision, self.value_max), _("Start with = to calculate, e.g. =12*2"))
        local function fail(msg)
            help:set(msg, true)
            UIManager:setDirty(dialog, "ui")
        end
        dialog = InputDialog:new{
            title = _("Enter a number"),
            description = sub,
            input_hint = cur,
            input_type = "number",
            buttons = { {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("OK"), is_enter_default = true, callback = function()
                    local input_text = dialog:getInputText()
                    local v = tonumber(input_text)
                    local unchecked = false
                    if input_text:match("^:") and G_reader_settings:isTrue("debug_verbose") then
                        unchecked = true
                        input_text = input_text:gsub("^:", "")
                        v = tonumber(input_text)
                    end
                    if input_text:match("^=") then
                        v = nil
                        if not input_text:gsub("math%.%a*", ""):find("[%a%[%]%{%}]") then
                            local func = load((input_text:gsub("^=", "return ")), "user_sandbox", nil, { math = math })
                            if func then
                                local ok, res = pcall(func)
                                v = ok and tonumber(res) or nil
                            end
                        end
                    end
                    if not v then return fail(_("Enter a number.")) end
                    if not unchecked and v < self.value_min then
                        return fail(string.format(_("This value should be %s or more."), plain(self.precision, self.value_min)))
                    elseif not unchecked and v > self.value_max then
                        return fail(string.format(_("This value should be %s or less."), plain(self.precision, self.value_max)))
                    end
                    self.value = v
                    self:update()
                    UIManager:close(dialog)
                end },
            } },
        }
        help = Help:new{ width = dialog:getAddedWidgetAvailableWidth() }
        help:set(hint_text, false)
        dialog:addWidget(help)
        UIManager:show(dialog)
        dialog:onShowKeyboard()
        return dialog, help
    end
    M.enter_number = enter_number

    ---------------------------------------------------------------- NumberPickerWidget
    local function pct_of(self)
        if self.value_table then
            local n = #self.value_table
            return n > 1 and ((self.value_index or 1) - 1) / (n - 1) or 0
        end
        local span = self.value_max - self.value_min
        return span > 0 and (self.value - self.value_min) / span or 0
    end

    -- value + small unit (.ko-sr .val small)
    local function value_group(self)
        local g = HorizontalGroup:new{ align = "bottom" }
        -- a quantity: "2", not KOReader's "02"
        local v = self.value_table and tostring(self.value) or plain(self.precision, self.value)
        table.insert(g, text(v, "ui-medium", "fs-md", "text"))
        if self.unit and self.unit ~= "" then
            table.insert(g, HorizontalSpan:new{ width = math.max(1, Screen:scaleBySize(1)) })
            table.insert(g, text(self.unit, "ui", "fs-xs", "text-3"))
        end
        return g
    end

    local function build_slider(self, up, down)
        local row_w = self.leaf_width
        local gap = T.px("sp-2")
        local icon = T.px("icon-sm")
        local step_pad = math.floor((T.px("hit") - icon) / 2)
        local step_pad_h = math.floor((Screen:scaleBySize(36 * T.scale) - icon) / 2)
        local step_w = icon + 2 * step_pad_h
        local value_w = T.px("h-row") -- .ko-sr .val: 48px
        local face = require("ui/font"):getFace(value_face, T.fs("fs-md"))
        local samples = self.value_table and {} or { fmt(self, self.value_min), fmt(self, self.value_max) }
        for _i, v in ipairs(self.value_table or {}) do table.insert(samples, tostring(v)) end
        for _i, s in ipairs(samples) do
            local tw = TextWidget:new{ text = s .. (self.unit or ""), face = face }
            value_w = math.max(value_w, tw:getSize().w + T.px("sp-1"))
            tw:free()
        end
        value_w = math.min(value_w, math.floor(row_w * 0.3))
        local label_widget
        if self.leaf_label and self.leaf_label ~= "" then
            local label_w = Screen:scaleBySize(112 * T.scale)
            label_widget = LeftContainer:new{ dimen = geom(label_w, T.px("hit")),
                text(self.leaf_label, "ui", "fs-md", "text", label_w - gap) }
            row_w = row_w - label_w
        end
        local slider_w = math.max(T.px("h-row"), row_w - 2 * step_w - value_w - 3 * gap)
        local function step_button(name, src)
            return IconButton:new{ icon = name, width = icon, height = icon, padding = step_pad,
                padding_left = step_pad_h, padding_right = step_pad_h,
                callback = src.callback, hold_callback = src.hold_callback, show_parent = self.show_parent }
        end
        local minus = step_button("leaf.gw.minus", down)
        local plus = step_button("leaf.gw.plus", up)
        self.leaf_slider = LeafSlider:new{
            width = slider_w, pct = pct_of(self), show_parent = self.show_parent,
            on_change = function(frac, final)
                if self.date_month and self.date_year then
                    self.value_max = self:getDaysInMonth(self.date_month:getValue(), self.date_year:getValue())
                end
                if self.value_table then
                    local idx = 1 + math.floor(frac * (#self.value_table - 1) + 0.5)
                    if idx == self.value_index and not final then return end
                    self.value_index = idx
                    self.value = self.value_table[idx]
                else
                    local steps = math.floor(frac * (self.value_max - self.value_min) / self.value_step + 0.5)
                    local v = math.min(self.value_max, self.value_min + steps * self.value_step)
                    if v == self.value and not final then return end
                    self.value = v
                end
                if final then
                    self:update()
                else
                    self.formatted_value = self.value_table and self.value or fmt(self, self.value)
                    self:leafSetValue()
                    self.leaf_slider:setPct(pct_of(self))
                    UIManager:setDirty(self.show_parent, "ui", self.dimen)
                end
            end,
        }
        local h = T.px("hit")
        self.leaf_value_box = RightContainer:new{ dimen = geom(value_w, h), value_group(self) }
        local value_tap = Kit.Tap:new{ width = value_w, height = h, content = self.leaf_value_box,
            callback = self.leaf_input_cb }
        self[1] = HorizontalGroup:new{ align = "center",
            label_widget or HorizontalSpan:new{ width = 0 },
            minus, HorizontalSpan:new{ width = gap },
            self.leaf_slider, HorizontalSpan:new{ width = gap },
            plus, HorizontalSpan:new{ width = gap },
            value_tap,
        }
        self.layout = { { minus, plus } }
    end

    -- .ko-row in a sunken group: icon · label · .ko-stepper [−] value [+]
    local function build_stepper(self, up, down)
        local W = self.leaf_width
        local h = T.px("h-row")
        local padx = T.px("sp-4")
        local box = T.px("h-chip")
        local is = T.px("icon-sm")
        local hair = T.px("hairline")
        local function step(icon, src)
            local b = IconButton:new{ icon = icon, width = is, height = is, padding = math.floor((box - 2 * hair - is) / 2),
                callback = src.callback, hold_callback = src.hold_callback, show_parent = self.show_parent }
            return b, FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface-2"),
                radius = T.px("r-sm"), padding = 0, margin = 0, b }
        end
        local minus, minus_f = step("leaf.gw.minus", down)
        local plus, plus_f = step("leaf.gw.plus", up)
        local val_w = T.px("hit")
        self.leaf_value_box = CenterContainer:new{ dimen = geom(val_w, box),
            text(tostring(self.formatted_value), "ui", "fs-sm", "text") }
        local value_tap = Kit.Tap:new{ width = val_w, height = box, content = self.leaf_value_box, callback = self.leaf_input_cb }
        local stepper = HorizontalGroup:new{ align = "center",
            minus_f, HorizontalSpan:new{ width = T.px("sp-2") }, value_tap,
            HorizontalSpan:new{ width = T.px("sp-2") }, plus_f, HorizontalSpan:new{ width = padx } }
        local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = padx },
            tint(self.leaf_icon or "leaf.gw.clock", "icon-md", "text-2"), HorizontalSpan:new{ width = T.px("sp-3") },
            text(self.leaf_label or "", "ui", "fs-md", "text", W / 2) }
        self[1] = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), left },
            RightContainer:new{ dimen = geom(W, h), stepper } }
        self.layout = { { minus, plus } }
    end

    function NumberPickerWidget:leafSetValue()
        local box = self.leaf_value_box
        if not box then return end
        if self.leaf_stepper then
            box[1] = text(tostring(self.formatted_value), "ui", "fs-sm", "text")
        else
            box[1] = value_group(self)
        end
    end

    L.wrap(NumberPickerWidget, "init", function(orig, self)
        orig(self)
        -- only pickers laid out by a Leaf dialog (leaf_width set); others keep KOReader's column
        if not self.leaf_width then return end
        local up = self.layout[1][1]
        local down = self.layout[#self.layout][1]
        if not self.value_table then
            self.leaf_input_cb = function() enter_number(self) end
        end
        if self.leaf_stepper then build_stepper(self, up, down) else build_slider(self, up, down) end
        -- dimen must be a real Geom (HorizontalGroup:getSize() returns a plain table)
        local sz = self[1]:getSize()
        self.dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }
        self.frame = self[1]
        self:refocusWidget()
    end, "NumberPickerWidget:init")

    L.wrap(NumberPickerWidget, "update", function(orig, self)
        if not self.leaf_width then return orig(self) end
        -- KOReader's update() sets the value text on its own Button: give it a scratch one
        local real = self.text_value
        self.text_value = { setText = function() end }
        local ok, err = pcall(orig, self)
        self.text_value = real
        if not ok then error(err, 0) end
        self:leafSetValue()
        if self.leaf_slider then self.leaf_slider:setPct(pct_of(self)) end
    end, "NumberPickerWidget:update")

    ---------------------------------------------------------------- the dialog
    local PAD = function() return T.px("sp-5") end
    -- .ko-dialog.gp-spin / .gp-dt: min(92%, 480px)
    local function dialog_width()
        return math.min(math.floor(Screen:getWidth() * 0.92), Screen:scaleBySize(480 * T.scale))
    end
    M.dialog_width = dialog_width

    -- {{text, bold}, ...} on one line, --fs-sm --text-3 (bold parts: semibold --text)
    local function rich(parts, max_w)
        local g = HorizontalGroup:new{ align = "bottom" }
        for _i, p in ipairs(parts) do
            table.insert(g, text(p[1], p[2] and "ui-semibold" or "ui", "fs-sm", p[2] and "text" or "text-3", max_w))
        end
        return g
    end

    -- .gp-spin-meta: left text, right "⌨ Type a number" (.ko-link)
    local function meta(inner, left, link_label, link_cb)
        local h = T.px("h-chip")
        local g = OverlapGroup:new{ dimen = geom(inner, h), LeftContainer:new{ dimen = geom(inner, h), left } }
        if link_cb then
            local lg = HorizontalGroup:new{ align = "center",
                tint("leaf.gw.keyboard", "icon-sm", "accent"), HorizontalSpan:new{ width = Screen:scaleBySize(5 * T.scale) },
                text(link_label, "ui-medium", "fs-sm", "accent") }
            local sz = lg:getSize()
            lg:resetLayout()
            local w = sz.w + 2 * T.px("sp-2")
            table.insert(g, RightContainer:new{ dimen = geom(inner, h),
                Kit.Tap:new{ width = w, height = h, callback = link_cb, content = CenterContainer:new{ dimen = geom(w, h), lg } } })
        end
        return g
    end

    -- .gp-ko: ⓘ KOReader: …
    local function ko_note(s, inner)
        return HorizontalGroup:new{ align = "center", tint("leaf.gw.info", "icon-sm", "text-3"),
            HorizontalSpan:new{ width = T.px("sp-1h") },
            text(_("KOReader") .. ": " .. s, "ui", "fs-xs", "text-3", inner - T.px("icon-sm") - T.px("sp-1h")) }
    end

    local function label_width(s)
        local tw = TextWidget:new{ text = s, face = require("ui/font"):getFace(value_face, T.fs("fs-md")) }
        local w = tw:getSize().w
        tw:free()
        return w
    end
    -- does one action row hold these entries (buttons.lua sizes: label + 2 x --sp-4, min 64px)?
    local function fits(entries, inner)
        local total = 0
        for i, e in ipairs(entries) do
            total = total + math.max(math.floor(T.px("h-control") * 1.6), label_width(e.text) + 2 * T.px("sp-4") + 2 * Size.padding.button)
                + (i > 1 and T.px("sp-1") or 0)
        end
        return total <= inner
    end

    --[[ o = { title, sub, help, rows = {widgets}, sunken, meta, ko, actions = {entries},
              extras = {entries} (beside the actions when they fit, else a row above) }
         -> vgroup, button_table, insert position for added widgets ]]
    local function body(self, o, inner)
        local surface = T.color("surface")
        local vg = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = PAD() },
            TextBoxWidget:new{ text = o.title or "", face = L.face("ui-semibold", "fs-head"), width = inner, bgcolor = surface } }
        if o.sub and o.sub ~= "" then
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-half") })
            table.insert(vg, text(o.sub, "ui", "fs-sm", "text-3", inner))
        end
        if o.help and o.help ~= "" then
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-1h") })
            table.insert(vg, TextBoxWidget:new{ text = o.help, face = L.face("ui", "fs-md"), fgcolor = T.color("text-2"),
                width = inner, bgcolor = surface })
        end
        table.insert(vg, VerticalSpan:new{ width = T.px("sp-3") })
        if o.sunken then
            -- .ko-group.ko-group--sunken: --surface-2, hairline --border, --r-lg, rows split by inset hairlines
            local hair = T.px("hairline")
            local g = VerticalGroup:new{ align = "left" }
            for i, r in ipairs(o.rows) do
                if i > 1 then
                    table.insert(g, HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-4") },
                        Kit.line(inner - 2 * hair - T.px("sp-4"), "border") })
                end
                table.insert(g, r)
            end
            table.insert(vg, FrameContainer:new{ bordersize = hair, color = T.color("border"),
                background = T.color("surface-2"), radius = T.px("r-lg"), padding = 0, margin = 0, g })
        else
            for _i, r in ipairs(o.rows) do table.insert(vg, r) end
        end
        if o.meta then
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-1") })
            table.insert(vg, o.meta)
        end
        local insert_at = #vg + 1
        if o.ko then
            table.insert(vg, VerticalSpan:new{ width = T.px("sp-3") })
            table.insert(vg, ko_note(o.ko, inner))
        end
        local buttons = {}
        local extras = o.extras or {}
        local all = {}
        for _i, e in ipairs(o.actions) do if e.leaf_left then table.insert(all, e) end end
        for _i, e in ipairs(extras) do table.insert(all, e) end
        for _i, e in ipairs(o.actions) do if not e.leaf_left then table.insert(all, e) end end
        local row = all
        if #extras > 0 and not fits(all, inner) then
            table.insert(buttons, extras)
            row = o.actions
        end
        table.insert(buttons, row)
        local button_table = ButtonTable:new{ width = inner, buttons = buttons, zero_sep = true, show_parent = self,
            leaf_actions = true }
        table.insert(vg, VerticalSpan:new{ width = T.px("sp-4") - Size.padding.buttontable })
        table.insert(vg, button_table)
        return vg, button_table, insert_at
    end

    local function frame(vgroup)
        return FrameContainer:new{
            radius = T.px("r-lg"), bordersize = T.px("hairline"), color = T.color("border-strong"),
            padding = 0, padding_left = PAD(), padding_right = PAD(), margin = 0,
            background = T.color("surface"), vgroup,
        }
    end

    local function default_entry(label, enabled, callback)
        return { text = label, leaf_left = true, enabled = enabled, callback = callback }
    end
    -- KOReader "Language defaults: 2 / 2" -> "Language defaults · 2 / 2"
    local function dot(s) return (s:gsub(":%s+", " · ", 1)) end

    ---------------------------------------------------------------- SpinWidget
    L.wrap(SpinWidget, "update", function(orig, self, numberpicker_value, numberpicker_value_index)
        local prev_offset = self.movable and self.movable:getMovedOffset()
        local prev_alpha = self.movable and self.movable.alpha
        local H = human("spin", self.title_text)
        self.width = dialog_width()
        local inner = self.width - 2 * PAD()
        self.layout = {}
        self.value_widget = NumberPickerWidget:new{
            show_parent = self, leaf_width = inner, leaf_label = H.label or self.leaf_label,
            leaf_input_label = H.label or self.leaf_label or self.title_text,
            value = numberpicker_value or self.value,
            value_table = self.value_table,
            value_index = numberpicker_value_index or self.value_index,
            value_min = self.value_min, value_max = self.value_max,
            value_step = self.value_step, value_hold_step = self.value_hold_step,
            precision = self.precision, wrap = self.wrap, unit = self.unit,
            picker_updated_callback = function(value, value_index) self:update(value, value_index) end,
        }
        self:mergeLayoutInVertical(self.value_widget)
        local vw = self.value_widget
        local current, current_index = vw:getValue()
        local unit = (self.unit and self.unit ~= "") and self.unit or ""

        local function closing(cb)
            return function()
                if cb then
                    self.value, self.value_index = vw:getValue()
                    cb(self)
                end
                if not self.keep_shown_on_apply then self:onClose() end
            end
        end
        local extras = {}
        if self.extra_text then
            table.insert(extras, { text = H.extra and H.extra[self.extra_text] or self.extra_text, callback = closing(self.extra_callback) })
        end
        if self.option_text then table.insert(extras, { text = self.option_text, callback = closing(self.option_callback) }) end

        local actions = {}
        local default_shown
        if self.default_value then
            default_shown = self.default_text
            if not default_shown then
                local v = self.value_table and self.value_table[self.default_value] or self.default_value
                default_shown = (self.value_table and tostring(v) or plain(self.precision, v)) .. unit
            end
            local at_default = (self.value_table and current_index == self.default_value) or (not self.value_table and current == self.default_value)
            -- "Default · 14", or just "Default" when an extra button shares the row
            local label = #extras > 0 and _("Default") or (_("Default") .. " · " .. default_shown)
            table.insert(actions, default_entry(label, not at_default, function()
                if vw.value_table then
                    vw.value_index = self.default_value
                    vw.value = vw.value_table[self.default_value]
                else
                    vw.value = self.default_value
                end
                vw:update()
            end))
        end
        table.insert(actions, { text = self.cancel_text or _("Close"), callback = function()
            if self.cancel_callback then self.cancel_callback() end
            self:onClose()
        end })
        table.insert(actions, { text = self.ok_text or _("Apply"),
            enabled = self.ok_always_enabled or self.original_value ~= current,
            callback = function()
                self.value, self.value_index = vw:getValue()
                self.original_value = self.value
                if self.callback then self.callback(self) end
                if self.keep_shown_on_apply then self:update() else self:onClose() end
            end })

        local range
        if not self.value_table then
            range = string.format("%s–%s%s", plain(self.precision, self.value_min), plain(self.precision, self.value_max), unit)
            if default_shown then range = range .. " · " .. _("default") .. " " .. default_shown end
        elseif default_shown then
            range = _("Default") .. " " .. default_shown
        end
        local vgroup, button_table, insert_at = body(self, {
            title = H.title or self.title_text, help = H.help or self.info_text,
            rows = { vw },
            meta = meta(inner, text(range or "", "ui", "fs-sm", "text-3", inner / 2), _("Type a number"), vw.leaf_input_cb),
            ko = H.ko or (H.title and self.title_text) or nil, actions = actions, extras = extras,
        }, inner)
        self.vgroup = vgroup
        self._leaf_insert_at = insert_at
        self:mergeLayoutInVertical(button_table)
        self.spin_frame = frame(self.vgroup)
        self.movable = MovableContainer:new{ alpha = prev_alpha, self.spin_frame }
        self[1] = WidgetContainer:new{ align = "center",
            dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height }, self.movable }
        if self._added_widgets then
            for _i, widget in ipairs(self._added_widgets) do self:addWidget(widget, true) end
        end
        if prev_offset then self.movable:setMovedOffset(prev_offset) end
        self:refocusWidget()
        UIManager:setDirty(self, function() return "ui", self.spin_frame.dimen end)
    end, "SpinWidget:update")

    -- added widgets (a check box under the value) go above the note and the buttons
    L.wrap(SpinWidget, "addWidget", function(orig, self, widget, re_init)
        if not self._leaf_insert_at then return orig(self, widget, re_init) end
        if not re_init then
            self._added_widgets = self._added_widgets or {}
            table.insert(self._added_widgets, widget)
            table.insert(self.layout, #self.layout, { widget })
        end
        table.insert(self.vgroup, self._leaf_insert_at, widget)
        self._leaf_insert_at = self._leaf_insert_at + 1
        self.vgroup:resetLayout()
    end, "SpinWidget:addWidget")
    L.wrap(SpinWidget, "getAddedWidgetAvailableWidth", function(orig, self)
        return self.width - 2 * PAD()
    end, "SpinWidget:getAddedWidgetAvailableWidth")

    ---------------------------------------------------------------- DoubleSpinWidget
    local DoubleSpinWidget = require("ui/widget/doublespinwidget")
    L.wrap(DoubleSpinWidget, "update", function(orig, self, left_value, right_value)
        local prev_offset = self.movable and self.movable:getMovedOffset()
        local prev_alpha = self.movable and self.movable.alpha
        local H = human("spin2", self.title_text)
        self.width = dialog_width()
        local inner = self.width - 2 * PAD()
        self.layout = {}
        local labels = H.labels or { self.left_text, self.right_text }
        if labels[1] == "" then labels[1] = nil end
        if labels[2] == "" then labels[2] = nil end
        local function side(name, value, label)
            return NumberPickerWidget:new{
                show_parent = self, leaf_width = inner, leaf_label = label, leaf_input_label = label or self.title_text,
                value = value or self[name .. "_value"],
                value_min = self[name .. "_min"], value_max = self[name .. "_max"],
                value_step = self[name .. "_step"], value_hold_step = self[name .. "_hold_step"],
                precision = self[name .. "_precision"], wrap = self[name .. "_wrap"], unit = self.unit,
            }
        end
        self.left_widget = side("left", left_value, labels[1])
        self.right_widget = side("right", right_value, labels[2])
        self:mergeLayoutInVertical(self.left_widget)
        self:mergeLayoutInVertical(self.right_widget)
        self.left_widget.picker_updated_callback = function(value) self:update(value, self.right_widget:getValue()) end
        self.right_widget.picker_updated_callback = function(value) self:update(self.left_widget:getValue(), value) end

        local lv, rv = self.left_widget:getValue(), self.right_widget:getValue()
        local unit = (self.unit and self.unit ~= "") and self.unit or ""
        local sep = H.sep or (self.is_range and " – " or " / ")
        local function f(p, v) return plain(p, v) end
        local actions = {}
        if self.left_default and self.right_default then
            local shown = self.default_text and dot(self.default_text)
                or (_("Default") .. " · " .. f(self.left_precision, self.left_default) .. sep .. f(self.right_precision, self.right_default) .. unit)
            table.insert(actions, default_entry(shown, lv ~= self.left_default or rv ~= self.right_default, function()
                self.left_widget.value = self.left_default
                self.right_widget.value = self.right_default
                self.left_widget:update()
                self.right_widget:update()
            end))
        end
        table.insert(actions, { text = self.cancel_text or _("Close"), callback = function()
            if self.cancel_callback then self.cancel_callback() end
            self:onClose()
        end })
        table.insert(actions, { text = self.ok_text or _("Apply"),
            enabled = self.ok_always_enabled or self.left_value ~= lv or self.right_value ~= rv,
            callback = function()
                self.left_value = self.left_widget:getValue()
                self.right_value = self.right_widget:getValue()
                if self.callback then self.callback(self.left_value, self.right_value) end
                if self.keep_shown_on_apply then self:update() else self:onClose() end
            end })
        local extras
        if self.extra_text then
            extras = { { text = self.extra_text, callback = function()
                if self.extra_callback then self.extra_callback(self.left_widget:getValue(), self.right_widget:getValue()) end
                if not self.keep_shown_on_apply then self:onClose() end
            end } }
        end
        -- "Low 20 – high 90%"
        local summary
        if labels[1] and labels[2] then
            summary = string.format("%s %s%s%s %s%s", labels[1], f(self.left_precision, lv), sep, labels[2]:lower(), f(self.right_precision, rv), unit)
        else
            summary = f(self.left_precision, lv) .. sep .. f(self.right_precision, rv) .. unit
        end
        local vgroup, button_table, insert_at = body(self, {
            title = H.title or self.title_text, help = H.help or self.info_text,
            rows = { self.left_widget, self.right_widget },
            meta = meta(inner, text(summary, "ui", "fs-sm", "text-3", inner * 0.7), _("Type"), self.left_widget.leaf_input_cb),
            ko = H.ko or (H.title and self.title_text) or nil, actions = actions, extras = extras,
        }, inner)
        self._leaf_vgroup, self._leaf_insert_at = vgroup, insert_at
        self:mergeLayoutInVertical(button_table)
        self.widget_frame = frame(vgroup)
        self.movable = MovableContainer:new{ alpha = prev_alpha, self.widget_frame }
        self[1] = WidgetContainer:new{ align = "center",
            dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height }, self.movable }
        if prev_offset then self.movable:setMovedOffset(prev_offset) end
        self:refocusWidget()
        UIManager:setDirty(self, function() return "ui", self.widget_frame.dimen end)
    end, "DoubleSpinWidget:update")

    ---------------------------------------------------------------- DateTimeWidget
    local DateTimeWidget = require("ui/widget/datetimewidget")
    local ICONS = { year = "leaf.gw.calendar", month = "leaf.gw.calendar", day = "leaf.gw.calendar",
        hour = "leaf.gw.clock", min = "leaf.gw.clock-3", sec = "leaf.gw.timer" }
    L.wrap(DateTimeWidget, "createLayout", function(orig, self)
        local H = human("datetime", self.title_text)
        self.width = dialog_width()
        local inner = self.width - 2 * PAD()
        self.layout = {}
        local dummy = {}
        function dummy:free() end
        function dummy:getValue() end
        function dummy:update() end
        local date_mode = self.year or self.month
        local rows = {}
        local function field(key, label, args)
            if not self[key] then return dummy end
            args.value = self[key]
            args.show_parent = self
            args.leaf_width = inner - 2 * T.px("hairline")
            args.leaf_stepper = true
            args.leaf_label = label
            args.leaf_input_label = label
            args.leaf_icon = ICONS[key]
            local w = NumberPickerWidget:new(args)
            self:mergeLayoutInVertical(w)
            table.insert(rows, w)
            return w
        end
        local function clamp_day(month, year)
            if not (self.month and self.day) then return end
            local d = self.day_widget:getValue()
            local max = self.day_widget:getDaysInMonth(month, year)
            if d > max then
                self.day_widget.value = max
                self.day_widget:update()
            end
        end
        local clock = H.clock or date_mode
        self.year_widget = field("year", _("Year"), { value_min = self.year_min or 2021, value_max = self.year_max or 2525,
            value_step = 1, value_hold_step = self.year_hold_step or 4, precision = "%d",
            picker_updated_callback = function(value) if self.month then clamp_day(self.month_widget:getValue(), value) end end })
        self.month_widget = field("month", _("Month"), { value_min = self.month_min or 1, value_max = self.month_max or 12,
            value_step = 1, value_hold_step = self.month_hold_step or 3,
            picker_updated_callback = function(value) clamp_day(value, self.year and self.year_widget:getValue() or 2021) end })
        -- a day of a date is "Day"; a duration counts "Days"
        self.day_widget = field("day", date_mode and _("Day") or _("Days"), { value_min = self.day_min or 1, value_max = self.day_max or 31,
            value_step = 1, value_hold_step = self.day_hold_step or 3,
            date_month = self.month and self.month_widget or nil, date_year = self.year and self.year_widget or nil })
        self.hour_widget = field("hour", clock and _("Hour") or _("Hours"), { value_min = self.hour_min or 0, value_max = self.hour_max or 23,
            value_step = 1, value_hold_step = self.hour_hold_step or 4 })
        self.min_widget = field("min", clock and _("Minute") or _("Minutes"), { value_min = self.min_min or 0, value_max = self.min_max or 59,
            value_step = self.min_step or 1, value_hold_step = self.min_hold_step or 10 })
        self.sec_widget = field("sec", clock and _("Second") or _("Seconds"), { value_min = self.sec_min or 0, value_max = self.sec_max or 59,
            value_step = 1, value_hold_step = self.sec_hold_step or 10 })

        local function values()
            return { year = self.year_widget:getValue(), month = self.month_widget:getValue(), day = self.day_widget:getValue(),
                hour = self.hour_widget:getValue(), minute = self.min_widget:getValue(), second = self.sec_widget:getValue() }
        end
        -- a changed value rebuilds the note line
        for _i, w in ipairs(rows) do
            local prev = w.picker_updated_callback
            w.picker_updated_callback = function(...)
                if prev then prev(...) end
                if self._leaf_note_box and H.note then
                    self._leaf_note_box[1] = rich(H.note(values()), inner * 0.7)
                    UIManager:setDirty(self, "ui")
                end
            end
        end
        local actions = {}
        if self.default_value then
            table.insert(actions, default_entry(_("Default") .. " · " .. tostring(self.default_value), true, function()
                if self.default_callback then self.default_callback(values()) end
                if not self.keep_shown_on_apply then self:onClose() end
            end))
        end
        table.insert(actions, { text = self.cancel_text or _("Close"), callback = function()
            if self.cancel_callback then self.cancel_callback(self) end
            self:onClose()
        end })
        table.insert(actions, { text = self.ok_text or _("Apply"), callback = function()
            if self.callback then
                self.year = self.year_widget:getValue()
                self.month = self.month_widget:getValue()
                self.day = self.day_widget:getValue()
                self.hour = self.hour_widget:getValue()
                self.min = self.min_widget:getValue()
                self.sec = self.sec_widget:getValue()
                self:callback(self)
            end
            if not self.keep_shown_on_apply then self:onClose() end
        end })
        local extras
        if self.extra_text then
            extras = { { text = self.extra_text, callback = function() self.extra_callback(self) end } }
        end
        local last = rows[#rows]
        self._leaf_note_box = LeftContainer:new{ dimen = geom(inner * 0.7, T.px("h-chip")),
            H.note and rich(H.note(values()), inner * 0.7) or HorizontalSpan:new{ width = 0 } }
        local help = self.info_text
        if H.help ~= nil then help = H.help or nil end
        local vgroup, button_table, insert_at = body(self, { title = H.title or self.title_text, sub = H.sub, help = help,
            rows = rows, sunken = true,
            meta = meta(inner, self._leaf_note_box, _("Type"), last and last.leaf_input_cb),
            ko = H.ko or (H.title and self.title_text) or nil, actions = actions, extras = extras }, inner)
        self._leaf_vgroup, self._leaf_insert_at, self._leaf_human = vgroup, insert_at, H
        self:mergeLayoutInVertical(button_table)
        self.date_frame = frame(vgroup)
        self[1] = WidgetContainer:new{ align = "center",
            dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height }, self.date_frame }
        self:refocusWidget()
    end, "DateTimeWidget:createLayout")

    -- caller widgets (the read timer's check boxes) -> .ko-check-row (44px), above the note
    L.wrap(DateTimeWidget, "addWidget", function(orig, self, widget)
        if not self._leaf_insert_at then return orig(self, widget) end
        local H = self._leaf_human or {}
        if widget.initCheckButton then
            -- renamed when Leaf has a human label (.ko-check-row)
            if H.checks and widget.text and H.checks[widget.text] then
                widget.text = H.checks[widget.text]
                widget:initCheckButton(widget.checked)
            end
        end
        table.insert(self.layout, #self.layout, { widget })
        local inner = self.width - 2 * PAD()
        local row = LeftContainer:new{ dimen = geom(inner, math.max(T.px("hit"), widget:getSize().h)), widget }
        table.insert(self._leaf_vgroup, self._leaf_insert_at, VerticalSpan:new{ width = T.px("sp-1") })
        table.insert(self._leaf_vgroup, self._leaf_insert_at + 1, row)
        self._leaf_insert_at = self._leaf_insert_at + 2
        self._leaf_vgroup:resetLayout()
    end, "DateTimeWidget:addWidget")
    L.wrap(DateTimeWidget, "getAddedWidgetAvailableWidth", function(orig, self)
        return self.width - 2 * PAD()
    end, "DateTimeWidget:getAddedWidgetAvailableWidth")
end

return M
