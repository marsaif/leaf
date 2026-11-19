--[[
    Leaf segmented control (.ko-seg): a --surface-2 track with --r-md corners; the selected
    segment is --surface with a --bw-md accent outline and an accent semibold label, the others
    --text-2. Each segment is at least --h-seg tall and splits the width evenly.

    LeafSeg:new{ width = px, items = { {label=, key=}, ... }, selected = key, on_select = function(key) end }
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")

local LeafSeg = InputContainer:extend{ width = nil, items = nil, selected = nil, on_select = nil }

function LeafSeg:init()
    local L = require("leaf/core")
    local T = L.T
    local pad = T.px("sp-half")
    local hair = T.px("hairline")
    local n = math.max(1, #self.items)
    local inner = self.width - 2 * (pad + hair)
    local cell_w = math.floor((inner - (n - 1) * pad) / n)
    local h = T.px("h-seg")
    local row = HorizontalGroup:new{ align = "center" }
    self.cells = {}
    -- e-ink: the accent is only a grey, so the selected segment gets a --text outline (.eink .ko-seg button.on)
    local eink = not require("device").screen:isColorEnabled()
    local sel_color = eink and "text" or "accent"
    for i, it in ipairs(self.items) do
        local on = it.key == self.selected
        local cell = FrameContainer:new{
            bordersize = on and T.px("bw-md") or 0, color = T.color(sel_color),
            background = T.color(on and "surface" or "surface-2"), radius = T.px("r-inner"),
            padding = 0, margin = 0,
            CenterContainer:new{ dimen = Geom:new{ w = cell_w - 2 * (on and T.px("bw-md") or 0), h = h - 2 * (on and T.px("bw-md") or 0) },
                TextWidget:new{ text = it.label, face = L.face(on and "ui-semibold" or "ui", "fs-sm"),
                    fgcolor = T.color(on and sel_color or "text-2"), max_width = cell_w - T.px("sp-2") } },
        }
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = pad }) end
        table.insert(row, cell)
        self.cells[i] = { cell = cell, key = it.key }
    end
    self[1] = FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface-2"),
        radius = T.px("r-md"), padding = pad, row }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self[1]:getSize().h }
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
end

function LeafSeg:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    InputContainer.paintTo(self, bb, x, y)
end

function LeafSeg:onTap(_, ges)
    for _, c in ipairs(self.cells) do
        local d = c.cell.dimen
        if d and ges and ges.pos and not ges.pos:notIntersectWith(d) then
            if c.key ~= self.selected and self.on_select then self.on_select(c.key) end
            return true
        end
    end
    return true
end

return LeafSeg
