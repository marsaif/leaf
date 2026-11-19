--[[
    Leaf sheets and popovers (safety-net item 12): ButtonDialog, the "grid of grey buttons" behind
    long-press menus, the quick menu, external links, filters and ~85 other places.

    * Not anchored -> bottom sheet (.ko-sheet): grip, head (title --fs-head + close on the right,
      .ko-sheet-head), then the buttons. A table of plain text buttons (at most 3 per row) becomes
      one full-width row per button (.ko-row: 48px, label left, --text; Delete/Remove... in --danger).
      Tables with icons or wider rows keep their grid inside the sheet. The sheet sits on the bottom
      edge with --r-xl top corners, --bg-raised, a --border-strong hairline.
    * Anchored (opened from a button / a text selection) -> popover look (.ko-popover: --r-lg,
      --surface, --border-strong hairline), keeping its grid and its position. The text-selection
      popup gets its own port with the reader (prototype "hl-popup").
    KOReader still builds the dialog (ids, focus, scrolling for long lists, callbacks).
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local M = {}

local DANGER = { delete = true, remove = true, erase = true, reset = true, purge = true }

-- the sheet's grip: a 36x4 rounded bar in --border-strong
local Grip = Widget:extend{}
function Grip:init()
    local T = require("leaf/core").T
    self.T = T
    self.dimen = Geom:new{ w = Screen:scaleBySize(36 * T.scale), h = T.px("sp-1") }
end
function Grip:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, self.T.color("border-strong"), math.floor(self.dimen.h / 2))
end

-- rows of plain text buttons (<= 3 per row) -> one button per row; nil if the table should stay a grid
local function flatten(rows)
    local out = {}
    for _, row in ipairs(rows or {}) do
        if #row > 3 then return nil end
        for _, e in ipairs(row) do
            if e.icon or not (e.text or e.text_func) then return nil end
            table.insert(out, { e })
        end
    end
    return #out > 0 and out or nil
end

function M.apply(L)
    local T = L.T
    local ButtonDialog = require("ui/widget/buttondialog")
    local IconButton = require("ui/widget/iconbutton")

    L.wrap(ButtonDialog, "init", function(orig, self)
        ------------------------------------------------ anchored: popover look, same layout
        if self.anchor then
            orig(self)
            local frame = self.movable[1]
            frame.radius = T.px("r-lg")
            frame.background = T.color("surface")
            frame.color = T.color("border-strong")
            return
        end

        ------------------------------------------------ bottom sheet
        if not self._leaf_rows then
            self._leaf_rows = flatten(self.buttons) or false
            if self._leaf_rows then self.buttons = self._leaf_rows end
        end
        local W = Screen:getWidth()
        self.width = W
        self.shrink_unneeded_width = false
        orig(self)

        local pad = T.px("sp-5")
        if self._leaf_rows then
            for _, row in ipairs(self.buttontable.buttons_layout) do
                for _, b in ipairs(row) do
                    local word = (tostring(b.text or ""):match("^%s*([%a]+)") or ""):lower()
                    b._leaf_kind = DANGER[word] and "row-danger" or "row"
                    b.align = "left"
                    b.padding_h = pad
                    b:free()
                    b:init()
                end
            end
        end

        local inner = W - 2 * T.px("hairline") -- inside the sheet's border
        local frame = self.movable[1]
        local old = frame[1] -- VerticalGroup{ title_group, separator, buttons }
        local buttons = old[3] or old[#old]
        local body = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = Geom:new{ w = inner, h = T.px("sp-1") }, Grip:new{} },
            VerticalSpan:new{ width = T.px("sp-1") },
        }
        if self.title and not self._added_widgets then
            local close = IconButton:new{
                icon = "close", width = T.px("icon-md"), height = T.px("icon-md"),
                padding = math.floor((T.px("hit") - T.px("icon-md")) / 2),
                callback = function() self:onClose() end, show_parent = self,
            }
            local cw = close:getSize().w
            local title = TextBoxWidget:new{
                text = self.title, face = L.face("ui-semibold", "fs-head"),
                width = inner - pad - cw - T.px("sp-3"),
            }
            local hh = math.max(T.px("h-header"), title:getSize().h + 2 * T.px("sp-2"))
            table.insert(body, HorizontalGroup:new{ align = "center",
                LeftContainer:new{ dimen = Geom:new{ w = inner - cw, h = hh },
                    HorizontalGroup:new{ align = "center", require("ui/widget/horizontalspan"):new{ width = pad }, title } },
                close,
            })
            table.insert(body, LineWidget:new{ dimen = Geom:new{ w = inner, h = T.px("hairline") }, background = T.color("border") })
        elseif old[1] then
            table.insert(body, old[1]) -- added widgets (check boxes...) stay under the grip
            if old[2] then table.insert(body, old[2]) end
        end
        table.insert(body, buttons)

        -- extend below the screen by the corner radius, so only the top corners show
        local r = T.px("r-xl")
        frame[1] = body
        frame.radius = r
        frame.padding = 0
        frame.padding_bottom = r
        frame.bordersize = T.px("hairline")
        frame.color = T.color("border-strong")
        frame.background = T.color("bg-raised")
        self.movable.unmovable = true
        self[1] = BottomContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = W, h = Screen:getHeight() + r },
            self.movable,
        }
    end, "ButtonDialog:init")
end

return M
