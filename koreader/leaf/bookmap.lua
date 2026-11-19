--[[
    Leaf book map and page browser (prototype overlays "bookmap" / "pagebrowser"): KOReader's own
    widgets (BookMapWidget, PageBrowserWidget, the BookMapRow ribbon they share) keep their
    structure, gestures, menus and settings; Leaf restyles what they paint:

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
end

return M
