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
               reopen KOReader's last result lists. File search start page: BROWSE YOUR LIBRARY
               (Titles / Authors / Series / Folders tiles: a search for "*", an author or series
               list -> metadata search, the home folder) and RECENTLY OPENED covers (book details).
      keyboard: KOReader's on-screen keyboard (Leaf-styled), Enter reads "Search" (Next / Current
               folder, KOReader's enter defaults).
      results: both result lists are Leaf pages (prototype .sr): in a book, chapter-grouped snippet
               cards in the book face; file search, book rows (cover, progress, format, size,
               Resume/Open) and folder rows. KOReader's own lists stay one tap away (⋮).
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
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
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
    local clear_button

    -- the search header (.sr-head): ‹ · field (.kb-field--lg: --surface-2, --r-lg, 52px, search icon,
    -- content, trailing) · right button. `content` is the InputText, or a static label on the results page.
    local FIELD_H = Screen:scaleBySize(52 * T.scale) -- .kb-field--lg min-height (raw in the prototype CSS)

    -- .kb-clear: an x in a --h-chip --surface-3 circle (--text-2), in a --hit tap area
    function clear_button(cb)
        local c = T.px("h-chip")
        local hit = T.px("hit")
        return K.tap(CenterContainer:new{ dimen = K.geom(hit, hit),
            FrameContainer:new{ bordersize = 0, background = T.color("surface-3"), radius = math.floor(c / 2), padding = 0, margin = 0,
                CenterContainer:new{ dimen = K.geom(c, c), K.icon("leaf.gl.close", "icon-sm") } } }, cb)
    end

    -- the search header: the status strip, then .sr-head (← back · field · right button)
    function M.search_head(page, content, trailing, right)
        local W = Screen:getWidth()
        local hit = T.px("hit")
        local field_w = W - 2 * T.px("sp-2") - 2 * hit - 2 * T.px("sp-1")
        local fh = FIELD_H
        local hair = T.px("hairline")
        -- e-ink: --surface-2 and --bg print the same grey, so the field keeps a hairline (--border)
        local field = FrameContainer:new{
            bordersize = hair, color = T.color("border"), background = T.color("surface-2"), radius = T.px("r-lg"), padding = 0,
            OverlapGroup:new{ dimen = K.geom(field_w - 2 * hair, fh - 2 * hair),
                LeftContainer:new{ dimen = K.geom(field_w - 2 * hair, fh - 2 * hair), HorizontalGroup:new{ align = "center",
                    K.hspan("sp-3"), K.icon("leaf.sys.search", "icon-md"), K.hspan("sp-1"), content } },
                require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(field_w - 2 * hair, fh - 2 * hair),
                    trailing or K.hspan(0) },
            },
        }
        local head = HorizontalGroup:new{ align = "center",
            K.hspan("sp-2"),
            K.icon_button("leaf.kb.left", function() page:onClose() end, page),
            K.hspan("sp-1"), field, K.hspan("sp-1"),
            right or K.hspan(hit),
        }
        return VerticalGroup:new{ align = "left", require("leaf/widgets/kit").status_strip(W),
            CenterContainer:new{ dimen = K.geom(W, fh + 2 * T.px("sp-2")), head } }
    end

    -- the book's cover thumbnail (.sr-thumb: 44px wide, 2:3)
    local function book_thumb(ui)
        local w = T.px("hit")
        local h = math.floor(w * 1.5)
        local cover
        pcall(function()
            local bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(ui.document)
            if bb then
                cover = require("ui/widget/imagewidget"):new{ image = bb, image_disposable = true, width = w, height = h,
                    scale_factor = math.max(w / bb:getWidth(), h / bb:getHeight()), center_x_ratio = 0.5, center_y_ratio = 0.5 }
            end
        end)
        if not cover then return nil end
        return FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"), padding = 0, cover }
    end
    M.book_thumb = book_thumb

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
            text = self.text or "", hint = self.hint, face = L.face("ui", "fs-lg"),
            width = text_w, padding = T.px("sp-2"), margin = 0, bordersize = 0,
            scroll = false, focused = true, parent = self,
            _leaf_enter_label = _("Search"), -- the keyboard's Enter key (leaf/keyboard.lua)
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
        local header = M.search_head(self, self.input,
            self._has_text and clear_button( function() self:setSearch("") end, self, { size = "icon-sm" }),
            self:kbButton())

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
                table.insert(chips, K.chip{ label = q, icon = "leaf.sys.recent", dim = true, lg = true,
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
        for _i, w in ipairs(self.after_func and self.after_func(self, W) or {}) do
            table.insert(body, w)
        end
        self:frame(body)
    end

    -- the keyboard toggle (.sr-kbbtn): keyboard icon; while the keyboard is shown, keyboard-off
    -- pressed in (.ko-icon-btn.on, e-ink: --bw-lg --text ring)
    function SearchPage:kbButton()
        local function toggle()
            self.input:toggleKeyboard()
            self._kb_on = self.input:isKeyboardVisible()
            self:rebuild()
            UIManager:setDirty(nil, "ui")
        end
        if self._kb_on == false then return K.icon_button("leaf.sys.keyboard", toggle, self) end
        local hit = T.px("hit")
        local bw = T.px("bw-lg")
        return K.tap(FrameContainer:new{ bordersize = bw, color = T.color("text"), background = T.color("accent-soft"),
            radius = T.px("r-md"), padding = 0, margin = 0,
            CenterContainer:new{ dimen = K.geom(hit - 2 * bw, hit - 2 * bw), K.icon("leaf.sys.keyboard-off", "icon-md") } }, toggle)
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

    -- the library at a glance (search start page): books and folders under the home folder, authors
    -- and series from Project: Title's book cache (bookinfomanager), when it is there
    local function library_index(home)
        local lfs = require("libs/libkoreader-lfs")
        local DocumentRegistry = require("document/documentregistry")
        local idx = { books = 0, folders = 0, authors = {}, series = {} }
        local function walk(dir, depth)
            if depth > 8 then return end
            local ok, iter, d = pcall(lfs.dir, dir)
            if not ok then return end
            for f in iter, d do
                if f ~= "." and f ~= ".." and not f:match("^%.") then
                    local path = dir .. "/" .. f
                    local mode = lfs.attributes(path, "mode")
                    if mode == "directory" then
                        if not f:match("%.sdr$") then
                            idx.folders = idx.folders + 1
                            walk(path, depth + 1)
                        end
                    elseif mode == "file" and DocumentRegistry:hasProvider(path) then
                        idx.books = idx.books + 1
                    end
                end
            end
        end
        walk(home, 1)
        local BIM = package.loaded["bookinfomanager"]
        if BIM then
            pcall(function()
                BIM:openDbConnection()
                local q = string.format("SELECT authors, series FROM bookinfo WHERE directory LIKE '%s%%' AND unsupported IS NULL;",
                    (home:gsub("'", "''")))
                local res = BIM.db_conn:exec(q)
                if res then
                    for i = 1, #(res[1] or {}) do
                        local a, sr = res[1][i], res[2] and res[2][i]
                        if a and a ~= "" then
                            for one in tostring(a):gmatch("[^\n]+") do idx.authors[one] = (idx.authors[one] or 0) + 1 end
                        end
                        if sr and sr ~= "" then idx.series[tostring(sr)] = (idx.series[tostring(sr)] or 0) + 1 end
                    end
                end
            end)
        end
        local function count(t) local n = 0 for _k in pairs(t) do n = n + 1 end return n end
        idx.n_authors, idx.n_series = count(idx.authors), count(idx.series)
        return idx
    end

    -- a list of authors / series (name · number of books); tap = a metadata search for it
    local function value_list(title, values, on_pick)
        local Menu = require("ui/widget/menu")
        local items = {}
        for v, n in pairs(values) do table.insert(items, { text = v, mandatory = n, callback = function() on_pick(v) end }) end
        table.sort(items, function(a, b) return a.text:lower() < b.text:lower() end)
        local menu
        menu = Menu:new{ title = title, item_table = items, covers_fullscreen = true, is_borderless = true,
            is_popout = false, title_bar_fm_style = true,
            onMenuChoice = function(_m, item) UIManager:close(menu) item.callback() end,
            close_callback = function() UIManager:close(menu) end }
        UIManager:show(menu)
    end
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
            after_func = function(p, W)
                local out = {}
                local home = G_reader_settings:readSetting("home_dir")
                if not home then return out end
                local pad = T.px("sp-4")
                local idx = p._leaf_index or library_index(home)
                p._leaf_index = idx
                -- run a KOReader file search in the home folder (subfolders on; metadata when asked)
                local function search_all(text, metadata)
                    local sub, meta = fs.include_subfolders, fs.include_metadata
                    fs.include_subfolders = true
                    if metadata ~= nil then fs.include_metadata = metadata end
                    FileSearcher.search_string = text
                    FileSearcher.search_path = home
                    UIManager:close(p)
                    require("ui/trapper"):wrap(function()
                        fs:doSearch()
                        fs.include_subfolders, fs.include_metadata = sub, meta
                    end)
                end
                -- BROWSE YOUR LIBRARY (.sr-browse): 2 x 2 tiles
                table.insert(out, K.vspan("sp-2"))
                table.insert(out, K.section(_("Browse your library"), W))
                local gap = T.px("sp-2")
                local tw = math.floor((W - 2 * pad - gap) / 2)
                local function tile(icon, label, sub, cb, enabled)
                    local iw = K.inner(tw, { pad = "sp-3" })
                    local t = K.tile(icon, { size = "hit", icon = "icon-md", bg = "surface-2" })
                    local col = VerticalGroup:new{ align = "left",
                        K.text(label, "ui-semibold", "fs-md", enabled and "text" or "text-3", iw - T.px("hit") - T.px("sp-3")),
                        K.vspan("sp-half"),
                        K.text(sub, "ui", "fs-xs", "text-3", iw - T.px("hit") - T.px("sp-3")) }
                    local card = K.card(tw, HorizontalGroup:new{ align = "center", t, K.hspan("sp-3"), col }, { pad = "sp-3", radius = "r-lg" })
                    return enabled and K.tap(card, cb) or card
                end
                local metadata_ok = fs.ui.coverbrowser ~= nil and package.loaded["bookinfomanager"] ~= nil
                local row1 = HorizontalGroup:new{ K.hspan(pad),
                    tile("leaf.sys.titles", _("Titles"), T_(N_("1 book", "%1 books", idx.books), idx.books),
                        function() search_all("*") end, idx.books > 0),
                    K.hspan(gap),
                    tile("leaf.sys.user", _("Authors"), T_(N_("1 author", "%1 authors", idx.n_authors), idx.n_authors),
                        function() value_list(_("Authors"), idx.authors, function(v) search_all(v, true) end) end,
                        metadata_ok and idx.n_authors > 0) }
                local row2 = HorizontalGroup:new{ K.hspan(pad),
                    tile("leaf.sys.layers", _("Series"), T_(N_("1 series", "%1 series", idx.n_series), idx.n_series),
                        function() value_list(_("Series"), idx.series, function(v) search_all(v, true) end) end,
                        metadata_ok and idx.n_series > 0),
                    K.hspan(gap),
                    tile("leaf.sys.folder", _("Folders"), T_(N_("1 folder", "%1 folders", idx.folders), idx.folders),
                        function()
                            UIManager:close(p)
                            if fs.ui.onHome then fs.ui:onHome() end
                        end, in_fm) }
                table.insert(out, row1)
                table.insert(out, K.vspan(gap))
                table.insert(out, row2)
                -- RECENTLY OPENED (.sr-recent): covers from the history
                local ReadHistory = require("readhistory")
                local lfs = require("libs/libkoreader-lfs")
                local files = {}
                for _i, h in ipairs(ReadHistory.hist or {}) do
                    if #files >= 6 then break end
                    if h.file and lfs.attributes(h.file, "mode") == "file" then table.insert(files, h.file) end
                end
                if #files > 0 then
                    local P = require("leaf/widgets/libparts")
                    table.insert(out, K.vspan("sp-3"))
                    table.insert(out, K.section(_("Recently opened"), W))
                    local n, cg = 6, T.px("sp-3")
                    local cw = math.floor((W - 2 * T.px("sp-5") - (n - 1) * cg) / n)
                    local row = HorizontalGroup:new{ align = "top", K.hspan("sp-5") }
                    for i, f in ipairs(files) do
                        if i > 1 then table.insert(row, K.hspan(cg)) end
                        local info = P.bookInfo(f)
                        table.insert(row, P.Tap:new{ content = P.coverBox(f, cw, math.floor(cw * 1.5), { title = info.title }),
                            callback = function()
                                UIManager:close(p)
                                local BookInfo = require("apps/filemanager/filemanagerbookinfo")
                                BookInfo:show(f)
                            end })
                    end
                    table.insert(out, row)
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
                local nch = 0
                pcall(function() for _i, t in ipairs(rs.ui.toc.toc or {}) do if t.depth == 1 then nch = nch + 1 end end end)
                if nch > 1 then table.insert(bits, T_(_("%1 chapters"), nch)) end
                local thumb = book_thumb(rs.ui)
                local tw = iw - (thumb and (thumb:getSize().w + T.px("sp-3")) or 0)
                local col = VerticalGroup:new{ align = "left",
                    K.text(_("SEARCHING IN"), "ui-semibold", "fs-2xs", "text-3", tw),
                    K.vspan("sp-1"),
                    K.text(title, "ui-medium", "fs-md", "text", tw),
                    K.vspan("sp-half"),
                    K.text(table.concat(bits, " · "), "ui", "fs-sm", "text-2", tw) }
                local card = K.card(cw, thumb and HorizontalGroup:new{ align = "center", thumb, K.hspan("sp-3"), col } or col, { pad = "sp-3" })
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

    ------------------------------------------------------------------ in-book results (prototype scope "book")
    -- KOReader's result list (a Menu) is replaced by a page of chapter-grouped snippet cards:
    --   header: ‹ · the query (tap = edit the search) · ⋮ (KOReader's results menu: all results,
    --           current chapter, current page, back to the original page)
    --   "SEARCHING IN" card · "61 matches for “silence” in 11 chapters"
    --   per chapter: CHAPTER I (count) ........ p. 3–8, then up to 3 cards (chapter · page, the
    --   snippet in the book face, the match in bold); "4 more in Chapter I ›" opens that chapter alone
    -- KOReader pages, it doesn't scroll: the blocks are cut into pages with a pager at the bottom.
    -- The Menu is still built (unshown): it holds the list KOReader's result navigation walks.
    local TextBoxWidget = require("ui/widget/textboxwidget")
    -- cut blocks ({widget, gap, head}) into screen pages under `top`, with a pager (.ko-pager) at the bottom;
    -- swipes turn the pages too (KOReader pages, it doesn't scroll)
    local function paginate(self, top, blocks)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pager_h = T.px("h-header")
        local avail = H - top:getSize().h - pager_h - T.px("sp-3")
        top:resetLayout()
        local pages, cur, used = {}, {}, 0
        for i, b in ipairs(blocks) do
            local h = b.widget:getSize().h + T.px(b.gap or "sp-2")
            -- a chapter label never ends a page
            local nxt = blocks[i + 1]
            local need = h + ((b.head and nxt) and (nxt.widget:getSize().h + T.px(nxt.gap or "sp-2")) or 0)
            if used > 0 and used + need > avail then
                table.insert(pages, cur)
                cur, used = {}, 0
            end
            table.insert(cur, b)
            used = used + h
        end
        if #cur > 0 then table.insert(pages, cur) end
        self.page_count = math.max(1, #pages)
        self.page_no = math.max(1, math.min(self.page_no, self.page_count))
        local body = VerticalGroup:new{ align = "left", top }
        for _i, b in ipairs(pages[self.page_no] or {}) do
            table.insert(body, K.vspan(b.gap or "sp-2"))
            table.insert(body, b.widget)
        end
        -- pager (.ko-pager): ‹  Page 1 of 4  ›
        local pager
        if self.page_count > 1 then
            local BD = require("ui/bidi")
            local function go(d)
                self.page_no = self.page_no + d
                self:rebuild()
            end
            pager = VerticalGroup:new{ K.line(W), CenterContainer:new{ dimen = K.geom(W, pager_h), HorizontalGroup:new{ align = "center",
                self.page_no > 1 and K.icon_button(BD.mirroredUILayout() and "chevron.right" or "chevron.left", function() go(-1) end, self) or K.hspan("hit"),
                K.hspan("sp-3"),
                K.text(T_(_("Page %1 of %2"), self.page_no, self.page_count), "ui", "fs-sm", "text-2"),
                K.hspan("sp-3"),
                self.page_no < self.page_count and K.icon_button(BD.mirroredUILayout() and "chevron.left" or "chevron.right", function() go(1) end, self) or K.hspan("hit"),
            } } }
        end
        self:frame(body, pager)
    end

    local ResultsPage = K.Page:extend{ page_no = 1, chapter = nil }

    function ResultsPage:groups()
        local rs = self.rs
        local items = rs.result_menu and rs.result_menu.item_table or rs.findall_results or {}
        local groups, by = {}, {}
        for i, item in ipairs(items) do
            item._leaf_i = i
            if item._leaf_ch == nil then
                local ok, t = pcall(rs.ui.toc.getTocTitleByPage, rs.ui.toc, item.start)
                item._leaf_ch = ok and t and t ~= "" and t or false
            end
            local key = item._leaf_ch or ""
            local g = by[key]
            if not g then
                g = { title = item._leaf_ch or _("Start of the book"), items = {} }
                by[key] = g
                table.insert(groups, g)
            end
            table.insert(g.items, item)
        end
        return groups, #items
    end

    -- the snippet: "…before **match** after…" (Poor Text Formatting bold for the match)
    local function snippet(item)
        local function flat(t) return (t or ""):gsub("%s+", " ") end
        local prev, nxt = flat(item.prev_text), flat(item.next_text)
        if prev ~= "" and not prev:find(" $") then prev = prev .. " " end
        if nxt ~= "" and not nxt:find("^[%s%p]") then nxt = " " .. nxt end
        return table.concat{ TextBoxWidget.PTF_HEADER, "…", (prev:gsub("^ ", "")), TextBoxWidget.PTF_BOLD_START,
            (item.matched_word_prefix or "") .. (item.matched_text or "") .. (item.matched_word_suffix or ""),
            TextBoxWidget.PTF_BOLD_END, (nxt:gsub(" $", "")), "…" }
    end
    -- the match is also underlined (search-term mark: 2px --accent underline)
    local MarkedText = TextBoxWidget:extend{}
    function MarkedText:paintTo(bb, x, y)
        TextBoxWidget.paintTo(self, bb, x, y)
        local bold = self._ptf_char_is_bold
        if not bold then return end
        pcall(function()
            local n = #self.charlist
            local i = 1
            while i <= n do
                if bold[i] then
                    local j = i
                    while j < n and bold[j + 1] do j = j + 1 end
                    local x0, y0 = self:_getXYForCharPos(i)
                    local x1, y1 = self:_getXYForCharPos(j + 1)
                    if y1 ~= y0 then x1 = self.width end
                    local uy = y0 + self.line_glyph_baseline + T.px("sp-half") + T.px("hairline")
                    if uy < self.height then
                        bb:paintRect(x + x0, y + uy, math.max(0, x1 - x0), T.px("bw-lg"), T.color("accent"))
                    end
                    i = j + 1
                else
                    i = i + 1
                end
            end
        end)
    end

    function ResultsPage:card(item, w)
        local pad = T.px("sp-3")
        local iw = K.inner(w, { pad = "sp-3" })
        local loc = {}
        if item._leaf_ch then table.insert(loc, item._leaf_ch) end
        table.insert(loc, T_(_("p. %1"), item.mandatory or "?"))
        local col = VerticalGroup:new{ align = "left",
            K.text(table.concat(loc, "  •  "), "ui", "fs-xs", "text-3", iw),
            K.vspan("sp-1h"),
            MarkedText:new{ text = snippet(item), face = L.face("book", "fs-md"),
                fgcolor = T.color("text"), bgcolor = T.color("surface"), width = iw, line_height = 0.5,
                height = 3 * math.floor(L.face("book", "fs-md").size * 1.5 + 0.5), height_adjust = true,
                height_overflow_show_ellipsis = true },
        }
        local rs = self.rs
        local idx = item._leaf_i
        return K.tap(K.card(w, col, { pad = "sp-3", radius = "r-md" }), function()
            self.rs.findall_results_item_index = idx
            UIManager:close(self)
            rs:gotoResultsItem(idx)
        end, function()
            -- KOReader: hold a result = its place in the table of contents
            local menu = rs.result_menu
            if menu and menu.onMenuHold then menu:onMenuHold(item) end
        end)
    end

    function ResultsPage:blocks(W)
        local rs = self.rs
        local pad = T.px("sp-5")
        local cw = W - 2 * T.px("sp-4")
        local groups, total = self:groups()
        local out = {}
        local q = rs.last_search_text or ""
        local function add(w) table.insert(out, w) end
        -- summary (.sr-summary)
        local nch = 0
        for _i, g in ipairs(groups) do if g.title ~= _("Start of the book") or #groups == 1 then nch = nch + 1 end end
        local sum
        if self.chapter then
            local g
            for _i, gg in ipairs(groups) do if gg.title == self.chapter then g = gg end end
            sum = HorizontalGroup:new{ align = "center",
                K.text(tostring(g and #g.items or 0), "ui-semibold", "fs-sm", "text"),
                K.text(" " .. T_(_("matches for “%1” in %2"), q, self.chapter), "ui", "fs-sm", "text-2",
                    W - 2 * pad - Screen:scaleBySize(140 * T.scale)) }
            local all = K.tap(K.text(_("All chapters"), "ui-medium", "fs-sm", "accent"), function()
                self.chapter, self.page_no = nil, 1
                self:rebuild()
            end)
            add({ widget = OverlapGroup:new{ dimen = K.geom(W, T.px("h-control")),
                LeftContainer:new{ dimen = K.geom(W, T.px("h-control")), HorizontalGroup:new{ K.hspan(pad), sum } },
                require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(W, T.px("h-control")),
                    HorizontalGroup:new{ all, K.hspan(pad) } } } })
            groups = { g }
        else
            sum = HorizontalGroup:new{ align = "center",
                K.text(tostring(total), "ui-semibold", "fs-sm", "text"),
                K.text(" " .. (nch > 1 and T_(_("matches for “%1” in %2 chapters"), q, nch) or T_(_("matches for “%1”"), q)),
                    "ui", "fs-sm", "text-2", W - 2 * pad - Screen:scaleBySize(60 * T.scale)) }
            add({ widget = HorizontalGroup:new{ K.hspan(pad), sum }, gap = "sp-2" })
        end
        for _i, g in ipairs(groups) do
            if g then
                -- chapter label (.ko-section-label .sr-sec): title · count pill ...... p. a–b
                local n = #g.items
                local pill_t = K.text(tostring(n), "ui", "fs-xs", "text-2")
                local ph = pill_t:getSize().h + 2 * T.px("sp-half")
                local pill = FrameContainer:new{ bordersize = 0, background = T.color("surface-3"), radius = math.floor(ph / 2),
                    padding = 0, padding_left = Screen:scaleBySize(7 * T.scale), padding_right = Screen:scaleBySize(7 * T.scale),
                    CenterContainer:new{ dimen = K.geom(pill_t:getSize().w, ph), pill_t } }
                local p0, p1 = g.items[1].mandatory, g.items[n].mandatory
                local range = (p0 == p1) and T_(_("p. %1"), p0) or T_(_("p. %1–%2"), p0, p1)
                local hh = T.px("h-control")
                add({ widget = OverlapGroup:new{ dimen = K.geom(W, hh),
                    LeftContainer:new{ dimen = K.geom(W, hh), HorizontalGroup:new{ align = "center", K.hspan(pad),
                        K.text(g.title:upper(), "ui-semibold", "fs-xs", "text-3", math.floor(W * 0.6)), K.hspan("sp-2"), pill } },
                    require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(W, hh),
                        HorizontalGroup:new{ K.text(range, "ui", "fs-xs", "text-3"), K.hspan(pad) } } }, gap = "sp-2", head = true })
                local shown = self.chapter and n or math.min(3, n)
                for i = 1, shown do
                    add({ widget = HorizontalGroup:new{ K.hspan("sp-4"), self:card(g.items[i], cw) }, gap = "sp-2" })
                end
                if shown < n then
                    local title = g.title
                    add({ widget = HorizontalGroup:new{ K.hspan(pad), K.tap(HorizontalGroup:new{ align = "center",
                        K.text(T_(_("%1 more in %2"), n - shown, title), "ui-medium", "fs-sm", "accent", W - 3 * pad),
                        K.hspan("sp-1"), K.icon("chevron.right", "icon-sm") }, function()
                            self.chapter, self.page_no = title, 1
                            self:rebuild()
                        end) }, gap = "sp-1" })
                end
            end
        end
        return out
    end

    function ResultsPage:build()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local rs = self.rs
        local q = rs.last_search_text or ""
        local label = K.tap(K.text(q, "ui", "fs-lg", "text", W - 2 * T.px("hit") - Screen:scaleBySize(120 * T.scale)), function()
            UIManager:close(self)
            rs:onShowFulltextSearchInput(q)
        end)
        local header = M.search_head(self, label,
            clear_button( function()
                UIManager:close(self)
                rs:onShowFulltextSearchInput("")
            end, self, { size = "icon-sm" }),
            K.icon_button("appbar.menu", function()
                if rs.result_menu then
                    rs._leaf_results_page = self
                    rs:showAllResultsMenuDialog()
                end
            end, self))
        local top = VerticalGroup:new{ align = "left", header, K.line(W) }
        -- SEARCHING IN card (first page only)
        local blocks = self:blocks(W)
        if not self.chapter then
            local props = rs.ui.doc_props or {}
            local pad = T.px("sp-4")
            local cw = W - 2 * pad
            local iw = K.inner(cw, { pad = "sp-3" })
            local thumb = book_thumb(rs.ui)
            local tw = iw - (thumb and (thumb:getSize().w + T.px("sp-3")) or 0)
            local bits = {}
            if props.authors and props.authors ~= "" then table.insert(bits, (props.authors:gsub("\n", ", "))) end
            local pages = rs.ui.document and rs.ui.document:getPageCount()
            if pages then table.insert(bits, T_(_("%1 pages"), pages)) end
            local col = VerticalGroup:new{ align = "left",
                K.text(_("SEARCHING IN"), "ui-semibold", "fs-2xs", "text-3", tw), K.vspan("sp-1"),
                K.text(props.display_title or props.title or "", "ui-medium", "fs-md", "text", tw), K.vspan("sp-half"),
                K.text(table.concat(bits, " · "), "ui", "fs-sm", "text-2", tw) }
            table.insert(blocks, 1, { widget = HorizontalGroup:new{ K.hspan(pad),
                K.card(cw, thumb and HorizontalGroup:new{ align = "center", thumb, K.hspan("sp-3"), col } or col, { pad = "sp-3" }) },
                gap = "sp-4" })
        end
        paginate(self, top, blocks)
    end
    local function onSwipe(self, _arg, ges)
        local dir = ges.direction
        if dir == "west" and self.page_no < self.page_count then self.page_no = self.page_no + 1 self:rebuild() return true end
        if dir == "east" and self.page_no > 1 then self.page_no = self.page_no - 1 self:rebuild() return true end
    end
    ResultsPage.onSwipe = onSwipe
    function ResultsPage:onClose()
        local rs = self.rs
        if rs.result_menu and rs.result_menu.close_callback then pcall(rs.result_menu.close_callback) end
        UIManager:close(self)
        return true
    end
    M.ResultsPage = ResultsPage

    ------------------------------------------------------------------ file search results (prototype scope "all")
    -- KOReader's result list (BookList, Project: Title's mosaic) is replaced by .sr rows:
    --   header: ‹ · the query (tap = edit) · ⋮ = KOReader's own result list (select mode, every action)
    --   "3 results for “animal”", BOOKS (n): cover · title (match in bold, underlined) · author ·
    --   progress / New / Finished · FORMAT pill · size · Resume/Open; FOLDERS (n): folder rows
    -- tap a book = book details, Open/Resume = read it, hold = KOReader's file actions.
    local FileResultsPage = K.Page:extend{ page_no = 1 }
    FileResultsPage.onSwipe = onSwipe

    local function marked(text, q, role, size, color, width, bg)
        local s, e
        if q ~= "" then s, e = text:lower():find(q:lower(), 1, true) end
        local t = text
        if s and not q:find("[%*%?]") then
            t = TextBoxWidget.PTF_HEADER .. text:sub(1, s - 1) .. TextBoxWidget.PTF_BOLD_START .. text:sub(s, e)
                .. TextBoxWidget.PTF_BOLD_END .. text:sub(e + 1)
        end
        local face = L.face(role, size)
        return MarkedText:new{ text = t, face = face, fgcolor = T.color(color), bgcolor = T.color(bg or "bg"), width = width,
            height = math.floor(face.size * 1.4 + 0.5), height_adjust = true, height_overflow_show_ellipsis = true }
    end

    function FileResultsPage:build()
        local W = Screen:getWidth()
        local fs = self.fs
        local menu = fs.booklist_menu
        local q = FileSearcher.search_string or ""
        local lfs = require("libs/libkoreader-lfs")
        local P = require("leaf/widgets/libparts")
        local label = K.tap(K.text(q, "ui", "fs-lg", "text", W - 2 * T.px("hit") - Screen:scaleBySize(120 * T.scale)), function()
            UIManager:close(self)
            fs:onShowFileSearch(q)
        end)
        local header = M.search_head(self, label,
            clear_button( function()
                UIManager:close(self)
                fs:onShowFileSearch("")
            end, self, { size = "icon-sm" }),
            K.icon_button("appbar.menu", function()
                -- KOReader's own list: select mode, sorting, every file action
                UIManager:close(self)
                fs._leaf_native = true
                fs:onShowSearchResults()
                fs._leaf_native = nil
            end, self))
        local top = VerticalGroup:new{ align = "left", header, K.line(W) }
        local items = menu and menu.item_table or FileSearcher.search_results or {}
        local books, dirs = {}, {}
        for _i, it in ipairs(items) do
            if it.is_file then table.insert(books, it) elseif it.path then table.insert(dirs, it) end
        end
        local blocks = {}
        local pad = T.px("sp-5")
        local total = #books + #dirs
        local sum = HorizontalGroup:new{ align = "center", K.text(tostring(total), "ui-semibold", "fs-sm", "text"),
            K.text(" " .. (q == "*" and _("books and folders") or T_(_("results for “%1”"), q)), "ui", "fs-sm", "text-2", W - 3 * pad) }
        table.insert(blocks, { widget = HorizontalGroup:new{ K.hspan(pad), sum }, gap = "sp-4" })
        local function section(title, n)
            local pill_t = K.text(tostring(n), "ui", "fs-xs", "text-2")
            local ph = pill_t:getSize().h + 2 * T.px("sp-half")
            -- .sr-count is --surface-2, which prints as --bg on e-ink: one step darker so it still reads as a pill
            local pill = FrameContainer:new{ bordersize = 0, background = T.color("surface-3"), radius = math.floor(ph / 2),
                padding = 0, padding_left = Screen:scaleBySize(7 * T.scale), padding_right = Screen:scaleBySize(7 * T.scale),
                CenterContainer:new{ dimen = K.geom(pill_t:getSize().w, ph), pill_t } }
            return { widget = LeftContainer:new{ dimen = K.geom(W, T.px("h-control")), HorizontalGroup:new{ align = "center",
                K.hspan(pad), K.text(title:upper(), "ui-semibold", "fs-xs", "text-3"), K.hspan("sp-2"), pill } },
                gap = "sp-3", head = true }
        end
        local function select(it)
            UIManager:close(self)
            if menu then fs.onMenuSelect(menu, it) end
        end
        local function hold(it)
            if menu then fs.onMenuHold(menu, it) end
        end
        local row_h = Screen:scaleBySize(60 * T.scale)
        if #books > 0 then
            table.insert(blocks, section(_("Books"), #books))
            for i, it in ipairs(books) do
                local info = P.bookInfo(it.path)
                local tw_ = T.px("hit")
                local cover = P.coverBox(it.path, tw_, math.floor(tw_ * 1.5), { title = info.title })
                local done = info.status == "complete"
                -- .ko-btn--sm .sr-open: book icon + Resume / Open, --h-control, --surface-2, hairline --border
                local bl = HorizontalGroup:new{ align = "center", K.icon("leaf.sys.book", "icon-sm"), K.hspan("sp-2"),
                    K.text((info.pct or 0) > 0 and not done and _("Resume") or _("Open"), "ui-medium", "fs-sm", "text") }
                local bh = T.px("h-control")
                local btn = K.tap(FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"),
                    background = T.color("surface-2"), radius = T.px("r-md"), padding = 0,
                    padding_left = T.px("sp-3"), padding_right = T.px("sp-3"),
                    CenterContainer:new{ dimen = K.geom(bl:getSize().w, bh - 2 * T.px("hairline")), bl } },
                    function() select(it) end)
                local text_w = W - 2 * pad - tw_ - 2 * T.px("sp-3") - btn:getSize().w
                local meta = HorizontalGroup:new{ align = "center" }
                if done then
                    table.insert(meta, K.icon("leaf.sys.check", "icon-xs"))
                    table.insert(meta, K.hspan("sp-1"))
                    table.insert(meta, K.text(_("Finished"), "ui-medium", "fs-xs", "text"))
                elseif info.status == "new" or (info.pct or 0) == 0 then
                    table.insert(meta, K.text(_("New"), "ui-medium", "fs-xs", "accent"))
                else
                    table.insert(meta, P.Bar:new{ width = Screen:scaleBySize(36 * T.scale), height = P.px(2), pct = info.pct })
                    table.insert(meta, K.hspan("sp-1h"))
                    table.insert(meta, K.text(string.format("%d%%", math.floor(info.pct * 100 + 0.5)), "ui-medium", "fs-xs", "text-2"))
                end
                local ext = (it.path:match("%.([^./]+)$") or ""):upper()
                if ext ~= "" then
                    local et = K.text(ext, "ui-semibold", "fs-2xs", "text-2")
                    local eh = et:getSize().h + 2 * T.px("sp-half")
                    table.insert(meta, K.hspan("sp-2"))
                    table.insert(meta, FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border-strong"),
                        radius = math.floor(eh / 2), padding = 0, padding_left = T.px("sp-1h"), padding_right = T.px("sp-1h"),
                        CenterContainer:new{ dimen = K.geom(et:getSize().w, eh), et } })
                end
                local size = lfs.attributes(it.path, "size")
                if size then
                    table.insert(meta, K.hspan("sp-2"))
                    table.insert(meta, K.text(util.getFriendlySize(size), "ui", "fs-xs", "text-3"))
                end
                local col = VerticalGroup:new{ align = "left",
                    marked(info.title or it.text or "", q, "ui-medium", "fs-md", "text", text_w),
                    K.vspan("sp-half"),
                    K.text(info.authors or "", "ui", "fs-sm", "text-2", text_w),
                    K.vspan("sp-1h"), meta }
                local h = math.max(row_h, math.floor(tw_ * 1.5), col:getSize().h) + 2 * T.px("sp-2")
                col:resetLayout()
                local row = OverlapGroup:new{ dimen = K.geom(W, h),
                    LeftContainer:new{ dimen = K.geom(W, h), HorizontalGroup:new{ align = "center", K.hspan(pad), cover, K.hspan("sp-3"), col } },
                    require("ui/widget/container/rightcontainer"):new{ dimen = K.geom(W, h), HorizontalGroup:new{ btn, K.hspan(pad) } } }
                local path = it.path
                local tap = K.tap(row, function()
                    require("apps/filemanager/filemanagerbookinfo"):show(path)
                end, function() hold(it) end)
                if i > 1 then
                    -- inset hairline (.sr-item + .sr-item::before, from 76px)
                    table.insert(blocks, { widget = HorizontalGroup:new{ K.hspan(pad + tw_ + T.px("sp-3")), K.line(W - 2 * pad - tw_ - T.px("sp-3")) }, gap = "sp-half" })
                end
                table.insert(blocks, { widget = tap, gap = "sp-half" })
            end
        end
        if #dirs > 0 then
            table.insert(blocks, section(_("Folders"), #dirs))
            for _i, it in ipairs(dirs) do
                local name = it.text or it.path:match("([^/]+)/?$") or it.path
                table.insert(blocks, { widget = K.row{ width = W, tile = "leaf.sys.folder", tile_opts = { size = "hit", icon = "icon-md" },
                    label = name:gsub("/$", ""), sub = it.path, height = row_h,
                    trailing = K.icon("chevron.right", "icon-sm"),
                    callback = function() select(it) end, hold = function() hold(it) end }, gap = "sp-half" })
            end
        end
        if total == 0 then
            table.insert(blocks, { widget = CenterContainer:new{ dimen = K.geom(W, Screen:scaleBySize(200 * T.scale)),
                K.text(T_(_("No matches for “%1”"), q), "ui-semibold", "fs-lg", "text") } })
        end
        paginate(self, top, blocks)
    end
    function FileResultsPage:onClose()
        local fs = self.fs
        if fs.booklist_menu and fs.booklist_menu.close_callback then pcall(fs.booklist_menu.close_callback) end
        UIManager:close(self)
        return true
    end

    L.wrap(FileSearcher, "onShowSearchResults", function(orig, self, not_cached)
        if self._leaf_native or (not not_cached and FileSearcher.search_results == nil) then
            return orig(self, not_cached)
        end
        local show = UIManager.show
        local fs = self
        UIManager.show = function(um, w, ...)
            if w ~= nil and w == fs.booklist_menu then return end
            return show(um, w, ...)
        end
        local ok, err = pcall(orig, self, not_cached)
        UIManager.show = show
        if not ok then error(err) end
        local page = FileResultsPage:new{ fs = self }
        page.ges_events = page.ges_events or {}
        page.ges_events.Swipe = { require("ui/gesturerange"):new{ ges = "swipe", range = function() return page.dimen end } }
        UIManager:show(page)
        return true
    end, "FileSearcher:onShowSearchResults")

    L.wrap(ReaderSearch, "onShowFindAllResults", function(orig, self, not_cached)
        if not self.last_search_hash or (not not_cached and self.findall_results == nil) then
            return orig(self, not_cached)
        end
        -- let KOReader prepare its result list (snippets, page numbers, the Menu), without showing it
        local show = UIManager.show
        local rs = self
        UIManager.show = function(um, w, ...)
            if w ~= nil and w == rs.result_menu then return end
            return show(um, w, ...)
        end
        local ok, err = pcall(orig, self, not_cached)
        UIManager.show = show
        if not ok then error(err) end
        if self.result_menu then
            local page = ResultsPage:new{ rs = self }
            page.ges_events = page.ges_events or {}
            page.ges_events.Swipe = { require("ui/gesturerange"):new{ ges = "swipe", range = function() return page.dimen end } }
            self._leaf_results_page = page
            UIManager:show(page)
        end
    end, "ReaderSearch:onShowFindAllResults")

    L.wrap(ReaderSearch, "updateAllResultsMenu", function(orig, self, item_table, item_index)
        orig(self, item_table, item_index)
        -- KOReader's results menu (⋮) changed the list: show it on the Leaf page
        local page = self._leaf_results_page
        if page and page.rs == self and UIManager:isWidgetShown(page) then
            page.chapter, page.page_no = nil, 1
            page:rebuild()
        end
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
