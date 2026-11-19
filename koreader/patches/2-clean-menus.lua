--[[
    Cleaner look for KOReader's menus and dialogs:
    - top menu: no boxed tabs; the active tab gets a bold underline on a light rule
    - menu rows: taller, hairline light-grey separators, thin frame
    - dialogs: rounder corners, regular-weight buttons
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Size = require("ui/size")
local Screen = Device.screen

-- Dialogs
Size.radius.window = 0 -- square corners, like the Kindle UI
Size.radius.button = 0
local Button = require("ui/widget/button")
Button.text_font_bold = false

-- Top menu
local TouchMenu = require("ui/widget/touchmenu")
TouchMenu.bordersize = Size.border.default
TouchMenu.item_height = Screen:scaleBySize(56)
TouchMenu.split_height = Size.line.thin
TouchMenu.split_color = Blitbuffer.COLOR_LIGHT_GRAY

-- TouchMenuBar is local to touchmenu.lua: reach it through TouchMenu.init's upvalues
local TouchMenuBar
local i = 1
while true do
    local name, value = debug.getupvalue(TouchMenu.init, i)
    if not name then break end
    if name == "TouchMenuBar" then TouchMenuBar = value break end
    i = i + 1
end

if TouchMenuBar then
    local underline_h = Screen:scaleBySize(3)
    local rule_h = math.max(1, Size.line.thin)
    local orig_init = TouchMenuBar.init
    TouchMenuBar.init = function(self)
        orig_init(self)
        -- hide the vertical tab separators
        for _, sep in ipairs(self.icon_seps) do
            sep.paintTo = function() end
        end
        -- replace the "line with a gap" by "light rule + underline under the active tab"
        local bar_sep = self.bar_sep
        bar_sep.dimen.h = underline_h
        bar_sep.paintTo = function(line, bb, x, y)
            bb:paintRect(x, y + underline_h - rule_h, line.dimen.w, rule_h, Blitbuffer.COLOR_LIGHT_GRAY)
            local seg = line.empty_segments and line.empty_segments[1]
            if seg then
                bb:paintRect(x + seg.s, y, seg.e - seg.s, underline_h, Blitbuffer.COLOR_BLACK)
            end
        end
    end
end
