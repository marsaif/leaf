--[[
    Leaf toggle (.ko-toggle): 40x24 track with --r-mark ends and an 18px knob.
    off: --surface-3 track, --border-strong hairline, --bg-raised knob with a hairline ring.
    on:  accent track, --accent-ink knob on the right. Disabled: --disabled tones.
    Display only: the row it sits in handles the tap.
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local LeafToggle = Widget:extend{ on = false, enabled = true }

function LeafToggle:init()
    local T = require("leaf/core").T
    self.T = T
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:scaleBySize(40 * T.scale), h = Screen:scaleBySize(24 * T.scale) }
end

function LeafToggle:getSize() return self.dimen end

function LeafToggle:paintTo(bb, x, y)
    local T, d = self.T, self.dimen
    d.x, d.y = x, y
    local r = math.floor(d.h / 2)
    local hair = T.px("hairline")
    local on = self.on and self.enabled
    local track = on and T.color("accent") or T.color("surface-3")
    local edge = on and T.color("accent") or T.color(self.enabled and "border-strong" or "disabled")
    bb:paintRoundedRect(x, y, d.w, d.h, edge, r)
    bb:paintRoundedRect(x + hair, y + hair, d.w - 2 * hair, d.h - 2 * hair, track, r - hair)
    local kr = math.floor(Screen:scaleBySize(18 * T.scale) / 2)
    local inset = math.floor(d.h / 2)
    local cx = self.on and (x + d.w - inset) or (x + inset)
    local cy = y + math.floor(d.h / 2)
    if on then
        bb:paintCircle(cx, cy, kr, T.color("accent-ink"))
    else
        bb:paintCircle(cx, cy, kr, T.color("border-strong"))
        bb:paintCircle(cx, cy, kr - hair, T.color("bg-raised"))
    end
end

return LeafToggle
