--[[
    Leaf frontlight sheet (prototype overlay "frontlight", js/screens/dialogs.js):

      grip
      Frontlight                                   ×      (.ko-sheet-head; sub "62% brightness · 35% warmth" / "Off")
      ─────────────────────────────────────────────
      💡 Frontlight                            [on]
      Brightness   ☼ ───────●──────── ☀   62%          (slider rows, dimmed while the light is off)
      Warmth       ❄ ────●─────────── 🔥   35%          (devices with natural light only)
      ─────────────────────────────────────────────
      ◐ Night mode                            [off]
      🌇 Automatic warmth                      [on]       (when the Auto warmth plugin is loaded)
         Warmer from sunset to sunrise
      ⚙ Frontlight settings                     ›        (KOReader's own frontlight dialog: min/max,
                                                          natural light configuration, …)

    Device:showLightDialog() (sent by ShowFlDialog: the reader chrome's Light button, the menu's
    Frontlight entry, gestures) shows this sheet. Values go through PowerD exactly as KOReader's
    FrontLightWidget does (setIntensity / toggleFrontlight / setWarmth + updateResumeFrontlightState).
--]]
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local Kit = require("leaf/widgets/kit")

    local Light = InputContainer:extend{
        name = "FrontLightWidget", -- so code looking for KOReader's dialog finds this one
        is_always_active = true,
    }

    function Light:init()
        self.powerd = Device:getPowerDevice()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end

    -- brightness in % of the native range; warmth in KOReader's 0-100 scale
    function Light:values()
        local p = self.powerd
        local on = p:isFrontlightOn()
        local span = math.max(1, p.fl_max - p.fl_min)
        local cur = on and p:frontlightIntensity() or (p.fl_intensity or p.fl_min)
        local b = math.floor((cur - p.fl_min) / span * 100 + 0.5)
        local w
        if Device:hasNaturalLight() then w = p:frontlightWarmth() or 0 end
        return on, math.max(0, math.min(100, b)), w
    end

    function Light:setBrightnessPct(pct)
        local p = self.powerd
        local v = p.fl_min + math.floor(pct / 100 * (p.fl_max - p.fl_min) + 0.5)
        v = math.max(p.fl_min, math.min(p.fl_max, v))
        if v == p.fl_min then
            if p:isFrontlightOn() then p:turnOffFrontlight() end
        else
            p:setIntensity(v)
        end
        p:updateResumeFrontlightState()
    end

    function Light:setWarmthPct(pct)
        self.powerd:setWarmth(math.max(0, math.min(100, math.floor(pct + 0.5))))
    end

    local function autowarmth()
        local plugin = package.loaded["plugins/autowarmth.koplugin/main"] or package.loaded["autowarmth"]
        if plugin then return true end
        -- the plugin registers itself in the reader / file manager instance
        local ui = require("apps/reader/readerui").instance or require("apps/filemanager/filemanager").instance
        return ui and ui.autowarmth ~= nil
    end

    function Light:build()
        local W = Screen:getWidth()
        local inner = Kit.inner(W)
        local on, b, w = self:values()
        local sub = on and (w and T_(_("%1% brightness · %2% warmth"), b, w) or T_(_("%1% brightness"), b)) or _("Off")
        local g = VerticalGroup:new{ align = "left" }
        table.insert(g, Kit.head{ width = inner, title = _("Frontlight"), sub = sub, parent = self,
            on_close = function() self:onClose() end })
        table.insert(g, Kit.line(inner))
        table.insert(g, VerticalSpan:new{ width = T.px("sp-1") })
        table.insert(g, Kit.row{ width = inner, icon = "leaf.fl.bulb", label = _("Frontlight"), trailing = "toggle", on = on,
            callback = function()
                self.powerd:toggleFrontlight()
                self.powerd:updateResumeFrontlightState()
                self:refresh()
            end })
        local live_b, live_w
        local function slide(set, kind)
            return function(frac, final)
                local pct = math.floor(frac * 100 + 0.5)
                set(self, pct)
                local row = kind == "b" and live_b or live_w
                if final then self:refresh() else
                    local _on, nb, nw = self:values()
                    local v = kind == "b" and nb or nw
                    row:set(v / 100, v)
                    UIManager:setDirty(self, "ui", self._frame.dimen)
                end
            end
        end
        live_b = Kit.slider_row{ width = inner, label = _("Brightness"), pct = b / 100, value = b, unit = "%",
            min_icon = "leaf.fl.sundim", max_icon = "leaf.rd.light", enabled = on, parent = self,
            on_change = slide(Light.setBrightnessPct, "b"),
            on_step = function(dir)
                -- one native step (KOReader's −/+), or 10% on hold
                local p = self.powerd
                local _on, cb = self:values()
                if math.abs(dir) > 1 then
                    self:setBrightnessPct(cb + dir)
                else
                    local cur = p:frontlightIntensity()
                    local v = math.max(p.fl_min, math.min(p.fl_max, cur + dir))
                    if v == p.fl_min then p:turnOffFrontlight() else p:setIntensity(v) end
                    p:updateResumeFrontlightState()
                end
                self:refresh()
            end }
        table.insert(g, live_b)
        if w then
            live_w = Kit.slider_row{ width = inner, label = _("Warmth"), pct = w / 100, value = w, unit = "%",
                min_icon = "leaf.fl.snow", max_icon = "leaf.fl.flame", enabled = on, parent = self,
                on_change = slide(Light.setWarmthPct, "w"),
                on_step = function(dir)
                    local _on, _b, cw = self:values()
                    self:setWarmthPct(cw + dir)
                    self:refresh()
                end }
            table.insert(g, live_w)
        end
        table.insert(g, VerticalSpan:new{ width = T.px("sp-1") })
        table.insert(g, Kit.line(inner))
        table.insert(g, VerticalSpan:new{ width = T.px("sp-1") })
        table.insert(g, Kit.row{ width = inner, icon = "appbar.contrast", label = _("Night mode"), trailing = "toggle",
            on = G_reader_settings:isTrue("night_mode"),
            callback = function()
                UIManager:broadcastEvent(Event:new("ToggleNightMode"))
                self:refresh()
            end })
        table.insert(g, Kit.sep(inner))
        if autowarmth() then
            local act = G_reader_settings:readSetting("autowarmth_activate") or 0
            local auto_sub = ({
                [1] = _("Warmer from sunset to sunrise"),
                [2] = _("On a schedule"),
                [3] = _("Sun or schedule, closer to noon"),
                [4] = _("Sun or schedule, closer to midnight"),
            })[act] or _("Off")
            table.insert(g, Kit.row{ width = inner, icon = "leaf.fl.sunset",
                label = Device:hasNaturalLight() and _("Automatic warmth") or _("Automatic night mode"),
                sub = auto_sub, trailing = "toggle", on = act > 0,
                callback = function()
                    if act > 0 then
                        G_reader_settings:saveSetting("leaf_autowarmth_last", act)
                        UIManager:broadcastEvent(Event:new("AutoWarmthMode", 0))
                    else
                        UIManager:broadcastEvent(Event:new("AutoWarmthMode", G_reader_settings:readSetting("leaf_autowarmth_last") or 1))
                    end
                    self:refresh()
                end })
        end
        if autowarmth() then table.insert(g, Kit.sep(inner)) end
        table.insert(g, Kit.row{ width = inner, icon = "appbar.settings", label = _("Frontlight settings"), trailing = "chevron",
            callback = function()
                UIManager:close(self)
                M.show_stock()
            end })
        table.insert(g, VerticalSpan:new{ width = T.px("sp-3") })
        local frame, container = Kit.sheet{ content = g }
        self._frame = frame
        self[1] = container
    end

    function Light:refresh()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function Light:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then self:onClose() end
        return true
    end
    function Light:onClose()
        UIManager:close(self)
        return true
    end
    function Light:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function Light:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end

    M.Light = Light
    local orig_show = Device.showLightDialog
    function M.show_stock()
        orig_show(Device)
    end
    function M.show()
        UIManager:show(Light:new{})
    end

    -- Android shows its own system dialog: keep it there
    if not Device:isAndroid() then
        L.wrap(Device, "showLightDialog", function(orig, self)
            M.show()
        end, "Device:showLightDialog")
    end
end

return M
