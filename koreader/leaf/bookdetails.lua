--[[
    Leaf book details (prototype overlay "book-details"): KOReader's "Book information" opens this
    page (a scrolling page, swipe up / down).

      header:  ‹ Book details · ♥ favourite · collections · ⋮ (the book-actions sheet)
      hero:    cover · eyebrow (series, else the folder) · title (Playfair --fs-2xl) · author ·
               year · pages · FORMAT · size · language · ★★★★★ rating (tap = rate) ·
               collection chips (tap = open the collection)
      card:    "8%" · page x of y · time left · progress line · Status: Reading | On hold | Finished
      about:   ABOUT THIS BOOK + the description (book face; tap = full text)
      notes:   HIGHLIGHTS & NOTES · "2 highlights · 3 bookmarks" · View all › (bookmark browser);
               up to 3 highlights (accent edge, note, chapter · page · date), or a dashed hint
      details: facts in two columns + the file path
      rows:    Bookmarks · Export highlights · Status, rating & review (KOReader's editor) ·
               Book information (KOReader's full metadata list: editing, custom cover, notebook…)
      footer:  Resume reading / Start reading / Read again (primary, % · time left) · add to
               collection · ⋯ (book actions)
    Status, rating, favourites and collections write through KOReader's own code (summary +
    BookList cache, ReadCollection), so the library and reader see the same values.
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local BookInfo = require("apps/filemanager/filemanagerbookinfo")
    local BookList = require("ui/widget/booklist")
    local ReadCollection = require("readcollection")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local util = require("util")
    local lfs = require("libs/libkoreader-lfs")

    local function geom(w, h) return Geom:new{ x = 0, y = 0, w = math.floor(w), h = math.floor(h) } end
    local function fm() return require("apps/filemanager/filemanager").instance end

    -- a box painted behind content (buttons, highlight quotes with an accent edge, dashed hint)
    local Box = Widget:extend{ w = 0, h = 0, content = nil, bg = nil, border = nil, radius = 0, edge = nil, dashed = false }
    function Box:init() self.dimen = geom(self.w, self.h) end
    function Box:getSize() return self.dimen end
    function Box:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if self.bg then bb:paintRoundedRect(x, y, self.w, self.h, self.bg, self.radius) end
        if self.border then
            bb:paintBorder(x, y, self.w, self.h, T.px("hairline"), self.border, self.radius)
            if self.dashed then
                local dash, hair, bg = Screen:scaleBySize(4 * T.scale), T.px("hairline"), T.color("bg")
                for xx = x + self.radius + dash, x + self.w - self.radius - dash, 2 * dash do
                    bb:paintRect(xx, y, dash, hair, bg) bb:paintRect(xx, y + self.h - hair, dash, hair, bg)
                end
                for yy = y + self.radius + dash, y + self.h - self.radius - dash, 2 * dash do
                    bb:paintRect(x, yy, hair, dash, bg) bb:paintRect(x + self.w - hair, yy, hair, dash, bg)
                end
            end
        end
        if self.edge then bb:paintRect(x, y, T.px("bw-xl"), self.h, self.edge) end
        if self.content then self.content:paintTo(bb, x, y) end
    end
    function Box:free() if self.content and self.content.free then self.content:free() end end

    local Page = InputContainer:extend{ covers_fullscreen = true }

    function Page:init()
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end

    function Page:status()
        local info = BookList.getBookInfo(self.file) or {}
        return info.been_opened and (info.status or "reading") or "new", info
    end

    function Page:summary()
        local ds = self.doc_settings_or_file
        if type(ds) ~= "table" then
            ds = BookList.getDocSettings(self.file)
            self.doc_settings_or_file = ds
        end
        return ds, ds:readSetting("summary") or {}
    end

    function Page:showActions()
        local f = fm()
        if f and f.file_chooser and f.file_chooser.showFileDialog then
            f.file_chooser:showFileDialog({ path = self.file, is_file = true, text = self.file:match("([^/]+)$") })
        end
    end

    function Page:showCollections()
        local f = fm()
        if f and f.collections then
            f.collections:onShowCollList(self.file, function() self:rebuild() end, true)
        end
    end

    function Page:build()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local K = require("leaf/syskit")(L)
        local I = require("leaf/libitems")(L)
        local P = require("leaf/widgets/libparts")
        local pad = T.px("sp-5")
        local file = self.file
        local props = self.props or {}
        local status, info = self:status()
        local d = I.data(file)
        local cw_ = W - 2 * pad

        ------------------------------------------------ header (.lbd-head)
        local fav = ReadCollection:isFileInCollection(file, ReadCollection.default_collection_name)
        local left = HorizontalGroup:new{ align = "center", K.hspan("sp-2"),
            K.icon_button("chevron.left", function() UIManager:close(self) end, self),
            K.text(_("Book details"), "ui", "fs-md", "text-2") }
        local fav_btn = K.icon_button(fav and "leaf.lib.heart.on" or "leaf.lib.heart", function()
            if fav then ReadCollection:removeItem(file, ReadCollection.default_collection_name)
            else ReadCollection:addItem(file, ReadCollection.default_collection_name) end
            ReadCollection:write({ [ReadCollection.default_collection_name] = true })
            self:rebuild()
        end, self)
        local right = HorizontalGroup:new{ align = "center", fav_btn,
            K.icon_button("leaf.lib.library", function() self:showCollections() end, self),
            K.icon_button("leaf.more.v", function() self:showActions() end, self),
            K.hspan("sp-2") }
        local hh = T.px("h-header")
        local header = OverlapGroup:new{ dimen = geom(W, hh),
            LeftContainer:new{ dimen = geom(W, hh), left },
            RightContainer:new{ dimen = geom(W, hh), right } }

        ------------------------------------------------ hero (.lbd-hero)
        local cover_w = P.px(168)
        local cover_h = math.floor(cover_w * 1.5)
        local cover = P.coverBox(file, cover_w, cover_h, { title = d.title })
        local col_w = W - 2 * pad - cover_w - T.px("sp-6")
        local col = VerticalGroup:new{ align = "left", K.vspan("sp-1") }
        local eyebrow, eicon
        if props.series and props.series ~= "" then
            eyebrow = props.series .. (props.series_index and (" · " .. T_(_("Book %1"), (tostring(props.series_index):gsub("%.0$", "")))) or "")
            eicon = "leaf.lib.library"
        else
            eyebrow, eicon = (file:match("([^/]+)/[^/]+$") or ""), "leaf.lib.folder"
        end
        if eyebrow ~= "" then
            table.insert(col, HorizontalGroup:new{ align = "center",
                I.InkIcon:new{ icon = eicon, size = T.px("icon-xs"), color = T.color("accent") }, K.hspan("sp-1h"),
                K.text(eyebrow:upper(), "ui-semibold", "fs-xs", "accent", col_w) })
        end
        table.insert(col, K.vspan("sp-2"))
        local title = props.display_title or props.title or d.title
        table.insert(col, TextBoxWidget:new{ text = title, face = L.face("display-semibold", "fs-2xl"), width = col_w, bgcolor = T.color("bg"),
            height = math.floor(cover_h * 0.45), height_overflow_show_ellipsis = true, height_adjust = true, line_height = 0.12 })
        table.insert(col, K.vspan("sp-2"))
        if props.authors and props.authors ~= "" then
            table.insert(col, K.text((props.authors:gsub("\n", " · "):gsub(";%s*", " · ")), "ui", "fs-lg", "text-2", col_w))
        end
        local _dir, fname = util.splitFilePathName(file)
        local _base, ftype = filemanagerutil.splitFileNameType(fname or "")
        local bits = {}
        local year = props.pubdate or props.date
        year = year and tostring(year):match("%d%d%d%d")
        if year then table.insert(bits, year) end
        local pages = props.pages or info.pages or d.pages
        if pages then table.insert(bits, T_(_("%1 pages"), pages)) end
        if ftype and ftype ~= "" then table.insert(bits, ftype:upper()) end
        if d.size then table.insert(bits, d.size) end
        if props.language and props.language ~= "" then table.insert(bits, props.language) end
        table.insert(col, K.vspan("sp-3"))
        table.insert(col, K.textbox(table.concat(bits, "  ·  "), "ui", "fs-sm", "text-3", col_w))
        -- rating (.lbd-rate): tap a star to rate, the current one again to clear
        local _ds, summary = self:summary()
        local rating = summary.rating or 0
        local stars = HorizontalGroup:new{ align = "center" }
        local ss = T.px("icon-tile")
        for i = 1, 5 do
            local st = K.tap(CenterContainer:new{ dimen = geom(P.px(26), P.px(26)),
                i <= rating and I.InkIcon:new{ icon = "leaf.lib.star.on", size = ss, color = T.color("accent") }
                    or I.InkIcon:new{ icon = "leaf.lib.star", size = ss, color = T.color("border-strong") } },
                function()
                    local ds, sm = self:summary()
                    sm.rating = (sm.rating == i) and nil or i
                    filemanagerutil.saveSummary(ds, sm)
                    self:rebuild()
                end)
            if i > 1 then table.insert(stars, K.hspan("sp-half")) end
            table.insert(stars, st)
        end
        table.insert(stars, K.hspan("sp-2"))
        table.insert(stars, K.text(rating > 0 and (rating .. ".0") or _("Not rated"), "ui", "fs-sm", "text-3"))
        table.insert(col, K.vspan("sp-3"))
        table.insert(col, stars)
        -- collection chips (.lbd-colls)
        local colls = {}
        for name in pairs(ReadCollection:getCollectionsWithFile(file) or {}) do table.insert(colls, name) end
        table.sort(colls, function(a, b)
            if a == ReadCollection.default_collection_name then return true end
            if b == ReadCollection.default_collection_name then return false end
            return a < b
        end)
        if #colls > 0 then
            local chips = {}
            for _i, name in ipairs(colls) do
                local is_fav = name == ReadCollection.default_collection_name
                table.insert(chips, K.chip{ label = is_fav and _("Favorites") or name, icon = is_fav and "leaf.lib.heart" or "leaf.lib.library",
                    callback = function()
                        UIManager:close(self)
                        local f = fm()
                        if f and f.collections then f.collections:onShowColl(name) end
                    end })
            end
            table.insert(col, K.vspan("sp-3"))
            table.insert(col, K.chip_row(chips, col_w, T.px("sp-1h")))
        end
        local hero = HorizontalGroup:new{ align = "top", K.hspan(pad), cover, K.hspan("sp-6"), col }

        ------------------------------------------------ progress card (.lbd-progress)
        local card_w = cw_
        local cin = K.inner(card_w)
        local pct = math.floor((info.percent_finished or 0) * 100 + 0.5)
        local started = status ~= "new"
        local line, right_txt
        if started and pages then
            line = T_(_("Page %1 of %2"), math.max(1, math.floor((info.percent_finished or 0) * pages + 0.5)), pages)
        else
            line = _("Not started yet")
        end
        if status == "complete" then
            right_txt = _("Finished") .. (d.last and (" " .. I.ago(d.last)) or "")
        elseif started and d.minleft then
            right_txt = T_(_("%1 left"), I.dur(d.minleft))
        elseif pages then
            right_txt = "≈ " .. T_(_("%1 to read"), I.dur(math.floor(pages * 1.6 + 0.5)))
        end
        local big = HorizontalGroup:new{ align = "bottom",
            K.text(tostring(pct), "ui-semibold", "fs-2xl", "text"), K.hspan(P.px(1)),
            VerticalGroup:new{ K.text("%", "ui-medium", "fs-md", "text-3"), K.vspan(P.px(2)) } }
        local bh = big:getSize().h
        big:resetLayout()
        local prow = OverlapGroup:new{ dimen = geom(cin, bh),
            LeftContainer:new{ dimen = geom(cin, bh), HorizontalGroup:new{ align = "center", big, K.hspan("sp-3"),
                K.text(line, "ui", "fs-sm", "text-2", math.floor(cin * 0.45)) } } }
        if right_txt then
            table.insert(prow, RightContainer:new{ dimen = geom(cin, bh), K.text(right_txt, "ui", "fs-sm", "text-3", math.floor(cin * 0.35)) })
        end
        local slabel = K.text(_("Status"), "ui", "fs-sm", "text-2")
        local seg = I.statusSeg(cin - T.px("sp-3") - slabel:getSize().w, started and status or nil, function(key)
            local ds, sm = self:summary()
            sm.status = key
            filemanagerutil.saveSummary(ds, sm)
            BookList.setBookInfoCacheProperty(file, "status", key)
            self:rebuild()
        end)
        local card = K.card(card_w, VerticalGroup:new{ align = "left",
            prow, K.vspan("sp-3"),
            P.Bar:new{ width = cin, height = P.px(4), pct = info.percent_finished or 0 },
            K.vspan("sp-4"),
            HorizontalGroup:new{ align = "center", slabel, K.hspan("sp-3"), seg } })

        ------------------------------------------------ sections
        local function eyebrow_row(t, sub, link, cb)
            local rh = T.px("h-chip")
            local lg = HorizontalGroup:new{ align = "center", K.text(t:upper(), "ui-semibold", "fs-xs", "text-3") }
            if sub then
                table.insert(lg, K.hspan("sp-3"))
                table.insert(lg, K.text(sub, "ui", "fs-sm", "text-3"))
            end
            local g = OverlapGroup:new{ dimen = geom(cw_, rh), LeftContainer:new{ dimen = geom(cw_, rh), lg } }
            if link then
                table.insert(g, RightContainer:new{ dimen = geom(cw_, rh), K.tap(HorizontalGroup:new{ align = "center",
                    K.text(link, "ui-medium", "fs-sm", "accent"),
                    I.InkIcon:new{ icon = "leaf.lib.chevright", size = T.px("icon-sm"), color = T.color("accent") } }, cb) })
            end
            return g
        end
        local secs = VerticalGroup:new{ align = "left" }
        local desc = props.description
        if desc and desc ~= "" then
            desc = util.htmlToPlainTextIfHtml and util.htmlToPlainTextIfHtml(desc) or desc
            table.insert(secs, K.vspan("sp-6"))
            table.insert(secs, eyebrow_row(_("About this book")))
            table.insert(secs, K.vspan("sp-2"))
            table.insert(secs, K.tap(TextBoxWidget:new{ text = desc, face = L.face("book", "fs-md"), width = cw_, bgcolor = T.color("bg"),
                line_height = 0.4, height = Screen:scaleBySize(150 * T.scale), height_overflow_show_ellipsis = true, height_adjust = true },
                function() BookInfo:onShowBookDescription(props.description, file) end))
        end
        -- highlights & notes
        local ann = {}
        if started then
            local ds = self:summary()
            ann = ds:readSetting("annotations") or {}
        end
        local hls, nbm = {}, 0
        for _i, a in ipairs(ann) do
            if a.text and a.text ~= "" then table.insert(hls, a) else nbm = nbm + 1 end
        end
        local function browse()
            local f = fm()
            if f and f.collections then
                local b = f.collections:genBookmarkBrowserButton({ [file] = true }, function() end)
                if b and b.callback then b.callback() end
            end
        end
        table.insert(secs, K.vspan("sp-6"))
        table.insert(secs, eyebrow_row(_("Highlights & notes"),
            T_(#hls == 1 and _("%1 highlight") or _("%1 highlights"), #hls) .. " · " .. T_(nbm == 1 and _("%1 bookmark") or _("%1 bookmarks"), nbm),
            #ann > 0 and _("View all") or nil, browse))
        table.insert(secs, K.vspan("sp-2"))
        if #hls > 0 then
            for i = 1, math.min(3, #hls) do
                local a = hls[i]
                local iw = cw_ - T.px("bw-xl") - 2 * T.px("sp-4")
                local q = VerticalGroup:new{ align = "left",
                    TextBoxWidget:new{ text = a.text, face = L.face("book", "fs-md"), width = iw, bgcolor = T.color("surface"), line_height = 0.3 } }
                if a.note and a.note ~= "" then
                    table.insert(q, K.vspan("sp-2"))
                    table.insert(q, HorizontalGroup:new{ align = "center",
                        I.InkIcon:new{ icon = "leaf.lib.stickynote", size = T.px("icon-sm"), color = T.color("accent") }, K.hspan("sp-1h"),
                        K.text(a.note, "ui", "fs-sm", "text-2", iw - T.px("icon-sm") - T.px("sp-1h")) })
                end
                local src = {}
                if a.chapter and a.chapter ~= "" then table.insert(src, a.chapter) end
                if a.pageno then table.insert(src, "p. " .. a.pageno) end
                if a.datetime then
                    local y, mo, dd = a.datetime:match("(%d+)-(%d+)-(%d+)")
                    if y then table.insert(src, I.fmtDate(os.time{ year = tonumber(y), month = tonumber(mo), day = tonumber(dd), hour = 12 })) end
                end
                table.insert(q, K.vspan("sp-2"))
                table.insert(q, K.text(table.concat(src, " · "), "ui", "fs-xs", "text-3", iw))
                local qh = q:getSize().h + 2 * T.px("sp-3")
                q:resetLayout()
                table.insert(secs, Box:new{ w = cw_, h = qh, bg = T.color("surface"), radius = T.px("r-md"), edge = T.color("accent"),
                    content = HorizontalGroup:new{ K.hspan(T.px("bw-xl") + T.px("sp-4")), VerticalGroup:new{ K.vspan("sp-3"), q } } })
                table.insert(secs, K.vspan("sp-2"))
            end
        else
            local hint = HorizontalGroup:new{ align = "center", K.icon("leaf.lib.highlighter", "icon-md"), K.hspan("sp-3"),
                K.textbox(_("No highlights yet. Long-press text while reading to highlight a passage."), "ui", "fs-sm", "text-3",
                    cw_ - 2 * T.px("sp-4") - T.px("icon-md") - T.px("sp-3")) }
            local hh2 = hint:getSize().h + 2 * T.px("sp-4")
            hint:resetLayout()
            table.insert(secs, Box:new{ w = cw_, h = hh2, border = T.color("border-strong"), radius = T.px("r-md"), dashed = true,
                content = HorizontalGroup:new{ K.hspan("sp-4"), VerticalGroup:new{ K.vspan("sp-4"), hint } } })
        end
        -- details (.lbd-facts: two columns)
        local facts = {}
        local function fact(k, v) if v and v ~= "" then table.insert(facts, { k, tostring(v) }) end end
        fact(_("Author"), props.authors and (props.authors:gsub("\n", " · ")))
        fact(_("Published"), year)
        fact(_("Pages"), pages)
        fact(_("Format"), ftype and ftype:upper())
        fact(_("Size"), d.size)
        fact(_("Language"), props.language)
        fact(_("Publisher"), props.publisher)
        if props.series and props.series ~= "" then
            fact(_("Series"), props.series .. (props.series_index and (" #" .. (tostring(props.series_index):gsub("%.0$", ""))) or ""))
        end
        if d.added then fact(_("Added"), I.fmtDate(d.added) .. ", " .. os.date("%Y", d.added)) end
        fact(_("Last read"), d.last and I.ago(d.last) or _("Never"))
        table.insert(secs, K.vspan("sp-6"))
        table.insert(secs, eyebrow_row(_("Details")))
        local fw = math.floor((cw_ - T.px("sp-6")) / 2)
        for i = 1, #facts, 2 do
            local r = HorizontalGroup:new{ align = "top" }
            for j = i, math.min(i + 1, #facts) do
                local f = facts[j]
                local kt = K.text(f[1], "ui", "fs-sm", "text-3")
                local fh = kt:getSize().h + 2 * T.px("sp-2h")
                local cell = VerticalGroup:new{ align = "left",
                    OverlapGroup:new{ dimen = geom(fw, fh),
                        LeftContainer:new{ dimen = geom(fw, fh), kt },
                        RightContainer:new{ dimen = geom(fw, fh), K.text(f[2], "ui", "fs-sm", "text", fw - kt:getSize().w - T.px("sp-3")) } },
                    K.line(fw) }
                if j > i then table.insert(r, K.hspan("sp-6")) end
                table.insert(r, cell)
            end
            table.insert(secs, r)
        end
        table.insert(secs, K.vspan("sp-3"))
        table.insert(secs, HorizontalGroup:new{ align = "center", K.icon("leaf.lib.folder", "icon-sm"), K.hspan("sp-2"),
            K.text(file, "ui", "fs-sm", "text-3", cw_ - T.px("icon-sm") - T.px("sp-2")) })
        -- rows (.lbd-more)
        local inner_g = cw_ - 2 * T.px("hairline")
        local function grow(icon, label, value, cb)
            local tr = HorizontalGroup:new{ align = "center" }
            if value then table.insert(tr, K.text(value, "ui", "fs-sm", "text-3")) table.insert(tr, K.hspan("sp-2")) end
            table.insert(tr, K.icon("leaf.lib.chevright", "icon-sm"))
            return K.row{ width = inner_g, icon = icon, label = label, trailing = tr, pad = T.px("sp-4"), callback = cb }
        end
        local rows = {
            grow("leaf.lib.bookmark", _("Bookmarks"), tostring(nbm), browse),
            grow("leaf.lib.fileoutput", _("Export highlights"), tostring(#hls), function()
                local f = fm()
                if f and f.collections then
                    local b = f.collections:genExportHighlightsButton({ [file] = true }, function() end)
                    if b and b.callback and b.enabled ~= false then b.callback() end
                end
            end),
            grow("leaf.lib.stickynote", _("Status, rating & review"), nil, function()
                self.bookinfo:editSummary(self.doc_settings_or_file, self.props_in or props)
            end),
            grow("leaf.lib.info", _("Book information"), nil, function()
                self.orig_show(self.bookinfo, self.doc_settings_or_file, self.props_in)
            end),
        }
        table.insert(secs, K.vspan("sp-6"))
        table.insert(secs, K.card(cw_, K.list(rows, inner_g, { inset = T.px("sp-4") }), { flush = true }))
        table.insert(secs, K.vspan("sp-6"))

        local content = VerticalGroup:new{ align = "left",
            K.vspan("sp-2"), hero, K.vspan("sp-6"),
            HorizontalGroup:new{ K.hspan(pad), card },
            HorizontalGroup:new{ K.hspan(pad), secs } }

        ------------------------------------------------ footer (.lbd-foot)
        local hc = T.px("h-control")
        local go_label = status == "complete" and _("Read again") or (started and _("Resume reading") or _("Start reading"))
        local go = HorizontalGroup:new{ align = "center",
            I.InkIcon:new{ icon = started and "leaf.lib.bookopen" or "leaf.lib.play", size = T.px("icon-md"), color = T.color("accent-ink") },
            K.hspan("sp-2"), K.text(go_label, "ui-semibold", "fs-md", "accent-ink") }
        if started and status ~= "complete" then
            table.insert(go, K.hspan("sp-3"))
            table.insert(go, K.text(pct .. "% · " .. (d.minleft and (I.durShort(d.minleft) .. " " .. _("left")) or ""), "ui", "fs-sm", "accent-ink"))
        end
        local go_w = W - 2 * pad - 2 * (hc + T.px("sp-2"))
        local go_btn = K.tap(Box:new{ w = go_w, h = hc, bg = T.color("accent"), radius = T.px("r-md"),
            content = CenterContainer:new{ dimen = geom(go_w, hc), go } }, function()
                UIManager:close(self)
                local RUI = package.loaded["apps/reader/readerui"]
                local cur = RUI and RUI.instance
                if cur and cur.document and cur.document.file == file then return end
                require("apps/reader/readerui"):showReader(file)
            end)
        local function sq(icon, cb)
            return K.tap(Box:new{ w = hc, h = hc, bg = T.color("surface-2"), border = T.color("border"), radius = T.px("r-md"),
                content = CenterContainer:new{ dimen = geom(hc, hc), K.icon(icon, "icon-md") } }, cb)
        end
        local foot_in = HorizontalGroup:new{ align = "center", go_btn, K.hspan("sp-2"),
            sq("leaf.lib.listplus", function() self:showCollections() end), K.hspan("sp-2"),
            sq("leaf.lib.ellipsis", function() self:showActions() end) }
        local foot_h = hc + T.px("sp-3") + T.px("sp-4")
        local foot = FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg-raised"),
            VerticalGroup:new{ K.line(W), CenterContainer:new{ dimen = geom(W, foot_h - T.px("hairline")), foot_in } } }

        ------------------------------------------------ page: header, scrolling body, footer
        local body_h = H - hh - foot_h
        local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
        local scroll = ScrollableContainer:new{ dimen = geom(W, body_h), show_parent = self,
            FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), width = W, content } }
        self.cropping_widget = scroll
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), width = W, height = H,
            VerticalGroup:new{ align = "left", header, scroll, foot } }
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

    L.wrap(BookInfo, "show", function(orig, self, doc_settings_or_file, book_props)
        local has_sidecar = type(doc_settings_or_file) == "table"
        local file = has_sidecar and doc_settings_or_file:readSetting("doc_path") or doc_settings_or_file
        if not file or not lfs.attributes(file, "mode") then return orig(self, doc_settings_or_file, book_props) end
        if not has_sidecar and BookList.hasBookBeenOpened(file) then
            doc_settings_or_file = BookList.getDocSettings(file)
        end
        local props = book_props or self:getDocProps(file, book_props)
        UIManager:show(Page:new{ file = file, props = props, props_in = book_props, bookinfo = self,
            doc_settings_or_file = doc_settings_or_file, orig_show = orig })
    end, "BookInfo:show")
end

return M
