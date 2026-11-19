--[[
    Leaf feedback (safety-net items 8, 9): Notification and InfoMessage.

    * Toast (.ko-toast): a --text pill with --bg text at --fs-sm, centred, 64px above the bottom
      edge; several toasts stack upwards. Two-line toasts get --r-lg corners instead of a pill.
    * Notification (113 call sites) is always a toast.
    * InfoMessage (395 call sites), following the coverage rule:
      - with a timeout, no image, no fixed height and at most two lines -> toast (it is the
        result of something that already happened);
      - otherwise -> the Leaf info dialog: no decorative icon (a real image is kept), body text
        --fs-md, --sp-5 padding, and an OK button (primary, right) when it can be dismissed.
      KOReader still builds the widget first, so timeout, tap-anywhere-to-dismiss, show_delay,
      dismiss_callback and the font shrinking for long texts behave exactly as before.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local MovableContainer = require("ui/widget/container/movablecontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local _ = require("gettext")

    local function toast_frame(text, max_lines)
        local max_w = math.floor(Screen:getWidth() * 0.86) - 2 * T.px("sp-4")
        local tb = TextBoxWidget:new{
            text = text, face = L.face("ui", "fs-sm"), fgcolor = T.color("bg"),
            width = max_w, alignment = "center",
        }
        -- shrink the box to the text when it fits on one line
        local line_h = tb:getLineHeight()
        local lines = math.floor(tb:getSize().h / line_h + 0.5)
        if max_lines and lines > max_lines then
            tb:free()
            return nil
        end
        if lines <= 1 then
            local TextWidget = require("ui/widget/textwidget")
            local one = TextWidget:new{ text = text, face = L.face("ui", "fs-sm"), fgcolor = T.color("bg") }
            if one:getSize().w <= max_w then
                tb:free()
                tb = one
            else
                one:free()
            end
        end
        local pv, ph = T.px("sp-2h"), T.px("sp-4")
        local h = tb:getSize().h + 2 * pv
        return FrameContainer:new{
            background = T.color("text"), bordersize = 0,
            radius = lines <= 1 and math.floor(h / 2) or T.px("r-lg"),
            padding = 0, padding_top = pv, padding_bottom = pv, padding_left = ph, padding_right = ph,
            tb,
        }
    end

    local function at_bottom(widget, stack_index, height)
        local offset = Screen:scaleBySize(64 * T.scale) + (stack_index - 1) * (height + T.px("sp-2"))
        return BottomContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() - offset },
            widget,
        }
    end

    ---------------------------------------------------------------- Notification -> toast
    local Notification = require("ui/widget/notification")
    L.wrap(Notification, "init", function(orig, self)
        orig(self) -- keeps KOReader's stacking bookkeeping (_shown_list / _shown_idx)
        local frame = toast_frame(self.text)
        self.frame = frame
        self[1] = at_bottom(frame, self._shown_idx or 1, frame:getSize().h)
    end, "Notification:init")

    ---------------------------------------------------------------- InfoMessage
    local InfoMessage = require("ui/widget/infomessage")
    local Button = require("ui/widget/button")
    L.wrap(InfoMessage, "init", function(orig, self)
        -- toast: a short, timed result
        if self.timeout and not self.image and not self.height and not self._leaf_dialog then
            orig(self) -- events, timeout, shrinking: all KOReader's
            local frame = toast_frame(self.text, 2)
            if frame then
                self.movable = MovableContainer:new{ frame, unmovable = true }
                self[1] = at_bottom(self.movable, 1, frame:getSize().h)
                return
            end
            self._leaf_dialog = true -- too long for a toast: fall through to the dialog
        end

        -- info dialog
        if not self.image then self.show_icon = false end
        if not self.face then
            self.face = self.monospace_font and require("ui/font"):getFace("infont") or L.face("ui", "fs-md")
        end
        orig(self)
        local frame = self.movable and self.movable[1]
        -- InfoMessage re-runs init() from inside init() to shrink long texts: restyle a frame once
        if not frame or frame._leaf_done then return end
        frame._leaf_done = true
        frame.padding = T.px("sp-5")
        frame.background = T.color("surface")
        if self.dismissable and not self.height then
            local content = frame[1]
            local w = content:getSize().w
            local ok = Button:new{
                text = _("OK"), _leaf_kind = "primary",
                height = T.px("h-control") - 2 * require("ui/size").padding.button,
                padding_h = T.px("sp-4"),
                callback = function() self:onTapClose() end, show_parent = self,
            }
            frame[1] = VerticalGroup:new{ align = "left",
                content,
                VerticalSpan:new{ width = T.px("sp-4") },
                RightContainer:new{ dimen = Geom:new{ w = math.max(w, ok:getSize().w), h = ok:getSize().h }, ok },
            }
        end
    end, "InfoMessage:init")
end

return M
