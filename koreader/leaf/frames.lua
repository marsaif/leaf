--[[
    Leaf frames and lines (safety-net items 2, 3, 7, 26): the parts of KOReader's look that come
    from shared sizes and default colours, changed once for every widget.

    * Size.radius: windows (dialogs, popups) --r-lg, buttons --r-md, small frames --r-sm.
    * Size.border / Size.line: every border and separator is a --hairline; "thick" is --bw-lg / --bw-md.
    * FrameContainer: default border colour --border-strong (Leaf has no black outlines; on e-ink a
      floating panel's shadow becomes this 1px outline).
    * LineWidget: any hairline-thin line is a separator and is painted --border, whatever grey or
      black the caller chose. Thicker lines (selection underlines, bars) keep their colour.
    Paddings are left alone here: they change layout maths, so each widget's restyle sets its own.
--]]
local Size = require("ui/size")

local M = {}

function M.apply(L)
    local T = L.T
    local hair = T.px("hairline")

    Size.radius.window = T.px("r-lg")
    Size.radius.button = T.px("r-md")
    Size.radius.default = T.px("r-sm")

    Size.border.default = hair
    Size.border.thin = hair
    Size.border.button = hair
    Size.border.window = hair
    Size.border.inputtext = hair
    Size.border.thick = T.px("bw-lg")

    Size.line.thin = hair
    Size.line.medium = hair
    Size.line.thick = T.px("bw-md")

    -- loaded after Size is changed, so class defaults computed from Size pick the new values
    local FrameContainer = require("ui/widget/container/framecontainer")
    FrameContainer.color = T.color("border-strong")
    FrameContainer.focus_border_size = 2 * hair

    local LineWidget = require("ui/widget/linewidget")
    local Blitbuffer = require("ffi/blitbuffer")
    local border = T.color("border")
    L.wrap(LineWidget, "paintTo", function(orig, self, bb, x, y)
        local d = self.dimen
        if d and (d.h <= hair or d.w <= hair) and self.background and self.background ~= Blitbuffer.COLOR_WHITE then
            local bg = self.background
            self.background = border
            orig(self, bb, x, y)
            self.background = bg
            return
        end
        return orig(self, bb, x, y)
    end, "LineWidget:paintTo")
end

return M
