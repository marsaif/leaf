--[[
    Leaf home (prototype screen "home"): a full-screen page over the file manager, opened from the
    bottom navigation (leaf/widgets/bottomnav.lua) of the library screens.

      header:   date eyebrow (.ko-eyebrow) + greeting (Playfair --fs-display); search · frontlight · ☰
      hero:     .ko-card — cover (tap: book details) · CONTINUE READING eyebrow · title (Playfair) ·
                author · page x of y · progress + % · time left in book (statistics) ·
                Resume (primary) · Details (ghost) · ⋮ (the library's long-press book dialog)
      stats:    Today (minutes vs goal, 7-day bars, pages this week, pages/h) · Streak (days, week
                dots, best streak, books this year) — from the statistics plugin's database
                (statistics.sqlite3, read only); tap = its calendar view
      recent:   "Recently read" + History ›, up to 5 covers with % badge, title, thin progress
      nav:      Home (active) · Library · History · Settings
    Data: ReadHistory (last books), BookList / DocSettings (progress, status), PT's cache (title,
    authors, covers). Books open with ReaderUI:showReader().
--]]
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local Screen = Device.screen

local M = {}
local instance

local function fm() return require("apps/filemanager/filemanager").instance end

---------------------------------------------------------------- statistics (read only)
local function day_start(t)
    local d = os.date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end

local function read_stats(md5)
    local out = { today = 0, week = { 0, 0, 0, 0, 0, 0, 0 }, pages_week = 0, secs_week = 0,
        streak = 0, best = 0, books_year = 0 }
    local DataStorage = require("datastorage")
    local path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if not require("libs/libkoreader-lfs").attributes(path, "mode") then return out end
    local SQ3 = require("lua-ljsqlite3/init")
    local ok, err = pcall(function()
        local conn = SQ3.open(path)
        local now = os.time()
        local today0 = day_start(now)
        local week0 = today0 - 6 * 86400
        -- minutes per day, last 7 days (oldest first)
        local res = conn:exec(string.format([[
            SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS d, sum(duration), count(DISTINCT id_book || ':' || page)
            FROM page_stat_data WHERE start_time >= %d GROUP BY d;]], week0))
        local by_day = {}
        if res then
            for i = 1, #res[1] do by_day[res[1][i]] = { tonumber(res[2][i]) or 0, tonumber(res[3][i]) or 0 } end
        end
        for i = 1, 7 do
            local t = week0 + (i - 1) * 86400 + 3600 * 12
            local v = by_day[os.date("%Y-%m-%d", t)]
            out.week[i] = v and math.floor(v[1] / 60 + 0.5) or 0
            if v then
                out.pages_week = out.pages_week + v[2]
                out.secs_week = out.secs_week + v[1]
            end
        end
        out.today = out.week[7]
        -- streaks from the distinct reading days
        local days = conn:exec([[SELECT DISTINCT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS d
            FROM page_stat_data ORDER BY d;]])
        if days then
            local set, prev_t, run = {}, nil, 0
            for _i, d in ipairs(days[1]) do
                set[d] = true
                local y, m, dd = d:match("(%d+)-(%d+)-(%d+)")
                local t = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 }
                if prev_t and math.abs(t - prev_t - 86400) < 7200 then run = run + 1 else run = 1 end
                out.best = math.max(out.best, run)
                prev_t = t
            end
            local t = now
            if not set[os.date("%Y-%m-%d", t)] then t = t - 86400 end -- today not read yet: count up to yesterday
            while set[os.date("%Y-%m-%d", t)] do
                out.streak = out.streak + 1
                t = t - 86400
            end
        end
        local year0 = os.time{ year = tonumber(os.date("%Y")), month = 1, day = 1, hour = 0 }
        out.books_year = tonumber(conn:rowexec(string.format(
            "SELECT count(DISTINCT id_book) FROM page_stat_data WHERE start_time >= %d;", year0))) or 0
        -- this book: seconds per page
        if md5 and md5:match("^%x+$") then
            local t, p = conn:rowexec(string.format(
                "SELECT total_read_time, total_read_pages FROM book WHERE md5 = '%s' ORDER BY last_open DESC LIMIT 1;", md5))
            t, p = tonumber(t), tonumber(p)
            if t and p and p > 0 then out.secs_per_page = t / p end
        end
        conn:close()
    end)
    if not ok then require("leaf/core").err("home: statistics", err) end
    return out
end

local function dur(min)
    local h, m = math.floor(min / 60), min % 60
    if h > 0 then return m > 0 and string.format("%d h %d min", h, m) or string.format("%d h", h) end
    return string.format("%d min", m)
end

---------------------------------------------------------------- the page
function M.apply(L)
    local T = L.T
    local P = require("leaf/widgets/libparts")
    local LeafNav = require("leaf/widgets/bottomnav")
    local IconButton = require("ui/widget/iconbutton")
    local IconWidget = require("ui/widget/iconwidget")
    local Button = require("ui/widget/button")

    local function text(t, role, size, color, max_w)
        return TextWidget:new{ text = t, face = L.face(role, size), fgcolor = T.color(color or "text"), padding = 0, max_width = max_w }
    end
    local function icon(name, size)
        local s = T.px(size or "icon-xs")
        return IconWidget:new{ icon = name, width = s, height = s, alpha = true }
    end
    local function icon_text(ic, t, color)
        return HorizontalGroup:new{ align = "center", icon(ic), HorizontalSpan:new{ width = P.px(5) },
            text(t, "ui", "fs-sm", color or "text-3") }
    end
    -- .ko-card: --surface, hairline --border, --r-lg, --sp-4 padding
    local function card(content, w, pad)
        pad = pad or T.px("sp-4")
        return FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = pad, margin = 0, width = w,
            content }
    end
    local function row_lr(w, h, left, right)
        return OverlapGroup:new{ dimen = Geom:new{ w = w, h = h },
            LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, left },
            RightContainer:new{ dimen = Geom:new{ w = w, h = h }, right } }
    end

    -- 7-day bars (.hm-bars): --surface-3 bars, met goal --text-3, today accent; dashed goal line
    local Bars = Widget:extend{ width = 100, height = 60, values = nil, goal = 45, labels = nil }
    function Bars:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
        self.label_h = P.px(16)
        self._labels = {}
        for i, l in ipairs(self.labels) do
            self._labels[i] = text(l, i == 7 and "ui-semibold" or "ui", "fs-2xs", i == 7 and "text" or "text-3")
        end
    end
    function Bars:getSize() return self.dimen end
    function Bars:paintTo(bb, x, y)
        local n = #self.values
        local gap = T.px("sp-1h")
        local col = math.floor((self.width - (n - 1) * gap) / n)
        local bw = math.min(col, P.px(14))
        local ch = self.height - self.label_h
        local max = self.goal
        for _i, v in ipairs(self.values) do max = math.max(max, v) end
        for i, v in ipairs(self.values) do
            local cx = x + (i - 1) * (col + gap)
            local bh = math.max(P.px(4), math.floor(ch * v / max))
            local c = i == n and "accent" or (v >= self.goal and "text-3" or "surface-3")
            bb:paintRoundedRect(cx + math.floor((col - bw) / 2), y + ch - bh, bw, bh, T.color(c), T.px("r-thumb"))
            local lw = self._labels[i]:getSize().w
            self._labels[i]:paintTo(bb, cx + math.floor((col - lw) / 2), y + ch + P.px(4))
        end
        -- dashed goal line
        local gy = y + ch - math.floor(ch * self.goal / max)
        local dash = P.px(3)
        for gx = x, x + self.width - dash, 2 * dash do
            bb:paintRect(gx, gy, dash, T.px("hairline"), T.color("border-strong"))
        end
    end

    -- streak dots (.hm-dots): 12px circles, --bw-md --border-strong ring, accent when read
    local Dots = Widget:extend{ on = 0, n = 7 }
    function Dots:init()
        self.s = P.px(12)
        self.gap = P.px(5)
        self.dimen = Geom:new{ x = 0, y = 0, w = self.n * self.s + (self.n - 1) * self.gap, h = self.s }
    end
    function Dots:getSize() return self.dimen end
    function Dots:paintTo(bb, x, y)
        for i = 1, self.n do
            local dx = x + (i - 1) * (self.s + self.gap)
            if i <= self.on then
                bb:paintRoundedRect(dx, y, self.s, self.s, T.color("accent"), math.floor(self.s / 2))
            else
                bb:paintBorder(dx, y, self.s, self.s, T.px("bw-md"), T.color("border-strong"), math.floor(self.s / 2))
            end
        end
    end

    -- the current-% badge on a cover (.ko-badge): pill, --surface on --text
    local function badge(t)
        local tw = text(t, "ui-semibold", "fs-2xs", "text")
        local sz = tw:getSize()
        return FrameContainer:new{ bordersize = 0, background = T.color("surface"), radius = math.floor(T.px("h-badge") / 2),
            padding = 0, padding_left = P.px(7), padding_right = P.px(7), margin = 0,
            require("ui/widget/container/centercontainer"):new{ dimen = Geom:new{ w = sz.w, h = T.px("h-badge") }, tw } }
    end

    local Home = InputContainer:extend{ covers_fullscreen = true, name = "leaf_home" }

    function Home:init()
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end

    local function open_book(file)
        M.close()
        require("apps/reader/readerui"):showReader(file)
    end
    local function details(file)
        local f = fm()
        if f and f.bookinfo then f.bookinfo:show(file) end
    end
    local function book_menu(file)
        local f = fm()
        if f and f.file_chooser and f.file_chooser.showFileDialog then
            f.file_chooser:showFileDialog({ path = file, is_file = true, text = file:match("([^/]+)$") })
        end
    end

    function Home:build()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pad = T.px("sp-5")
        local inner_w = W - 2 * pad
        local s = T.px("icon-md")
        local bp = math.floor((T.px("hit") - s) / 2)
        local function icon_button(ic, cb)
            return IconButton:new{ icon = ic, width = s, height = s, padding = bp, callback = cb, show_parent = self }
        end

        -- books: history order, existing files only
        local books = {}
        local lfs = require("libs/libkoreader-lfs")
        for _i, v in ipairs(require("readhistory").hist) do
            if not v.dim and v.file and lfs.attributes(v.file, "mode") == "file" then
                table.insert(books, v.file)
                if #books >= 6 then break end
            end
        end
        local cur = books[1] and P.bookInfo(books[1])
        local stats = read_stats(cur and cur.md5)

        -- header (.hm-head): eyebrow date + greeting
        local hour = tonumber(os.date("%H"))
        local greet = hour < 5 and _("Good night") or hour < 12 and _("Good morning") or hour < 18 and _("Good afternoon") or _("Good evening")
        local date = os.date("%A, %d %B"):gsub(" 0", " "):upper()
        local head_left = VerticalGroup:new{ align = "left",
            text(date, "ui-semibold", "fs-xs", "text-3"),
            VerticalSpan:new{ width = T.px("sp-half") },
            text(greet, "display-semibold", "fs-display", "text") }
        local head_right = HorizontalGroup:new{ align = "center",
            icon_button("appbar.search", function()
                M.close()
                if fm() and fm().filesearcher then fm().filesearcher:onShowFileSearch() end
            end),
            icon_button("leaf.lib.sun", function() UIManager:broadcastEvent(Event:new("ShowFlDialog")) end),
            icon_button("appbar.menu", function() if fm() then fm().menu:onShowMenu() end end),
            HorizontalSpan:new{ width = pad - bp } }
        local hh = math.max(P.px(68), head_left:getSize().h + T.px("sp-2"))
        local header = OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, head_left } },
            RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, head_right } }

        local body = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-3") }, header, VerticalSpan:new{ width = T.px("sp-2") } }
        local function add(w, gap_after)
            table.insert(body, HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, w })
            table.insert(body, VerticalSpan:new{ width = gap_after or T.px("sp-4") })
        end

        -- hero card (.hm-hero)
        if cur then
            local cpad = T.px("sp-4")
            local cw = P.px(128)
            local ch = math.floor(cw * 1.5)
            local col_w = inner_w - 2 * cpad - 2 * T.px("hairline") - cw - T.px("sp-5")
            local cover = P.Tap:new{ content = P.coverBox(cur.file, cw, ch, { title = cur.title, bg = T.color("surface") }),
                callback = function() details(cur.file) end }
            local col = VerticalGroup:new{ align = "left",
                HorizontalGroup:new{ align = "center", icon("leaf.lib.bookopen"), HorizontalSpan:new{ width = T.px("sp-1h") },
                    text(_("CONTINUE READING"), "ui-semibold", "fs-xs", "accent") },
                VerticalSpan:new{ width = T.px("sp-2") },
                TextBoxWidget:new{ text = cur.title, face = L.face("display-semibold", "fs-display"), width = col_w,
                    bgcolor = T.color("surface"), height = math.floor(ch * 0.42), height_adjust = true, height_overflow_show_ellipsis = true },
                VerticalSpan:new{ width = T.px("sp-1") },
            }
            if cur.authors and cur.authors ~= "" then
                table.insert(col, text(cur.authors, "ui", "fs-md", "text-2", col_w))
            end
            table.insert(col, VerticalSpan:new{ width = T.px("sp-3") })
            local pct = cur.pct or 0
            if cur.pages and cur.pages > 0 then
                local page = math.max(1, math.floor(pct * cur.pages + 0.5))
                table.insert(col, text(string.format(_("Page %d of %d"), page, cur.pages), "ui", "fs-sm", "text-3", col_w))
            end
            table.insert(col, VerticalSpan:new{ width = T.px("sp-2") })
            local pct_t = text(string.format("%d%%", math.floor(pct * 100 + 0.5)), "ui-semibold", "fs-sm", "text")
            local pw = pct_t:getSize().w
            table.insert(col, HorizontalGroup:new{ align = "center",
                P.Bar:new{ width = col_w - pw - T.px("sp-3"), height = P.px(4), pct = pct },
                HorizontalSpan:new{ width = T.px("sp-3") }, pct_t })
            if stats.secs_per_page and cur.pages then
                local left_pages = math.max(0, cur.pages - math.floor(pct * cur.pages + 0.5))
                table.insert(col, VerticalSpan:new{ width = T.px("sp-2") })
                table.insert(col, icon_text("leaf.lib.clock", string.format(_("%s left in book"),
                    dur(math.max(1, math.floor(left_pages * stats.secs_per_page / 60 + 0.5))))))
            end
            table.insert(col, VerticalSpan:new{ width = T.px("sp-4") })
            local resume = Button:new{ text = "▶  " .. (cur.status == "new" and _("Start") or _("Resume")), _leaf_kind = "primary",
                bordersize = 0, width = P.px(124), height = T.px("h-control") - 2 * require("ui/size").padding.button,
                show_parent = self, callback = function() open_book(cur.file) end }
            local det = Button:new{ text = _("Details"), _leaf_kind = "ghost", bordersize = 0,
                show_parent = self, callback = function() details(cur.file) end }
            local more = IconButton:new{ icon = "leaf.more.v", width = s, height = s, padding = bp, show_parent = self,
                callback = function() book_menu(cur.file) end }
            local actions_l = HorizontalGroup:new{ align = "center", resume, HorizontalSpan:new{ width = T.px("sp-2") }, det }
            table.insert(col, row_lr(col_w, math.max(actions_l:getSize().h, more:getSize().h), actions_l,
                HorizontalGroup:new{ more, HorizontalSpan:new{ width = 0 } }))
            local hero = HorizontalGroup:new{ align = "top", cover, HorizontalSpan:new{ width = T.px("sp-5") }, col }
            add(card(hero, inner_w, cpad))
        else
            local empty = VerticalGroup:new{ align = "left",
                text(_("CONTINUE READING"), "ui-semibold", "fs-xs", "accent"),
                VerticalSpan:new{ width = T.px("sp-2") },
                text(_("Nothing in progress"), "display-semibold", "fs-xl", "text"),
                VerticalSpan:new{ width = T.px("sp-1") },
                text(_("Books you open will appear here."), "ui", "fs-sm", "text-3") }
            add(card(empty, inner_w))
        end

        -- stats (.hm-stats): 1.55fr / 1fr
        local gap = T.px("sp-4")
        local sw1 = math.floor((inner_w - gap) * 1.55 / 2.55)
        local sw2 = inner_w - gap - sw1
        local cpad = T.px("sp-4")
        local in1 = sw1 - 2 * cpad - 2 * T.px("hairline")
        local in2 = sw2 - 2 * cpad - 2 * T.px("hairline")
        local goal = G_reader_settings:readSetting("leaf_home_goal", 45)
        local function big(value, unit)
            return HorizontalGroup:new{ align = "bottom",
                text(tostring(value), "ui-semibold", "fs-2xl", "text"),
                text(unit, "ui-medium", "fs-md", "text-3") }
        end
        local WD = { "S", "M", "T", "W", "T", "F", "S" }
        local labels = {}
        local wday = tonumber(os.date("%w")) -- 0 = Sunday
        for i = 1, 7 do labels[i] = WD[((wday - 7 + i) % 7) + 1] end
        local left_block = VerticalGroup:new{ align = "left",
            big(stats.today, "m"),
            VerticalSpan:new{ width = T.px("sp-1h") },
            text(string.format(_("of %d min goal · %d%%"), goal, math.min(100, math.floor(stats.today * 100 / goal + 0.5))), "ui", "fs-sm", "text-3") }
        local lbw = left_block:getSize().w
        local bars = Bars:new{ width = math.max(P.px(60), in1 - lbw - T.px("sp-4")), height = P.px(78), values = stats.week, goal = goal, labels = labels }
        local pph = stats.secs_week > 0 and math.floor(stats.pages_week * 3600 / stats.secs_week + 0.5) or 0
        local today_card = VerticalGroup:new{ align = "left",
            row_lr(in1, T.px("icon-sm"), text(_("TODAY"), "ui-semibold", "fs-xs", "text-3"), icon("chevron.right")),
            VerticalSpan:new{ width = T.px("sp-3") },
            row_lr(in1, math.max(left_block:getSize().h, bars:getSize().h),
                VerticalGroup:new{ align = "left", VerticalSpan:new{ width = math.max(0, bars:getSize().h - left_block:getSize().h) }, left_block },
                bars),
            VerticalSpan:new{ width = T.px("sp-3") },
            require("ui/widget/linewidget"):new{ dimen = Geom:new{ w = in1, h = T.px("hairline") }, background = T.color("border") },
            VerticalSpan:new{ width = T.px("sp-3") },
            HorizontalGroup:new{ align = "center",
                icon_text("leaf.lib.filetext", string.format(_("%d pages this week"), stats.pages_week)),
                HorizontalSpan:new{ width = T.px("sp-4") },
                icon_text("leaf.lib.gauge", string.format(_("%d pages/h"), pph)) } }
        local wk_on = 0
        for i = 7, 1, -1 do if stats.week[i] > 0 then wk_on = wk_on + 1 elseif i < 7 then break end end
        local streak_card = VerticalGroup:new{ align = "left",
            row_lr(in2, T.px("icon-sm"), text(_("STREAK"), "ui-semibold", "fs-xs", "text-3"), icon("leaf.lib.flame")),
            VerticalSpan:new{ width = T.px("sp-3") },
            big(stats.streak, " " .. _("days")),
            VerticalSpan:new{ width = T.px("sp-3") },
            Dots:new{ on = math.min(7, stats.streak) },
            VerticalSpan:new{ width = T.px("sp-3") },
            TextBoxWidget:new{ text = string.format(_("Best %d days · %d books this year"), stats.best, stats.books_year),
                face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), width = in2, bgcolor = T.color("surface") } }
        local _unused = wk_on
        local h1 = today_card:getSize().h
        local h2 = streak_card:getSize().h
        local ch = math.max(h1, h2)
        local function stat_card(content, w, h)
            local c = card(VerticalGroup:new{ align = "left", content, VerticalSpan:new{ width = h - content:getSize().h } }, w, cpad)
            return P.Tap:new{ content = c, callback = function()
                local f = fm()
                if f then f:handleEvent(Event:new("ShowCalendarView")) end
            end }
        end
        add(HorizontalGroup:new{ align = "top", stat_card(today_card, sw1, ch), HorizontalSpan:new{ width = gap }, stat_card(streak_card, sw2, ch) },
            T.px("sp-5"))

        -- recently read (.hm-recent): 5 covers
        local recent = {}
        for i = 2, #books do table.insert(recent, books[i]) end
        if #recent > 0 then
            local link = P.Tap:new{ content = HorizontalGroup:new{ align = "center",
                    text(_("History"), "ui-medium", "fs-sm", "accent"), icon("chevron.right") },
                callback = function()
                    M.close()
                    if fm() then fm().history:onShowHist() end
                end }
            add(row_lr(inner_w, link:getSize().h, text(_("Recently read"), "ui-semibold", "fs-md", "text"), link), T.px("sp-3"))
            local n = 5
            local g = T.px("sp-3")
            local bw = math.floor((inner_w - (n - 1) * g) / n)
            -- fit the shelf above the bottom nav (the prototype scrolls; KOReader pages don't)
            local used = body:getSize().h
            body:resetLayout()
            local cap_h = P.px(44)
            local bh = math.min(math.floor(bw * 1.5), H - LeafNav.height() - used - cap_h - T.px("sp-3"))
            if bh < P.px(60) then n = 0 end
            local shelf = HorizontalGroup:new{ align = "top" }
            for i, file in ipairs(recent) do
                if i > n then break end
                bh = math.max(bh, 1)
                local info = P.bookInfo(file)
                local cov = P.coverBox(file, bw, bh, { title = info.title })
                local b = info.status == "complete" and "✓" or string.format("%d%%", math.floor((info.pct or 0) * 100 + 0.5))
                local bd = badge(b)
                local bsz = bd:getSize()
                local cover_ol = OverlapGroup:new{ dimen = Geom:new{ w = bw, h = bh }, cov,
                    RightContainer:new{ dimen = Geom:new{ w = bw - T.px("sp-1h"), h = 2 * (bh - T.px("sp-1h")) - bsz.h }, bd } }
                local cell = VerticalGroup:new{ align = "left", cover_ol,
                    VerticalSpan:new{ width = T.px("sp-2") },
                    text(info.title, "ui-medium", "fs-sm", "text", bw),
                    VerticalSpan:new{ width = T.px("sp-1h") },
                    info.status == "complete" and text(_("Finished"), "ui", "fs-xs", "text-3")
                        or P.Bar:new{ width = bw, height = P.px(2), pct = info.pct } }
                if i > 1 then table.insert(shelf, HorizontalSpan:new{ width = g }) end
                table.insert(shelf, P.Tap:new{ content = cell, callback = function() open_book(file) end,
                    hold_callback = function() details(file) end })
            end
            add(shelf)
        end

        local nav = LeafNav:new{ width = W, active = "home", on_select = function(key)
            if key == "home" then return end
            local lib = require("leaf/library")
            if key == "settings" then lib.showSettings() return end
            M.close()
            if key == "history" and fm() then fm().history:onShowHist() end
        end }
        local nav_h = nav:getSize().h
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg"), width = W, height = H,
            OverlapGroup:new{ dimen = Geom:new{ w = W, h = H },
                body,
                require("ui/widget/container/bottomcontainer"):new{ dimen = Geom:new{ w = W, h = H }, nav } } }
        local _nh = nav_h
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    end

    function Home:onClose()
        M.close()
        return true
    end
    function Home:onShow()
        UIManager:setDirty(self, "full")
        return true
    end
    function Home:onShowingReader()
        M.close()
    end
    function Home:onCloseWidget()
        if instance == self then instance = nil end
        UIManager:setDirty(nil, "full")
    end

    function M.show()
        if instance then UIManager:close(instance) end
        instance = Home:new{}
        UIManager:show(instance)
    end
    function M.close()
        if instance then
            local w = instance
            instance = nil
            UIManager:close(w)
        end
    end
end

return M
