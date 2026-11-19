--[[
    Leaf bottom navigation (.ko-nav, prototype App.bottomNav): Home · Library · History · Settings.
    --h-nav tall, --bg-raised with a --border hairline on top; each item is an icon over a
    --fs-2xs label in --text-3; the active one has an accent semibold label and its icon at
    --stroke-strong (icons "leaf.nav.<key>" / "leaf.nav.<key>.on").

    LeafNav:new{ width = px, active = "library", on_select = function(key) end }
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local LeafNav = InputContainer:extend{ width = nil, active = nil, on_select = nil }

LeafNav.ITEMS = {
    { key = "home", label = _("Home") },
    { key = "library", label = _("Library") },
    { key = "history", label = _("History") },
    { key = "settings", label = _("Settings") },
}

function LeafNav.height()
    return require("leaf/core").T.px("h-nav")
end

function LeafNav:init()
    local L = require("leaf/core")
    local T = L.T
    local hair = T.px("hairline")
    local h = T.px("h-nav")
    local n = #LeafNav.ITEMS
    self.cell_w = math.floor(self.width / n)
    local s = T.px("icon-md")
    local row = HorizontalGroup:new{ align = "center" }
    for i, it in ipairs(LeafNav.ITEMS) do
        local on = it.key == self.active
        local w = i == n and self.width - (n - 1) * self.cell_w or self.cell_w
        table.insert(row, CenterContainer:new{ dimen = Geom:new{ w = w, h = h - hair },
            VerticalGroup:new{ align = "center",
                IconWidget:new{ icon = "leaf.nav." .. it.key .. (on and ".on" or ""), width = s, height = s, alpha = true },
                VerticalSpan:new{ width = T.px("sp-half") + 1 }, -- .ko-nav gap: 3px
                TextWidget:new{ text = it.label, face = L.face(on and "ui-semibold" or "ui", "fs-2xs"),
                    fgcolor = T.color(on and "accent" or "text-3"), padding = 0 } } })
    end
    self[1] = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg-raised"),
        VerticalGroup:new{
            LineWidget:new{ dimen = Geom:new{ w = self.width, h = hair }, background = T.color("border") },
            row } }
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = h }
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
end

function LeafNav:getSize()
    return self.dimen
end

function LeafNav:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    InputContainer.paintTo(self, bb, x, y)
end

function LeafNav:onTap(_, ges)
    if not (ges and ges.pos) then return true end
    local i = math.floor((ges.pos.x - self.dimen.x) / self.cell_w) + 1
    i = math.max(1, math.min(#LeafNav.ITEMS, i))
    local key = LeafNav.ITEMS[i].key
    if self.on_select then self.on_select(key) end
    return true
end

return LeafNav
