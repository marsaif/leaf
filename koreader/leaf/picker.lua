--[[
    Leaf number picker (safety-net item 15; prototype overlay "picker"): SpinWidget, and the
    NumberPickerWidget used by SpinWidget, DoubleSpinWidget and DateTimeWidget.

    * NumberPickerWidget: KOReader's ▲ value ▼ column becomes a slider row (UI.sliderRow):
      [−] [slider] [+] [value]. − and + call KOReader's own step / hold-step callbacks; tapping the
      value still opens "Enter number"; the slider sets the value from the tap/drag position
      (value_table pickers move by index). Days-in-month logic for dates is kept.
    * SpinWidget: dialog laid out like the prototype: title (--fs-head), range (--fs-sm --text-3),
      description (--text-2), the slider row, then [Default · 14] … [Close] [Apply].
      Same fields and callbacks as KOReader's (value_widget, spin_frame, movable, vgroup, layout,
      callback(self), extra/option buttons, keep_shown_on_apply, addWidget()).
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local M = {}

local function unit_suffix(unit)
    if not unit or unit == "" then return "" end
    if unit == "°" then return unit end
    return "\u{202F}" .. unit
end

local function fmt(self, v)
    if self.value_table then return tostring(v) end
    return string.format(self.precision or "%02d", v)
end

-- the range is a quantity, not a clock reading: no zero padding ("6–24", not "06–24")
local function plain(self, v)
    local p = self.precision or "%02d"
    if p:match("^%%0%d+d$") then p = "%d" end
    return string.format(p, v)
end

function M.apply(L)
    local T = L.T
    local fonts = require("leaf/fonts")
    local Button = require("ui/widget/button")
    local IconButton = require("ui/widget/iconbutton")
    local LeafSlider = require("leaf/widgets/slider")
    local NumberPickerWidget = require("ui/widget/numberpickerwidget")
    local SpinWidget = require("ui/widget/spinwidget")
    local value_face = fonts.FILES["ui-medium"]

    ---------------------------------------------------------------- NumberPickerWidget -> slider row
    local function pct_of(self)
        if self.value_table then
            local n = #self.value_table
            return n > 1 and ((self.value_index or 1) - 1) / (n - 1) or 0
        end
        local span = self.value_max - self.value_min
        return span > 0 and (self.value - self.value_min) / span or 0
    end

    L.wrap(NumberPickerWidget, "init", function(orig, self)
        orig(self)
        -- only pickers whose dialog lays them out as stacked rows (leaf_width set by the Leaf dialog);
        -- others (DoubleSpin / DateTime until ported) keep KOReader's column
        if not self.leaf_width then return end
        local up = self.layout[1][1]
        local down = self.layout[#self.layout][1]
        local input_cb = self.text_value.callback
        local unit = unit_suffix(self.unit)

        local row_w = self.leaf_width or math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.6)
        local gap = T.px("sp-2")
        local icon = T.px("icon-sm")
        local step_pad = math.floor((T.px("hit") - icon) / 2)
        local step_w = icon + 2 * step_pad

        -- value column: wide enough for the widest value, at least 48px, at most 40% of the row
        local face = require("ui/font"):getFace(value_face, T.fs("fs-md"))
        local samples = {}
        if self.value_table then
            for _, v in ipairs(self.value_table) do table.insert(samples, tostring(v)) end
        else
            samples = { fmt(self, self.value_min), fmt(self, self.value_max), fmt(self, self.value) }
        end
        local value_w = T.px("h-row")
        for _, s in ipairs(samples) do
            local tw = TextWidget:new{ text = s .. unit, face = face }
            value_w = math.max(value_w, tw:getSize().w + T.px("sp-1"))
            tw:free()
        end
        value_w = math.min(value_w, math.floor(row_w * 0.4))
        -- optional label column, as .ko-sr .lbl (112px)
        local label_widget
        if self.leaf_label and self.leaf_label ~= "" then
            local label_w = Screen:scaleBySize(112 * T.scale)
            label_widget = require("ui/widget/container/leftcontainer"):new{
                dimen = Geom:new{ w = label_w, h = T.px("hit") },
                TextWidget:new{ text = self.leaf_label, face = L.face("ui", "fs-md"), max_width = label_w - gap },
            }
            row_w = row_w - label_w
        end
        local slider_w = math.max(T.px("h-row"), row_w - 2 * step_w - value_w - 3 * gap)

        local function step_button(name, src)
            return IconButton:new{
                icon = name, width = icon, height = icon, padding = step_pad,
                callback = src.callback, hold_callback = src.hold_callback, show_parent = self.show_parent,
            }
        end
        local minus = step_button("leaf.minus", down)
        local plus = step_button("plus", up)

        self.leaf_slider = LeafSlider:new{
            width = slider_w, pct = pct_of(self), show_parent = self.show_parent,
            -- while dragging only the knob and the value text move; the full update (which makes the
            -- parent dialog rebuild, slider included) runs once, on release or tap
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
                    self.text_value:setText(tostring(self.formatted_value) .. unit_suffix(self.unit), self.width)
                    self.leaf_slider:setPct(pct_of(self))
                    UIManager:setDirty(self.show_parent, "ui", self.dimen)
                end
            end,
        }

        self.width = value_w -- KOReader's update() re-sets the value text at self.width
        self.text_value = Button:new{
            text = tostring(self.formatted_value) .. unit,
            bordersize = 0, padding = 0, padding_h = 0, radius = 0,
            text_font_face = value_face, text_font_size = T.fs("fs-md"), text_font_bold = false,
            width = value_w, show_parent = self.show_parent, callback = input_cb,
        }

        self[1] = HorizontalGroup:new{ align = "center",
            label_widget or HorizontalSpan:new{ width = 0 },
            minus, HorizontalSpan:new{ width = gap },
            self.leaf_slider, HorizontalSpan:new{ width = gap },
            plus, HorizontalSpan:new{ width = gap },
            self.text_value,
        }
        self.layout = { { minus, plus, self.text_value } }
        -- dimen must be a real Geom: UIManager refreshes call Geom methods on it later
        -- (HorizontalGroup:getSize() returns a plain {w, h} table)
        local sz = self[1]:getSize()
        self.dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }
        self.frame = self[1]
        self:refocusWidget()
    end, "NumberPickerWidget:init")

    L.wrap(NumberPickerWidget, "update", function(orig, self)
        if not self.leaf_slider then return orig(self) end
        orig(self)
        -- KOReader drops the unit when it re-sets the text: put it back, move the knob
        self.text_value:setText(tostring(self.formatted_value) .. unit_suffix(self.unit), self.width)
        self.leaf_slider:setPct(pct_of(self))
    end, "NumberPickerWidget:update")

    ---------------------------------------------------------------- shared dialog (prototype "picker")
    local ButtonTable = require("ui/widget/buttontable")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local _ = require("gettext")

    local PAD = function() return T.px("sp-5") end
    -- .ko-dialog width: min(86% of the screen, 400px)
    local function dialog_width(w)
        return math.max(w or 0, math.min(math.floor(Screen:getWidth() * 0.86), Screen:scaleBySize(400 * T.scale)))
    end

    --[[ o = { title, range (string|nil), desc, rows = { picker, ... }, side_rows = { {button entries}, ... },
              actions = { button entries (last row) } }
         -> vgroup (buttons last, so addWidget() can insert above them), button_table ]]
    local function body(self, o, inner)
        local head = VerticalGroup:new{ align = "left",
            TextBoxWidget:new{ text = o.title or "", face = L.face("ui-semibold", "fs-head"), width = inner },
        }
        if o.range then
            table.insert(head, VerticalSpan:new{ width = T.px("sp-half") })
            table.insert(head, TextWidget:new{ text = o.range, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = inner })
        end
        if o.desc and o.desc ~= "" then
            table.insert(head, VerticalSpan:new{ width = T.px("sp-1h") })
            table.insert(head, TextBoxWidget:new{ text = o.desc, face = L.face("ui", "fs-md"), fgcolor = T.color("text-2"), width = inner })
        end
        local rows = VerticalGroup:new{ align = "left" }
        for _, picker in ipairs(o.rows) do table.insert(rows, picker) end

        local buttons = {}
        for _, r in ipairs(o.side_rows or {}) do table.insert(buttons, r) end
        table.insert(buttons, o.actions)
        local button_table = ButtonTable:new{ width = inner, buttons = buttons, zero_sep = true, show_parent = self }

        local vgroup = VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = PAD() },
            head,
            VerticalSpan:new{ width = T.px("sp-2") },
            rows,
            VerticalSpan:new{ width = T.px("sp-2") },
            button_table,
        }
        return vgroup, button_table
    end

    local function frame(vgroup)
        return FrameContainer:new{
            radius = Size.radius.window, padding = 0, padding_left = PAD(), padding_right = PAD(), margin = 0,
            background = T.color("surface"), vgroup,
        }
    end

    local function picker(self, inner, label, args)
        args.show_parent = self
        args.leaf_width = inner
        args.leaf_label = label
        return NumberPickerWidget:new(args)
    end

    local function default_entry(text, enabled, callback)
        return { text = _("Default") .. " · " .. text, leaf_left = true, enabled = enabled, callback = callback }
    end

    ---------------------------------------------------------------- SpinWidget
    L.wrap(SpinWidget, "update", function(orig, self, numberpicker_value, numberpicker_value_index)
        local prev_offset = self.movable and self.movable:getMovedOffset()
        local prev_alpha = self.movable and self.movable.alpha
        self.width = dialog_width(self.width)
        local inner = self.width - 2 * PAD()
        self.layout = {}

        self.value_widget = picker(self, inner, nil, {
            value = numberpicker_value or self.value,
            value_table = self.value_table,
            value_index = numberpicker_value_index or self.value_index,
            value_min = self.value_min, value_max = self.value_max,
            value_step = self.value_step, value_hold_step = self.value_hold_step,
            precision = self.precision, wrap = self.wrap, unit = self.unit,
            picker_updated_callback = function(value, value_index) self:update(value, value_index) end,
        })
        self:mergeLayoutInVertical(self.value_widget)

        local vw = self.value_widget
        local current, current_index = vw:getValue()
        local function closing(cb)
            return function()
                if cb then
                    self.value, self.value_index = vw:getValue()
                    cb(self)
                end
                if not self.keep_shown_on_apply then self:onClose() end
            end
        end
        local side = {}
        if self.extra_text then table.insert(side, { text = self.extra_text, callback = closing(self.extra_callback) }) end
        if self.option_text then table.insert(side, { text = self.option_text, callback = closing(self.option_callback) }) end

        local actions = {}
        if self.default_value then
            local shown = self.default_text
            if not shown then
                local v = self.value_table and self.value_table[self.default_value] or self.default_value
                shown = fmt(vw, v) .. unit_suffix(self.unit)
            end
            local at_default = (self.value_table and current_index == self.default_value) or (not self.value_table and current == self.default_value)
            table.insert(actions, default_entry(shown, not at_default, function()
                if vw.value_table then
                    vw.value_index = self.default_value
                    vw.value = vw.value_table[self.default_value]
                else
                    vw.value = self.default_value
                end
                vw:update()
            end))
        end
        table.insert(actions, { text = self.cancel_text, callback = function()
            if self.cancel_callback then self.cancel_callback() end
            self:onClose()
        end })
        table.insert(actions, { text = self.ok_text,
            enabled = self.ok_always_enabled or self.original_value ~= current,
            callback = function()
                self.value, self.value_index = vw:getValue()
                self.original_value = self.value
                if self.callback then self.callback(self) end
                if self.keep_shown_on_apply then self:update() else self:onClose() end
            end })

        local button_table
        self.vgroup, button_table = body(self, {
            title = self.title_text,
            range = not self.value_table and string.format("%s %s–%s%s", _("Range"), plain(vw, self.value_min), plain(vw, self.value_max), unit_suffix(self.unit)) or nil,
            desc = self.info_text,
            rows = { vw },
            side_rows = #side > 0 and { side } or nil,
            actions = actions,
        }, inner)
        self:mergeLayoutInVertical(button_table)
        self.spin_frame = frame(self.vgroup)
        self.movable = MovableContainer:new{ alpha = prev_alpha, self.spin_frame }
        self[1] = WidgetContainer:new{ align = "center",
            dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height }, self.movable }
        if self._added_widgets then
            for _, widget in ipairs(self._added_widgets) do self:addWidget(widget, true) end
        end
        if prev_offset then self.movable:setMovedOffset(prev_offset) end
        self:refocusWidget()
        UIManager:setDirty(self, function() return "ui", self.spin_frame.dimen end)
    end, "SpinWidget:update")

    ---------------------------------------------------------------- DoubleSpinWidget: two stacked rows
    local DoubleSpinWidget = require("ui/widget/doublespinwidget")
    L.wrap(DoubleSpinWidget, "update", function(orig, self, left_value, right_value)
        local prev_offset = self.movable and self.movable:getMovedOffset()
        local prev_alpha = self.movable and self.movable.alpha
        self.width = dialog_width(self.width)
        local inner = self.width - 2 * PAD()
        self.layout = {}
        local labelled = (self.left_text or "") ~= "" or (self.right_text or "") ~= ""
        local function side(name, value)
            return picker(self, inner, labelled and self[name .. "_text"] or nil, {
                value = value or self[name .. "_value"],
                value_min = self[name .. "_min"], value_max = self[name .. "_max"],
                value_step = self[name .. "_step"], value_hold_step = self[name .. "_hold_step"],
                precision = self[name .. "_precision"], wrap = self[name .. "_wrap"], unit = self.unit,
            })
        end
        self.left_widget = side("left", left_value)
        self.right_widget = side("right", right_value)
        self:mergeLayoutInVertical(self.left_widget)
        self:mergeLayoutInVertical(self.right_widget)
        self.left_widget.picker_updated_callback = function(value) self:update(value, self.right_widget:getValue()) end
        self.right_widget.picker_updated_callback = function(value) self:update(self.left_widget:getValue(), value) end

        local lv, rv = self.left_widget:getValue(), self.right_widget:getValue()
        local actions = {}
        if self.left_default and self.right_default then
            local sep = self.is_range and "–" or " / "
            local function f(p, v) return p and string.format(p, v) or tostring(v) end
            local shown = self.default_text or (f(self.left_precision, self.left_default) .. sep
                .. f(self.right_precision, self.right_default) .. unit_suffix(self.unit))
            table.insert(actions, default_entry(shown, lv ~= self.left_default or rv ~= self.right_default, function()
                self.left_widget.value = self.left_default
                self.right_widget.value = self.right_default
                self.left_widget:update()
                self.right_widget:update()
            end))
        end
        table.insert(actions, { text = self.cancel_text, callback = function()
            if self.cancel_callback then self.cancel_callback() end
            self:onClose()
        end })
        table.insert(actions, { text = self.ok_text,
            enabled = self.ok_always_enabled or self.left_value ~= lv or self.right_value ~= rv,
            callback = function()
                self.left_value = self.left_widget:getValue()
                self.right_value = self.right_widget:getValue()
                if self.callback then self.callback(self.left_value, self.right_value) end
                if self.keep_shown_on_apply then self:update() else self:onClose() end
            end })
        local side_rows
        if self.extra_text then
            side_rows = { { { text = self.extra_text, callback = function()
                if self.extra_callback then self.extra_callback(self.left_widget:getValue(), self.right_widget:getValue()) end
                if not self.keep_shown_on_apply then self:onClose() end
            end } } }
        end

        local vgroup, button_table = body(self, {
            title = self.title_text, desc = self.info_text,
            rows = { self.left_widget, self.right_widget }, side_rows = side_rows, actions = actions,
        }, inner)
        self:mergeLayoutInVertical(button_table)
        self.widget_frame = frame(vgroup)
        self.movable = MovableContainer:new{ alpha = prev_alpha, self.widget_frame }
        self[1] = WidgetContainer:new{ align = "center",
            dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height }, self.movable }
        if prev_offset then self.movable:setMovedOffset(prev_offset) end
        self:refocusWidget()
        UIManager:setDirty(self, function() return "ui", self.widget_frame.dimen end)
    end, "DoubleSpinWidget:update")

    ---------------------------------------------------------------- DateTimeWidget: one row per field
    local DateTimeWidget = require("ui/widget/datetimewidget")
    L.wrap(DateTimeWidget, "createLayout", function(orig, self)
        self.width = dialog_width(self.width)
        local inner = self.width - 2 * PAD()
        self.layout = {}
        local dummy = {}
        function dummy:free() end
        function dummy:getValue() end
        function dummy:update() end

        local rows = {}
        local function field(key, label, args)
            if not self[key] then return dummy end
            args.value = self[key]
            local w = picker(self, inner, label, args)
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
        self.year_widget = field("year", _("Year"), { value_min = self.year_min or 2021, value_max = self.year_max or 2525,
            value_step = 1, value_hold_step = self.year_hold_step or 4, precision = "%d",
            picker_updated_callback = function(value) if self.month then clamp_day(self.month_widget:getValue(), value) end end })
        self.month_widget = field("month", _("Month"), { value_min = self.month_min or 1, value_max = self.month_max or 12,
            value_step = 1, value_hold_step = self.month_hold_step or 3,
            picker_updated_callback = function(value) clamp_day(value, self.year and self.year_widget:getValue() or 2021) end })
        self.day_widget = field("day", _("Day"), { value_min = self.day_min or 1, value_max = self.day_max or 31,
            value_step = 1, value_hold_step = self.day_hold_step or 3,
            date_month = self.month and self.month_widget or nil, date_year = self.year and self.year_widget or nil })
        self.hour_widget = field("hour", _("Hours"), { value_min = self.hour_min or 0, value_max = self.hour_max or 23,
            value_step = 1, value_hold_step = self.hour_hold_step or 4 })
        self.min_widget = field("min", _("Minutes"), { value_min = self.min_min or 0, value_max = self.min_max or 59,
            value_step = self.min_step or 1, value_hold_step = self.min_hold_step or 10 })
        self.sec_widget = field("sec", _("Seconds"), { value_min = self.sec_min or 0, value_max = self.sec_max or 59,
            value_step = 1, value_hold_step = self.sec_hold_step or 10 })

        local function values()
            return { year = self.year_widget:getValue(), month = self.month_widget:getValue(), day = self.day_widget:getValue(),
                hour = self.hour_widget:getValue(), minute = self.min_widget:getValue(), second = self.sec_widget:getValue() }
        end
        local actions = {}
        if self.default_value then
            table.insert(actions, default_entry(self.default_text or tostring(self.default_value), true, function()
                if self.default_callback then self.default_callback(values()) end
                if not self.keep_shown_on_apply then self:onClose() end
            end))
        end
        table.insert(actions, { text = self.cancel_text, callback = function()
            if self.cancel_callback then self.cancel_callback(self) end
            self:onClose()
        end })
        table.insert(actions, { text = self.ok_text, callback = function()
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
        local side_rows
        if self.extra_text then
            side_rows = { { { text = self.extra_text, callback = function() self.extra_callback(self) end } } }
        end

        local vgroup, button_table = body(self, { title = self.title_text, desc = self.info_text,
            rows = rows, side_rows = side_rows, actions = actions }, inner)
        self:mergeLayoutInVertical(button_table)
        self.date_frame = frame(vgroup)  -- addWidget() inserts into date_frame[1], above the buttons
        self[1] = WidgetContainer:new{ align = "center",
            dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height }, self.date_frame }
        self:refocusWidget()
    end, "DateTimeWidget:createLayout")
    L.wrap(DateTimeWidget, "getAddedWidgetAvailableWidth", function(orig, self)
        return self.width - 2 * PAD()
    end, "DateTimeWidget:getAddedWidgetAvailableWidth")

    -- added widgets (e.g. a check box under the value) span the inner width
    L.wrap(SpinWidget, "getAddedWidgetAvailableWidth", function(orig, self)
        return self.width - 2 * T.px("sp-5")
    end, "SpinWidget:getAddedWidgetAvailableWidth")
end

return M
