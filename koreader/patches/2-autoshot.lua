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

local function show(mod, args) UIManager:show(require(mod):new(args)) end
-- typeset scenes: open the reader's typesetting sheet on a Leaf tab (leaf_key), then run `after`
local function ts_open(key, after)
    local ui = RUI()
    if not ui then return end
    if not ui._leaf_ts_paged and not ui.document.koptinterface then
        ui._leaf_ts_paged = true
        ui:handleEvent(require("ui/event"):new("GotoPage", 12)) -- a text page behind the sheet
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

local LK = {} -- lookup scenes: helpers, defined below the list
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
    { "fm", noop },
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
    { "buttondialog", function() show("ui/widget/buttondialog", {
        title = "Animal Farm",
        buttons = {
            { { text = "Open", callback = noop }, { text = "Book information", callback = noop } },
            { { text = "Mark as finished", callback = noop }, { text = "Add to collection", callback = noop } },
            { { text = "Delete", callback = noop }, { text = "Rename", callback = noop } },
        } }) end },
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
        FM().bookinfo:show(G_reader_settings:readSetting("home_dir") .. "/Animal Farm (EN-AR).epub")
    end },
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
    -- library scenes
    { "lib-library", function() require("leaf/library").showTab("library") end, wait = 3 },
    { "lib-folders", function() require("leaf/library").showTab("folders") end, wait = 3 },
    { "lib-detail", function()
        require("leaf/library").showTab("library")
        require("leaf/library").setView("detail")
    end, wait = 3 },
    { "lib-list", function() require("leaf/library").setView("list") end, wait = 3 },
    { "lib-grid", function() require("leaf/library").setView("grid") end, wait = 3 },
    { "lib-favorites", function()
        local RC = require("readcollection")
        local home = G_reader_settings:readSetting("home_dir")
        for _i, f in ipairs({ "/Animal Farm.epub", "/Animal Farm (EN-AR).epub" }) do
            if not RC:isFileInCollection(home .. f, RC.default_collection_name) then RC:addItem(home .. f, RC.default_collection_name) end
        end
        RC:write({ [RC.default_collection_name] = true })
        require("leaf/library").showTab("favorites")
    end, wait = 3 },
    { "lib-collections", function() require("leaf/library").showTab("collections") end, wait = 2 },
    { "lib-history", function()
        local RH = require("readhistory")
        local home = G_reader_settings:readSetting("home_dir")
        for _i, f in ipairs({ "/KOReader UI Redesign Concept.pdf", "/Animal Farm (EN-AR).epub", "/Animal Farm.epub" }) do
            RH:addItem(home .. f, os.time())
        end
        require("leaf/library").navigate("history")
    end, wait = 3 },
    { "lib-settings", function() require("leaf/library").navigate("settings") end, wait = 2 },
    { "home", function()
        require("leaf/library").closeOverlays()
        require("leaf/home").show()
    end, wait = 3 },
    { "catalog", function()
        local ok, catalog = pcall(require, "leaf/catalog")
        if ok then catalog.show() else logger.info("autoshot: no leaf/catalog yet") end
    end },
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
    -- reader scenes replace the file manager: keep them last
    { "reader", function()
        local book = G_reader_settings:readSetting("home_dir") .. "/Animal Farm.epub"
        require("apps/reader/readerui"):showReader(book)
    end, keep = true, wait = 4 },
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
    { "bookmarks", function() RUI().bookmark:onShowBookmark() end },
    -- kvpages scenes (reader): the paragraph-translate patch panel, on the EN-AR edition (opens it: keep last)
    { "translate", function()
        local book = G_reader_settings:readSetting("home_dir") .. "/Animal Farm (EN-AR).epub"
        require("apps/reader/readerui"):showReader(book)
        UIManager:scheduleIn(4, function()
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
        local book = G_reader_settings:readSetting("home_dir") .. "/Animal Farm (EN-AR).epub"
        local function chapter_one()
            local ui = RUI()
            for _, t in ipairs(ui.toc.toc or {}) do
                if t.title:find("Chapter I", 1, true) then ui.rolling:onGotoXPointer(t.xpointer) break end
            end
        end
        if RUI() then
            RUI():switchDocument(book, true)
        else
            require("apps/reader/readerui"):showReader(book)
        end
        UIManager:scheduleIn(3, chapter_one)
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
        s.last_search_text = "the"
        s.case_insensitive = true
        require("ui/trapper"):wrap(function() s:findAllText("the") end)
    end, wait = 3 },
    -- end system and tools reader scenes
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
    { "reader-pdf", function()
        local book = G_reader_settings:readSetting("home_dir") .. "/KOReader UI Redesign Concept.pdf"
        require("apps/reader/readerui"):showReader(book)
    end, keep = true, wait = 4 },
    { "ts-pdf-rotate", function() ts_open("rotate") end },
    { "ts-pdf-crop", function() ts_open("crop") end },
    { "ts-pdf-zoom", function() ts_open("zoom") end },
    { "ts-pdf-page", function() ts_open("page") end },
    { "ts-pdf-reflow", function() ts_open("reflow") end },
    { "ts-pdf-contrast", function() ts_open("contrast") end },
    { "ts-pdf-doc", function() ts_open("doc") end },
    -- reader extras scenes (frontlight, go to, skim, book map, page browser, book end, page header)
    { "reader-page", function()
        -- a text page with a chapter title, so the page header has something to show
        RUI():handleEvent(require("ui/event"):new("GotoPage", 12))
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
    { "skim", function() RUI().gotopage:onShowSkimtoDialog() end },
    { "skim-moved", function()
        RUI().gotopage:onShowSkimtoDialog()
        local w = UIManager._window_stack[#UIManager._window_stack].widget
        if w.goToPage then w:goToPage(w.curr_page + 10) end
    end },
    { "bookmap", function() RUI().thumbnail:onShowBookMap() end, wait = 3 },
    { "bookmap-overview", function() RUI().thumbnail:onShowBookMap(true) end, wait = 3 },
    { "pagebrowser", function() RUI().thumbnail:onShowPageBrowser() end, wait = 5 },
    { "bookend", function() RUI().status:onEndOfBook() end, wait = 2 },
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
