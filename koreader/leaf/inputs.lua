--[[
    Leaf text input (safety-net item 13): InputDialog, MultiInputDialog, InputText.
    Replaces the pre-Leaf patch 2-dialogs.lua (patches/legacy/). Target: prototype overlay "input".

    * Field (.kb-field--compact): soft filled --surface-2, --r-md corners, no outline (the cursor
      shows the active field), Inter --fs-md, --sp-3 padding (44px tall).
    * Compact dialogs: the title (Leaf TitleBar) has no rule under it; width is the Leaf dialog width
      (min(86%, 400px)) unless the caller chose one. Fullscreen editors keep their layout.
    * Actions: buttons.lua's action row (right-aligned, the last one primary).
--]]
local Device = require("device")
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local InputText = require("ui/widget/inputtext")
    local InputDialog = require("ui/widget/inputdialog")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TitleBar = require("ui/widget/titlebar")

    local field_bg = T.color("surface-2")
    InputDialog.input_face = L.face("ui", "fs-md")
    InputDialog.input_padding = T.px("sp-3")

    local function style_field(input)
        local frame = input._frame_textwidget
        if not frame then return end
        frame.background = field_bg
        frame.radius = T.px("r-md")
        frame.color = field_bg
        local tw = input.text_widget
        if tw then
            tw.bgcolor = field_bg
            if tw.text_widget then tw.text_widget.bgcolor = field_bg end -- ScrollTextWidget's inner box
        end
    end

    L.wrap(InputText, "initTextBox", function(orig, self, ...)
        local saved = TextBoxWidget.bgcolor
        TextBoxWidget.bgcolor = field_bg
        local ok, err = pcall(orig, self, ...)
        TextBoxWidget.bgcolor = saved
        if not ok then error(err, 0) end
        style_field(self)
    end, "InputText:initTextBox")
    for _, name in ipairs({ "focus", "unfocus" }) do
        if InputText[name] then
            L.wrap(InputText, name, function(orig, self, ...)
                local ret = orig(self, ...)
                style_field(self)
                return ret
            end, "InputText:" .. name)
        end
    end

    L.wrap(InputDialog, "init", function(orig, self)
        if self.fullscreen then return orig(self) end
        local pad = T.px("sp-5")
        -- the frame gets --sp-5 side padding: lay the content out in the inner width, and let the
        -- field fill it (KOReader uses 90%). KOReader re-runs init() (keyboard toggle, rotation):
        -- start from the original width every time.
        if not self._leaf_width then
            self._leaf_width = self.width or math.min(math.floor(Screen:getWidth() * 0.86), Screen:scaleBySize(400 * T.scale))
        end
        self.width = self._leaf_width - 2 * pad
        if not self.text_width then
            self.text_width = self.width - 2 * ((self.border_size or 0) + self.input_padding + self.input_margin)
        end
        -- compact dialogs: no rule under the title, title aligned with the field
        local orig_new = TitleBar.new
        TitleBar.new = function(class, o)
            o = o or {}
            o.with_bottom_line = false
            o.title_h_padding = 0
            return orig_new(class, o)
        end
        local ok, err = pcall(orig, self)
        TitleBar.new = orig_new
        if not ok then error(err, 0) end
        local frame = self.dialog_frame
        if frame then
            frame.padding_left = pad
            frame.padding_right = pad
            frame.background = T.color("surface")
        end
    end, "InputDialog:init")
end

return M
