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

    ---------------------------------------------------------------- SpinWidget dialog
    local ButtonTable = require("ui/widget/buttontable")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")

    L.wrap(SpinWidget, "update", function(orig, self, numberpicker_value, numberpicker_value_index)
        local prev_offset = self.movable and self.movable:getMovedOffset()
        local prev_alpha = self.movable and self.movable.alpha
        local pad = T.px("sp-5")
        -- .ko-dialog width: min(86% of the screen, 400px)
        self.width = math.max(self.width, math.min(math.floor(Screen:getWidth() * 0.86), Screen:scaleBySize(400 * T.scale)))
        local inner = self.width - 2 * pad
        self.layout = {}

        self.value_widget = NumberPickerWidget:new{
            show_parent = self,
            leaf_width = inner,
            value = numberpicker_value or self.value,
            value_table = self.value_table,
            value_index = numberpicker_value_index or self.value_index,
            value_min = self.value_min,
            value_max = self.value_max,
            value_step = self.value_step,
            value_hold_step = self.value_hold_step,
            precision = self.precision,
            wrap = self.wrap,
            unit = self.unit,
            picker_updated_callback = function(value, value_index)
                self:update(value, value_index)
            end,
        }
        self:mergeLayoutInVertical(self.value_widget)

        -- header: title, range, description
        local head = VerticalGroup:new{ align = "left",
            TextBoxWidget:new{ text = self.title_text or "", face = L.face("ui-semibold", "fs-head"), width = inner },
        }
        if not self.value_table then
            local vw = self.value_widget
            table.insert(head, VerticalSpan:new{ width = T.px("sp-half") })
            table.insert(head, TextWidget:new{
                text = string.format("Range %s–%s%s", plain(vw, self.value_min), plain(vw, self.value_max), unit_suffix(self.unit)),
                face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = inner,
            })
        end
        if self.info_text and self.info_text ~= "" then
            table.insert(head, VerticalSpan:new{ width = T.px("sp-1h") })
            table.insert(head, TextBoxWidget:new{
                text = self.info_text, face = L.face("ui", "fs-md"), fgcolor = T.color("text-2"), width = inner,
            })
        end

        -- buttons: [Default · x] … [Close] [Apply]; extra / option buttons on a row above
        local current = self.value_widget:getValue()
        local _, current_index = self.value_widget:getValue()
        local buttons = {}
        local function closing(cb)
            return function()
                if cb then
                    self.value, self.value_index = self.value_widget:getValue()
                    cb(self)
                end
                if not self.keep_shown_on_apply then self:onClose() end
            end
        end
        local extra = {}
        if self.extra_text then table.insert(extra, { text = self.extra_text, callback = closing(self.extra_callback) }) end
        if self.option_text then table.insert(extra, { text = self.option_text, callback = closing(self.option_callback) }) end
        if #extra > 0 then table.insert(buttons, extra) end

        local actions = {}
        if self.default_value then
            local shown = self.default_text
            if not shown then
                local v = self.value_table and self.value_table[self.default_value] or self.default_value
                shown = fmt(self.value_widget, v) .. unit_suffix(self.unit)
            end
            local at_default = self.value_table and current_index == self.default_value or (not self.value_table and current == self.default_value)
            table.insert(actions, {
                text = "Default · " .. shown,
                leaf_left = true,
                enabled = not at_default,
                callback = function()
                    if self.value_widget.value_table then
                        self.value_widget.value_index = self.default_value
                        self.value_widget.value = self.value_widget.value_table[self.default_value]
                    else
                        self.value_widget.value = self.default_value
                    end
                    self.value_widget:update()
                end,
            })
        end
        table.insert(actions, {
            text = self.cancel_text,
            callback = function()
                if self.cancel_callback then self.cancel_callback() end
                self:onClose()
            end,
        })
        table.insert(actions, {
            text = self.ok_text,
            enabled = self.ok_always_enabled or self.original_value ~= current,
            callback = function()
                self.value, self.value_index = self.value_widget:getValue()
                self.original_value = self.value
                if self.callback then self.callback(self) end
                if self.keep_shown_on_apply then self:update() else self:onClose() end
            end,
        })
        table.insert(buttons, actions)
        local button_table = ButtonTable:new{ width = inner, buttons = buttons, zero_sep = true, show_parent = self }
        self:mergeLayoutInVertical(button_table)

        self.vgroup = VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = pad },
            head,
            VerticalSpan:new{ width = T.px("sp-2") },
            self.value_widget,
            VerticalSpan:new{ width = T.px("sp-2") },
            button_table,
        }
        self.spin_frame = FrameContainer:new{
            radius = Size.radius.window,
            padding = 0, padding_left = pad, padding_right = pad,
            margin = 0,
            background = T.color("surface"),
            self.vgroup,
        }
        self.movable = MovableContainer:new{ alpha = prev_alpha, self.spin_frame }
        self[1] = WidgetContainer:new{
            align = "center",
            dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height },
            self.movable,
        }
        if self._added_widgets then
            for _, widget in ipairs(self._added_widgets) do self:addWidget(widget, true) end
        end
        if prev_offset then self.movable:setMovedOffset(prev_offset) end
        self:refocusWidget()
        UIManager:setDirty(self, function() return "ui", self.spin_frame.dimen end)
    end, "SpinWidget:update")

    -- added widgets (e.g. a check box under the value) span the inner width
    L.wrap(SpinWidget, "getAddedWidgetAvailableWidth", function(orig, self)
        return self.width - 2 * T.px("sp-5")
    end, "SpinWidget:getAddedWidgetAvailableWidth")
end

return M
