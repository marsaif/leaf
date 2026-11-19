--[[
    Input dialogs (New folder, Rename, Search, ...) in the same style as the rest:
    bold left-aligned title with no rule under it, a soft filled text field,
    and plain text buttons at the bottom right with no separator lines.
--]]
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputDialog = require("ui/widget/inputdialog")
local InputText = require("ui/widget/inputtext")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local SANS_BOLD = "source/SourceSans3-Bold.ttf"
local FIELD_BG = Blitbuffer.COLOR_GRAY_E
local HINTS = { -- placeholder text for dialogs that don't set one
    ["New folder"] = "Folder name",
}
local FIELD_FOCUS = FIELD_BG -- no outline: the cursor shows which field is active

-- Soft filled text field
local function style_field(input)
    local frame = input._frame_textwidget
    if not frame then return end
    frame.background = FIELD_BG
    frame.radius = 0
    frame.color = input.focused and FIELD_FOCUS or FIELD_BG
    local tw = input.text_widget
    if tw then
        tw.bgcolor = FIELD_BG
        if tw.text_widget then tw.text_widget.bgcolor = FIELD_BG end -- ScrollTextWidget's inner box
    end
end
local orig_initTextBox = InputText.initTextBox
InputText.initTextBox = function(self, ...)
    local saved = TextBoxWidget.bgcolor
    TextBoxWidget.bgcolor = FIELD_BG
    local ok, err = pcall(orig_initTextBox, self, ...)
    TextBoxWidget.bgcolor = saved
    if not ok then error(err, 0) end
    style_field(self)
end
for _, name in ipairs({ "focus", "unfocus" }) do
    local orig = InputText[name]
    if orig then
        InputText[name] = function(self, ...)
            local ret = orig(self, ...)
            style_field(self)
            return ret
        end
    end
end

-- Title and buttons
local orig_init = InputDialog.init
InputDialog.init = function(self)
    local orig_titlebar_new, orig_buttontable_new = TitleBar.new, ButtonTable.new
    local compact = not self.fullscreen
    if compact then
        -- taller field, same outer width as before
        local old_padding = self.input_padding
        self.input_padding = Screen:scaleBySize(11)
        if not self.condensed and not self.text_width then
            local w = self.width or math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.8)
            self.text_width = math.floor(w * 0.9) - 2 * (self.input_padding - old_padding)
        end
        if (self.input_hint == nil or self.input_hint == "") and HINTS[self.title] then
            self.input_hint = HINTS[self.title]
        end
    end
    TitleBar.new = function(class, o)
        o = o or {}
        if compact then
            o.with_bottom_line = false
            o.title_face = Font:getFace(SANS_BOLD, 26)
            o.title_top_padding = Screen:scaleBySize(18)
            o.bottom_v_padding = Screen:scaleBySize(8)
        end
        return orig_titlebar_new(class, o)
    end
    local narrow_buttons = false
    local primary_index
    ButtonTable.new = function(class, o)
        o = o or {}
        if compact and o.buttons and #o.buttons == 1 and #o.buttons[1] <= 3 then
            narrow_buttons = true
            o.sep_width = 0
            o.width = math.floor(o.width * (#o.buttons[1] == 3 and 0.75 or 0.55))
            for j, btn in ipairs(o.buttons[1]) do
                if btn.is_enter_default then
                    btn.font_bold = true
                    primary_index = j
                end
            end
        end
        return orig_buttontable_new(class, o)
    end
    local ok, err = pcall(orig_init, self)
    TitleBar.new, ButtonTable.new = orig_titlebar_new, orig_buttontable_new
    if not ok then error(err, 0) end

    -- move the (now narrower) button row to the bottom right
    if narrow_buttons and self.vgroup and self.button_table then
        local last = #self.vgroup
        local table_w = self.button_table:getSize().w
        -- primary action as a solid button
        local row = self.button_table.buttons_layout and self.button_table.buttons_layout[1]
        local primary = row and primary_index and row[primary_index]
        if primary and primary.frame then
            -- paint it black with white text (invert would ignore the rounded corners)
            primary.frame.radius = 0
            primary.frame.background = Blitbuffer.COLOR_BLACK
            if primary.label_widget then primary.label_widget.fgcolor = Blitbuffer.COLOR_WHITE end
        end
        local cancel = self.button_table.getButtonById and self.button_table:getButtonById("close")
        if cancel and cancel.label_widget then cancel.label_widget.fgcolor = Blitbuffer.COLOR_GRAY_5 end
        self.vgroup[last] = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Screen:scaleBySize(10) },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = math.max(0, self.width - table_w - Screen:scaleBySize(14)) },
                self.button_table,
            },
            VerticalSpan:new{ width = Screen:scaleBySize(14) },
        }
        self.vgroup:resetLayout()
    end
end
