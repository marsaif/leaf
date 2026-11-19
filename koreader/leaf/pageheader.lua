--[[
    Leaf page header (prototype .rd-head: "ANIMAL FARM" in small tracked capitals on the left,
    the chapter on the right, small, above the text).

    The header of a reflowable book is drawn by crengine itself (KOReader's "alt status bar",
    ReaderCoptListener), so Leaf can only steer what crengine offers:

      * shown by default: the creoptions default for "Alt status bar" becomes on (books with their
        own saved setting, and users who chose a default, keep theirs)
      * items (once, for items still at KOReader's stock default): book title on, author / clock /
        battery / page number / page count / chapter marks off (page x / y is in Leaf's footer);
        every item stays in KOReader's menu (Settings › Status bar › Alt status bar)
      * the chapter on the right: through ReaderCoptListener's additional header content (as the
        Read timer plugin does), truncated to keep the title readable
      * the title in tracked capitals: crengine's alternative title property (runtime only, the book's
        metadata is untouched); crengine has no letter-spacing, so hair spaces do the tracking
      * font: Inter (crengine's header font unless the user picked one) at --fs-folio (12px),
        unless the user set a size

    crengine limits (documented, not fixable from Lua): one font, one size and one colour for the
    whole header (no italic chapter next to a caps title, no --text-3 grey); its layout is fixed
    (title left, page info right) and it always rules a thin progress line under the header when
    chapter marks are on. Leaf adds two switches to KOReader's Alt status bar menu:
    "Chapter title (Leaf)" and "Title in capitals (Leaf)".
--]]
local Device = require("device")
local _ = require("gettext")
local util = require("util")
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

    -- the alt status bar on by default
    local ok_opts, creoptions = pcall(require, "ui/data/creoptions")
    if ok_opts and type(creoptions) == "table" then
        for _i, tab in ipairs(creoptions) do
            for _j, o in ipairs(tab.options or {}) do
                if o.name == "status_line" then o.default_value = 0 end
            end
        end
    end

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
