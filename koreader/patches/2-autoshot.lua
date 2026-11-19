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

local LK = {} -- lookup scenes: helpers, defined below the list

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
