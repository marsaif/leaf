--[[
    Main menu (TouchMenu) in the same style as the library panel:
    a floating rounded card, and an icon in front of every row that isn't a checkbox.
    Icons are picked by keyword from the row's label (first match wins).
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local Size = require("ui/size")
local TouchMenu = require("ui/widget/touchmenu")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local KEYWORDS = {
    { "sleep screen", "pt_i_image" },
    { "screensaver", "pt_i_image" },
    { "night mode", "pt_i_moon" },
    { "last document", "pt_i_book-open" },
    { "history", "pt_i_history" },
    { "favorites", "pt_i_heart" },
    { "collection", "pt_i_library" },
    { "bookmark", "pt_i_bookmark" },
    { "quickstart", "pt_i_rocket" },
    { "help", "pt_i_circle-help" },
    { "about", "pt_i_info" },
    { "exit", "pt_i_log-out" },
    { "restart", "pt_i_rotate-cw" },
    { "reboot", "pt_i_rotate-cw" },
    { "power off", "pt_i_power" },
    { "sleep", "pt_i_moon" },
    { "wikipedia", "pt_i_globe" },
    { "dictionar", "pt_i_book-a" },
    { "translat", "pt_i_languages" },
    { "language", "pt_i_languages" },
    { "search", "pt_i_search" },
    { "find", "pt_i_search" },
    { "font", "pt_i_type" },
    { "wi-fi", "pt_i_wifi" },
    { "network", "pt_i_wifi" },
    { "ssh", "pt_i_terminal" },
    { "terminal", "pt_i_terminal" },
    { "cloud", "pt_i_cloud" },
    { "calibre", "pt_i_library" },
    { "opds", "pt_i_rss" },
    { "news", "pt_i_newspaper" },
    { "statistic", "pt_i_chart-column" },
    { "calendar", "pt_i_calendar" },
    { "time", "pt_i_clock" },
    { "date", "pt_i_calendar" },
    { "frontlight", "pt_i_sun" },
    { "cover", "pt_i_image" },
    { "screen", "pt_i_monitor" },
    { "e-ink", "pt_i_monitor" },
    { "color", "pt_i_palette" },
    { "contrast", "pt_i_contrast" },
    { "gesture", "pt_i_hand" },
    { "tap", "pt_i_pointer" },
    { "keyboard", "pt_i_keyboard" },
    { "navigation", "pt_i_navigation" },
    { "status bar", "pt_i_panel-bottom" },
    { "plugin", "pt_i_puzzle" },
    { "patch", "pt_i_puzzle" },
    { "update", "pt_i_download" },
    { "profile", "pt_i_user" },
    { "battery", "pt_i_battery" },
    { "device", "pt_i_tablet" },
    { "export", "pt_i_upload" },
    { "import", "pt_i_download" },
    { "vocabulary", "pt_i_graduation-cap" },
    { "note", "pt_i_notebook-pen" },
    { "text editor", "pt_i_file-pen" },
    { "sort", "pt_i_arrow-down-wide-narrow" },
    { "display mode", "pt_i_layout-grid" },
    { "items per page", "pt_i_layout-grid" },
    { "folder", "pt_i_folder" },
    { "file", "pt_i_file" },
    { "document", "pt_i_file-text" },
    { "developer", "pt_i_code" },
    { "debug", "pt_i_bug" },
    { "log", "pt_i_scroll-text" },
    { "advanced", "pt_i_sliders-horizontal" },
    { "settings", "pt_i_settings" },
    { "tool", "pt_i_wrench" },
    { "password", "pt_i_lock" },
    { "lock", "pt_i_lock" },
    { "select", "pt_i_list-checks" },
    { "random", "pt_i_shuffle" },
    { "home", "pt_i_house" },
    { "hide", "pt_i_eye-off" },
    { "show", "pt_i_eye" },
    { "sync", "pt_i_refresh-cw" },
    { "reset", "pt_i_rotate-ccw" },
    { "save", "pt_i_save" },
    { "progress", "pt_i_loader" },
    { "author", "pt_i_user" },
    { "title", "pt_i_heading" },
    { "page", "pt_i_file-text" },
    { "read", "pt_i_book-open" },
    { "book", "pt_i_book" },
    { "auto", "pt_i_zap" },
    { "move", "pt_i_move" },
}
local DEFAULT_ICON = "pt_i_dot"
local cache = {}
local function icon_for(text)
    local key = text:lower()
    local hit = cache[key]
    if hit then return hit end
    hit = DEFAULT_ICON
    for _, kw in ipairs(KEYWORDS) do
        if key:find(kw[1], 1, true) then hit = kw[2] break end
    end
    cache[key] = hit
    return hit
end

local function upvalue(func, wanted)
    local i = 1
    while true do
        local name, value = debug.getupvalue(func, i)
        if not name then return nil end
        if name == wanted then return value end
        i = i + 1
    end
end

-- Row icons
local TouchMenuItem = upvalue(TouchMenu.updateItems, "TouchMenuItem")
if TouchMenuItem then
    local orig_item_init = TouchMenuItem.init
    TouchMenuItem.init = function(self)
        orig_item_init(self)
        if true then return end -- plain text rows (Kindle style): no icons
        local item = self.item
        local group = self.item_frame and self.item_frame[1]
        local slot = group and group[1]
        if not slot or not slot[1] then return end
        if item.checked_func or item.checked ~= nil or item.radio then -- keep check/radio marks
            table.insert(group, 2, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
            group:resetLayout()
            return
        end
        local text = item.text or (item.text_func and item.text_func()) or ""
        if type(text) ~= "string" or text == "" then return end
        local size = math.min(slot.dimen.w, Screen:scaleBySize(20))
        local enabled = item.enabled
        if item.enabled_func then enabled = item.enabled_func() end
        if slot[1].free then slot[1]:free() end
        slot[1] = IconWidget:new{ icon = icon_for(text), width = size, height = size, dim = enabled == false }
        table.insert(group, 2, HorizontalSpan:new{ width = Screen:scaleBySize(6) })
        group:resetLayout()
    end
end

-- Drop-down card in the style of the library panel:
-- compact, anchored top-right, section heading, tighter rows in the UI sans font.
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")

local SANS = "source/SourceSans3-Regular.ttf"
local SANS_BOLD = "source/SourceSans3-Bold.ttf"
local TAB_NAMES = {
    ["appbar.filebrowser"] = "Library",
    ["appbar.settings"] = "Settings",
    ["appbar.tools"] = "Tools",
    ["appbar.search"] = "Search",
    ["appbar.menu"] = "Menu",
    ["appbar.navigation"] = "Navigation",
    ["appbar.typeset"] = "Typesetting",
}

local right_margin = Screen:scaleBySize(12)
local top_offset = Screen:scaleBySize(54)
local heading_h = 0 -- no section heading (Kindle style)

TouchMenu.bordersize = Size.border.window
TouchMenu.item_height = Screen:scaleBySize(42)
if TouchMenuItem then
    TouchMenuItem.face = Font:getFace(SANS, 18)
end

local orig_menu_init = TouchMenu.init
TouchMenu.init = function(self)
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    self.width = math.min(math.floor(screen_w * 0.66), screen_w - 2 * right_margin)
    orig_menu_init(self)
    local frame = self.menu_frame
    if not frame then return end
    frame.radius = Size.radius.window
    frame.padding_top = Screen:scaleBySize(4)
    local frame_w = self.width + 2 * (self.padding + self.bordersize)
    self[1] = HorizontalGroup:new{
        align = "top",
        HorizontalSpan:new{ width = math.max(0, screen_w - frame_w - right_margin) },
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = top_offset },
            frame,
        },
    }
    -- fewer rows fit now that the card starts lower and has a heading
    local items_h = screen_h - top_offset - heading_h - self.bar:getSize().h - self.footer:getSize().h
        - self.footer_top_margin:getSize().h - 2 * (self.padding + self.bordersize) - Screen:scaleBySize(12)
    self.max_per_page = math.max(3, math.floor(items_h / (self.item_height + self.split_height)))
    self:updateItems(1)
end

local orig_updateItems = TouchMenu.updateItems
TouchMenu.updateItems = function(self, ...)
    local ret = orig_updateItems(self, ...)
    if not self.dimen or not self.item_group or #self.item_group == 0 then return ret end
    -- (section heading removed for the plain Kindle style)
    if heading_h == 0 then
        self.item_group:resetLayout()
        self.dimen.x = 0
        self.dimen.y = 0
        self.dimen.w = Screen:getWidth()
        self.dimen.h = top_offset + self.item_group:getSize().h + 2 * (self.padding + self.bordersize) + Screen:scaleBySize(8)
        return ret
    end
    local tab = self.tab_item_table and self.tab_item_table[self.cur_tab or 1]
    local name = tab and TAB_NAMES[tab.icon] or ""
    local heading = TextWidget:new{
        text = name:upper(),
        face = Font:getFace(SANS_BOLD, 12),
        fgcolor = Blitbuffer.COLOR_GRAY_6,
        padding = 0,
    }
    local indent = Screen:scaleBySize(8)
    local gap_top = math.max(0, heading_h - heading:getSize().h - Screen:scaleBySize(4))
    table.insert(self.item_group, 2, VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = gap_top },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = indent },
            heading,
            HorizontalSpan:new{ width = math.max(0, self.item_width - indent - heading:getSize().w) },
        },
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
    })
    self.item_group:resetLayout()
    -- The card isn't where TouchMenu thinks it is: make its area (used for screen refreshes and
    -- tap-outside-to-close) span the full width and reach down to the card's bottom edge.
    self.dimen.x = 0
    self.dimen.y = 0
    self.dimen.w = Screen:getWidth()
    self.dimen.h = top_offset + self.item_group:getSize().h + 2 * (self.padding + self.bordersize) + Screen:scaleBySize(8)
    return ret
end
