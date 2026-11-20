--[[
    Leaf folder / file chooser (Gaps › path-chooser, path-confirm): KOReader's PathChooser (download
    folder, custom cover image, folder shortcuts, collections' connected folders, cloud downloads,
    text editor, screensaver image…).

    A full page: status strip, page header (crumb = the last folders of the path, the purpose as the
    title, ← back; HOME, folder shortcuts, and New folder when a folder is wanted), then the folder
    as a list: "Up one level" (+ the parent path), folders (count of items, chevron), files (size;
    "tap to choose" when choosable, dimmed when not). Foot (.gp-foot):
      * folder wanted: the current path + "n folders · m files", [Cancel] [Use this folder].
      * file wanted: "Tap a file to choose it" (+ what can be chosen), [Cancel].
    Choosing a file asks "Choose this file?" (a .ko-dialog: file name, Folder / Size / Modified,
    [Cancel] [Choose]); a long-press on a folder asks "Choose this folder?". KOReader's
    behaviour is kept: onConfirm(path), changeToPath, goHome, folder shortcuts, New folder, paging.
--]]
local Device = require("device")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

local IMAGE = { jpg = true, jpeg = true, png = true, gif = true, webp = true, svg = true, bmp = true, tif = true, tiff = true }
local ARCHIVE = { zip = true, cbz = true, rar = true, cbr = true, ["7z"] = true, cb7 = true, tar = true, gz = true }

-- "286 KB", "1.2 MB" (the prototype's sizes; KOReader writes "292.9 kB")
local function size_of(n)
    n = n or 0
    if n < 1024 then return string.format("%d B", n) end
    if n < 1024 * 1024 then return string.format("%d KB", math.floor(n / 1024 + 0.5)) end
    local s = string.format("%.1f", n / (1024 * 1024)):gsub("%.0$", "")
    return s .. " MB"
end

local function ext(name) return (name:match("%.([%w]+)$") or ""):lower() end

function M.apply(L)
    local T = L.T
    local GW = require("leaf/widgets/gwkit")(L)
    local PathChooser = require("ui/widget/pathchooser")
    local util = require("util")
    local ffiUtil = require("ffi/util")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local geom = GW.geom

    local function images_only(self)
        if not self.file_filter then return false end
        local ok, a = pcall(self.file_filter, "x.jpg")
        local ok2, b = pcall(self.file_filter, "x.epub")
        return ok and ok2 and a and not b
    end

    local function title_of(self)
        if self.leaf_title then return self.leaf_title end
        if type(self.title) == "string" and not self.title:find(_("Long-press"), 1, true) then return self.title end
        if self.select_directory and not self.select_file then return _("Choose a folder") end
        if self.select_file and not self.select_directory then
            return images_only(self) and _("Choose an image") or _("Choose a file")
        end
        return _("Choose a file or folder")
    end

    local function count_items(path)
        local n = 0
        local ok, iter, dir = pcall(lfs.dir, path)
        if not ok then return 0 end
        for f in iter, dir do
            if f ~= "." and f ~= ".." and not f:match("^%.") then n = n + 1 end
        end
        return n
    end

    local function crumb_of(path)
        local segs = {}
        for s in path:gmatch("[^/]+") do table.insert(segs, s) end
        local from = math.max(1, #segs - 2)
        return table.concat(segs, " › ", from)
    end

    -- "Choose this file?" / "Choose this folder?" (KOReader's PathChooser:onMenuHold, as a .ko-dialog)
    local function confirm(self, path)
        local attr = lfs.attributes(path)
        if not attr then return end
        local dir, name = util.splitFilePathName(path)
        local pairs_ = { { _("Folder"), (dir:gsub("/$", "")) } }
        if attr.mode == "file" then
            table.insert(pairs_, { _("Size"), size_of(attr.size) })
            table.insert(pairs_, { _("Modified"), os.date("%b %d, %H:%M", attr.modification) })
        else
            name = name ~= "" and name or path
        end
        local onConfirm = self.onConfirm
        UIManager:show(GW.Dialog:new{
            title = attr.mode == "file" and _("Choose this file?") or _("Choose this folder?"),
            sub = name,
            body = GW.kv(pairs_, GW.dialog_inner()),
            actions = {
                { label = _("Cancel"), kind = "ghost" },
                { label = _("Choose"), kind = "primary", callback = function()
                    if onConfirm then onConfirm(path) end
                    UIManager:close(self)
                end },
            },
        })
    end

    local function render(self)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local folder_mode = self.select_directory and not self.select_file
        local actions = {
            GW.icon_btn{ icon = "leaf.gw.house", callback = function() self:goHome() end },
            GW.icon_btn{ icon = "leaf.gw.folder-symlink", callback = function()
                local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
                FileManagerShortcuts:onShowFolderShortcutsDialog(function(path) self:changeToPath(path) end)
            end },
        }
        if self.select_directory then
            table.insert(actions, GW.icon_btn{ icon = "leaf.gw.folder-plus", callback = function()
                local FileManager = require("apps/filemanager/filemanager")
                FileManager.file_chooser = self
                FileManager:createFolder()
            end })
        end
        local head = GW.page_head{ width = W, title = title_of(self), crumb = crumb_of(self.path or "/"),
            on_back = function() self:onClose() end, actions = actions }

        local rows, nd, nf = {}, 0, 0
        for _i, item in ipairs(self.item_table or {}) do
            local path = item.path or ""
            if path:sub(-2) == "/." then -- "Long-press here to choose current folder": the foot does it
                goto continue
            end
            if item.is_go_up then
                local parent = ffiUtil.realpath((self.path or "") .. "/..") or "/"
                table.insert(rows, { icon = "leaf.gw.corner-left-up", label = _("Up one level"), sub = parent,
                    callback = function() self:onMenuSelect(item) end })
            elseif item.is_file then
                nf = nf + 1
                local name = item.text
                local e = ext(name)
                local ok_file = self.select_file
                local size = size_of(item.attr and item.attr.size)
                table.insert(rows, { icon = IMAGE[e] and "leaf.gw.file-image" or ARCHIVE[e] and "leaf.gw.file-archive" or "leaf.gw.file",
                    label = name, sub = ok_file and (size .. " · " .. _("tap to choose")) or size, disabled = not ok_file,
                    callback = function() self:onMenuHold(item) end, hold_callback = function() self:onMenuHold(item) end })
            else
                nd = nd + 1
                local name = item.text:gsub("/$", "")
                local n = count_items(path)
                table.insert(rows, { icon = "leaf.gw.folder", label = name,
                    sub = string.format(n == 1 and _("%d item") or _("%d items"), n), chevron = true,
                    callback = function() self:onMenuSelect(item) end,
                    hold_callback = self.select_directory and function() self:onMenuHold(item) end or nil })
            end
            ::continue::
        end

        -- folder choosers hide files (show_files = false): list them dimmed, as the prototype does
        if not self.show_files and self.path then
            local names = {}
            local ok, iter, dir = pcall(lfs.dir, self.path)
            if ok then
                for f in iter, dir do
                    if not f:match("^%.") and lfs.attributes(self.path .. "/" .. f, "mode") == "file" then table.insert(names, f) end
                end
            end
            table.sort(names)
            for _i, f in ipairs(names) do
                nf = nf + 1
                local e = ext(f)
                table.insert(rows, { icon = IMAGE[e] and "leaf.gw.file-image" or ARCHIVE[e] and "leaf.gw.file-archive" or "leaf.gw.file",
                    label = f, sub = size_of(lfs.attributes(self.path .. "/" .. f, "size")), disabled = true })
            end
        end

        -- foot
        local foot
        if folder_mode or self.select_directory and not self.select_file then
            local tw = W * 0.5
            local col = VerticalGroup:new{ align = "left",
                GW.text(self.path or "", "ui", "fs-sm", "text", tw), GW.vspan("sp-half"),
                GW.text(string.format(_("%d folders · %d files"), nd, nf), "ui", "fs-xs", "text-3", tw) }
            foot = GW.foot{ width = W, left = { col }, right = {
                GW.button{ label = _("Cancel"), kind = "ghost", callback = function() self:onClose() end },
                GW.button{ label = _("Use this folder"), kind = "primary", callback = function()
                    local onConfirm = self.onConfirm
                    local path = self.path
                    UIManager:close(self)
                    if onConfirm then onConfirm(path) end
                end } } }
        else
            local imgs = images_only(self)
            local col = VerticalGroup:new{ align = "left",
                GW.text(imgs and _("Tap an image to choose it") or _("Tap a file to choose it"), "ui", "fs-sm", "text", W * 0.6) }
            local what = imgs and _("Only images can be chosen")
                or (self.file_filter and _("Only matching files are listed"))
                or (self.select_directory and _("Long-press a folder to choose it")) or nil
            if what then
                table.insert(col, GW.vspan("sp-half"))
                table.insert(col, GW.text(what, "ui", "fs-xs", "text-3", W * 0.6))
            end
            foot = GW.foot{ width = W, left = { col }, right = {
                GW.button{ label = _("Cancel"), kind = "ghost", callback = function() self:onClose() end } } }
        end

        -- rows that fit, the rest on the next pages
        local built = {}
        for i, r in ipairs(rows) do
            r.width = W
            built[i] = GW.row(r)
        end
        local row_h = T.px("h-row")
        for _i, b in ipairs(built) do row_h = math.max(row_h, b:getSize().h + T.px("hairline")) end
        local avail = H - head:getSize().h - foot:getSize().h
        local per = math.max(1, math.floor(avail / row_h))
        if #built > per then per = math.max(1, math.floor((avail - T.px("hit")) / row_h)) end
        self.perpage = per
        self.page_num = math.max(1, math.ceil(#built / per))
        self.page = math.max(1, math.min(self.page or 1, self.page_num))
        local list = {}
        for i = (self.page - 1) * per + 1, math.min(#built, self.page * per) do table.insert(list, built[i]) end

        local body = VerticalGroup:new{ align = "left", head }
        if #list > 0 then
            -- .ko-list.inset: separators start at the label (52px)
            local inset = T.px("sp-5") + T.px("icon-md") + T.px("sp-3")
            local g = VerticalGroup:new{ align = "left" }
            for i, r in ipairs(list) do
                if i > 1 then table.insert(g, HorizontalGroup:new{ GW.hspan(inset), GW.line(W - inset) }) end
                table.insert(g, r)
            end
            table.insert(body, g)
        else
            table.insert(body, CenterContainer:new{ dimen = geom(W, avail / 2),
                VerticalGroup:new{ align = "center", GW.icon("leaf.lib.folderopen", "icon-2xl", "text-3"), GW.vspan("sp-3"),
                    GW.text(_("Empty folder"), "ui-semibold", "fs-head", "text"), GW.vspan("sp-1"),
                    GW.text(_("Nothing inside yet."), "ui", "fs-sm", "text-3") } })
        end
        local bottom = VerticalGroup:new{ align = "left" }
        if self.page_num > 1 then
            table.insert(bottom, CenterContainer:new{ dimen = geom(W, T.px("hit")), HorizontalGroup:new{ align = "center",
                GW.icon_btn{ icon = "leaf.gw.chevron-up", enabled = self.page > 1, callback = function() self:onPrevPage() end },
                GW.text(string.format("%d / %d", self.page, self.page_num), "ui", "fs-sm", "text-2"),
                GW.icon_btn{ icon = "leaf.gw.chevron-down", enabled = self.page < self.page_num, callback = function() self:onNextPage() end } } })
        end
        table.insert(bottom, foot)
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg"), width = W, height = H,
            OverlapGroup:new{ dimen = geom(W, H), body, BottomContainer:new{ dimen = geom(W, H), bottom } } }
        UIManager:setDirty(self, "ui")
    end

    L.wrap(PathChooser, "init", function(orig, self)
        if PathChooser._leaf_title then
            self.leaf_title = PathChooser._leaf_title
            PathChooser._leaf_title = nil
        end
        orig(self)
        self._leaf = true
        self.covers_fullscreen = true
        self.updateItems = function(this) render(this) end
        render(self)
    end, "PathChooser:init")

    L.wrap(PathChooser, "onMenuHold", function(orig, self, item)
        if not self._leaf then return orig(self, item) end
        local path = item.path
        if path:sub(-2) == "/." then path = path:sub(1, -3) end
        path = ffiUtil.realpath(path)
        if not path then return true end
        local attr = lfs.attributes(path)
        if not attr then return true end
        if attr.mode == "file" and not self.select_file then return true end
        if attr.mode == "directory" and not self.select_directory then return true end
        confirm(self, path)
        return true
    end, "PathChooser:onMenuHold")

    -- purposes KOReader doesn't name (its title is "Long-press … to choose it")
    local function titled(mod, method, title)
        local ok, Class = pcall(require, mod)
        if not ok or not Class[method] then return end
        L.wrap(Class, method, function(orig, ...)
            PathChooser._leaf_title = title
            local ok2, ret = pcall(orig, ...)
            PathChooser._leaf_title = nil
            if not ok2 then error(ret, 0) end
            return ret
        end, mod .. ":" .. method)
    end
    titled("ui/downloadmgr", "chooseDir", _("Choose download folder"))
    titled("apps/filemanager/filemanagerbookinfo", "setCustomCover", _("Choose a cover image"))
end

return M
