--[[
    Dev helper (inert unless KO_AUTOSHOT is set): screenshot a list of scenes, then quit.
    Driven by tools/ko-sandbox.sh --shots DIR [--scenes a,b] [--night].

    KO_AUTOSHOT=/dir            one PNG per scene: <dir>/<scene>.png (<scene>-night.png in night mode)
    KO_AUTOSHOT_SCENES=a,b,c    subset / order (default: every scene below, reader ones last)
    KO_AUTOSHOT_NIGHT=1         turn night mode on first (Leaf Dark on e-ink = inverted Paper)
    Legacy: KO_AUTOSHOT=/file.png [KO_AUTOSHOT_ACTION=menu|plus|newfolder|<titlebar button>]

    Each scene opens something; after the shot every widget it added is closed again.
--]]
local path = os.getenv("KO_AUTOSHOT")
if not path then return end

local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local logger = require("logger")

local function FM() return require("apps/filemanager/filemanager").instance end
local function RUI() return require("apps/reader/readerui").instance end

-- legacy single-shot mode
if path:match("%.png$") then
    local action = os.getenv("KO_AUTOSHOT_ACTION")
    UIManager:scheduleIn(3, function()
        local fm = FM()
        if action == "menu" then fm.menu:onShowMenu()
        elseif action == "plus" then fm:onShowPlusMenu()
        elseif action == "newfolder" then fm:createFolder()
        elseif action and fm.title_bar[action] then fm.title_bar[action].callback() end
    end)
    UIManager:scheduleIn(5, function()
        Screen:shot(path)
        UIManager:quit()
    end)
    return
end

local function home(f) return G_reader_settings:readSetting("home_dir") .. "/" .. f end
EPUB_BOOK = "Animal Farm (EN-AR).epub" -- every EPUB reader scene (the prototype's animal-farm)
PDF_BOOK = "KOReader UI Redesign Concept.pdf"
-- open a book in the reader unless it is already the open one; true when it had to open it
local function open_book(name)
    local file, ui = home(name), RUI()
    if ui and ui.document and ui.document.file == file then return false end
    if ui then ui:switchDocument(file, true) else require("apps/reader/readerui"):showReader(file) end
    return true
end
local function book_open(kind)
    local ui = RUI()
    return ui and ui.document and ui.document.file == home(kind == "pdf" and PDF_BOOK or EPUB_BOOK)
end

-- reader scenes: Chapter I of the open EPUB (+ n pages), like the prototype's reading page
local function chapter_one(n)
    local ui = RUI()
    if not (ui and ui.rolling) then return end
    for _i, t in ipairs(ui.toc.toc or {}) do
        if t.title:find("Chapter I", 1, true) then
            ui.rolling:onGotoXPointer(t.xpointer)
            if n and n > 0 then ui:handleEvent(require("ui/event"):new("GotoPage", ui.document:getCurrentPage() + n)) end
            return
        end
    end
end
-- a few bookmarks (one with a note) so the bookmark list, skim and book map have something to show
local function seed_bookmarks()
    local ui = RUI()
    if not (ui and ui.rolling) or ui._leaf_seeded then return end
    ui._leaf_seeded = true
    local start
    for _i, t in ipairs(ui.toc.toc or {}) do
        if t.title:find("Chapter I", 1, true) then start = t.page break end
    end
    start = start or 10
    for i, off in ipairs({ 1, 30, 60 }) do
        local pg = start + off
        if not ui.bookmark:isPageBookmarked(ui.document:getPageXPointer(pg)) then ui.bookmark:toggleBookmark(pg) end
        if i == 2 then
            local idx = ui.bookmark:getDogearBookmarkIndex(ui.document:getPageXPointer(pg))
            local item = idx and ui.annotation.annotations[idx]
            if item then item.note = "Start of the vote" end
        end
    end
end

local function show(mod, args) UIManager:show(require(mod):new(args)) end
-- typeset scenes: open the reader's typesetting sheet on a Leaf tab (leaf_key), then run `after`
local function ts_open(key, after)
    local ui = RUI()
    if not ui then return end
    if not ui._leaf_ts_paged and not ui.document.koptinterface then
        ui._leaf_ts_paged = true
        chapter_one(3) -- a text page behind the sheet
    end
    ui.config:onShowConfigMenu()
    local d = ui.config.config_dialog
    if not d then return end
    for i, o in ipairs(d.config_options) do
        if o.leaf_key == key then d:onShowConfigPanel(i) end
    end
    if after then after(d) end
end
local noop = function() end

-- gaps-widgets helpers
local GW = {} -- gaps-widgets scenes: helpers
function GW.arrange(sel)
    local items = {}
    for _i, t in ipairs({ "Favorites", "To read this winter", "Sherlock Holmes", "Arabic", "Poetry", "Book club", "Philosophy", "Comics" }) do
        table.insert(items, { text = t })
    end
    local w = require("ui/widget/sortwidget"):new{ title = "Arrange collections", item_table = items, callback = noop }
    UIManager:show(w)
    if sel then
        w.marked = sel
        w:_populateItems()
    end
    return w
end

-- the read timer's DateTimeWidget, with its check boxes (readtimer.koplugin addCheckboxes)
function GW.timer(kind)
    local CheckButton = require("ui/widget/checkbutton")
    local w = require("ui/widget/datetimewidget"):new(kind == "alarm"
        and { hour = 22, min = 30, ok_text = "Set alarm", title_text = "Alarm", info_text = "Enter a time in hours and minutes.", callback = noop }
        or { hour = 0, min = 20, hour_max = 17, ok_text = "Start timer", title_text = "Interval", info_text = "Enter a time in hours and minutes.", callback = noop })
    if kind ~= "alarm" then w:addWidget(CheckButton:new{ text = "Auto-reschedule", checked = false, parent = w, callback = noop }) end
    w:addWidget(CheckButton:new{ text = "Show timer in alt status bar", checked = false, parent = w, callback = noop })
    w:addWidget(CheckButton:new{ text = "Show timer in status bar", checked = true, parent = w, callback = noop })
    UIManager:show(w)
end

-- a small fake device tree for the path chooser: <data dir>/onboard/{Downloads, Pictures/Covers, …}
function GW.onboard()
    local lfs = require("libs/libkoreader-lfs")
    local root = require("datastorage"):getDataDir() .. "/onboard"
    local function dir(p) lfs.mkdir(root .. (p ~= "" and ("/" .. p) or "")) end
    local function file(p, kb)
        local f = io.open(root .. "/" .. p, "rb")
        if f then f:close() return end
        f = io.open(root .. "/" .. p, "wb")
        if f then f:write(string.rep("x", math.floor(kb * 1024))) f:close() end
    end
    for _i, d in ipairs({ "", "Books", "Downloads", "Downloads/Comics", "Downloads/Articles", "Pictures", "Pictures/Covers",
        "Screenshots", "Documents" }) do dir(d) end
    for i = 1, 10 do file("Downloads/Comics/issue-" .. i .. ".cbz", 1) end
    for i = 1, 12 do file("Downloads/Articles/article-" .. i .. ".html", 1) end
    file("Downloads/comics-pack.zip", 480) file("Downloads/The Odyssey.epub", 120) file("Downloads/receipt.pdf", 88)
    file("Pictures/Covers/animal-farm-1945.jpg", 286) file("Pictures/Covers/animal-farm-penguin.jpg", 302)
    file("Pictures/Covers/moby-dick.png", 540)
    return root
end

-- an input dialog with its keyboard, then a long-press on one of its keys (by key or label)
function GW.hold_key(title, input, which)
    local d
    d = require("ui/widget/inputdialog"):new{ title = title, input = input, input_hint = title == "Search" and "Title, author, text…" or nil,
        buttons = {{ { text = "Cancel", id = "close", callback = function() UIManager:close(d) end },
            { text = "Save", is_enter_default = true, callback = noop } }} }
    UIManager:show(d)
    d:onShowKeyboard()
    UIManager:scheduleIn(0.4, function()
        local kb = d._input_widget and d._input_widget.keyboard
        for _i, row in ipairs(kb and kb.layout or {}) do
            for _j, key in ipairs(row) do
                if (key.key == which or key.label == which) and key.hold_callback then key.hold_callback() return end
            end
        end
    end)
end

-- a note field with a few clipboard snippets (InputText's clipboard settings, as KOReader saves them)
function GW.note_field()
    local IT = require("ui/widget/inputtext")
    if IT.clipboard_settings then
        IT.clipboard_settings.snippets = {
            { name = "Signature", text = "— sent from my e-reader" },
            { text = "Remember to return this book to the library." },
            { name = "Book club", text = "Book club · Thursday 19:00 · chapters 4–6" },
            { name = "Address", text = "12 Rue des Lilas, Lyon" },
        }
    end
    pcall(function() require("device").input.setClipboardText("the creatures outside looked from pig to man") end)
    local d
    d = require("ui/widget/inputdialog"):new{ title = "Add a note", input = "The windmill was finished at last, and the animals",
        buttons = {{ { text = "Cancel", id = "close", callback = function() UIManager:close(d) end },
            { text = "Save", is_enter_default = true, callback = noop } }} }
    UIManager:show(d)
    d:onShowKeyboard()
    return d._input_widget
end

-- the sleep screen, then its lock prompt (ScreenSaverLockWidget), with or without an exit gesture
function GW.unlock(gesture)
    local ss = require("ui/screensaver")
    pcall(function() ss:setup() ss:show() end)
    UIManager:scheduleIn(0.6, function()
        local w = require("ui/widget/screensaverlockwidget"):new{ ui = FM() }
        w.has_exit_screensaver_gesture = gesture
        if gesture then w.ui = { gestures = { gestures = { swipe_north = { exit_screensaver = true } } } } end
        w:showWaitForGestureMessage()
    end)
    UIManager:scheduleIn(2.2, function() pcall(function() ss:close_widget() ss:cleanup() end) end)
end

local LK = {} -- lookup scenes: helpers, defined below the list
local LIB = {} -- library scenes: helpers, defined below the list
local GL = {} -- gaps library scenes: helpers, defined below the list
local GL = {} -- gaps-lists scenes: helpers, defined below the list
local STATS = {} -- gaps-lists stats scenes: helpers, defined below the list
-- desktop has no Wi-Fi hardware: a fake scan result (system and tools scenes)
function LEAF_FAKE_NETWORKS()
    return {
        { ssid = "Home-5G", signal_quality = 92, flags = "[WPA2-PSK-CCMP][ESS]", password = "x", connected = true },
        { ssid = "Home-2.4G", signal_quality = 74, flags = "[WPA2-PSK-CCMP][ESS]", password = "x" },
        { ssid = "Café Lumière", signal_quality = 70, flags = "[WPA2-PSK-CCMP][ESS]" },
        { ssid = "Bibliothèque publique", signal_quality = 48, flags = "[ESS]" },
        { ssid = "Vodafone-7F21", signal_quality = 41, flags = "[WPA2-PSK-CCMP][SAE][ESS]" },
        { ssid = "DIRECT-HP OfficeJet", signal_quality = 22, flags = "[WPA2-PSK-CCMP][ESS]" },
        { ssid = "eduroam", signal_quality = 18, flags = "[WPA2-EAP-CCMP][ESS]" },
    }
end

local SCENES = {
    { "fm", function() LIB.seed() end, wait = 4 },
    { "menu", function() FM().menu:onShowMenu() end },
    { "menu-settings", function()
        local fm = FM()
        fm.menu:onShowMenu()
        local tm = fm.menu.menu_container and fm.menu.menu_container[1]
        if tm then
            for i, tab in ipairs(tm.tab_item_table) do
                if tab.icon == "appbar.settings" then tm.bar:switchToTab(i) end
            end
        end
    end },
    { "menu-sub", function()
        local fm = FM()
        fm.menu:onShowMenu()
        local tm = fm.menu.menu_container and fm.menu.menu_container[1]
        if not tm then return end
        for i, tab in ipairs(tm.tab_item_table) do
            if tab.icon == "appbar.settings" then tm.bar:switchToTab(i) end
        end
        for _, item in ipairs(tm.item_table) do
            if item.sub_item_table or item.sub_item_table_func then tm:onMenuSelect(item) break end
        end
    end },
    { "plus", function() FM():onShowPlusMenu() end },
    { "confirm", function() show("ui/widget/confirmbox", {
        text = "Delete this book?\nThe file and its highlights, notes and reading progress will be removed.",
        ok_text = "Delete", ok_callback = noop }) end },
    { "multiconfirm", function() show("ui/widget/multiconfirmbox", {
        text = "A file with this name already exists.",
        choice1_text = "Keep both", choice1_callback = noop,
        choice2_text = "Replace", choice2_callback = noop }) end },
    { "info", function() show("ui/widget/infomessage", {
        text = "No dictionaries installed.\nDownload one from Settings › Dictionary." }) end },
    { "notify", function() require("ui/widget/notification"):notify("Cache cleared · 142 MB freed",
        require("ui/widget/notification").SOURCE_ALWAYS_SHOW) end },
    { "info-toast", function() show("ui/widget/infomessage", { text = "Cache cleared · 142 MB freed", timeout = 3 }) end },
    { "info-long", function() show("ui/widget/infomessage", {
        text = "Can't open this file.\n\n“comic-chapter-12.cbz” looks damaged or incomplete. Try copying it to the device again." }) end },
    { "notify-stack", function()
        local N = require("ui/widget/notification")
        N:notify("Font size 22", N.SOURCE_ALWAYS_SHOW)
        N:notify("Bookmark added", N.SOURCE_ALWAYS_SHOW)
    end },
    { "input", function()
        local d
        d = require("ui/widget/inputdialog"):new{
            title = "New folder", input_hint = "Folder name",
            buttons = {{
                { text = "Cancel", id = "close", callback = function() UIManager:close(d) end },
                { text = "Create", is_enter_default = true, callback = noop },
            }},
        }
        UIManager:show(d)
        d:onShowKeyboard()
    end },
    { "input-sym", function()
        local d = require("ui/widget/inputdialog"):new{ title = "Go to page", input_hint = "Page 1–112",
            buttons = {{ { text = "Cancel", id = "close", callback = noop }, { text = "Go", is_enter_default = true, callback = noop } }} }
        UIManager:show(d)
        d:onShowKeyboard()
        UIManager:scheduleIn(0.3, function()
            local kb = d._input_widget and d._input_widget.keyboard
            if kb then kb:setLayer("Sym") end
        end)
    end },
    { "input-ar", function()
        local d = require("ui/widget/inputdialog"):new{ title = "Rename collection", input = "روايات",
            buttons = {{ { text = "Cancel", id = "close", callback = noop }, { text = "Save", is_enter_default = true, callback = noop } }} }
        UIManager:show(d)
        d:onShowKeyboard()
        UIManager:scheduleIn(0.3, function()
            local kb = d._input_widget and d._input_widget.keyboard
            if kb then kb:setKeyboardLayout("ar") end
        end)
        -- the layout is saved in settings: put English back once the shot is taken
        UIManager:scheduleIn(1.4, function() G_reader_settings:saveSetting("keyboard_layout", "en") end)
    end },
    { "buttondialog", function()
        -- the library's long-press on a book (Leaf book-actions sheet over KOReader's file dialog)
        LIB.seed()
        local fc = FM().file_chooser
        local file = G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub"
        if fc and fc.showFileDialog then fc:showFileDialog({ path = file, is_file = true, text = "Animal Farm.epub" })
        else show("ui/widget/buttondialog", { title = "Animal Farm", buttons = {
            { { text = "Open", callback = noop }, { text = "Book information", callback = noop } } } }) end
    end, wait = 2 },
    { "spin", function() show("ui/widget/spinwidget", {
        title_text = "Items per page", info_text = "Number of books shown on one page",
        value = 14, value_min = 6, value_max = 24, default_value = 14, callback = noop }) end },
    { "spin-change", function()
        -- moves the slider in code (as a tap at 90% would) to exercise the update path
        local w = require("ui/widget/spinwidget"):new{
            title_text = "Items per page", info_text = "Number of books shown on one page",
            value = 14, value_min = 6, value_max = 24, default_value = 14, callback = noop }
        UIManager:show(w)
        UIManager:scheduleIn(0.5, function()
            local s = w.value_widget.leaf_slider
            if s then s.on_change(0.9, true) end
        end)
    end },
    { "doublespin", function() show("ui/widget/doublespinwidget", {
        title_text = "Page margins", info_text = "Left and right margins, in pixels",
        left_text = "Left", left_value = 18, left_min = 0, left_max = 80, left_default = 15,
        right_text = "Right", right_value = 18, right_min = 0, right_max = 80, right_default = 15,
        callback = noop }) end },
    { "datetime", function() show("ui/widget/datetimewidget", {
        title_text = "Sleep timer", info_text = "Put the device to sleep after this much idle time",
        hour = 0, min = 30, ok_text = "Set", callback = noop }) end },
    { "textviewer", function() show("ui/widget/textviewer", {
        title = "Book description",
        text = "A farm is taken over by its overworked, mistreated animals. With flaming idealism and stirring slogans, they set out to create a paradise of progress, justice, and equality." }) end },
    { "keyvalue", function() show("ui/widget/keyvaluepage", {
        title = "Book information",
        kv_pairs = { { "Title", "Animal Farm" }, { "Author", "George Orwell" }, { "Format", "EPUB" },
            { "Pages", "112" }, "----", { "Language", "en" }, { "Size", "412 KB" } } }) end },
    { "bookdetails", function()
        LIB.seed()
        FM().bookinfo:show(G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub")
    end, wait = 2 },
    -- kvpages scenes (KeyValuePage, TextViewer)
    { "kv-bookinfo", function()
        -- the Leaf book details page, then its ⋮: KOReader's full "Book information" list
        FM().bookinfo:show(G_reader_settings:readSetting("home_dir") .. "/Animal Farm (EN-AR).epub")
        UIManager:scheduleIn(0.5, function()
            local top = UIManager._window_stack[#UIManager._window_stack].widget
            if top.orig_show then top.orig_show(top.bookinfo, top.doc_settings_or_file, top.props_in) end
        end)
    end, wait = 2.5 },
    { "kv-stats", function()
        local kv = {}
        local days = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
        table.insert(kv, { "Total time spent reading", "4 h 06 min" })
        table.insert(kv, { "Pages read", "412" })
        table.insert(kv, { "Average time per page", "36 s", separator = true })
        for i = 1, 24 do
            table.insert(kv, { string.format("%s, Nov %d", days[(i - 1) % 7 + 1], i),
                string.format("%d min · %d pages", 10 + i * 3, 4 + i), callback = noop,
                separator = i % 7 == 0 })
        end
        show("ui/widget/keyvaluepage", { title = "Books by week", value_overflow_align = "right",
            callback_return = noop, kv_pairs = kv })
    end },
    { "kv-single", function() show("ui/widget/keyvaluepage", {
        title = "Current statistics", value_align = "right", single_page = true,
        kv_pairs = { { "Current period", "00:24:12" }, { "Current pages", "18" },
            { "Today", "00:41:05" }, { "Pages today", "31", separator = true },
            { "Time to read", "02:13:40" }, { "Read pages", "39 of 112" },
            { "Percentage completed", "35%" }, { "Average time per page", "1 min 19 s", separator = true },
            { "Book title", "Animal Farm: A Fairy Story, with an introduction and notes on the text" },
            { "Started reading", "2026-11-02" }, { "Last read", "2026-11-19" },
            { "Days reading this book", "12" }, { "Description", "Tap to display", callback = noop } } }) end },
    { "textviewer-long", function()
        local p = "Mr. Jones, of the Manor Farm, had locked the hen-houses for the night, but was too drunk to remember to shut the pop-holes. With the ring of light from his lantern dancing from side to side, he lurched across the yard, kicked off his boots at the back door, drew himself a last glass of beer from the barrel in the scullery, and made his way up to bed, where Mrs. Jones was already snoring."
        show("ui/widget/textviewer", { title = "Note · Chapter I", text = table.concat({ p, p, p, p, p, p, p }, "\n\n") })
    end },
    { "description", function()
        FM().bookinfo:onShowBookDescription(nil, G_reader_settings:readSetting("home_dir") .. "/Animal Farm (EN-AR).epub")
    end },
    { "textviewer-code", function()
        show("ui/widget/textviewer", { title = "Page HTML", text_type = "code",
            text = '<section id="chapter-1" class="chapter">\n  <p class="para" id="p2">\n    The slow on for of Benjamin at the bright, such which Clover that could light old.\n  </p>\n</section>' })
    end },
    -- library scenes (LIB.seed: realistic sandbox data, once: statuses, history, collections, stats)
    { "lib-library", function() LIB.seed() require("leaf/library").showTab("library") LIB.view("grid") end, wait = 4 },
    { "lib-folders", function() LIB.seed() require("leaf/library").showTab("folders") end, wait = 4 },
    { "lib-detail", function()
        LIB.seed()
        require("leaf/library").showTab("library")
        LIB.view("detail")
    end, wait = 3 },
    { "lib-list", function() LIB.seed() require("leaf/library").showTab("library") LIB.view("list") end, wait = 4 },
    { "lib-grid", function() LIB.seed() require("leaf/library").showTab("library") LIB.view("grid") end, wait = 4 },
    { "lib-favorites", function()
        LIB.seed()
        require("leaf/library").showTab("library")
        LIB.view("grid")
        require("leaf/library").showTab("favorites")
    end, wait = 3 },
    { "lib-collections", function() LIB.seed() require("leaf/library").showTab("collections") end, wait = 4 },
    { "lib-history", function()
        LIB.seed()
        require("leaf/library").navigate("history")
    end, wait = 3 },
    { "lib-settings", function() require("leaf/library").navigate("settings") end, wait = 2 },
    { "home", function()
        LIB.seed()
        require("leaf/library").closeOverlays()
        require("leaf/home").show()
    end, wait = 3 },
    { "catalog", function()
        local ok, catalog = pcall(require, "leaf/catalog")
        if ok then catalog.show() else logger.info("autoshot: no leaf/catalog yet") end
    end },
    -- gaps library scenes (leaf/gapslib.lua): select mode list, connected folders, metadata fields,
    -- archive viewer (a test archive made in the sandbox), OPDS page stream (stubbed HTTP)
    { "gl-selfiles", function()
        LIB.seed()
        local h = G_reader_settings:readSetting("home_dir")
        FM().selected_files = { [h .. "/Animal Farm.epub"] = true, [h .. "/Animal Farm (EN-AR).epub"] = true,
            [h .. "/KOReader UI Redesign Concept.pdf"] = true }
        LK.cleanup = function() FM().selected_files = nil end
        FM():showSelectedFilesList()
    end, wait = 2.5 },
    { "gl-collfolders", function()
        LIB.seed()
        GL.coll(true)
        FM().collections:showCollFolderList({ name = GL.COLL, text = GL.COLL })
    end, wait = 2 },
    { "gl-collfolder", function()
        LIB.seed()
        FM().collections:onShowColl(GL.COLL)
        GL.coll(true)
        UIManager:scheduleIn(1, function()
            require("leaf/gapslib").show_folder_sheet(FM().collections, GL.COLL, GL.folders[1])
        end)
    end, wait = 3 },
    { "gl-collstatus", function()
        LIB.seed()
        FM().collections:onShowColl(GL.COLL)
        GL.coll(true)
        UIManager:scheduleIn(1, function()
            FM().collections:showCollFilterStatusDialog({ name = GL.COLL, text = GL.COLL })
        end)
    end, wait = 3 },
    { "gl-metafield", function()
        LIB.seed()
        local bi = FM().bookinfo
        -- an edited title (custom metadata), without writing a sidecar
        bi.custom_doc_settings = { readSetting = function(_s, key)
            if key == "doc_props" then return { title = "Animal Farm", authors = "George Orwell" } end
            return { title = "Animal Farm (EN-AR)" }
        end }
        LK.cleanup = function() FM().bookinfo.custom_doc_settings = nil end
        bi:showCustomDialog(home("Animal Farm (EN-AR).epub"), { title = "Animal Farm (EN-AR)", authors = "George Orwell" }, "title")
    end, wait = 2 },
    { "gl-metacover", function()
        LIB.seed()
        local bi = FM().bookinfo
        bi.custom_book_cover = GL.cover_image()
        LK.cleanup = function() FM().bookinfo.custom_book_cover = nil end
        bi:showCustomDialog(home("Animal Farm.epub"), { title = "Animal Farm" })
    end, wait = 2 },
    { "gl-archive", function() GL.archive() end, wait = 2 },
    { "gl-archmenu", function()
        local av = GL.archive()
        UIManager:scheduleIn(1, function() av:showMenu() end)
    end, wait = 2.5 },
    { "gl-archsub", function() GL.archive("Issue 1/") end, wait = 2 },
    { "gl-archfile", function()
        local av = GL.archive("Issue 1/")
        UIManager:scheduleIn(0.8, function() av:showFileDialog("Issue 1/page-03.jpg") end)
    end, wait = 2.5 },
    { "gl-archextract", function()
        local av = GL.archive()
        UIManager:scheduleIn(0.8, function() av:extractAllDialog() end)
    end, wait = 2.5 },
    { "gl-archimg", function()
        local av = GL.archive("Issue 1/")
        UIManager:scheduleIn(0.8, function() av:viewFile("Issue 1/page-03.jpg") end)
    end, wait = 3 },
    { "gl-opds", function() GL.pse() end, wait = 3 },
    -- end gaps library scenes
    -- system and tools scenes
    { "stats", function()
        local now = os.time()
        local dates = {}
        for i, m in ipairs({ 35, 62, 0, 9, 22, 18, 51 }) do -- today first, as the plugin returns them
            if m > 0 then table.insert(dates, { m * 2, m * 60, os.date("%Y-%m-%d", now - 86400 * (i - 1)) }) end
        end
        show("readerprogress", { dates = dates, current_duration = 1260, current_pages = 14,
            today_duration = 2100, today_pages = 27 })
    end },
    { "calendar", function()
        local month = os.date("%Y-%m")
        local today = tonumber(os.date("%d"))
        local ratios, books = {}, {}
        local mins = { 12, 0, 45, 30, 70, 5, 0, 22, 90, 40, 0, 15, 33, 61, 8, 0, 27, 44, 52, 0, 18, 75, 36, 9, 0, 41, 28, 63 }
        for d = 1, today do
            local m = mins[(d - 1) % #mins + 1]
            if m > 0 then
                local r = {}
                for h = 1, 24 do r[h] = 0 end
                r[21] = math.min(1, m / 60) ; r[22] = math.max(0, (m - 60) / 60)
                local key = string.format("%s-%02d", month, d)
                ratios[key] = r
                books[key] = { { id = d % 3 + 1, title = ({ "Animal Farm", "Dracula", "Walden" })[d % 3 + 1] } }
            end
        end
        local fake = {
            settings = {}, color = false,
            getFirstTimestamp = function() return os.time() - 86400 * 90 end,
            getReadingRatioPerHourByDay = function() return ratios end,
            getReadBookByDay = function() return books end,
        }
        show("calendarview", { reader_statistics = fake, start_day_of_week = 2, nb_book_spans = 2,
            show_hourly_histogram = true, browse_future_months = false })
    end },
    { "search", function()
        G_reader_settings:saveSetting("leaf_search_history", { "Orwell", "Brave", "gothic", "stoic", "Holmes" })
        FM().filesearcher:onShowFileSearch("")
    end },
    { "search-results", function()
        local FS = require("apps/filemanager/filemanagerfilesearcher")
        FS.search_string = "animal"
        FS.search_path = G_reader_settings:readSetting("home_dir")
        require("ui/trapper"):wrap(function() FM().filesearcher:doSearch() end)
    end, wait = 3 },
    { "search-last", function() FM().filesearcher:onShowFileSearch("animal") end },
    { "wifi", function() show("ui/widget/networksetting", { network_list = LEAF_FAKE_NETWORKS() }) end },
    { "wifi-password", function()
        local w = require("ui/widget/networksetting"):new{ network_list = LEAF_FAKE_NETWORKS() }
        UIManager:show(w)
        for _i, it in ipairs(w._leaf_items or {}) do
            if it.info.ssid == "Café Lumière" then it:onAddNetwork() end
        end
    end },
    { "sleep", function()
        G_reader_settings:saveSetting("screensaver_type", "cover")
        G_reader_settings:saveSetting("lastfile", G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub")
        -- through the "Choose sleep screen" entry Leaf adds to KOReader's Sleep screen menu
        local ss = FM().menu.menu_items and FM().menu.menu_items.screensaver
        if ss and ss.sub_item_table[1].callback then ss.sub_item_table[1].callback() else require("leaf/system").show_sleep() end
    end },
    { "sleep-preview", function()
        local p = require("leaf/system").SleepPage:new{}
        UIManager:show(p)
        p:preview()
    end },
    { "about", function()
        -- through KOReader's menu entry (Help › About), which Leaf points at its About card
        local items = FM().menu.menu_items
        if items and items.about then items.about.callback() else require("leaf/system").show_about() end
    end },
    { "quick", function() require("leaf/system").show_quick() end },
    -- polish-ui scenes (menus, dialogs and system)
    { "stats-month", function()
        show("readerprogress", { dates = {}, current_duration = 1260, current_pages = 14,
            today_duration = 2100, today_pages = 27, _leaf_range = "month" })
    end },
    { "input-filled", function()
        local d
        d = require("ui/widget/inputdialog"):new{ title = "Rename", input = "Animal Farm (EN-AR).epub",
            buttons = {{ { text = "Cancel", id = "close", callback = function() UIManager:close(d) end },
                { text = "Rename", is_enter_default = true, callback = noop } }} }
        UIManager:show(d)
        d:onShowKeyboard()
    end },
    -- end polish-ui scenes
    -- end system and tools scenes
    -- gaps-widgets scenes (library side: spinners, date/time, arrange, path chooser, image viewer,
    -- keyboard popups, clipboard, open with, unlock)
    { "gw-spin-items", function()
        local w = require("ui/widget/spinwidget"):new{ title_text = "Items per page", value = 14, value_min = 6,
            value_max = 30, default_value = 14, keep_shown_on_apply = true, callback = noop }
        UIManager:show(w)
        -- the prototype state: moved to 16 (Apply enabled)
        w.value_widget.value = 16
        w.value_widget:update()
    end },
    { "gw-number-err", function()
        local w = require("ui/widget/spinwidget"):new{ title_text = "Items per page", value = 14, value_min = 6,
            value_max = 30, default_value = 14, keep_shown_on_apply = true, callback = noop }
        UIManager:show(w)
        local d = require("leaf/picker").enter_number(w.value_widget)
        d._input_widget:setText("42")
        local row = d.button_table.buttons_layout[#d.button_table.buttons_layout]
        row[#row].callback()
    end, wait = 2 },
    { "gw-spin2-grid", function() show("ui/widget/doublespinwidget", {
        title_text = "Portrait cover grid mode", width_factor = 0.6,
        left_text = "Columns", left_value = 3, left_min = 2, left_max = 4, left_default = 3, left_precision = "%01d",
        right_text = "Rows", right_value = 3, right_min = 2, right_max = 4, right_default = 3, right_precision = "%01d",
        keep_shown_on_apply = true, callback = noop }) end },
    { "gw-spin-listmodes", function() show("ui/widget/spinwidget", {
        title_text = "List modes", value = 7, value_min = 3, value_max = 10, default_value = 7,
        keep_shown_on_apply = true, callback = noop }) end },
    { "gw-dt-daystart", function() show("ui/widget/datetimewidget", {
        hour = 4, min = 0, min_max = 50, min_step = 10, min_hold_step = 30, ok_text = "Set time",
        title_text = "Daily timeline starts at", info_text = "Set the time when the daily timeline should start.",
        callback = noop }) end },
    { "gw-dt-suspend", function() show("ui/widget/datetimewidget", {
        hour = 1, min = 0, hour_max = 23, min_max = 59, hour_hold_step = 5, min_hold_step = 10,
        ok_text = "Set timeout", title_text = "Timeout for autosuspend", info_text = "Enter time in hours and minutes.",
        default_value = "1h 0m", default_callback = noop, extra_text = "Disable", extra_callback = noop,
        callback = noop }) end },
    { "gw-arrange-coll", function() GW.arrange() end },
    { "gw-arrange-sel", function() GW.arrange(3) end },
    { "gw-arrange-menu", function()
        local w = GW.arrange()
        UIManager:scheduleIn(0.3, function() w:onShowWidgetMenu() end)
    end },
    { "gw-arrange-books", function()
        local items = {}
        for _i, t in ipairs({ "Walden", "Crime and Punishment", "Jane Eyre", "Middlemarch", "Little Women", "Siddhartha", "The Odyssey" }) do
            table.insert(items, { text = t })
        end
        -- inside the collection, so the page names it
        local RC = require("readcollection")
        if not RC.coll["To read this winter"] then RC:addCollection("To read this winter") end
        pcall(function() FM().collections:onShowColl("To read this winter") end)
        UIManager:scheduleIn(0.5, function()
            show("ui/widget/sortwidget", { title = "Arrange books in collection", item_table = items, callback = noop })
        end)
    end, wait = 2 },
    { "gw-path-folder", function()
        local root = GW.onboard()
        require("ui/downloadmgr"):new{ onConfirm = noop }:chooseDir(root .. "/Downloads")
    end },
    { "gw-path-file", function()
        local root = GW.onboard()
        LIB.seed()
        FM().bookinfo:setCustomCover(G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub")
        local top = UIManager._window_stack[#UIManager._window_stack].widget
        if top.changeToPath then top:changeToPath(root .. "/Pictures/Covers") end
    end },
    { "gw-path-confirm", function()
        local root = GW.onboard()
        local pc = require("ui/widget/pathchooser"):new{ select_directory = false, path = root .. "/Pictures/Covers",
            file_filter = function(f) return require("document/documentregistry"):isImageFile(f) end, onConfirm = noop }
        UIManager:show(pc)
        pc:onMenuHold({ path = root .. "/Pictures/Covers/animal-farm-1945.jpg" })
    end },
    { "gw-iv-cover", function()
        LIB.seed()
        FM().bookinfo:onShowBookCover(G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub")
    end, wait = 2 },
    { "gw-iv-rot", function()
        LIB.seed()
        FM().bookinfo:onShowBookCover(G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub")
        local top = UIManager._window_stack[#UIManager._window_stack].widget
        top.rotated = true
        top.scale_factor, top._scale_to_fit = 1, false
        top:update()
    end, wait = 2 },
    { "gw-keypopup", function() GW.hold_key("Rename collection", "Café readi", "e") end, wait = 2 },
    { "gw-kblayouts", function()
        G_reader_settings:saveSetting("keyboard_layouts", { "en", "ar", "fr" })
        G_reader_settings:saveSetting("keyboard_layout_default", "en")
        GW.hold_key("Search", "", "🌐")
    end, wait = 2 },
    { "gw-clipboard", function()
        local it = GW.note_field()
        UIManager:scheduleIn(0.4, function() it:holdTextBox() end)
    end, wait = 2 },
    { "gw-snippets", function()
        local it = GW.note_field()
        UIManager:scheduleIn(0.4, function() it:showClipboardSnippets() end)
    end, wait = 2 },
    { "gw-snippet-edit", function()
        local it = GW.note_field()
        UIManager:scheduleIn(0.4, function() it:editClipboardSnippet(3) end)
    end, wait = 2 },
    { "gw-openwith", function()
        LIB.seed()
        FM():showOpenWithDialog(G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub")
    end },
    { "gw-openwith-confirm", function()
        LIB.seed()
        FM():showOpenWithDialog(G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub")
        local d = UIManager._window_stack[#UIManager._window_stack].widget
        for _i, row in ipairs(d.radio_button_table.radio_buttons_layout) do
            for _j, b in ipairs(row) do
                if b.provider and b.provider.provider == "mupdf" then d.radio_button_table:checkButton(b) end
            end
        end
        d._check_global_button:toggleCheck()
        if d._leaf_open then d._leaf_open() end
    end },
    { "gw-unlock", function() LIB.seed() GW.unlock(true) end, wait = 2 },
    { "gw-unlock-tap", function() LIB.seed() GW.unlock(false) end, wait = 2 },
    -- end gaps-widgets scenes
    -- reader scenes replace the file manager: keep them last
    -- every EPUB reader scene runs on the bilingual Animal Farm (book = "epub": opened first if needed)
    { "reader", function()
        open_book(EPUB_BOOK)
        UIManager:scheduleIn(2.5, function() chapter_one(3) seed_bookmarks() end)
    end, keep = true, wait = 5, book = "epub" },
    { "readermenu", function() RUI().menu:onShowMenu() end },
    { "readerconfig", function() RUI().config:onShowConfigMenu() end },
    { "readerconfig-text", function()
        RUI().config:onShowConfigMenu()
        local d = RUI().config.config_dialog
        if d then
            for i, o in ipairs(d.config_options) do
                if o.icon == "appbar.textsize" or o.leaf_key == "text" then d:handleEvent(require("ui/event"):new("ShowConfigPanel", i)) end
            end
        end
    end },
    { "toc", function() RUI().toc:onShowToc() end },
    { "chrome", function()
        local ok, chrome = pcall(require, "leaf/reader_chrome")
        if ok and chrome.show then chrome.show(RUI()) end
    end },
    { "bookmarks", function() seed_bookmarks() RUI().bookmark:onShowBookmark() end },
    -- kvpages scenes (reader): the paragraph-translate patch panel, on the EN-AR edition (opens it: keep last)
    { "translate", function()
        local opened = open_book(EPUB_BOOK)
        UIManager:scheduleIn(opened and 4 or 0.5, function()
            local ui = RUI()
            ui:handleEvent(require("ui/event"):new("GotoPage", 12))
            local RH = require("apps/reader/modules/readerhighlight")
            local function up(fn, want)
                local i = 1
                while true do
                    local n, v = debug.getupvalue(fn, i)
                    if not n then return end
                    if n == want then return v end
                    i = i + 1
                end
            end
            local Panel = up(RH.lookupDictWord, "Panel")
            local block_xp = up(RH.lookupDictWord, "block_xpointer")
            local neighbor = Panel and up(Panel.build, "neighbor")
            if not (Panel and block_xp) then logger.info("autoshot: no translate patch") return end
            local doc = ui.document
            local block = block_xp(doc:getXPointer())
            local para = doc:getTextFromXPointer(block) or ""
            if not para:find("%a%a%a%a") and neighbor then block, para = neighbor(doc, block, 1) end
            if block then UIManager:show(Panel:new{ ui = ui, doc = doc, block = block, para = para, word = "farm" }) end
        end)
    end, wait = 7 },

    -- lookup scenes (leaf/lookup.lua): the bilingual Animal Farm, Chapter I, a selection mid-page
    { "lk-open", function()
        local function chapter_one()
            local ui = RUI()
            for _, t in ipairs(ui.toc.toc or {}) do
                if t.title:find("Chapter I", 1, true) then ui.rolling:onGotoXPointer(t.xpointer) break end
            end
        end
        UIManager:scheduleIn(open_book(EPUB_BOOK) and 3 or 0.2, chapter_one)
    end, keep = true, wait = 5 },
    { "lk-hl-popup", function() LK.select(0.30, 0.34) RUI().highlight:onShowHighlightMenu() end },
    { "lk-hl-popup-low", function() LK.select(0.80, 0.82) RUI().highlight:onShowHighlightMenu() end },
    { "lk-hl-edit", function()
        local hl = RUI().highlight
        LK.select(0.42, 0.44)
        local index = hl:saveHighlight()
        hl:clear()
        local item = RUI().annotation.annotations[index]
        item.note = "Irony starts here: the animals' dream, before the pigs."
        item.drawer = "underscore"
        UIManager:setDirty(RUI().dialog, "ui")
        hl:showHighlightNoteOrDialog(index)
        LK.cleanup = function() hl:deleteHighlight(RUI().annotation:getItemIndex(item) or index) end
    end },
    { "lk-dict", function()
        local ui = RUI()
        local hl = ui.highlight
        LK.select(0.30, 0.30, true)
        ui.dictionary.highlight = hl
        ui.dictionary:showDict("answered", {
            { dict = "Oxford Dictionary of English", word = "answered", definition =
                "answer (verb)\n1. Say or write something to deal with or as a reaction to someone or something.\n   “he answered without hesitation”\n2. Act in reaction to a signal, such as a doorbell or telephone.\n   “she answered the phone”\n3. Be responsible or report to.\n   “he answers to the board”" },
            { dict = "Wiktionary EN→AR (offline)", word = "answered", definition = "أجاب، ردّ\n(verb) past of answer" },
            { dict = "WordNet 3.1", word = "answered", definition = "(v) answer: react verbally\n(v) answer: give the correct answer or solution to\n(v) answer: be liable or accountable" },
            { dict = "Al-Mawrid Mini", word = "answer", definition = "جواب، ردّ؛ أجاب" },
        }, LK.word_boxes())
    end },
    { "lk-dict-empty", function()
        local ui = RUI()
        LK.select(0.30, 0.30, true)
        ui.dictionary:onLookupWord("answered", false, LK.word_boxes(), ui.highlight)
    end, wait = 3 },
    { "lk-wiki", function()
        local ui = RUI()
        ui.wikipedia:initLanguages("Animal Farm")
        ui.wikipedia.wiki_languages = { "en", "ar", "fr" }
        ui.wikipedia:showDict("Animal Farm", {
            { dict = "Wikipedia EN", word = "Animal Farm", lang = "en", definition =
                "Animal Farm (originally Animal Farm: A Fairy Story) is a satirical allegorical novella, in the form of a beast fable, by George Orwell, first published in England on 17 August 1945. It tells the story of a group of anthropomorphic farm animals who rebel against their human farmer, hoping to create a society where the animals can be equal, free, and happy. Ultimately, the rebellion is betrayed, and under the dictatorship of a pig named Napoleon, the farm ends up in a state as bad as it was before.\n(full article : 64 kB, = 9 x this intro length)" },
        })
    end },
    { "lk-translate", function()
        local hl = RUI().highlight
        LK.select(0.30, 0.30, true)
        hl:lookupDictWord()
    end },
    -- the popup's Translate (KOReader's online Translator), with a canned answer (no network in the sandbox)
    { "lk-translator", function()
        local Tr = require("ui/translator")
        local load = Tr.loadPage
        Tr.loadPage = function() return { { { "كان السيد جونز، صاحب مزرعة مانور، قد أقفل أبواب أكواخ الدجاج لليلة، لكنه كان أسكر من أن يتذكّر إغلاق الفتحات الصغيرة.",
            "Mr. Jones, of the Manor Farm, had locked the hen-houses for the night, but was too drunk to remember to shut the pop-holes." } }, nil, "en" } end
        LK.select(0.42, 0.46)
        require("ui/trapper"):wrap(function()
            Tr:_showTranslation(RUI().highlight.selected_text.text, false, "en", "ar", true)
            Tr.loadPage = load
        end)
    end, wait = 3 },
    { "lk-footnote", function()
        local ui = RUI()
        local FootnoteWidget = require("ui/widget/footnotewidget")
        local popup
        popup = FootnoteWidget:new{
            html = "<p><sup>1</sup> Middle White: a breed of pig. Old Major, the prize boar, was exhibited under the name of Willingdon Beauty, a show name that the farm still remembered with some pride.</p>",
            doc_font_name = ui.font.font_face,
            doc_font_size = Screen:scaleBySize(ui.document.configurable.font_size),
            doc_margins = ui.document:getPageMargins(),
            follow_callback = function() UIManager:close(popup) end,
            dialog = ui,
        }
        UIManager:show(popup)
    end },
    -- system and tools reader scenes
    { "search-book", function()
        G_reader_settings:saveSetting("leaf_fulltext_history", { "silence", "windmill", "Napoleon" })
        RUI().search:onShowFulltextSearchInput("silence")
    end },
    { "search-book-results", function()
        local s = RUI().search
        s.last_search_text = "silence"
        s.case_insensitive = true
        require("ui/trapper"):wrap(function() s:findAllText("silence") end)
    end, wait = 3 },
    -- end system and tools reader scenes
    -- reader extras scenes (frontlight, go to, skim, book map, page browser, book end, page header)
    { "reader-page", function()
        -- a text page inside Chapter I, so the page header has a chapter to show
        chapter_one(3)
        seed_bookmarks()
    end, keep = true, wait = 2 },
    { "frontlight", function()
        -- desktop has no frontlight: pretend the device has one with warmth while the sheet is up
        local Device = require("device")
        local has_fl, has_nl = Device.hasFrontlight, Device.hasNaturalLight
        Device.hasFrontlight = function() return true end
        Device.hasNaturalLight = function() return true end
        local powerd = Device:getPowerDevice()
        powerd:setIntensity(62)
        powerd:setWarmth(35)
        local ok, err = pcall(function() Device:showLightDialog() end)
        Device.hasFrontlight, Device.hasNaturalLight = has_fl, has_nl
        if not ok then error(err) end
    end },
    { "frontlight-stock", function()
        local Device = require("device")
        local has_nl = Device.hasNaturalLight
        Device.hasNaturalLight = function() return true end
        local ok, err = pcall(function() UIManager:show(require("ui/widget/frontlightwidget"):new{}) end)
        Device.hasNaturalLight = has_nl
        if not ok then error(err) end
    end },
    { "goto", function() RUI().gotopage:onShowGotoDialog() end },
    { "goto-typed", function()
        RUI().gotopage:onShowGotoDialog()
        local w = UIManager._window_stack[#UIManager._window_stack].widget
        if w.leaf_key then for _, k in ipairs({ "4", "0" }) do w:leaf_key(k) end end
    end },
    { "skim", function() seed_bookmarks() RUI().gotopage:onShowSkimtoDialog() end },
    { "skim-moved", function()
        RUI().gotopage:onShowSkimtoDialog()
        local w = UIManager._window_stack[#UIManager._window_stack].widget
        if w.goToPage then w:goToPage(w.curr_page + 10) end
    end },
    { "bookmap", function() seed_bookmarks() RUI().thumbnail:onShowBookMap() end, wait = 3 },
    { "bookmap-overview", function() RUI().thumbnail:onShowBookMap(true) end, wait = 3 },
    { "pagebrowser", function() seed_bookmarks() RUI().thumbnail:onShowPageBrowser() end, wait = 5 },
    { "bookend", function() RUI().status:onEndOfBook() end, wait = 2 },
    -- typeset scenes (EPUB: every tab; then the PDF panel, which replaces the reader: keep it last)
    { "ts-presets", function() ts_open("presets") end },
    { "ts-text", function() ts_open("text") end },
    { "ts-text-help", function() ts_open("text", function(d) d._leaf_help = "word_spacing"; d:update() end) end },
    { "ts-font", function() ts_open("font") end },
    { "ts-margins", function() ts_open("margins") end },
    { "ts-page", function() ts_open("page") end },
    { "ts-layout", function() ts_open("layout") end },
    { "ts-contrast", function() ts_open("contrast") end },
    { "ts-style", function() ts_open("style") end },
    { "ts-style-scrolled", function() ts_open("style", function(d)
        local sc = d._leaf_scroll
        if sc then sc:initState(); if sc._is_scrollable then sc:_scrollBy(0, sc._max_scroll_offset_y) end end
    end) end },
    { "ts-slider-change", function() ts_open("text", function(d)
        -- moves the line spacing slider in code (as a tap at 80% would): exercises the choose/update path
        local o = d:findOptionByName("line_spacing")
        if not o then return end
        local before = d.configurable.line_spacing
        d:onConfigChoose(o.values, o.name, o.event, o.args, math.floor(#o.values * 0.8), o.hide_on_apply)
        -- put the book back once the shot is taken (doc settings persist across runs)
        local ui = RUI()
        UIManager:scheduleIn(2, function()
            ui.document.configurable.line_spacing = before
            ui:handleEvent(require("ui/event"):new("SetLineSpace", before))
        end)
    end) end },
    -- gaps-widgets reader scenes (spinners, timers and status bar items opened from the reader)
    { "gw-spin-battery", function() show("ui/widget/spinwidget", {
        value = 30, value_min = 0, value_max = 100, default_value = 100, unit = "%", value_hold_step = 10,
        title_text = "Minimum threshold to hide battery item", callback = noop,
        extra_text = "Disable", extra_callback = noop, ok_always_enabled = true }) end, book = "epub" },
    { "gw-spin-cpp", function() show("ui/widget/spinwidget", {
        title_text = "Characters per page", value = 1818, value_min = 500, value_max = 3000, value_hold_step = 20,
        default_value = 1818, ok_always_enabled = true, keep_shown_on_apply = true, callback = noop,
        extra_text = "Use publisher page numbers", extra_callback = noop }) end, book = "epub" },
    { "gw-spin2-battery", function() show("ui/widget/doublespinwidget", {
        title_text = "Battery level alert thresholds",
        info_text = "Low level threshold is checked when the device is not charging.\nHigh level threshold is checked when the device is charging.",
        left_text = "Low", left_value = 20, left_min = 1, left_max = 90, left_default = 20, left_hold_step = 5,
        right_text = "High", right_value = 90, right_min = 20, right_max = 100, right_default = 100, right_hold_step = 5,
        unit = "%", callback = noop }) end, book = "epub" },
    { "gw-spin2-hyph", function() show("ui/widget/doublespinwidget", {
        left_value = 2, left_min = 1, left_max = 10, right_value = 3, right_min = 1, right_max = 10,
        left_default = 2, right_default = 2, width_factor = 0.6, default_text = "Language defaults: 2 / 2",
        title_text = "Hyphenation limits", info_text = "Set minimum length before hyphenation occurs.",
        keep_shown_on_apply = true, callback = noop }) end, book = "epub" },
    { "gw-dt-alarm", function() GW.timer("alarm") end, book = "epub" },
    { "gw-dt-interval", function() GW.timer("interval") end, book = "epub" },
    { "gw-arrange-footer", function()
        local footer = RUI().view.footer
        local items = {}
        for i, m in ipairs(footer.mode_index) do
            items[i] = { text = footer:textOptionTitles(m), label = m, dim = not footer.settings[m] }
        end
        show("ui/widget/sortwidget", { title = "Arrange items", item_table = items, callback = noop })
    end, book = "epub" },
    -- end gaps-widgets reader scenes
    -- gaps-lists scenes (leaf/readerlists.lua: bookmark actions / details / select, search bar, pinned page,
    -- book map and page browser options, page actions, dictionary menus)
    { "gp-bm-actions", function() GL.marks() require("leaf/readerlists").show_actions(RUI(), GL.item(false)) end, book = "epub" },
    { "gp-bm-hl-actions", function() GL.marks() require("leaf/readerlists").show_actions(RUI(), GL.item(true)) end, book = "epub" },
    { "gp-bm-view", function() GL.marks() RUI().bookmark:showBookmarkDetails(2) end, book = "epub" },
    { "gp-bm-select", function() GL.marks() require("leaf/readerlists").show_select(RUI(), { [1] = true, [3] = true, [4] = true }) end, book = "epub" },
    { "gp-search-result", function()
        local s = RUI().search
        s.last_search_text = "windmill"
        s.case_insensitive = true
        require("ui/trapper"):wrap(function() s:findAllText("windmill") end)
        UIManager:scheduleIn(2, function()
            GL.close_to_reader()
            s:gotoResultsItem(3)
        end)
    end, wait = 4, book = "epub" },
    { "gp-search-bar", function()
        chapter_one(3)
        local s = RUI().search
        s.last_search_text = "windmill"
        s:onShowSearchDialog("windmill", 0, s.current_search_type, true)
    end, wait = 2, book = "epub" },
    { "gp-search-wait", function() chapter_one(3) UIManager:show(require("leaf/readerlists").wait_pill("windmill")) end, book = "epub" },
    { "gp-goto-pin", function()
        local ui = RUI()
        ui.doc_settings:saveSetting("pinned_page", ui.document:getPageXPointer(42))
        ui.gotopage:onShowGotoDialog()
    end, book = "epub" },
    { "gp-goto-unpin", function()
        -- the pin-off button's confirm, over the Go to sheet
        RUI().gotopage:onShowGotoDialog()
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = "Remove the pinned page?\nPage 42 stays as it is; only the pin is removed.", ok_text = "Remove", ok_callback = noop })
    end, book = "epub" },
    { "gp-bookmap-menu", function()
        RUI().thumbnail:onShowBookMap()
        UIManager:scheduleIn(1.5, function() require("leaf/readerlists").show_map_options(RUI()) end)
    end, wait = 4, book = "epub" },
    { "gp-pb-menu", function()
        RUI().thumbnail:onShowPageBrowser()
        UIManager:scheduleIn(2, function() require("leaf/readerlists").show_pages_options(RUI()) end)
    end, wait = 5, book = "epub" },
    { "gp-pb-hold", function()
        local ui = RUI()
        ui.thumbnail:onShowPageBrowser()
        UIManager:scheduleIn(2, function() require("leaf/readerlists").show_page_hold(ui, ui:getCurrentPage() + 1) end)
    end, wait = 5, book = "epub" },
    { "gp-dict-results", function()
        GL.dict()
        UIManager:scheduleIn(0.6, function() GL.top():onShowResultsMenu() end)
    end, wait = 2, book = "epub" },
    { "gp-dict-lookup", function()
        GL.dict()
        UIManager:scheduleIn(0.6, function() GL.top():onLookupInputWord("silence") end)
    end, wait = 2, book = "epub" },
    { "gp-dict-wikilang", function()
        local ui = RUI()
        ui.wikipedia:initLanguages("Animal Farm")
        ui.wikipedia.wiki_languages = { "en", "ar", "fr", "de" }
        ui.wikipedia:showDict("Animal Farm", {
            { dict = "Wikipedia EN", word = "Animal Farm", lang = "en", definition =
                "Animal Farm (originally Animal Farm: A Fairy Story) is a satirical allegorical novella, in the form of a beast fable, by George Orwell, first published in England on 17 August 1945. It tells the story of a group of anthropomorphic farm animals who rebel against their human farmer, hoping to create a society where the animals can be equal, free, and happy." },
        })
        UIManager:scheduleIn(0.6, function() require("leaf/readerlists").wiki_lang_menu(GL.top()) end)
    end, wait = 2, book = "epub" },
    -- end gaps-lists scenes
    -- gaps-lists stats scenes (leaf/statpages.lua: the statistics plugin's pages, seeded database)
    { "gp-stats-book", function() STATS.seed():onShowBookStats() end, wait = 2, book = "epub" },
    { "gp-stats-cal", function() STATS.seed():onShowCalendarView() end, wait = 2, book = "epub" },
    { "gp-stats-cal-set", function()
        STATS.seed():onShowCalendarView()
        require("leaf/statpages").calendar_settings(UIManager._window_stack[#UIManager._window_stack].widget)
    end, wait = 2, book = "epub" },
    { "gp-stats-day", function() STATS.seed():onShowCalendarDayView() end, wait = 2, book = "epub" },
    { "gp-stats-range", function() STATS.seed():onShowTimeRange() end, wait = 2, book = "epub" },
    { "gp-stats-week", function() STATS.seed():onShowTimeRange() STATS.tap("Last week") end, wait = 2, book = "epub" },
    { "gp-stats-months", function() STATS.seed():onShowTimeRange() STATS.tap("Books by month") end, wait = 2, book = "epub" },
    { "gp-stats-in", function()
        STATS.seed():onShowTimeRange()
        STATS.tap("Books by month")
        STATS.tap(nil, 1)
    end, wait = 2, book = "epub" },
    { "gp-stats-days", function() STATS.seed():onShowBookStats() STATS.tap("Days reading this book") end, wait = 2, book = "epub" },
    { "gp-stats-books", function() STATS.seed():onShowTimeRange() STATS.tap("All books") end, wait = 2, book = "epub" },
    { "gp-stats-reset", function() STATS.seed():resetPerBook() end, wait = 2, book = "epub" },
    -- end gaps-lists stats scenes
    -- PDF scenes: replace the EPUB with the PDF, so they run last (reader + typeset tabs)
    { "reader-pdf", function() open_book(PDF_BOOK) end, keep = true, wait = 4, book = "pdf" },
    { "chrome-pdf", function()
        local ok, chrome = pcall(require, "leaf/reader_chrome")
        if ok and chrome.show then chrome.show(RUI()) end
    end, book = "pdf" },
    { "ts-pdf-rotate", function() ts_open("rotate") end },
    { "ts-pdf-crop", function() ts_open("crop") end },
    { "ts-pdf-zoom", function() ts_open("zoom") end },
    { "ts-pdf-page", function() ts_open("page") end },
    { "ts-pdf-reflow", function() ts_open("reflow") end },
    { "ts-pdf-contrast", function() ts_open("contrast") end },
    { "ts-pdf-doc", function() ts_open("doc") end },
}

-- lookup scenes: helpers
-- select the text between two heights of the page (fractions), like a long-press + drag
function LK.select(y0, y1, word)
    local ui = RUI()
    local hl = ui.highlight
    local W, H = Screen:getWidth(), Screen:getHeight()
    local p0 = { x = math.floor(W * (word and 0.45 or 0.12)), y = math.floor(H * y0) }
    local p1 = { x = math.floor(W * (word and 0.45 or 0.72)), y = math.floor(H * y1) }
    hl:clear()
    hl.hold_pos = ui.view:screenToPageTransform(p0)
    if word then
        local w = ui.document:getWordFromPosition(p0, true)
        hl.selected_text = { text = w.word, pos0 = w.pos0, pos1 = w.pos1, sboxes = { w.sbox } }
    else
        hl.selected_text = ui.document:getTextFromPositions(p0, p1)
    end
    ui.view.highlight.temp[hl.hold_pos.page] = hl.selected_text.sboxes
    UIManager:setDirty(ui.dialog, "ui")
end
function LK.word_boxes() return RUI().highlight.selected_text.sboxes end


-- library scenes: helpers
-- PT's display mode for every list (grid / detail / list), without the file manager rebuild of setView
function LIB.view(key)
    local lib = require("leaf/library")
    if lib.currentView() ~= key then lib.setView(key) end
end
-- sandbox data like a device in use (idempotent): sidecars (status, progress, rating, highlights),
-- history with times, favorites + collections, the statistics database, PT's book cache
function LIB.seed()
    if LIB.seeded then return end
    LIB.seeded = true
    local home = G_reader_settings:readSetting("home_dir")
    if not home then return end
    local DocSettings = require("docsettings")
    local BookList = require("ui/widget/booklist")
    local now = os.time()
    local function at(days_ago, h, m)
        local d = os.date("*t", now - days_ago * 86400)
        d.hour, d.min, d.sec = h, m, 0
        return math.min(now - 60, os.time(d))
    end
    local books = {
        { f = "/Animal Farm.epub", pct = 0.08, status = "reading", pages = 112, last = at(0, 21, 10),
          hl = { { "All animals are equal, but some animals are more equal than others.", "The whole book in one line.", "Chapter X", 102 },
                 { "Man is the only creature that consumes without producing.", nil, "Chapter I", 9 } } },
        { f = "/Animal Farm (EN-AR).epub", pct = 1, status = "complete", rating = 5, pages = 140, last = at(2, 22, 30) },
    }
    for _i, b in ipairs(books) do
        local file = home .. b.f
        local ds = DocSettings:open(file)
        ds:saveSetting("percent_finished", b.pct)
        ds:saveSetting("doc_pages", b.pages)
        ds:saveSetting("last_page", math.max(1, math.floor(b.pages * b.pct + 0.5)))
        ds:saveSetting("summary", { status = b.status, rating = b.rating, modified = os.date("%Y-%m-%d", b.last) })
        ds:saveSetting("partial_md5_checksum", require("util").partialMD5(file))
        if b.hl then
            local ann = {}
            for _j, h in ipairs(b.hl) do
                table.insert(ann, { text = h[1], note = h[2], chapter = h[3], pageno = h[4], page = h[4],
                    datetime = os.date("%Y-%m-%d %H:%M:%S", b.last - 3600 * _j), drawer = "lighten", color = "yellow" })
            end
            ds:saveSetting("annotations", ann)
            ds:saveSetting("bookmarks_sorted_20220106", true)
        end
        ds:flush()
        BookList.resetBookInfoCache(file)
    end
    -- history: today, this week, and a deleted file from earlier
    local RH = require("readhistory")
    local gone = home .. "/Brave New World.epub" -- in the history, then deleted
    local fh = io.open(gone, "w")
    if fh then fh:close() end
    RH:addItem(gone, now - 16 * 86400, true)
    os.remove(gone)
    for _j, v in ipairs(RH.hist) do if v.file == gone then v.dim = true end end
    RH:addItem(home .. "/Animal Farm (EN-AR).epub", books[2].last, true)
    RH:addItem(home .. "/Animal Farm.epub", books[1].last)
    -- favorites + two collections
    local RC = require("readcollection")
    local fav = RC.default_collection_name
    local function add(f, coll)
        if not RC.coll[coll] then RC:addCollection(coll) end
        if not RC:isFileInCollection(home .. f, coll) then RC:addItem(home .. f, coll) end
    end
    add("/Animal Farm.epub", fav)
    add("/Animal Farm (EN-AR).epub", "Arabic")
    add("/Animal Farm (EN-AR).epub", "To read this winter")
    add("/KOReader UI Redesign Concept.pdf", "To read this winter")
    add("/Animal Farm.epub", "To read this winter")
    RC:write()
    -- a folder shortcut (the Folders tab's chips)
    local shortcuts = G_reader_settings:readSetting("folder_shortcuts", {})
    shortcuts[home .. "/Folder A"] = shortcuts[home .. "/Folder A"] or { time = now }
    -- statistics: 7 days of reading on Animal Farm (home: today, streak, pages/h)
    pcall(function()
        local path = require("datastorage"):getSettingsDir() .. "/statistics.sqlite3"
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(path)
        conn:exec([[CREATE TABLE IF NOT EXISTS book (id integer PRIMARY KEY autoincrement, title text, authors text,
            notes integer, last_open integer, highlights integer, pages integer, series text, language text, md5 text,
            total_read_time integer, total_read_pages integer);
            CREATE TABLE IF NOT EXISTS page_stat_data (id_book integer, page integer NOT NULL DEFAULT 0,
            start_time integer NOT NULL DEFAULT 0, duration integer NOT NULL DEFAULT 0, total_pages integer NOT NULL DEFAULT 0,
            UNIQUE (id_book, page, start_time));]])
        local n = tonumber(conn:rowexec("SELECT count(*) FROM page_stat_data;")) or 0
        if n == 0 then
            local md5 = require("util").partialMD5(home .. "/Animal Farm.epub")
            conn:exec(string.format([[INSERT INTO book (title, authors, notes, last_open, highlights, pages, series, language, md5,
                total_read_time, total_read_pages) VALUES ('Animal Farm', 'George Orwell', 1, %d, 2, 112, '', 'en', '%s', 9000, 140);]],
                now, md5))
            local id = tonumber(conn:rowexec("SELECT max(id) FROM book;"))
            local mins = { 35, 62, 9, 28, 22, 51, 40, 18, 30, 26, 44, 33 } -- today first
            local page = 1
            for d, m in ipairs(mins) do
                local t0 = at(d - 1, 20, 0)
                for k = 0, math.floor(m * 60 / 78) - 1 do
                    conn:exec(string.format("INSERT OR IGNORE INTO page_stat_data VALUES (%d, %d, %d, 78, 112);",
                        id, page % 112 + 1, t0 + k * 78))
                    page = page + 1
                end
            end
        end
        conn:close()
    end)
    -- PT's book cache (titles, covers) for the Library tab: extract now, in the background
    local BIM = package.loaded["bookinfomanager"]
    if BIM then
        local files = {}
        local lfs = require("libs/libkoreader-lfs")
        for f in lfs.dir(home) do
            if f:match("%.epub$") or f:match("%.pdf$") then
                table.insert(files, { filepath = home .. "/" .. f, cover_specs = { max_cover_w = 600, max_cover_h = 900 } })
            end
        end
        BIM:extractInBackground(files)
        UIManager:scheduleIn(2.5, function()
            local fm = FM()
            if fm then fm:onRefresh() end
        end)
    end
end

-- gaps library scenes: helpers
GL.COLL = "To read this winter"
-- connected folders + "only add" filters on a collection, in memory only (undone after the shot)
function GL.coll(on)
    local RC = require("readcollection")
    local cs = RC.coll_settings[GL.COLL]
    if not cs then return end
    local root = G_reader_settings:readSetting("home_dir"):gsub("/[^/]+$", "")
    GL.folders = { root .. "/Books/Classics", root .. "/Downloads", root .. "/Books/Philosophy" }
    cs.folders = { [GL.folders[1]] = { subfolders = true }, [GL.folders[2]] = { scan_on_show = true },
        [GL.folders[3]] = { subfolders = true, scan_on_show = true } }
    cs.filter = cs.filter or {}
    cs.filter.add = { filetype = "epub, pdf", status = { new = true, reading = true } }
    LK.cleanup = function()
        cs.folders = nil
        cs.filter.add = nil
    end
end
-- a comic-like page (panels) as JPEG bytes
function GL.page_jpeg(seed)
    local Blitbuffer = require("ffi/blitbuffer")
    local w, h = 600, 850
    local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    local ink = Blitbuffer.COLOR_BLACK
    local panels = { { 30, 30, 540, 250 }, { 30, 300, 260, 250 }, { 310, 300, 260, 250 }, { 30, 570, 540, 250 } }
    for i, p in ipairs(panels) do
        bb:paintBorder(p[1], p[2], p[3], p[4], 4, ink)
        local k = (i + (seed or 0)) % 3
        bb:paintRect(p[1] + 40, p[2] + 60 + k * 30, p[3] - 80, 6, Blitbuffer.COLOR_GRAY_9)
        bb:paintRect(p[1] + 40, p[2] + 110 + k * 20, math.floor((p[3] - 80) * 0.6), 6, Blitbuffer.COLOR_GRAY_9)
    end
    local tmp = os.tmpname()
    bb:writeJPG(tmp, 80)
    bb:free()
    local f = io.open(tmp, "rb")
    local data = f and f:read("*a")
    if f then f:close() end
    os.remove(tmp)
    return data
end
-- the archive: <sandbox>/Downloads/comics-pack.zip (two issues, a cover, a readme), opened in the viewer
function GL.archive(sub)
    local root = G_reader_settings:readSetting("home_dir"):gsub("/[^/]+$", "")
    local dir = root .. "/Downloads"
    local zip = dir .. "/comics-pack.zip"
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(zip, "mode") then
        lfs.mkdir(dir)
        local W = require("ffi/archiver").Writer:new()
        if W:open(zip, "zip") then
            W:setZipCompression("store")
            for i = 1, 9 do W:addFileFromMemory(string.format("Issue 1/page-%02d.jpg", i), GL.page_jpeg(i)) end
            for i = 1, 8 do W:addFileFromMemory(string.format("Issue 2/page-%02d.jpg", i), GL.page_jpeg(i + 1)) end
            W:addFileFromMemory("cover.jpg", GL.page_jpeg(0))
            W:addFileFromMemory("readme.txt", "Comics pack: two issues of The Long Field.\n")
            W:close()
        end
    end
    local av = FM().archiveviewer
    av:openFile(zip)
    if sub and av.booklist then
        av.booklist.path = sub
        av.booklist:rebuild()
    end
    return av
end
-- a custom cover image (the book's own cover, saved as a JPEG next to the sandbox)
function GL.cover_image()
    local path = require("datastorage"):getDataDir() .. "/animal-farm-1945.jpg"
    if not require("libs/libkoreader-lfs").attributes(path, "mode") then
        local bb = FM().bookinfo:getCoverImage(nil, home("Animal Farm.epub"), true)
        if bb then
            bb:writeJPG(path, 85)
            bb:free()
        end
    end
    return path
end
-- OPDS page stream: Kavita-like publication, HTTP stubbed with a local page image
function GL.pse()
    local http = require("socket.http")
    local real = http.request
    local data = GL.page_jpeg(2)
    http.request = function(req)
        if type(req) == "table" and req.sink then req.sink(data) end
        return 1, 200, {}, "HTTP/1.1 200 OK"
    end
    LK.cleanup = function() http.request = real end
    require("leaf/gapslib").pse_context("The Long Field · Issue 3", "Kavita")
    require("opdspse"):streamPages("http://leaf.invalid/opds/key/image?page={pageNumber}", 48, false, nil, nil, 12)
end

-- gaps-lists scenes: helpers
-- bookmarks (seed_bookmarks) + three highlights, one with a note (once)
function GL.marks()
    seed_bookmarks()
    local ui = RUI()
    if ui._leaf_gl_marks then return end
    ui._leaf_gl_marks = true
    chapter_one(1)
    local hl = ui.highlight
    for i, y in ipairs({ 0.30, 0.52, 0.70 }) do
        LK.select(y, y + 0.02)
        local index = hl:saveHighlight()
        hl:clear()
        local item = index and ui.annotation.annotations[index]
        if item and i == 2 then item.note = "Old Major's dream" end
    end
    chapter_one(3)
end
-- the first bookmark (false) or highlight (true)
function GL.item(highlight)
    for _i, a in ipairs(RUI().annotation.annotations) do
        if (a.drawer ~= nil) == highlight then return a end
    end
end
function GL.top() return UIManager._window_stack[#UIManager._window_stack].widget end
-- close everything above the reader
function GL.close_to_reader()
    local stack = UIManager._window_stack
    while #stack > 0 and stack[#stack].widget ~= RUI() do UIManager:close(stack[#stack].widget) end
end
-- the dictionary popup on "silence"
function GL.dict()
    local ui = RUI()
    LK.select(0.30, 0.30, true)
    ui.dictionary.highlight = ui.highlight
    ui.dictionary:showDict("silence", {
        { dict = "Oxford Dictionary of English", word = "silence", definition = "silence (noun)\n1. Complete absence of sound.\n   “the silence of the night”\n2. The fact of abstaining from speech.\n   “she lapsed into silence”" },
        { dict = "Wiktionary EN→AR (offline)", word = "سكوت", definition = "سكوت، صمت" },
        { dict = "WordNet 3.1", word = "silences", definition = "(n) silence: the absence of sound" },
        { dict = "Al-Mawrid Mini", word = "سكوت", definition = "سكوت؛ صمت" },
    }, LK.word_boxes())
end

-- gaps-lists stats scenes: helpers
-- the reader's statistics with a realistic database (idempotent): the open book for the last week
-- (one day without any reading), several other books this month, earlier books in past months
function STATS.seed()
    local ui = RUI()
    local st = ui and ui.statistics
    if not st then error("no statistics plugin") end
    if STATS.seeded then return st end
    STATS.seeded = true
    -- calendar settings as the prototype shows them
    st.settings.calendar_nb_book_spans = 2
    st.settings.calendar_show_histogram = true
    st.settings.calendar_browse_future_months = false
    st.settings.calendar_start_day_of_week = 2
    st.settings.calendar_day_start_hour = 4
    st.settings.calendar_day_start_minute = 0
    st.settings.calendar_use_day_time_shift = true
    pcall(function() st:insertDB() end)
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(require("datastorage"):getSettingsDir() .. "/statistics.sqlite3")
    local have = tonumber(conn:rowexec("SELECT count(*) FROM book WHERE md5 LIKE 'leaf-seed-%';")) or 0
    if have == 0 then
        local now = os.time()
        local function q(v) return "'" .. tostring(v):gsub("'", "''") .. "'" end
        local function at(days_ago, h, m)
            local d = os.date("*t", now - days_ago * 86400)
            d.hour, d.min, d.sec = h, m, 0
            return os.time(d)
        end
        local function read(id, total, days_ago, h, m, minutes, page0)
            local t0 = at(days_ago, h, m)
            if t0 + minutes * 60 > now - 60 then t0 = now - minutes * 60 - 120 end
            local n = math.max(1, math.floor(minutes * 60 / 75))
            for k = 0, n - 1 do
                conn:exec(string.format("INSERT OR IGNORE INTO page_stat_data VALUES (%d, %d, %d, 75, %d);",
                    id, (page0 + k) % total + 1, t0 + k * 75, total))
            end
            return page0 + n
        end
        local function book(title, authors, pages)
            conn:exec(string.format([[INSERT INTO book (title, authors, notes, last_open, highlights, pages, series, language, md5,
                total_read_time, total_read_pages) VALUES (%s, %s, 0, %d, 0, %d, '', 'en', %s, 0, 0);]],
                q(title), q(authors), now - 200 * 86400, pages, q("leaf-seed-" .. title)))
            return tonumber(conn:rowexec("SELECT max(id) FROM book;")), pages
        end
        -- the open book: today (three sessions) and five more days; three days ago nobody read
        local cur = st.id_curr_book
        if cur then
            local total = tonumber(conn:rowexec("SELECT pages FROM book WHERE id = " .. cur .. ";")) or 386
            local pg = 60
            pg = read(cur, total, 0, 6, 40, 13, pg)
            pg = read(cur, total, 0, 7, 5, 9, pg)
            pg = read(cur, total, 0, 21, 2, 13, pg)
            for _i, d in ipairs({ { 1, 28 }, { 2, 20 }, { 4, 26 }, { 5, 11 }, { 6, 14 } }) do
                pg = read(cur, total, d[1], 20, 30, d[2], pg)
            end
        end
        local BOOKS = {
            { "Siddhartha", "Hermann Hesse", 152, { { 0, 12, 30, 14 }, { 0, 21, 30, 8 }, { 1, 21, 10, 22 } } },
            { "The Odyssey", "Homer", 541, { { 4, 22, 0, 30 }, { 5, 22, 0, 18 }, { 6, 22, 0, 25 } } },
            { "Walden", "Henry David Thoreau", 352, { { 9, 21, 0, 35 }, { 10, 21, 0, 28 } } },
            { "Meditations", "Marcus Aurelius", 254, { { 7, 7, 0, 25 }, { 8, 7, 0, 20 }, { 10, 7, 0, 22 }, { 12, 7, 0, 30 }, { 14, 7, 0, 18 }, { 16, 7, 0, 26 } } },
            { "Frankenstein", "Mary Shelley", 280, { { 12, 20, 0, 40 }, { 13, 20, 0, 45 }, { 14, 20, 0, 38 }, { 15, 20, 0, 50 }, { 16, 20, 0, 42 }, { 17, 20, 0, 36 }, { 18, 20, 0, 44 } } },
            { "Dracula", "Bram Stoker", 418, { { 34, 21, 0, 50 }, { 36, 21, 0, 55 }, { 38, 21, 0, 48 }, { 40, 21, 0, 60 } } },
            { "A Study in Scarlet", "Arthur Conan Doyle", 188, { { 50, 20, 0, 60 }, { 52, 20, 0, 70 }, { 55, 20, 0, 65 } } },
            { "Pride and Prejudice", "Jane Austen", 432, { { 60, 21, 0, 45 }, { 63, 21, 0, 50 }, { 66, 21, 0, 40 }, { 70, 21, 0, 55 } } },
            { "Moby-Dick", "Herman Melville", 635, { { 90, 22, 0, 30 }, { 95, 22, 0, 40 }, { 100, 22, 0, 35 } } },
        }
        for _i, b in ipairs(BOOKS) do
            local id, total = book(b[1], b[2], b[3])
            local pg = 0
            for _j, s in ipairs(b[4]) do pg = read(id, total, s[1], s[2], s[3], s[4], pg) end
        end
        conn:exec([[UPDATE book SET last_open = (SELECT max(start_time) FROM page_stat_data WHERE id_book = book.id)
            WHERE md5 LIKE 'leaf-seed-%';]])
    end
    conn:close()
    return st
end
-- tap a row of the statistics page on top (by the start of its key, or its index)
function STATS.tap(prefix, index)
    local kv = RUI().statistics.kv
    if not (kv and kv.kv_pairs) then return end
    for i, pr in ipairs(kv.kv_pairs) do
        if type(pr) == "table" and ((index and i == index) or (prefix and tostring(pr[1]):sub(1, #prefix) == prefix)) then
            if kv.call then kv:call(i) elseif pr.callback then pr.callback(kv, { kv_pairs_idx = i }) end
            return
        end
    end
end

-- reader scenes need their book: every scene from "reader" on is an EPUB scene, from "reader-pdf" on a PDF one
do
    local kind
    for _i, sc in ipairs(SCENES) do
        if sc[1] == "reader" then kind = "epub" elseif sc[1] == "reader-pdf" then kind = "pdf" end
        sc.book = sc.book or kind
    end
end

local wanted = os.getenv("KO_AUTOSHOT_SCENES")
local list = {}
if wanted then
    local by_name = {}
    for _, s in ipairs(SCENES) do by_name[s[1]] = s end
    for name in wanted:gmatch("[^,%s]+") do
        if by_name[name] then table.insert(list, by_name[name]) else logger.warn("autoshot: unknown scene", name) end
    end
else
    list = SCENES
end

local night = os.getenv("KO_AUTOSHOT_NIGHT") and true or false
local suffix = night and "-night" or ""

local function close_above(depth)
    local stack = UIManager._window_stack
    while #stack > depth do
        UIManager:close(stack[#stack].widget)
    end
end

local function run(i)
    local scene = list[i]
    if not scene then
        UIManager:scheduleIn(0.5, function() UIManager:quit() end)
        return
    end
    -- a reader scene run on its own (or after the other book): open its book first
    if scene.book and not scene._opened and not book_open(scene.book) then
        scene._opened = true
        open_book(scene.book == "pdf" and PDF_BOOK or EPUB_BOOK)
        if scene.book == "epub" then UIManager:scheduleIn(2.5, function() chapter_one(3) seed_bookmarks() end) end
        UIManager:scheduleIn(4, function() run(i) end)
        return
    end
    local depth = #UIManager._window_stack
    local ok, err = pcall(scene[2])
    if not ok then logger.err("autoshot: scene", scene[1], "failed:", err) end
    UIManager:scheduleIn(scene.wait or 1.5, function()
        UIManager:forceRePaint()
        Screen:shot(string.format("%s/%s%s.png", path, scene[1], suffix))
        if not scene.keep then close_above(depth) end
        if LK and LK.cleanup then pcall(LK.cleanup) LK.cleanup = nil end
        if LK and RUI() and RUI().highlight then RUI().highlight:clear() end
        UIManager:scheduleIn(0.5, function() run(i + 1) end)
    end)
end

UIManager:scheduleIn(3, function()
    if night and not Screen.night_mode then
        Screen:toggleNightMode()
        UIManager:setDirty("all", "full")
    end
    run(1)
end)
