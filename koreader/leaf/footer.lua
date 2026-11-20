--[[
    Leaf reading footer (prototype .rd-foot): a thin progress line with chapter ticks above
    "6% · 12 min left in chapter ………… 4 / 67", in Inter on the page's --page-2 grey.

    * Text: KOReader's footer text line is replaced by the Leaf line (left: book percentage and
      time left in the chapter from the statistics plugin, or pages left without it; right:
      page / pages), padded so the page count sits on the right edge. Turn it off with the
      KOReader setting footer.leaf_text = false to get KOReader's configurable items back.
    * Defaults (only for footers the user never configured): bar above the text, thin, chapter
      ticks, left-aligned, "·" separator.
    * Colours: text --page-2, track --page-line, fill --page-line-fill, ticks --page-tick.
    * Painting: Leaf paints .rd-foot itself (text on the book's side margins, the current page in
      --page-ink medium, a 2px line with 6px chapter ticks); KOReader keeps the footer's height,
      visibility, taps and menu. footer.leaf_text = false restores KOReader's painting.
--]]
local _ = require("gettext")
local T_ = require("ffi/util").template

local M = {}

function M.apply(L)
    local T = L.T
    local ReaderFooter = require("apps/reader/modules/readerfooter")

    -- defaults for a footer the user never configured (their saved settings win)
    local d = ReaderFooter.default_settings
    d.progress_bar_position = "above"
    d.progress_style_thin = true
    d.progress_style_thin_height = 2
    d.toc_markers = true
    d.toc_markers_width = 1
    d.align = "left"
    d.all_at_once = true       -- the full .rd-foot line; with it off a tap cycles single items (Gaps › footer-mode)
    d.items_separator = "dot"
    d.text_font_size = 11      -- --fs-xs (KOReader sizes share the 600px base)
    d.progress_margin = true   -- line and text aligned with the book's margins
    -- Inter: the footer takes a registered font file path, so look up where Leaf's Inter is
    for _, path in ipairs(require("fontlist"):getFontList()) do
        if path:match("leaf/Inter%-Regular%.ttf$") then d.text_font_face = path break end
    end

    -- "1 min", "12 min", "1 h 05 min" (the prototype's "… left in chapter")
    local function human_duration(secs)
        local m = math.max(1, math.floor(secs / 60 + 0.5))
        if m < 60 then return T_(_("%1 min"), m) end
        return T_(_("%1 h %2 min"), math.floor(m / 60), string.format("%02d", m % 60))
    end

    local function leaf_text(self)
        local doc = self.ui.document
        local page = self.pageno or (self.ui.view and self.ui.view.state and self.ui.view.state.page) or 1
        local total = doc and doc:getPageCount() or 0
        local pct = math.floor((self:getBookProgress() or 0) * 100 + 0.5)
        local left_pages = self.ui.toc and self.ui.toc:getChapterPagesLeft(page, true)
            or (doc and doc:getTotalPagesLeft(page)) or 0
        local when
        local st = self.ui.statistics
        if st and st.settings and st.settings.is_enabled and st.avg_time and st.avg_time == st.avg_time and st.avg_time > 0 then
            when = T_(_("%1 left in chapter"), human_duration(left_pages * st.avg_time))
        end
        when = when or T_(_("%1 pages left in chapter"), left_pages)
        return string.format("%d%% · %s", pct, when), string.format("%d / %d", page, total), page, total
    end

    -- "all at once" off: one item per tap (prototype Gaps › footer-mode): left text, right text, or nil (bar only)
    local GEN = ReaderFooter.textGeneratorMap or {}
    local function single_text(self)
        if self.settings.all_at_once then return end
        local name = self.mode_index and self.mode_index[self.mode]
        if self.genFooterText == GEN.empty or not name or not self.settings[name] then return "", "" end
        local doc = self.ui.document
        local page = self.pageno or (self.ui.view and self.ui.view.state and self.ui.view.state.page) or 1
        local total = doc and doc:getPageCount() or 0
        local st = self.ui.statistics
        local avg = st and st.settings and st.settings.is_enabled and st.avg_time and st.avg_time == st.avg_time and st.avg_time > 0 and st.avg_time
        local ch_left = self.ui.toc and self.ui.toc:getChapterPagesLeft(page, true) or (doc and doc:getTotalPagesLeft(page)) or 0
        local book_left = doc and doc:getTotalPagesLeft(page) or 0
        if name == "page_progress" then return "", string.format("%d / %d", page, total), page, total
        elseif name == "pages_left_book" then return T_(_("%1 pages left in book"), book_left)
        elseif name == "pages_left" then return T_(_("%1 pages left in chapter"), ch_left)
        elseif name == "time" then
            local now = os.time()
            local secs = tonumber(os.date("%H", now)) * 3600 + tonumber(os.date("%M", now)) * 60
            return require("datetime").secondsToHour(secs, G_reader_settings:isTrue("twelve_hour_clock"))
        elseif name == "battery" then
            local cap
            pcall(function() cap = require("device"):getPowerDevice():getCapacity() end)
            return cap and T_(_("Battery %1%"), cap) or ""
        elseif name == "percentage" then return string.format("%d%%", math.floor((self:getBookProgress() or 0) * 100 + 0.5))
        elseif name == "book_time_to_read" then
            return avg and T_(_("%1 left in book"), human_duration(book_left * avg)) or T_(_("%1 pages left in book"), book_left)
        elseif name == "chapter_time_to_read" then
            return avg and T_(_("%1 left in chapter"), human_duration(ch_left * avg)) or T_(_("%1 pages left in chapter"), ch_left)
        elseif name == "chapter_progress" then
            local done = self.ui.toc and self.ui.toc:getChapterPagesDone(page)
            local count = self.ui.toc and self.ui.toc:getChapterPageCount(page)
            if done and count then return T_(_("Page %1 of %2 in chapter"), done + 1, count) end
        end
        local ok, t = pcall(self.genFooterText, self)
        return ok and t or ""
    end
    M.single_text = single_text

    local function paint_colours(self)
        if self.footer_text then self.footer_text.fgcolor = T.color("page-2") end
        local bar = self.progress_bar
        if bar then
            bar.bgcolor = T.color("page-line")
            bar.fillcolor = T.color("page-line-fill")
            bar.bordercolor = T.color("page-tick")
            bar.bordersize = 0
            bar.radius = 0
        end
    end

    L.wrap(ReaderFooter, "init", function(orig, self, ...)
        orig(self, ...)
        paint_colours(self)
    end, "ReaderFooter:init")
    L.wrap(ReaderFooter, "updateFooterFont", function(orig, self, ...)
        orig(self, ...)
        paint_colours(self)
    end, "ReaderFooter:updateFooterFont")

    -- Leaf paints the footer itself (.rd-foot): the text on the book's side margins, "4" in --page-ink
    -- medium and " / 67" in --page-2, and a 2px line with 6px chapter ticks above it. KOReader keeps
    -- the footer's height, visibility, taps and menu; footer.leaf_text = false gives its own painting.
    local TextWidget = require("ui/widget/textwidget")
    local Screen = require("device").screen
    local function leaf_paint_ok(self)
        local st = self.settings
        return st.leaf_text ~= false and not self.has_no_mode and not st.disable_progress_bar
            and st.progress_bar_position == "above" and self.footer_text
    end
    L.wrap(ReaderFooter, "paintTo", function(orig, self, bb, x, y)
        if not leaf_paint_ok(self) then return orig(self, bb, x, y) end
        local W, H = Screen:getWidth(), Screen:getHeight()
        local fh = self:getHeight()
        local left_m, right_m
        if self.ui.rolling then
            local m = self.ui.document:getPageMargins()
            left_m, right_m = m.left, m.right
        else
            left_m = Screen:scaleBySize(16 * T.scale)
            right_m = left_m
        end
        local inner = W - left_m - right_m
        local face = L.face("ui", "fs-xs")
        local left, right, page, total = single_text(self)
        if left == nil then
            left, right, page, total = leaf_text(self)
        end
        local bar_only = left == "" and (right == nil or right == "")
        local lw = TextWidget:new{ text = left, face = face, fgcolor = T.color("page-2"), max_width = math.floor(inner * 0.7) }
        local pw = TextWidget:new{ text = page and tostring(page) or "", face = L.face("ui-medium", "fs-xs"), fgcolor = T.color("page-ink") }
        local ow = TextWidget:new{ text = page and (" / " .. total) or "", face = face, fgcolor = T.color("page-2") }
        local probe = TextWidget:new{ text = "0", face = face }
        local th = probe:getSize().h
        probe:free()
        local text_y = y + H - T.px("sp-3") - th
        local line_y = text_y - T.px("sp-2") - 2
        local clear_y = line_y - 2 -- the whole .rd-foot band, whatever this mode shows
        if bar_only then line_y = y + H - T.px("sp-3") - 2 end
        -- clear the footer band (and the tick overhang above it) to the page colour
        local top = math.min(y + H - fh, clear_y)
        bb:paintRect(x, top, W, y + H - top, T.color("page"))
        -- .rd-line: track, fill, chapter ticks
        local lh = 2
        bb:paintRoundedRect(x + left_m, line_y, inner, lh, T.color("page-line"), T.px("r-tick"))
        local pct = self:getBookProgress() or 0
        local fill = math.floor(inner * math.max(0, math.min(1, pct)) + 0.5)
        if fill > 0 then bb:paintRoundedRect(x + left_m, line_y, fill, lh, T.color("page-line-fill"), T.px("r-tick")) end
        local ticks = self.progress_bar and self.progress_bar.ticks
        local last = self.progress_bar and self.progress_bar.last
        if not ticks and self.settings.toc_markers and self.ui.toc then
            last = self.ui.document:getPageCount()
            -- (KOReader skips chapter markers on its thin bar: Leaf keeps them, cached per layout)
            if not (self._leaf_ticks and self._leaf_ticks_n == last) then
                self._leaf_ticks, self._leaf_ticks_n = self.ui.toc:getTocTicksFlattened(), last
            end
            ticks = self._leaf_ticks
        end
        if ticks and last and last > 0 then
            for _i, t in ipairs(ticks) do
                local tx = x + left_m + math.floor(inner * t / last)
                bb:paintRect(tx, line_y - 2, 1, 6, T.color("page-tick"))
            end
        end
        local base = text_y + lw:getBaseline()
        if left ~= "" then lw:paintTo(bb, x + left_m, text_y) end
        if page then
            local rx = x + W - right_m - pw:getSize().w - ow:getSize().w
            pw:paintTo(bb, rx, base - pw:getBaseline())
            ow:paintTo(bb, rx + pw:getSize().w, base - ow:getBaseline())
        end
        lw:free() pw:free() ow:free()
    end, "ReaderFooter:paintTo")

    L.wrap(ReaderFooter, "_updateFooterText", function(orig, self, force_repaint, full_repaint)
        if not (self.ui and self.ui.document) then return end -- a refresh scheduled before the book closed
        if self.settings.leaf_text == false or self.has_no_mode or not self.footer_text or not self.settings.all_at_once then
            return orig(self, force_repaint, full_repaint)
        end
        local left, right = leaf_text(self)
        -- pad with spaces so "page / pages" sits on the right edge of the text area
        -- the same maximum text width KOReader will use (it depends on bar position / alignment)
        local st = self.settings
        if st.progress_bar_position == "alongside" and not st.disable_progress_bar then
            -- text shares the line with the bar: no padding, just both parts
            local text = left .. " · " .. right
            local gen = self.genFooterText
            self.genFooterText = function() return text end
            local ok, err = pcall(orig, self, force_repaint, full_repaint)
            self.genFooterText = gen
            if not ok then error(err, 0) end
            return
        end
        local avail
        if not st.disable_progress_bar and st.align == "center" then
            avail = math.floor(self._saved_screen_width - 2 * require("device").screen:scaleBySize(st.progress_margin_width))
        else
            avail = math.floor(self._saved_screen_width - 2 * self.horizontal_margin)
        end
        local TextWidget = require("ui/widget/textwidget")
        local face = self.footer_text.face
        local function w(s)
            local tw = TextWidget:new{ text = s, face = face }
            local width = tw:getSize().w
            tw:free()
            return width
        end
        local space = math.max(1, w("  ") - w(" "))
        local gap = avail - w(left) - w(right) - space
        local text = left .. string.rep(" ", math.max(1, math.floor(gap / space))) .. right
        local gen = self.genFooterText
        self.genFooterText = function() return text end
        local ok, err = pcall(orig, self, force_repaint, full_repaint)
        self.genFooterText = gen
        if not ok then error(err, 0) end
    end, "ReaderFooter:_updateFooterText")
end

return M
