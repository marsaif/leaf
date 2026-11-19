--[[
    Leaf slider (.ko-slider): a --hit tall touch area with a 4px --surface-3 track (--r-cover ends),
    an accent fill up to the value and a 20px knob (--surface with a --bw-lg accent ring).
    Tap anywhere on it, or drag, to set the value.

    LeafSlider:new{ width = px, pct = 0..1, on_change = function(frac, final) end, enabled = true }
    slider:setPct(frac) moves the knob without calling on_change.
--]]
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")

local LeafSlider = InputContainer:extend{
    width = nil,
    pct = 0,
    enabled = true,
    on_change = nil,
    show_parent = nil,
}

function LeafSlider:init()
    local T = require("leaf/core").T
    self.T = T
    self.knob_r = math.floor(T.px("icon-md") / 2)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = T.px("hit") }
    local range = function() return self.dimen end
    self.ges_events = {
        TapSlider = { GestureRange:new{ ges = "tap", range = range } },
        PanSlider = { GestureRange:new{ ges = "pan", range = range } },
        PanReleaseSlider = { GestureRange:new{ ges = "pan_release", range = range } },
        TouchSlider = { GestureRange:new{ ges = "touch", range = range } },
    }
end

function LeafSlider:getSize()
    return self.dimen
end

-- track runs between the knob centres at both ends, so the knob never leaves the widget
function LeafSlider:_track()
    local x0 = self.dimen.x + self.knob_r
    return x0, self.dimen.w - 2 * self.knob_r
end

function LeafSlider:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local T = self.T
    local x0, tw = self:_track()
    local th = T.px("sp-1")
    local cy = y + math.floor(self.dimen.h / 2)
    local r = T.px("r-cover")
    bb:paintRoundedRect(x0, cy - math.floor(th / 2), tw, th, T.color("surface-3"), math.min(r, math.floor(th / 2)))
    local kx = x0 + math.floor(tw * math.max(0, math.min(1, self.pct)) + 0.5)
    if self.enabled and kx > x0 then
        bb:paintRoundedRect(x0, cy - math.floor(th / 2), kx - x0, th, T.color("accent"), math.min(r, math.floor(th / 2)))
    end
    local ring = self.enabled and T.color("accent") or T.color("disabled")
    bb:paintCircle(kx, cy, self.knob_r, T.color("surface"))
    bb:paintCircle(kx, cy, self.knob_r, ring, T.px("bw-lg"))
end

function LeafSlider:setPct(frac)
    self.pct = math.max(0, math.min(1, frac))
    UIManager:setDirty(self.show_parent, "ui", self.dimen)
end

function LeafSlider:_from(ges, final)
    if not self.enabled or not ges or not ges.pos then return true end
    local x0, tw = self:_track()
    local frac = tw > 0 and (ges.pos.x - x0) / tw or 0
    frac = math.max(0, math.min(1, frac))
    if self.on_change then self.on_change(frac, final) end
    return true
end

function LeafSlider:onTapSlider(_, ges) return self:_from(ges, true) end
function LeafSlider:onPanSlider(_, ges) return self:_from(ges, false) end
function LeafSlider:onPanReleaseSlider(_, ges) return self:_from(ges, true) end
function LeafSlider:onTouchSlider() return true end -- swallow, so a drag starting on the knob doesn't move the dialog

return LeafSlider
