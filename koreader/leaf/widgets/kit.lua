--[[
    Leaf kit: small building blocks shared by the reader tools (frontlight, go to, skim, book end).
    Plain functions returning KOReader widgets, sized from the tokens.

      Kit.Grip                        the sheet grip (36x4, --border-strong)
      Kit.Tap:new{ width, height, content, callback, hold_callback, bg, radius, border, border_color }
                                      a tappable box (paints its own background / outline)
      Kit.line(w, token)              a hairline
      Kit.icon_button(icon, cb, parent [, size_token])
      Kit.button{ label, kind, callback, parent [, width] }       a .ko-btn (40px, _leaf_kind)
      Kit.status_strip(width)        the prototype's status bar (wifi · clock · battery %), right-aligned
      Kit.TintIcon:new{ icon, size_token, color }                 an icon in a token colour
      Kit.icon_label_button{ icon, label, kind, callback }        a .ko-btn with a leading icon
      Kit.head{ width, title, sub, actions = {widgets}, on_close, parent }
                                      .ko-sheet-head: title + sub on the left, actions + × on the right
      Kit.row{ width, icon, label, sub, trailing = "toggle"|"chevron"|nil, on, enabled, callback [, pad] }
                                      .ko-row (48px, or taller with a sub line)
      Kit.slider_row{ width, label, pct, value, unit, min_icon, max_icon, on_change(frac, final),
                      on_step(dir), enabled, parent }       .ko-sr: label · step · slider · step · value
      Kit.sheet{ width, height, content, parent }  -> frame, container
                                      .ko-sheet: --bg-raised, --r-xl top corners, on the bottom edge
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
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
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local Kit = {}

local function L_() return require("leaf/core") end

local function geom(w, h) return Geom:new{ x = 0, y = 0, w = w, h = h } end
Kit.geom = geom

---------------------------------------------------------------- grip
Kit.Grip = Widget:extend{}
function Kit.Grip:init()
    local T = L_().T
    self.T = T
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:scaleBySize(36 * T.scale), h = T.px("sp-1") }
end
function Kit.Grip:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, self.T.color("border-strong"), math.floor(self.dimen.h / 2))
end

---------------------------------------------------------------- a tappable box
Kit.Tap = InputContainer:extend{ width = 0, height = 0 }
function Kit.Tap:init()
    self.dimen = geom(self.width, self.height)
    if self.content then
        self[1] = self.content
    end
    local range = function() return self.dimen end
    self.ges_events = {
        TapLeaf = { GestureRange:new{ ges = "tap", range = range } },
        HoldLeaf = { GestureRange:new{ ges = "hold", range = range } },
    }
end
function Kit.Tap:getSize() return self.dimen end
function Kit.Tap:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local r = self.radius or 0
    if self.border then
        bb:paintRoundedRect(x, y, self.width, self.height, self.border_color, r)
        local b = self.border
        bb:paintRoundedRect(x + b, y + b, self.width - 2 * b, self.height - 2 * b, self.bg or L_().T.color("bg-raised"), math.max(0, r - b))
    elseif self.bg then
        bb:paintRoundedRect(x, y, self.width, self.height, self.bg, r)
    end
    if self[1] then self[1]:paintTo(bb, x, y) end
end
function Kit.Tap:onTapLeaf()
    if self.enabled == false then return true end
    if self.callback then self.callback() end
    return true
end
function Kit.Tap:onHoldLeaf()
    if self.enabled == false then return true end
    if self.hold_callback then self.hold_callback() return true end
    if self.callback and self.hold_is_tap then self.callback() end
    return true
end

---------------------------------------------------------------- bits
function Kit.line(w, token)
    local T = L_().T
    return LineWidget:new{ dimen = geom(w, T.px("hairline")), background = T.color(token or "border") }
end

-- the separator between rows of a .ko-list: a hairline inset by the row padding on both sides
function Kit.sep(w)
    local T = L_().T
    local pad = T.px("sp-5")
    return HorizontalGroup:new{ HorizontalSpan:new{ width = pad },
        LineWidget:new{ dimen = geom(w - 2 * pad, T.px("hairline")), background = T.color("border") } }
end

function Kit.icon_button(icon, cb, parent, size_token)
    local T = L_().T
    local IconButton = require("ui/widget/iconbutton")
    local s = T.px(size_token or "icon-md")
    local p = math.floor((T.px("hit") - s) / 2)
    return IconButton:new{ icon = icon, width = s, height = s, padding = p, callback = cb, show_parent = parent }
end

-- an icon in a fixed box (keeps rows aligned whatever the icon)
function Kit.icon(icon, size_token)
    local T = L_().T
    local s = T.px(size_token or "icon-md")
    return IconWidget:new{ icon = icon, width = s, height = s, alpha = true }
end

function Kit.button(o)
    local T = L_().T
    local Button = require("ui/widget/button")
    local Size = require("ui/size")
    return Button:new{ text = o.label, _leaf_kind = o.kind or "secondary", padding_h = T.px("sp-4"), bordersize = 0,
        width = o.width, enabled = o.enabled ~= false,
        height = T.px("h-control") - 2 * Size.padding.button, callback = o.callback, hold_callback = o.hold_callback,
        show_parent = o.parent }
end

-- an icon painted in a token colour (icons are black SVGs: their strokes become a mask), e.g. a
-- --text-3 trash can, or a white icon on a primary button. Kit.TintIcon:new{ icon, size_token, color }
Kit.TintIcon = Widget:extend{ size_token = "icon-md" }
function Kit.TintIcon:init()
    local s = L_().T.px(self.size_token)
    self.dimen = geom(s, s)
    self._icon = IconWidget:new{ icon = self.icon, width = s, height = s, alpha = true }
end
function Kit.TintIcon:getSize() return self.dimen end
function Kit.TintIcon:paintTo(bb, x, y)
    local Blitbuffer = require("ffi/blitbuffer")
    local w, h = self.dimen.w, self.dimen.h
    self.dimen.x, self.dimen.y = x, y
    if not self._mask then
        local m = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
        m:fill(Blitbuffer.COLOR_WHITE)
        self._icon:paintTo(m, 0, 0)
        m:invertRect(0, 0, w, h)
        self._mask = m
    end
    bb:colorblitFrom(self._mask, x, y, 0, 0, w, h, self.color or L_().T.color("text"))
end
function Kit.TintIcon:free()
    if self._mask then self._mask:free() self._mask = nil end
    if self._icon then self._icon:free() end
end

-- a .ko-btn with a leading icon (UI.button({icon, label, kind})): Kit.icon_label_button{ icon, label,
-- kind = "primary"|"secondary"|"ghost", callback, enabled }
function Kit.icon_label_button(o)
    local L = L_()
    local T = L.T
    local kinds = {
        primary = { bg = "accent", fg = "accent-ink", face = "ui-semibold" },
        secondary = { bg = "surface-2", fg = "text", face = "ui-medium" },
        ghost = { fg = "text-2", face = "ui-medium" },
    }
    local k = kinds[o.kind or "secondary"] or kinds.secondary
    local enabled = o.enabled ~= false
    local label = TextWidget:new{ text = o.label, face = L.face(k.face, "fs-md"), fgcolor = T.color(enabled and k.fg or "disabled") }
    local g = HorizontalGroup:new{ align = "center",
        Kit.TintIcon:new{ icon = o.icon, size_token = "icon-sm", color = T.color(enabled and k.fg or "disabled") },
        HorizontalSpan:new{ width = T.px("sp-2") }, label }
    local pad = o.kind == "ghost" and T.px("sp-3") or T.px("sp-4")
    local w = g:getSize().w + 2 * pad
    g:resetLayout()
    local h = T.px("h-control")
    local bg = k.bg and T.color(enabled and k.bg or "surface-2") or nil
    return Kit.Tap:new{ width = w, height = h, radius = T.px("r-md"), bg = bg, enabled = enabled,
        content = CenterContainer:new{ dimen = geom(w, h), g }, callback = o.callback }
end

---------------------------------------------------------------- sheet head
function Kit.head(o)
    local L = L_()
    local T = L.T
    local W = o.width
    local pad = T.px("sp-5")
    local right = HorizontalGroup:new{ align = "center" }
    for _, a in ipairs(o.actions or {}) do table.insert(right, a) end
    if o.on_close then
        table.insert(right, Kit.icon_button("close", o.on_close, o.parent))
    end
    table.insert(right, HorizontalSpan:new{ width = T.px("sp-2") })
    local rw = right:getSize().w
    right:resetLayout()
    local tw = W - pad - rw - T.px("sp-2")
    local texts = VerticalGroup:new{ align = "left" }
    if o.title_widget then
        table.insert(texts, o.title_widget)
    else
        table.insert(texts, TextWidget:new{ text = o.title or "", face = L.face("ui-semibold", "fs-head"), max_width = tw })
    end
    if o.sub and o.sub ~= "" then
        table.insert(texts, VerticalSpan:new{ width = T.px("sp-half") })
        table.insert(texts, TextWidget:new{ text = o.sub, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = tw })
    end
    local left = texts
    if o.on_title_tap then
        local sz = texts:getSize()
        texts:resetLayout()
        left = Kit.Tap:new{ width = sz.w, height = sz.h, content = texts, callback = o.on_title_tap, hold_callback = o.on_title_hold }
    end
    local h = math.max(T.px("h-header"), left:getSize().h + 2 * T.px("sp-3"))
    return OverlapGroup:new{ dimen = geom(W, h),
        LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, left } },
        RightContainer:new{ dimen = geom(W, h), right } }
end

---------------------------------------------------------------- row
function Kit.row(o)
    local L = L_()
    local T = L.T
    local W = o.width
    local pad = o.pad or T.px("sp-5")
    local enabled = o.enabled ~= false
    local trailing
    if o.trailing == "toggle" then
        trailing = require("leaf/widgets/toggle"):new{ on = o.on, enabled = enabled }
    elseif o.trailing == "chevron" then
        trailing = Kit.icon("chevron.right", "icon-sm")
    elseif o.trailing_widget then
        trailing = o.trailing_widget
    end
    local tr_w = trailing and trailing:getSize().w + T.px("sp-3") or 0
    local icon_w = o.icon and (T.px("icon-md") + T.px("sp-3")) or 0
    local tw = W - 2 * pad - icon_w - tr_w
    local texts = VerticalGroup:new{ align = "left",
        TextWidget:new{ text = o.label, face = L.face(o.label_face or "ui", "fs-md"),
            fgcolor = T.color(enabled and (o.danger and "danger" or "text") or "disabled"), max_width = tw } }
    if o.sub and o.sub ~= "" then
        table.insert(texts, TextWidget:new{ text = o.sub, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = tw })
    end
    local h = math.max(T.px("h-row"), texts:getSize().h + 2 * T.px("sp-2"))
    texts:resetLayout()
    local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad } }
    if o.icon then
        table.insert(left, Kit.icon(o.icon))
        table.insert(left, HorizontalSpan:new{ width = T.px("sp-3") })
    end
    table.insert(left, texts)
    local content = OverlapGroup:new{ dimen = geom(W, h),
        LeftContainer:new{ dimen = geom(W, h), left } }
    if trailing then
        table.insert(content, RightContainer:new{ dimen = geom(W, h),
            HorizontalGroup:new{ align = "center", trailing, HorizontalSpan:new{ width = pad } } })
    end
    return Kit.Tap:new{ width = W, height = h, content = content, callback = o.callback, hold_callback = o.hold_callback,
        enabled = enabled }
end

---------------------------------------------------------------- slider row
function Kit.slider_row(o)
    local L = L_()
    local T = L.T
    local LeafSlider = require("leaf/widgets/slider")
    local IconButton = require("ui/widget/iconbutton")
    local W = o.width
    local pad = T.px("sp-5")
    local gap = T.px("sp-2")
    local enabled = o.enabled ~= false
    local label_w = o.label_w or Screen:scaleBySize(112 * T.scale)
    local is = T.px("icon-sm")
    local step_w = Screen:scaleBySize(36 * T.scale)
    local sp = math.floor((step_w - is) / 2)
    local value_w = T.px("h-row")
    local function step(icon, dir)
        return IconButton:new{ icon = icon, width = is, height = is, padding = sp, show_parent = o.parent,
            callback = function() if enabled and o.on_step then o.on_step(dir) end end,
            hold_callback = function() if enabled and o.on_step then o.on_step(dir * 10) end end }
    end
    local slider_w = W - 2 * pad - label_w - 2 * step_w - value_w - 4 * gap
    local row = {}
    local value = HorizontalGroup:new{ align = "bottom" }
    local function fill_value(v)
        for i = #value, 1, -1 do table.remove(value, i) end
        table.insert(value, TextWidget:new{ text = tostring(v), face = L.face("ui-medium", "fs-md"),
            fgcolor = T.color(enabled and "text" or "disabled") })
        if o.unit and o.unit ~= "" then
            table.insert(value, TextWidget:new{ text = o.unit, face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3") })
        end
        value:resetLayout()
    end
    fill_value(o.value)
    local slider = LeafSlider:new{ width = slider_w, pct = o.pct or 0, enabled = enabled, show_parent = o.parent,
        on_change = function(frac, final) if o.on_change then o.on_change(frac, final) end end }
    local h = T.px("h-row")
    local value_box = RightContainer:new{ dimen = geom(value_w, h), value }
    local group = HorizontalGroup:new{ align = "center",
        HorizontalSpan:new{ width = pad },
        LeftContainer:new{ dimen = geom(label_w, h),
            TextWidget:new{ text = o.label, face = L.face("ui", "fs-md"), fgcolor = T.color(enabled and "text" or "disabled"),
                max_width = label_w - gap } },
        step(o.min_icon or "leaf.minus", -1), HorizontalSpan:new{ width = gap },
        slider, HorizontalSpan:new{ width = gap },
        step(o.max_icon or "plus", 1), HorizontalSpan:new{ width = gap },
        value_box }
    local sz = group:getSize()
    group:resetLayout()
    row = Kit.Tap:new{ width = W, height = math.max(h, sz.h), content = group }
    row.slider = slider
    -- move the knob and the value without rebuilding the sheet (while dragging)
    function row:set(pct, v)
        slider:setPct(pct)
        fill_value(v)
    end
    return row
end

---------------------------------------------------------------- sheet frame
-- content: a VerticalGroup (grip added here). Returns the frame (for outside-tap tests) and the
-- full-screen container to put in self[1].
function Kit.sheet(o)
    local L = L_()
    local T = L.T
    local W, H = Screen:getWidth(), Screen:getHeight()
    local hair = T.px("hairline")
    local r = T.px("r-xl")
    local inner = (o.width or W) - 2 * hair
    local body = VerticalGroup:new{ align = "left",
        VerticalSpan:new{ width = T.px("sp-2") },
        CenterContainer:new{ dimen = geom(inner, T.px("sp-1")), Kit.Grip:new{} },
        VerticalSpan:new{ width = T.px("sp-1") },
        o.content }
    local frame = FrameContainer:new{
        bordersize = hair, color = T.color("border-strong"), background = T.color("bg-raised"),
        radius = r, padding = 0, padding_bottom = o.floating and 0 or r, body }
    local container
    if o.floating then
        container = CenterContainer:new{ dimen = geom(W, H), frame }
    elseif o.top then
        container = VerticalGroup:new{ frame }
    else
        -- the bottom radius hangs below the screen edge: only the top corners show
        container = BottomContainer:new{ dimen = geom(W, H + r), frame }
    end
    return frame, container
end

-- inner width of a sheet built with Kit.sheet (content width)
function Kit.inner(width)
    local T = L_().T
    return (width or Screen:getWidth()) - 2 * T.px("hairline")
end

---------------------------------------------------------------- status strip
-- App.statusBar(): wifi · time · battery (pt_i_battery) · % on the right, --h-status high, --text-2 --fs-xs.
-- Kit.status_strip(width [, right_pad])
function Kit.status_strip(width, right_pad)
    local L = L_()
    local T = L.T
    local h = T.px("h-status")
    local col = T.color("text-2")
    local g = HorizontalGroup:new{ align = "center" }
    local s = T.px("icon-xs")
    local ok_net, NetworkMgr = pcall(require, "ui/network/manager")
    local wifi_on = ok_net and NetworkMgr.isWifiOn and NetworkMgr:isWifiOn()
    table.insert(g, Kit.TintIcon:new{ icon = wifi_on and "leaf.sys.wifi" or "leaf.sys.wifi.off", size_token = "icon-xs", color = col })
    table.insert(g, HorizontalSpan:new{ width = T.px("sp-2") })
    local clock = os.date("%H:%M")
    pcall(function()
        local now = os.time()
        local secs = tonumber(os.date("%H", now)) * 3600 + tonumber(os.date("%M", now)) * 60
        clock = require("datetime").secondsToHour(secs, G_reader_settings:isTrue("twelve_hour_clock"))
    end)
    table.insert(g, TextWidget:new{ text = clock, face = L.face("ui-medium", "fs-xs"), fgcolor = col })
    local pct
    pcall(function()
        local powerd = Device:getPowerDevice()
        if Device:hasBattery() then pct = powerd:getCapacity() end
    end)
    if pct then
        table.insert(g, HorizontalSpan:new{ width = T.px("sp-2") })
        table.insert(g, Kit.TintIcon:new{ icon = "pt_i_battery", size_token = "icon-sm", color = col })
        table.insert(g, HorizontalSpan:new{ width = T.px("sp-1") })
        table.insert(g, TextWidget:new{ text = pct .. "%", face = L.face("ui-medium", "fs-xs"), fgcolor = col })
    end
    table.insert(g, HorizontalSpan:new{ width = right_pad or T.px("sp-4") })
    local _ = s
    return RightContainer:new{ dimen = geom(width, h), g }
end

return Kit
