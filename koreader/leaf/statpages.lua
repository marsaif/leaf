--[[
    Leaf statistics pages (prototype "Gaps" group: book-stats, stats-cal, stats-cal-set, stats-day,
    stats-range, stats-books; js/screens/gaps.js).

    The statistics plugin shows its lists as KeyValuePages. Every KeyValuePage the plugin creates
    becomes a Leaf page instead (StatPage below), picked by its title:
      * "Current statistics" (and a book's own statistics) -> Book statistics: hero card (cover,
        title, author, progress), four tiles, Time / Days / Pages and notes groups, "Reset
        statistics for this book" (resetCurrentBook); info buttons open KOReader's estimate popup
      * "Time range statistics" -> Time range: icon rows, totals for All books and Last 7 days
      * Books by week / month, Last week, ... -> date lists ("Thu 19 Nov · 1h 18m · 52 pages")
      * "Books read in …" -> book rows with covers; "Days reading …" -> day rows (hold = reset)
      * "Total time spent reading: …" -> All books; "Reset book statistics" -> rows with a trash
        button + "Remove short reads" (deleteBooksByTotalDuration)
    Rows keep the plugin's callbacks (tap), hold_callbacks (reset a period) and callback_return
    (‹ back to the previous list); removeKeyValueItem refreshes the page like KeyValuePage.

    CalendarView -> the prototype's month screen (weekday header, day cells with an hourly
    histogram and book bars, legend, pager « ‹ YYYY-MM › »), its settings icon opens the
    "Calendar settings" sheet (the plugin's calendar settings). CalendarDayView -> the day
    timeline page (tiles, books with check marks that filter the timeline, 24 hour lines from the
    day start, ‹ day › pager). Both keep the plugin's data calls, navigation and day / month logic.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

local function stats_plugin()
    for _i, mod in ipairs({ "apps/reader/readerui", "apps/filemanager/filemanager" }) do
        local cls = package.loaded[mod]
        local inst = cls and cls.instance
        if inst and inst.statistics then return inst.statistics end
    end
end

-- the statistics database (same file as the plugin's db_location)
local function db_rows(sql)
    local ok, res = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
        local r = conn:exec(sql)
        conn:close()
        return r
    end)
    return ok and res or nil
end
local function db_value(sql)
    local r = db_rows(sql)
    return r and r[1] and r[1][1]
end
local function sq(s) return "'" .. tostring(s):gsub("'", "''") .. "'" end

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local Kit = require("leaf/widgets/kit")
    local P = require("leaf/widgets/libparts")
    local datetime = require("datetime")
    local geom = K.geom
    local function sc(v) return Screen:scaleBySize(v * T.scale) end

    ------------------------------------------------------------------ formatting
    -- KOReader duration strings in any of its formats ("1:18:00", "1h18'", "1h 18m") -> seconds
    local function parse_dur(s)
        if type(s) == "number" then return s end
        s = tostring(s or "")
        local a, b, c = s:match("(%d+):(%d+):(%d+)")
        if a then return tonumber(a) * 3600 + tonumber(b) * 60 + tonumber(c) end
        a, b = s:match("^%s*(%d+):(%d+)")
        if a then return tonumber(a) * 60 + tonumber(b) end
        local d = tonumber(s:match("(%d+)%s*d")) or 0
        local h = tonumber(s:match("(%d+)%s*h")) or 0
        local m = tonumber(s:match("(%d+)%s*m")) or tonumber(s:match("(%d+)'")) or 0
        local sec = tonumber(s:match("(%d+)%s*s")) or tonumber(s:match("(%d+)\"")) or 0
        if d + h + m + sec == 0 and not s:find("%d") then return nil end
        return d * 86400 + h * 3600 + m * 60 + sec
    end
    local function fmt(sec) -- "1h 02m" / "35m"
        sec = math.floor(tonumber(sec) or 0)
        local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
        if h > 0 then return string.format("%dh %02dm", h, m) end
        return m .. "m"
    end
    local function fmt_long(sec) -- "212 h 40 min" (totals)
        sec = math.floor(tonumber(sec) or 0)
        return string.format("%d h %02d min", math.floor(sec / 3600), math.floor((sec % 3600) / 60))
    end
    local function fmt_mmss(sec) -- "1m 31s" (time per page)
        sec = math.floor((tonumber(sec) or 0) + 0.5)
        if sec >= 60 then return string.format("%dm %02ds", math.floor(sec / 60), sec % 60) end
        return sec .. "s"
    end
    -- "1:18:00 (52 pages)" -> "1h 18m · 52 pages"
    local function dur_pages(v)
        v = tostring(v or "")
        local d, n = v:match("^(.-)%s*%((%d+)[^%)]*%)%s*$")
        if not d then return fmt(parse_dur(v)), nil, parse_dur(v) end
        local s = parse_dur(d)
        local p = tonumber(n)
        return fmt(s) .. " · " .. T_(p == 1 and _("%1 page") or _("%1 pages"), p), p, s
    end
    local function short_month(m) return (datetime.shortMonthTranslation[m] or m) end
    -- "2026-11-19 (Thu)" / "2026-11-19" -> "Thu 19 Nov"
    local function day_label(s)
        local y, mo, d = tostring(s):match("(%d%d%d%d)-(%d%d)-(%d%d)")
        if not y then return s end
        local ts = os.time{ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 }
        return string.format("%s %d %s", datetime.shortDayOfWeekTranslation[os.date("%a", ts)] or os.date("%a", ts),
            tonumber(d), short_month(os.date("%b", ts)))
    end
    local function nice_label(s)
        s = tostring(s or "")
        if s:match("^%d%d%d%d%-%d%d%-%d%d") then return day_label(s) end
        local y, w = s:match("^(%d%d%d%d)%D+(%d+)%s*$")
        if y and s:lower():find("week") then return string.format("%s · %s %d", y, _("week"), tonumber(w)) end
        return s
    end
    -- "(6 days ago) 2026-11-14" -> "Nov 14 · 6 days ago"; "(in 5 days) 2026-11-25" -> "Nov 25 · in 5 days"
    local function rel_date(v)
        v = tostring(v or "")
        local rel, rest = v:match("^%((.-)%)%s*(.*)$")
        local y, mo, d = (rest or v):match("(%d%d%d%d)-(%d%d)-(%d%d)")
        if not y then return v end
        local ts = os.time{ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 }
        local s = string.format("%s %d", short_month(os.date("%b", ts)), tonumber(d))
        return rel and (s .. " · " .. rel) or s
    end
    local function strip_key(k)
        k = tostring(k or "")
        for _i, sym in ipairs({ "▸", "◂", "ⓘ" }) do
            local n = #sym
            if k:sub(-n) == sym then k = k:sub(1, -n - 1) end
        end
        return (k:gsub("%s+$", ""))
    end
    local function tpl_prefix(s) return (s:match("^(.-)%%1")) or s end
    local function starts(s, p) return p ~= "" and s:sub(1, #p) == p end

    ------------------------------------------------------------------ small widgets
    local function chev() return Kit.TintIcon:new{ icon = "chevron.right", size_token = "icon-sm", color = T.color("text-3") } end
    -- trailing "value ›" (or value + a widget)
    local function trail(value, extra)
        local g = HorizontalGroup:new{ align = "center" }
        if value and value ~= "" then table.insert(g, K.text(value, "ui", "fs-sm", "text-3")) end
        if extra then
            if #g > 0 then table.insert(g, K.hspan("sp-3")) end
            table.insert(g, extra)
        end
        return #g > 0 and g or nil
    end
    local function info_btn(cb)
        local s = T.px("icon-md")
        local hit = T.px("hit")
        return K.tap(CenterContainer:new{ dimen = geom(sc(28), hit),
            Kit.TintIcon:new{ icon = "info", size_token = "icon-md", color = T.color("text-2") } }, cb)
        -- (s: the icon box; the tap area is the row height)
    end
    -- .ko-group: a card of rows (rows padded --sp-4, separators inset on the left)
    local function group(rows, W)
        local inner = W - 2 * T.px("hairline")
        return K.card(W, K.list(rows, inner, { inset = T.px("sp-4"), inset_right = 0 }), { flush = true })
    end
    local function grow(o, W)
        o.width = W - 2 * T.px("hairline")
        o.pad = o.pad or T.px("sp-4")
        return K.row(o)
    end
    -- .ko-stats--card --center: equal tiles split by hairlines
    local function tiles(items, W)
        local hair = T.px("hairline")
        local n = #items
        local tw = math.floor((W - 2 * hair - (n - 1) * hair) / n)
        local g = HorizontalGroup:new{ align = "center" }
        local th = 0
        local cols = {}
        for i, it in ipairs(items) do
            local col = VerticalGroup:new{ align = "center",
                K.text(it[1], "ui-semibold", "fs-lg", "text", tw - 2 * T.px("sp-2")),
                K.vspan("sp-half"),
                K.text(it[2], "ui", "fs-xs", "text-3", tw - 2 * T.px("sp-2")) }
            th = math.max(th, col:getSize().h + 2 * T.px("sp-3"))
            col:resetLayout()
            cols[i] = col
        end
        for i, col in ipairs(cols) do
            if i > 1 then table.insert(g, K.Rect:new{ w = hair, h = th, color = T.color("border") }) end
            table.insert(g, CenterContainer:new{ dimen = geom(tw, th), col })
        end
        return K.card(W, g, { flush = true })
    end
    -- a page's centred padding block
    local function padded(w, l)
        return HorizontalGroup:new{ HorizontalSpan:new{ width = l or T.px("sp-4") }, w }
    end
    -- a text cover thumbnail (books in the statistics database may have no file)
    local function thumb(title, w, h, file)
        w = w or sc(32)
        h = h or math.floor(w * 1.5)
        return P.CoverBox:new{ image = file and P.cover(file, w, h, true) or nil, width = w, height = h, title = title,
            radius = T.px("r-thumb"), bg = T.color("bg") }
    end
    local function authors_of(title, id)
        local where = id and ("id = " .. tonumber(id)) or ("title = " .. sq(title))
        local a = db_value("SELECT authors FROM book WHERE " .. where .. " LIMIT 1;")
        a = a and tostring(a) or ""
        return (a:match("^[^\n]*") or a)
    end

    ------------------------------------------------------------------ page head (.ko-header--page --rule)
    local function page_head(o, W, parent)
        local left = HorizontalGroup:new{ align = "center", K.hspan("sp-2"),
            K.icon_button("leaf.kb.left", o.back, parent), K.hspan("sp-1") }
        local right = HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(o.actions or {}) do table.insert(right, a) end
        table.insert(right, K.hspan("sp-2"))
        local lw, rw = left:getSize().w, right:getSize().w
        left:resetLayout()
        right:resetLayout()
        local tw = W - lw - rw - T.px("sp-2")
        local col = VerticalGroup:new{ align = "left" }
        if o.crumbs and #o.crumbs > 0 then
            table.insert(col, K.text(table.concat(o.crumbs, " › "), "ui", "fs-xs", "text-3", tw))
            table.insert(col, K.vspan("sp-half"))
        end
        table.insert(col, K.text(o.title or "", "ui-semibold", "fs-lg", "text", tw))
        local h = math.max(sc(64), col:getSize().h + 2 * T.px("sp-2"))
        col:resetLayout()
        table.insert(left, col)
        return VerticalGroup:new{
            OverlapGroup:new{ dimen = geom(W, h),
                LeftContainer:new{ dimen = geom(W, h), left },
                RightContainer:new{ dimen = geom(W, h), right } },
            K.line(W) }
    end

    -- pager (.ko-pager): left text, right widgets; hairline on top
    local function pager(W, left_text, rights)
        local h = T.px("h-row")
        local r = HorizontalGroup:new{ align = "center" }
        for _i, w in ipairs(rights) do table.insert(r, w) end
        table.insert(r, K.hspan("sp-3"))
        local g = OverlapGroup:new{ dimen = geom(W, h),
            RightContainer:new{ dimen = geom(W, h), r } }
        if left_text then
            table.insert(g, LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ K.hspan("sp-5"),
                K.text(left_text, "ui", "fs-sm", "text-3") } })
        end
        return VerticalGroup:new{ K.line(W), FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), g } }
    end
    local function chev_btn(icon, enabled, cb)
        local hit = T.px("hit")
        return Kit.Tap:new{ width = hit, height = hit, enabled = enabled,
            content = CenterContainer:new{ dimen = geom(hit, hit),
                Kit.TintIcon:new{ icon = icon, size_token = "icon-md", color = T.color(enabled and "text-2" or "disabled") } },
            callback = cb }
    end

    ------------------------------------------------------------------ the Leaf statistics page
    local StatPage = K.Page:extend{ kv = nil, kind = "list", page_no = 1 }
    M.StatPage = StatPage

    function StatPage:init()
        self.kv_pairs = self.kv.kv_pairs or {}
        self.title = self.kv.title or ""
        self.callback_return = self.kv.callback_return
        self.close_callback = self.kv.close_callback
        self.ges_events = self.ges_events or {}
        self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } }
        K.Page.init(self)
        M.last = self
    end

    -- KeyValuePage API used by the plugin
    function StatPage:removeKeyValueItem(item)
        if item and item.kv_pairs_idx then
            table.remove(self.kv_pairs, item.kv_pairs_idx)
            self:rebuild()
        end
    end
    function StatPage:onClose()
        UIManager:close(self)
        if self.close_callback then self.close_callback() end
        if M.last == self then M.last = nil end
        return true
    end
    function StatPage:onReturn()
        if self.callback_return then
            self:callback_return()
            UIManager:close(self)
            UIManager:setDirty(nil, "ui")
            return true
        end
        return self:onClose()
    end
    function StatPage:onShow()
        M.last = self
        UIManager:setDirty(self, "full")
        return true
    end
    function StatPage:onSwipe(arg, ges)
        local d = ges.direction
        if d == "west" or d == "north" then self:flip(1)
        elseif d == "east" then self:flip(-1)
        elseif d == "south" then
            if (self.page_no or 1) > 1 then self:flip(-1) else self:onReturn() end
        end
        return true
    end
    function StatPage:flip(d)
        local p = math.max(1, math.min(self._pages or 1, (self.page_no or 1) + d))
        if p == self.page_no then return end
        self.page_no = p
        self:rebuild()
    end
    -- call a pair's callback the way KeyValuePage does (kv_page, kv_item)
    function StatPage:call(i, hold)
        local pr = self.kv_pairs[i]
        if not pr then return end
        local item = { kv_pairs_idx = i, book_id = pr.book_id }
        local f = hold and pr.hold_callback or pr.callback
        if f then f(self, item) end
    end
    function StatPage:cb(i) return self.kv_pairs[i] and self.kv_pairs[i].callback and function() self:call(i) end end
    function StatPage:hcb(i) return self.kv_pairs[i] and self.kv_pairs[i].hold_callback and function() self:call(i, true) end end

    -- lay the body blocks into screen pages; o = { head = {...}, blocks = {widgets}, foot = widget }
    function StatPage:layout_page(o)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local head = page_head(o.head, W, self)
        local fixed = VerticalGroup:new{ align = "left", Kit.status_strip(W), head }
        local fixed_h = fixed:getSize().h
        fixed:resetLayout()
        local foot = o.foot
        local foot_h = foot and foot:getSize().h or 0
        local avail = H - fixed_h - foot_h
        local hair = T.px("hairline")
        -- a split block { split = true, label = widget, rows = {row widgets}, gw = card width } may
        -- continue on the next screen (its card is cut between rows, as a scrolling page would be)
        local function bh(b)
            if not b.split then return b:getSize().h end
            local h = (b.label and b.label:getSize().h or 0) + 2 * hair
            for k, r in ipairs(b.rows) do h = h + r:getSize().h + (k > 1 and hair or 0) end
            return h
        end
        local total = 0
        for _i, b in ipairs(o.blocks) do total = total + bh(b) end
        local pav = avail
        if total > avail and not foot then pav = avail - T.px("h-row") - hair end
        local blocks, page_of, pages, used = {}, {}, 1, 0
        for _i, b in ipairs(o.blocks) do
            if b.split then
                local i, first = 1, true
                while i <= #b.rows do
                    local lh = (first and b.label) and b.label:getSize().h or 0
                    local room = pav - used - lh - 2 * hair
                    local chunk, ch = {}, 0
                    while i <= #b.rows do
                        local rh = b.rows[i]:getSize().h + (#chunk > 0 and hair or 0)
                        if ch + rh > room and (#chunk > 0 or used > 0) then break end
                        table.insert(chunk, b.rows[i])
                        ch = ch + rh
                        i = i + 1
                    end
                    if #chunk == 0 then
                        pages = pages + 1
                        used = 0
                    else
                        local w = VerticalGroup:new{ align = "left" }
                        if first and b.label then table.insert(w, b.label) end
                        table.insert(w, padded(group(chunk, b.gw)))
                        first = false
                        table.insert(blocks, w)
                        page_of[#blocks] = pages
                        used = used + w:getSize().h
                        if i <= #b.rows then pages = pages + 1 used = 0 end
                    end
                end
            else
                local h = b:getSize().h
                if used > 0 and used + h > pav then pages = pages + 1 used = 0 end
                used = used + h
                table.insert(blocks, b)
                page_of[#blocks] = pages
            end
        end
        if pages > 1 and not foot then
            foot = pager(W, T_(_("Page %1 of %2"), math.min(self.page_no, pages), pages), {
                chev_btn("chevron.left", self.page_no > 1, function() self:flip(-1) end),
                chev_btn("chevron.right", self.page_no < pages, function() self:flip(1) end) })
        end
        o.blocks = blocks
        self._pages = pages
        self.page_no = math.max(1, math.min(self.page_no or 1, pages))
        local body = VerticalGroup:new{ align = "left", fixed }
        for i, b in ipairs(o.blocks) do
            if page_of[i] == self.page_no then table.insert(body, b) end
        end
        self:frame(body, foot)
    end

    function StatPage:back() return function() self:onReturn() end end

    -- crumbs from the page this one was opened from
    function StatPage:crumbs()
        local p = self.parent
        if not p then return { _("Statistics") } end
        if p.kind == "book" then return { _("Book statistics") } end
        return { _("Statistics"), p.crumb_name or p.title }
    end

    ------------------------------------------------ builders per kind
    local BUILD = {}

    -- Time range
    local RANGE = {
        { "All books", "leaf.mn.library", nil },
        { "Books by week", "leaf.gs.calendar-range" },
        { "Books by month", "leaf.sys.calendar" },
        { "Last week", "leaf.gs.calendar-days", "Last 7 days" },
        { "Last month by day", "leaf.gs.calendar-check" },
        { "Last year by day", "leaf.gs.calendar-clock" },
        { "Last year by week", "leaf.gs.calendar-fold" },
        { "All stats by month", "leaf.mn.history", "All statistics by month" },
    }
    function BUILD.range(self)
        local W = Screen:getWidth()
        local gw = W - 2 * T.px("sp-4")
        self.crumb_name = _("Time range")
        local total = tonumber(db_value("SELECT sum(duration) FROM page_stat;")) or 0
        local now_t = os.date("*t")
        local begin = os.time() - 6 * 86400 - (now_t.hour * 3600 + now_t.min * 60 + now_t.sec)
        local week = tonumber(db_value("SELECT sum(duration) FROM page_stat WHERE start_time >= " .. begin .. ";")) or 0
        local rows = {}
        for i, pr in ipairs(self.kv_pairs) do
            local key = strip_key(pr[1])
            local icon, label = nil, key
            for _j, r in ipairs(RANGE) do
                if key == _(r[1]) then icon = r[2]; label = r[3] and _(r[3]) or key end
            end
            local value
            if key == _("All books") then value = fmt_long(total)
            elseif key == _("Last week") then value = fmt_long(week) end
            table.insert(rows, grow({ icon = icon, label = label, trailing = trail(value, chev()),
                callback = self:cb(i), hold = self:hcb(i) }, gw))
        end
        self:layout_page{ head = { title = _("Time range"), crumbs = self:crumbs(), back = self:back() },
            blocks = { VerticalGroup:new{ align = "left", K.vspan("sp-1"), padded(group(rows, gw)) } } }
    end

    -- date lists (weeks, months, days)
    function BUILD.dates(self)
        local W = Screen:getWidth()
        local gw = W - 2 * T.px("sp-4")
        local title = self.title
        local days_tpl = tpl_prefix(_("Days reading %1"))
        local is_days = starts(title, days_tpl)
        if title == _("Last week") then title = _("Last 7 days")
        elseif title == _("All stats by month") then title = _("All statistics by month") end
        self.crumb_name = title
        local rows = {}
        local function add(i, label, value, disabled)
            local pr = i and self.kv_pairs[i]
            local can = pr and (pr.callback or pr.hold_callback)
            table.insert(rows, grow({ label = label, dim = disabled,
                trailing = disabled and K.text("—", "ui", "fs-sm", "text-3") or trail(value, (pr and pr.callback) and chev() or nil),
                callback = can and (self:cb(i) or function() end) or nil, hold = pr and self:hcb(i) }, gw))
        end
        if self.title == _("Last week") then
            -- every day of the week, the ones without reading greyed (prototype "Sat 14 Nov —")
            local by_day = {}
            for i, pr in ipairs(self.kv_pairs) do
                local d = tostring(pr[1]):match("(%d%d%d%d%-%d%d%-%d%d)")
                if d then by_day[d] = i end
            end
            for k = 0, 6 do
                local d = os.date("%Y-%m-%d", os.time() - k * 86400)
                local i = by_day[d]
                if i then add(i, day_label(d), (dur_pages(self.kv_pairs[i][2])))
                else add(nil, day_label(d), nil, true) end
            end
        else
            for i, pr in ipairs(self.kv_pairs) do
                if type(pr) == "table" then
                    -- a day without a tap action (days reading a book): open its timeline
                    local d = tostring(pr[1]):match("^(%d%d%d%d%-%d%d%-%d%d)")
                    if d and not pr.callback then
                        pr.callback = function() M.open_day(d, { _("Statistics"), title }) end
                    end
                    add(i, nice_label(strip_key(pr[1])), (dur_pages(pr[2])))
                end
            end
        end
        local blocks = {}
        if is_days then
            table.insert(blocks, K.textbox(_("Long-press a day to reset this book's statistics for it."), "ui", "fs-sm", "text-3",
                W - 2 * T.px("sp-5"), "bg"))
            blocks[1] = VerticalGroup:new{ align = "left", K.vspan("sp-3"), padded(blocks[1], T.px("sp-5")), K.vspan("sp-3") }
        end
        if #rows > 0 then table.insert(blocks, padded(group(rows, gw))) end
        self:layout_page{ head = { title = title, crumbs = self:crumbs(), back = self:back() }, blocks = blocks }
    end

    -- book rows with a cover (books read in a period, all books, reset)
    local function book_row(self, i, o, W)
        local cw = sc(32)
        return K.row{ width = W, lead = thumb(o.title, cw), label = o.title, sub = o.sub, trailing = o.trailing,
            height = math.floor(cw * 1.5) + 2 * T.px("sp-2"), callback = o.callback, hold = o.hold }
    end
    local function book_list(rows, W)
        return K.list(rows, W, { inset = sc(52), inset_right = 0 })
    end
    local function note_line(icon, text, W)
        local h = sc(44)
        return LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", K.hspan("sp-5"),
            Kit.TintIcon:new{ icon = icon, size_token = "icon-sm", color = T.color("text-3") }, K.hspan("sp-2"),
            K.text(text, "ui", "fs-sm", "text-3", W - sc(60)) } }
    end

    function BUILD.books(self)
        local W = Screen:getWidth()
        local title = self.title
        local p_in = tpl_prefix(_("Books read in %1"))
        local p_day = tpl_prefix(_("Books read %1"))
        local when = starts(title, p_in) and title:sub(#p_in + 1) or (starts(title, p_day) and title:sub(#p_day + 1)) or ""
        if when:match("^%d%d%d%d%-%d%d%-%d%d") then
            title = T_(_("Books read on %1"), day_label(when))
        elseif when:find("[Ww]eek") then
            title = T_(_("Books read in %1"), nice_label(when))
        end
        self.crumb_name = title
        local rows = {}
        for i, pr in ipairs(self.kv_pairs) do
            local t = tostring(pr[1])
            table.insert(rows, book_row(self, i, { title = t, sub = (dur_pages(pr[2])),
                trailing = pr.callback and chev() or nil, callback = self:cb(i), hold = self:hcb(i) }, W))
        end
        local period = when:match("^%d%d%d%d%-") and _("this day") or (when:lower():find("week") and _("this week") or _("this month"))
        local blocks = { VerticalGroup:new{ align = "left", K.vspan("sp-3"),
            padded(K.textbox(T_(_("Tap a book for its statistics. Long-press to reset its statistics for %1."), period),
                "ui", "fs-sm", "text-3", W - 2 * T.px("sp-5"), "bg"), T.px("sp-5")), K.vspan("sp-3") } }
        for _i, r in ipairs(rows) do table.insert(blocks, r) end
        -- one list: separators between the rows
        if #rows > 0 then
            blocks = { blocks[1], book_list(rows, W) }
        end
        self:layout_page{ head = { title = title, crumbs = self:crumbs(), back = self:back() }, blocks = blocks }
    end

    function BUILD.all(self)
        local W = Screen:getWidth()
        self.crumb_name = _("All books")
        local total = self.title:sub(#tpl_prefix(_("Total time spent reading: %1")) + 1)
        local rows = {}
        for i, pr in ipairs(self.kv_pairs) do
            local t = tostring(pr[1])
            table.insert(rows, book_row(self, i, { title = t, sub = authors_of(t),
                trailing = trail(fmt(parse_dur(pr[2])), pr.callback and chev() or nil),
                callback = self:cb(i), hold = self:hcb(i) }, W))
        end
        local blocks = { note_line("leaf.sys.clock", T_(_("Total time spent reading · %1"), fmt_long(parse_dur(total))), W) }
        if #rows > 0 then table.insert(blocks, book_list(rows, W)) end
        self:layout_page{ head = { title = _("All books"), crumbs = { _("Statistics") }, back = self:back() }, blocks = blocks }
    end

    function BUILD.reset(self)
        local W = Screen:getWidth()
        local st = stats_plugin()
        self.crumb_name = _("Reset book statistics")
        local rows = {}
        for i, pr in ipairs(self.kv_pairs) do
            local t = tostring(pr[1])
            local trash = K.tap(CenterContainer:new{ dimen = geom(sc(32), T.px("hit")),
                Kit.TintIcon:new{ icon = "leaf.lib.trash", size_token = "icon-md", color = T.color("text-2") } },
                function() self:call(i) end)
            table.insert(rows, book_row(self, i, { title = t, sub = authors_of(t, pr[3]),
                trailing = trail(fmt(parse_dur(pr[2])), trash), hold = function() self:call(i) end }, W))
        end
        local blocks = { note_line("leaf.sys.clock", _("The current book is not listed"), W) }
        if #rows > 0 then table.insert(blocks, book_list(rows, W)) end
        if st and st.deleteBooksByTotalDuration then
            table.insert(blocks, K.section(_("Remove short reads"), W))
            local gw = W - 2 * T.px("sp-4")
            local srows = {}
            for _j, m in ipairs({ 1, 5, 15, 30, 60 }) do
                table.insert(srows, grow({ icon = "leaf.lib.eraser", label = T_(_("Books read for less than %1 min"), m),
                    callback = function() st:deleteBooksByTotalDuration(m) end }, gw))
            end
            table.insert(blocks, padded(group(srows, gw)))
        end
        self:layout_page{ head = { title = _("Reset book statistics"), crumbs = self:crumbs(), back = self:back() }, blocks = blocks }
    end

    -- Book statistics (current book, or a book of the lists)
    local BOOK_KEYS = {
        session = "Time spent reading this session", session_pages = "Pages read this session",
        today = "Time spent reading today", today_pages = "Pages read today",
        total = "Total time spent on this book", read = "Time spent reading",
        left = "Estimated reading time left", days = "Days reading this book", per_day = "Average time per day",
        start = "Book start date", finish = "Estimated finish date", finished = "Book marked as finished",
        page = "Current page/Total pages", pages = "Pages read", per_page = "Average time per page",
        hl = "Book highlights", notes = "Book notes", last = "Last read date",
    }
    function BUILD.book(self)
        local W = Screen:getWidth()
        local gw = W - 2 * T.px("sp-4")
        local st = stats_plugin()
        self.crumb_name = _("Book statistics")
        local by, used = {}, {}
        for i, pr in ipairs(self.kv_pairs) do
            if type(pr) == "table" then
                local k = strip_key(pr[1])
                for id, en in pairs(BOOK_KEYS) do
                    if k == _(en) then by[id] = i end
                end
            end
        end
        local function v(id) local i = by[id]; if i then used[i] = true; return self.kv_pairs[i][2] end end
        local function cb(id) return by[id] and self:cb(by[id]) end
        local current = self.current
        -- book
        local title = current and st and st.data and st.data.title or self.title
        local authors = current and st and st.data and st.data.authors or authors_of(title)
        authors = tostring(authors or ""):match("^[^\n]*") or ""
        local cur_s, tot_s, pct = tostring(v("page") or ""):match("^%s*(%S+)%s*/+%s*(%S+)%s*%((%d+)%%%)")
        local pages_v = v("pages")
        local pr_n, pr_pct = tostring(pages_v or ""):match("^(%d+)%s*%((%d+)%%%)")
        pct = tonumber(pct) or tonumber(pr_pct) or 0
        -- hero card (.gp-bs-hero)
        local cw = sc(56)
        local cover
        if current and st and st.ui and st.ui.document then
            pcall(function()
                local bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(st.ui.document)
                if bb then
                    local ImageWidget = require("ui/widget/imagewidget")
                    local ch = math.floor(cw * 1.5)
                    cover = P.CoverBox:new{ image = ImageWidget:new{ image = bb, image_disposable = true, width = cw, height = ch,
                        scale_factor = math.max(cw / bb:getWidth(), ch / bb:getHeight()), center_x_ratio = 0.5, center_y_ratio = 0.5 },
                        width = cw, height = ch, radius = T.px("r-thumb"), bg = T.color("surface") }
                end
            end)
        end
        cover = cover or thumb(title, cw)
        local card_inner = K.inner(gw)
        local text_w = card_inner - cw - T.px("sp-4")
        local meta = cur_s and T_(_("%1% · page %2 of %3"), pct, cur_s, tot_s) or (pct .. "%")
        local hero = HorizontalGroup:new{ align = "center", cover, K.hspan("sp-4"), VerticalGroup:new{ align = "left",
            K.text(title, "ui-semibold", "fs-head", "text", text_w),
            K.text(authors, "ui", "fs-md", "text-3", text_w),
            K.vspan("sp-2"),
            P.Bar:new{ width = text_w, height = T.px("sp-1"), pct = pct / 100 },
            K.vspan("sp-1"),
            K.text(meta, "ui", "fs-xs", "text-3", text_w) } }
        local blocks = { VerticalGroup:new{ align = "left", K.vspan("sp-3"), padded(K.card(gw, hero)), K.vspan("sp-3"),
            padded(tiles({ { fmt(parse_dur(v("session"))), _("This session") }, { fmt(parse_dur(v("today"))), _("Today") },
                { fmt(parse_dur(v("total"))), _("With this book") }, { tostring(v("days") or "0"), _("Days") } }, gw)) } }
        if not v("today") then
            -- a book of the lists: no session / today values
            blocks[1] = VerticalGroup:new{ align = "left", K.vspan("sp-3"), padded(K.card(gw, hero)), K.vspan("sp-3"),
                padded(tiles({ { fmt(parse_dur(v("total"))), _("With this book") }, { tostring(v("days") or "0"), _("Days") },
                    { tostring(v("hl") or "0"), _("Highlights") } }, gw)) }
        end
        -- Time
        local rows = {}
        local per_page = parse_dur(v("per_page"))
        table.insert(rows, grow({ label = _("Total time"), trailing = trail(fmt(parse_dur(v("read")))) }, gw))
        if by.per_day then table.insert(rows, grow({ label = _("Average per day"), trailing = trail(fmt(parse_dur(v("per_day")))) }, gw)) end
        if by.per_page then table.insert(rows, grow({ label = _("Average per page"), trailing = trail(fmt_mmss(per_page)) }, gw)) end
        if by.left then
            local lv = v("left")
            local ls = parse_dur(lv)
            table.insert(rows, grow({ label = _("Estimated time left"),
                trailing = trail(ls and fmt(ls) or tostring(lv), cb("left") and info_btn(cb("left")) or nil) }, gw))
        end
        table.insert(blocks, { split = true, label = K.section(_("Time"), W), rows = rows, gw = gw })
        -- Days
        rows = {}
        if by.today then
            table.insert(rows, grow({ label = _("Today"), trailing = trail(fmt(parse_dur(v("today"))) .. " · "
                .. T_(_("%1 pages"), tostring(v("today_pages") or 0)), cb("today") and chev() or nil), callback = cb("today") }, gw))
            used[by.today_pages or 0] = true
        end
        if by.session then
            table.insert(rows, grow({ label = _("This session"), trailing = trail(fmt(parse_dur(v("session"))) .. " · "
                .. T_(_("%1 pages"), tostring(v("session_pages") or 0))) }, gw))
        end
        if by.days then
            table.insert(rows, grow({ label = _("Days reading this book"), trailing = trail(tostring(v("days")), cb("days") and chev() or nil),
                callback = cb("days") }, gw))
        end
        if by.start then table.insert(rows, grow({ label = _("Started"), trailing = trail(rel_date(v("start"))) }, gw)) end
        if by.last then table.insert(rows, grow({ label = _("Last read"), trailing = trail(rel_date(v("last"))) }, gw)) end
        if by.finish then
            table.insert(rows, grow({ label = _("Estimated finish"), trailing = trail(rel_date(v("finish")),
                cb("finish") and info_btn(cb("finish")) or nil) }, gw))
        elseif by.finished then
            table.insert(rows, grow({ label = _("Marked as finished"), trailing = trail(rel_date(v("finished"))) }, gw))
        end
        table.insert(blocks, { split = true, label = K.section(_("Days"), W), rows = rows, gw = gw })
        -- Pages and notes
        rows = {}
        if cur_s then table.insert(rows, grow({ label = _("Current page"), trailing = trail(cur_s .. " / " .. tot_s) }, gw))
        elseif by.page then table.insert(rows, grow({ label = _("Current page"), trailing = trail(tostring(v("page"))) }, gw)) end
        if pages_v then table.insert(rows, grow({ label = _("Pages read"),
            trailing = trail(pr_n and (pr_n .. " · " .. pr_pct .. "%") or tostring(pages_v)) }, gw)) end
        if by.hl then table.insert(rows, grow({ label = _("Highlights"), trailing = trail(tostring(v("hl"))) }, gw)) end
        if by.notes then table.insert(rows, grow({ label = _("Notes"), trailing = trail(tostring(v("notes"))) }, gw)) end
        table.insert(blocks, { split = true, label = K.section(_("Pages and notes"), W), rows = rows, gw = gw })
        -- anything else the plugin listed (kept reachable)
        rows = {}
        for i, pr in ipairs(self.kv_pairs) do
            if type(pr) == "table" and not used[i] and pr[1] and pr[1] ~= "" then
                table.insert(rows, grow({ label = strip_key(pr[1]), trailing = trail(tostring(pr[2] or ""), pr.callback and chev() or nil),
                    callback = self:cb(i), hold = self:hcb(i) }, gw))
            end
        end
        if #rows > 0 then
            table.insert(blocks, K.vspan("sp-3"))
            table.insert(blocks, padded(group(rows, gw)))
        end
        if current and st and st.resetCurrentBook then
            table.insert(blocks, K.vspan("sp-3"))
            table.insert(blocks, padded(group({ grow({ label = _("Reset statistics for this book"), danger = true,
                callback = function() st:resetCurrentBook() end }, gw) }, gw)))
        end
        table.insert(blocks, K.vspan("sp-4"))
        local actions = {}
        if st and st.onShowCalendarView then
            table.insert(actions, K.icon_button("leaf.gs.calendar-days", function() st:onShowCalendarView() end, self))
        end
        self:layout_page{ head = { title = _("Book statistics"), crumbs = { title }, back = self:back(), actions = actions },
            blocks = blocks }
    end

    -- the day timeline of a date (CalendarDayView, Leaf day page)
    function M.open_day(d, crumbs)
        require("calendarview") -- hooks it
        local DV, st = M.CalendarDayView, stats_plugin()
        if not (DV and st) then return end
        local y, mo, dd = d:match("(%d%d%d%d)-(%d%d)-(%d%d)")
        local ts = os.time{ year = tonumber(y), month = tonumber(mo), day = tonumber(dd), hour = 0 }
        UIManager:show(DV:new{ day_ts = ts + (st.settings.calendar_day_start_hour or 0) * 3600
            + (st.settings.calendar_day_start_minute or 0) * 60, reader_statistics = st, color = st.color, _leaf_crumbs = crumbs })
    end

    function StatPage:build()
        local f = BUILD[self.kind] or BUILD.dates
        f(self)
    end

    ------------------------------------------------ which KeyValuePage is which
    local function kind_of(o)
        local t = tostring(o.title or "")
        if t == _("Current statistics") then return "book", true end
        if t == _("Time range statistics") then return "range" end
        if t == _("Reset book statistics") then return "reset" end
        if starts(t, tpl_prefix(_("Total time spent reading: %1"))) then return "all" end
        if starts(t, tpl_prefix(_("Days reading %1"))) then return "dates" end
        if starts(t, tpl_prefix(_("Books read in %1"))) or starts(t, tpl_prefix(_("Books read %1"))) then return "books" end
        if o.single_page then return "book" end
        return "dates"
    end
    local function from_stats()
        for lvl = 3, 8 do
            local info = debug.getinfo(lvl, "S")
            if not info then break end
            if info.source and info.source:find("statistics.koplugin", 1, true) then return true end
        end
        return false
    end
    local KeyValuePage = require("ui/widget/keyvaluepage")
    L.wrap(KeyValuePage, "new", function(orig, cls, o)
        if cls ~= KeyValuePage or type(o) ~= "table" or not from_stats() then return orig(cls, o) end
        local kind, current = kind_of(o)
        local parent = o.callback_return and M.last or nil
        return StatPage:new{ kv = o, kind = kind, current = current, parent = parent }
    end, "KeyValuePage.new (statistics)")

    ------------------------------------------------------------------ calendar (month)
    local function upvalue(fn, wanted)
        local i = 1
        while fn do
            local name, value = debug.getupvalue(fn, i)
            if not name then return end
            if name == wanted then return value end
            i = i + 1
        end
    end

    local BAR = { "accent-soft", "surface-3", "heat-1" }

    -- one day cell: number, hourly histogram, book bars (painted)
    local DayCell = InputContainer:extend{ width = 0, height = 0 }
    function DayCell:init()
        self.dimen = geom(self.width, self.height)
        local range = function() return self.dimen end
        self.ges_events = { TapDay = { GestureRange:new{ ges = "tap", range = range } },
            HoldDay = { GestureRange:new{ ges = "hold", range = range } } }
        self.num = K.text(tostring(self.day), "ui-semibold", "fs-xs", self.future and "disabled" or (self.today and "accent" or "text"))
        self.labels = {}
        for li, b in pairs(self.bars or {}) do
            if b.label then
                self.labels[li] = K.text(b.label, "ui", "fs-2xs", "text", self.width - 2 * T.px("sp-1"))
            end
        end
        if self.more and self.more > 0 then self.more_w = K.text("+" .. self.more, "ui", "fs-2xs", "text-3") end
    end
    function DayCell:getSize() return self.dimen end
    function DayCell:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local w, h = self.width, self.height
        local r = T.px("r-sm")
        local edge = self.today and T.px("bw-lg") or T.px("hairline")
        bb:paintRoundedRect(x, y, w, h, T.color(self.today and "text" or "border"), r)
        bb:paintRoundedRect(x + edge, y + edge, w - 2 * edge, h - 2 * edge, T.color("surface"), math.max(0, r - edge))
        local pad = sc(3)
        local cy = y + T.px("sp-1")
        self.num:paintTo(bb, x + 2 * pad, cy)
        cy = cy + self.num:getSize().h + sc(3)
        if self.hist then
            local hh = sc(10)
            local hx, hw = x + pad + sc(2), w - 2 * pad - 2 * sc(2)
            local bw = hw / 24
            for i = 1, 24 do
                local lv = self.hist[i] or 0
                if lv > 0 then
                    local bh = math.max(1, math.floor(hh * lv / 4 + 0.5))
                    local bx = math.floor(hx + (i - 1) * bw)
                    bb:paintRect(bx, cy + hh - bh, math.max(1, math.floor(hx + i * bw) - bx), bh, T.color("text-3"))
                end
            end
            cy = cy + hh + sc(3)
        end
        local bh = sc(15)
        for li = 1, self.lanes or 0 do
            local b = self.bars and self.bars[li]
            if b then
                local x0 = b.s and (x + pad) or (x + edge)
                local x1 = b.e and (x + w - pad) or (x + w - edge)
                local rr = (b.s or b.e) and T.px("r-tick") or 0
                bb:paintRoundedRect(x0, cy, x1 - x0, bh, T.color(BAR[b.c] or "surface-3"), rr)
                if b.s and not b.e then bb:paintRect(x1 - rr, cy, rr, bh, T.color(BAR[b.c] or "surface-3")) end
                if b.e and not b.s then bb:paintRect(x0, cy, rr, bh, T.color(BAR[b.c] or "surface-3")) end
                local lw = self.labels[li]
                if lw then
                    local lh = lw:getSize().h
                    lw:paintTo(bb, x0 + T.px("sp-1"), cy + math.floor((bh - lh) / 2))
                end
            end
            cy = cy + bh + sc(3)
        end
        if self.more_w then self.more_w:paintTo(bb, x + 2 * pad, cy) end
        if self.future then
            -- .gp-cal-day.fut { opacity: .45 }: wash the cell with the page background
            bb:lightenRect(x, y, w, h, 0.55)
        end
    end
    function DayCell:onTapDay()
        if self.callback then self.callback() end
        return true
    end
    function DayCell:onHoldDay() return self:onTapDay() end

    -- the legend sample (.gp-cal-key i)
    local function sample(color)
        return K.Rect:new{ w = sc(18), h = sc(9), color = T.color(color), radius = T.px("r-tick") }
    end

    local function month_name(ts)
        return (datetime.longMonthTranslation[os.date("%B", ts)] or os.date("%B", ts)) .. os.date(" %Y", ts)
    end
    local function month_ts(ym) return os.time{ year = tonumber(ym:sub(1, 4)), month = tonumber(ym:sub(6, 7)), day = 1, hour = 12 } end

    local function build_calendar(self, CalendarDayView)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local st = self.reader_statistics
        local ratio_by_day = st:getReadingRatioPerHourByDay(self.cur_month) or {}
        local books_by_day = st:getReadBookByDay(self.cur_month) or {}
        local mts = month_ts(self.cur_month)
        local today_s = os.date("%Y-%m-%d")
        local start = self.start_day_of_week or 2
        local lanes = math.max(1, self.nb_book_spans or 2)
        local histo = self.show_hourly_histogram

        -- header: ← November 2026 ······ settings
        local header = K.header{ width = W, title = month_name(mts), back = function() self:onClose() end, parent = self,
            actions = { { "leaf.mn.settings-2", function() M.calendar_settings(self) end } } }
        -- weekday names
        local padx, gap = T.px("sp-3"), T.px("sp-1")
        local cw = math.floor((W - 2 * padx - 6 * gap) / 7)
        padx = math.floor((W - 7 * cw - 6 * gap) / 2)
        local wd = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = padx } }
        for i = 0, 6 do
            local name = self.weekdays[(start - 1 + i) % 7 + 1]
            if i > 0 then table.insert(wd, HorizontalSpan:new{ width = gap }) end
            table.insert(wd, CenterContainer:new{ dimen = geom(cw, sc(22)),
                K.text(datetime.shortDayOfWeekTranslation[name] or name, "ui", "fs-xs", "text-3") })
        end

        -- days of the month, in weeks
        local days = {}
        local t = os.date("*t", mts)
        local month = t.month
        local ts = mts
        while os.date("*t", ts).month == month do
            local d = os.date("*t", ts)
            table.insert(days, { day = d.day, wday = d.wday, s = os.date("%Y-%m-%d", ts),
                ts = os.time{ year = d.year, month = d.month, day = d.day, hour = 0 } })
            ts = ts + 86400
        end
        local weeks, cur = {}, nil
        for _i, d in ipairs(days) do
            if not cur or d.wday == start then
                cur = {}
                table.insert(weeks, cur)
                local col = (d.wday - start) % 7
                for c = 1, col do cur[c] = false end
            end
            table.insert(cur, d)
        end
        -- book colours: the open book first (accent tint), then the others in turn
        local colour, order = {}, {}
        local cur_id = st.id_curr_book
        local function colour_of(id, title)
            if not colour[id] then
                if id == cur_id then colour[id] = 1 else
                    local n = 0
                    for _k, c in pairs(colour) do if c ~= 1 then n = n + 1 end end
                    colour[id] = n % 2 + 2
                end
                table.insert(order, { id = id, title = title })
            end
            return colour[id]
        end
        if cur_id then
            for _i, d in ipairs(days) do
                for _j, b in ipairs(books_by_day[d.s] or {}) do if b.id == cur_id then colour_of(b.id, b.title) end end
            end
        end
        -- per week: book runs on consecutive days, given a lane each (at most `lanes` lanes)
        local cell_bars, cell_more = {}, {}
        for _w, wk in ipairs(weeks) do
            local runs = {}
            local open = {}
            for c = 1, 7 do
                local d = wk[c]
                local here = {}
                for _j, b in ipairs(d and books_by_day[d.s] or {}) do here[b.id] = b end
                for id, r in pairs(open) do
                    if not here[id] then open[id] = nil end
                end
                for id, b in pairs(here) do
                    if open[id] then open[id].e = c
                    else
                        open[id] = { id = id, title = b.title, s = c, e = c }
                        table.insert(runs, open[id])
                    end
                end
            end
            table.sort(runs, function(a, b) if a.s ~= b.s then return a.s < b.s end return (a.e - a.s) > (b.e - b.s) end)
            local busy = {}
            for _r, run in ipairs(runs) do
                local lane
                for ln = 1, lanes do
                    local free = true
                    for c = run.s, run.e do if busy[ln .. ":" .. c] then free = false break end end
                    if free then lane = ln break end
                end
                local c_idx = colour_of(run.id, run.title)
                for c = run.s, run.e do
                    local d = wk[c]
                    if d then
                        if lane then
                            busy[lane .. ":" .. c] = true
                            cell_bars[d.s] = cell_bars[d.s] or {}
                            cell_bars[d.s][lane] = { c = c_idx, s = c == run.s, e = c == run.e,
                                label = (c == run.s) and run.title or nil }
                        else
                            cell_more[d.s] = (cell_more[d.s] or 0) + 1
                        end
                    end
                end
            end
        end
        -- legend
        local groups = { {}, {}, {} }
        for _i, b in ipairs(order) do table.insert(groups[colour[b.id]], b.title) end

        -- sizes: cells as tall as the prototype (88px) unless the screen is short
        local status = Kit.status_strip(W)
        local pager_h = T.px("h-row") + T.px("hairline")
        local legend_items = {}
        for c = 1, 3 do
            if #groups[c] > 0 then table.insert(legend_items, { BAR[c], table.concat(groups[c], " · ") }) end
        end
        if histo then table.insert(legend_items, { "text-3", _("Reading by hour") }) end
        local legend = VerticalGroup:new{ align = "left" }
        local line = HorizontalGroup:new{ align = "center" }
        local used = 0
        local lw = W - 2 * T.px("sp-4")
        for _i, it in ipairs(legend_items) do
            local item = HorizontalGroup:new{ align = "center", it[1] == "text-3" and K.Rect:new{ w = sc(18), h = sc(9), color = T.color("text-3") } or sample(it[1]),
                K.hspan("sp-1h"), K.text(it[2], "ui", "fs-xs", "text-3", lw - sc(24)) }
            local iw = item:getSize().w
            item:resetLayout()
            if used > 0 and used + T.px("sp-4") + iw > lw then
                table.insert(legend, line)
                table.insert(legend, K.vspan("sp-2"))
                line = HorizontalGroup:new{ align = "center" }
                used = 0
            end
            if used > 0 then table.insert(line, K.hspan("sp-4")) used = used + T.px("sp-4") end
            table.insert(line, item)
            used = used + iw
        end
        if used > 0 then table.insert(legend, line) end
        local fixed_h = status:getSize().h + T.px("h-header") + sc(22) + T.px("sp-2") + T.px("hairline")
        local legend_h = legend:getSize().h + T.px("sp-1") + T.px("sp-4")
        legend:resetLayout()
        local avail = H - fixed_h - pager_h - legend_h - 2 * T.px("sp-2")
        local cell_h = math.min(sc(88), math.floor((avail - (#weeks - 1) * gap) / #weeks))

        local grid = VerticalGroup:new{ align = "left" }
        for wi, wk in ipairs(weeks) do
            if wi > 1 then table.insert(grid, VerticalSpan:new{ width = gap }) end
            local row = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = padx } }
            for c = 1, 7 do
                if c > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                local d = wk[c]
                if d then
                    local future = d.s > today_s
                    local hist
                    local ratios = ratio_by_day[d.s]
                    if histo and ratios and not future then
                        hist = {}
                        local any = false
                        for h = 1, 24 do
                            local rr = tonumber(ratios[h]) or 0
                            hist[h] = rr > 0 and math.max(1, math.min(4, math.ceil(rr * 4))) or 0
                            if hist[h] > 0 then any = true end
                        end
                        if not any then hist = nil end
                    end
                    local day_ts = d.ts
                    table.insert(row, DayCell:new{ width = cw, height = cell_h, day = d.day, today = d.s == today_s,
                        future = future, hist = hist, bars = cell_bars[d.s], more = cell_more[d.s], lanes = lanes,
                        callback = (not future) and function()
                            if not CalendarDayView then return end
                            UIManager:show(CalendarDayView:new{
                                day_ts = day_ts + (st.settings.calendar_day_start_hour or 0) * 3600
                                    + (st.settings.calendar_day_start_minute or 0) * 60,
                                reader_statistics = st,
                                close_callback = function(this)
                                    UIManager:tickAfterNext(function() self:goToMonth(os.date("%Y-%m", this.day_ts + 10800)) end)
                                end,
                                min_month = self.min_month,
                                color = st.color,
                                _leaf_crumbs = { _("Statistics"), _("Calendar") },
                            })
                        end or nil })
                else
                    table.insert(row, HorizontalSpan:new{ width = cw })
                end
            end
            table.insert(grid, row)
        end

        -- pager: previous month · « ‹ 2026-11 › »
        local can_prev = self.cur_month > self.min_month
        local can_next = self.cur_month < self.max_month or self.browse_future_months
        local prev_ts = month_ts(self.cur_month) - 20 * 86400
        local ym = K.tap(CenterContainer:new{ dimen = geom(sc(72), T.px("hit")),
            K.text(self.cur_month, "ui", "fs-sm", "text") }, function() M.enter_month(self) end)
        local foot = pager(W, can_prev and month_name(prev_ts) or nil, {
            chev_btn("leaf.sk.left10", can_prev, function() self:goToMonth(self.min_month) end),
            chev_btn("chevron.left", can_prev, function() self:prevMonth() end),
            ym,
            chev_btn("chevron.right", can_next, function() self:nextMonth() end),
            chev_btn("leaf.sk.right10", can_next, function() self:goToMonth(self.max_month) end) })

        local body = VerticalGroup:new{ align = "left", status, header, wd, K.vspan("sp-2"), K.line(W),
            K.vspan("sp-2"), grid, K.vspan("sp-1"), padded(legend) }
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), width = W, height = H,
            OverlapGroup:new{ dimen = geom(W, H), body, BottomContainer:new{ dimen = geom(W, H), foot } } }
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end

    function M.enter_month(view)
        local InputDialog = require("ui/widget/inputdialog")
        local d
        d = InputDialog:new{ title = _("Enter month"), input = view.cur_month, input_hint = "YYYY-MM",
            buttons = { { { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
                { text = _("Go"), is_enter_default = true, callback = function()
                    local s = d:getInputText()
                    local y, m = s:match("^(%d%d%d%d)-(%d%d)$")
                    UIManager:close(d)
                    if y and tonumber(m) >= 1 and tonumber(m) <= 12 and tonumber(y) >= 1000 then
                        view:goToMonth(s)
                    else
                        UIManager:show(require("ui/widget/infomessage"):new{ text = _("Invalid year-month string (YYYY-MM)") })
                    end
                end } } } }
        UIManager:show(d)
        d:onShowKeyboard()
    end

    ------------------------------------------------------------------ calendar settings sheet
    local CalSettings = InputContainer:extend{ view = nil, _leaf_wants_scrim = true }
    function CalSettings:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(W, H)
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end
    function CalSettings:apply()
        local v, s = self.view, self.view.reader_statistics.settings
        v.start_day_of_week = s.calendar_start_day_of_week
        v.nb_book_spans = s.calendar_nb_book_spans
        v.show_hourly_histogram = s.calendar_show_histogram
        v.browse_future_months = s.calendar_browse_future_months
        v:_populateItems()
        self:build()
        UIManager:setDirty("all", "ui")
    end
    function CalSettings:build()
        local W = Screen:getWidth()
        local inner = Kit.inner(W)
        local s = self.view.reader_statistics.settings
        local head = Kit.head{ width = inner, title = _("Calendar settings"), parent = self,
            on_close = function() UIManager:close(self) end }
        -- weeks start on: the plugin's four choices
        local LeafSeg = require("leaf/widgets/seg")
        local items = {}
        for _i, wd in ipairs({ 6, 7, 1, 2 }) do
            table.insert(items, { label = datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[wd]], key = wd })
        end
        local seg = LeafSeg:new{ width = sc(68) * #items, items = items, selected = s.calendar_start_day_of_week,
            on_select = function(key) s.calendar_start_day_of_week = key; self:apply() end }
        local rh = T.px("h-row") + T.px("sp-2")
        local seg_row = OverlapGroup:new{ dimen = geom(inner, rh),
            LeftContainer:new{ dimen = geom(inner, rh), HorizontalGroup:new{ K.hspan("sp-5"), K.text(_("Weeks start on"), "ui", "fs-md", "text") } },
            RightContainer:new{ dimen = geom(inner, rh), HorizontalGroup:new{ seg, K.hspan("sp-5") } } }
        local n = s.calendar_nb_book_spans or 3
        local slider
        slider = Kit.slider_row{ width = inner, label = _("Books per day"), pct = (n - 1) / 4, value = n, parent = self,
            on_change = function(frac, final)
                local nv = math.max(1, math.min(5, 1 + math.floor(frac * 4 + 0.5)))
                if final then s.calendar_nb_book_spans = nv; self:apply()
                else slider:set((nv - 1) / 4, nv); UIManager:setDirty(self, "ui") end
            end,
            on_step = function(dir)
                s.calendar_nb_book_spans = math.max(1, math.min(5, n + (dir > 0 and 1 or -1)))
                self:apply()
            end }
        local gw = inner - 2 * T.px("sp-4")
        local function tg(icon, label, key, sub)
            return grow({ icon = icon, label = label, sub = sub, trailing = require("leaf/widgets/toggle"):new{ on = s[key] and true or false, enabled = true },
                callback = function() s[key] = not s[key]; self:apply() end }, gw)
        end
        local start = string.format("%02d:%02d", s.calendar_day_start_hour or 0, s.calendar_day_start_minute or 0)
        local rows = {
            tg("leaf.gs.chart", _("Show reading by hour in each day"), "calendar_show_histogram"),
            tg("leaf.gs.calendar-plus", _("Allow browsing coming months"), "calendar_browse_future_months"),
            grow({ icon = "leaf.gs.sunrise", label = _("Days start at"), trailing = trail(start, chev()),
                callback = function() M.day_start(s, function() self:apply() end) end }, gw),
            tg("leaf.gs.calendar-days", _("Use that start in the calendar too"), "calendar_use_day_time_shift",
                _("Reading after midnight counts for the evening before")),
        }
        local content = VerticalGroup:new{ align = "left", head, K.vspan("sp-1"), seg_row, K.vspan("sp-2"), slider,
            K.vspan("sp-2"), padded(group(rows, gw)), K.vspan("sp-2") }
        local frame, container = Kit.sheet{ width = W, content = content }
        self._frame = frame
        self[1] = container
    end
    function CalSettings:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then UIManager:close(self) end
        return true
    end
    function CalSettings:onClose() UIManager:close(self) return true end
    function CalSettings:onShow() UIManager:setDirty(self, "ui") return true end
    function CalSettings:onCloseWidget() UIManager:setDirty(nil, "ui") end
    function M.calendar_settings(view)
        UIManager:show(CalSettings:new{ view = view })
    end

    function M.day_start(s, done)
        local DateTimeWidget = require("ui/widget/datetimewidget")
        UIManager:show(DateTimeWidget:new{
            hour = s.calendar_day_start_hour or 0, min = s.calendar_day_start_minute or 0,
            min_max = 50, min_step = 10, min_hold_step = 30,
            ok_text = _("Set time"), title_text = _("Daily timeline starts at"),
            info_text = _([[
Set the time when the daily timeline should start.

If you read past midnight, and would like this reading session to be displayed on the same screen with your previous evening reading sessions, use a value such as 04:00.

Time is in hours and minutes.]]),
            callback = function(time)
                s.calendar_day_start_hour = time.hour
                s.calendar_day_start_minute = time.min
                if done then done() end
            end })
    end

    ------------------------------------------------------------------ day timeline
    local Track = Widget:extend{ width = 0, height = 0, blocks = nil, now = nil }
    function Track:getSize() return geom(self.width, self.height) end
    function Track:paintTo(bb, x, y)
        local h = self.height
        local hl = T.px("hairline")
        bb:paintRect(x, y, hl, h, T.color("border"))
        bb:paintRect(x, y + h - hl, self.width, hl, T.color("border"))
        local inset = sc(2)
        for _i, b in ipairs(self.blocks or {}) do
            local bx = x + math.floor(b.f0 * self.width)
            local bw = math.max(sc(3), math.floor((b.f1 - b.f0) * self.width))
            bb:paintRoundedRect(bx, y + inset, math.min(bw, x + self.width - bx), h - 2 * inset, T.color(b.color), T.px("r-tick"))
        end
        if self.now then
            local nx = x + math.floor(self.now * self.width)
            bb:paintRect(nx, y - sc(3), T.px("bw-lg"), h + 2 * sc(3), T.color("text"))
        end
    end

    local function build_day(self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local st = self.reader_statistics
        local s = st.settings
        local start_h, start_m = s.calendar_day_start_hour or 0, s.calendar_day_start_minute or 0
        local day_ts = self.day_ts - start_h * 3600 - start_m * 60
        local dt = os.date("*t", day_ts + 10800)
        local title = string.format("%s %d %s", datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[dt.wday]] or os.date("%A", day_ts + 10800),
            dt.day, datetime.longMonthTranslation[os.date("%B", day_ts + 10800)] or os.date("%B", day_ts + 10800))
        -- totals
        local total, pages, sessions = 0, 0, 0
        local sw_color = { "text", "text-3" }
        local rows = {}
        local gw = W - 2 * T.px("sp-4")
        for i, kv in ipairs(self.kv_pairs) do
            local label, p, sec = dur_pages(kv[2])
            total = total + (kv.duration or sec or 0)
            pages = pages + (p or 0)
            sessions = sessions + #(kv.periods or {})
            local check = K.tap(CenterContainer:new{ dimen = geom(sc(36), T.px("h-row")),
                Kit.icon(kv.checked and "leaf.check.on" or "leaf.check.off", "icon-md") }, function()
                    if kv.check_cb then kv:check_cb() end
                end)
            local sw = K.Rect:new{ w = sc(12), h = sc(12), color = T.color(sw_color[(i - 1) % 2 + 1]), radius = T.px("r-tick") }
            table.insert(rows, grow({ lead = sw, label = tostring(kv[1]), sub = label, trailing = check,
                callback = kv.callback and function() kv:callback() end or nil,
                hold = kv.hold_callback and function() kv.hold_callback(self, kv) end or nil }, gw))
        end
        local blocks = VerticalGroup:new{ align = "left", K.vspan("sp-3"),
            padded(tiles({ { fmt(total), _("Read") }, { tostring(pages), _("Pages") }, { tostring(#self.kv_pairs), _("Books") },
                { tostring(sessions), _("Sessions") } }, gw)), K.vspan("sp-1") }
        if #rows > 0 then table.insert(blocks, padded(group(rows, gw))) end
        -- timeline head
        local th = sc(44)
        local link = K.tap(HorizontalGroup:new{ align = "center",
            K.text(T_(_("Day starts at %1"), string.format("%02d:%02d", start_h, start_m)), "ui-medium", "fs-sm", "text") },
            function() M.day_start(s, function() self:setupView() end) end)
        table.insert(blocks, OverlapGroup:new{ dimen = geom(W, th),
            LeftContainer:new{ dimen = geom(W, th), HorizontalGroup:new{ K.hspan("sp-5"), K.text(_("Timeline"):upper(), "ui-semibold", "fs-xs", "text-3") } },
            RightContainer:new{ dimen = geom(W, th), HorizontalGroup:new{ link, K.hspan("sp-5") } } })
        -- footer pager: ‹ 19 of 30 ›
        local month_days = os.date("*t", os.time{ year = dt.year, month = dt.month + 1, day = 0, hour = 12 }).day
        local now = os.time()
        local is_today = now >= self.day_ts and now < self.day_ts + 86400
        local can_next = self.day_ts + 86400 < now
        local can_prev = self.day_ts - 82800 >= (self.min_ts or 0)
        local hit = T.px("hit")
        local foot_h = T.px("h-row")
        local foot = VerticalGroup:new{ K.line(W), FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"),
            OverlapGroup:new{ dimen = geom(W, foot_h),
                CenterContainer:new{ dimen = geom(W, foot_h), K.text(T_(_("%1 of %2"), dt.day, month_days), "ui", "fs-sm", "text-3") },
                LeftContainer:new{ dimen = geom(W, foot_h), HorizontalGroup:new{ K.hspan("sp-3"),
                    chev_btn("chevron.left", can_prev, function() self:onPrevPage() end) } },
                RightContainer:new{ dimen = geom(W, foot_h), HorizontalGroup:new{
                    chev_btn("chevron.right", can_next, function() self:onNextPage() end), K.hspan("sp-3") } } } } }
        -- timeline: 24 lines from the day start, as many as fit the prototype's 22px each
        local head = page_head({ title = title, crumbs = self._leaf_crumbs or { _("Statistics"), _("Calendar") },
            back = function() self:onClose() end }, W, self)
        local status = Kit.status_strip(W)
        local top_h = status:getSize().h + head:getSize().h + blocks:getSize().h
        blocks:resetLayout()
        local avail = H - top_h - foot_h - T.px("hairline") - T.px("sp-3")
        local line_h = math.max(sc(12), math.min(sc(22), math.floor(avail / 24)))
        local lab_w = sc(36)
        local track_w = W - 2 * T.px("sp-5") - lab_w - T.px("sp-2")
        local tl = VerticalGroup:new{ align = "left" }
        local now_frac
        if is_today then now_frac = (now - self.day_ts) / 3600 end
        for i = 0, 23 do
            local s0, s1 = i * 3600, (i + 1) * 3600
            local blk = {}
            for bi, kv in ipairs(self.kv_pairs) do
                if kv.checked then
                    for _p, per in ipairs(kv.periods or {}) do
                        local a, b = math.max(per.start, s0), math.min(per.finish, s1)
                        if b > a then
                            table.insert(blk, { f0 = (a - s0) / 3600, f1 = (b - s0) / 3600, color = sw_color[(bi - 1) % 2 + 1] })
                        end
                    end
                end
            end
            local hh = (start_h + i) % 24
            local track = Track:new{ width = track_w, height = math.min(sc(14), line_h - sc(4)), blocks = blk,
                now = (now_frac and now_frac >= i and now_frac < i + 1) and (now_frac - i) or nil }
            table.insert(tl, LeftContainer:new{ dimen = geom(W, line_h), HorizontalGroup:new{ align = "center", K.hspan("sp-5"),
                LeftContainer:new{ dimen = geom(lab_w, line_h), K.text(string.format("%02d:%02d", hh, start_m), "ui", "fs-2xs", "text-3") },
                K.hspan("sp-2"), track } })
        end
        local body = VerticalGroup:new{ align = "left", status, head, blocks, tl }
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), width = W, height = H,
            OverlapGroup:new{ dimen = geom(W, H), body, BottomContainer:new{ dimen = geom(W, H), foot } } }
        UIManager:setDirty(self, "ui")
    end

    ------------------------------------------------------------------ hooks on the plugin's calendar
    local function hook_calendar(CalendarView)
        if type(CalendarView) ~= "table" or not CalendarView._populateItems then return end
        -- (_populateItems is already wrapped by stats.lua: read the class from an unwrapped method)
        local CalendarDayView = upvalue(CalendarView.showCalendarDayView, "CalendarDayView")
            or upvalue(CalendarView._populateItems, "CalendarDayView")
        M.CalendarDayView = CalendarDayView
        L.wrap(CalendarView, "init", function(orig, self)
            self.dimen = geom(Screen:getWidth(), Screen:getHeight())
            self.covers_fullscreen = true
            if Device:hasKeys() then
                self.key_events.Close = { { Device.input.group.Back } }
                self.key_events.NextMonth = { { Device.input.group.PgFwd } }
                self.key_events.PrevMonth = { { Device.input.group.PgBack } }
            end
            if Device:isTouchDevice() then
                self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
                self.ges_events.MultiSwipe = { GestureRange:new{ ges = "multiswipe", range = self.dimen } }
            end
            local now = os.time()
            self.min_month = os.date("%Y-%m", self.reader_statistics:getFirstTimestamp() or now)
            self.max_month = os.date("%Y-%m", now)
            if self.min_month > self.max_month then self.min_month = self.max_month end
            self.cur_month = self.cur_month or self.max_month
            self.layout = {}
            self:_populateItems()
        end, "CalendarView:init (Leaf month)")
        L.wrap(CalendarView, "_populateItems", function(orig, self)
            build_calendar(self, CalendarDayView)
        end, "CalendarView:_populateItems (Leaf month)")

        if CalendarDayView then
            L.wrap(CalendarDayView, "init", function(orig, self)
                self.dimen = geom(Screen:getWidth(), Screen:getHeight())
                self.covers_fullscreen = true
                if Device:hasKeys() then
                    self.key_events.Close = { { Device.input.group.Back } }
                    self.key_events.NextPage = { { Device.input.group.PgFwd } }
                    self.key_events.PrevPage = { { Device.input.group.PgBack } }
                end
                if Device:isTouchDevice() then
                    self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
                end
                self.ges_events.MultiSwipe = { GestureRange:new{ ges = "multiswipe", range = self.dimen } }
                local min_month = self.min_month or os.date("%Y-%m", self.reader_statistics:getFirstTimestamp() or os.time())
                self.min_ts = os.time{ year = tonumber(min_month:sub(1, 4)), month = tonumber(min_month:sub(6)), day = 0 }
                self.layout = {}
                self:setupView()
            end, "CalendarDayView:init (Leaf day)")
            L.wrap(CalendarDayView, "setupView", function(orig, self)
                self.kv_pairs = self.reader_statistics:getBooksFromPeriod(self.day_ts, self.day_ts + 86400)
                local seconds_books = self.reader_statistics:getReadingDurationBySecond(self.day_ts)
                for _i, kv in ipairs(self.kv_pairs) do
                    if seconds_books[kv.book_id] then kv.periods = seconds_books[kv.book_id].periods end
                    kv.checked = true
                    kv.check_cb = function(this)
                        this.checked = not this.checked
                        build_day(self)
                    end
                end
                table.sort(self.kv_pairs, function(a, b) return (a.duration or 0) > (b.duration or 0) end)
                self.title = self:getTitle()
                self.show_page, self.pages = 1, 1
                build_day(self)
            end, "CalendarDayView:setupView (Leaf day)")
            L.wrap(CalendarDayView, "_populateBooks", function(orig, self) build_day(self) end, "CalendarDayView:_populateBooks (Leaf day)")
            L.wrap(CalendarDayView, "refreshTimeline", function(orig, self) build_day(self) end, "CalendarDayView:refreshTimeline (Leaf day)")
        end
    end

    -- the plugin loads after the patches: hook calendarview when it is first required
    local hooked = false
    local orig_require = require
    _G.require = function(name, ...)
        local mod = orig_require(name, ...)
        if name == "calendarview" and not hooked then
            hooked = true
            local ok, err = pcall(hook_calendar, mod)
            if ok then L.log("statpages: hooked calendarview") else L.err("statpages: hook failed:", err) end
        end
        return mod
    end
    if package.loaded["calendarview"] then
        hooked = true
        pcall(hook_calendar, package.loaded["calendarview"])
    end
end

return M
