--[[
    Leaf typesetting panel (safety-net item 21; prototype overlay "typeset"): KOReader's ConfigDialog
    (bottom panel in the reader, EPUB and PDF), its ToggleSwitch and ButtonProgressWidget.

    * Sheet: --bg-raised, --r-xl top corners on the bottom edge, grip, head (tab name --fs-head +
      close), a hairline, the options, a hairline, then the tab bar.
    * Tab bar: icon over a label (Layout · Margins · Page · Text · Contrast · Style …), the
      active tab's label in accent semibold.
    * Option names: Inter --fs-md.
    * ToggleSwitch (.ko-seg): --surface-2 track with --r-md corners, unselected cells blend in
      with --text-2 labels, the selected cell --surface with an accent outline and accent label.
    * ButtonProgressWidget (stepped values): reads like a slider track: steps up to the value in
      accent, the rest --surface-3; − / + as plain buttons.
    KOReader's options, tabs, callbacks and hold-to-set-default stay as they are.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

local TAB_LABEL = {
    ["appbar.rotation"] = _("Layout"),
    ["appbar.crop"] = _("Margins"),
    ["appbar.pageview"] = _("Page"),
    ["appbar.textsize"] = _("Text"),
    ["appbar.contrast"] = _("Contrast"),
    ["appbar.settings"] = _("Style"),
    ["appbar.pagefit"] = _("Fit"),
    ["appbar.pokeball"] = _("More"),
    ["appbar.typeset"] = _("Typeset"),
}
local function tab_label(icon)
    return TAB_LABEL[icon] or (tostring(icon or ""):gsub("^appbar%.", ""):gsub("^%l", string.upper))
end

local function upvalue(fn, wanted)
    local i = 1
    while true do
        local name, value = debug.getupvalue(fn, i)
        if not name then return nil end
        if name == wanted then return value end
        i = i + 1
    end
end

function M.apply(L)
    local T = L.T
    local fonts = require("leaf/fonts")
    local ConfigDialog = require("ui/widget/configdialog")
    local ToggleSwitch = require("ui/widget/toggleswitch")
    local ButtonProgressWidget = require("ui/widget/buttonprogresswidget")
    local IconButton = require("ui/widget/iconbutton")
    local hair = T.px("hairline")
    local ui_face = fonts.FILES["ui"]

    local MenuBar = upvalue(ConfigDialog.update, "MenuBar")
    local ConfigPanel = upvalue(ConfigDialog.update, "ConfigPanel")
    local ConfigOption = ConfigPanel and upvalue(ConfigPanel.init, "ConfigOption")

    ---------------------------------------------------------------- option names
    if ConfigOption then
        L.wrap(ConfigOption, "init", function(orig, self)
            for _, opt in ipairs(self.options or {}) do
                if not opt.name_font_face then
                    opt.name_font_face = ui_face
                    opt.name_font_size = T.fs("fs-md")
                end
            end
            return orig(self)
        end, "ConfigOption:init")
    end

    ---------------------------------------------------------------- ToggleSwitch -> .ko-seg
    L.wrap(ToggleSwitch, "init", function(orig, self)
        self.font_face = ui_face
        self.font_size = T.fs("fs-sm")
        orig(self)
        local f = self.toggle_frame
        f.background = T.color("surface-2")
        f.color = T.color("border")
        f.radius = T.px("r-md")
    end, "ToggleSwitch:init")
    L.wrap(ToggleSwitch, "update", function(orig, self)
        orig(self)
        local pos = self.position
        for i = 1, #self.toggle_content do
            local row = self.toggle_content[i]
            for j = 1, #row do
                local cell = row[j]
                local on = pos == (i - 1) * self.n_pos + j
                cell.radius = T.px("r-inner")
                cell.background = T.color(on and "surface" or "surface-2")
                cell.color = T.color(on and "accent" or "surface-2")
                local label = cell[1] and cell[1][1]
                if label then label.fgcolor = T.color(on and "accent" or "text-2") end
            end
        end
    end, "ToggleSwitch:update")

    ---------------------------------------------------------------- ButtonProgressWidget -> track
    L.wrap(ButtonProgressWidget, "update", function(orig, self)
        self.font_face = ui_face
        self.font_size = T.fs("fs-md")
        orig(self)
        local c = self.buttonprogress_content
        for k = 1, #c do
            local b = c[k]
            local f = b and b.frame
            if f and b.text ~= nil then
                f.invert = false
                if b.text == "" then
                    -- a step: accent up to the value, track after it
                    local idx
                    for n, entry in ipairs(self.layout and self.layout[1] or {}) do
                        if entry == b then idx = n end
                    end
                    local on = b.preselect or b.no_focus
                    f.background = T.color(on and "accent" or "surface-3")
                    f.color = f.background
                    f.radius = T.px("r-tick")
                else
                    -- − / + / ⋮
                    f.background = nil
                    f.color = T.color("border")
                    f.radius = T.px("r-sm")
                    if b.label_widget then b.label_widget.fgcolor = T.color("text-2") end
                end
            end
        end
    end, "ButtonProgressWidget:update")

    ---------------------------------------------------------------- tab bar: icon over label
    local Tab = InputContainer:extend{}
    function Tab:init()
        local s = T.px("icon-md")
        local g = VerticalGroup:new{ align = "center",
            IconWidget:new{ icon = self.icon, width = s, height = s, alpha = true },
            VerticalSpan:new{ width = T.px("sp-1") },
            TextWidget:new{ text = self.label, face = L.face(self.active and "ui-semibold" or "ui", "fs-xs"),
                fgcolor = T.color(self.active and "accent" or "text-2") } }
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = T.px("h-nav") }
        self[1] = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.dimen.h }, g }
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    function Tab:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        InputContainer.paintTo(self, bb, x, y)
    end
    function Tab:onTap()
        if self.callback then self.callback() end
        return true
    end

    if MenuBar then
        L.wrap(MenuBar, "init", function(orig, self)
            local dialog = self.config_dialog
            local opts = dialog.config_options
            local W = Screen:getWidth()
            -- KOReader's IconButtons stay the focus layout (keys); the touch bar is Leaf's
            if not self.menu_items then
                self.menu_items = {}
                for c = 1, #opts do
                    self.menu_items[c] = IconButton:new{ show_parent = dialog, icon = opts[c].icon,
                        width = T.px("icon-md"), height = T.px("icon-md"),
                        callback = function() dialog:handleEvent(Event:new("ShowConfigPanel", c)) end }
                end
            end
            table.insert(dialog.layout, self.menu_items)
            local tw = math.floor(W / math.max(1, #opts))
            local bar = HorizontalGroup:new{ align = "center" }
            for c = 1, #opts do
                table.insert(bar, Tab:new{ icon = opts[c].icon, label = tab_label(opts[c].icon), width = tw,
                    active = c == self.panel_index,
                    callback = function() dialog:handleEvent(Event:new("ShowConfigPanel", c)) end })
            end
            self.background = T.color("bg-raised")
            self.dimen = Geom:new{ x = 0, y = 0, w = W, h = T.px("h-nav") }
            table.insert(self, bar)
        end, "ConfigDialog MenuBar:init")
    end

    ---------------------------------------------------------------- the sheet
    L.wrap(ConfigDialog, "update", function(orig, self)
        orig(self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local frame = self.dialog_frame
        local inner = frame[1] -- VerticalGroup{ config_panel, config_menubar }
        local r = T.px("r-xl")
        local pad = T.px("sp-5")
        local s = T.px("icon-md")
        local bp = math.floor((T.px("hit") - s) / 2)
        local opt = self.config_options[self.panel_index] or {}
        local title = TextWidget:new{ text = tab_label(opt.icon), face = L.face("ui-semibold", "fs-head") }
        local close = IconButton:new{ icon = "close", width = s, height = s, padding = bp, show_parent = self,
            callback = function() self:closeDialog() end }
        local hh = T.px("h-header")
        local head = OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, title } },
            RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, HorizontalGroup:new{ close, HorizontalSpan:new{ width = T.px("sp-3") - bp } } } }
        local grip = require("ui/widget/widget"):extend{}
        function grip:init() self.dimen = Geom:new{ w = Screen:scaleBySize(36 * T.scale), h = T.px("sp-1") } end
        function grip:paintTo(bb, x, y)
            bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, T.color("border-strong"), math.floor(self.dimen.h / 2))
        end
        frame[1] = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = Geom:new{ w = W, h = T.px("sp-1") }, grip:new{} },
            head,
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") },
            inner[1],
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") },
            inner[2],
        }
        frame.background = T.color("bg-raised")
        frame.radius = r
        frame.bordersize = hair
        frame.color = T.color("border-strong")
        frame.padding = 0
        frame.padding_bottom = r
        -- corners below the screen edge: only the top ones show
        self[1] = BottomContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H + r }, frame }
    end, "ConfigDialog:update")
end

return M
