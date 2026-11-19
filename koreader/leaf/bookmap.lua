--[[
    Leaf book map and page browser (prototype overlays "bookmap" / "pagebrowser").

    Both are Leaf screens now (LeafMap, LeafPages below), opened by KOReader's ShowBookMap /
    ShowPageBrowser: the prototype's chapter grid and thumbnail grid. KOReader's own widgets stay
    reachable from their "⋮" (all their menus and settings), and the overview mode of the book map
    (ShowBookMap with overview) is still KOReader's. Those widgets keep a Leaf restyle:

      * page background --bg; the title bar is Leaf's (titlebar.lua)
      * chapter spans: --surface-2 boxes (alternate theme: --surface-2 / --surface-3) with a --border
        hairline, --r-thumb corners and Inter --text-2 titles; the pages frame in --border-strong
      * read pages: --text-2 bars (pages read this session: --text-3), like .rd-map .cell.read
      * current page: an accent outline around its slot (.cell.here) and an accent ▲ under it;
        bookmark / highlight / note / location marks in --text-2
      * page numbers: Inter --fs-2xs in --text-3
      * page browser: thumbnails get a --border hairline frame with --r-cover corners, the current page
        an accent --bw-lg frame (.rd-thumb.here); the view finder on the ribbon is accent
--]]
local Blitbuffer = require("ffi/blitbuffer")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")
local TextWidget = require("ui/widget/textwidget")

local M = {}

function M.apply(L)
    local T = L.T
    local BookMapWidget = require("ui/widget/bookmapwidget")
    local BookMapRow = BookMapWidget.BookMapRow
    local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
    local FrameContainer = require("ui/widget/container/framecontainer")

    local function is_a(obj, class)
        local mt = getmetatable(obj)
        while mt do
            if mt == class then return true end
            mt = getmetatable(mt)
        end
        return false
    end

    ---------------------------------------------------------------- the ribbon (both widgets)
    L.wrap(BookMapRow, "init", function(orig, self)
        orig(self)
        local frame = self.pages_frame
        if frame and frame[1] and is_a(frame[1], FrameContainer) then
            frame[1].color = T.color("border-strong")
        end
        local alt = 0
        for i = 2, #(frame or {}) do
            local span = frame[i]
            if is_a(span, FrameContainer) and span.background and not span.focusable_page_slot then
                alt = alt + 1
                span.color = T.color("border")
                span.background = self.alt_theme and T.color(alt % 2 == 0 and "surface-2" or "surface-3") or T.color("surface-2")
                span.radius = T.px("r-thumb")
                local cc = span[1]
                local tw = cc and cc[1]
                if tw and is_a(tw, TextWidget) then
                    tw.fgcolor = T.color("text-2")
                end
            end
        end
        for _i, f in ipairs(self.background_fillers or {}) do
            f.color = T.color("surface-3")
        end
        local black, gray5 = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_5
        for _i, m in ipairs(self.pages_markers or {}) do
            local c = m.color
            if c and c == gray5 then
                m.color = T.color("text-3")
            elseif c and c == black then
                m.color = T.color("text-2")
            end
        end
        self.smaller_font_face = L.face("ui", "fs-2xs")
    end, "BookMapRow:init")

    -- same painting as KOReader's, with Leaf colours and the current page outlined
    L.wrap(BookMapRow, "paintTo", function(orig, self, bb, x, y)
        local ox = x + self.pages_frame_offset_x
        for _i, filler in ipairs(self.background_fillers) do
            if filler.stripe_width then
                bb:hatchRect(ox + filler.x, y + filler.y, filler.w, filler.h, filler.stripe_width, filler.color)
            else
                bb:paintRect(ox + filler.x, y + filler.y, filler.w, filler.h, filler.color)
            end
        end
        InputContainer.paintTo(self, bb, x, y)
        -- current page slot (.rd-map .cell.here): accent-soft fill under the read bar, accent outline over it
        local here
        local cur = self.cur_page
        if cur and cur >= self.start_page and cur <= self.end_page then
            local px0 = self:getPageX(cur)
            local px1 = self:getPageX(cur, true)
            local bw = math.max(1, T.px("bw-md"))
            local fb = self.pages_frame_border
            local top = y + fb + self.span_height * math.max(1, self.nb_toc_spans or 1)
            local h = y + self.pages_frame_height - fb - top
            if h > 2 * bw then
                here = { x = ox + px0, y = top, w = math.max(2 * bw + 1, px1 - px0), h = h, bw = bw }
                bb:paintRect(here.x, here.y, here.w, here.h, T.color("accent-soft"))
            end
        end
        for _i, marker in ipairs(self.pages_markers) do
            bb:paintRect(ox + marker.x, y + marker.y, marker.w, marker.h, marker.color)
        end
        if here then bb:paintBorder(here.x, here.y, here.w, here.h, here.bw, T.color("accent")) end
        local accent, ink = T.color("accent"), T.color("text-2")
        for _i, indicator in ipairs(self.indicators) do
            local glyph = RenderText:getGlyph(indicator.face or self.font_face, indicator.c)
            local alt_bb
            if indicator.rotation then alt_bb = glyph.bb:rotatedCopy(indicator.rotation) end
            local d_x = math.floor(glyph.bb:getWidth() * (indicator.shift_x_pct or 0.5))
            bb:colorblitFrom(alt_bb or glyph.bb, ox + indicator.x - d_x, y + indicator.y, 0, 0,
                glyph.bb:getWidth(), glyph.bb:getHeight(), indicator.c == 0x25B2 and accent or ink)
            if alt_bb then alt_bb:free() end
        end
        for _i, btext in ipairs(self.bottom_texts) do
            local text_w = TextWidget:new{ text = btext.text, face = self.smaller_font_face, padding = 0, fgcolor = T.color("text-3") }
            local d_y = self.height - math.ceil(text_w:getSize().h)
            local text_width = text_w:getWidth()
            local d_width = btext.slot_width - text_width
            local d_x
            if not btext.block or d_width >= 2 * btext.block_dx then
                d_x = math.ceil(d_width / 2)
            elseif btext.block == "left" then
                d_x = btext.block_dx
            else
                d_x = d_width - btext.block_dx
            end
            text_w:paintTo(bb, ox + btext.x + d_x, y + d_y)
            text_w:free()
        end
    end, "BookMapRow:paintTo")

    ---------------------------------------------------------------- book map
    L.wrap(BookMapWidget, "init", function(orig, self)
        orig(self)
        if self[1] then self[1].background = T.color("bg") end
    end, "BookMapWidget:init")

    ---------------------------------------------------------------- page browser
    L.wrap(PageBrowserWidget, "updateLayout", function(orig, self)
        orig(self)
        if self[1] then self[1].background = T.color("bg") end
        for i = 1, self.nb_grid_items or 0 do
            local f = self.grid and self.grid[i]
            if f and f.background then f.background = T.color("bg") end
        end
    end, "PageBrowserWidget:updateLayout")

    L.wrap(PageBrowserWidget, "showTile", function(orig, self, grid_idx, page, tile, do_refresh)
        orig(self, grid_idx, page, tile, do_refresh)
        local item = self.grid[grid_idx]
        local thumb = item and item[1] and item[1][1]
        if thumb and thumb.is_page_thumbnail then
            local here = page == self.cur_page
            thumb.bordersize = here and T.px("bw-lg") or T.px("hairline")
            thumb.color = T.color(here and "accent" or "border-strong")
            thumb.radius = T.px("r-cover")
            thumb.background = T.color("page")
        end
    end, "PageBrowserWidget:showTile")

    L.wrap(PageBrowserWidget, "paintTo", function(orig, self, bb, x, y)
        InputContainer.paintTo(self, bb, x, y)
        for _i, r in ipairs(self.view_finder_row_lines or {}) do
            bb:hatchRect(r.x, r.y, r.w, r.h, r.h, T.color("text-2"), 0.3)
        end
        if self.view_finder_x then
            bb:paintBorder(self.view_finder_x, self.view_finder_y, self.view_finder_w, self.view_finder_h,
                self.view_finder_bw, T.color("accent"), self.view_finder_r)
        end
    end, "PageBrowserWidget:paintTo")

    ---------------------------------------------------------------- Leaf book map page
    --[[ the prototype's overlay "bookmap" (.rd-map): a full page
           status strip · ← Book map ······ ⋮ ▦     (⋮: KOReader's own book map, with its menu and
                                                     settings; ▦: the page browser)
           summary tiles: pages · read · bookmarks · highlights
           legend: Read · Unread · Current · Bookmark · Highlight
           one block per chapter: CHAPTER I  Silence ······ 1–5 · 60%, then a cell per page
       A tap on a cell goes to that page (location stack kept). Long books page with ‹ n / m ›
       and swipes. The overview mode (ShowBookMap with overview) stays KOReader's. ]]
    local Kit = require("leaf/widgets/kit")
    local Device = require("device")
    local Event = require("ui/event")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local LineWidget = require("ui/widget/linewidget")
    local UIManager = require("ui/uimanager")
    local Widget = require("ui/widget/widget")
    local _ = require("gettext")
    local T_ = require("ffi/util").template
    local Screen = Device.screen
    local function geom(w, h) return Geom:new{ x = 0, y = 0, w = w, h = h } end
    local function sc(v) return Screen:scaleBySize(v * T.scale) end

    -- a .cell (18x26, --r-thumb): read / unread / here, with bookmark ribbon and highlight dot
    local function paint_cell(bb, x, y, w, h, st)
        local r = T.px("r-thumb")
        if st.here then
            local o = T.px("bw-md") + 1
            bb:paintRoundedRect(x - o - T.px("bw-md"), y - o - T.px("bw-md"), w + 2 * (o + T.px("bw-md")), h + 2 * (o + T.px("bw-md")), T.color("text"), r + o)
            bb:paintRoundedRect(x - o, y - o, w + 2 * o, h + 2 * o, T.color("bg"), r + o)
            bb:paintRoundedRect(x, y, w, h, T.color("text"), r)
            bb:paintRoundedRect(x + 1, y + 1, w - 2, h - 2, T.color("accent"), r)
        elseif st.read then
            bb:paintRoundedRect(x, y, w, h, T.color("text-3"), r)
        else
            bb:paintBorder(x, y, w, h, T.px("hairline"), T.color("border-strong"), r)
        end
        if st.bm then -- ribbon at the top right, notched at the bottom
            local rw, rh = sc(6), sc(9)
            local rx, ry = x + w - sc(2) - rw, y - 1
            local cut = math.floor(rh * 0.7)
            for yy = 0, rh - 1 do
                if yy < cut then
                    bb:paintRect(rx, ry + yy, rw, 1, T.color("text"))
                else
                    local gap = math.floor((yy - cut + 1) / (rh - cut) * rw / 2 + 0.5)
                    local side = math.floor(rw / 2) - math.floor(gap / 2)
                    if side > 0 then
                        bb:paintRect(rx, ry + yy, side, 1, T.color("text"))
                        bb:paintRect(rx + rw - side, ry + yy, side, 1, T.color("text"))
                    end
                end
            end
        end
        if st.hl then -- dot at the bottom centre, with a --bg ring
            local d, ring = sc(6), T.px("bw-md")
            local dx, dy = x + math.floor((w - d) / 2), y + h - sc(3) - d
            bb:paintRoundedRect(dx - ring, dy - ring, d + 2 * ring, d + 2 * ring, T.color("bg"), math.floor(d / 2) + ring)
            bb:paintRoundedRect(dx, dy, d, d, T.color("text"), math.floor(d / 2))
        end
    end
    M.paint_cell = paint_cell

    -- one line of page cells; a tap goes to the page under it
    local CellLine = InputContainer:extend{ cells = nil, cw = 0, ch = 0, gap = 0, width = 0, height = 0 }
    function CellLine:init()
        self.dimen = geom(self.width, self.height)
        self.ges_events = { TapCell = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    function CellLine:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local top = y + math.floor((self.height - self.ch) / 2)
        for i, c in ipairs(self.cells) do
            paint_cell(bb, x + (i - 1) * (self.cw + self.gap), top, self.cw, self.ch, c)
        end
    end
    function CellLine:onTapCell(arg, ges)
        local i = math.floor((ges.pos.x - self.dimen.x) / (self.cw + self.gap)) + 1
        local c = self.cells[i]
        if c and self.on_page then self.on_page(c.page) end
        return true
    end

    -- a legend sample: a small cell
    local Sample = Widget:extend{}
    function Sample:init() self.dimen = geom(sc(10), sc(14)) end
    function Sample:paintTo(bb, x, y) paint_cell(bb, x, y, self.dimen.w, self.dimen.h, self.st) end

    local LeafMap = InputContainer:extend{ ui = nil, page = 1 }

    function LeafMap:marks()
        local ui, doc = self.ui, self.ui.document
        local bm, hl, nb, nh = {}, {}, 0, 0
        for _i, a in ipairs(ui.annotation and ui.annotation.annotations or {}) do
            local p = a.pageno or a.page
            if type(p) == "string" then p = doc:getPageFromXPointer(p) end
            if p then
                if a.drawer then hl[p] = true; nh = nh + 1 else bm[p] = true; nb = nb + 1 end
            end
        end
        return bm, hl, nb, nh
    end

    -- chapters: the top level of the TOC (pages before the first entry form their own block)
    function LeafMap:chapters(total)
        local toc = self.ui.toc
        if toc.fillToc then toc:fillToc() end
        local min_d = math.huge
        for _i, t in ipairs(toc.toc or {}) do min_d = math.min(min_d, t.depth or 1) end
        local list = {}
        for _i, t in ipairs(toc.toc or {}) do
            if (t.depth or 1) == min_d and t.page and t.page >= 1 and t.page <= total then
                if #list > 0 and list[#list].from == t.page then list[#list] = nil end
                table.insert(list, { title = t.title, from = t.page })
            end
        end
        if #list > 0 and list[1].from <= 3 then
            list[1].from = 1 -- a cover page or two before the first entry: part of it
        elseif #list == 0 or list[1].from > 1 then
            table.insert(list, 1, { title = #list == 0 and _("All pages") or _("Start"), from = 1 })
        end
        for i, c in ipairs(list) do c.to = (list[i + 1] and list[i + 1].from - 1) or total end
        return list
    end

    function LeafMap:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(W, H)
        self.covers_fullscreen = true
        self.ges_events = { Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end

    function LeafMap:goTo(p)
        local ui = self.ui
        UIManager:close(self)
        if ui.link then ui.link:addCurrentLocationToStack() end
        ui:handleEvent(Event:new("GotoPage", p))
    end

    function LeafMap:build()
        local ui = self.ui
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pad = T.px("sp-5")
        local cw = W - 2 * pad
        local doc = ui.document
        local total = doc:getPageCount() or 1
        local cur = (ui.view and ui.view.state and ui.view.state.page) or doc:getCurrentPage() or 1
        local bm, hl, nb, nh = self:marks()

        -- header: ← Book map ··· ⋮ ▦
        local back = Kit.icon_button("leaf.kb.left", function() self:onClose() end, self)
        local head_h = T.px("h-header")
        local actions = HorizontalGroup:new{ align = "center",
            Kit.icon_button("leaf.more.v", function()
                -- KOReader's own book map: its menu, TOC depth, pages per row, overview...
                UIManager:close(self)
                UIManager:show(BookMapWidget:new{ ui = ui })
            end, self),
            Kit.icon_button("leaf.bm.grid", function()
                UIManager:close(self)
                ui:handleEvent(Event:new("ShowPageBrowser"))
            end, self),
            HorizontalSpan:new{ width = T.px("sp-2") } }
        local header = OverlapGroup:new{ dimen = geom(W, head_h),
            LeftContainer:new{ dimen = geom(W, head_h), HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = T.px("sp-2") }, back, HorizontalSpan:new{ width = T.px("sp-2") },
                TextWidget:new{ text = _("Book map"), face = L.face("ui-semibold", "fs-lg") } } },
            RightContainer:new{ dimen = geom(W, head_h), actions } }

        -- summary tiles (.rd-map-sum)
        local tiles = HorizontalGroup:new{}
        local read_pct = math.floor((cur - 1) / math.max(1, total) * 100 + 0.5)
        local vals = { { tostring(total), _("pages") }, { read_pct .. "%", _("read") }, { tostring(nb), _("bookmarks") }, { tostring(nh), _("highlights") } }
        local hair = T.px("hairline")
        local tile_w = math.floor((cw - 2 * hair - 3 * hair) / 4)
        for i, v in ipairs(vals) do
            if i > 1 then table.insert(tiles, LineWidget:new{ dimen = geom(hair, sc(64)), background = T.color("border") }) end
            local col = VerticalGroup:new{ align = "left",
                TextWidget:new{ text = v[1], face = L.face("ui-semibold", "fs-lg") },
                VerticalSpan:new{ width = T.px("sp-half") },
                TextWidget:new{ text = v[2], face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3"), max_width = tile_w - 2 * T.px("sp-3") } }
            local th = col:getSize().h + 2 * T.px("sp-3")
            col:resetLayout()
            table.insert(tiles, LeftContainer:new{ dimen = geom(tile_w, th), HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-3") }, col } })
        end
        local tsz = tiles:getSize()
        tiles:resetLayout()
        local summary = FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = 0, width = cw, tiles }

        -- legend (.rd-map-legend)
        local legend = HorizontalGroup:new{ align = "center" }
        for i, it in ipairs({ { { read = true }, _("Read") }, { {}, _("Unread") }, { { here = true }, _("Current") },
                { { bm = true }, _("Bookmark") }, { { hl = true }, _("Highlight") } }) do
            if i > 1 then table.insert(legend, HorizontalSpan:new{ width = T.px("sp-4") }) end
            table.insert(legend, Sample:new{ st = it[1] })
            table.insert(legend, HorizontalSpan:new{ width = T.px("sp-1h") })
            table.insert(legend, TextWidget:new{ text = it[2], face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3") })
        end

        local status = Kit.status_strip(W)
        local fixed = VerticalGroup:new{ align = "left",
            status, header,
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, summary },
            VerticalSpan:new{ width = T.px("sp-3") },
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, legend },
            VerticalSpan:new{ width = T.px("sp-3") } }
        local fixed_h = fixed:getSize().h
        fixed:resetLayout()

        -- chapter blocks, split into lines, packed into screen pages
        local cell_w, cell_h, gap = sc(18), sc(26), T.px("sp-1")
        local per_line = math.max(1, math.floor((cw + gap) / (cell_w + gap)))
        local line_h = cell_h + gap + T.px("bw-md")
        local blocks = {}
        local here_block
        for _i, c in ipairs(self:chapters(total)) do
            local is_here = cur >= c.from and cur <= c.to
            local span = c.to - c.from + 1
            local done = math.max(0, math.min(span, cur - c.from))
            local pct = math.floor(done / span * 100 + 0.5)
            local range = (c.from == c.to) and tostring(c.from) or (c.from .. "–" .. c.to)
            if done >= span then range = range .. " · " .. _("read") elseif pct > 0 then range = range .. " · " .. pct .. "%" end
            local bs = require("leaf/booksheet")
            local eyebrow, title
            if bs.split_title then eyebrow, title = bs.split_title(c.title) else title = c.title end
            local rw = TextWidget:new{ text = range, face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3") }
            local hd = HorizontalGroup:new{ align = "center" }
            local left_w = cw - rw:getSize().w - T.px("sp-2")
            if eyebrow then
                local lw = TextWidget:new{ text = eyebrow:upper(), face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3") }
                table.insert(hd, lw)
                table.insert(hd, HorizontalSpan:new{ width = T.px("sp-2") })
                left_w = left_w - lw:getSize().w - T.px("sp-2")
            end
            table.insert(hd, TextWidget:new{ text = title, face = L.face(is_here and "ui-semibold" or "ui", "fs-md"), max_width = math.max(T.px("sp-5"), left_w) })
            local hd_h = hd:getSize().h
            hd:resetLayout()
            table.insert(blocks, { sep = true, h = T.px("sp-3") + hd_h + T.px("sp-2"), w = OverlapGroup:new{ dimen = geom(cw, T.px("sp-3") + hd_h + T.px("sp-2")),
                VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-3") }, LeftContainer:new{ dimen = geom(cw, hd_h), hd } },
                VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-3") }, RightContainer:new{ dimen = geom(cw, hd_h), rw } } } })
            if is_here then here_block = #blocks end
            local p = c.from
            while p <= c.to do
                local cells = {}
                for q = p, math.min(c.to, p + per_line - 1) do
                    table.insert(cells, { page = q, read = q < cur, here = q == cur, bm = bm[q], hl = hl[q] })
                end
                table.insert(blocks, { h = line_h, w = CellLine:new{ cells = cells, cw = cell_w, ch = cell_h, gap = gap,
                    width = cw, height = line_h, on_page = function(pg) self:goTo(pg) end } })
                p = p + per_line
            end
            blocks[#blocks].h = blocks[#blocks].h + T.px("sp-2")
        end
        local foot_h = T.px("hit")
        local avail = H - fixed_h - foot_h
        local pages, page_of, used = 1, {}, 0
        for i, b in ipairs(blocks) do
            local h = b.h + (b.sep and hair or 0)
            -- keep a chapter header with its first line
            local need = h + ((b.sep and blocks[i + 1]) and blocks[i + 1].h or 0)
            if used > 0 and used + need > avail then pages = pages + 1; used = 0 end
            used = used + h
            page_of[i] = pages
        end
        if self._first then self.page = page_of[here_block or 1] or 1 end
        self._first = false
        self.page = math.max(1, math.min(self.page, pages))
        self._pages = pages
        local body = VerticalGroup:new{ align = "left" }
        for i, b in ipairs(blocks) do
            if page_of[i] == self.page then
                if b.sep then table.insert(body, LineWidget:new{ dimen = geom(cw, hair), background = T.color("border") }) end
                table.insert(body, b.w)
            end
        end
        local foot = HorizontalGroup:new{ align = "center" }
        if pages > 1 then
            table.insert(foot, Kit.icon_button("chevron.left", function() self:flip(-1) end, self, "icon-sm"))
            table.insert(foot, TextWidget:new{ text = T_(_("%1 / %2"), self.page, pages), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") })
            table.insert(foot, Kit.icon_button("chevron.right", function() self:flip(1) end, self, "icon-sm"))
        end
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), width = W, height = H,
            OverlapGroup:new{ dimen = geom(W, H),
                VerticalGroup:new{ align = "left", fixed, HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, body } },
                require("ui/widget/container/bottomcontainer"):new{ dimen = geom(W, H), CenterContainer:new{ dimen = geom(W, foot_h), foot } } } }
    end

    function LeafMap:flip(d)
        local p = math.max(1, math.min(self._pages or 1, self.page + d))
        if p == self.page then return end
        self.page = p
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function LeafMap:onSwipe(arg, ges)
        local dir = ges.direction
        if dir == "west" or dir == "north" then self:flip(1)
        elseif dir == "east" or dir == "south" then self:flip(-1) end
        return true
    end
    function LeafMap:onClose()
        UIManager:close(self)
        return true
    end
    function LeafMap:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function LeafMap:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end
    M.LeafMap = LeafMap

    local ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
    L.wrap(ReaderThumbnail, "onShowBookMap", function(orig, self, overview_mode)
        if overview_mode then return orig(self, overview_mode) end
        UIManager:show(LeafMap:new{ ui = self.ui, _first = true })
        return true
    end, "ReaderThumbnail:onShowBookMap")

    ---------------------------------------------------------------- Leaf page browser
    --[[ the prototype's overlay "pagebrowser" (.rd-pb): a full page
           status strip · ← Pages 1–6 of 354 ······ [2|3|4] ⋮   (⋮: KOReader's own page browser,
                                                                 with its menu, rows, ribbon...)
           a grid of page thumbnails (KOReader's thumbnail cache), page number under each, the
           chapter label under a chapter's first page, the current page framed in accent
           chapter strip (one segment per chapter, as wide as its pages; the ones on screen in accent)
           Page 4 · Chapter I ······ ‹ ›
       A tap on a thumbnail goes there (location stack kept); swipes / chevrons turn the grid. ]]
    local ImageWidget = require("ui/widget/imagewidget")

    local function chapter_label(title, i)
        local bs = require("leaf/booksheet")
        local head = bs.split_title and bs.split_title(title) or nil
        return head, head and head:match("%s(%S+)$") or ""
    end

    -- a thumbnail slot: --page fill, the tile centred, a --border-strong ring (accent --bw-xl when current)
    local Thumb = InputContainer:extend{ width = 0, height = 0 }
    function Thumb:init()
        self.dimen = geom(self.width, self.height)
        self.ges_events = { TapThumb = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    function Thumb:setTile(tile)
        if self.image then self.image:free() end
        self.image = ImageWidget:new{ image = tile.bb, image_disposable = false, original_in_nightmode = false }
        local sz = self.image:getSize()
        -- the slot takes the tile's shape (pages are not all the screen's shape)
        self.tw, self.th = math.min(sz.w, self.width), math.min(sz.h, self.height)
    end
    function Thumb:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local w, h = self.tw or self.width, self.th or self.height
        local ox = x + math.floor((self.width - w) / 2)
        local r = T.px("r-cover")
        bb:paintRoundedRect(ox, y, w, h, T.color("page"), r)
        if self.image then self.image:paintTo(bb, ox, y) end
        if self.here then
            local b = T.px("bw-xl")
            bb:paintBorder(ox - b, y - b, w + 2 * b, h + 2 * b, b, T.color("accent"), r + b)
        else
            bb:paintBorder(ox, y, w, h, T.px("hairline"), T.color("border-strong"), r)
        end
        if self.bm then -- .rd-thumb .pv .bm: a ribbon at 10% from the right edge
            local rw, rh = sc(9), sc(15)
            local rx = ox + w - math.floor(w * 0.1) - rw
            local cut = math.floor(rh * 0.72)
            for yy = 0, rh - 1 do
                if yy < cut then bb:paintRect(rx, y + yy, rw, 1, T.color("page-ink"))
                else
                    local gap = math.floor((yy - cut + 1) / (rh - cut) * rw / 2 + 0.5)
                    local side = math.floor(rw / 2) - math.floor(gap / 2)
                    if side > 0 then
                        bb:paintRect(rx, y + yy, side, 1, T.color("page-ink"))
                        bb:paintRect(rx + rw - side, y + yy, side, 1, T.color("page-ink"))
                    end
                end
            end
        end
    end
    function Thumb:onTapThumb()
        if self.callback then self.callback() end
        return true
    end
    function Thumb:free()
        if self.image then self.image:free() self.image = nil end
    end

    -- the chapter strip: proportional segments, the ones overlapping the grid in accent
    local Strip = InputContainer:extend{ width = 0, height = 0 }
    function Strip:init()
        self.dimen = geom(self.width, self.height)
        self.ges_events = { TapStrip = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
        local gap = T.px("sp-half")
        local total = self.total
        local avail = self.width - gap * (#self.chapters - 1)
        local x = 0
        self.segs = {}
        for i, c in ipairs(self.chapters) do
            local w = math.max(1, math.floor(avail * (c.to - c.from + 1) / total + 0.5))
            if i == #self.chapters then w = math.max(1, self.width - x) end
            table.insert(self.segs, { x = x, w = w, c = c, on = self.first <= c.to and self.last >= c.from })
            x = x + w + gap
        end
    end
    function Strip:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local face_on, face = L.face("ui-semibold", "fs-2xs"), L.face("ui", "fs-2xs")
        for _i, s in ipairs(self.segs) do
            bb:paintRoundedRect(x + s.x, y, s.w, self.height, T.color(s.on and "accent" or "surface-2"), T.px("r-thumb"))
            local tw = TextWidget:new{ text = s.c.num or "", face = s.on and face_on or face,
                fgcolor = T.color(s.on and "accent-ink" or "text-3"), max_width = s.w - 2 }
            local sz = tw:getSize()
            if sz.w <= s.w - 2 then
                tw:paintTo(bb, x + s.x + math.floor((s.w - sz.w) / 2), y + math.floor((self.height - sz.h) / 2))
            end
            tw:free()
        end
    end
    function Strip:onTapStrip(arg, ges)
        local px = ges.pos.x - self.dimen.x
        for _i, s in ipairs(self.segs) do
            if px >= s.x and px < s.x + s.w + T.px("sp-half") then
                if self.on_chapter then self.on_chapter(s.c) end
                break
            end
        end
        return true
    end

    local LeafPages = InputContainer:extend{ ui = nil }
    M.LeafPages = LeafPages

    function LeafPages:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = geom(W, H)
        self.covers_fullscreen = true
        self.ges_events = { Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        local doc = self.ui.document
        self.total = doc:getPageCount() or 1
        self.cur = (self.ui.view and self.ui.view.state and self.ui.view.state.page) or doc:getCurrentPage() or 1
        self.cols = self.ui.doc_settings:readSetting("page_browser_nb_cols") or G_reader_settings:readSetting("page_browser_nb_cols") or 3
        self.chapters = LeafMap.chapters({ ui = self.ui }, self.total)
        for i, c in ipairs(self.chapters) do c.label, c.num = chapter_label(c.title, i) end
        self.batch = 0
        self:build(true)
    end

    function LeafPages:chapterOf(p)
        for _i, c in ipairs(self.chapters) do
            if p >= c.from and p <= c.to then return c end
        end
    end

    function LeafPages:build(first)
        local ui = self.ui
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pad = T.px("sp-5")
        local landscape = W > H
        if self.cols > (landscape and 5 or 4) or self.cols < 2 then self.cols = math.max(2, math.min(landscape and 5 or 4, self.cols)) end
        local cols = self.cols
        -- header: ← Pages  1–6 of N ······ [2|3|4] ⋮
        local head_h = T.px("h-header")
        local seg_items = {}
        for n = 2, landscape and 5 or 4 do table.insert(seg_items, { label = tostring(n), key = n }) end
        local seg = require("leaf/widgets/seg"):new{ width = sc(52) * #seg_items, items = seg_items, selected = cols,
            on_select = function(n)
                self.cols = n
                ui.doc_settings:saveSetting("page_browser_nb_cols", n)
                self.start = nil
                self:rebuild()
            end }
        local right = HorizontalGroup:new{ align = "center", seg,
            Kit.icon_button("leaf.more.v", function()
                -- KOReader's own page browser: its menu (rows, columns, page numbers, ribbon, TOC levels...)
                UIManager:close(self)
                self._orig_show(ui.thumbnail)
            end, self),
            HorizontalSpan:new{ width = T.px("sp-2") } }

        -- grid geometry
        local col_gap, row_gap = T.px("sp-3h"), T.px("sp-4")
        local tw = math.floor((W - 2 * pad - (cols - 1) * col_gap) / cols)
        local pw, ph = W, H
        if not ui.rolling then
            pcall(function()
                local d = ui.document:getNativePageDimensions(self.cur)
                if d and d.w > 0 then pw, ph = d.w, d.h end
            end)
        end
        local th = math.floor(tw * ph / pw)
        local cap_h = TextWidget:new{ text = "1", face = L.face("ui", "fs-sm") }:getSize().h
            + TextWidget:new{ text = "C", face = L.face("ui", "fs-2xs") }:getSize().h
        local strip_h = sc(24) + 2 * T.px("sp-3")
        local pager_h = T.px("h-header")
        local fixed_h = T.px("h-status") + head_h + T.px("sp-2") + strip_h + pager_h + T.px("hairline")
        local cell_h = th + T.px("sp-1h") + cap_h
        local rows = math.max(1, math.floor((H - fixed_h - T.px("sp-5") + row_gap) / (cell_h + row_gap)))
        local per = rows * cols
        self.per = per
        if not self.start then self.start = math.floor((self.cur - 1) / per) * per + 1 end
        self.start = math.max(1, math.min(self.start, self.total))
        local last = math.min(self.total, self.start + per - 1)

        local header = OverlapGroup:new{ dimen = geom(W, head_h),
            LeftContainer:new{ dimen = geom(W, head_h), HorizontalGroup:new{ align = "center",
                HorizontalSpan:new{ width = T.px("sp-2") }, Kit.icon_button("leaf.kb.left", function() self:onClose() end, self),
                HorizontalSpan:new{ width = T.px("sp-2") },
                TextWidget:new{ text = _("Pages"), face = L.face("ui-semibold", "fs-lg") },
                HorizontalSpan:new{ width = T.px("sp-3") },
                TextWidget:new{ text = T_(_("%1–%2 of %3"), self.start, last, self.total), face = L.face("ui", "fs-md"), fgcolor = T.color("text-3") } } },
            RightContainer:new{ dimen = geom(W, head_h), right } }

        -- thumbnails
        local bm = LeafMap.marks({ ui = ui })
        if self.thumbs then for _i, t in ipairs(self.thumbs) do t:free() end end
        self.thumbs = {}
        if self.batch_id then ui.thumbnail:cancelPageThumbnailRequests(self.batch_id) end
        self.batch = self.batch + 1
        self.batch_id = "LeafPages" .. tostring(os.time()) .. "_" .. self.batch
        local batch_id = self.batch_id
        local grid = VerticalGroup:new{ align = "left" }
        local p = self.start
        for r = 1, rows do
            if p > self.total then break end
            if r > 1 then table.insert(grid, VerticalSpan:new{ width = row_gap }) end
            local line = HorizontalGroup:new{ align = "top" }
            for c = 1, cols do
                if c > 1 then table.insert(line, HorizontalSpan:new{ width = col_gap }) end
                if p <= self.total then
                    local page = p
                    local here = page == self.cur
                    local th_w = Thumb:new{ width = tw, height = th, here = here, bm = bm[page],
                        callback = function() self:goTo(page) end }
                    table.insert(self.thumbs, th_w)
                    local cap = VerticalGroup:new{ align = "center",
                        TextWidget:new{ text = tostring(page), face = L.face(here and "ui-semibold" or "ui", "fs-sm"),
                            fgcolor = T.color(here and "text" or "text-2") } }
                    local ch = self:chapterOf(page)
                    if ch and ch.from == page and ch.label then
                        table.insert(cap, TextWidget:new{ text = ch.label, face = L.face("ui", "fs-2xs"), fgcolor = T.color("text-3"), max_width = tw })
                    end
                    table.insert(line, VerticalGroup:new{ align = "center", th_w, VerticalSpan:new{ width = T.px("sp-1h") },
                        CenterContainer:new{ dimen = geom(tw, cap_h), cap } })
                    ui.thumbnail:getPageThumbnail(page, tw, th, batch_id, function(tile, bid, async)
                        if bid ~= self.batch_id or not tile then return end
                        th_w:setTile(tile)
                        if async then UIManager:setDirty(self, function() return "ui", th_w.dimen end) end
                    end)
                    p = p + 1
                end
            end
            table.insert(grid, line)
        end

        -- chapter strip + pager
        local strip = Strip:new{ width = W - 2 * pad, height = sc(24), chapters = self.chapters, total = self.total,
            first = self.start, last = last,
            on_chapter = function(c) self.start = c.from; self:rebuild() end }
        local cur_ch = self:chapterOf(self.cur)
        local where = T_(_("Page %1"), self.cur) .. ((cur_ch and cur_ch.label) and (" · " .. cur_ch.label) or "")
        local function chev(icon, enabled, d)
            local hit = T.px("hit")
            return Kit.Tap:new{ width = hit, height = hit, enabled = enabled,
                content = CenterContainer:new{ dimen = geom(hit, hit),
                    Kit.TintIcon:new{ icon = icon, size_token = "icon-md", color = T.color(enabled and "text" or "disabled") } },
                callback = function() self:flip(d) end }
        end
        local pager = OverlapGroup:new{ dimen = geom(W, pager_h),
            LeftContainer:new{ dimen = geom(W, pager_h), HorizontalGroup:new{ HorizontalSpan:new{ width = pad },
                TextWidget:new{ text = where, face = L.face("ui", "fs-md"), fgcolor = T.color("text-2") } } },
            RightContainer:new{ dimen = geom(W, pager_h), HorizontalGroup:new{ align = "center",
                chev("chevron.left", self.start > 1, -1), chev("chevron.right", last < self.total, 1),
                HorizontalSpan:new{ width = T.px("sp-3") } } } }
        local bottom = VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, CenterContainer:new{ dimen = geom(W - 2 * pad, strip_h), strip } },
            LineWidget:new{ dimen = geom(W, T.px("hairline")), background = T.color("border") },
            pager }
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), width = W, height = H,
            OverlapGroup:new{ dimen = geom(W, H),
                VerticalGroup:new{ align = "left", Kit.status_strip(W), header, VerticalSpan:new{ width = T.px("sp-2") },
                    HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, grid } },
                require("ui/widget/container/bottomcontainer"):new{ dimen = geom(W, H), bottom } } }
    end

    function LeafPages:rebuild()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function LeafPages:flip(d)
        local s = self.start + d * self.per
        if s < 1 or s > self.total then return end
        self.start = s
        self:rebuild()
    end
    function LeafPages:goTo(p)
        local ui = self.ui
        self:onClose()
        if ui.link then ui.link:addCurrentLocationToStack() end
        ui:handleEvent(Event:new("GotoPage", p))
    end
    function LeafPages:onSwipe(arg, ges)
        local dir = ges.direction
        if dir == "west" or dir == "north" then self:flip(1)
        elseif dir == "east" or dir == "south" then self:flip(-1) end
        return true
    end
    function LeafPages:onClose()
        if self.batch_id then self.ui.thumbnail:cancelPageThumbnailRequests(self.batch_id) end
        UIManager:close(self)
        return true
    end
    function LeafPages:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function LeafPages:onCloseWidget()
        if self.thumbs then for _i, t in ipairs(self.thumbs) do t:free() end end
        self.ui.thumbnail:tidyCache()
        UIManager:setDirty(self.ui.dialog, "full")
    end

    L.wrap(ReaderThumbnail, "onShowPageBrowser", function(orig, self)
        UIManager:show(LeafPages:new{ ui = self.ui, _orig_show = orig })
        return true
    end, "ReaderThumbnail:onShowPageBrowser")
end

return M
