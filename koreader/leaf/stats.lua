--[[
    Leaf reading statistics (prototype screen "stats"): the statistics plugin's own drawn screens.

    ReaderProgress ("Reading progress") becomes the Stats page:
      header:  ‹ Reading stats (Playfair, top-level) · calendar (CalendarView) · ⋮ (KOReader's own
               statistics menu entries stay in the menu)
      hero:    TIME READ · LAST 7 DAYS, the week's time as the hero metric (Playfair --fs-jumbo
               number, Inter unit), pages this week; four tiles under a hairline:
               session pages / session time / today pages / today time (KOReader's "Session" and
               "Today" blocks)
      chart:   "Per day" + date range, 7 accent bars with a 0 / half / max scale, today's bar in
               --text (prototype .bars .today), weekday initials under the bars, a legend.
    Its data, the readonly mode (sleep screen "reading progress") and swipe-to-close stay KOReader's.

    CalendarView keeps its grid, paging and day view; it is restyled: --bg page, day cells with
    --r-sm corners and a hairline --border, filled by reading time like the prototype heatmap
    (--heat-0..4), today with an accent ring, future days in --disabled; weekday names
    --fs-xs --text-3 caps; book spans as --surface-3 pills; hourly histogram in accent.
    The plugin loads after the patches: both are hooked from a require watcher.
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

local function stats_plugin()
    for _i, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local cls = package.loaded[mod]
        local inst = cls and cls.instance
        if inst and inst.statistics then return inst.statistics end
    end
end

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)

    ------------------------------------------------------------------ the week chart
    local Chart = Widget:extend{ width = 0, height = 0, days = nil }  -- days: { {sec, label, today} } oldest first
    function Chart:init()
        self.dimen = K.geom(self.width, self.height)
        local max = 0
        for _i, d in ipairs(self.days) do max = math.max(max, d.sec) end
        -- a round scale in three steps: 15 / 30 / 45 / 60 / 90 / 120 ... minutes at the top
        local steps = { 15, 30, 45, 60, 90, 120, 180, 240, 360, 480, 720, 1440 }
        local top = steps[#steps] * 60
        for _i, s in ipairs(steps) do if max <= s * 60 then top = s * 60 break end end
        self.top = top
        local function lab(sec)
            local m = math.floor(sec / 60 + 0.5)
            if m >= 120 and m % 60 == 0 then return math.floor(m / 60) .. "h" end
            return m .. "m"
        end
        self.scale = {}
        for i = 0, 3 do
            table.insert(self.scale, { f = i / 3, w = K.text(lab(top * i / 3), "ui", "fs-2xs", "text-3") })
        end
        self.labels = {}
        for i, d in ipairs(self.days) do
            self.labels[i] = K.text(d.label, d.today and "ui-semibold" or "ui", "fs-2xs", d.today and "text" or "text-3")
        end
    end
    function Chart:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local axis_w = 0
        for _i, s in ipairs(self.scale) do axis_w = math.max(axis_w, s.w:getSize().w) end
        axis_w = axis_w + T.px("sp-2")
        local lab_h = self.labels[1] and self.labels[1]:getSize().h or 0
        local plot_top = y + math.floor(lab_h / 2)
        local plot_h = self.height - lab_h - T.px("sp-2") - math.floor(lab_h / 2)
        local plot_x = x + axis_w
        local plot_w = self.width - axis_w
        local base = plot_top + plot_h
        for _i, s in ipairs(self.scale) do
            local ly = base - math.floor(plot_h * s.f)
            bb:paintRect(plot_x, ly, plot_w, T.px("hairline"), T.color("border"))
            local sh = s.w:getSize().h
            s.w:paintTo(bb, x, ly - math.floor(sh / 2))
        end
        local n = #self.days
        local slot = plot_w / n
        local bar_w = math.floor(slot * 0.74)
        for i, d in ipairs(self.days) do
            local cx = plot_x + math.floor(slot * (i - 0.5))
            local h = math.floor(plot_h * math.min(1, d.sec / self.top) + 0.5)
            if d.sec > 0 and h < T.px("sp-1") then h = T.px("sp-1") end
            if h > 0 then
                bb:paintRoundedRect(cx - math.floor(bar_w / 2), base - h, bar_w, h,
                    T.color(d.today and "text" or "accent"), T.px("r-tick"))
            end
            local lw = self.labels[i]:getSize().w
            self.labels[i]:paintTo(bb, cx - math.floor(lw / 2), base + T.px("sp-2"))
        end
    end

    local function legend_dot(color, label)
        local s = T.px("sp-2h")
        return HorizontalGroup:new{ align = "center",
            K.Rect:new{ w = s, h = s, color = T.color(color), radius = T.px("r-tick") },
            K.hspan("sp-1h"), K.text(label, "ui", "fs-2xs", "text-2") }
    end

    -- hero metric: Playfair numbers, Inter units ("4h 6m" -> 4 h 6 m)
    local function hero_time(sec)
        sec = math.floor(sec or 0)
        local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
        local g = HorizontalGroup:new{ align = "bottom" }
        local function part(num, unit)
            if #g > 0 then table.insert(g, K.hspan("sp-2")) end
            table.insert(g, K.text(tostring(num), "display-semibold", "fs-jumbo", "text"))
            table.insert(g, K.hspan("sp-half"))
            local u = K.text(unit, "ui-medium", "fs-lg", "text-2")
            table.insert(g, VerticalGroup:new{ u, K.vspan(T.px("sp-2")) })
        end
        if h > 0 then part(h, "h") end
        part(m, "m")
        return g
    end

    -- tile row (.ko-stats inside the card): value --fs-lg semibold, label --fs-xs --text-3
    local function tiles(width, list)
        local n = #list
        local hair = T.px("hairline")
        local cw = math.floor((width - (n - 1) * hair) / n)
        local h = T.px("h-row") + T.px("sp-4")
        local g = HorizontalGroup:new{ align = "center" }
        for i, t in ipairs(list) do
            if i > 1 then table.insert(g, K.Rect:new{ w = hair, h = h, color = T.color("border") }) end
            local col = VerticalGroup:new{ align = "center",
                K.text(t[1], "ui-semibold", "fs-lg", "text", cw),
                K.vspan("sp-half"),
                K.text(t[2], "ui", "fs-xs", "text-3", cw) }
            table.insert(g, require("ui/widget/container/centercontainer"):new{ dimen = K.geom(cw, h), col })
        end
        return g
    end

    local function week_days(dates)
        local list = {}
        local now = os.time()
        local j = 1
        local by_day = {}
        for _i, d in ipairs(dates or {}) do if d[3] then by_day[d[3]] = d end end
        for i = 7, 1, -1 do
            local t = now - 86400 * (i - 1)
            local key = os.date("%Y-%m-%d", t)
            local d = by_day[key]
            table.insert(list, { sec = d and d[2] or 0, pages = d and d[1] or 0, today = i == 1,
                label = os.date("%a", t):sub(1, 1), t = t })
        end
        local _unused = j
        return list
    end

    local function build(self, width)
        local W = width or Screen:getWidth()
        local pad = T.px("sp-4")
        local cw = W - 2 * pad
        local inner = K.inner(cw)
        local days = week_days(self.dates)
        local week_sec, week_pages = 0, 0
        for _i, d in ipairs(days) do week_sec = week_sec + d.sec week_pages = week_pages + d.pages end

        local actions = {}
        if not self.readonly then
            table.insert(actions, { "leaf.sys.calendar", function()
                local st = stats_plugin()
                if st and st.onShowCalendarView then
                    self:onClose()
                    st:onShowCalendarView()
                end
            end })
        end
        local header = K.header{ width = W, title = _("Reading stats"), display = true, parent = self,
            back = not self.readonly and function() self:onClose() end or nil, actions = actions }

        -- hero card
        local hero_col = VerticalGroup:new{ align = "left",
            K.text(_("TIME READ · LAST 7 DAYS"), "ui-semibold", "fs-xs", "text-3"),
            K.vspan("sp-2"),
            hero_time(week_sec),
            K.vspan("sp-1"),
            K.text(string.format(_("%d pages this week"), week_pages), "ui", "fs-sm", "text-2", inner),
        }
        local hero_in = T.px("sp-4")
        local hero = K.card(cw, VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ K.hspan(hero_in), VerticalGroup:new{ K.vspan(hero_in), hero_col, K.vspan(hero_in) } },
            K.line(cw - 2 * T.px("hairline")),
            tiles(cw - 2 * T.px("hairline"), {
                { tostring(self.current_pages or 0), _("session pages") },
                { K.duration(self.current_duration), _("session time") },
                { tostring(self.today_pages or 0), _("pages today") },
                { K.duration(self.today_duration), _("read today") },
            }),
        }, { flush = true })

        -- chart card
        local first, last = days[1].t, days[#days].t
        local range = os.date("%d %b", first):gsub("^0", "") .. " – " .. os.date("%d %b", last):gsub("^0", "")
        local head = OverlapGroup:new{ dimen = K.geom(inner, T.px("h-badge")),
            K.text(_("Per day"), "ui-semibold", "fs-md", "text"),
            require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(inner, T.px("h-badge")),
                K.text(range, "ui", "fs-xs", "text-3") } }
        local chart_h = math.floor(Screen:scaleBySize(170 * T.scale))
        local chart = K.card(cw, VerticalGroup:new{ align = "left",
            head, K.vspan("sp-3"),
            Chart:new{ width = inner, height = chart_h, days = days },
            K.vspan("sp-3"),
            HorizontalGroup:new{ align = "center", legend_dot("accent", _("Read")), K.hspan("sp-4"), legend_dot("text", _("Today")) },
        })

        local body = VerticalGroup:new{ align = "left",
            header,
            K.vspan("sp-2"),
            HorizontalGroup:new{ K.hspan(pad), hero },
            K.vspan("sp-3"),
            HorizontalGroup:new{ K.hspan(pad), chart },
        }
        if not self.readonly then
            local st = stats_plugin()
            if st then
                local bw = math.floor((cw - T.px("sp-3")) / 2)
                local function link_card(icon, title, sub, cb)
                    local iw = K.inner(bw)
                    return K.tap(K.card(bw, VerticalGroup:new{ align = "left",
                        HorizontalGroup:new{ align = "center", K.icon(icon, "icon-sm"), K.hspan("sp-2"),
                            K.text(title, "ui-medium", "fs-sm", "text-2", iw - T.px("icon-sm") - T.px("sp-2")) },
                        K.vspan("sp-2"),
                        K.text(sub, "ui-semibold", "fs-md", "text", iw) }), function()
                            self:onClose()
                            cb()
                        end)
                end
                table.insert(body, K.vspan("sp-3"))
                table.insert(body, HorizontalGroup:new{ K.hspan(pad),
                    link_card("leaf.sys.calendar", _("Calendar"), _("Month by month"), function() st:onShowCalendarView() end),
                    K.hspan("sp-3"),
                    link_card("leaf.sys.clock", _("Today"), _("Reading timeline"), function() st:onShowCalendarDayView() end) })
            end
        end
        return body
    end

    local function hook_progress(ReaderProgress)
        if type(ReaderProgress) ~= "table" or not ReaderProgress.getStatusContent then return end
        L.wrap(ReaderProgress, "getStatusContent", function(orig, self, width)
            return build(self, width)
        end, "ReaderProgress:getStatusContent")
        L.wrap(ReaderProgress, "init", function(orig, self)
            orig(self)
            local f = self[1]
            if f then f.background = T.color("bg") end
        end, "ReaderProgress:init")
    end

    ------------------------------------------------------------------ calendar view
    local function upvalue(fn, wanted)
        local i = 1
        while fn do
            local name, value = debug.getupvalue(fn, i)
            if not name then return end
            if name == wanted then return value end
            i = i + 1
        end
    end

    local function hook_calendar(CalendarView)
        if type(CalendarView) ~= "table" or not CalendarView._populateItems then return end
        local CalendarDay = upvalue(CalendarView._populateItems, "CalendarDay")
        local CalendarWeek = upvalue(CalendarView._populateItems, "CalendarWeek")
        local CalendarDayView = upvalue(CalendarView._populateItems, "CalendarDayView")
        local HistogramWidget = CalendarDay and upvalue(CalendarDay.init, "HistogramWidget")
        if HistogramWidget then HistogramWidget.color = T.color("accent") end

        -- footer buttons sit on the page background (KOReader paints them white)
        local function footer_bg(self)
            for _i, b in ipairs({ self.page_info_first_chev, self.page_info_left_chev, self.page_info_right_chev,
                    self.page_info_last_chev, self.page_info_text }) do
                if b then
                    b.background = T.color("bg")
                    if b.frame then b.frame.background = T.color("bg") end
                end
            end
        end

        local today_s
        if CalendarDay then
            L.wrap(CalendarDay, "init", function(orig, self)
                orig(self)
                if self.filler then return end
                local frame = self[1]
                -- reading time this day (ratio_per_hour: share of each hour spent reading)
                local sum = 0
                for _i, r in pairs(self.ratio_per_hour or {}) do sum = sum + (tonumber(r) or 0) end
                local mins = sum * 60
                -- whole cells are tinted, so only the light half of the heat scale (.heat-0..2)
                local level = mins <= 0 and 0 or (mins < 30 and 1 or 2)
                frame.radius = T.px("r-sm")
                frame.bordersize = T.px("hairline")
                frame.color = T.color(self.is_future and "surface-3" or "border")
                frame.background = T.color(self.is_future and "bg" or ("heat-" .. level))
                local today = self._leaf_today
                if today then
                    frame.bordersize = T.px("bw-lg")
                    frame.color = T.color("accent")
                end
                local dn = self.daynum_w
                if dn then
                    local strong = false
                    dn.face = L.face(today and "ui-bold" or "ui-semibold", "fs-xs")
                    dn.bold = false
                    dn.fgcolor = T.color(self.is_future and "disabled" or (strong and "accent-ink" or (today and "accent" or "text-2")))
                    dn.text = "  " .. tostring(self.daynum)
                    dn:free()
                    if dn.init then dn:init() end
                end
            end, "CalendarDay:init")
        end

        if CalendarWeek then
            L.wrap(CalendarWeek, "update", function(orig, self)
                orig(self)
                local overlaps = self[1] and self[1][1]
                if not overlaps then return end
                for i = 2, #overlaps do
                    local outer = overlaps[i]
                    local pill = outer and outer[1]
                    if pill and pill.bordersize ~= nil then
                        pill.bordersize = 0
                        pill.radius = T.px("r-tick")
                        pill.background = T.color("surface-3")
                        local cc = pill[1]
                        local tw = cc and cc[1]
                        if tw and tw.fgcolor then tw.fgcolor = T.color("text") end
                    end
                end
            end, "CalendarWeek:update")
        end

        L.wrap(CalendarView, "_populateItems", function(orig, self)
            today_s = os.date("%Y-%m-%d")
            -- mark today's cell (CalendarDay doesn't know its date): wrap new() for this pass
            local orig_new = CalendarDay and CalendarDay.new
            local month = self.cur_month
            if orig_new then
                CalendarDay.new = function(cls, o)
                    if o and o.daynum and not o.filler then
                        o._leaf_today = string.format("%s-%02d", month, o.daynum) == today_s
                    end
                    return orig_new(cls, o)
                end
            end
            local ok, err = pcall(orig, self)
            if orig_new then CalendarDay.new = orig_new end
            if not ok then error(err, 0) end
            footer_bg(self)
        end, "CalendarView:_populateItems")

        L.wrap(CalendarView, "init", function(orig, self)
            orig(self)
            local f = self[1]
            if f then f.background = T.color("bg") end
            -- weekday names: --fs-xs semibold --text-3, caps
            for _i, w in ipairs(self.day_names or {}) do
                local cc = w[1]
                local tw = cc and cc[1]
                if tw and tw.text then
                    tw.face = L.face("ui-semibold", "fs-xs")
                    tw.bold = false
                    tw.fgcolor = T.color("text-3")
                    tw.text = tw.text:upper()
                    tw:free()
                    if tw.init then tw:init() end
                end
            end
            footer_bg(self)
            local pt = self.page_info_text
            if pt then
                pt._leaf_kind = "caption"
                pt.text_font_face = require("leaf/fonts").FILES["ui-medium"]
                pt:setText(pt.text or "", pt.width)
                if pt.frame then pt.frame.background = T.color("bg") end
            end
        end, "CalendarView:init")

        if CalendarDayView then
            L.wrap(CalendarDayView, "init", function(orig, self)
                orig(self)
                local f = self[1]
                if f and f.background then f.background = T.color("bg") end
            end, "CalendarDayView:init")
        end
    end

    local hooks = { readerprogress = hook_progress, calendarview = hook_calendar }
    local done = {}
    local orig_require = require
    _G.require = function(name, ...)
        local mod = orig_require(name, ...)
        local hook = hooks[name]
        if hook and not done[name] then
            done[name] = true
            local ok, err = pcall(hook, mod)
            if ok then L.log("stats: hooked", name) else L.err("stats: hook", name, "failed:", err) end
        end
        return mod
    end
end

return M
