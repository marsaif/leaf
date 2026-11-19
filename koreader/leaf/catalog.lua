--[[
    Leaf test card: the prototype's #/catalog (Tokens + Controls pages) rebuilt from real KOReader
    widgets with the Leaf styling applied, to compare side by side with the HTML spec.
    Open it with the sandbox screenshot scene "catalog", or from Lua: require("leaf/catalog").show()
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local RadioMark = require("ui/widget/radiomark")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local Catalog = InputContainer:extend{}

function Catalog:init()
    local L = require("leaf/core")
    local T = L.T
    assert(L.face, "Leaf is not loaded (disabled, or the fonts module failed)")
    local W = Screen:getWidth()
    local side = T.px("sp-5")
    local inner = W - 2 * side

    local function text(s, role, size, color)
        return TextWidget:new{ text = s, face = L.face(role or "ui", size or "fs-md"), fgcolor = color and T.color(color) or nil }
    end
    local function label(s)  -- .ko-section-label
        return VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = T.px("sp-5") },
            text(s:upper(), "ui-semibold", "fs-xs", "text-3"),
            VerticalSpan:new{ width = T.px("sp-2") } }
    end
    local function row(items, gap)
        local g = HorizontalGroup:new{ align = "center" }
        for i, it in ipairs(items) do
            if i > 1 then table.insert(g, HorizontalSpan:new{ width = gap or T.px("sp-3") }) end
            table.insert(g, it)
        end
        return g
    end
    local function swatch(name)
        return VerticalGroup:new{ align = "left",
            FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"), padding = 0,
                -- a filled block (FrameContainer only draws its first child)
                LineWidget:new{ dimen = Geom:new{ w = T.px("h-row") * 2, h = T.px("h-chip") }, background = T.color(name) } },
            text("--" .. name, "ui", "fs-2xs", "text-3") }
    end
    local function button(lbl, kind, enabled)
        return Button:new{ text = lbl, _leaf_kind = kind, enabled = enabled ~= false, bordersize = 0,
            padding_h = T.px("sp-4"), height = T.px("h-control") - 2 * require("ui/size").padding.button,
            callback = function() end, show_parent = self }
    end
    local function progress(pct, h)
        return ProgressWidget:new{ width = math.floor(inner / 3) - T.px("sp-3"), height = T.px(h), percentage = pct / 100 }
    end

    local colors = { "bg", "surface", "surface-2", "surface-3", "border", "border-strong",
        "text", "text-2", "text-3", "disabled", "accent", "danger" }
    local swatch_rows = {}
    for i = 1, #colors, 4 do
        table.insert(swatch_rows, row({ swatch(colors[i]), swatch(colors[i + 1]), swatch(colors[i + 2]), swatch(colors[i + 3]) }))
        table.insert(swatch_rows, VerticalSpan:new{ width = T.px("sp-2") })
    end

    local body = VerticalGroup:new{ align = "left",
        label("Type scale"),
        text("Top-level title · display 26", "display-semibold", "fs-display"),
        text("Sheet / dialog title · head 17", "ui-semibold", "fs-head"),
        text("Row and body UI · md 15", "ui", "fs-md"),
        text("Metadata and secondary · sm 13", "ui", "fs-sm", "text-2"),
        text("Caption · xs 11", "ui", "fs-xs", "text-3"),
        text("Book text in panels · Literata 15", "book", "fs-md"),
        label("Colour · paper (e-ink greys)"),
        VerticalGroup:new(swatch_rows),
        label("Buttons · 40px in every variant"),
        row({ button("Primary", "primary"), button("Secondary", "secondary"), button("Ghost", "ghost"), button("Delete", "danger") }),
        VerticalSpan:new{ width = T.px("sp-2") },
        row({ button("Save", "primary", false), button("Close", "secondary", false) }),
        label("Check · radio"),
        row({ CheckMark:new{ checked = false }, CheckMark:new{ checked = true }, CheckMark:new{ checked = true, enabled = false },
            HorizontalSpan:new{ width = T.px("sp-4") },
            RadioMark:new{ checked = false }, RadioMark:new{ checked = true }, RadioMark:new{ checked = true, enabled = false } }),
        label("Progress · thin 2 · default 3 · md 4"),
        row({ progress(35, "bw-lg"), progress(62, "bw-xl"), progress(80, "sp-1") }),
        label("Separator · hairline"),
        LineWidget:new{ dimen = Geom:new{ w = inner, h = T.px("hairline") }, background = Blitbuffer.COLOR_BLACK },
    }

    local title = TitleBar:new{
        width = W, title = "Leaf · design system", subtitle = "KOReader widgets with the Leaf styling",
        with_bottom_line = true, close_callback = function() UIManager:close(self) end, show_parent = self,
    }
    self[1] = FrameContainer:new{
        width = W, height = Screen:getHeight(), bordersize = 0, padding = 0, background = T.color("surface"),
        VerticalGroup:new{ align = "left", title,
            FrameContainer:new{ bordersize = 0, padding = 0, padding_left = side, padding_right = side, body } },
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = Screen:getHeight() }
end

local M = {}
function M.show()
    UIManager:show(Catalog:new{ covers_fullscreen = true })
end
return M
