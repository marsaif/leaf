--[[
    Leaf library "+" popover (prototype overlay "plus"). Replaces the pre-Leaf patch
    2-library-panel.lua (patches/legacy/).

    A .ko-popover (300px, --surface, --r-lg, --border-strong hairline) under the header's
    buttons: uppercase section labels (Files · Home folder · Shortcuts), 44px rows with a Lucide
    icon, the label and a --text-3 sub-line where useful (clipboard state, home path, number of
    shortcuts), then a divider and the system rows (Cache book info, All settings).
    The rows and callbacks are KOReader's own (FileManager:getPlusDialogButtons); unknown rows
    (plugins) go in an unlabelled group before the system rows.
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

-- KOReader label -> section, icon, shorter label
local KNOWN = {
    ["Select files"] = { "files", "leaf.plus.select" },
    ["New folder"] = { "files", "leaf.plus.newfolder" },
    ["Paste"] = { "files", "leaf.plus.paste" },
    ["Set as HOME folder"] = { "home", "leaf.plus.sethome" },
    ["Go to HOME folder"] = { "home", "leaf.plus.gohome" },
    ["Open random document"] = { "home", "leaf.plus.random" },
    ["Folder shortcuts"] = { "shortcuts", "leaf.plus.shortcuts" },
    ["Add to folder shortcuts"] = { "shortcuts", "leaf.plus.addshortcut" },
    ["Remove from folder shortcuts"] = { "shortcuts", "leaf.plus.delshortcut" },
    ["Extract and cache book information"] = { "system", "leaf.plus.cache", _("Cache book info") },
}
local SECTIONS = {
    { "files", _("Files") }, { "home", _("Home folder") }, { "shortcuts", _("Shortcuts") },
    { "other", nil }, { "system", nil },
}

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

function M.apply(L)
    local T = L.T
    local FileManager = require("apps/filemanager/filemanager")

    -- one 44px row: icon, label (+ sub-line); a tap runs the callback
    local Row = InputContainer:extend{}
    function Row:init()
        local w, h = self.width, T.px("h-row-compact")
        local pad = T.px("sp-4")
        local s = T.px("icon-md")
        local texts = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = self.text, face = L.face("ui", "fs-md"),
                fgcolor = T.color(self.enabled and "text" or "disabled"), max_width = w - 2 * pad - s - T.px("sp-3") } }
        if self.sub then
            table.insert(texts, TextWidget:new{ text = self.sub, face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3"),
                max_width = w - 2 * pad - s - T.px("sp-3") })
        end
        local hh = math.max(h, texts:getSize().h + 2 * T.px("sp-1"))
        self[1] = LeftContainer:new{ dimen = Geom:new{ w = w, h = hh },
            HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = pad },
                IconWidget:new{ icon = self.icon, width = s, height = s, alpha = true, dim = not self.enabled },
                HorizontalSpan:new{ width = T.px("sp-3") },
                texts } }
        self.dimen = Geom:new{ x = 0, y = 0, w = w, h = hh }
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    function Row:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        InputContainer.paintTo(self, bb, x, y)
    end
    function Row:onTap()
        if self.enabled and self.callback then self.callback() end
        return true
    end

    local Panel = InputContainer:extend{ sections = nil }
    function Panel:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        if Device:isTouchDevice() then
            self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        end
        if Device:hasKeys() then
            self.key_events = { Close = { { Device.input.group.Back } } }
        end
        local hair = T.px("hairline")
        local pw = math.min(Screen:scaleBySize(300 * T.scale), W - 2 * T.px("sp-3"))
        local inner = pw - 2 * hair
        local content = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-2") } }
        local first = true
        for _, sec in ipairs(SECTIONS) do
            local rows = self.sections[sec[1]]
            if rows and #rows > 0 then
                if sec[2] then
                    if not first then table.insert(content, VerticalSpan:new{ width = T.px("sp-1") }) end
                    -- .ko-section-label: caps, --fs-xs semibold, --text-3
                    table.insert(content, HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-4") },
                        TextWidget:new{ text = sec[2]:upper(), face = L.face("ui-semibold", "fs-xs"), fgcolor = T.color("text-3") } })
                    table.insert(content, VerticalSpan:new{ width = T.px("sp-1") })
                elseif not first then
                    -- .ko-divider before an unlabelled group
                    table.insert(content, VerticalSpan:new{ width = T.px("sp-1") })
                    table.insert(content, LineWidget:new{ dimen = Geom:new{ w = inner, h = hair }, background = T.color("border") })
                    table.insert(content, VerticalSpan:new{ width = T.px("sp-1") })
                end
                for _, r in ipairs(rows) do
                    r.width = inner
                    table.insert(content, Row:new(r))
                end
                first = false
            end
        end
        table.insert(content, VerticalSpan:new{ width = T.px("sp-2") })
        local FrameContainer = require("ui/widget/container/framecontainer")
        self.frame = FrameContainer:new{
            background = T.color("surface"), bordersize = hair, color = T.color("border-strong"),
            radius = T.px("r-lg"), padding = 0, content,
        }
        -- under the header's buttons, right-aligned like the prototype (top 74 - 26 status, right 64)
        self[1] = VerticalGroup:new{ align = "left",
            VerticalSpan:new{ width = T.px("h-header") },
            RightContainer:new{ dimen = Geom:new{ w = W - Screen:scaleBySize(64 * T.scale), h = self.frame:getSize().h }, self.frame },
        }
    end
    function Panel:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function Panel:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end
    function Panel:onTapClose(arg, ges)
        if not self.frame.dimen or ges.pos:notIntersectWith(self.frame.dimen) then UIManager:close(self) end
        return true
    end
    function Panel:onClose()
        UIManager:close(self)
        return true
    end

    L.wrap(FileManager, "onShowPlusMenu", function(orig, self)
        local ok, _title, rows = pcall(self.getPlusDialogButtons, self)
        if not ok or type(rows) ~= "table" then return orig(self) end
        local sections = {}
        local function add(sec, item)
            sections[sec] = sections[sec] or {}
            table.insert(sections[sec], item)
        end
        local home = G_reader_settings:readSetting("home_dir")
        for _r, row in ipairs(rows) do -- (not `_`: that is gettext here)
            for _s, spec in ipairs(row) do
                local text = spec.text or (spec.text_func and spec.text_func()) or ""
                if text ~= "" then
                    local known = KNOWN[text]
                    local enabled = spec.enabled ~= false
                    if spec.enabled_func then enabled = spec.enabled_func() and true or false end
                    local sub
                    if text == "Paste" and not enabled then sub = _("Clipboard is empty")
                    elseif text == "Go to HOME folder" and home then sub = home
                    elseif text == "Folder shortcuts" then
                        local n = count(G_reader_settings:readSetting("folder_shortcuts"))
                        if n > 0 then sub = require("ffi/util").template(_("%1 saved"), n) end
                    end
                    add(known and known[1] or "other", {
                        text = known and known[3] or text, sub = sub,
                        icon = known and known[2] or "leaf.plus.action",
                        enabled = enabled, callback = spec.callback,
                    })
                end
            end
        end
        local fm = self
        add("system", { text = _("All settings"), icon = "leaf.plus.settings", enabled = true, callback = function()
            UIManager:close(fm.plus_dialog)
            fm.menu:onShowMenu()
        end })
        -- KOReader's callbacks close `self.plus_dialog`, so the popover takes that name
        self.plus_dialog = Panel:new{ sections = sections }
        UIManager:show(self.plus_dialog)
        return true
    end, "FileManager:onShowPlusMenu")
end

return M
