--[[
    Leaf controls (safety-net items 22, 23): check marks, radio marks, progress bars.

    * CheckMark / RadioMark: KOReader draws text glyphs (▢ ✓ / ◯ ◉). Leaf draws .ko-check / .ko-radio:
      20px (--icon-md) marks from koreader/icons/leaf.{check,radio}.{on,off}.svg (generated from
      the tokens by tools/build-icons.py) followed by an --sp-2 gap. Disabled marks are dimmed.
      Size and baseline stay what the callers expect (they align the mark with the row text).
    * ProgressWidget: .ko-progress: --surface-3 track, accent fill, --r-thumb corners, no border,
      no inset. Callers keep their own height; the ones that ask for black fill / square corners
      keep them.
--]]
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")

local M = {}

local function mark(L, kind, self)
    local T = L.T
    local s = T.px("icon-md")
    local icon = IconWidget:new{
        icon = string.format("leaf.%s.%s", kind, self.checked and "on" or "off"),
        width = s,
        height = s,
        dim = not self.enabled,
        alpha = true,
    }
    local gap = T.px("sp-2")
    self[1] = HorizontalGroup:new{ align = "center", icon, HorizontalSpan:new{ width = gap } }
    -- keep the text baseline the caller aligns with, but never above the mark's own bottom
    self.baseline = math.max(self.baseline or 0, math.floor(s * 0.85))
    self.dimen = Geom:new{ x = 0, y = 0, w = s + gap, h = math.max(s, self.dimen and self.dimen.h or 0) }
end

function M.apply(L)
    local T = L.T
    for kind, mod in pairs({ check = "ui/widget/checkmark", radio = "ui/widget/radiomark" }) do
        local Class = require(mod)
        L.wrap(Class, "init", function(orig, self)
            orig(self)
            if self.checkable then mark(L, kind, self) end
        end, mod .. ":init")
    end

    local ProgressWidget = require("ui/widget/progresswidget")
    ProgressWidget.bordersize = 0
    ProgressWidget.margin_h = 0
    ProgressWidget.margin_v = 0
    ProgressWidget.radius = T.px("r-thumb")
    ProgressWidget.bgcolor = T.color("surface-3")
    ProgressWidget.fillcolor = T.color("accent")
    ProgressWidget.bordercolor = T.color("border")
end

return M
