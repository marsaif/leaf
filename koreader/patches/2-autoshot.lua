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
local noop = function() end

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
    { "catalog", function()
        local ok, catalog = pcall(require, "leaf/catalog")
        if ok then catalog.show() else logger.info("autoshot: no leaf/catalog yet") end
    end },
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
                if o.icon == "appbar.textsize" then d:handleEvent(require("ui/event"):new("ShowConfigPanel", i)) end
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
}

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
