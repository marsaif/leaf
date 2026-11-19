--[[
    Leaf system screens: sleep screen, About, quick settings (prototype overlays "sleep", "about",
    "quick").

    Sleep screen page (Menu › Settings › Screen › Sleep screen › "Choose sleep screen", the first
    entry Leaf adds to KOReader's sub-menu, whose other entries stay where they are):
      header ‹ Sleep screen · Preview (book cover only), a one-line explanation, then one card per
      KOReader wallpaper type (2 columns): preview art (the last book's cover, or an icon on
      --surface-2), radio + name + a human description; the selected card has an accent outline.
      "Custom image" / "Random image" ask for the file / folder (KOReader's choosers) when unset.
      OPTIONS: Show sleep message (toggle) · Sleep message (KOReader's editor).
    About (Menu › Help › About): a dialog card: app mark, KOReader + version · Leaf UI, a line about
    KOReader, Device / Screen / Build / Licence rows (.ko-kv), storage used with a bar, and
    "Check for updates" (KOReader's OTA menu, devices with OTA updates).
    Quick settings: a bottom sheet with 4x2 tiles (Wi-Fi, Frontlight, Night mode, Rotate, Statistics,
    Search, Screenshot, Sleep; accent when on) and Brightness / Warmth slider rows. KOReader has no
    quick-settings panel: it is a gesture / profile action ("Leaf: quick settings", event
    ShowLeafQuickSettings) and every tile sends KOReader's own event.
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local T_ = require("ffi/util").template
local lfs = require("libs/libkoreader-lfs")
local Screen = Device.screen

local M = {}

local function current_ui()
    local RUI = package.loaded["apps/reader/readerui"]
    local FM = package.loaded["apps/filemanager/filemanager"]
    return (RUI and RUI.instance) or (FM and FM.instance)
end

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local Toggle = require("leaf/widgets/toggle")

    ------------------------------------------------------------------ sleep screen page
    local function last_file()
        local f = G_reader_settings:readSetting("lastfile")
        return f and lfs.attributes(f, "mode") == "file" and f or nil
    end

    local function cover_widget(file, w, h)
        if not file then return end
        local widget
        pcall(function()
            local bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(nil, file)
            if bb then widget = require("ui/widget/imagewidget"):new{ image = bb, width = w, height = h, scale_factor = 0 } end
        end)
        return widget
    end

    local SleepPage = K.Page:extend{}

    function SleepPage:types()
        local ui = current_ui()
        local list = {
            { key = "cover", label = _("Book cover"), sub = _("The book you're reading"), icon = "leaf.sys.book", enabled = last_file() ~= nil },
            { key = "document_cover", label = _("Custom image"), sub = _("An image or a book's cover"), icon = "leaf.sys.image",
              choose = function() require("ui/screensaver").chooseFile() end, setting = "screensaver_document_cover" },
            { key = "random_image", label = _("Random image"), sub = _("From a folder of images"), icon = "leaf.sys.layers",
              choose = function() require("ui/screensaver").chooseFolder() end, setting = "screensaver_dir" },
            { key = "readingprogress", label = _("Reading progress"), sub = _("Your week in reading"), icon = "leaf.sys.chart",
              enabled = ui and ui.statistics ~= nil },
            { key = "bookstatus", label = _("Book status"), sub = _("Title, progress, rating"), icon = "leaf.sys.files", enabled = last_file() ~= nil },
            { key = "disable", label = _("Leave as is"), sub = _("The page stays on screen"), icon = "leaf.sys.moon" },
        }
        return list
    end

    function SleepPage:build()
        local W = Screen:getWidth()
        local pad = T.px("sp-4")
        local cur = G_reader_settings:readSetting("screensaver_type")
        local actions = {}
        if cur == "cover" and last_file() then
            local Button = require("ui/widget/button")
            local b = K.button{ label = _("Preview"), kind = "secondary", parent = self, callback = function() self:preview() end }
            actions = { { widget = HorizontalGroup:new{ b } } }
        end
        local header = K.header{ width = W, title = _("Sleep screen"), parent = self, back = function() self:onClose() end, actions = actions }
        local body = VerticalGroup:new{ align = "left", header,
            HorizontalGroup:new{ K.hspan("sp-5"), K.textbox(_("Shown while the device sleeps. E-ink keeps the image on screen without using power."),
                "ui", "fs-sm", "text-2", W - 2 * T.px("sp-5")) },
            K.vspan("sp-4"),
        }
        -- cards, two columns
        local gap = T.px("sp-3")
        local cols = 3
        local cw = math.floor((W - 2 * pad - (cols - 1) * gap) / cols)
        local art_w = K.inner(cw, { pad = "sp-3" })
        local art_h = math.floor(art_w * 1.1)
        local row
        for i, t in ipairs(self:types()) do
            local on = cur == t.key
            local enabled = t.enabled ~= false
            local art = t.key == "cover" and cover_widget(last_file(), math.floor(art_h * 0.56), math.floor(art_h * 0.84))
            local art_box = CenterContainer:new{ dimen = K.geom(art_w, art_h),
                art or K.icon(t.icon, "icon-xl", not enabled) }
            local Size = require("ui/size")
            local radio = K.icon(on and "leaf.radio.on" or "leaf.radio.off", "icon-md")
            local tw = art_w - T.px("icon-md") - T.px("sp-2")
            local card = K.card(cw, VerticalGroup:new{ align = "left",
                require("ui/widget/container/framecontainer"):new{ bordersize = 0, background = T.color("surface-2"),
                    radius = T.px("r-md"), padding = 0, art_box },
                K.vspan("sp-2"),
                HorizontalGroup:new{ align = "center", radio, K.hspan("sp-2"),
                    K.text(t.label, "ui-semibold", "fs-sm", enabled and "text" or "disabled", tw) },
                K.vspan("sp-1"),
                K.textbox(t.sub, "ui", "fs-xs", "text-3", art_w, "surface",
                    { height = Screen:scaleBySize(T.size["fs-xs"] * 2.9 * T.scale) }),
            }, { pad = "sp-3", on = on })
            local _unused = Size
            local tap = K.tap(card, enabled and function()
                G_reader_settings:saveSetting("screensaver_type", t.key)
                if t.choose and not G_reader_settings:readSetting(t.setting) then t.choose() end
                self:rebuild()
            end or nil, t.choose and function()
                G_reader_settings:saveSetting("screensaver_type", t.key)
                t.choose()
                self:rebuild()
            end or nil)
            if (i - 1) % cols == 0 then
                if row then table.insert(body, K.vspan(gap)) end
                row = HorizontalGroup:new{ align = "top", K.hspan(pad), tap }
                table.insert(body, row)
            else
                table.insert(row, K.hspan(gap))
                table.insert(row, tap)
            end
        end
        table.insert(body, K.vspan("sp-3"))
        table.insert(body, K.section(_("Options"), W))
        local show_msg = G_reader_settings:isTrue("screensaver_show_message")
        local cw2 = W - 2 * pad
        table.insert(body, HorizontalGroup:new{ K.hspan(pad), K.card(cw2, K.list({
            K.row{ width = K.inner(cw2, { flush = true }), pad = T.px("sp-4"), icon = "leaf.sys.quote", label = _("Show sleep message"),
                trailing = Toggle:new{ on = show_msg },
                callback = function() G_reader_settings:toggle("screensaver_show_message") self:rebuild() end },
            K.row{ width = K.inner(cw2, { flush = true }), pad = T.px("sp-4"), icon = "edit", label = _("Sleep message"),
                sub = G_reader_settings:readSetting("screensaver_message") or nil,
                trailing = K.icon("chevron.right", "icon-md", true),
                callback = function() require("ui/screensaver"):setMessage() end },
        }, K.inner(cw2, { flush = true }), { inset = T.px("sp-4") }), { flush = true }) })
        self:frame(body)
    end

    -- the cover as KOReader shows it (fit, page background), tap to return
    function SleepPage:preview()
        local file = last_file()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local img = cover_widget(file, W, H)
        if not img then return end
        local P = InputContainer:extend{ covers_fullscreen = true }
        local p
        p = P:new{
            dimen = K.geom(W, H),
            ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = K.geom(W, H) } } },
            onTapClose = function() UIManager:close(p) UIManager:setDirty(nil, "full") return true end,
            require("ui/widget/container/framecontainer"):new{ bordersize = 0, padding = 0, width = W, height = H,
                background = T.color(G_reader_settings:readSetting("screensaver_img_background") == "white" and "bg" or "text"),
                OverlapGroup:new{ dimen = K.geom(W, H),
                    CenterContainer:new{ dimen = K.geom(W, H), img },
                    CenterContainer:new{ dimen = K.geom(W, T.px("h-header") * 2),
                        require("ui/widget/container/framecontainer"):new{ bordersize = 0, background = T.color("text"),
                            radius = T.px("r-pill"), padding = T.px("sp-2"), padding_left = T.px("sp-4"), padding_right = T.px("sp-4"),
                            K.text(_("Preview · tap anywhere to return"), "ui-medium", "fs-sm", "bg") } } } },
        }
        UIManager:show(p, "full")
    end

    M.SleepPage = SleepPage
    function M.show_sleep() UIManager:show(SleepPage:new{}) end

    ------------------------------------------------------------------ About
    local About = InputContainer:extend{ _leaf_wants_scrim = true }
    function About:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local Version = require("version")
        local util = require("util")
        local dw = math.min(math.floor(W * 0.86), Screen:scaleBySize(400 * T.scale))
        local pad = T.px("sp-5")
        local iw = dw - 2 * pad
        -- app mark: accent rounded square, Playfair "K"
        local ms = T.px("h-control") + T.px("sp-2")
        local mark = require("ui/widget/container/framecontainer"):new{ bordersize = 0, background = T.color("accent"),
            radius = T.px("r-md"), padding = 0,
            CenterContainer:new{ dimen = K.geom(ms, ms), K.text("K", "display-semibold", "fs-glyph", "accent-ink") } }
        local ver = Version:getShortVersion() or ""
        local close = K.icon_button("close", function() UIManager:close(self) end, self)
        local head_w = iw - close:getSize().w - ms - T.px("sp-3")
        local head = OverlapGroup:new{ dimen = K.geom(iw, ms),
            HorizontalGroup:new{ align = "center", mark, K.hspan("sp-3"),
                VerticalGroup:new{ align = "left",
                    K.text("KOReader", "display-semibold", "fs-xl", "text", head_w),
                    K.text(T_("%1 · Leaf UI %2", ver, L.version or ""), "ui", "fs-sm", "text-3", head_w) } },
            require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(iw + T.px("sp-3"), ms), close },
        }
        -- device rows (.ko-kv)
        local function kv(k, v)
            local vw = K.text(v, "ui-medium", "fs-sm", "text", math.floor(iw * 0.62))
            local h = T.px("h-control")
            return OverlapGroup:new{ dimen = K.geom(K.inner(iw, { pad = "sp-3" }), h),
                require("ui/widget/container/leftcontainer"):new{ dimen = K.geom(K.inner(iw, { pad = "sp-3" }), h), K.text(k, "ui", "fs-sm", "text-2") },
                require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(K.inner(iw, { pad = "sp-3" }), h), vw } }
        end
        local rev = Version:getCurrentRevision() or ""
        local date = Version.getBuildDate and Version:getBuildDate() or 0
        local build = rev
        if date and date > 0 then
            local d = tostring(date)
            build = d:sub(1, 4) .. "-" .. d:sub(5, 6) .. "-" .. d:sub(7, 8)
        end
        local model = Device.model or "?"
        local ki = K.inner(iw, { pad = "sp-3" })
        local rows = {
            kv(_("Device"), model),
            kv(_("Screen"), T_("%1 × %2 · %3 ppi", Screen:getWidth(), Screen:getHeight(), Screen:getDPI())),
            kv(_("Build"), build),
            kv(_("Licence"), "AGPL-3.0"),
        }
        local kvcard = K.card(iw, K.list(rows, ki, { inset = 0 }), { pad = "sp-3", bg = "surface-2" })

        -- storage
        local storage = VerticalGroup:new{ align = "left" }
        local du = util.diskUsage(require("datastorage"):getDataDir())
        if du and du.total and du.used then
            local frac = du.total > 0 and du.used / du.total or 0
            local label = T_(_("%1 of %2 used"), util.getFriendlySize(du.used), util.getFriendlySize(du.total))
            local lw = K.text(label, "ui-medium", "fs-sm", "text")
            local bar_h = T.px("sp-2h")
            local used_w = math.max(T.px("sp-1"), math.floor(iw * frac))
            table.insert(storage, OverlapGroup:new{ dimen = K.geom(iw, T.px("h-badge")),
                HorizontalGroup:new{ align = "center", K.text(_("Storage"), "ui-semibold", "fs-sm", "text") },
                require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(iw, T.px("h-badge")), lw } })
            table.insert(storage, K.vspan("sp-2"))
            table.insert(storage, OverlapGroup:new{ dimen = K.geom(iw, bar_h),
                K.Rect:new{ w = iw, h = bar_h, color = T.color("surface-3"), radius = T.px("r-tick") },
                K.Rect:new{ w = used_w, h = bar_h, color = T.color("accent"), radius = T.px("r-tick") } })
            table.insert(storage, K.vspan("sp-1h"))
            table.insert(storage, K.text(T_(_("%1 free"), util.getFriendlySize(du.available or (du.total - du.used))), "ui", "fs-xs", "text-3"))
        end

        local col = VerticalGroup:new{ align = "left",
            head,
            K.vspan("sp-3"),
            K.textbox(_("A document viewer for E Ink devices. Free and open source, made by volunteers since 2012."),
                "ui", "fs-sm", "text-2", iw, "surface"),
            K.vspan("sp-3"),
            kvcard,
            K.vspan("sp-4"),
            storage,
        }
        if Device:hasOTAUpdates() then
            table.insert(col, K.vspan("sp-4"))
            table.insert(col, K.button{ label = _("Check for updates"), kind = "primary", width = iw, parent = self, callback = function()
                UIManager:close(self)
                local OTAManager = require("ui/otamanager")
                OTAManager:fetchAndProcessUpdate()
            end })
        end
        table.insert(col, K.vspan("sp-3"))
        table.insert(col, CenterContainer:new{ dimen = K.geom(iw, T.px("h-badge")),
            K.text("koreader.rocks · github.com/koreader", "ui", "fs-xs", "text-3") })
        self.card = require("ui/widget/container/framecontainer"):new{
            bordersize = T.px("hairline"), color = T.color("border-strong"), background = T.color("surface"),
            radius = T.px("r-xl"), padding = pad, col }
        self[1] = CenterContainer:new{ dimen = K.geom(W, H), self.card }
        self.dimen = K.geom(W, H)
        self.ges_events = { TapOut = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
    end
    function About:onTapOut(_a, ges)
        if self.card.dimen and ges.pos:notIntersectWith(self.card.dimen) then UIManager:close(self) end
        return true
    end
    function About:onClose() UIManager:close(self) return true end
    function About:onShow() UIManager:setDirty(self, "ui") return true end
    function About:onCloseWidget() UIManager:setDirty(nil, "ui") end
    M.About = About
    function M.show_about() UIManager:show(About:new{}) end

    ------------------------------------------------------------------ Quick settings
    local Quick = InputContainer:extend{ _leaf_wants_scrim = true }
    function Quick:init()
        self:build()
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
    end
    function Quick:send(name, ...)
        local ui = current_ui()
        if ui then ui:handleEvent(Event:new(name, ...)) end
    end
    function Quick:build()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local inner = W - 2 * T.px("hairline")
        local powerd = Device:getPowerDevice()
        local NetworkMgr = require("ui/network/manager")
        local ui = current_ui()
        local close = function() UIManager:close(self) end
        local function after_close(fn) return function() UIManager:close(self) UIManager:nextTick(fn) end end

        local sub = { (os.date("%A, %d %B"):gsub(" 0", " ")) }
        if Device:hasBattery() then
            local ok, cap = pcall(powerd.getCapacity, powerd)
            if ok and cap then table.insert(sub, cap .. "%") end
        end
        local content = VerticalGroup:new{ align = "left",
            K.sheet_head{ width = inner, title = _("Quick settings"), sub = table.concat(sub, " · "), parent = self, close = close,
                actions = { { "leaf.sys.settings", after_close(function()
                    if ui and ui.menu then ui.menu:onShowMenu() end
                end) } } },
        }

        local wifi_on = Device:hasWifiToggle() and NetworkMgr:isWifiOn()
        local fl_on = Device:hasFrontlight() and powerd:isFrontlightOn()
        local tiles = {
            { icon = wifi_on and "leaf.sys.wifi" or "leaf.sys.wifi.off", label = _("Wi-Fi"), on = wifi_on,
              sub = not Device:hasWifiToggle() and _("Not available") or (wifi_on and _("On") or _("Off")),
              enabled = Device:hasWifiToggle(),
              cb = after_close(function() self:send("ToggleWifi") end),
              hold = after_close(function() NetworkMgr:reconnectOrShowNetworkMenu(nil, true) end) },
            { icon = "leaf.sys.sun", label = _("Frontlight"), on = fl_on, enabled = Device:hasFrontlight(),
              sub = not Device:hasFrontlight() and _("Not available") or (fl_on and _("On") or _("Off")),
              cb = function() self:send("ToggleFrontlight") self:rebuild() end },
            { icon = "leaf.sys.moon", label = _("Night mode"), on = G_reader_settings:isTrue("night_mode"),
              sub = G_reader_settings:isTrue("night_mode") and _("On") or _("Off"),
              cb = function() self:send("ToggleNightMode") self:rebuild() end },
            { icon = "leaf.sys.rotate", label = _("Rotate"), sub = Screen:getScreenMode() == "landscape" and _("Landscape") or _("Portrait"),
              cb = after_close(function() self:send("SwapRotation") end) },
            { icon = "leaf.sys.chart", label = _("Statistics"), sub = _("This week"), enabled = ui and ui.statistics ~= nil,
              cb = after_close(function() ui.statistics:onShowReaderProgress() end) },
            { icon = "leaf.sys.search", label = _("Search"), sub = ui and ui.document and _("In this book") or _("Files"),
              cb = after_close(function()
                  if ui.document and ui.search then ui.search:onShowFulltextSearchInput()
                  elseif ui.filesearcher then ui.filesearcher:onShowFileSearch() end
              end) },
            { icon = "leaf.sys.camera", label = _("Screenshot"), sub = _("Capture"), enabled = ui and ui.screenshot ~= nil,
              cb = after_close(function() UIManager:scheduleIn(0.5, function() self:send("Screenshot") end) end) },
            { icon = "leaf.sys.sleep", label = _("Sleep"), sub = _("Now"), enabled = Device:canSuspend(),
              cb = after_close(function() self:send("RequestSuspend") end) },
        }
        local pad = T.px("sp-4")
        local gap = T.px("sp-2")
        local tw = math.floor((inner - 2 * pad - 3 * gap) / 4)
        local grid = VerticalGroup:new{ align = "left" }
        local row
        for i, t in ipairs(tiles) do
            local enabled = t.enabled ~= false
            local tin = K.inner(tw, { pad = "sp-3" })
            local tile = K.card(tw, VerticalGroup:new{ align = "left",
                K.tile(t.icon, { size = "h-control", icon = "icon-md", round = true, bg = t.on and "accent-soft" or "surface-2" }),
                K.vspan("sp-3"),
                K.text(t.label, "ui-semibold", "fs-sm", enabled and "text" or "disabled", tin),
                K.text(t.sub or "", "ui", "fs-xs", "text-3", tin) }, { pad = "sp-3", on = t.on, bg = t.on and "surface-2" or "surface" })
            local w = enabled and K.tap(tile, t.cb, t.hold) or tile
            if (i - 1) % 4 == 0 then
                if row then table.insert(grid, K.vspan(gap)) end
                row = HorizontalGroup:new{ align = "top", K.hspan(pad) }
                table.insert(grid, row)
            else
                table.insert(row, K.hspan(gap))
            end
            table.insert(row, w)
        end
        table.insert(content, K.vspan("sp-3"))
        table.insert(content, grid)

        -- light sliders (.ko-sr): label, slider, value
        if Device:hasFrontlight() then
            local LeafSlider = require("leaf/widgets/slider")
            local lab_w = math.floor(inner * 0.26)
            local val_w = math.floor(inner * 0.12)
            local sw = inner - 2 * T.px("sp-5") - lab_w - val_w - T.px("sp-2")
            local function slider_row(label, pct, set)
                local value = K.text(math.floor(pct * 100 + 0.5) .. "%", "ui", "fs-md", "text-2")
                local sl
                sl = LeafSlider:new{ width = sw, pct = pct, show_parent = self, on_change = function(frac, final)
                    sl:setPct(frac)
                    value:setText(math.floor(frac * 100 + 0.5) .. "%")
                    if final then set(frac) end
                    UIManager:setDirty(self, "ui")
                end }
                return HorizontalGroup:new{ align = "center", K.hspan("sp-5"),
                    require("ui/widget/container/leftcontainer"):new{ dimen = K.geom(lab_w, T.px("h-row")), K.text(label, "ui", "fs-md", "text") },
                    sl, K.hspan("sp-2"),
                    require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(val_w, T.px("h-row")), value } }
            end
            local fl_min, fl_max = powerd.fl_min or 0, powerd.fl_max or 100
            local cur = powerd:frontlightIntensity() or 0
            table.insert(content, K.vspan("sp-3"))
            table.insert(content, slider_row(_("Brightness"), (cur - fl_min) / math.max(1, fl_max - fl_min), function(frac)
                powerd:setIntensity(math.floor(fl_min + frac * (fl_max - fl_min) + 0.5))
            end))
            if Device:hasNaturalLight() then
                local wmax = powerd.fl_warmth_max or 100
                local wcur = powerd:frontlightWarmth() or 0
                table.insert(content, slider_row(_("Warmth"), wcur / math.max(1, wmax), function(frac)
                    powerd:setWarmth(math.floor(frac * wmax + 0.5))
                end))
            end
        end
        table.insert(content, K.vspan("sp-4"))
        local frame, bottom = K.sheet(content, W)
        self.sheet = frame
        self[1] = bottom
        self.dimen = K.geom(W, H)
        self.ges_events = { TapOut = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    function Quick:rebuild()
        self:build()
        UIManager:setDirty("all", "ui")
    end
    function Quick:onTapOut(_a, ges)
        if self.sheet.dimen and ges.pos:notIntersectWith(self.sheet.dimen) then UIManager:close(self) end
        return true
    end
    function Quick:onClose() UIManager:close(self) return true end
    function Quick:onShow() UIManager:setDirty(self, "ui") return true end
    function Quick:onCloseWidget() UIManager:setDirty(nil, "ui") end
    M.Quick = Quick
    function M.show_quick() UIManager:show(Quick:new{}) end

    ------------------------------------------------------------------ entry points
    local Dispatcher = require("dispatcher")
    Dispatcher:registerAction("leaf_quick_settings", { category = "none", event = "ShowLeafQuickSettings",
        title = _("Leaf: quick settings"), general = true })
    for _i, mod in ipairs({ "apps/filemanager/filemanager", "apps/reader/readerui" }) do
        local ok, cls = pcall(require, mod)
        if ok and cls then
            cls.onShowLeafQuickSettings = function() M.show_quick() return true end
        end
    end

    local function patch_menu(menu_items)
        if menu_items.about then
            menu_items.about.callback = function() M.show_about() end
        end
        local ss = menu_items.screensaver
        if ss and type(ss.sub_item_table) == "table" and not ss._leaf then
            ss._leaf = true
            table.insert(ss.sub_item_table, 1, {
                text = _("Choose sleep screen"),
                callback = function(touchmenu) M.show_sleep() end,
                separator = true,
            })
        end
    end
    for _i, mod in ipairs({ "apps/filemanager/filemanagermenu", "apps/reader/modules/readermenu" }) do
        local ok, cls = pcall(require, mod)
        if ok and cls and cls.setUpdateItemTable then
            L.wrap(cls, "setUpdateItemTable", function(orig, self, ...)
                local ret = orig(self, ...)
                patch_menu(self.menu_items or {})
                return ret
            end, mod .. ":setUpdateItemTable")
        end
    end
end

return M
