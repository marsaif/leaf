--[[
    Leaf confirm dialogs (safety-net items 10, 11): ConfirmBox (154 call sites), MultiConfirmBox (24).
    Target: prototype overlay "confirm" (UI.dialog).

    * No decorative icon. The message is split like UI.dialog: first line = title (Inter SemiBold
      --fs-head), the rest = body (--fs-md, --text-2). A short one-line message is a title only;
      a long one is body only.
    * Destructive confirms (ok text Delete/Remove/Erase/Reset/Purge) get a trash icon before the title.
    * Leaf dialog width (min(86%, 400px)), --sp-5 padding, Leaf action row (Cancel ghost, OK primary /
      danger) from buttons.lua.
    Same fields and behaviour as KOReader's: text_group (added widgets last), text_widget_width,
    movable, ok/cancel/other buttons, keep_dialog_open, no_ok_button, dismissal, addWidget().
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local M = {}

local DANGER = { delete = true, remove = true, erase = true, reset = true, purge = true }

--- "Title\nbody" -> title, body (either may be nil)
local function split(text)
    text = tostring(text or "")
    local first, rest = text:match("^([^\n]+)\n+(.+)$")
    if first and #first <= 90 then return first, rest end
    if not text:find("\n") and #text <= 70 then return text, nil end
    return nil, text
end

function M.apply(L)
    local T = L.T
    local ButtonTable = require("ui/widget/buttontable")

    local function dialog_width()
        return math.min(math.floor(Screen:getWidth() * 0.86), Screen:scaleBySize(400 * T.scale))
    end

    local function dismiss_events(self)
        if not self.dismissable then return end
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } },
            }
        end
        if Device:hasKeys() then
            self.key_events.Close = { { Device.input.group.Back } }
        end
    end

    --- title / body group in the inner width; returns the VerticalGroup
    local function head(text, inner, danger)
        local title, body = split(text)
        local g = VerticalGroup:new{ align = "left" }
        if title then
            local tw = inner
            local row = HorizontalGroup:new{ align = "center" }
            if danger then
                local s = T.px("icon-tile")
                table.insert(row, IconWidget:new{ icon = "leaf.trash", width = s, height = s, alpha = true })
                table.insert(row, HorizontalSpan:new{ width = T.px("sp-2") })
                tw = tw - s - T.px("sp-2")
            end
            table.insert(row, TextBoxWidget:new{ text = title, face = L.face("ui-semibold", "fs-head"), width = tw })
            table.insert(g, row)
        end
        if body then
            if title then table.insert(g, VerticalSpan:new{ width = T.px("sp-1h") }) end
            table.insert(g, TextBoxWidget:new{ text = body, face = L.face("ui", "fs-md"), fgcolor = T.color("text-2"), width = inner })
        end
        return g
    end

    -- shared with feedback.lua (the info dialog uses the same title / body split)
    M.head = head
    M.dialog_width = dialog_width

    local function frame(content, button_table)
        return FrameContainer:new{
            background = T.color("surface"), radius = Size.radius.window,
            padding = T.px("sp-5"), padding_bottom = 0,
            VerticalGroup:new{ align = "left", content, VerticalSpan:new{ width = T.px("sp-4") }, button_table },
        }
    end

    ---------------------------------------------------------------- ConfirmBox
    local ConfirmBox = require("ui/widget/confirmbox")
    L.wrap(ConfirmBox, "init", function(orig, self)
        dismiss_events(self)
        local inner = dialog_width() - 2 * T.px("sp-5")
        self.text_widget_width = inner
        local word = (tostring(self.ok_text or ""):match("^%s*([%a]+)") or ""):lower()
        self.text_group = VerticalGroup:new{ align = "left", head(self.text, inner, DANGER[word]) }
        if self._added_widgets then
            table.insert(self.text_group, VerticalSpan:new{ width = T.px("sp-3") })
            for _, widget in ipairs(self._added_widgets) do table.insert(self.text_group, widget) end
        end

        local buttons = { {
            { text = self.cancel_text, callback = function()
                self.cancel_callback()
                UIManager:close(self)
            end },
            { text = self.ok_text, callback = function()
                self.ok_callback()
                if self.keep_dialog_open then return end
                UIManager:close(self)
            end },
        } }
        if self.no_ok_button then table.remove(buttons[1], 2) end
        if self.other_buttons then
            local rownum = self.other_buttons_first and 0 or 1
            for i, buttons_row in ipairs(self.other_buttons) do
                local row = {}
                for _, button in ipairs(buttons_row) do
                    table.insert(row, { text = button.text, callback = function()
                        if button.callback then button.callback() end
                        if self.keep_dialog_open then return end
                        UIManager:close(self)
                    end })
                end
                table.insert(buttons, rownum + i, row)
            end
        end
        local button_table = ButtonTable:new{ width = inner, buttons = buttons, zero_sep = true, show_parent = self }
        self.movable = MovableContainer:new{ frame(self.text_group, button_table), unmovable = self.unmovable }
        self[1] = CenterContainer:new{ dimen = Screen:getSize(), self.movable }
    end, "ConfirmBox:init")

    ---------------------------------------------------------------- MultiConfirmBox
    local MultiConfirmBox = require("ui/widget/multiconfirmbox")
    L.wrap(MultiConfirmBox, "init", function(orig, self)
        dismiss_events(self)
        local inner = dialog_width() - 2 * T.px("sp-5")
        local button_table = ButtonTable:new{
            width = inner, zero_sep = true, show_parent = self,
            buttons = { {
                { text = self.cancel_text, callback = function()
                    self.cancel_callback()
                    UIManager:close(self)
                end },
                { text = self.choice1_text, text_func = self.choice1_text_func, enabled = self.choice1_enabled,
                  callback = function()
                    self.choice1_callback()
                    UIManager:close(self)
                end },
                { text = self.choice2_text, text_func = self.choice2_text_func, enabled = self.choice2_enabled,
                  callback = function()
                    self.choice2_callback()
                    UIManager:close(self)
                end },
            } },
        }
        self.movable = MovableContainer:new{ frame(head(self.text, inner, false), button_table) }
        self[1] = CenterContainer:new{ dimen = Screen:getSize(), self.movable } -- self[1][1] = MovableContainer, as KOReader's
    end, "MultiConfirmBox:init")
end

return M
