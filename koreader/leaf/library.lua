--[[
    Leaf library (prototype screens "library", "history", "collection"), drawn through the
    Project: Title plugin (PT).

    PT loads after the patches, so its modules are hooked as they are required (a `require`
    watcher for PT's module names; KOReader's own modules have different names).

    Header (PT's titlebar.lua, the user's customised one; same fields, callbacks and helpers):
      * title in Playfair SemiBold --fs-display + count in --fs-sm --text-3 (.ko-header .title.display);
      * Lucide icon buttons: search, sort, +, ☰ (main menu) — History: search, ⋮ (filters), ☰;
      * Leaf tabs (.ko-tabs): Library · Favorites · Collections · Folders, active --text medium with a
        --bw-lg accent underline, the others --text-3; on the right the grid / detail / list view
        switch (.lb-viewsw) = PT display modes mosaic_image / list_image_meta / list_no_meta;
      * History: filter chips (.lb-chips) All · Reading · On hold · Finished · Deleted with counts;
      * Folders: a crumb row (⬆ + path; long-press = folder shortcuts).
    Tabs → KOReader / PT:
      Library = PT's "meta browse" (every book under home, from PT's cache), Folders = the file
      browser (PT's default), Favorites = the favorites collection, Collections = the collection list.
    Bottom navigation (.ko-nav, leaf/widgets/bottomnav.lua) under the library, favorites,
    collections and history lists: Home (leaf/home.lua) · Library · History · Settings (main menu
    on its Settings tab).
    Footer: folder / sort text --fs-sm --text-3, "Page x of y" --fs-sm --text-2.
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local M = {}

local function fm() return require("apps/filemanager/filemanager").instance end

---------------------------------------------------------------- PT's "meta browse" switch
-- covermenu.lua keeps it in a local (`meta_browse_mode`): reached with debug.getupvalue
local meta = {}
local function meta_find(fn)
    for i = 1, 80 do
        local name = debug.getupvalue(fn, i)
        if not name then return end
        if name == "meta_browse_mode" then meta.fn, meta.idx = fn, i return end
    end
end
function M.metaMode()
    if not meta.fn then return false end
    local _n, v = debug.getupvalue(meta.fn, meta.idx)
    return v and true or false
end
local function meta_set(v)
    if meta.fn then debug.setupvalue(meta.fn, meta.idx, v and true or false) end
end

---------------------------------------------------------------- navigation
--- close the Leaf home, PT's history / collection lists, back to the file manager
function M.closeOverlays()
    local f = fm()
    local home = package.loaded["leaf/home"]
    if home and home.close then home.close() end
    if not f then return end
    if f.history and f.history.booklist_menu and f.history.booklist_menu.close_callback then
        f.history.booklist_menu.close_callback()
    end
    local c = f.collections
    if c then
        if c.booklist_menu and c.booklist_menu.close_callback then c.booklist_menu.close_callback() end
        if c.coll_list and c.coll_list.close_callback then c.coll_list.close_callback(true) end
    end
end

--- Library / Folders tab: PT's meta browse on / off (the file manager is rebuilt)
function M.showTab(tab)
    M.closeOverlays()
    local f = fm()
    if not f then return end
    if tab == "favorites" then
        f.collections:onShowColl()
    elseif tab == "collections" then
        f.collections:onShowCollList()
    else
        local want = tab == "library" and G_reader_settings:readSetting("home_dir") ~= nil
        G_reader_settings:saveSetting("leaf_library_tab", tab)
        if M.metaMode() ~= want then
            meta_set(want)
            f:reinit(want and G_reader_settings:readSetting("home_dir") or nil)
        end
    end
end

function M.showSettings()
    local f = fm()
    if not (f and f.menu) then return end
    f.menu:onShowMenu()
    local tm = f.menu.menu_container and f.menu.menu_container[1]
    if tm and tm.tab_item_table then
        for i, tab in ipairs(tm.tab_item_table) do
            if tab.icon == "appbar.settings" then tm.bar:switchToTab(i) end
        end
    end
end

function M.navigate(key)
    local f = fm()
    if not f then return end
    if key == "home" then
        M.closeOverlays()
        require("leaf/home").show()
    elseif key == "library" then
        M.closeOverlays()
    elseif key == "history" then
        M.closeOverlays()
        f.history:onShowHist()
    elseif key == "settings" then
        M.showSettings()
    end
end

---------------------------------------------------------------- view modes (PT display modes)
local VIEW_MODES = { grid = "mosaic_image", detail = "list_image_meta", list = "list_no_meta" }
local function view_of(mode)
    if not mode then return "list" end
    if mode:match("^mosaic") then return "grid" end
    if mode == "list_image_meta" then return "detail" end
    return "list"
end
local DB_NAMES = { filemanager = "filemanager_display_mode", history = "history_display_mode", collections = "collection_display_mode" }
function M.currentView(widget_id)
    local BIM = package.loaded["bookinfomanager"]
    if not BIM then return nil end
    return view_of(BIM:getSetting(DB_NAMES[widget_id or "filemanager"]))
end
--- one view everywhere (as the prototype): file manager, favorites / collections and history
function M.setView(key, menu)
    local f = fm()
    local pt = f and f.projecttitle
    local mode = VIEW_MODES[key]
    if not (pt and mode) then return end
    pt:setDisplayMode(mode)
    if pt.setupWidgetDisplayMode then
        pt.setupWidgetDisplayMode("collections", mode)
        pt.setupWidgetDisplayMode("history", mode)
    end
    if menu and menu.name == "collections" and menu.close_callback then
        local name = menu.path
        menu.close_callback()
        f.collections:onShowColl(name)
    else
        f:reinit()
    end
end


---------------------------------------------------------------- upvalues of PT's modules
local function upvalue(fn, name)
    if type(fn) ~= "function" then return end
    for i = 1, 200 do
        local n, v = debug.getupvalue(fn, i)
        if not n then return end
        if n == name then return v, i end
    end
end
--- replace a file-level local of a PT module (shared by every function of that file)
local function set_upvalue(fn, name, value)
    local _v, i = upvalue(fn, name)
    if i then debug.setupvalue(fn, i, value) return true end
end

--- PT's list progress bars (bordered grey boxes) -> .ko-progress: a thin accent bar on --surface-3
local function leaf_progress_class(L)
    local T = L.T
    local ProgressWidget = require("ui/widget/progresswidget")
    local Bar = ProgressWidget:extend{}
    function Bar:paintTo(bb, x, y)
        local P = require("leaf/widgets/libparts")
        local sz = self:getSize()
        local h = math.min(sz.h, P.px(3))
        local yy = y + math.floor((sz.h - h) / 2)
        local r = math.floor(h / 2)
        bb:paintRoundedRect(x, yy, sz.w, h, T.color("surface-3"), r)
        local p = math.max(0, math.min(1, self.percentage or 0))
        if p > 0 then bb:paintRoundedRect(x, yy, math.max(h, math.floor(sz.w * p + 0.5)), h, T.color("accent"), r) end
    end
    return Bar
end

---------------------------------------------------------------- header
local function header_init(L, self)
    local T = L.T
    local P = require("leaf/widgets/libparts")
    local IconButton = require("ui/widget/iconbutton")
    local IconWidget = require("ui/widget/iconwidget")
    local Button = require("ui/widget/button")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local fonts = require("leaf/fonts")
    local W = Screen:getWidth()
    self.width = W
    local side = T.px("sp-5")
    local s = T.px("icon-md")
    local btn_pad = math.floor((T.px("hit") - s) / 2)
    local menu = self.show_parent -- the history / collection list (PT passes it as show_parent)
    local function icon_button(icon, tap, hold)
        return IconButton:new{ icon = icon, width = s, height = s, padding = btn_pad,
            callback = tap, hold_callback = hold, show_parent = self.show_parent }
    end
    local function show_main_menu()
        if fm() and fm().menu then fm().menu:onShowMenu() end
    end

    -- which screen: library | folders | favorites | collection | collections | history
    local mode = self.mode
    local screen, title
    local selecting = self.right1_icon == "check"
    if mode == "history" then
        screen, title = "history", "History"
    elseif mode == "colllist" then
        screen, title = "collections", "Collections"
    elseif mode == "collections" then
        local ReadCollection = require("readcollection")
        local name = menu and menu.path
        if not name or name == ReadCollection.default_collection_name then
            screen, title = "favorites", "Favorites"
        else
            screen, title = "collection", name
        end
    else
        screen = M.metaMode() and "library" or "folders"
        title = screen == "library" and "Library" or "Folders"
    end
    if selecting then title = "Select books" end
    self.leaf_screen = screen

    local title_widget = TextWidget:new{ text = title, face = L.face("display-semibold", "fs-display"), padding = 0,
        max_width = math.floor(W * 0.45) }
    self.count_widget = TextWidget:new{ text = "", face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), padding = 0 }

    local buttons
    if screen == "library" or screen == "folders" then
        self.right3_button = icon_button("pt_search", function()
            if fm() and fm().filesearcher then fm().filesearcher:onShowFileSearch() end
        end)
        self.right2_button = icon_button("pt_sort", function()
            local ButtonDialog = require("ui/widget/buttondialog")
            local dialog
            local function choice(text, sort_mode)
                return { { text = text, callback = function()
                    UIManager:close(dialog)
                    if fm() then fm():onSetSortBy(sort_mode) end
                end } }
            end
            dialog = ButtonDialog:new{ title = "Sort by", buttons = {
                choice("Title", "strcoll"), choice("Recently read", "access"),
                choice("Date added", "date"), choice("Progress", "percent_unopened_first") } }
            UIManager:show(dialog)
        end)
        self.right1_button = icon_button(self.right1_icon == "plus" and "pt_plus" or self.right1_icon,
            self.right1_icon_tap_callback, self.right1_icon_hold_callback)
        self.settings_button = icon_button("appbar.menu", show_main_menu)
        buttons = { self.right3_button, self.right2_button, self.right1_button, self.settings_button }
    elseif screen == "collections" then
        self.right3_button = icon_button("pt_search", function()
            if fm() and fm().filesearcher then fm().filesearcher:onShowFileSearch() end
        end)
        -- the collection list's own dialog (new collection, sort, …)
        self.right2_button = icon_button("leaf.more.v", function() if menu and menu.onLeftButtonTap then menu:onLeftButtonTap() end end)
        self.settings_button = icon_button("appbar.menu", show_main_menu)
        buttons = { self.right3_button, self.right2_button, self.settings_button }
    else
        -- history / favorites / a collection: search, ⋮ (the list's dialog: filters, sort, select…), ☰
        self.right3_button = icon_button("pt_search", function()
            if mode == "history" and fm() then fm().history:onSearchHistory()
            elseif fm() and menu then fm().collections:onShowCollectionsSearchDialog(nil, menu.path) end
        end)
        self.right2_button = icon_button("leaf.more.v", self.right2_icon_tap_callback, self.right2_icon_hold_callback)
        self.settings_button = icon_button("appbar.menu", show_main_menu)
        buttons = { self.right3_button, self.right2_button, self.settings_button }
    end

    -- row 1: title + count left, actions right (.ko-header: --h-header, --sp-5 sides)
    local hh = math.max(T.px("h-header"), title_widget:getSize().h + 2 * T.px("sp-2"))
    local left = HorizontalGroup:new{ align = "center",
        HorizontalSpan:new{ width = side }, title_widget,
        HorizontalSpan:new{ width = T.px("sp-2") }, self.count_widget }
    local right = HorizontalGroup:new{ align = "center" }
    for _i, b in ipairs(buttons) do table.insert(right, b) end
    table.insert(right, HorizontalSpan:new{ width = side - btn_pad })
    local row1 = OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
        LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, left },
        RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, right },
    }
    local rows = { row1 }

    if screen == "history" then
        -- row 2: filter chips (.lb-chips)
        local counts = { all = 0, reading = 0, abandoned = 0, complete = 0, deleted = 0, new = 0 }
        local BookList = require("ui/widget/booklist")
        for _i, v in ipairs(require("readhistory").hist) do
            counts.all = counts.all + 1
            local st = v.dim and "deleted" or BookList.getBookStatus(v.file)
            if counts[st] then counts[st] = counts[st] + 1 end
        end
        local h = fm() and fm().history
        local cur = (h and h.filter) or G_reader_settings:readSetting("history_filter", "all")
        local chips = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = side } }
        for i, c in ipairs({ { "all", "All" }, { "reading", "Reading" }, { "abandoned", "On hold" },
                             { "complete", "Finished" }, { "deleted", "Deleted" } }) do
            local key, label = c[1], c[2]
            local on = key == cur
            local inner = HorizontalGroup:new{ align = "center",
                TextWidget:new{ text = label, face = L.face(on and "ui-semibold" or "ui", "fs-sm"),
                    fgcolor = T.color(on and "text" or "text-2"), padding = 0 },
                HorizontalSpan:new{ width = T.px("sp-1h") },
                TextWidget:new{ text = tostring(counts[key]), face = L.face("ui", "fs-xs"),
                    fgcolor = T.color(on and "text-2" or "text-3"), padding = 0 } }
            local isz = inner:getSize()
            local chip = FrameContainer:new{ bordersize = T.px("hairline"), color = T.color(on and "accent" or "border"),
                background = T.color(on and "accent-soft" or "surface-2"), radius = math.floor(T.px("h-chip") / 2),
                padding = 0, padding_left = T.px("sp-3"), padding_right = T.px("sp-3"),
                CenterContainer:new{ dimen = Geom:new{ w = isz.w, h = T.px("h-chip") - 2 * T.px("hairline") }, inner } }
            if i > 1 then table.insert(chips, HorizontalSpan:new{ width = T.px("sp-2") }) end
            table.insert(chips, P.Tap:new{ content = chip, callback = function()
                if not (h and h.booklist_menu) then return end
                h.filter = key
                if key == "all" then h.search_string = nil h.selected_collections = nil end
                h.booklist_menu.close_callback() -- saves the filter
                h:onShowHist()
            end })
        end
        table.insert(rows, VerticalSpan:new{ width = T.px("sp-1h") })
        table.insert(rows, chips)
        table.insert(rows, VerticalSpan:new{ width = T.px("sp-3h") })
    else
        -- row 2: Leaf tabs (.ko-tabs) + view switch (.lb-viewsw)
        local function tab(text, active, tap, hold)
            local face = active and fonts.FILES["ui-medium"] or fonts.FILES["ui"]
            local probe = TextWidget:new{ text = text, face = require("ui/font"):getFace(face, T.fs("fs-md")) }
            local w = probe:getSize().w
            probe:free()
            local b = Button:new{ text = text, bordersize = 0, radius = 0, margin = 0, padding = 0, padding_h = 0,
                text_font_face = face, text_font_size = T.fs("fs-md"), text_font_bold = false,
                width = w, height = T.px("hit") - T.px("bw-lg"),
                callback = tap, hold_callback = hold or nil, show_parent = self.show_parent }
            if b.label_widget then
                b.label_widget.fgcolor = T.color(active and "text" or "text-3")
                if b.label_widget.update then b.label_widget:update() end
            end
            local g = VerticalGroup:new{ align = "left", b,
                active and LineWidget:new{ dimen = Geom:new{ w = w, h = T.px("bw-lg") }, background = T.color("accent") }
                    or VerticalSpan:new{ width = T.px("bw-lg") } }
            return b, g
        end
        local function go(t) return function() M.showTab(t) end end
        local folder_hold = function() if fm() then fm().folder_shortcuts:onShowFolderShortcutsDialog() end end
        local t1, t2, t3, t4, g1, g2, g3, g4
        t1, g1 = tab("Library", screen == "library", go("library"))
        t2, g2 = tab("Favorites", screen == "favorites", go("favorites"))
        t3, g3 = tab("Collections", screen == "collections" or screen == "collection", go("collections"))
        t4, g4 = tab("Folders", screen == "folders", go("folders"), folder_hold)
        self.left1_button, self.left2_button, self.left3_button, self.center_button = t1, t2, t3, t4
        local gap = T.px("sp-5")
        local tabs = HorizontalGroup:new{ align = "bottom",
            HorizontalSpan:new{ width = side }, g1, HorizontalSpan:new{ width = gap }, g2,
            HorizontalSpan:new{ width = gap }, g3, HorizontalSpan:new{ width = gap }, g4 }
        local th = tabs:getSize().h
        local row2 = OverlapGroup:new{ dimen = Geom:new{ w = W, h = th },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = th }, tabs } }
        if screen ~= "collections" then
            -- .lb-viewsw: --hairline --border box, --r-sm, three 34x28 icon cells; on = accent-soft + accent ring
            local widget_id = (screen == "favorites" or screen == "collection") and "collections" or "filemanager"
            local cur = M.currentView(widget_id)
            local cells = HorizontalGroup:new{ align = "center" }
            local cw, ch = T.px("h-seg"), P.px(28)
            for i, k in ipairs({ "grid", "detail", "list" }) do
                local on = k == cur
                local bw = on and T.px("bw-md") or 0
                local cell = FrameContainer:new{ bordersize = bw, color = T.color("accent"),
                    background = on and T.color("accent-soft") or nil, radius = T.px("r-cover"), padding = 0, margin = 0,
                    CenterContainer:new{ dimen = Geom:new{ w = cw - 2 * bw, h = ch - 2 * bw },
                        IconWidget:new{ icon = "leaf.view." .. k .. (on and ".on" or ""), width = T.px("icon-sm"), height = T.px("icon-sm"), alpha = true } } }
                if i > 1 then table.insert(cells, HorizontalSpan:new{ width = T.px("sp-half") }) end
                table.insert(cells, P.Tap:new{ content = cell, callback = function()
                    if k ~= cur then M.setView(k, mode == "collections" and menu or nil) end
                end })
            end
            local sw = FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"), radius = T.px("r-sm"),
                padding = T.px("sp-half"), margin = 0, cells }
            table.insert(row2, RightContainer:new{ dimen = Geom:new{ w = W - side, h = th - T.px("bw-lg") }, sw })
        end
        table.insert(rows, row2)
    end
    table.insert(rows, LineWidget:new{ dimen = Geom:new{ w = W, h = T.px("hairline") }, background = T.color("border") })

    if screen == "folders" then
        -- crumb row (.lb-crumbs): ⬆ parent folder, the current path; long-press = folder shortcuts
        local up = icon_button("go_up", self.right2_icon_tap_callback)
        self.crumb_widget = TextWidget:new{ text = "", face = L.face("ui-semibold", "fs-sm"), fgcolor = T.color("accent"),
            padding = 0, max_width = W - 2 * side - T.px("hit"), truncate_left = true }
        local crumb = P.Tap:new{ content = LeftContainer:new{ dimen = Geom:new{ w = W - T.px("hit") - side, h = T.px("hit") }, self.crumb_widget },
            callback = function() end,
            hold_callback = function() if fm() then fm().folder_shortcuts:onShowFolderShortcutsDialog() end end }
        table.insert(rows, HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = T.px("sp-4") - btn_pad }, up, crumb })
        table.insert(rows, LineWidget:new{ dimen = Geom:new{ w = W, h = T.px("hairline") }, background = T.color("border") })
    end

    local content = VerticalGroup:new{ align = "left" }
    for _i, r in ipairs(rows) do table.insert(content, r) end
    self.titlebar_height = content:getSize().h
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = self.titlebar_height }
    table.insert(self, content)
    self.left_button = self.left1_button
    self.right_button = self.right1_button
    OverlapGroup.init(self)
end

--- "Books  ›  Classics" style path for the crumb row (relative to the home folder's parent)
local function pretty_path(path)
    if not path then return "" end
    local home = G_reader_settings:readSetting("home_dir")
    local rel = path
    if home and path:sub(1, #home) == home then
        local base = home:match("([^/]+)/*$") or home
        rel = base .. path:sub(#home + 1)
    end
    rel = rel:gsub("^/+", ""):gsub("/+$", "")
    return (rel:gsub("/", "  ›  "))
end

function M.apply(L)
    local T = L.T
    local LeafNav = require("leaf/widgets/bottomnav")

    -- the footer (.lb footer): folder / sort text --fs-sm --text-3, "Page x of y" --fs-sm --text-2
    local function style_footer(menu)
        local cf = menu.cur_folder_text
        if cf and cf.setText then
            cf.face = L.face("ui", "fs-sm")
            cf.fgcolor = T.color("text-3")
            cf:setText(cf.text or "")
        end
        local pt = menu.page_info_text
        if pt and pt.setText and pt._leaf_kind ~= "caption" then
            pt._leaf_kind = "caption"
            pt:setText(pt.text or "", pt.width)
        end
        -- favorites / a collection: the footer's ⮌ (back to the collection list) replaces the folder text
        if menu.name == "collections" and cf and cf.setText and cf.text ~= "" then cf:setText("") end
        local tb = menu.title_bar
        if tb and tb.crumb_widget and type(menu.path) == "string" then
            tb.crumb_widget:setText(pretty_path(menu.path))
        end
    end

    -- which list gets the bottom navigation
    local function nav_kind(menu)
        if menu.name == "filemanager" and menu.custom_title_bar and menu.custom_title_bar.setCount then return "library" end
        if menu.name == "history" and not menu.no_title then return "history" end
        if menu.name == "collections" and not menu.no_title then return "collections" end
        local FMC = package.loaded["apps/filemanager/filemanagercollection"]
        if FMC and menu._manager and menu.onMenuChoice == FMC.onCollListChoice
            and menu.title_bar_left_icon == "appbar.menu" then return "colllist" end
    end

    local hooks = {
        -- PT's list / grid container: bottom nav, footer, counts
        covermenu = function(CoverMenu)
            if type(CoverMenu) ~= "table" or not CoverMenu.menuInit then return end
            if CoverMenu.genItemTable then meta_find(CoverMenu.genItemTable) end
            -- start on the tab used last (default: Library = every book)
            if G_reader_settings:readSetting("leaf_library_tab", "library") == "library"
                and G_reader_settings:readSetting("home_dir") then
                meta_set(true)
            end
            L.wrap(CoverMenu, "menuInit", function(orig, self, ...)
                local kind = nav_kind(self)
                if kind then
                    local nav_h = LeafNav.height()
                    if (self.height or Screen:getHeight()) > Screen:getHeight() - nav_h then
                        self.height = Screen:getHeight() - nav_h
                    end
                    if kind == "colllist" and not self.custom_title_bar then
                        local TitleBar = package.loaded["titlebar"]
                        if TitleBar and TitleBar.setCount then
                            self.custom_title_bar = TitleBar:new{ mode = "colllist", show_parent = self }
                        end
                    end
                end
                orig(self, ...)
                style_footer(self)
                if kind then
                    self._leaf_nav = LeafNav:new{ width = self.dimen.w, active = kind == "history" and "history" or "library",
                        on_select = function(key)
                            if key == "history" and kind == "history" then return end
                            if key == "library" and kind == "library" then return end
                            M.navigate(key)
                        end }
                    self[1] = VerticalGroup:new{ align = "left", self[1], self._leaf_nav }
                    if kind == "colllist" and self.title_bar and self.title_bar.count_widget then
                        local n = 0
                        for _k in pairs(require("readcollection").coll) do n = n + 1 end
                        self.title_bar.count_widget:setText(tostring(n))
                    end
                end
            end, "PT CoverMenu:menuInit")
            L.wrap(CoverMenu, "updatePageInfo", function(orig, self, ...)
                orig(self, ...)
                style_footer(self)
            end, "PT CoverMenu:updatePageInfo")
            L.wrap(CoverMenu, "updateItems", function(orig, self, ...)
                local r = { orig(self, ...) }
                local tb = self.title_bar
                if tb and tb.setCount and tb.mode ~= "colllist" and self.item_table then
                    local n = 0
                    for _i, e in ipairs(self.item_table) do
                        if e.is_file or e.file then n = n + 1 end
                    end
                    tb:setCount(n)
                end
                return unpack(r)
            end, "PT CoverMenu:updateItems")
        end,
        -- PT's fonts: its serif / italic faces (titles, authors, folder names) -> Inter, like the prototype
        ptutil = function(ptutil)
            if type(ptutil) ~= "table" or not ptutil.good_serif then return end
            local F = require("leaf/fonts").FILES
            ptutil.good_serif = F["ui"]
            ptutil.good_serif_it = F["ui"]
            ptutil.good_serif_bold = F["ui-semibold"]
            ptutil.good_serif_boldit = F["ui-semibold"]
            ptutil.title_serif = F["ui-semibold"]
            -- list rows on the prototype's type scale (.lb-drow .t --fs-lg, .a --fs-sm; .lb-lrow .t --fs-md)
            local d = ptutil.list_defaults
            if type(d) == "table" then
                local fs = function(k) return T.size[k] end
                d.title_font_nominal, d.title_font_max, d.title_font_min = fs("fs-lg"), fs("fs-lg"), fs("fs-md")
                d.authors_font_nominal, d.authors_font_max, d.authors_font_min = fs("fs-sm"), fs("fs-sm"), fs("fs-xs")
                d.wright_font_nominal, d.wright_font_max = fs("fs-xs"), fs("fs-sm")
                d.directory_font_nominal, d.directory_font_max = fs("fs-md"), fs("fs-lg")
            end
        end,
        -- list views: Leaf progress bars
        listmenu = function(ListMenu)
            if type(ListMenu) ~= "table" or not ListMenu._updateItemsBuildUI then return end
            local Item = upvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
            if Item and Item.update then set_upvalue(Item.update, "ProgressWidget", leaf_progress_class(L)) end
        end,
        -- grid: folder tiles (.lb-frow look as a tile), covers with --r-cover corners and a --border hairline
        mosaicmenu = function(MosaicMenu)
            if type(MosaicMenu) ~= "table" or not MosaicMenu._updateItemsBuildUI then return end
            local Item = upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
            if not (Item and Item.update and Item.paintTo) then return end
            local P = require("leaf/widgets/libparts")
            local ptutil = package.loaded["ptutil"]
            L.wrap(Item, "update", function(orig, self, ...)
                orig(self, ...)
                if not self.is_directory or (ptutil and ptutil.isPathChooser(self)) then return end
                local FrameContainer = require("ui/widget/container/framecontainer")
                local CenterContainer = require("ui/widget/container/centercontainer")
                local IconWidget = require("ui/widget/iconwidget")
                local TextBoxWidget = require("ui/widget/textboxwidget")
                local inset = T.px("sp-2")
                local w, h = self.width - 2 * inset, self.height - 2 * inset
                local name = (self.text or ""):gsub("/$", "")
                local n = (self.mandatory or ""):gsub("^☆ ", ""):match("%d+")
                local icon_s = T.px("icon-2xl")
                local inner_w = w - 2 * T.px("sp-3")
                local col = VerticalGroup:new{ align = "center",
                    IconWidget:new{ icon = "leaf.lib.folder", width = icon_s, height = icon_s, alpha = true },
                    VerticalSpan:new{ width = T.px("sp-3") },
                    TextBoxWidget:new{ text = name, face = L.face("ui-medium", "fs-md"), width = inner_w, alignment = "center",
                        bgcolor = T.color("surface"), height = 3 * T.px("sp-6"), height_adjust = true, height_overflow_show_ellipsis = true },
                    VerticalSpan:new{ width = T.px("sp-1") },
                    TextWidget:new{ text = n and (n == "1" and "1 item" or (n .. " items")) or "", face = L.face("ui", "fs-sm"),
                        fgcolor = T.color("text-3"), padding = 0, max_width = inner_w } }
                local tile = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height },
                    FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"), background = T.color("surface"),
                        radius = T.px("r-md"), padding = 0, margin = 0,
                        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * T.px("hairline"), h = h - 2 * T.px("hairline") }, col } } }
                if self._underline_container[1] then self._underline_container[1]:free() end
                self._underline_container[1] = tile
            end, "PT MosaicMenuItem:update")
            L.wrap(Item, "paintTo", function(orig, self, bb, x, y)
                orig(self, bb, x, y)
                if self.is_directory then return end
                local target = self[1] and self[1][1] and self[1][1][1]
                local d = target and target.dimen
                if not (d and d.w and d.w > 0 and d.x) then return end
                -- the cover frame: --border hairline (over PT's black line) and --r-cover corners
                local r = T.px("r-cover")
                local bg = T.color("bg")
                local bw = math.max(1, require("ui/size").border.thin)
                bb:paintBorder(d.x, d.y, d.w, d.h, bw, bg)
                for dy = 0, r - 1 do
                    local yy = r - dy - 0.5
                    local cut = r - math.floor(math.sqrt(math.max(0, r * r - yy * yy)) + 0.5)
                    if cut > 0 then
                        bb:paintRect(d.x, d.y + dy, cut, 1, bg)
                        bb:paintRect(d.x + d.w - cut, d.y + dy, cut, 1, bg)
                        bb:paintRect(d.x, d.y + d.h - 1 - dy, cut, 1, bg)
                        bb:paintRect(d.x + d.w - cut, d.y + d.h - 1 - dy, cut, 1, bg)
                    end
                end
                bb:paintBorder(d.x, d.y, d.w, d.h, T.px("hairline"), T.color("border"), r)
            end, "PT MosaicMenuItem:paintTo")
        end,
        -- PT's header (its titlebar.lua; KOReader's is "ui/widget/titlebar")
        titlebar = function(TitleBar)
            if type(TitleBar) ~= "table" or not TitleBar.setCount then return end -- not PT's
            L.wrap(TitleBar, "init", function(orig, self) header_init(L, self) end, "PT TitleBar:init")
        end,
    }
    local done = {}
    local orig_require = require
    _G.require = function(name, ...)
        local mod = orig_require(name, ...)
        local hook = hooks[name]
        if hook and not done[name] then
            done[name] = true
            local ok, err = pcall(hook, mod)
            if ok then L.log("library: hooked", name) else L.err("library: hook", name, "failed:", err) end
        end
        return mod
    end
end

return M
