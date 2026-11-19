--[[
    Leaf page header (prototype .rd-head: "ANIMAL FARM" in small tracked capitals on the left, the
    chapter in Literata italic on the right, --page-2, on the text's side margins, in a 34px band
    above the text) and the reading page's metrics.

    Leaf draws the header itself (a ReaderView module, painted over the page like the footer and
    the dogear, refreshed with every page): crengine's own top bar is turned off and the page's top
    margin grows by the band's height. "Alt status bar" (Typeset › Style, or Settings › Status bar)
    still shows / hides it. Fallback: Alt status bar › "Leaf page header" off brings crengine's
    header back, steered as far as crengine allows:

      * items (once, for items still at KOReader's stock default): book title on, author / clock /
        battery / page number / page count / chapter marks off (page x / y is in Leaf's footer)
      * the chapter on the right through ReaderCoptListener's additional header content
      * the title in tracked capitals (crengine's alternative title property, runtime only)
      * Inter at --fs-folio unless the user set a size
      (crengine: one font, size and colour for the whole header, fixed layout)

    Both headers share the switches "Title in capitals (Leaf)" and "Chapter title (Leaf)".

    Reading page metrics, as the prototype's RD.style: the default font is Literata, the default side
    margins 20, and the side margins get the prototype's 10px base (mx = 10 + setting); the setting
    leaf_page_margins = false turns that base off.
--]]
local Device = require("device")
local _ = require("gettext")
local util = require("util")
local UIManager = require("ui/uimanager")
local Screen = Device.screen

local M = {}

local DEFAULTS = {
    cre_header_title = 1,
    cre_header_author = 0,
    cre_header_clock = 0,
    cre_header_battery = 0,
    cre_header_battery_percent = 0,
    cre_header_page_number = 0,
    cre_header_page_count = 0,
    cre_header_reading_percent = 0,
    cre_header_chapter_marks = 0,
}

-- KOReader's own defaults (ReaderCoptListener:onReadSettings)
local STOCK = {
    cre_header_title = 1, cre_header_author = 1, cre_header_clock = 1, cre_header_battery = 1,
    cre_header_battery_percent = 0, cre_header_page_number = 1, cre_header_page_count = 1,
    cre_header_reading_percent = 0, cre_header_chapter_marks = 1,
}

local HAIR = "\u{200A}"
local CHAPTER_MAX = 48 -- characters

function M.apply(L)
    local T = L.T
    local CreDocument = require("document/credocument")
    local ReaderCoptListener = require("apps/reader/modules/readercoptlistener")

    CreDocument.header_font = "Inter"
    -- the prototype's reading font (Typeset › Font: "Literata · Default"), for books and users with no font of their own
    CreDocument.default_font = "Literata"

    -- the alt status bar on by default
    local ok_opts, creoptions = pcall(require, "ui/data/creoptions")
    if ok_opts and type(creoptions) == "table" then
        for _i, tab in ipairs(creoptions) do
            for _j, o in ipairs(tab.options or {}) do
                if o.name == "status_line" then o.default_value = 0 end
                -- the prototype's default side margins (Typeset › Margins: 20px)
                if o.name == "h_page_margins" then
                    o.default_value = { 20, 20 }
                    for k, v in ipairs(o.values or {}) do
                        if type(v) == "table" and v[1] == 20 then o.default_pos = k end
                    end
                end
            end
        end
    end

    local Header = {} -- Leaf's own page header (view module), defined below
    Header.__index = Header
    -- the prototype's page margins: side = 10px + the setting (reader.js RD.style: mx = 10 + h * 1.2)
    local function side_offset() return Screen:scaleBySize(10 * T.scale) end

    local function caps(text)
        if not text or text == "" then return text end
        local up = util.splitToChars(text:upper())
        return table.concat(up, HAIR)
    end

    local function apply_title(self)
        local doc = self.document
        if not (doc and doc.setAltDocumentProp and self.ui.doc_props) then return end
        local title = self.ui.doc_props.display_title or ""
        if G_reader_settings:nilOrTrue("leaf_header_caps") then
            doc:setAltDocumentProp("title", caps(title))
        else
            doc:setAltDocumentProp("title", title)
        end
    end

    -- KOReader writes every item with its stock default the first time it reads it, so "never
    -- changed" can't be told from "chose the stock value": once, Leaf moves the items still at their
    -- stock default to Leaf's (anything the user changed stays)
    if not G_reader_settings:has("leaf_header_defaults") then
        for key, leaf_value in pairs(DEFAULTS) do
            local v = G_reader_settings:readSetting(key)
            if v == nil or v == STOCK[key] then G_reader_settings:saveSetting(key, leaf_value) end
        end
        G_reader_settings:saveSetting("leaf_header_defaults", 1)
    end

    L.wrap(ReaderCoptListener, "onReadSettings", function(orig, self, ...)
        orig(self, ...)
        if not G_reader_settings:has("cre_header_status_font_size") then
            local size = math.floor(Screen:scaleBySize(T.size["fs-folio"] * T.scale) + 0.5)
            self.document._document:setIntProperty("crengine.page.header.font.size", size)
        end
        -- the chapter on the right
        self.leaf_chapter = function()
            if not G_reader_settings:nilOrTrue("leaf_header_chapter") then return end
            local ui = self.ui
            local page = self.leaf_pageno or (ui.document and ui.document:getCurrentPage())
            local t = page and ui.toc and ui.toc:getTocTitleByPage(page) or ""
            if t == "" then return end
            t = t:gsub("%s+", " ")
            local chars = util.splitToChars(t)
            if #chars > CHAPTER_MAX then t = table.concat(chars, "", 1, CHAPTER_MAX - 1) .. "…" end
            return t
        end
        self:addAdditionalHeaderContent(self.leaf_chapter)
        if self.view and self.view.registerViewModule and not self.view.view_modules.leaf_header then
            self.view:registerViewModule("leaf_header", setmetatable({ ui = self.ui, cache = {} }, Header))
        end
    end, "ReaderCoptListener:onReadSettings")

    L.wrap(ReaderCoptListener, "updatePageInfoOverride", function(orig, self, pageno)
        self.leaf_pageno = pageno
        return orig(self, pageno)
    end, "ReaderCoptListener:updatePageInfoOverride")

    L.wrap(ReaderCoptListener, "onReaderReady", function(orig, self, ...)
        local r = orig(self, ...)
        apply_title(self)
        return r
    end, "ReaderCoptListener:onReaderReady")

    L.wrap(ReaderCoptListener, "onBookMetadataChanged", function(orig, self, prop_updated, ...)
        local r = orig(self, prop_updated, ...)
        local key = prop_updated and prop_updated.metadata_key_updated
        if key == "title" then
            apply_title(self)
            self:updateHeader()
        end
        return r
    end, "ReaderCoptListener:onBookMetadataChanged")

    ---------------------------------------------------------------- Leaf's own page header
    -- crengine's header has one font / size / colour, so by default Leaf draws .rd-head itself, as
    -- a view module painted over the page (like ReaderFooter / ReaderDogear): crengine's top bar is
    -- turned off and the page's top margin grows by the header height. "Alt status bar" (Typeset ›
    -- Style, or the status bar menu) still shows / hides it. Fallback: Settings › Status bar ›
    -- Alt status bar › "Leaf page header" off gives crengine's header back (styled as above).
    local Event = require("ui/event")
    local TextWidget = require("ui/widget/textwidget")
    local ReaderRolling = require("apps/reader/modules/readerrolling")
    local function leaf_mode() return G_reader_settings:nilOrTrue("leaf_page_header") end
    local function header_h() return Screen:scaleBySize(34 * T.scale) end

    L.wrap(CreDocument, "setPageMargins", function(orig, self, left, top, right, bottom)
        if self._leaf_header_h then top = top + self._leaf_header_h end
        if G_reader_settings:nilOrTrue("leaf_page_margins") then
            left, right = left + side_offset(), right + side_offset()
        end
        return orig(self, left, top, right, bottom)
    end, "CreDocument:setPageMargins")

    local function apply_margins(ui)
        local doc = ui.document
        local want = ui._leaf_header_on and ui.view and ui.view.view_mode == "page" and header_h() or nil
        if doc._leaf_header_h == want then return end
        doc._leaf_header_h = want
        if ui.typeset and ui.typeset.unscaled_margins then
            ui:handleEvent(Event:new("SetPageMargins", ui.typeset.unscaled_margins))
        end
    end
    M.apply_margins = apply_margins

    L.wrap(ReaderRolling, "onSetStatusLine", function(orig, self, status_line)
        local ui = self.ui
        if leaf_mode() then
            ui._leaf_header_on = status_line == 0
            orig(self, 1) -- crengine's own header off: Leaf draws the header
        else
            ui._leaf_header_on = false
            orig(self, status_line)
        end
        apply_margins(ui)
    end, "ReaderRolling:onSetStatusLine")

    -- page / scroll mode: the header band only exists in page mode
    L.wrap(require("apps/reader/modules/readerview"), "onSetViewMode", function(orig, self, ...)
        local r = orig(self, ...)
        if self.ui and self.ui.rolling then apply_margins(self.ui) end
        return r
    end, "ReaderView:onSetViewMode")

    -- the header itself (.rd-head): title in small tracked capitals (Inter --fs-2xs medium) on the
    -- left, the chapter in Literata italic --fs-folio on the right (max 55%), --page-2, on the
    -- text's side margins, sitting on the bottom of a 34px band
    function Header:text(key, text, face, maxw)
        local c = self.cache[key]
        if c and c.text == text and c.maxw == maxw then return c.w end
        if c then c.w:free() end
        local w = TextWidget:new{ text = text, face = face, fgcolor = T.color("page-2"), max_width = maxw, padding = 0 }
        self.cache[key] = { text = text, maxw = maxw, w = w }
        return w
    end
    function Header:paintTo(bb, x, y)
        local ui = self.ui
        if not (ui._leaf_header_on and ui.rolling and ui.view and ui.view.view_mode == "page") then return end
        local W = Screen:getWidth()
        local m = ui.typeset and ui.typeset.unscaled_margins or { 15, 15, 15, 15 }
        local off = G_reader_settings:nilOrTrue("leaf_page_margins") and side_offset() or 0
        local left, right = Screen:scaleBySize(m[1]) + off, Screen:scaleBySize(m[3]) + off
        local inner = W - left - right
        local base = y + header_h() -- the band's bottom edge (the user's top margin follows it)
        local page = ui.document:getCurrentPage()
        local chapter = ""
        if G_reader_settings:nilOrTrue("leaf_header_chapter") then
            chapter = (ui.toc and ui.toc:getTocTitleByPage(page) or ""):gsub("%s+", " ")
        end
        local title = ui.doc_props and (ui.doc_props.display_title or ui.doc_props.title) or ""
        if G_reader_settings:nilOrTrue("leaf_header_caps") then title = caps(title) end
        local gap = T.px("sp-3")
        local cw = chapter ~= "" and self:text("c", chapter, L.face("book-italic", "fs-folio"), math.floor(inner * 0.55)) or nil
        local cwid = cw and cw:getSize().w or 0
        local tw = self:text("t", title, L.face("ui-medium", "fs-2xs"), math.max(1, inner - cwid - gap))
        -- align the two texts on a common baseline at the band's bottom
        local tb = tw:getBaseline()
        local cb = cw and cw:getBaseline() or tb
        local line = base - T.px("sp-1")
        tw:paintTo(bb, x + left, line - tb)
        if cw then cw:paintTo(bb, x + W - right - cwid, line - cb) end
    end
    function Header:free()
        for _k, c in pairs(self.cache) do c.w:free() end
        self.cache = {}
    end

    L.wrap(ReaderCoptListener, "getAltStatusBarMenu", function(orig, self)
        local menu = orig(self)
        local items = menu and menu.sub_item_table
        if type(items) == "table" then
            -- after "Book title" / "Book author"
            local at = #items + 1
            for i, it in ipairs(items) do
                if it.text == _("Book author") then at = i + 1 end
            end
            table.insert(items, at, {
                text = _("Leaf page header"),
                help_text = _("Draw the header with Leaf's typography (title in small capitals, chapter in italics). Off: the rendering engine's own header."),
                checked_func = function() return G_reader_settings:nilOrTrue("leaf_page_header") end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("leaf_page_header")
                    local ui = self.ui
                    ui:handleEvent(Event:new("SetStatusLine", ui.document.configurable.status_line))
                    UIManager:setDirty(ui.dialog, "ui")
                end,
            })
            at = at + 1
            table.insert(items, at, {
                text = _("Title in capitals (Leaf)"),
                checked_func = function() return G_reader_settings:nilOrTrue("leaf_header_caps") end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("leaf_header_caps")
                    apply_title(self)
                    self:updateHeader()
                end,
            })
            table.insert(items, at + 1, {
                text = _("Chapter title (Leaf)"),
                checked_func = function() return G_reader_settings:nilOrTrue("leaf_header_chapter") end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("leaf_header_chapter")
                    self:updatePageInfoOverride()
                    self:updateHeader()
                end,
            })
        end
        return menu
    end, "ReaderCoptListener:getAltStatusBarMenu")
end

return M
