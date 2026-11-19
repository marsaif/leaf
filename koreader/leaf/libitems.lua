--[[
    Leaf library items: the book cells and rows Project: Title's grid and lists show, drawn like the
    prototype (js/screens/library.js gridHTML / listHTML / history, css/screens/library.css).
    Not a module of L.MODULES: leaf/library.lua calls `require("leaf/libitems")(L)` and puts these
    widgets in PT's items (PT keeps paging, item sizes, taps, long-press, background extraction).

      I.data(file, entry)           what a cell shows: title, authors, status, %, pages, favourite,
                                    format, size, last read / added, minutes left
      I.prog(d, width, o)           .lb-prog: "Not started" · ✓ Finished (+ ★) · bar + 8% (⏸ on hold)
      I.grid(d, w, h)               .lb-cell: cover (New / ✓ badge, ♥ ribbon), title, author, .lb-prog
      I.detail(d, w, h)             .lb-drow: cover, title, author, meta / series, .lb-prog, status
                                    pill + "when", ⋮
      I.list(d, w, h)               .lb-lrow: thumbnail, file name, "EPUB · 0.3 MB · 112 p · ♥", .lb-prog, ⋮
      I.history(d, w, h, o)         .lb-hrow: (group heading) cover, title, author, .lb-prog, time +
                                    "2h 45m left", ⋮; deleted files: struck title, "File deleted", Remove
      I.InkIcon{icon, size, color}  a Lucide icon painted in any colour (white ticks on dark badges)
    Each row returns its tap zones (⋮, Remove) in `widget.zones`, filled at paint time.
--]]
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local Screen = Device.screen

local cache

return function(L)
    if cache then return cache end
    local T = L.T
    local P = require("leaf/widgets/libparts")
    local I = {}

    local function geom(w, h) return Geom:new{ x = 0, y = 0, w = math.floor(w), h = math.floor(h) } end
    local function text(t, role, size, color, max_w)
        return TextWidget:new{ text = t or "", face = L.face(role, size), fgcolor = T.color(color or "text"), padding = 0,
            max_width = max_w and math.max(1, math.floor(max_w)) or nil }
    end
    local function icon(name, size_tok)
        local s = type(size_tok) == "number" and size_tok or T.px(size_tok or "icon-md")
        return IconWidget:new{ icon = name, width = s, height = s, alpha = true }
    end
    I.text, I.icon, I.geom = text, icon, geom

    ------------------------------------------------------------ InkIcon: an icon in any colour
    I.InkIcon = Widget:extend{ icon = nil, size = nil, color = nil }
    function I.InkIcon:init()
        self.dimen = geom(self.size, self.size)
    end
    function I.InkIcon:getSize() return self.dimen end
    function I.InkIcon:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if not self._mask then
            local s = self.size
            local tmp = Blitbuffer.new(s, s, Blitbuffer.TYPE_BB8)
            tmp:fill(Blitbuffer.COLOR_WHITE)
            local iw = IconWidget:new{ icon = self.icon, width = s, height = s, alpha = true }
            iw:paintTo(tmp, 0, 0)
            iw:free()
            tmp:invertRect(0, 0, s, s) -- coverage: stroke = 255
            self._mask = tmp
        end
        bb:colorblitFrom(self._mask, x, y, 0, 0, self.size, self.size, self.color)
    end
    function I.InkIcon:free()
        if self._mask then self._mask:free() self._mask = nil end
    end

    ------------------------------------------------------------ data
    local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    local function day0(t)
        local d = os.date("*t", t)
        d.hour, d.min, d.sec = 0, 0, 0
        return os.time(d)
    end
    function I.fmtDate(t)
        local d = os.date("*t", t)
        return MONTHS[d.month] .. " " .. d.day
    end
    --- "today", "yesterday", "3 days ago", "Oct 16"
    function I.ago(t)
        if not t then return nil end
        local days = math.floor((day0(os.time()) - day0(t)) / 86400 + 0.5)
        if days <= 0 then return _("today") end
        if days == 1 then return _("yesterday") end
        if days < 30 then return string.format(_("%d days ago"), days) end
        return I.fmtDate(t)
    end
    --- history times: "21:10" today, "Tue 22:30" this week, "Nov 2" earlier
    function I.when(t)
        local days = math.floor((day0(os.time()) - day0(t)) / 86400 + 0.5)
        if days <= 0 then return os.date("%H:%M", t) end
        if days < 7 then return os.date("%a %H:%M", t) end
        return I.fmtDate(t)
    end
    function I.group(t)
        local days = math.floor((day0(os.time()) - day0(t)) / 86400 + 0.5)
        if days <= 0 then return _("Today") end
        if days < 7 then return _("This week") end
        return _("Earlier")
    end
    function I.durShort(min)
        local h, m = math.floor(min / 60), min % 60
        if h > 0 then return string.format("%dh %02dm", h, m) end
        return string.format("%dm", m)
    end
    function I.dur(min)
        local h, m = math.floor(min / 60), min % 60
        if h > 0 then return m > 0 and string.format(_("%d h %d min"), h, m) or string.format(_("%d h"), h) end
        return string.format(_("%d min"), m)
    end

    -- reading speed per book (statistics plugin), seconds per page
    local speed = {}
    local function secs_per_page(md5)
        if not md5 then return nil end
        if speed[md5] ~= nil then return speed[md5] or nil end
        speed[md5] = false
        pcall(function()
            local path = require("datastorage"):getSettingsDir() .. "/statistics.sqlite3"
            if not require("libs/libkoreader-lfs").attributes(path, "mode") then return end
            local conn = require("lua-ljsqlite3/init").open(path)
            local row = conn:exec(string.format("SELECT total_read_time, total_read_pages FROM book WHERE md5 = '%s' LIMIT 1;", md5))
            conn:close()
            if row and row[1] and tonumber(row[2][1]) and tonumber(row[2][1]) > 0 then
                speed[md5] = tonumber(row[1][1]) / tonumber(row[2][1])
            end
        end)
        return speed[md5] or nil
    end
    function I.resetSpeed() speed = {} end

    function I.data(file, entry)
        local d = P.bookInfo(file)
        local util = require("util")
        local lfs = require("libs/libkoreader-lfs")
        d.file = file
        d.name = file:match("([^/]+)$") or file
        d.ext = (d.name:match("%.([^.]+)$") or ""):upper()
        d.deleted = entry and entry.dim and not lfs.attributes(file, "mode")
        local attr = lfs.attributes(file) or {}
        d.size = attr.size and util.getFriendlySize(attr.size):gsub("%.0 ", " ") or nil
        d.added = attr.modification
        local RC = require("readcollection")
        d.fav = RC:isFileInCollection(file, RC.default_collection_name)
        local BIM = package.loaded["bookinfomanager"]
        if BIM then
            local ok, bi = pcall(BIM.getBookInfo, BIM, file, false)
            if ok and bi then
                d.series, d.series_index = bi.series, bi.series_index
                d.language = bi.language
                d.has_cover = bi.has_cover
            end
        end
        -- last read: the history entry, else the sidecar's summary date
        d.last = entry and entry.time
        if not d.last then
            local RH = require("readhistory")
            local i = RH.getIndexByFile and RH:getIndexByFile(file)
            if i and RH.hist[i] then d.last = RH.hist[i].time end
        end
        d.rating = 0
        if d.status ~= "new" then
            pcall(function()
                local ds = require("ui/widget/booklist").getDocSettings(file)
                local summary = ds:readSetting("summary") or {}
                d.rating = summary.rating or 0
                d.md5 = d.md5 or ds:readSetting("partial_md5_checksum")
                if not d.last and summary.modified then
                    local y, m, dd = summary.modified:match("(%d+)-(%d+)-(%d+)")
                    if y then d.last = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 } end
                end
            end)
        end
        d.pct100 = math.floor((d.pct or 0) * 100 + 0.5)
        if d.pages and d.status ~= "complete" then
            local spp = secs_per_page(d.md5) or 96 -- the prototype's 1.6 min a page
            d.minleft = math.max(1, math.floor((1 - (d.pct or 0)) * d.pages * spp / 60 + 0.5))
        end
        return d
    end

    I.STATUS_LABEL = { new = _("New"), reading = _("Reading"), abandoned = _("On hold"), complete = _("Finished") }

    ------------------------------------------------------------ painted pieces
    -- the favourite ribbon (.lb-mark): accent flag with a V notch, heart in --accent-ink
    local Ribbon = Widget:extend{ w = 18, h = 24 }
    function Ribbon:init()
        self.dimen = geom(self.w, self.h)
        local s = math.floor(self.w * 11 / 18)
        self.heart = I.InkIcon:new{ icon = "leaf.lib.heart.bold", size = s, color = T.color("accent-ink") }
    end
    function Ribbon:getSize() return self.dimen end
    function Ribbon:paintTo(bb, x, y)
        local w, h = self.w, self.h
        local c = T.color("accent")
        local body = math.floor(h * 0.8)
        bb:paintRect(x, y, w, body, c)
        for yy = body, h - 1 do
            local k = math.floor((yy - body + 1) / (h - body) * w / 2 + 0.5)
            local half = math.floor(w / 2)
            if half - k > 0 then
                bb:paintRect(x, y + yy, half - k, 1, c)
                bb:paintRect(x + w - (half - k), y + yy, half - k, 1, c)
            end
        end
        self.heart:paintTo(bb, x + math.floor((w - self.heart.size) / 2), y + math.floor(h * 4 / 24))
    end
    function Ribbon:free() self.heart:free() end
    I.Ribbon = Ribbon

    -- a pill-shaped box painted behind content (badges, pills)
    local Pill = Widget:extend{ content = nil, bg = nil, border = nil, bw = 0, h = 0, padx = 0 }
    function Pill:init()
        local sz = self.content:getSize()
        self.w = sz.w + 2 * self.padx
        self.dimen = geom(self.w, self.h)
    end
    function Pill:getSize() return self.dimen end
    function Pill:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local r = math.floor(self.h / 2)
        if self.border then
            bb:paintRoundedRect(x, y, self.w, self.h, self.border, r)
            bb:paintRoundedRect(x + self.bw, y + self.bw, self.w - 2 * self.bw, self.h - 2 * self.bw, self.bg or T.color("bg"), r - self.bw)
        elseif self.bg then
            bb:paintRoundedRect(x, y, self.w, self.h, self.bg, r)
        end
        local sz = self.content:getSize()
        self.content:paintTo(bb, x + self.padx, y + math.floor((self.h - sz.h) / 2))
    end
    function Pill:free() if self.content.free then self.content:free() end end
    I.Pill = Pill

    -- .ko-badge on a cover: "New" (accent) or a ✓ (cover scrim)
    function I.badge(status)
        local h = T.px("h-badge")
        if status == "new" then
            return Pill:new{ h = h, padx = P.px(7), bg = T.color("accent"),
                content = text(_("New"), "ui-semibold", "fs-2xs", "accent-ink") }
        elseif status == "complete" then
            local s = T.px("icon-xs")
            return Pill:new{ h = h, padx = math.floor((h - s) / 2), bg = T.color("cover-scrim"),
                content = I.InkIcon:new{ icon = "leaf.lib.check.bold", size = s, color = T.color("on-cover") } }
        end
    end

    -- .ko-pill: New (accent fill), Reading (accent outline), Finished (--surface-2), On hold (plain)
    function I.pill(status)
        local h = T.px("h-badge")
        local hair = T.px("hairline")
        local label = I.STATUS_LABEL[status] or ""
        if status == "new" then
            return Pill:new{ h = h, padx = T.px("sp-2"), bg = T.color("accent"),
                content = text(label, "ui-semibold", "fs-2xs", "accent-ink") }
        elseif status == "reading" then
            return Pill:new{ h = h, padx = T.px("sp-2"), border = T.color("accent"), bw = T.px("bw-md"), bg = T.color("bg"),
                content = text(label, "ui-bold", "fs-2xs", "text") }
        elseif status == "complete" then
            return Pill:new{ h = h, padx = T.px("sp-2"), border = T.color("border-strong"), bw = hair, bg = T.color("surface-2"),
                content = text(label, "ui-semibold", "fs-2xs", "text-2") }
        end
        return Pill:new{ h = h, padx = T.px("sp-2"), border = T.color("border-strong"), bw = hair, bg = T.color("bg"),
            content = text(label, "ui-semibold", "fs-2xs", "text-2") }
    end

    -- ★★★★★ (filled = rating, shape not colour)
    function I.stars(n, size_tok, gap)
        local g = HorizontalGroup:new{ align = "center" }
        for i = 1, 5 do
            if i > 1 then table.insert(g, HorizontalSpan:new{ width = gap or P.px(1) }) end
            table.insert(g, I.InkIcon:new{ icon = i <= n and "leaf.lib.star.on" or "leaf.lib.star", size = size_tok or P.px(9),
                color = T.color(i <= n and "accent" or "border-strong") })
        end
        return g
    end

    --- .lb-prog (height 14): new / finished / bar + %
    function I.prog(d, width, o)
        o = o or {}
        local h = P.px(14)
        local g = HorizontalGroup:new{ align = "center" }
        if d.deleted then
            table.insert(g, icon("leaf.lib.trash", "icon-2xs"))
            table.insert(g, HorizontalSpan:new{ width = T.px("sp-1") })
            table.insert(g, text(string.format(_("File deleted · was at %d%%"), d.pct100), "ui", "fs-xs", "text-3", width))
        elseif d.status == "new" then
            table.insert(g, text(_("Not started"), "ui", "fs-xs", "text-3", width))
        elseif d.status == "complete" then
            table.insert(g, icon("leaf.lib.circlecheck", "icon-2xs"))
            table.insert(g, HorizontalSpan:new{ width = T.px("sp-1") })
            table.insert(g, text(_("Finished"), "ui", "fs-xs", "text-2"))
            if o.rating ~= false and d.rating and d.rating > 0 then
                table.insert(g, HorizontalSpan:new{ width = T.px("sp-2") })
                table.insert(g, I.stars(d.rating))
            end
        else
            local num = HorizontalGroup:new{ align = "center" }
            if d.status == "abandoned" then
                table.insert(num, icon("leaf.lib.pause", "icon-2xs"))
                table.insert(num, HorizontalSpan:new{ width = P.px(3) })
            end
            table.insert(num, text(d.pct100 .. "%", "ui", "fs-xs", "text-3"))
            local nw = math.max(P.px(28), num:getSize().w)
            num:resetLayout()
            local gap = T.px("sp-2")
            local bw = math.max(P.px(20), math.min(o.max or P.px(140), width - nw - gap))
            table.insert(g, P.Bar:new{ width = bw, height = P.px(2), pct = d.pct or 0, dim = d.status == "abandoned" })
            table.insert(g, HorizontalSpan:new{ width = gap })
            table.insert(g, RightContainer:new{ dimen = geom(nw, h), num })
        end
        return LeftContainer:new{ dimen = geom(math.min(width, g:getSize().w), h), g }
    end

    --- cover box with the overlays of a grid cell
    function I.cover(d, cw, ch, o)
        o = o or {}
        local box = P.coverBox(d.file, cw, ch, { title = d.title, bg = o.bg, cache_only = true,
            radius = cw <= P.px(48) and T.px("r-thumb") or nil })
        local og = OverlapGroup:new{ dimen = geom(cw, ch), box }
        if o.badge then
            local b = I.badge(d.status)
            if b then
                local m = T.px("sp-1h")
                table.insert(og, BottomContainer:new{ dimen = geom(cw, ch - m),
                    RightContainer:new{ dimen = geom(cw - m, b:getSize().h), b } })
            end
        end
        if o.mark and d.fav then
            local rw = o.small and P.px(14) or P.px(18)
            local rh = o.small and P.px(19) or P.px(24)
            table.insert(og, RightContainer:new{ dimen = geom(cw - (o.small and P.px(5) or T.px("sp-2")), rh),
                Ribbon:new{ w = rw, h = rh } })
        end
        return og
    end

    ------------------------------------------------------------ the ⋮ button (zone)
    local Zone = Widget:extend{ w = 0, h = 0, content = nil, key = nil, owner = nil }
    function Zone:init() self.dimen = geom(self.w, self.h) end
    function Zone:getSize() return self.dimen end
    function Zone:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if self.owner then self.owner.zones[self.key] = self.dimen end
        if self.content then
            local sz = self.content:getSize()
            self.content:paintTo(bb, x + math.floor((self.w - sz.w) / 2), y + math.floor((self.h - sz.h) / 2))
        end
    end
    function Zone:free() if self.content and self.content.free then self.content:free() end end
    local function more(owner, h)
        local s = P.px(36)
        return Zone:new{ w = s, h = math.max(s, h or s), key = "more", owner = owner, content = icon("leaf.more.v", "icon-md") }
    end

    -- a row container: the widget + its tap zones
    local Row = OverlapGroup:extend{}
    local function row(w, h)
        local r = Row:new{ dimen = geom(w, h) }
        r.zones = {}
        return r
    end

    ------------------------------------------------------------ grid cell (.lb-cell)
    function I.grid(d, w, h)
        local capH = P.px(70)
        local ch = h - capH - T.px("sp-2")
        local cw = math.floor(ch * 2 / 3)
        if cw > w - P.px(8) then cw = w - P.px(8) ch = math.floor(cw * 1.5) end
        ch = math.floor(cw * 1.5)
        local capW = math.min(w, math.floor(cw * 1.42))
        local col = VerticalGroup:new{ align = "left",
            HorizontalSpan:new{ width = capW },
            I.cover(d, cw, ch, { badge = true, mark = true }),
            VerticalSpan:new{ width = T.px("sp-2h") },
            text(d.title, "ui-medium", "fs-md", "text", capW),
            VerticalSpan:new{ width = P.px(1) },
            text(d.authors or "", "ui", "fs-sm", "text-3", capW),
            VerticalSpan:new{ width = P.px(7) },
            I.prog(d, capW, { rating = false }) }
        local r = row(w, h)
        table.insert(r, BottomContainer:new{ dimen = geom(w, h), col })
        return r
    end

    ------------------------------------------------------------ detailed row (.lb-drow)
    function I.detail(d, w, h)
        local pad_l, pad_r = T.px("sp-5"), T.px("sp-2")
        local gap = T.px("sp-4")
        local ch = math.min(P.px(120), h - P.px(30))
        local cw = math.floor(ch * 2 / 3)
        local r = row(w, h)
        -- side: pill + when, ⋮ (in --h-control on the right)
        local when = d.status == "new" and d.added and (_("Added") .. " " .. I.fmtDate(d.added)) or I.ago(d.last) or ""
        local side = VerticalGroup:new{ align = "right", I.pill(d.status), VerticalSpan:new{ width = T.px("sp-1h") },
            text(when, "ui", "fs-xs", "text-3") }
        local side_w = side:getSize().w
        side:resetLayout()
        local mid_w = w - pad_l - cw - gap - gap - side_w - T.px("h-control") - pad_r
        local s_line
        if d.series and d.series ~= "" then
            s_line = HorizontalGroup:new{ align = "center", icon("leaf.lib.library", "icon-2xs"), HorizontalSpan:new{ width = P.px(5) },
                text(d.series .. (d.series_index and (" · #" .. tostring(d.series_index):gsub("%.0$", "")) or ""), "ui", "fs-sm", "text-3", mid_w) }
        else
            local bits = { d.ext }
            if d.size then table.insert(bits, d.size) end
            if d.pages then table.insert(bits, d.pages .. " p") end
            s_line = text(table.concat(bits, " · "), "ui", "fs-sm", "text-3", mid_w)
        end
        local mid = VerticalGroup:new{ align = "left",
            text(d.title, "ui-semibold", "fs-lg", "text", mid_w),
            VerticalSpan:new{ width = P.px(1) },
            text(d.authors or "", "ui", "fs-sm", "text-2", mid_w),
            VerticalSpan:new{ width = P.px(3) },
            s_line,
            VerticalSpan:new{ width = P.px(7) },
            I.prog(d, mid_w, { max = P.px(200) }) }
        table.insert(r, LeftContainer:new{ dimen = geom(w, h), HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = pad_l }, I.cover(d, cw, ch, { mark = true, small = true }),
            HorizontalSpan:new{ width = gap }, mid } })
        table.insert(r, RightContainer:new{ dimen = geom(w, h), HorizontalGroup:new{ align = "center",
            side, HorizontalSpan:new{ width = T.px("h-control") - P.px(36) + T.px("sp-1") }, more(r), HorizontalSpan:new{ width = pad_r } } })
        return r
    end

    ------------------------------------------------------------ list row (.lb-lrow)
    function I.list(d, w, h)
        local pad_l, pad_r = T.px("sp-5"), T.px("sp-2")
        local gap = T.px("sp-4")
        local ch = math.min(P.px(66), h - P.px(20))
        local cw = math.floor(ch * 2 / 3)
        local r = row(w, h)
        local mid_w = w - pad_l - cw - gap - P.px(36) - pad_r - gap
        local meta = HorizontalGroup:new{ align = "center" }
        local bits = { d.ext }
        if d.size then table.insert(bits, d.size) end
        if d.pages then table.insert(bits, d.pages .. " p") end
        table.insert(meta, text(table.concat(bits, " · ") .. (d.fav and " · " or ""), "ui", "fs-sm", "text-3", mid_w - P.px(16)))
        if d.fav then table.insert(meta, icon("leaf.lib.heart", "icon-2xs")) end
        local mid = VerticalGroup:new{ align = "left",
            text(d.name, "ui-medium", "fs-md", "text", mid_w),
            VerticalSpan:new{ width = T.px("sp-half") },
            meta,
            VerticalSpan:new{ width = T.px("sp-1h") },
            I.prog(d, mid_w, { max = P.px(180) }) }
        table.insert(r, LeftContainer:new{ dimen = geom(w, h), HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = pad_l }, I.cover(d, cw, ch, {}), HorizontalSpan:new{ width = gap }, mid } })
        table.insert(r, RightContainer:new{ dimen = geom(w, h), HorizontalGroup:new{ align = "center", more(r), HorizontalSpan:new{ width = pad_r } } })
        return r
    end

    ------------------------------------------------------------ history row (.lb-hrow)
    I.HGROUP_H = function() return P.px(36) end
    function I.history(d, w, h, o)
        o = o or {}
        local pad_l = T.px("sp-5")
        local gap = T.px("sp-4")
        local head_h = o.head and I.HGROUP_H() or 0
        local rh = h - head_h
        local cw, ch = P.px(40), P.px(60)
        local r = row(w, h)
        local side = VerticalGroup:new{ align = "right" }
        local when = d.last and I.when(d.last) or ""
        table.insert(side, text(when, "ui", "fs-sm", "text-2"))
        local right
        if d.deleted then
            table.insert(side, VerticalSpan:new{ width = P.px(5) })
            local rm = text(_("Remove"), "ui-medium", "fs-sm", "accent")
            table.insert(side, Zone:new{ w = rm:getSize().w + 2 * T.px("sp-2"), h = P.px(26), key = "remove", owner = r, content = rm })
            right = HorizontalGroup:new{ align = "center", side, HorizontalSpan:new{ width = T.px("sp-4") } }
        else
            if d.minleft and d.status ~= "new" then
                table.insert(side, VerticalSpan:new{ width = P.px(5) })
                table.insert(side, text(string.format(_("%s left"), I.durShort(d.minleft)), "ui", "fs-sm", "text-3"))
            end
            right = HorizontalGroup:new{ align = "center", side, HorizontalSpan:new{ width = T.px("sp-4") }, more(r, rh), HorizontalSpan:new{ width = T.px("sp-2") } }
        end
        local right_w = right:getSize().w
        right:resetLayout()
        local mid_w = w - pad_l - cw - gap - right_w - gap
        local cover
        if d.deleted then
            cover = P.CoverBox:new{ width = cw, height = ch, title = d.title, radius = T.px("r-thumb") }
        else
            cover = P.coverBox(d.file, cw, ch, { title = d.title, cache_only = true, radius = T.px("r-thumb") })
        end
        local title = text(d.title, "ui-medium", "fs-md", d.deleted and "text-3" or "text", mid_w)
        local mid = VerticalGroup:new{ align = "left", title,
            VerticalSpan:new{ width = P.px(1) },
            text(d.authors or "", "ui", "fs-sm", "text-3", mid_w),
            VerticalSpan:new{ width = P.px(7) },
            I.prog(d, mid_w, { max = P.px(160) }) }
        local body = OverlapGroup:new{ dimen = geom(w, rh),
            LeftContainer:new{ dimen = geom(w, rh), HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = pad_l }, cover, HorizontalSpan:new{ width = gap }, mid } },
            RightContainer:new{ dimen = geom(w, rh), right } }
        if d.deleted then
            -- strike the title through (.lb-hrow.deleted .t)
            local Strike = Widget:extend{}
            function Strike:getSize() return title:getSize() end
            function Strike:paintTo(bb, x, y)
                local sz = title:getSize()
                bb:paintRect(x, y + math.floor(sz.h * 0.55), sz.w, T.px("hairline"), T.color("text-3"))
            end
            local tsz = mid:getSize()
            mid:resetLayout()
            table.insert(body, LeftContainer:new{ dimen = geom(w, rh), HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = pad_l + cw + gap },
                VerticalGroup:new{ align = "left", Strike:new{}, VerticalSpan:new{ width = tsz.h - title:getSize().h } } } })
        end
        local col = VerticalGroup:new{ align = "left" }
        if o.head then
            -- .ko-eyebrow.lb-hgroup: 36px, text at the bottom (--sp-1h)
            table.insert(col, VerticalGroup:new{ align = "left",
                VerticalSpan:new{ width = head_h - T.px("sp-1h") - text("X", "ui-semibold", "fs-xs"):getSize().h },
                HorizontalGroup:new{ HorizontalSpan:new{ width = pad_l }, text(o.head:upper(), "ui-semibold", "fs-xs", "text-3") },
                VerticalSpan:new{ width = T.px("sp-1h") } })
        end
        table.insert(col, body)
        table.insert(r, col)
        return r
    end

    ------------------------------------------------------------ status segments (.ko-seg--icons)
    -- Reading · On hold · Finished; selected = ✓ + accent outline; on_select(key) for the others
    function I.statusSeg(width, cur, on_select, enabled)
        local FrameContainer = require("ui/widget/container/framecontainer")
        local pad = T.px("sp-half")
        local keys = { { "reading", "leaf.lib.bookopen", _("Reading") }, { "abandoned", "leaf.lib.pause", _("On hold") },
            { "complete", "leaf.lib.check", _("Finished") } }
        local inner = width - 2 * P.px(3)
        local cw = math.floor((inner - 2 * pad) / 3)
        local h = T.px("h-seg")
        local row = HorizontalGroup:new{ align = "center" }
        for i, k in ipairs(keys) do
            local on = cur == k[1]
            local g = HorizontalGroup:new{ align = "center",
                on and I.InkIcon:new{ icon = "leaf.lib.check.bold", size = T.px("icon-xs"), color = T.color("accent") } or icon(k[2], "icon-xs"),
                HorizontalSpan:new{ width = T.px("sp-1h") }, text(k[3], on and "ui-semibold" or "ui", "fs-sm", on and "accent" or "text-2") }
            local bw = on and T.px("bw-md") or 0
            local cell = FrameContainer:new{ bordersize = bw, color = T.color("accent"),
                background = T.color(on and "surface" or "surface-2"), radius = T.px("r-inner"), padding = 0, margin = 0,
                CenterContainer:new{ dimen = geom(cw - 2 * bw, h - 2 * bw), g } }
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = pad }) end
            if not on and on_select and (not enabled or enabled[k[1]] ~= false) then
                cell = P.Tap:new{ content = cell, callback = function() on_select(k[1]) end }
            end
            table.insert(row, cell)
        end
        return FrameContainer:new{ bordersize = 0, background = T.color("surface-2"), radius = T.px("r-md"), padding = P.px(3), row }
    end

    ------------------------------------------------------------ folder browser rows (.lb-frow)
    -- a folder: accent folder icon, name (+ HOME tag), "3 items", count, ⋮ (KOReader's folder menu)
    function I.dirRow(o, w, h)
        local pad_l, pad_r = T.px("sp-5"), T.px("sp-3")
        local gap = T.px("sp-4")
        local r = row(w, h)
        local ico = CenterContainer:new{ dimen = geom(P.px(36), P.px(36)),
            I.InkIcon:new{ icon = o.count and o.count > 0 and "leaf.lib.folder" or "leaf.lib.folderopen", size = P.px(30), color = T.color("accent") } }
        local right = HorizontalGroup:new{ align = "center",
            text(o.count and tostring(o.count) or "", "ui", "fs-sm", "text-3"), HorizontalSpan:new{ width = T.px("sp-2") },
            more(r), HorizontalSpan:new{ width = pad_r } }
        local rw = right:getSize().w
        right:resetLayout()
        local mid_w = w - pad_l - P.px(36) - gap - rw - gap
        local name = HorizontalGroup:new{ align = "center", text(o.name, "ui-medium", "fs-md", "text", mid_w - (o.home and P.px(70) or 0)) }
        if o.home then
            table.insert(name, HorizontalSpan:new{ width = T.px("sp-2") })
            table.insert(name, Pill:new{ h = P.px(18), padx = T.px("sp-1h"), border = T.color("accent"), bw = T.px("hairline"), bg = T.color("accent-soft"),
                content = HorizontalGroup:new{ align = "center", icon("leaf.lib.house", P.px(10)), HorizontalSpan:new{ width = P.px(3) },
                    text("HOME", "ui-semibold", "fs-2xs", "text") } })
        end
        local mid = VerticalGroup:new{ align = "left", name, VerticalSpan:new{ width = P.px(3) },
            text(o.meta or "", "ui", "fs-sm", "text-3", mid_w) }
        table.insert(r, LeftContainer:new{ dimen = geom(w, h), HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = pad_l }, ico, HorizontalSpan:new{ width = gap }, mid } })
        table.insert(r, RightContainer:new{ dimen = geom(w, h), right })
        return r
    end
    -- a book file: thumbnail, file name, "EPUB · 0.3 MB · yesterday", New pill / ✓ / %, ⋮
    function I.fileRow(d, w, h)
        local pad_l, pad_r = T.px("sp-5"), T.px("sp-3")
        local gap = T.px("sp-4")
        local r = row(w, h)
        local pct
        if d.status == "new" then pct = I.pill("new")
        elseif d.status == "complete" then pct = icon("leaf.lib.circlecheck", "icon-sm")
        else pct = text(d.pct100 .. "%", "ui", "fs-sm", "text-2") end
        local right = HorizontalGroup:new{ align = "center", pct, HorizontalSpan:new{ width = T.px("sp-2") }, more(r), HorizontalSpan:new{ width = pad_r } }
        local rw = right:getSize().w
        right:resetLayout()
        local tw, th = P.px(30), P.px(45)
        local mid_w = w - pad_l - tw - 2 * P.px(3) - gap - rw - gap
        local bits = { d.ext }
        if d.size then table.insert(bits, d.size) end
        local when = d.last and I.ago(d.last) or (d.added and I.fmtDate(d.added))
        if when then table.insert(bits, when) end
        local mid = VerticalGroup:new{ align = "left", text(d.name, "ui-medium", "fs-md", "text", mid_w), VerticalSpan:new{ width = P.px(3) },
            text(table.concat(bits, " · "), "ui", "fs-sm", "text-3", mid_w) }
        table.insert(r, LeftContainer:new{ dimen = geom(w, h), HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = pad_l + P.px(3) }, I.cover(d, tw, th, {}), HorizontalSpan:new{ width = P.px(3) + gap }, mid } })
        table.insert(r, RightContainer:new{ dimen = geom(w, h), right })
        return r
    end

    ------------------------------------------------------------ collections (.lb-ccard)
    -- stacked covers (.lb-stack): up to 3, the first in front, the others smaller behind (no tilt on e-ink)
    local Stack = Widget:extend{ width = 0, height = 0, files = nil }
    function Stack:init()
        self.dimen = geom(self.width, self.height)
        local sh = math.floor(self.height * 0.82)
        local sw = math.floor(sh * 2 / 3)
        self.covers = {}
        local cx = math.floor(self.width / 2)
        local top = math.floor(self.height * 0.09)
        local n = math.min(3, #self.files)
        local function cover(i, w, h, x, y)
            local f = self.files[i]
            table.insert(self.covers, { w = P.coverBox(f.file, w, h, { cache_only = true, title = (f.file:match("([^/]+)$") or ""):gsub("%.[^.]+$", ""),
                bg = T.color("bg-raised") }), x = x, y = y })
        end
        local ssw, ssh = math.floor(sw * 0.86), math.floor(sh * 0.86)
        local sy = top + math.floor((sh - ssh) / 2)
        if n == 3 then
            cover(3, ssw, ssh, cx + math.floor(0.25 * sw), sy)
            cover(2, ssw, ssh, cx - math.floor(1.11 * sw), sy)
            cover(1, sw, sh, cx - math.floor(sw / 2), top)
        elseif n == 2 then
            local s2w, s2h = math.floor(sw * 0.9), math.floor(sh * 0.9)
            cover(2, s2w, s2h, cx - math.floor(0.23 * sw), top + math.floor((sh - s2h) / 2))
            cover(1, sw, sh, cx - math.floor(0.72 * sw), top)
        elseif n == 1 then
            cover(1, sw, sh, cx - math.floor(sw / 2), top)
        end
        if n == 0 then self.empty = icon("leaf.lib.library", "icon-xl") end
    end
    function Stack:getSize() return self.dimen end
    function Stack:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local r = T.px("r-lg") - T.px("hairline")
        bb:paintRoundedRect(x, y, self.width, self.height, T.color("bg-raised"), r)
        bb:paintRect(x, y + self.height - r, self.width, r, T.color("bg-raised"))
        for _i, c in ipairs(self.covers) do c.w:paintTo(bb, x + c.x, y + c.y) end
        if self.empty then
            local sz = self.empty:getSize()
            self.empty:paintTo(bb, x + math.floor((self.width - sz.w) / 2), y + math.floor((self.height - sz.h) / 2))
        end
    end
    function Stack:free()
        for _i, c in ipairs(self.covers) do c.w:free() end
    end

    local Tap = P.Tap
    function I.collCard(o)
        local hair = T.px("hairline")
        local iw, ih = o.width - 2 * hair, o.height - 2 * hair
        local pad_l = T.px("sp-4")
        local m_w = iw - pad_l - P.px(36) - T.px("sp-1")
        local name = HorizontalGroup:new{ align = "center" }
        if o.is_fav then
            table.insert(name, icon("leaf.lib.heart", "icon-xs"))
            table.insert(name, HorizontalSpan:new{ width = T.px("sp-1h") })
        end
        table.insert(name, text(o.title or o.name, "ui-semibold", "fs-md", "text", m_w - (o.is_fav and T.px("icon-xs") + T.px("sp-1h") or 0)))
        local n = #o.files
        local meta_col = VerticalGroup:new{ align = "left", name, VerticalSpan:new{ width = T.px("sp-half") },
            text(string.format(n == 1 and _("%d book · %d finished") or _("%d books · %d finished"), n, o.finished or 0), "ui", "fs-sm", "text-3", m_w) }
        local mh = meta_col:getSize().h + 2 * T.px("sp-2h")
        meta_col:resetLayout()
        local more_btn = Tap:new{ content = CenterContainer:new{ dimen = geom(P.px(36), P.px(36)), icon("leaf.more.v", "icon-md") },
            callback = o.hold }
        local meta = OverlapGroup:new{ dimen = geom(iw, mh),
            LeftContainer:new{ dimen = geom(iw, mh), HorizontalGroup:new{ HorizontalSpan:new{ width = pad_l }, meta_col } },
            RightContainer:new{ dimen = geom(iw, mh), HorizontalGroup:new{ align = "center", more_btn, HorizontalSpan:new{ width = T.px("sp-1") } } } }
        local body = VerticalGroup:new{ align = "left",
            Stack:new{ width = iw, height = ih - mh - hair, files = o.files },
            require("ui/widget/linewidget"):new{ dimen = geom(iw, hair), background = T.color("border") },
            meta }
        local frame = require("ui/widget/container/framecontainer"):new{ bordersize = hair, color = T.color("border"),
            background = T.color("surface"), radius = T.px("r-lg"), padding = 0, margin = 0, body }
        return Tap:new{ content = frame, callback = o.callback, hold_callback = o.hold }
    end

    -- the dashed "New collection" card (.lb-ccard.new)
    local Dashed = Widget:extend{ width = 0, height = 0, content = nil }
    function Dashed:init() self.dimen = geom(self.width, self.height) end
    function Dashed:getSize() return self.dimen end
    function Dashed:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local w, h, r = self.width, self.height, T.px("r-lg")
        local hair = T.px("hairline")
        bb:paintBorder(x, y, w, h, hair, T.color("border-strong"), r)
        local dash, bg = P.px(4), T.color("bg")
        for xx = x + r + dash, x + w - r - dash, 2 * dash do
            bb:paintRect(xx, y, dash, hair, bg)
            bb:paintRect(xx, y + h - hair, dash, hair, bg)
        end
        for yy = y + r + dash, y + h - r - dash, 2 * dash do
            bb:paintRect(x, yy, hair, dash, bg)
            bb:paintRect(x + w - hair, yy, hair, dash, bg)
        end
        local sz = self.content:getSize()
        self.content:paintTo(bb, x + math.floor((w - sz.w) / 2), y + math.floor((h - sz.h) / 2))
    end
    function I.newCollCard(o)
        local tw = o.width - 2 * T.px("sp-4")
        local col = VerticalGroup:new{ align = "center",
            I.InkIcon:new{ icon = "leaf.lib.plus", size = T.px("icon-lg"), color = T.color("accent") },
            VerticalSpan:new{ width = T.px("sp-1") + T.px("sp-1h") },
            text(_("New collection"), "ui-medium", "fs-md", "text-2", tw),
            VerticalSpan:new{ width = T.px("sp-1h") },
            text(_("Group books by theme, mood or plan"), "ui", "fs-sm", "text-3", tw) }
        return Tap:new{ content = Dashed:new{ width = o.width, height = o.height, content = col }, callback = o.callback }
    end

    cache = I
    return I
end
