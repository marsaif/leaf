--[[
    Leaf scrim (--scrim): modal dialogs and bottom sheets dim everything behind them, as in the
    prototype (.ko-scrim). A full-screen Scrim widget is shown just below the dialog in KOReader's
    window stack and closed with it. UIManager repaints every widget above a repainted one, so the
    scrim is re-applied whenever the screen behind changes, and never stacks up when only the
    dialog redraws.
    Night mode inverts the screen, so there the buffer is lightened instead (it shows darker).
    Toasts, anchored popovers and fullscreen editors get no scrim.
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local M = {}

local Scrim = Widget:extend{ name = "LeafScrim", alpha = 0.28 }
function Scrim:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
end
function Scrim:paintTo(bb)
    local w, h = Screen:getWidth(), Screen:getHeight()
    if Screen.night_mode then
        bb:lightenRect(0, 0, w, h, self.alpha)
    else
        bb:darkenRect(0, 0, w, h, self.alpha)
    end
end

local function is_a(obj, class)
    local mt = getmetatable(obj)
    while mt do
        if mt == class then return true end
        mt = getmetatable(mt)
    end
    return false
end

function M.apply(L)
    local T = L.T
    local UIManager = require("ui/uimanager")
    Scrim.alpha = T.colors.paper.scrim.alpha or 0.28

    local classes = {}
    for _, mod in ipairs({ "ui/widget/confirmbox", "ui/widget/multiconfirmbox", "ui/widget/inputdialog",
            "ui/widget/multiinputdialog", "ui/widget/spinwidget", "ui/widget/doublespinwidget",
            "ui/widget/datetimewidget", "ui/widget/infomessage", "ui/widget/buttondialog" }) do
        local ok, class = pcall(require, mod)
        if ok then classes[mod] = class end
    end
    local function wants_scrim(w)
        if type(w) ~= "table" or w._leaf_scrim ~= nil then return false end
        if w.fullscreen or w._leaf_toast or w.anchor or w.invisible then return false end
        for _, class in pairs(classes) do
            if is_a(w, class) then return true end
        end
        -- the top menu is shown inside a container: [1] is the TouchMenu
        local TouchMenu = package.loaded["ui/widget/touchmenu"]
        if TouchMenu and type(w[1]) == "table" and is_a(w[1], TouchMenu) then return true end
        return false
    end

    L.wrap(UIManager, "show", function(orig, self, widget, ...)
        if wants_scrim(widget) then
            local s = Scrim:new{}
            widget._leaf_scrim = s
            orig(self, s, "ui", s.dimen)
        end
        return orig(self, widget, ...)
    end, "UIManager:show")

    -- one refresh on close: drop the scrim from the stack first, let KOReader close the dialog
    -- (it repaints everything below), then refresh the whole screen once
    L.wrap(UIManager, "close", function(orig, self, widget, ...)
        local s = type(widget) == "table" and widget._leaf_scrim
        if s then
            for i = #self._window_stack, 1, -1 do
                if self._window_stack[i].widget == s then table.remove(self._window_stack, i) end
            end
            self._dirty[s] = nil
            widget._leaf_scrim = nil
        end
        local ret = orig(self, widget, ...)
        if s then
            self:setDirty(nil, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
        end
        return ret
    end, "UIManager:close")
end

return M
