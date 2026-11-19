--[[
    Leaf search (prototype screen "search"): the file search (FileSearcher) and the full-text
    search in a book (ReaderSearch) open a full-screen search page instead of an input dialog.

      header:  ‹ · search field (.ko-input: --surface-2, --r-md, 44px, search icon, ⊗ clear)
               · keyboard toggle
      scopes:  chips (.ko-chip, accent when on). File search: Current folder | Home folder
               (where to look), then Match case, Subfolders, Titles & authors (KOReader's check
               boxes). In a book: Match case, Ignore accents, Regex (KOReader's search types,
               mutually exclusive as in KOReader; hold Regex for KOReader's help).
      in-book: a "SEARCHING IN" card (title, author, pages) and the actions ‹ Previous ·
               Next › · All results (primary), as KOReader's dialog buttons.
      body:    RECENT SEARCHES (chips with a history icon, "Clear"), and "Last results" rows that
               reopen KOReader's last result lists.
      keyboard: KOReader's on-screen keyboard (Leaf-styled), Enter = search (Next / Current folder,
               KOReader's enter defaults).
    The search itself, the result lists (BookList / Menu), the caches and every setting stay
    KOReader's; the recent searches are Leaf's own (settings leaf_search_history /
    leaf_fulltext_history).
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local OverlapGroup = require("ui/widget/overlapgroup")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

local MAX_HISTORY = 8

local function history(key)
    return G_reader_settings:readSetting(key) or {}
end
local function remember(key, text)
    if not text or text == "" then return end
    local list = history(key)
    for i = #list, 1, -1 do if list[i] == text then table.remove(list, i) end end
    table.insert(list, 1, text)
    while #list > MAX_HISTORY do table.remove(list) end
    G_reader_settings:saveSetting(key, list)
end

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local InputText = require("ui/widget/inputtext")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")

    ------------------------------------------------------------------ the page
    -- o: title (hint), text, history_key, chips_func(page) -> { {chip}, ... } rows,
    --    body_func(page, width) -> widgets, on_search(page, text)
    local SearchPage = K.Page:extend{}

    function SearchPage:init()
        local W = Screen:getWidth()
        local hit = T.px("hit")
        -- field width: screen - side pads - back - keyboard toggle - icon - clear
        local field_w = W - 2 * T.px("sp-2") - 2 * hit - 2 * T.px("sp-1")
        self.field_w = field_w
        local text_w = field_w - T.px("icon-md") - T.px("sp-3") - T.px("sp-2") - hit
        self.input = InputText:new{
            text = self.text or "", hint = self.hint, face = L.face("ui", "fs-md"),
            width = text_w, padding = T.px("sp-2"), margin = 0, bordersize = 0,
            scroll = false, focused = true, parent = self,
            enter_callback = function() self:submit() end,
            edit_callback = function()
                -- the clear button follows the text (the page re-lays out only when that changes)
                local has = self.input and self.input:getText() ~= ""
                if self._has_text ~= nil and has ~= self._has_text then
                    UIManager:nextTick(function() self:rebuild() end)
                end
                self._has_text = has
            end,
        }
        self._has_text = (self.text or "") ~= ""
        self.layout = { { self.input } }
        K.Page.init(self)
    end

    function SearchPage:getInputText() return self.input:getText() end

    function SearchPage:submit(...)
        local text = self.input:getText()
        if text == "" then return end
        if self.history_key then remember(self.history_key, text) end
        self.on_search(self, text, ...)
    end

    function SearchPage:setSearch(text)
        self.input:setText(text)
        self._has_text = text ~= ""
        self:rebuild()
    end

    function SearchPage:build()
        local W = Screen:getWidth()
        local hit = T.px("hit")
        -- field (.ko-input): icon, text, clear
        local fh = T.px("h-input")
        local field = FrameContainer:new{
            bordersize = 0, background = T.color("surface-2"), radius = T.px("r-md"), padding = 0,
            OverlapGroup:new{ dimen = K.geom(self.field_w, fh),
                LeftContainer:new{ dimen = K.geom(self.field_w, fh), HorizontalGroup:new{ align = "center",
                    K.hspan("sp-3"), K.icon("leaf.sys.search", "icon-md", true), K.hspan("sp-1"), self.input } },
                require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(self.field_w, fh),
                    self._has_text and K.icon_button("leaf.sys.clear", function() self:setSearch("") end, self, { size = "icon-sm" })
                        or K.hspan(0) },
            },
        }
        local head = HorizontalGroup:new{ align = "center",
            K.hspan("sp-2"),
            K.icon_button("chevron.left", function() self:onClose() end, self),
            K.hspan("sp-1"), field, K.hspan("sp-1"),
            K.icon_button("leaf.sys.keyboard", function()
                self.input:toggleKeyboard()
                UIManager:setDirty(nil, "ui")
            end, self),
        }
        local header = CenterContainer:new{ dimen = K.geom(W, T.px("h-header") + T.px("sp-2")), head }

        local body = VerticalGroup:new{ align = "left", header }
        -- chip rows
        local pad = T.px("sp-5")
        for _i, row in ipairs(self.chips_func and self.chips_func(self) or {}) do
            local chips = {}
            for _j, c in ipairs(row) do table.insert(chips, K.chip(c)) end
            table.insert(body, K.vspan("sp-1"))
            table.insert(body, HorizontalGroup:new{ K.hspan(pad), K.chip_row(chips, W - 2 * pad) })
        end
        table.insert(body, K.vspan("sp-3"))
        table.insert(body, K.line(W))
        for _i, w in ipairs(self.body_func and self.body_func(self, W) or {}) do
            table.insert(body, w)
        end

        -- recent searches
        local list = self.history_key and history(self.history_key) or {}
        if #list > 0 then
            table.insert(body, K.vspan("sp-2"))
            table.insert(body, K.section(_("Recent searches"), W, _("Clear"), function()
                G_reader_settings:delSetting(self.history_key)
                self:rebuild()
            end, self))
            local chips = {}
            for _i, q in ipairs(list) do
                table.insert(chips, K.chip{ label = q, icon = "leaf.sys.recent", dim = true,
                    callback = function() self:setSearch(q) end })
            end
            -- two lines of chips at most
            local w = W - 2 * pad
            local rows, cur, used = {}, {}, 0
            for _i, c in ipairs(chips) do
                local cw = c:getSize().w
                if used > 0 and used + cw > w then
                    table.insert(rows, cur) cur, used = {}, 0
                end
                table.insert(cur, c)
                used = used + cw + T.px("sp-2")
            end
            if #cur > 0 then table.insert(rows, cur) end
            for i = 1, math.min(2, #rows) do
                if i > 1 then table.insert(body, K.vspan("sp-2")) end
                table.insert(body, HorizontalGroup:new{ K.hspan(pad), K.chip_row(rows[i], w) })
            end
        end
        self:frame(body)
    end

    function SearchPage:onShow()
        UIManager:setDirty(self, "full")
        UIManager:nextTick(function() self.input:onShowKeyboard() end)
        return true
    end

    function SearchPage:onCloseWidget()
        self.input:onCloseKeyboard()
        self.input:onCloseWidget()
        UIManager:setDirty(nil, "full")
    end

    M.SearchPage = SearchPage

    ------------------------------------------------------------------ file search
    local FileSearcher = require("apps/filemanager/filemanagerfilesearcher")
    L.wrap(FileSearcher, "onShowFileSearch", function(orig, self, search_string)
        local fs = self
        local in_fm = self.ui.file_chooser ~= nil
        local scope = fs._leaf_scope or "current"
        local page
        page = SearchPage:new{
            hint = _("File names, titles, authors…"),
            text = search_string or FileSearcher.search_string,
            history_key = "leaf_search_history",
            chips_func = function()
                local home = G_reader_settings:has("home_dir")
                local row1 = {
                    { label = in_fm and _("Current folder") or _("Book folder"), icon = "leaf.sys.folder", on = scope == "current",
                      callback = function() scope = "current" fs._leaf_scope = scope page:rebuild() end },
                }
                if home then
                    table.insert(row1, { label = _("Home folder"), icon = "home", on = scope == "home",
                        callback = function() scope = "home" fs._leaf_scope = scope page:rebuild() end })
                end
                local row2 = {
                    { label = _("Match case"), icon = "leaf.sys.case", on = fs.case_sensitive,
                      callback = function() fs.case_sensitive = not fs.case_sensitive page:rebuild() end },
                    { label = _("Subfolders"), icon = "leaf.sys.layers", on = fs.include_subfolders,
                      callback = function() fs.include_subfolders = not fs.include_subfolders page:rebuild() end },
                }
                if fs.ui.coverbrowser then
                    table.insert(row2, { label = _("Titles & authors"), icon = "leaf.sys.book", on = fs.include_metadata,
                        callback = function() fs.include_metadata = not fs.include_metadata page:rebuild() end })
                end
                return { row1, row2 }
            end,
            body_func = function(p, W)
                local out = {}
                if FileSearcher.search_results and #FileSearcher.search_results > 0 then
                    table.insert(out, K.vspan("sp-2"))
                    table.insert(out, K.section(_("Last search"), W))
                    table.insert(out, K.row{ width = W, tile = "leaf.sys.files",
                        label = T_(_("Results for “%1”"), FileSearcher.search_string or ""),
                        sub = T_(_("%1 items"), #FileSearcher.search_results),
                        trailing = K.icon("chevron.right", "icon-md", true),
                        callback = function()
                            UIManager:close(p)
                            fs:onShowSearchResults()
                        end })
                end
                return out
            end,
            on_search = function(p, text)
                FileSearcher.search_string = text
                if scope == "home" and G_reader_settings:has("home_dir") then
                    FileSearcher.search_path = G_reader_settings:readSetting("home_dir")
                else
                    FileSearcher.search_path = fs.ui.file_chooser and fs.ui.file_chooser.path or fs.ui:getLastDirFile()
                end
                UIManager:close(p)
                require("ui/trapper"):wrap(function() fs:doSearch() end)
            end,
        }
        UIManager:show(page)
        return true
    end, "FileSearcher:onShowFileSearch")

    -- result list title: "Results for “x”" + count (KOReader: "Search results (n)" + "Query: x")
    L.wrap(FileSearcher, "updateItemTable", function(orig, self, item_table)
        orig(self, item_table)
        local menu = self.booklist_menu
        if menu and menu.title_bar and menu.title_bar.setTitle then
            local n = #(item_table or menu.item_table or {})
            menu.title_bar:setTitle(T_(_("Results for “%1”"), FileSearcher.search_string or ""))
            if menu.title_bar.setSubTitle then menu.title_bar:setSubTitle(T_(_("%1 items"), n)) end
        end
    end, "FileSearcher:updateItemTable")

    ------------------------------------------------------------------ full text search in a book
    local ReaderSearch = require("apps/reader/modules/readersearch")
    L.wrap(ReaderSearch, "onShowFulltextSearchInput", function(orig, self, search_string)
        local rs = self
        local case = { checked = not self.case_insensitive }
        rs.check_button_case = case
        local types = self.search_types or {}
        local function type_label(t)
            if t.regex then return _("Regex") end
            if t.flags == 0x01FF then return _("Ignore accents") end
            return t.text
        end
        local page
        page = SearchPage:new{
            hint = _("Search in this book"),
            text = search_string or self.last_search_text or self.ui.doc_settings:readSetting("fulltext_search_last_search_text"),
            history_key = "leaf_fulltext_history",
            chips_func = function()
                local row = {
                    { label = _("Match case"), icon = "leaf.sys.case", on = case.checked,
                      callback = function() case.checked = not case.checked page:rebuild() end },
                }
                if rs.ui.rolling then
                    for _i, t in ipairs(types) do
                        table.insert(row, { label = type_label(t), icon = t.regex and "leaf.sys.regex" or "leaf.sys.words",
                            on = rs.current_search_type == t,
                            callback = function()
                                rs.current_search_type = rs.current_search_type == t and rs.default_search_type or t
                                page:rebuild()
                            end,
                            hold = t.regex and function()
                                -- KOReader's regex help text is a local of readersearch.lua
                                local help
                                local up = 1
                                while true do
                                    local n, v = debug.getupvalue(orig, up)
                                    if not n then break end
                                    if n == "regex_help_text" then help = v break end
                                    up = up + 1
                                end
                                if help then
                                    UIManager:show(require("ui/widget/infomessage"):new{ text = help, width = Screen:getWidth() * 0.9 })
                                end
                            end or nil })
                    end
                end
                return { row }
            end,
            body_func = function(p, W)
                local out = {}
                local pad = T.px("sp-4")
                local cw = W - 2 * pad
                local iw = K.inner(cw)
                local props = rs.ui.doc_props or {}
                local title = props.display_title or props.title or ""
                local bits = {}
                if props.authors and props.authors ~= "" then table.insert(bits, (props.authors:gsub("\n", ", "))) end
                local pages = rs.ui.document and rs.ui.document:getPageCount()
                if pages then table.insert(bits, T_(_("%1 pages"), pages)) end
                local card = K.card(cw, VerticalGroup:new{ align = "left",
                    K.text(_("SEARCHING IN"), "ui-semibold", "fs-2xs", "text-3", iw),
                    K.vspan("sp-1"),
                    K.text(title, "ui-semibold", "fs-md", "text", iw),
                    K.vspan("sp-half"),
                    K.text(table.concat(bits, " · "), "ui", "fs-sm", "text-2", iw) }, { pad = "sp-3" })
                table.insert(out, K.vspan("sp-4"))
                table.insert(out, HorizontalGroup:new{ K.hspan(pad), card })
                -- actions: Previous · Next · All results
                local BD = require("ui/bidi")
                local back_t, fwd_t = BD.getArrowLabels()
                local bw = math.floor((cw - 2 * T.px("sp-2")) / 3)
                table.insert(out, K.vspan("sp-3"))
                table.insert(out, HorizontalGroup:new{ K.hspan(pad),
                    K.button{ label = back_t .. " " .. _("Previous"), kind = "secondary", width = bw, parent = p,
                        callback = function() p:submit(1) end },
                    K.hspan("sp-2"),
                    K.button{ label = _("Next") .. " " .. fwd_t, kind = "secondary", width = bw, parent = p,
                        callback = function() p:submit(0) end },
                    K.hspan("sp-2"),
                    K.button{ label = _("All results"), kind = "primary", width = bw, parent = p,
                        callback = function() p:submit(nil) end } })
                if rs.findall_results and #rs.findall_results > 0 and rs.last_search_text then
                    table.insert(out, K.vspan("sp-3"))
                    table.insert(out, K.section(_("Last search"), W))
                    table.insert(out, K.row{ width = W, tile = "leaf.sys.text",
                        label = T_(_("Matches for “%1”"), rs.last_search_text),
                        sub = T_(_("%1 matches"), #rs.findall_results),
                        trailing = K.icon("chevron.right", "icon-md", true),
                        callback = function()
                            UIManager:close(p)
                            rs:onShowFindAllResults()
                        end })
                end
                return out
            end,
            on_search = function(p, text, reverse)
                rs.input_dialog = p
                rs:searchCallback(reverse)
            end,
        }
        self.input_dialog = page
        UIManager:show(page)
    end, "ReaderSearch:onShowFulltextSearchInput")

    L.wrap(ReaderSearch, "updateAllResultsMenu", function(orig, self, item_table, item_index)
        orig(self, item_table, item_index)
        local menu = self.result_menu
        if menu and menu.title_bar and menu.title_bar.setTitle then
            local n = #(item_table or menu.item_table or {})
            menu.title_bar:setTitle(T_(_("%1 matches for “%2”"), n, self.last_search_text or ""))
            local props = self.ui.doc_props or {}
            local book = props.display_title or props.title
            if book and menu.title_bar.setSubTitle then menu.title_bar:setSubTitle(T_(_("In %1"), book)) end
        end
    end, "ReaderSearch:updateAllResultsMenu")
end

return M
