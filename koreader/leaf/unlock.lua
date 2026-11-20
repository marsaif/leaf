--[[
    Leaf sleep-screen lock prompt (Gaps › unlock): KOReader's ScreenSaverLockWidget message.

    When the sleep screen waits for a gesture, KOReader paints an InfoMessage box over it
    ("Waiting for specific gesture to exit screensaver." / "No exit screensaver gesture configured.
    Tap to exit."). Leaf paints a small floating pill instead (.ko-popover.gp-float.gp-unlock:
    --surface, hairline --border-strong, --r-lg, --sp-2 --sp-4 padding, centred at 44% of the
    height): an icon and "Swipe up to unlock" (named from the configured gesture), the user's
    own exit message when there is one, or "Tap anywhere to wake" when no gesture is set.
    Same setting (screensaver_show_exit_message), same painting straight to the screen.
--]]
local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

-- the configured exit gesture -> words + icon
local function gesture_words(ui)
    local name
    pcall(function()
        for gesture, actions in pairs(ui.gestures.gestures) do
            if actions["exit_screensaver"] then name = gesture break end
        end
    end)
    if not name then return _("Use your unlock gesture"), "leaf.gw.pointer" end
    local dirs = { { "north", _("Swipe up to unlock"), "leaf.gw.chevrons-up" }, { "south", _("Swipe down to unlock"), "leaf.gw.chevrons-down" },
        { "east", _("Swipe right to unlock"), "leaf.gw.chevron-right" }, { "west", _("Swipe left to unlock"), "leaf.gw.arrow-left" } }
    for _i, d in ipairs(dirs) do
        if name:find(d[1], 1, true) then return d[2], d[3] end
    end
    if name:find("hold", 1, true) then return _("Long-press to unlock"), "leaf.gw.pointer" end
    if name:find("tap", 1, true) then return _("Tap to unlock"), "leaf.gw.pointer" end
    return _("Use your unlock gesture"), "leaf.gw.pointer"
end

function M.apply(L)
    local T = L.T
    local GW = require("leaf/widgets/gwkit")(L)
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")

    function M.pill(text, icon)
        return FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border-strong"), background = T.color("surface"),
            radius = T.px("r-lg"), margin = 0, padding = T.px("sp-2"), padding_left = T.px("sp-4"), padding_right = T.px("sp-4"),
            HorizontalGroup:new{ align = "center", GW.icon(icon, "icon-md", "text"), GW.hspan("sp-2"),
                GW.text(text, "ui-medium", "fs-sm", "text", Screen:getWidth() * 0.8) } }
    end

    L.wrap(ScreenSaverLockWidget, "showWaitForGestureMessage", function(orig, self)
        if G_reader_settings:has("screensaver_show_exit_message") then return end -- false
        local text, icon
        if self.has_exit_screensaver_gesture then
            text = G_reader_settings:readSetting("screensaver_exit_message")
            text = text and self.ui and self.ui.bookinfo and self.ui.bookinfo:expandString(text) or text
            if text then icon = "leaf.gw.chevrons-up" else text, icon = gesture_words(self.ui) end
        else
            text, icon = _("Tap anywhere to wake"), "leaf.gw.pointer"
        end
        local pill = M.pill(text, icon)
        local sz = pill:getSize()
        local x = math.floor((Screen:getWidth() - sz.w) / 2)
        local y = math.floor(Screen:getHeight() * 0.44)
        pill:paintTo(Screen.bb, x, y)
        UIManager:setDirty(nil, "ui", GW.geom(Screen:getWidth(), Screen:getHeight()))
        UIManager:forceRePaint()
        pill:free()
        self.is_infomessage_visible = true
    end, "ScreenSaverLockWidget:showWaitForGestureMessage")
end

return M
