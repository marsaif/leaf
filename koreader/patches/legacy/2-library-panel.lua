--[[
    Replaces the file manager's centred "plus" dialog with a drop-down panel
    anchored under the header's right-hand buttons: grouped sections, icon + label rows.
    Reuses KOReader's own actions (FileManager:getPlusDialogButtons), so behaviour is unchanged.
--]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local SANS = "source/SourceSans3-Regular.ttf"
local SANS_BOLD = "source/SourceSans3-Bold.ttf"

-- English label -> { section, icon, optional shorter label }
local KNOWN = {
    ["Go to HOME folder"]                  = { "Navigation", "pt_m_home" },
    ["Open random document"]               = { "Navigation", "pt_m_random" },
    ["Select files"]                       = { "File operations", "pt_m_select" },
    ["New folder"]                         = { "File operations", "pt_m_newfolder" },
    ["Paste"]                              = { "File operations", "pt_m_paste" },
    ["Folder shortcuts"]                   = { "Shortcuts", "pt_m_shortcuts" },
    ["Add to folder shortcuts"]            = { "Shortcuts", "pt_m_addshortcut" },
    ["Remove from folder shortcuts"]       = { "Shortcuts", "pt_m_delshortcut" },
    ["Set as HOME folder"]                 = { "Shortcuts", "pt_m_sethome" },
    ["Extract and cache book information"] = { "System", "pt_m_extract", "Extract and cache book info" },
}
local SECTION_ORDER = { "Navigation", "File operations", "Shortcuts", "Actions", "System" }

local Panel = InputContainer:extend{
    sections = nil, -- { name = { {text=, icon=, enabled=, callback=}, ... } }
}

function Panel:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h }
    if Device:isTouchDevice() then
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end

    local pad = Screen:scaleBySize(10)
    local icon_size = Screen:scaleBySize(20)
    local icon_gap = Screen:scaleBySize(12)
    local panel_w = math.min(Screen:scaleBySize(330), screen_w - Screen:scaleBySize(24))
    local inner_w = panel_w - 2 * pad

    local content = VerticalGroup:new{ align = "left" }
    local first = true
    for _, name in ipairs(SECTION_ORDER) do
        local items = self.sections[name]
        if items and #items > 0 then
            if not first then
                table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(4) })
                table.insert(content, LineWidget:new{
                    background = Blitbuffer.COLOR_GRAY,
                    dimen = Geom:new{ w = inner_w, h = Size.line.thin },
                })
            end
            first = false
            table.insert(content, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            for _, item in ipairs(items) do
                local button = Button:new{
                    text = item.text,
                    align = "left",
                    width = inner_w - Screen:scaleBySize(12),
                    bordersize = 0,
                    radius = 0,
                    margin = 0,
                    padding_h = 0,
                    padding_v = Screen:scaleBySize(10),
                    text_font_face = SANS,
                    text_font_size = 18,
                    text_font_bold = false,
                    enabled = item.enabled,
                    callback = item.callback,
                    show_parent = self,
                }
                table.insert(content, HorizontalGroup:new{
                    align = "center",
                    HorizontalSpan:new{ width = Screen:scaleBySize(12) },
                    button,
                })
            end
        end
    end

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = pad,
        padding_top = Screen:scaleBySize(4),
        content,
    }
    self[1] = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Screen:scaleBySize(54) }, -- just under the header's title row
        RightContainer:new{
            dimen = Geom:new{ w = screen_w - Screen:scaleBySize(12), h = self.frame:getSize().h },
            self.frame,
        },
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
    if not self.frame.dimen or ges.pos:notIntersectWith(self.frame.dimen) then
        UIManager:close(self)
    end
    return true
end

function Panel:onClose()
    UIManager:close(self)
    return true
end

local orig_onShowPlusMenu = FileManager.onShowPlusMenu
FileManager.onShowPlusMenu = function(self)
    local ok, _title, rows = pcall(self.getPlusDialogButtons, self)
    if not ok or type(rows) ~= "table" then
        return orig_onShowPlusMenu(self)
    end
    local sections = {}
    local function add(section, item)
        sections[section] = sections[section] or {}
        table.insert(sections[section], item)
    end
    for _, row in ipairs(rows) do
        for _, spec in ipairs(row) do
            local text = spec.text or (spec.text_func and spec.text_func()) or ""
            if text ~= "" then
                local known = KNOWN[text]
                local enabled = spec.enabled ~= false
                if spec.enabled_func then enabled = spec.enabled_func() and true or false end
                add(known and known[1] or "Actions", {
                    text = known and known[3] or text,
                    icon = known and known[2] or "pt_m_default",
                    enabled = enabled,
                    callback = spec.callback,
                })
            end
        end
    end
    local fm = self
    add("System", {
        text = "All settings",
        icon = "pt_m_settings",
        enabled = true,
        callback = function()
            UIManager:close(fm.plus_dialog)
            fm.menu:onShowMenu()
        end,
    })
    -- KOReader's own callbacks close `self.plus_dialog`, so the panel takes that name
    self.plus_dialog = Panel:new{ sections = sections }
    UIManager:show(self.plus_dialog)
    return true
end
