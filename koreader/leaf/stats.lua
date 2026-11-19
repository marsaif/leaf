--[[
    Leaf reading statistics (prototype screen "stats"): the statistics plugin's own drawn screens.

    ReaderProgress ("Reading progress") becomes the Stats page:
      header:  ← Reading stats (Playfair, top-level) · calendar (CalendarView)
      range:   Today · Week · Month · Year (.ko-seg; a new range re-opens the page). Week uses the
               plugin's seven days; Month / Year read 30 / 365 days from the statistics database,
               Today its hourly ratios (the calendar's data)
      hero:    TIME READ · <range>, the time as the hero metric (Playfair --fs-jumbo number, Inter
               unit), pages; four tiles under a hairline: pages / days read / books / time per
               reading day (Today: today's and the session's pages and time, KOReader's blocks)
      chart:   per day (per hour, per month) bars with a round three-step scale, the current one in
               --text (prototype .bars .today), sparse axis labels, a legend.
      streak:  days in a row with reading, the longest run in 30 days, a 3 x 7 heat grid (today ringed)
      links:   Calendar (month by month) · Today (reading timeline)
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
        -- a round scale in three steps, the top just above the longest day (prototype: 0 / 20 / 40 / 60m)
        local steps = { 15, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300, 360, 480, 720, 1440, 2880, 4320, 7200, 12000, 18000 }
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

    -- the statistics database over the last n days ({ [YYYY-MM-DD] = {pages, sec} }), or nil
    local function series(st, n)
        if not (st and st.getReadingProgressStats) then return nil end
        local ok, res = pcall(st.getReadingProgressStats, st, n)
        if not ok or type(res) ~= "table" then return nil end
        local by = {}
        for _i, d in ipairs(res) do if d[3] then by[d[3]] = { d[1] or 0, d[2] or 0 } end end
        return by
    end

    local RANGES = { { key = "today", label = _("Today") }, { key = "week", label = _("Week") },
        { key = "month", label = _("Month") }, { key = "year", label = _("Year") } }

    --- the bars, hero and tiles of one range
    local function range_data(self, range, st)
        local now = os.time()
        local r = { bars = {} }
        if range == "today" then
            local ratios
            if st and st.getReadingRatioPerHourByDay then
                local ok, per = pcall(st.getReadingRatioPerHourByDay, st, os.date("%Y-%m"))
                ratios = ok and per and per[os.date("%Y-%m-%d")]
            end
            local hour = tonumber(os.date("%H"))
            for h = 1, 24 do
                local sec = math.floor(((ratios and ratios[h]) or 0) * 3600 + 0.5)
                table.insert(r.bars, { sec = sec, today = h == hour + 1,
                    label = ((h - 1) % 6 == 0) and string.format("%02d", h - 1) or "" })
            end
            r.sec, r.pages = tonumber(self.today_duration) or 0, tonumber(self.today_pages) or 0
            r.eyebrow, r.range = _("TIME READ · TODAY"), os.date("%d %b"):gsub("^0", "")
            r.sub = string.format(_("%d pages today"), r.pages)
            r.tiles = { { tostring(self.today_pages or 0), _("pages today") }, { K.duration(self.today_duration), _("read today") },
                { tostring(self.current_pages or 0), _("session pages") }, { K.duration(self.current_duration), _("session time") } }
            return r
        end
        local n = range == "week" and 7 or range == "month" and 30 or 365
        local by = (range ~= "week") and series(st, n) or nil
        if not by then
            by = {}
            for _i, d in ipairs(self.dates or {}) do if d[3] then by[d[3]] = { d[1] or 0, d[2] or 0 } end end
        end
        local days_read, pages, sec = 0, 0, 0
        local daily = {}
        for i = n, 1, -1 do
            local t = now - 86400 * (i - 1)
            local d = by[os.date("%Y-%m-%d", t)]
            local e = { t = t, sec = d and d[2] or 0, pages = d and d[1] or 0, today = i == 1 }
            table.insert(daily, e)
            if e.sec > 0 then days_read = days_read + 1 end
            pages, sec = pages + e.pages, sec + e.sec
        end
        if range == "year" then -- twelve monthly bars
            local months, order = {}, {}
            for _i, e in ipairs(daily) do
                local k = os.date("%Y-%m", e.t)
                if not months[k] then months[k] = { sec = 0, t = e.t } table.insert(order, k) end
                months[k].sec = months[k].sec + e.sec
            end
            for i = math.max(1, #order - 11), #order do
                local m = months[order[i]]
                table.insert(r.bars, { sec = m.sec, today = i == #order, label = os.date("%b", m.t):sub(1, 1) })
            end
        else
            for i, e in ipairs(daily) do
                local label
                if range == "week" then label = os.date("%a", e.t):sub(1, 1)
                else label = ((n - i) % 7 == 0) and tostring(tonumber(os.date("%d", e.t))) or "" end
                table.insert(r.bars, { sec = e.sec, today = e.today, label = label })
            end
        end
        r.sec, r.pages = sec, pages
        local first, last = daily[1].t, daily[#daily].t
        r.range = os.date("%d %b", first):gsub("^0", "") .. " – " .. os.date("%d %b", last):gsub("^0", "")
        r.eyebrow = range == "week" and _("TIME READ · THIS WEEK") or range == "month" and _("TIME READ · LAST 30 DAYS")
            or _("TIME READ · LAST 12 MONTHS")
        r.sub = string.format(range == "week" and _("%d pages this week") or _("%d pages in this period"), pages)
        local books
        if st and st.getBooksFromPeriod then
            local ok, list = pcall(st.getBooksFromPeriod, st, first - (first % 86400) - 86400, now)
            if ok and type(list) == "table" then books = #list end
        end
        r.tiles = { { tostring(pages), _("pages") }, { tostring(days_read), days_read == 1 and _("day read") or _("days read") },
            books and { tostring(books), books == 1 and _("book") or _("books") } or { tostring(self.today_pages or 0), _("pages today") },
            { K.duration(days_read > 0 and math.floor(sec / days_read) or 0), _("per reading day") } }
        return r
    end

    local function build(self, width)
        local W = width or Screen:getWidth()
        local pad = T.px("sp-4")
        local cw = W - 2 * pad
        local inner = K.inner(cw)
        local st = (not self.readonly) and stats_plugin() or nil
        local range = self._leaf_range or "week"
        local data = range_data(self, range, st)

        local actions = {}
        if not self.readonly then
            table.insert(actions, { "leaf.sys.calendar", function()
                if st and st.onShowCalendarView then
                    self:onClose()
                    st:onShowCalendarView()
                end
            end })
        end
        local header = K.header{ width = W, title = _("Reading stats"), display = true, parent = self,
            back = not self.readonly and function() self:onClose() end or nil, actions = actions }

        -- range: Today · Week · Month · Year (.ko-seg--block); a new range re-opens the page
        local seg
        if not self.readonly then
            local LeafSeg = require("leaf/widgets/seg")
            seg = LeafSeg:new{ width = cw, items = RANGES, selected = range, on_select = function(key)
                if key == range then return end
                local cls = getmetatable(self)
                UIManager:close(self)
                UIManager:show(cls:new{ dates = self.dates, current_duration = self.current_duration,
                    current_pages = self.current_pages, today_duration = self.today_duration,
                    today_pages = self.today_pages, _leaf_range = key })
            end }
        end

        -- hero card
        local hero_col = VerticalGroup:new{ align = "left",
            K.text(data.eyebrow, "ui-semibold", "fs-xs", "text-3"),
            K.vspan(-T.px("sp-2")), -- (Playfair's tall ascender: the number sits under the eyebrow)
            hero_time(data.sec),
            K.text(data.sub, "ui", "fs-sm", "text-2", inner),
        }
        local hero_in = T.px("sp-4")
        local hero = K.card(cw, VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ K.hspan(hero_in), VerticalGroup:new{ K.vspan(hero_in), hero_col, K.vspan(hero_in) } },
            K.line(cw - 2 * T.px("hairline")),
            tiles(cw - 2 * T.px("hairline"), data.tiles),
        }, { flush = true })

        -- chart card
        local head = OverlapGroup:new{ dimen = K.geom(inner, T.px("h-badge")),
            K.text(range == "today" and _("Per hour") or range == "year" and _("Per month") or _("Per day"), "ui-semibold", "fs-md", "text"),
            require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(inner, T.px("h-badge")),
                K.text(data.range, "ui", "fs-xs", "text-3") } }
        local chart_h = math.floor(Screen:scaleBySize(170 * T.scale))
        local chart = K.card(cw, VerticalGroup:new{ align = "left",
            head, K.vspan("sp-3"),
            Chart:new{ width = inner, height = chart_h, days = data.bars },
            K.vspan("sp-3"),
            HorizontalGroup:new{ align = "center", legend_dot("accent", _("Read")), K.hspan("sp-4"),
                legend_dot("text", range == "year" and _("This month") or range == "today" and _("This hour") or _("Today")) },
        })

        -- reading streak (prototype "Reading streak" card): days in a row with reading up to today (or
        -- yesterday, when today has none yet), the last 21 days as a heat grid, the longest run
        local by = series(st, 30)
        if not by then
            by = {}
            for _i, d in ipairs(self.dates or {}) do if d[3] then by[d[3]] = { d[1] or 0, d[2] or 0 } end end
        end
        local now = os.time()
        local last30 = {}
        for i = 30, 1, -1 do
            local d = by[os.date("%Y-%m-%d", now - 86400 * (i - 1))]
            table.insert(last30, d and d[2] or 0)
        end
        local streak, longest, run = 0, 0, 0
        for _i, v in ipairs(last30) do
            run = v > 0 and run + 1 or 0
            longest = math.max(longest, run)
        end
        do
            local i = #last30
            if last30[i] <= 0 then i = i - 1 end
            while i >= 1 and last30[i] > 0 do streak = streak + 1 i = i - 1 end
        end
        local FrameContainer = require("ui/widget/container/framecontainer")
        local cs = T.px("icon-xs") + T.px("sp-half")
        local cgap = T.px("sp-1")
        local grid = VerticalGroup:new{ align = "left" }
        for row = 0, 2 do
            local line = HorizontalGroup:new{ align = "center" }
            for col = 1, 7 do
                local idx = #last30 - 21 + row * 7 + col
                local mins = (last30[idx] or 0) / 60
                local heat = mins <= 0 and "heat-0" or mins < 15 and "heat-1" or mins < 30 and "heat-2" or mins < 60 and "heat-3" or "heat-4"
                if col > 1 then table.insert(line, K.hspan(cgap)) end
                local today = idx == #last30
                local bw = today and T.px("bw-lg") or T.px("hairline")
                table.insert(line, FrameContainer:new{ bordersize = bw,
                    color = T.color(today and "text" or "border"), background = T.color(heat),
                    radius = T.px("r-thumb"), padding = 0, margin = 0,
                    K.Rect:new{ w = cs - 2 * bw, h = cs - 2 * bw, color = T.color(heat), radius = T.px("r-tick") } })
            end
            if row > 0 then table.insert(grid, K.vspan(cgap)) end
            table.insert(grid, line)
        end
        local grid_w = grid:getSize().w
        grid:resetLayout()
        local streak_left = VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ align = "center", K.icon("leaf.sys.flame", "icon-sm"), K.hspan("sp-2"),
                K.text(_("Reading streak"), "ui-medium", "fs-sm", "text-2") },
            K.vspan("sp-2"),
            HorizontalGroup:new{ align = "bottom",
                K.text(tostring(streak), "ui-semibold", "fs-2xl", "text"), K.hspan("sp-1"),
                VerticalGroup:new{ K.text(streak == 1 and _("day") or _("days"), "ui-medium", "fs-md", "text-2"), K.vspan(T.px("sp-1")) } },
            K.text(string.format(longest == 1 and _("Longest: %d day in the last 30") or _("Longest: %d days in the last 30"), longest), "ui", "fs-xs", "text-3", inner - grid_w - T.px("sp-3")),
        }
        local sh = math.max(streak_left:getSize().h, grid:getSize().h)
        local streak_card = K.card(cw, OverlapGroup:new{ dimen = K.geom(inner, sh),
            streak_left,
            require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(inner, sh),
                require("ui/widget/container/bottomcontainer"):new{ dimen = K.geom(grid_w, sh), grid } } })

        local body = VerticalGroup:new{ align = "left", header, K.vspan("sp-2") }
        if seg then
            table.insert(body, HorizontalGroup:new{ K.hspan(pad), seg })
            table.insert(body, K.vspan("sp-3"))
        end
        table.insert(body, HorizontalGroup:new{ K.hspan(pad), hero })
        table.insert(body, K.vspan("sp-3"))
        table.insert(body, HorizontalGroup:new{ K.hspan(pad), chart })
        table.insert(body, K.vspan("sp-3"))
        table.insert(body, HorizontalGroup:new{ K.hspan(pad), streak_card })
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
                    -- a disabled chevron is not drawn (ImageWidget's dim lightens the whole square:
                    -- a visible box on --bg); it keeps its place
                    local lw = b.label_widget
                    if lw and b ~= self.page_info_text then
                        lw.paintTo = (b.enabled == false) and function() end or nil
                    end
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
