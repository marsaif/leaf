--[[
    Leaf arrange page (Gaps › arrange): KOReader's SortWidget (arrange collections, books in a
    collection, status bar items, actions, dictionaries, cloud servers…).

    A full page: status strip, page header (crumb over the title, ← back, a sort button on the
    right), a --text-3 help line, then the items as rows of a .ko-group card: grip handle, an optional
    check (items with checked_func, or the status bar's hidden items), the label (+ "Hidden"), its
    position on the right. Tap an item to select it (--surface-3, a move handle, semibold); the
    footer then shows its name and ⇈ ↑ ↓ ⇊ + Done. Otherwise the footer is [⟲ Undo changes] … [Close]
    [Save]. The sort button opens a popover: A to Z, Z to A, and their natural-number variants.
    Pages when the items don't fit (swipe, or the ‹ n / m › pager over the footer).

    Same instance, fields and callbacks as KOReader's: item_table (re-ordered in place), marked,
    orig_item_table (Undo = onCancel), moveItem, sortItems, onReturn (Save → callback), onClose,
    item callbacks / hold_callbacks, sort_disabled (tap = the item's callback).
    The status bar's "Arrange items" list also toggles items on/off from the check (saved with Save).
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

-- KOReader title -> Leaf title + crumb
local TITLES = {
    ["Arrange collections"] = { crumb = "Collections" },
    ["Arrange books in collection"] = { title = "Arrange books", crumb = "Collection" },
    ["Arrange items"] = { title = "Status bar items", crumb = "Settings › Status bar" },
    ["Arrange actions"] = { crumb = "Gestures" },
    ["Arrange servers"] = { crumb = "Cloud storage" },
    ["Manage installed dictionaries"] = { title = "Dictionary order", crumb = "Dictionaries" },
    ["Sort and toggle buttons"] = { crumb = "Dictionary" },
}

function M.apply(L)
    local T = L.T
    local GW = require("leaf/widgets/gwkit")(L)
    local Kit = require("leaf/widgets/kit")
    local SortWidget = require("ui/widget/sortwidget")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LeftContainer = require("ui/widget/container/leftcontainer")

    local function human(title)
        return TITLES[title] or TITLES[_(title) or ""] or {}
    end

    local function is_footer(self)
        return self.title == _("Arrange items") and self.item_table[1] and self.item_table[1].label ~= nil
            and self.item_table[1].dim ~= nil
    end
    -- the item's on/off state, if it has one
    local function check_state(self, item)
        if item.checked_func then return item.checked_func() end
        if self._leaf_footer then return not item.dim end
    end

    local function backup(self)
        if not self.orig_item_table then
            self.orig_item_table = require("util").tableDeepCopy(self.item_table)
        end
    end

    local function toggle(self, item)
        if item.checked_func then
            if item.callback then item:callback() end
        elseif self._leaf_footer then
            backup(self)
            item.dim = not item.dim
        end
        self:_populateItems()
    end

    local function row(self, idx, W)
        local item = self.item_table[idx]
        local sel = idx == self.marked
        local on = check_state(self, item)
        local inner = GW.group_inner(W)
        local lead = HorizontalGroup:new{ align = "center",
            GW.icon(sel and "leaf.gw.move-vertical" or "leaf.gw.grip-vertical", "icon-md", sel and "accent" or "text-2") }
        local check_tap
        if on ~= nil then
            -- the check's touch area runs to the label (44px tall, check + --sp-3 wide)
            local w, h = T.px("icon-md") + T.px("sp-3"), T.px("hit")
            check_tap = Kit.Tap:new{ width = w, height = h, callback = function() toggle(self, item) end,
                content = LeftContainer:new{ dimen = GW.geom(w, h), GW.check(on) } }
            table.insert(lead, GW.hspan("sp-3"))
            table.insert(lead, check_tap)
        end
        local text = item.text or (item.text_func and item.text_func()) or ""
        -- status bar items: KOReader appends the item's symbol, "Current page (/)": drop it
        if self._leaf_footer then text = text:gsub("%s*%b()%s*$", "") end
        local hidden = (self._leaf_footer and item.dim) or (item.checked_func and not on and self._leaf_footer)
        return GW.row{ width = inner, pad = T.px("sp-4"), lead = lead, lead_gap = check_tap and 0 or nil,
            label = text, label_role = sel and "ui-semibold" or "ui",
            sub = hidden and _("Hidden") or nil, sub_color = sel and "text-2" or nil,
            value = tostring(idx), value_color = sel and "text-2" or nil, sel = sel,
            callback = function()
                if self.sort_disabled then
                    if item.checked_func then return toggle(self, item) end
                    if item.callback then item:callback() self:_populateItems() end
                    return
                end
                self.marked = (self.marked == idx) and 0 or idx
                self:_populateItems()
            end,
            hold_callback = function()
                if item.hold_callback then
                    item:hold_callback(function() self:_populateItems() end)
                elseif item.callback then
                    item:callback()
                    self:_populateItems()
                end
            end }
    end

    local function show_sort_menu(self, anchor)
        local W = math.floor(Screen:scaleBySize(290 * T.scale))
        local pop
        local function entry(icon, label, collate, rev)
            return GW.pop_row{ width = W, icon = icon, label = label, callback = function()
                UIManager:close(pop)
                self:sortItems(collate, rev)
            end }
        end
        local content = VerticalGroup:new{ align = "left",
            HorizontalGroup:new{ GW.hspan(0), GW.section(_("Sort"), W) },
            entry("leaf.gw.arrow-down-a-z", _("A to Z"), "strcoll"),
            entry("leaf.gw.arrow-up-z-a", _("Z to A"), "strcoll", true),
            entry("leaf.gw.arrow-down-1-0", _("A to Z, numbers in order"), "natural"),
            entry("leaf.gw.arrow-up-1-0", _("Z to A, numbers in order"), "natural", true) }
        pop = GW.Popover:new{ content = content, anchor = anchor, align = "right" }
        UIManager:show(pop)
        self._leaf_menu = pop
    end

    L.wrap(SortWidget, "init", function(orig, self)
        self.width, self.height = nil, nil -- a full page
        orig(self)
        self._leaf = true
        self._leaf_footer = is_footer(self)
        self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        if self._leaf_footer and self.callback then
            -- Save also applies the on/off checks to the status bar
            local cb = self.callback
            self.callback = function(this, ...)
                pcall(function()
                    local footer = require("apps/reader/readerui").instance.view.footer
                    for _i, item in ipairs(self.item_table) do footer.settings[item.label] = not item.dim end
                end)
                return cb(this, ...)
            end
        end
        self:_populateItems()
    end, "SortWidget:init")

    L.wrap(SortWidget, "onShowWidgetMenu", function(orig, self)
        if not self._leaf then return orig(self) end
        show_sort_menu(self, self._leaf_sort_btn and self._leaf_sort_btn.dimen)
        return true
    end, "SortWidget:onShowWidgetMenu")

    L.wrap(SortWidget, "sortItems", function(orig, self, ...)
        orig(self, ...)
        if self._leaf then
            self.marked = 0 -- (KOReader marks item 1 to enable its cancel button: Leaf has Undo)
            self:_populateItems()
        end
    end, "SortWidget:sortItems")

    L.wrap(SortWidget, "_populateItems", function(orig, self)
        if not self._leaf then return orig(self) end
        local W, H = Screen:getWidth(), Screen:getHeight()
        local hm = human(self.title)
        local sort_btn
        if not self.sort_disabled then
            sort_btn = GW.icon_btn{ icon = "leaf.gw.arrow-down-a-z", callback = function() self:onShowWidgetMenu() end }
            self._leaf_sort_btn = sort_btn
        end
        local crumb = hm.crumb
        if self.title == _("Arrange books in collection") then
            -- the open collection's name (FileManagerCollection keeps it as the book list's path)
            pcall(function()
                local fmc = require("apps/filemanager/filemanager").instance.collections
                local name = fmc.booklist_menu.path
                crumb = fmc.getCollectionTitle and fmc:getCollectionTitle(name) or name
            end)
        end
        local head = GW.page_head{ width = W, title = hm.title or self.title, crumb = crumb,
            on_back = function() self:onClose() end, actions = { sort_btn } }
        local has_checks = false
        for _i, it in ipairs(self.item_table) do
            if check_state(self, it) ~= nil then has_checks = true break end
        end
        local help
        if self.sort_disabled then
            help = _("Tap an item to change it.")
        elseif self.marked > 0 then
            help = _("Move the selected item with the arrows below, or tap another item.")
        else
            help = _("Tap an item, then move it up or down.") .. (has_checks and (" " .. _("The check shows or hides it.")) or "")
        end
        local help_w = GW.help(help, W)
        local foot
        if self.marked > 0 then
            local n = #self.item_table
            local item = self.item_table[self.marked]
            foot = GW.foot{ width = W, gap = 0,
                left = { GW.text(item.text or "", "ui-semibold", "fs-sm", "text", W * 0.34) },
                right = {
                    GW.icon_btn{ icon = "leaf.gw.chevrons-up", enabled = self.marked > 1, callback = function() self:moveItem(1 - self.marked) end },
                    GW.icon_btn{ icon = "leaf.gw.chevron-up", enabled = self.marked > 1, callback = function() self:moveItem(-1) end },
                    GW.icon_btn{ icon = "leaf.gw.chevron-down", enabled = self.marked < n, callback = function() self:moveItem(1) end },
                    GW.icon_btn{ icon = "leaf.gw.chevrons-down", enabled = self.marked < n, callback = function() self:moveItem(n - self.marked) end },
                    GW.hspan("sp-2"),
                    GW.button{ label = _("Done"), kind = "secondary", callback = function() self.marked = 0 self:_populateItems() end },
                } }
        else
            local dirty = self.orig_item_table ~= nil
            foot = GW.foot{ width = W,
                left = { GW.button{ label = _("Undo changes"), icon = "leaf.gw.undo-2", kind = "ghost", enabled = dirty,
                    callback = function() self:onCancel() end } },
                right = {
                    GW.button{ label = _("Close"), kind = "ghost", callback = function() self:onClose() end },
                    GW.button{ label = _("Save"), kind = "primary", enabled = dirty or self.sort_disabled,
                        callback = function() self.marked = 0 self:onReturn() end },
                } }
        end
        -- pages: as many rows as fit between the help line and the footer
        local avail = H - head:getSize().h - help_w:getSize().h - foot:getSize().h - T.px("sp-3")
        local rows, heights = {}, {}
        for idx = 1, #self.item_table do
            rows[idx] = row(self, idx, W)
            heights[idx] = rows[idx]:getSize().h + T.px("hairline")
        end
        local pages, start, used = { 1 }, 1, 2 * T.px("hairline")
        for idx = 1, #self.item_table do
            if used + heights[idx] > avail and idx > start then
                table.insert(pages, idx)
                start, used = idx, 2 * T.px("hairline")
            end
            used = used + heights[idx]
        end
        -- one more pass with room for the pager when several pages
        if #pages > 1 then
            avail = avail - T.px("hit")
            pages, start, used = { 1 }, 1, 2 * T.px("hairline")
            for idx = 1, #self.item_table do
                if used + heights[idx] > avail and idx > start then
                    table.insert(pages, idx)
                    start, used = idx, 2 * T.px("hairline")
                end
                used = used + heights[idx]
            end
        end
        self.pages = #pages
        if self.marked > 0 then
            for p = #pages, 1, -1 do
                if self.marked >= pages[p] then self.show_page = p break end
            end
        end
        self.show_page = math.max(1, math.min(self.show_page or 1, self.pages))
        self.items_per_page = (pages[2] or (#self.item_table + 1)) - 1
        local first, last = pages[self.show_page], (pages[self.show_page + 1] or (#self.item_table + 1)) - 1
        local page_rows = {}
        for idx = first, last do table.insert(page_rows, rows[idx]) end
        local body = VerticalGroup:new{ align = "left", head, help_w }
        if #page_rows > 0 then table.insert(body, GW.group(page_rows, W)) end
        local bottom = VerticalGroup:new{ align = "left" }
        if self.pages > 1 then
            local pager = HorizontalGroup:new{ align = "center",
                GW.icon_btn{ icon = "leaf.gw.chevron-up", enabled = self.show_page > 1, callback = function() self:prevPage() end },
                GW.text(string.format("%d / %d", self.show_page, self.pages), "ui", "fs-sm", "text-2"),
                GW.icon_btn{ icon = "leaf.gw.chevron-down", enabled = self.show_page < self.pages, callback = function() self:nextPage() end } }
            table.insert(bottom, CenterContainer:new{ dimen = GW.geom(W, T.px("hit")), pager })
        end
        table.insert(bottom, foot)
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg"),
            width = W, height = H,
            OverlapGroup:new{ dimen = GW.geom(W, H), body, BottomContainer:new{ dimen = GW.geom(W, H), bottom } } }
        UIManager:setDirty(self, function() return "ui", self.dimen end)
    end, "SortWidget:_populateItems")
end

return M
