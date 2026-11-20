--[[
    Leaf gaps kit: building blocks of the generic widgets ported from the prototype's "Gaps" group
    (arrange, path chooser, image viewer, keyboard popups, open with, …). Plain functions returning
    KOReader widgets, sized from the tokens. `local GW = require("leaf/widgets/gwkit")(L)`.

      GW.text(s, role, size, color, max_w)    GW.icon(name, size_token, color_token)
      GW.icon_btn{ icon, callback, parent, enabled, color, size }   .ko-icon-btn (44px)
      GW.page_head{ width, title, crumb, on_back, actions = {widgets}, parent }
                                              status strip + .ko-header--page (crumb over title) + rule
      GW.help(text, width)                    .gp-help: --fs-sm --text-3, --sp-3 --sp-5 margins
      GW.row{ width, lead, icon, label, label_role, sub, value, trailing, chevron, pad, height,
              sel, disabled, danger, callback, hold_callback }        .ko-row
      GW.group(rows, width [, o])             .ko-group: rows in a --surface card, inset hairlines
      GW.foot{ width, left = {widgets}, right = {widgets} }           .gp-foot (--bg-raised, top rule)
      GW.button{ label, kind, icon, callback, enabled }                .ko-btn (40px)
      GW.check(on [, enabled])                .ko-check (20px)        GW.radio(on)
      GW.Popover:new{ content, anchor = Geom|nil, align = "right"|"left"|"center", above, width }
                                              .ko-popover: --surface, --r-lg, hairline; tap outside closes
      GW.pop_row{ width, icon, label, sub, value, trailing, chevron, disabled, danger, callback }
      GW.section(text, width [, pad])         .ko-section-label in a popover
      GW.divider(width)                       .ko-divider
--]]
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
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local cache

return function(L)
    if cache then return cache end
    local T = L.T
    local Kit = require("leaf/widgets/kit")
    local GW = {}
    local function geom(w, h) return Geom:new{ x = 0, y = 0, w = math.floor(w), h = math.floor(h) } end
    GW.geom = geom

    function GW.text(s, role, size, color, max_w)
        return TextWidget:new{ text = s or "", face = L.face(role or "ui", size or "fs-md"),
            fgcolor = T.color(color or "text"), max_width = max_w and math.floor(max_w) or nil }
    end
    local text = GW.text
    function GW.icon(name, size, color)
        return Kit.TintIcon:new{ icon = name, size_token = size or "icon-md", color = T.color(color or "text-2") }
    end
    function GW.hspan(n) return HorizontalSpan:new{ width = type(n) == "number" and n or T.px(n) } end
    function GW.vspan(n) return VerticalSpan:new{ width = type(n) == "number" and n or T.px(n) } end

    function GW.icon_btn(o)
        local s = T.px("hit")
        local enabled = o.enabled ~= false
        return Kit.Tap:new{ width = o.w or s, height = o.h or s, enabled = enabled, callback = o.callback,
            hold_callback = o.hold_callback, bg = o.bg, radius = o.radius,
            content = CenterContainer:new{ dimen = geom(o.w or s, o.h or s),
                GW.icon(o.icon, o.size or "icon-md", enabled and (o.color or "text-2") or "disabled") } }
    end

    function GW.button(o)
        if o.icon then
            return Kit.icon_label_button{ icon = o.icon, label = o.label, kind = o.kind, callback = o.callback, enabled = o.enabled }
        end
        return Kit.button{ label = o.label, kind = o.kind or "secondary", callback = o.callback, enabled = o.enabled,
            parent = o.parent }
    end

    function GW.check(on, enabled)
        local s = T.px("icon-md")
        return IconWidget:new{ icon = on and "leaf.check.on" or "leaf.check.off", width = s, height = s, alpha = true,
            dim = enabled == false }
    end
    function GW.radio(on, enabled)
        local s = T.px("icon-md")
        return IconWidget:new{ icon = on and "leaf.radio.on" or "leaf.radio.off", width = s, height = s, alpha = true,
            dim = enabled == false }
    end

    function GW.line(w, color) return Kit.line(w, color) end

    -- status strip + .ko-header--page --rule
    function GW.page_head(o)
        local W = o.width
        local hh = Screen:scaleBySize(64 * T.scale)
        local pad = T.px("sp-2")
        local right = HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(o.actions or {}) do table.insert(right, a) end
        table.insert(right, GW.hspan(pad))
        local rw = right:getSize().w
        right:resetLayout()
        local back = o.on_back and GW.icon_btn{ icon = o.back_icon or "leaf.gw.arrow-left", callback = o.on_back }
        local lw = pad + (back and (T.px("hit") + T.px("sp-1")) or T.px("sp-3"))
        local tw = W - lw - rw - T.px("sp-1")
        local col = VerticalGroup:new{ align = "left" }
        if o.crumb and o.crumb ~= "" then
            table.insert(col, text(o.crumb, "ui", "fs-xs", "text-3", tw))
            table.insert(col, GW.vspan("sp-half"))
        end
        table.insert(col, text(o.title, "ui-semibold", "fs-lg", "text", tw))
        if o.sub and o.sub ~= "" then
            table.insert(col, GW.vspan("sp-half"))
            table.insert(col, text(o.sub, "ui", "fs-xs", "text-3", tw))
        end
        local left = HorizontalGroup:new{ align = "center", GW.hspan(pad) }
        if back then
            table.insert(left, back)
            table.insert(left, GW.hspan("sp-1"))
        else
            table.insert(left, GW.hspan("sp-3"))
        end
        table.insert(left, col)
        local head = OverlapGroup:new{ dimen = geom(W, hh),
            LeftContainer:new{ dimen = geom(W, hh), left },
            RightContainer:new{ dimen = geom(W, hh), right } }
        local g = VerticalGroup:new{ align = "left" }
        if o.status ~= false then table.insert(g, Kit.status_strip(W)) end
        table.insert(g, head)
        if o.rule ~= false then table.insert(g, GW.line(W)) end
        return g
    end

    function GW.help(s, width, color)
        local pad = T.px("sp-5")
        return VerticalGroup:new{ align = "left", GW.vspan("sp-3"),
            HorizontalGroup:new{ GW.hspan(pad),
                TextBoxWidget:new{ text = s, face = L.face("ui", "fs-sm"), fgcolor = T.color(color or "text-3"),
                    width = width - 2 * pad, bgcolor = T.color("bg") } },
            GW.vspan("sp-3") }
    end

    -- .ko-row
    function GW.row(o)
        local W = o.width
        local pad = o.pad or T.px("sp-5")
        local gap = T.px("sp-3")
        local lead_gap = o.lead_gap or gap
        local enabled = not o.disabled
        local lead = o.lead
        if not lead and o.icon then lead = GW.icon(o.icon, o.icon_size or "icon-md", enabled and (o.icon_color or (o.danger and "danger" or "text-2")) or "disabled") end
        local trailing = o.trailing
        if not trailing and o.value then
            trailing = text(o.value, "ui", "fs-sm", enabled and (o.value_color or "text-3") or "disabled", W * 0.4)
        end
        if o.chevron then
            local chev = GW.icon("leaf.gw.chevron-right", "icon-sm", "text-3")
            trailing = trailing and HorizontalGroup:new{ align = "center", trailing, GW.hspan("sp-2"), chev } or chev
        end
        local lead_w = lead and (lead:getSize().w + lead_gap) or 0
        local trail_w = trailing and (trailing:getSize().w + gap) or 0
        local tw = W - 2 * pad - lead_w - trail_w
        local col = VerticalGroup:new{ align = "left",
            text(o.label, o.label_role or "ui", "fs-md", enabled and (o.danger and "danger" or (o.label_color or "text")) or "disabled", tw) }
        if o.sub and o.sub ~= "" then
            table.insert(col, GW.vspan("sp-half"))
            table.insert(col, text(o.sub, "ui", "fs-sm", enabled and (o.sub_color or "text-3") or "disabled", tw))
        end
        local h = math.max(o.height or T.px("h-row"), col:getSize().h + 2 * T.px("sp-2"))
        col:resetLayout()
        local left = HorizontalGroup:new{ align = "center", GW.hspan(pad) }
        if lead then
            table.insert(left, lead)
            table.insert(left, GW.hspan(lead_gap))
        end
        table.insert(left, col)
        local body = OverlapGroup:new{ dimen = geom(W, h), LeftContainer:new{ dimen = geom(W, h), left } }
        if trailing then
            table.insert(body, RightContainer:new{ dimen = geom(W, h),
                HorizontalGroup:new{ align = "center", trailing, GW.hspan(pad) } })
        end
        return Kit.Tap:new{ width = W, height = h, content = body, bg = o.sel and T.color("surface-3") or o.bg,
            callback = enabled and o.callback or nil, hold_callback = enabled and o.hold_callback or nil }
    end

    -- .ko-group (margin 0 --sp-4): rows built at GW.group_inner(width)
    function GW.group_inner(width) return width - 2 * T.px("sp-4") - 2 * T.px("hairline") end
    function GW.group(rows, width, o)
        o = o or {}
        local inner = GW.group_inner(width)
        local g = VerticalGroup:new{ align = "left" }
        local inset = o.inset or T.px("sp-4")
        for i, r in ipairs(rows) do
            if i > 1 and not o.no_lines then
                table.insert(g, HorizontalGroup:new{ GW.hspan(inset), GW.line(inner - inset) })
            end
            table.insert(g, r)
        end
        local hair = T.px("hairline")
        return HorizontalGroup:new{ GW.hspan("sp-4"),
            FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color(o.bg or "surface"),
                radius = T.px("r-lg"), padding = 0, margin = 0, g } }
    end

    -- .gp-foot: [left …] <grow> [… right], --sp-3 --sp-4 padding, --bg-raised, a hairline on top
    function GW.foot(o)
        local W = o.width
        local h = o.height or (T.px("h-control") + 2 * T.px("sp-3"))
        local padx = T.px("sp-4")
        local function row(list, gap)
            local g = HorizontalGroup:new{ align = "center" }
            for i, w in ipairs(list or {}) do
                if i > 1 then table.insert(g, GW.hspan(gap or "sp-2")) end
                table.insert(g, w)
            end
            return g
        end
        local body = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", GW.hspan(padx), row(o.left, o.gap) } },
            RightContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", row(o.right, o.gap), GW.hspan(padx) } } }
        return FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg-raised"),
            VerticalGroup:new{ GW.line(W), body } }
    end

    function GW.section(s, width, padx)
        local pad = padx or T.px("sp-4")
        return VerticalGroup:new{ align = "left", GW.vspan("sp-3"),
            HorizontalGroup:new{ GW.hspan(pad), text(s:upper(), "ui-semibold", "fs-xs", "text-3", width - 2 * pad) },
            GW.vspan("sp-1") }
    end
    function GW.divider(width)
        return VerticalGroup:new{ GW.vspan("sp-2"), GW.line(width), GW.vspan("sp-2") }
    end
    function GW.pop_row(o)
        o.pad = o.pad or T.px("sp-4")
        o.height = o.height or T.px("h-row-compact")
        return GW.row(o)
    end

    --------------------------------------------------------------------- popover
    -- .ko-popover at an anchor (a Geom on screen); tap outside closes it
    local Popover = InputContainer:extend{ modal = true, width = nil, content = nil, anchor = nil,
        align = "left", above = false, _leaf_wants_scrim = false }
    function Popover:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local hair = T.px("hairline")
        self.frame = FrameContainer:new{ bordersize = hair, color = T.color("border-strong"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = 0, padding_top = T.px("sp-2"), padding_bottom = T.px("sp-2"), margin = 0,
            self.content }
        local sz = self.frame:getSize()
        local m = T.px("sp-2")
        local x, y = self.x or m, self.y or m
        local a = self.anchor
        if a then
            if self.align == "right" then x = a.x + a.w - sz.w
            elseif self.align == "center" then x = a.x + math.floor((a.w - sz.w) / 2)
            else x = a.x end
            if self.above then y = a.y - sz.h - T.px("sp-2")
            elseif self.over then y = a.y + math.floor((a.h - sz.h) / 2)
            else y = a.y + a.h + T.px("sp-1h") end
        end
        x = math.max(m, math.min(x, W - sz.w - m))
        y = math.max(m, math.min(y, H - sz.h - m))
        self.frame_dimen = Geom:new{ x = x, y = y, w = sz.w, h = sz.h }
        self.dimen = geom(W, H)
        self.ges_events = { TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        self[1] = self.frame
    end
    function Popover:paintTo(bb, x, y)
        self.frame:paintTo(bb, self.frame_dimen.x, self.frame_dimen.y)
    end
    function Popover:onTapOutside(_arg, ges)
        if ges and ges.pos and ges.pos:intersectWith(self.frame_dimen) then return false end
        self:onClose()
        return true
    end
    function Popover:onClose()
        UIManager:close(self)
        UIManager:setDirty(nil, "ui")
        if self.close_callback then self.close_callback() end
        return true
    end
    function Popover:onShow()
        UIManager:setDirty(self, function() return "ui", self.frame_dimen end)
        return true
    end
    function Popover:onCloseWidget()
        UIManager:setDirty(nil, "ui", self.frame_dimen)
    end
    GW.Popover = Popover


    --------------------------------------------------------------------- dialog
    -- .ko-dialog: title (--fs-head semibold), sub (--fs-sm --text-3), body widget, actions
    -- right-aligned (40px .ko-btn; { label, kind = "ghost"|"primary"|"danger", callback, left = true })
    local Dialog = InputContainer:extend{ modal = true, _leaf_wants_scrim = true, title = nil, sub = nil, body = nil,
        actions = nil, width = nil }
    function GW.dialog_width() return math.min(math.floor(Screen:getWidth() * 0.86), Screen:scaleBySize(400 * T.scale)) end
    function GW.dialog_inner() return GW.dialog_width() - 2 * T.px("sp-5") - 2 * T.px("hairline") end
    function Dialog:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local dw = self.width or GW.dialog_width()
        local pad = T.px("sp-5")
        local inner = dw - 2 * pad - 2 * T.px("hairline")
        local vg = VerticalGroup:new{ align = "left",
            TextBoxWidget:new{ text = self.title or "", face = L.face("ui-semibold", "fs-head"), width = inner,
                bgcolor = T.color("surface") } }
        if self.sub and self.sub ~= "" then
            table.insert(vg, GW.vspan("sp-half"))
            table.insert(vg, text(self.sub, "ui", "fs-sm", "text-3", inner))
        end
        if self.body then table.insert(vg, self.body) end
        local left, right = HorizontalGroup:new{ align = "center" }, HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(self.actions or {}) do
            local b = GW.button{ label = a.label, kind = a.kind or "ghost", enabled = a.enabled, callback = function()
                if not a.keep then self:onClose() end
                if a.callback then a.callback() end
            end }
            local g = a.left and left or right
            if #g > 0 then table.insert(g, GW.hspan("sp-1")) end
            table.insert(g, b)
        end
        local ah = T.px("h-control")
        table.insert(vg, GW.vspan("sp-4"))
        table.insert(vg, OverlapGroup:new{ dimen = geom(inner, ah),
            LeftContainer:new{ dimen = geom(inner, ah), left }, RightContainer:new{ dimen = geom(inner, ah), right } })
        self.frame = FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border-strong"),
            background = T.color("surface"), radius = T.px("r-lg"), padding = pad, margin = 0, vg }
        self.dimen = geom(W, H)
        self.ges_events = { TapOutside = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        self[1] = CenterContainer:new{ dimen = geom(W, H), self.frame }
    end
    function Dialog:onTapOutside(_arg, ges)
        if ges and ges.pos and self.frame.dimen and ges.pos:intersectWith(self.frame.dimen) then return true end
        self:onClose()
        return true
    end
    function Dialog:onClose()
        UIManager:close(self)
        return true
    end
    function Dialog:onShow()
        UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
        return true
    end
    function Dialog:onCloseWidget()
        UIManager:setDirty(nil, "ui", self.frame.dimen)
    end
    GW.Dialog = Dialog

    -- .ko-kv: key / value rows on --surface-2, hairlines between
    function GW.kv(pairs_, width)
        local padx = T.px("sp-3")
        local inner = width - 2 * padx
        local g = VerticalGroup:new{ align = "left", GW.vspan("sp-half") }
        for i, p in ipairs(pairs_) do
            if i > 1 then table.insert(g, GW.line(inner)) end
            local h = T.px("hit") - T.px("sp-1")
            local v = text(p[2], "ui-medium", "fs-sm", "text", inner * 0.7)
            table.insert(g, OverlapGroup:new{ dimen = geom(inner, h),
                LeftContainer:new{ dimen = geom(inner, h), text(p[1], "ui", "fs-sm", "text-2", inner * 0.3) },
                RightContainer:new{ dimen = geom(inner, h), v } })
        end
        table.insert(g, GW.vspan("sp-half"))
        return VerticalGroup:new{ align = "left", GW.vspan("sp-3"),
            FrameContainer:new{ bordersize = 0, background = T.color("surface-2"), radius = T.px("r-md"),
                padding = 0, padding_left = padx, padding_right = padx, margin = 0, g } }
    end

    cache = GW
    return GW
end
