--[[
    Leaf system kit: small building blocks shared by the system and tool screens (search, Wi-Fi,
    sleep screen, about, quick settings, statistics). Not a module of L.MODULES: those modules
    call `require("leaf/syskit")(L)` and get the helpers below, all drawn from the tokens.

      K.text / K.textbox      Inter text (role, size token, colour token)
      K.icon(name, size)      a Lucide icon (koreader/icons)
      K.tap(widget, cb, hold) a tappable wrapper (whole widget area)
      K.header{...}           .ko-header: ‹ back, title (Playfair when display), right icon actions
      K.sheet_head{...}       .ko-sheet-head: title + sub, actions, × on the right, hairline under
      K.section(text, w, link) .ko-section-label: CAPS --fs-xs --text-3 (+ an accent link at the right)
      K.chip{...}             .ko-chip: 32px pill, --border; on = accent outline + accent text
      K.card(w, content, o)   .ko-card: --surface, --border hairline, --r-lg, --sp-4 padding
      K.row{...}              .ko-row: 48px, icon/tile, label + sub, trailing widget, tap
      K.button{...}           .ko-btn (Button with a Leaf kind), 40px
      K.Page                  fullscreen page base (FocusManager: InputText parents need it)
      K.Rect                  a painted (rounded) rectangle, for charts
      K.Grip                  the sheet grip
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
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
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local cache

return function(L)
    if cache then return cache end
    local T = L.T
    local K = {}

    local function geom(w, h) return Geom:new{ x = 0, y = 0, w = math.floor(w), h = math.floor(h) } end
    K.geom = geom

    function K.text(text, role, size, color, max_width)
        return TextWidget:new{ text = text or "", face = L.face(role or "ui", size or "fs-md"),
            fgcolor = T.color(color or "text"), max_width = max_width and math.floor(max_width) or nil, padding = 0 }
    end

    function K.textbox(text, role, size, color, width, bg, o)
        o = o or {}
        return TextBoxWidget:new{ text = text or "", face = L.face(role or "ui", size or "fs-md"),
            fgcolor = T.color(color or "text"), width = math.floor(width), bgcolor = T.color(bg or "bg"),
            alignment = o.align, height = o.height, height_adjust = o.height and true or nil,
            height_overflow_show_ellipsis = o.height and true or nil, line_height = o.line_height }
    end

    function K.icon(name, size, dim)
        local s = T.px(size or "icon-md")
        return IconWidget:new{ icon = name, width = s, height = s, alpha = true, dim = dim }
    end

    function K.hspan(tok) return HorizontalSpan:new{ width = type(tok) == "number" and tok or T.px(tok) } end
    function K.vspan(tok) return VerticalSpan:new{ width = type(tok) == "number" and tok or T.px(tok) } end

    function K.line(w, color)
        return LineWidget:new{ dimen = geom(w, T.px("hairline")), background = T.color(color or "border") }
    end

    --------------------------------------------------------------------- tappable wrapper
    local Tap = InputContainer:extend{ callback = nil, hold_callback = nil }
    function Tap:init()
        local sz = self[1]:getSize()
        self.dimen = geom(sz.w, sz.h)
        local range = function() return self.dimen end
        self.ges_events = {
            TapLeaf = { GestureRange:new{ ges = "tap", range = range } },
            HoldLeaf = { GestureRange:new{ ges = "hold", range = range } },
        }
    end
    function Tap:onTapLeaf()
        if self.callback then self.callback() end
        return true
    end
    function Tap:onHoldLeaf()
        if self.hold_callback then self.hold_callback() return true end
        return self:onTapLeaf()
    end
    function K.tap(widget, cb, hold)
        return Tap:new{ widget, callback = cb, hold_callback = hold }
    end

    --------------------------------------------------------------------- painted shapes
    local Rect = Widget:extend{ w = 0, h = 0, color = nil, radius = 0, border = 0, border_color = nil }
    function Rect:init() self.dimen = geom(self.w, self.h) end
    function Rect:getSize() return self.dimen end
    function Rect:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if self.w <= 0 or self.h <= 0 then return end
        local r = math.min(self.radius or 0, math.floor(math.min(self.w, self.h) / 2))
        if self.color then bb:paintRoundedRect(x, y, self.w, self.h, self.color, r) end
        if self.border and self.border > 0 and self.border_color then
            bb:paintBorder(x, y, self.w, self.h, self.border, self.border_color, r)
        end
    end
    K.Rect = Rect

    local Grip = Widget:extend{}
    function Grip:init() self.dimen = geom(Screen:scaleBySize(36 * T.scale), T.px("sp-1")) end
    function Grip:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, T.color("border-strong"), math.floor(self.dimen.h / 2))
    end
    K.Grip = Grip

    --------------------------------------------------------------------- icon button
    function K.icon_button(icon, cb, parent, o)
        o = o or {}
        local s = T.px(o.size or "icon-md")
        local IconButton = require("ui/widget/iconbutton")
        return IconButton:new{ icon = icon, width = s, height = s, padding = math.floor((T.px("hit") - s) / 2),
            callback = cb, show_parent = parent }
    end

    --------------------------------------------------------------------- header (.ko-header)
    -- {width, title, display, back = cb, actions = { {icon, cb}... }, parent, sub}
    function K.header(o)
        local W = o.width
        local hh = T.px("h-header")
        local left = HorizontalGroup:new{ align = "center", K.hspan("sp-2") }
        if o.back then
            table.insert(left, K.icon_button("leaf.kb.left", o.back, o.parent)) -- UI.screenHead back = arrow-left
        else
            table.insert(left, K.hspan("sp-3"))
        end
        local right = HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(o.actions or {}) do
            table.insert(right, a.widget or K.icon_button(a[1], a[2], o.parent))
        end
        table.insert(right, K.hspan("sp-2"))
        local rw = right:getSize().w
        right:resetLayout()
        local lw = left:getSize().w
        left:resetLayout()
        local title = o.display
            and K.text(o.title, "display-semibold", "fs-display", "text", W - lw - rw - T.px("sp-2"))
            or K.text(o.title, "ui-semibold", "fs-head", "text", W - lw - rw - T.px("sp-2"))
        table.insert(left, title)
        return OverlapGroup:new{ dimen = geom(W, hh),
            LeftContainer:new{ dimen = geom(W, hh), left },
            RightContainer:new{ dimen = geom(W, hh), right } }
    end

    --------------------------------------------------------------------- sheet head
    -- {width, title, sub, actions = { {icon, cb} }, close = cb, parent, rule}
    function K.sheet_head(o)
        local W = o.width
        local pad = T.px("sp-5")
        local right = HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(o.actions or {}) do
            table.insert(right, K.icon_button(a[1], a[2], o.parent))
        end
        if o.close then table.insert(right, K.icon_button("close", o.close, o.parent)) end
        table.insert(right, K.hspan("sp-2"))
        local rw = right:getSize().w
        right:resetLayout()
        local tw = W - pad - rw
        local col = VerticalGroup:new{ align = "left", K.text(o.title, "ui-semibold", "fs-head", "text", tw) }
        if o.sub and o.sub ~= "" then
            table.insert(col, K.vspan("sp-half"))
            table.insert(col, K.text(o.sub, "ui", "fs-sm", "text-3", tw))
        end
        local hh = math.max(T.px("h-header"), col:getSize().h + 2 * T.px("sp-3"))
        col:resetLayout()
        local head = OverlapGroup:new{ dimen = geom(W, hh),
            LeftContainer:new{ dimen = geom(W, hh), HorizontalGroup:new{ K.hspan(pad), col } },
            RightContainer:new{ dimen = geom(W, hh), right } }
        if o.rule == false then return head end
        return VerticalGroup:new{ head, K.line(W) }
    end

    --------------------------------------------------------------------- section label
    function K.section(text, width, link, link_cb, parent)
        local pad = T.px("sp-5")
        local h = T.px("h-control")
        local label = K.text(text:upper(), "ui-semibold", "fs-xs", "text-3")
        local g = OverlapGroup:new{ dimen = geom(width, h),
            LeftContainer:new{ dimen = geom(width, h), HorizontalGroup:new{ K.hspan(pad), label } } }
        if link then
            local lt = K.tap(HorizontalGroup:new{ align = "center",
                K.text(link, "ui-medium", "fs-sm", "accent"), K.hspan(pad) }, link_cb)
            table.insert(g, RightContainer:new{ dimen = geom(width, h), lt })
        end
        return g
    end

    --------------------------------------------------------------------- chip (.ko-chip)
    -- {label, icon, on, n, callback, hold}
    function K.chip(o)
        local h = T.px("h-chip")
        local hair = T.px("hairline")
        local bw = o.on and T.px("bw-md") or hair
        local g = HorizontalGroup:new{ align = "center" }
        if o.icon then
            table.insert(g, K.icon(o.icon, "icon-sm", not o.on and o.dim))
            table.insert(g, K.hspan("sp-1h"))
        end
        table.insert(g, K.text(o.label, o.on and "ui-semibold" or "ui-medium", "fs-sm", o.on and "accent" or "text-2"))
        if o.n ~= nil then
            table.insert(g, K.hspan("sp-1h"))
            table.insert(g, K.text(tostring(o.n), "ui", "fs-2xs", o.on and "accent" or "text-3"))
        end
        local frame = FrameContainer:new{
            bordersize = bw, color = T.color(o.on and "accent" or "border"),
            background = T.color(o.on and "accent-soft" or "surface"), radius = math.floor(h / 2),
            padding = 0, padding_left = T.px("sp-3") - bw, padding_right = T.px("sp-3") - bw,
            CenterContainer:new{ dimen = geom(g:getSize().w, h - 2 * bw), g },
        }
        g:resetLayout()
        if not o.callback then return frame end
        return K.tap(frame, o.callback, o.hold)
    end

    -- one line of chips; extra chips that don't fit are dropped (KOReader can't scroll a row)
    function K.chip_row(chips, width, gap)
        gap = gap or T.px("sp-2")
        local g = HorizontalGroup:new{ align = "center" }
        local used = 0
        for _i, c in ipairs(chips) do
            local w = c:getSize().w
            if used + w > width then break end
            if used > 0 then table.insert(g, K.hspan(gap)) end
            table.insert(g, c)
            used = used + w + gap
        end
        return g
    end

    --------------------------------------------------------------------- card (.ko-card)
    function K.card(width, content, o)
        o = o or {}
        local pad = o.flush and 0 or T.px(o.pad or "sp-4")
        local bw = T.px(o.on and "bw-md" or "hairline")
        -- FrameContainer:getSize() ignores `width`: pin the content width with a span
        local inner = width - 2 * (pad + bw)
        return FrameContainer:new{
            bordersize = bw, color = T.color(o.on and "accent" or "border"),
            background = T.color(o.bg or "surface"), radius = T.px(o.radius or "r-lg"),
            padding = pad, width = width, height = o.height,
            VerticalGroup:new{ align = "left", HorizontalSpan:new{ width = inner }, content },
        }
    end
    function K.inner(width, o) -- content width inside K.card
        o = o or {}
        local pad = o.flush and 0 or T.px(o.pad or "sp-4")
        return width - 2 * (pad + T.px("hairline"))
    end

    --------------------------------------------------------------------- icon tile (.ko-icon-tile)
    function K.tile(icon, o)
        o = o or {}
        local s = T.px(o.size or "h-chip")
        local hair = T.px("hairline")
        return FrameContainer:new{
            bordersize = o.accent and 0 or hair, color = T.color("border"),
            background = T.color(o.accent and "accent" or (o.bg or "bg")), -- .theme-paper .ko-icon-tile: --bg on white cards
            radius = o.round and math.floor(s / 2) or T.px("r-md"), padding = 0,
            CenterContainer:new{ dimen = geom(s - 2 * (o.accent and 0 or hair), s - 2 * (o.accent and 0 or hair)),
                K.icon(icon, o.icon or "icon-tile") },
        }
    end

    --------------------------------------------------------------------- row (.ko-row)
    -- {width, icon | tile, label, sub, value, trailing (widget), callback, hold, height, danger, dim}
    function K.row(o)
        local W = o.width
        local pad = o.pad or T.px("sp-5")
        local gap = T.px("sp-3")
        local lead
        if o.tile then lead = K.tile(o.tile, o.tile_opts)
        elseif o.icon then lead = K.icon(o.icon, "icon-md", o.dim)
        elseif o.lead then lead = o.lead end
        local lead_w = lead and (lead:getSize().w + gap) or 0
        local trailing = o.trailing
        if o.value and not trailing then
            trailing = K.text(o.value, "ui", "fs-sm", "text-3", math.floor(W * 0.4))
        end
        local trail_w = trailing and (trailing:getSize().w + T.px("sp-2")) or 0
        local tw = W - 2 * pad - lead_w - trail_w
        local col = VerticalGroup:new{ align = "left",
            K.text(o.label, o.label_role or "ui", "fs-md", o.danger and "danger" or (o.dim and "text-3" or "text"), tw) }
        if o.sub and o.sub ~= "" then
            table.insert(col, K.vspan("sp-half"))
            table.insert(col, K.text(o.sub, "ui", "fs-sm", "text-3", tw))
        end
        local h = math.max(o.height or T.px("h-row"), col:getSize().h + 2 * T.px("sp-2"))
        col:resetLayout()
        local left = HorizontalGroup:new{ align = "center", K.hspan(pad) }
        if lead then table.insert(left, lead) table.insert(left, K.hspan(gap)) end
        table.insert(left, col)
        local body = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), left } }
        if trailing then
            table.insert(body, RightContainer:new{ dimen = geom(W, h),
                HorizontalGroup:new{ align = "center", trailing, K.hspan(pad) } })
        end
        if not (o.callback or o.hold) then return body end
        return K.tap(body, o.callback, o.hold)
    end

    -- rows separated by hairlines (inset by the side padding), inside a card if `card`
    function K.list(rows, width, o)
        o = o or {}
        local g = VerticalGroup:new{ align = "left" }
        for i, r in ipairs(rows) do
            if i > 1 and not o.no_lines then
                local l, r = o.inset or T.px("sp-5"), o.inset_right or o.inset or T.px("sp-5")
                table.insert(g, HorizontalGroup:new{ K.hspan(l), K.line(width - l - r) })
            end
            table.insert(g, r)
        end
        return g
    end

    --------------------------------------------------------------------- button (.ko-btn)
    -- {label, kind, callback, width, parent, icon}
    function K.button(o)
        local Button = require("ui/widget/button")
        local Size = require("ui/size")
        return Button:new{
            text = o.label, _leaf_kind = o.kind or "secondary", bordersize = 0,
            width = o.width, height = T.px("h-control") - 2 * Size.padding.button,
            padding_h = T.px("sp-3h"),
            callback = o.callback, show_parent = o.parent, enabled = o.enabled ~= false,
        }
    end

    --------------------------------------------------------------------- fullscreen page
    local Page = FocusManager:extend{ covers_fullscreen = true, is_always_active = false }
    function Page:init()
        self.layout = self.layout or {}
        if Device:hasKeys() then self.key_events.Close = { { Device.input.group.Back } } end
        self.dimen = geom(Screen:getWidth(), Screen:getHeight())
        self:build()
    end
    function Page:build() end
    -- wrap the body in the page background; `bottom` stays on the bottom edge
    function Page:frame(body, bottom)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local g = OverlapGroup:new{ dimen = geom(W, H), body }
        if bottom then
            local BottomContainer = require("ui/widget/container/bottomcontainer")
            table.insert(g, BottomContainer:new{ dimen = geom(W, H), bottom })
        end
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg"),
            width = W, height = H, g }
        self.dimen = geom(W, H)
    end
    function Page:rebuild()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function Page:onClose()
        UIManager:close(self)
        return true
    end
    function Page:onShow()
        UIManager:setDirty(self, "full")
        return true
    end
    function Page:onCloseWidget()
        UIManager:setDirty(nil, "full")
    end
    K.Page = Page

    -- bottom sheet frame (grip + content), --bg-raised, --r-xl top corners, on the bottom edge
    function K.sheet(content, W)
        local BottomContainer = require("ui/widget/container/bottomcontainer")
        local r = T.px("r-xl")
        local inner = W - 2 * T.px("hairline")
        local body = VerticalGroup:new{ align = "center",
            K.vspan("sp-2"),
            CenterContainer:new{ dimen = geom(inner, T.px("sp-1")), Grip:new{} },
            K.vspan("sp-1"),
            content,
        }
        local frame = FrameContainer:new{
            bordersize = T.px("hairline"), color = T.color("border-strong"), background = T.color("bg-raised"),
            radius = r, padding = 0, padding_bottom = r, margin = 0, body,
        }
        return frame, BottomContainer:new{ dimen = geom(W, Screen:getHeight() + r), frame }
    end

    -- "1h 23m" / "35m" / "0m"
    function K.duration(sec)
        sec = math.floor(tonumber(sec) or 0)
        local h = math.floor(sec / 3600)
        local m = math.floor((sec % 3600) / 60)
        if h > 0 then return string.format("%dh %dm", h, m) end
        return string.format("%dm", m)
    end

    cache = K
    return K
end
