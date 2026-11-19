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
    d.items_separator = "dot"
    d.text_font_size = 11      -- --fs-xs (KOReader sizes share the 600px base)
    d.progress_margin = true   -- line and text aligned with the book's margins
    -- Inter: the footer takes a registered font file path, so look up where Leaf's Inter is
    for _, path in ipairs(require("fontlist"):getFontList()) do
        if path:match("leaf/Inter%-Regular%.ttf$") then d.text_font_face = path break end
    end

    local function leaf_text(self)
        local doc = self.ui.document
        local page = self.pageno or (self.ui.view and self.ui.view.state and self.ui.view.state.page) or 1
        local total = doc and doc:getPageCount() or 0
        local pct = math.floor((self:getBookProgress() or 0) * 100 + 0.5)
        local left_pages = self.ui.toc and self.ui.toc:getChapterPagesLeft(page, true)
            or (doc and doc:getTotalPagesLeft(page)) or 0
        local when
        if self.ui.statistics and self.ui.statistics.getTimeForPages then
            local t = self.ui.statistics:getTimeForPages(left_pages)
            -- no reading data yet gives "00:00": say pages instead
            local empty = not t or t == "" or t == _("N/A") or not t:find("[1-9]")
            if not empty then when = T_(_("%1 left in chapter"), t) end
        end
        when = when or T_(_("%1 pages left in chapter"), left_pages)
        return string.format("%d%% · %s", pct, when), string.format("%d / %d", page, total)
    end

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

    L.wrap(ReaderFooter, "_updateFooterText", function(orig, self, force_repaint, full_repaint)
        if self.settings.leaf_text == false or self.has_no_mode or not self.footer_text then
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
