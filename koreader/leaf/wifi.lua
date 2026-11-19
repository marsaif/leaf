--[[
    Leaf Wi-Fi (prototype overlay "wifi"): KOReader's NetworkSetting (the scan result list) is a
    bottom sheet:
      head:      Wi-Fi + the connected network (or "Not connected") · rescan · ×
      first row: Wi-Fi on/off toggle (devices with a Wi-Fi toggle)
      card:      the connected network: accent round tile, name (--fs-lg semibold),
                 "✓ Connected · WPA2 · Good", Disconnect (secondary) · Forget (ghost)
      list:      AVAILABLE NETWORKS: signal icon in a round tile, name, "Saved · WPA2 · Good",
                 a lock for secured networks; pages (‹ 1 / 2 ›) when they don't fit.
    Taps do what KOReader's rows do (connect a saved network, ask for a password, WEP warning);
    hold a saved network = KOReader's edit dialog (password / Forget). The password dialog gets the
    network's security and signal under its title (prototype "Wi-Fi password").
    KOReader's NetworkItem objects are still built and do the connecting.
--]]
local Device = require("device")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

local function security(flags)
    flags = flags or ""
    if flags:find("SAE") then return "WPA3" end
    if flags:find("EAP") then return "WPA2-Enterprise" end
    if flags:find("WPA2") then return "WPA2" end
    if flags:find("WPA") then return "WPA" end
    if flags:find("WEP") then return "WEP" end
    return _("Open")
end
local function strength(q)
    q = q or 0
    if q > 66 then return _("Good") end
    if q > 33 then return _("Fair") end
    return _("Weak")
end
local function signal_icon(info)
    local q = info.signal_quality or 0
    local lvl = q > 80 and 100 or (q > 55 and 75 or (q > 30 and 50 or (q > 5 and 25 or 0)))
    return "wifi.open." .. lvl
end
M.security, M.strength = security, strength

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local NetworkSetting = require("ui/widget/networksetting")
    local NetworkMgr = require("ui/network/manager")

    local NetworkItem
    local i = 1
    while true do
        local name, value = debug.getupvalue(NetworkSetting.init, i)
        if not name then break end
        if name == "NetworkItem" then NetworkItem = value break end
        i = i + 1
    end

    local function build(self)
        local W = Screen:getWidth()
        local inner = W - 2 * T.px("hairline")
        local items = self._leaf_items or {}
        local connected = self:getConnectedItem()
        local close = function() UIManager:close(self) end

        local content = VerticalGroup:new{ align = "left" }
        local actions = {}
        if NetworkMgr.reconnectOrShowNetworkMenu then
            table.insert(actions, { "leaf.sys.refresh", function()
                local cb = self.connect_callback
                UIManager:close(self)
                UIManager:nextTick(function() NetworkMgr:reconnectOrShowNetworkMenu(cb, true) end)
            end })
        end
        table.insert(content, K.sheet_head{ width = inner, title = _("Wi-Fi"), parent = self,
            sub = connected and connected.display_ssid or _("Not connected"), actions = actions, close = close })

        if Device:hasWifiToggle() then
            local Toggle = require("leaf/widgets/toggle")
            table.insert(content, K.row{ width = inner, icon = "leaf.sys.wifi", label = _("Wi-Fi"),
                trailing = Toggle:new{ on = true },
                callback = function()
                    UIManager:close(self)
                    NetworkMgr:toggleWifiOff(nil, true)
                end })
            table.insert(content, K.line(inner))
        end

        local pad = T.px("sp-4")
        if connected then
            local info = connected.info
            local cw = inner - 2 * pad
            local iw = K.inner(cw)
            -- .wf-cur tile: a filled accent circle, the icon in --accent-ink
            local ts = T.px("h-row")
            local tile = require("ui/widget/container/framecontainer"):new{
                bordersize = 0, background = T.color("accent"), radius = math.floor(ts / 2), padding = 0,
                require("ui/widget/container/centercontainer"):new{ dimen = K.geom(ts, ts),
                    require("ui/widget/iconwidget"):new{ icon = "leaf.sys.wifi.ink", width = T.px("icon-md"), height = T.px("icon-md"),
                        alpha = true } } }
            local tw = iw - tile:getSize().w - T.px("sp-3")
            local bits = { _("Connected"), security(info.flags), strength(info.signal_quality) }
            local card = K.card(cw, VerticalGroup:new{ align = "left",
                HorizontalGroup:new{ align = "center", tile, K.hspan("sp-3"),
                    VerticalGroup:new{ align = "left",
                        K.text(connected.display_ssid, "ui-semibold", "fs-lg", "text", tw),
                        K.vspan("sp-half"),
                        HorizontalGroup:new{ align = "center", K.icon("leaf.sys.check", "icon-xs"), K.hspan("sp-1"),
                            K.text(table.concat(bits, " · "), "ui", "fs-sm", "text-2", tw - T.px("icon-xs")) } } },
                K.vspan("sp-3"),
                (function()
                    -- natural-width buttons, left-aligned: Disconnect · Details · Forget
                    local g = HorizontalGroup:new{ align = "center",
                        K.button{ label = _("Disconnect"), kind = "secondary", parent = self,
                            callback = function() connected:disconnect() end } }
                    if NetworkMgr.isNetworkInfoAvailable and NetworkMgr:isNetworkInfoAvailable() then
                        table.insert(g, K.hspan("sp-2"))
                        table.insert(g, K.button{ label = _("Details"), kind = "secondary", parent = self,
                            callback = function()
                                UIManager:broadcastEvent(require("ui/event"):new("ShowNetworkInfo"))
                            end })
                    end
                    table.insert(g, K.hspan("sp-2"))
                    table.insert(g, K.button{ label = _("Forget"), kind = "ghost", parent = self,
                        callback = function()
                            NetworkMgr:deleteNetwork(info)
                            info.password = nil
                            connected:disconnect()
                        end })
                    return g
                end)(),
            })
            table.insert(content, K.vspan("sp-3"))
            table.insert(content, HorizontalGroup:new{ K.hspan(pad), card })
        end

        -- available networks, paged to fit 80% of the screen
        local others = {}
        for _j, it in ipairs(items) do if it ~= connected then table.insert(others, it) end end
        table.insert(content, K.vspan("sp-2"))
        table.insert(content, K.section(_("Available networks"), inner))
        local used = content:getSize().h
        content:resetLayout()
        local row_h = T.px("h-row") + T.px("sp-2h")
        local per_page = math.max(3, math.floor((Screen:getHeight() * 0.82 - used - T.px("h-row")) / row_h))
        local pages = math.max(1, math.ceil(#others / per_page))
        self._leaf_page = math.min(self._leaf_page or 1, pages)
        local first = (self._leaf_page - 1) * per_page + 1
        local rows = {}
        for k = first, math.min(#others, first + per_page - 1) do
            local it = others[k]
            local info = it.info
            local secured = (info.flags or ""):find("WPA") or (info.flags or ""):find("WEP")
            local sub = {}
            if info.password then table.insert(sub, _("Saved")) end
            table.insert(sub, security(info.flags))
            table.insert(sub, strength(info.signal_quality))
            table.insert(rows, K.row{ width = inner, height = row_h,
                tile = signal_icon(info), tile_opts = { icon = "icon-tile", size = "hit" },
                label = it.display_ssid, label_role = "ui-medium", sub = table.concat(sub, " · "),
                trailing = secured and K.icon("leaf.sys.lock", "icon-sm", true) or nil,
                callback = function()
                    if (info.flags or ""):find("WEP") then
                        UIManager:show(require("ui/widget/infomessage"):new{ text = _("Networks with WEP encryption are not supported.") })
                    elseif info.password then
                        it:connect()
                    else
                        it:onAddNetwork()
                    end
                end,
                hold = info.password and function() it:onEditNetwork() end or nil })
        end
        if #rows == 0 then
            table.insert(rows, K.row{ width = inner, icon = "leaf.sys.wifi.off", label = _("No other networks found"), dim = true })
        end
        -- separators start under the names (.ko-list rows with a tile)
        table.insert(content, K.list(rows, inner, { inset = T.px("sp-5") + T.px("hit") + T.px("sp-3"), inset_right = 0 }))
        if pages > 1 then
            local CenterContainer = require("ui/widget/container/centercontainer")
            table.insert(content, CenterContainer:new{ dimen = K.geom(inner, T.px("h-row")),
                HorizontalGroup:new{ align = "center",
                    K.icon_button("chevron.left", function()
                        self._leaf_page = math.max(1, self._leaf_page - 1) self:_leafRebuild() end, self),
                    K.text(T_(_("%1 of %2"), self._leaf_page, pages), "ui", "fs-sm", "text-2"),
                    K.icon_button("chevron.right", function()
                        self._leaf_page = math.min(pages, self._leaf_page + 1) self:_leafRebuild() end, self) } })
        end
        table.insert(content, K.vspan("sp-3"))

        local frame, bottom = K.sheet(content, W)
        self.popup = frame
        self[1] = bottom
    end

    function NetworkSetting:_leafRebuild()
        build(self)
        UIManager:setDirty("all", "ui")
    end

    NetworkSetting._leaf_wants_scrim = true
    L.wrap(NetworkSetting, "init", function(orig, self)
        orig(self)
        -- KOReader's rows (sorted by signal) are in its ListView
        local list = self.popup and self.popup[1] and self.popup[1][2]
        self._leaf_items = list and list.items or {}
        build(self)
    end, "NetworkSetting:init")

    if NetworkItem then
        L.wrap(NetworkItem, "refresh", function(orig, self)
            orig(self)
            local s = self.setting_ui
            if s and s._leaf_items then s:_leafRebuild() end
        end, "NetworkItem:refresh")

        -- password dialog: security and signal under the network name
        local InputDialog = require("ui/widget/inputdialog")
        for _k, method in ipairs({ "onAddNetwork", "onEditNetwork" }) do
            L.wrap(NetworkItem, method, function(orig, self)
                local info = self.info or {}
                local orig_new = InputDialog.new
                InputDialog.new = function(cls, o)
                    o = o or {}
                    o.description = o.description or (security(info.flags) .. " · " .. T_(_("%1 signal"), strength(info.signal_quality):lower()))
                    o.input_hint = _("Password")
                    return orig_new(cls, o)
                end
                local ok, ret = pcall(orig, self)
                InputDialog.new = orig_new
                if not ok then error(ret, 0) end
                return ret
            end, "NetworkItem:" .. method)
        end
    else
        L.err("wifi: NetworkItem not found, connecting won't refresh the sheet")
    end
end

return M
