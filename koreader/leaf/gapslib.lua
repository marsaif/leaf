--[[
    Leaf gaps · library (prototype group "Gaps", js/screens/gaps.js): the library surfaces the first
    pass left on KOReader's generic widgets, reimplemented as Leaf pages and sheets. KOReader's own
    code still does the work (selection, collection settings, metadata, extraction): only the screens
    are Leaf's.

      * Select mode › Show selected files list (FileManager:showSelectedFilesList) -> page
        "selected-files": ← Library › Select mode / Selected files · N, help line, a list of
        thumb · file name · folder · × (deselect); tap = show the file in its folder (KOReader);
        footer Deselect all · Done.
      * Collections › Connect folders (FileManagerCollection:showCollFolderList) -> page
        "coll-folders": connected folders (subfolders / checked-on-open in the sub line, ⋮ = the
        folder sheet), ONLY ADD: File types (KOReader's input) · Reading status (sheet below);
        footer Close · Connect a folder (KOReader's PathChooser).
        Folder options (onCollFolderListHold) -> sheet "coll-folder": Include subfolders,
        Check for new books when the collection opens (toggles), Disconnect folder.
        Filter by status (showCollFilterStatusDialog) -> sheet "coll-status": four checks,
        Clear filter · Done.
      * Book information › hold a field / the cover (BookInfo:showCustomDialog) -> sheet
        "meta-field": Edit… · Copy original · View original · Reset to original; the cover:
        View cover · Choose another image… · View the book's own cover · Remove custom cover.
      * Archive viewer (plugin archiveviewer: openFile, showMenu, showFileDialog,
        extractAllDialog) -> page "archive" (crumb = the archive's folder, Up row, folders with
        their counts, files with their sizes, ⋮ popover "Extract all files…"), sheet
        "archive-file" (View · Extract to <folder> · Extract to…), dialog "archive-extract".
        Viewing images keeps KOReader's ImageViewer (ported with the generic widgets); Leaf only
        gives it the archive's title line through leaf/imageviewer.lua's M.next: the image name as
        title (updated when flipping), sub = "archive.zip › folder", on a --page card.
      * OPDS page streaming (opdspse.streamPages): the same title line for the ImageViewer:
        the publication title and "Page stream · <catalog>" (sub), on a --page card.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local Kit = require("leaf/widgets/kit")
    local P = require("leaf/widgets/libparts")
    local LeafToggle = require("leaf/widgets/toggle")
    local geom = K.geom

    ------------------------------------------------------------------ building blocks
    local function tint(icon, color, size)
        return Kit.TintIcon:new{ icon = icon, size_token = size or "icon-md", color = T.color(color or "text-2") }
    end
    local function basename(p) return (p:gsub("/+$", ""):match("([^/]+)$")) or p end

    -- .ko-icon-btn: a 44px hit box around a 20px --text-2 icon
    local function icon_btn(icon, cb, color)
        local hit = T.px("hit")
        return K.tap(CenterContainer:new{ dimen = geom(hit, hit), tint(icon, color or "text-2") }, cb)
    end

    -- .ko-row: [lead] label (+ sub) … [value] [trailing]; o.trail_pad = right padding of the trailing
    local function row(o)
        local W = o.width
        local pad = o.pad or T.px("sp-5")
        local gap = T.px("sp-3")
        local fg = o.disabled and "disabled" or (o.danger and "danger" or "text")
        local lead = o.lead or (o.icon and tint(o.icon, o.disabled and "disabled" or (o.danger and "danger" or "text-2")))
        local lead_w = lead and (lead:getSize().w + gap) or 0
        local trailing = o.trailing
        local trail_pad = o.trail_pad or pad
        if o.value then
            local v = K.text(o.value, "ui", "fs-sm", o.disabled and "disabled" or "text-3", math.floor(W * 0.45))
            if trailing then
                trailing = HorizontalGroup:new{ align = "center", v, K.hspan("sp-3"), trailing }
            else
                trailing = v
            end
        end
        local trail_w = trailing and (trailing:getSize().w + gap) or 0
        local tw = W - pad - trail_pad - lead_w - trail_w
        local col = VerticalGroup:new{ align = "left", K.text(o.label, "ui", "fs-md", fg, tw) }
        if o.sub and o.sub ~= "" then
            table.insert(col, K.vspan("sp-half"))
            table.insert(col, K.text(o.sub, "ui", "fs-sm", o.disabled and "disabled" or "text-3", tw))
        end
        local h = math.max(o.height or T.px("h-row"), col:getSize().h + 2 * T.px("sp-2"),
            lead and (lead:getSize().h + 2 * T.px("sp-2")) or 0)
        col:resetLayout()
        local left = HorizontalGroup:new{ align = "center", K.hspan(pad) }
        if lead then
            table.insert(left, lead)
            table.insert(left, K.hspan(gap))
        end
        table.insert(left, col)
        local body = OverlapGroup:new{ dimen = geom(W, h), LeftContainer:new{ dimen = geom(W, h), left } }
        if trailing then
            table.insert(body, RightContainer:new{ dimen = geom(W, h),
                HorizontalGroup:new{ align = "center", trailing, K.hspan(trail_pad) } })
        end
        if o.disabled or not (o.callback or o.hold) then return body end
        return K.tap(body, o.callback, o.hold)
    end

    local function chevron() return tint("leaf.lib.chevright", "text-3") end
    -- .ko-check: 20px, --r-check; off = --border-strong --bw-md outline, on = accent fill + --accent-ink tick
    local Check = require("ui/widget/widget"):extend{ on = false }
    function Check:init()
        local s = T.px("icon-md")
        self.dimen = geom(s, s)
        if self.on then
            self._tick = Kit.TintIcon:new{ icon = "leaf.lib.check.bold", size_token = "icon-xs", color = T.color("accent-ink") }
        end
    end
    function Check:getSize() return self.dimen end
    function Check:paintTo(bb, x, y)
        local s = self.dimen.w
        self.dimen.x, self.dimen.y = x, y
        local r = T.px("r-check")
        if self.on then
            bb:paintRoundedRect(x, y, s, s, T.color("accent"), r)
            local t = self._tick:getSize().w
            self._tick:paintTo(bb, x + math.floor((s - t) / 2), y + math.floor((s - t) / 2))
        else
            bb:paintBorder(x, y, s, s, T.px("bw-md"), T.color("border-strong"), r)
        end
    end
    local function check(on) return Check:new{ on = on } end

    -- .ko-group: rows in a --surface card, --sp-4 side margins, separators from --sp-4
    local function group(make_rows, W)
        local cw = W - 2 * T.px("sp-4")
        local inner = cw - 2 * T.px("hairline")
        local list = K.list(make_rows(inner, T.px("sp-4")), inner, { inset = T.px("sp-4"), inset_right = 0 })
        return HorizontalGroup:new{ K.hspan("sp-4"), K.card(cw, list, { flush = true }) }
    end

    -- .ko-list.inset: full-width rows, separators from 52px (--sp-5 + icon + --sp-3)
    local function inset_list(rows, W)
        return K.list(rows, W, { inset = T.px("sp-5") + T.px("icon-md") + T.px("sp-3"), inset_right = 0 })
    end

    -- .gp-help / .gp-pm-src
    local function help(text, W)
        local pad = T.px("sp-5")
        return VerticalGroup:new{ K.vspan("sp-3"),
            HorizontalGroup:new{ K.hspan(pad), K.textbox(text, "ui", "fs-sm", "text-3", W - 2 * pad) }, K.vspan("sp-3") }
    end
    local function src_line(icon, text, W)
        local h = T.px("sp-3") * 2 + K.text("Ag", "ui", "fs-sm"):getSize().h
        return LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", K.hspan("sp-5"),
            tint(icon, "text-3", "icon-sm"), K.hspan("sp-2"), K.text(text, "ui", "fs-sm", "text-3", W - 2 * T.px("sp-5")) } }
    end
    local function section(text, W)
        local pad = T.px("sp-5")
        return VerticalGroup:new{ align = "left", K.vspan("sp-4"),
            HorizontalGroup:new{ K.hspan(pad), K.text(text:upper(), "ui-semibold", "fs-xs", "text-3") }, K.vspan("sp-2") }
    end

    -- UI.pageHead: ← [crumbs over an Inter --fs-lg title] … actions, rule under
    local function page_head(o)
        local W = o.width
        local pad = T.px("sp-2")
        local right = HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(o.actions or {}) do table.insert(right, a) end
        table.insert(right, K.hspan(pad))
        local rw = right:getSize().w
        right:resetLayout()
        local back = icon_btn("leaf.kb.left", o.back)
        local lw = pad + back:getSize().w + T.px("sp-1")
        local tw = W - lw - rw
        local col = VerticalGroup:new{ align = "left" }
        if o.crumbs then
            table.insert(col, K.text(table.concat(o.crumbs, "  ›  "), "ui", "fs-xs", "text-3", tw))
            table.insert(col, K.vspan("sp-half"))
        end
        table.insert(col, K.text(o.title, "ui-semibold", "fs-lg", "text", tw))
        local h = math.max(P.px(64), col:getSize().h + 2 * pad)
        col:resetLayout()
        local g = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", K.hspan(pad), back, K.hspan("sp-1"), col } },
            RightContainer:new{ dimen = geom(W, h), right } }
        return VerticalGroup:new{ g, K.line(W) }
    end

    -- .gp-foot: hairline, --bg-raised, --sp-3 --sp-4 padding; left widgets … right widgets
    local function foot(left, right, W, compact)
        local h = T.px("h-control") + 2 * T.px("sp-3")
        if compact then h = K.text("Ag", "ui", "fs-sm"):getSize().h + 2 * T.px("sp-3") end
        local lg = HorizontalGroup:new{ align = "center", K.hspan("sp-4") }
        for i, w in ipairs(left or {}) do
            if i > 1 then table.insert(lg, K.hspan("sp-2")) end
            table.insert(lg, w)
        end
        local rg = HorizontalGroup:new{ align = "center" }
        local n = 0
        for i = 1, right and table.maxn(right) or 0 do -- may hold a nil (no page label)
            local w = right[i]
            if w then
                if n > 0 then table.insert(rg, K.hspan("sp-2")) end
                table.insert(rg, w)
                n = n + 1
            end
        end
        table.insert(rg, K.hspan("sp-4"))
        return VerticalGroup:new{ K.line(W),
            FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg-raised"),
                OverlapGroup:new{ dimen = geom(W, h),
                    LeftContainer:new{ dimen = geom(W, h), lg },
                    RightContainer:new{ dimen = geom(W, h), rg } } } }
    end
    local function ghost(label, cb) return K.button{ label = label, kind = "ghost", callback = cb } end
    local function primary(label, cb, icon)
        if icon then return Kit.icon_label_button{ icon = icon, label = label, kind = "primary", callback = cb } end
        return K.button{ label = label, kind = "primary", callback = cb }
    end

    -- rows paged to fit `avail` height (KOReader can't scroll a group): returns pages of rows
    local function paginate(rows, avail)
        local pages, cur, used = {}, {}, 0
        local sep = T.px("hairline")
        for _i, r in ipairs(rows) do
            local h = r:getSize().h + sep
            if #cur > 0 and used + h > avail then
                table.insert(pages, cur)
                cur, used = {}, 0
            end
            table.insert(cur, r)
            used = used + h
        end
        if #cur > 0 or #pages == 0 then table.insert(pages, cur) end
        return pages
    end

    ------------------------------------------------------------------ page shell
    local Page = K.Page:extend{ page = 1 }
    -- o = { head, top = {widgets}, rows = {rows, paged}, after = {widgets below the rows},
    --       list = fn(page_rows) -> widget (default: .ko-list.inset), footer = fn(page_label) -> widget }
    function Page:compose(o)
        local W, H = Screen:getWidth(), Screen:getHeight()
        local above = VerticalGroup:new{ align = "left", Kit.status_strip(W), o.head }
        for _i, w in ipairs(o.top or {}) do table.insert(above, w) end
        local after_h = 0
        for _i, w in ipairs(o.after or {}) do after_h = after_h + w:getSize().h end
        local footer = o.footer and o.footer(nil)
        local fh = footer and footer:getSize().h or 0
        local avail = H - above:getSize().h - after_h - fh - T.px("sp-3")
        above:resetLayout()
        local pages = paginate(o.rows or {}, avail)
        self.npages = #pages
        self.page = math.max(1, math.min(self.page or 1, self.npages))
        if self.npages > 1 and o.footer then footer = o.footer(self:pageLabel()) end
        table.insert(above, (o.list or function(r) return inset_list(r, W) end)(pages[self.page]))
        for _i, w in ipairs(o.after or {}) do table.insert(above, w) end
        self:frame(above, footer)
        self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = geom(W, H) } }
    end
    function Page:onSwipe(_a, ges)
        local d = ges and ges.direction
        if not self.npages or self.npages < 2 then return end
        local p = self.page
        if d == "west" or d == "north" then p = math.min(self.npages, p + 1)
        elseif d == "east" or d == "south" then p = math.max(1, p - 1) end
        if p ~= self.page then
            self.page = p
            self:rebuild()
        end
        return true
    end
    function Page:pageLabel()
        if (self.npages or 1) < 2 then return nil end
        return K.text(string.format(_("Page %d of %d"), self.page, self.npages), "ui", "fs-sm", "text-3")
    end

    ------------------------------------------------------------------ sheet shell
    -- Sheet:new{ make = function(sheet, inner_width) return content end }
    local Sheet = InputContainer:extend{ _leaf_wants_scrim = true }
    function Sheet:init()
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end
    function Sheet:build()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local inner = W - 2 * T.px("hairline")
        local frame, bottom = K.sheet(self:make(inner), W)
        self.sheet = frame
        self[1] = bottom
        self.dimen = geom(W, H)
        self.ges_events = { TapOut = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    function Sheet:rebuild()
        self:build()
        UIManager:setDirty("all", "ui")
    end
    function Sheet:onTapOut(_a, ges)
        if self.sheet.dimen and ges.pos:notIntersectWith(self.sheet.dimen) then UIManager:close(self) end
        return true
    end
    function Sheet:onClose() UIManager:close(self) return true end
    function Sheet:onShow() UIManager:setDirty(self, "ui") return true end
    function Sheet:onCloseWidget() UIManager:setDirty(nil, "ui") end

    -- .ko-sheet-head--rule with a leading tile / cover: [lead] title + sub … ×, hairline under
    local function sheet_head_lead(o)
        local W = o.width
        local close = K.icon_button("close", o.close)
        local rw = close:getSize().w + T.px("sp-3") - T.px("sp-1")
        local lw = T.px("sp-5") + o.lead:getSize().w + T.px("sp-3")
        local tw = W - lw - rw - T.px("sp-2")
        local col = VerticalGroup:new{ align = "left", K.text(o.title, "ui-semibold", "fs-head", "text", tw) }
        if o.sub and o.sub ~= "" then
            table.insert(col, K.vspan("sp-half"))
            table.insert(col, K.text(o.sub, "ui", "fs-sm", "text-3", tw))
        end
        local ch = math.max(o.lead:getSize().h, col:getSize().h, T.px("hit"))
        col:resetLayout()
        local inner = OverlapGroup:new{ dimen = geom(W, ch),
            LeftContainer:new{ dimen = geom(W, ch), HorizontalGroup:new{ align = "center", K.hspan("sp-5"), o.lead, K.hspan("sp-3"), col } },
            RightContainer:new{ dimen = geom(W, ch), HorizontalGroup:new{ align = "center", close, K.hspan(T.px("sp-3") - T.px("sp-1")) } } }
        return VerticalGroup:new{ K.vspan("sp-1"), inner, K.vspan("sp-3"), K.line(W) }
    end
    -- action sheet body: groups separated by --sp-3 (.gp-gap), --sp-3 + --sp-1 at the end
    local function sheet_body(head, groups, extra, W)
        local g = VerticalGroup:new{ align = "left", head }
        for i, grp in ipairs(groups) do
            if i > 1 then table.insert(g, K.vspan("sp-3")) end
            table.insert(g, grp)
        end
        for _i, w in ipairs(extra or {}) do table.insert(g, w) end
        table.insert(g, K.vspan(T.px("sp-3") + T.px("sp-1")))
        return g
    end
    local function note(text, W) -- .gp-note: info icon + --fs-xs --text-3
        local pad = T.px("sp-5")
        local s = T.px("icon-sm")
        return VerticalGroup:new{ K.vspan("sp-3"), HorizontalGroup:new{ align = "top", K.hspan(pad), tint("leaf.lib.info", "text-3", "icon-sm"),
            K.hspan("sp-2"), K.textbox(text, "ui", "fs-xs", "text-3", W - 2 * pad - s - T.px("sp-2"), "bg-raised") } }
    end

    ------------------------------------------------------------------ dialog (UI.dialog with a 3-button row)
    local Dialog = InputContainer:extend{ _leaf_wants_scrim = true }
    function Dialog:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local dw = math.min(math.floor(W * 0.86), P.px(400))
        local pad = T.px("sp-5")
        local inner = dw - 2 * pad - 2 * T.px("hairline")
        local close = function() UIManager:close(self) end
        local function act(a)
            return K.button{ label = a.label, kind = a.kind or "ghost", callback = function()
                close()
                if a.callback then a.callback() end
            end }
        end
        local left = HorizontalGroup:new{ align = "center" }
        local right = HorizontalGroup:new{ align = "center" }
        for _i, a in ipairs(self.left_actions or {}) do table.insert(left, act(a)) end
        for i, a in ipairs(self.actions or {}) do
            if i > 1 then table.insert(right, K.hspan("sp-1")) end
            table.insert(right, act(a))
        end
        local ah = T.px("h-control")
        local content = VerticalGroup:new{ align = "left",
            K.textbox(self.title, "ui-semibold", "fs-head", "text", inner, "surface"),
            K.vspan("sp-1h"),
            K.textbox(self.body, "ui", "fs-md", "text-2", inner, "surface"),
            K.vspan("sp-4"),
            OverlapGroup:new{ dimen = geom(inner, ah),
                LeftContainer:new{ dimen = geom(inner, ah), left },
                RightContainer:new{ dimen = geom(inner, ah), right } },
        }
        self.frame = FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border-strong"),
            background = T.color("surface"), radius = T.px("r-lg"), padding = pad, content }
        self[1] = CenterContainer:new{ dimen = geom(W, H), self.frame }
        self.dimen = geom(W, H)
        self.ges_events = { TapOut = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
    end
    function Dialog:onTapOut(_a, ges)
        if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then UIManager:close(self) end
        return true
    end
    function Dialog:onClose() UIManager:close(self) return true end
    function Dialog:onShow() UIManager:setDirty(self, "ui") return true end
    function Dialog:onCloseWidget() UIManager:setDirty(nil, "ui") end

    ------------------------------------------------------------------ popover (.ko-popover, anchored)
    local Popover = InputContainer:extend{}
    function Popover:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pw = P.px(250)
        local inner = pw - 2 * T.px("hairline")
        local rows = VerticalGroup:new{ align = "left" }
        for _i, it in ipairs(self.items) do
            table.insert(rows, row{ width = inner, pad = T.px("sp-4"), icon = it.icon, label = it.label,
                height = T.px("h-row-compact"), callback = function()
                    UIManager:close(self)
                    it.callback()
                end })
        end
        self[1] = FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border-strong"),
            background = T.color("surface"), radius = T.px("r-lg"), padding = 0,
            padding_top = T.px("sp-2"), padding_bottom = T.px("sp-2"), rows }
        local sz = self[1]:getSize()
        self.px = math.max(0, math.min(W - sz.w - T.px("sp-2"), (self.right or W) - sz.w))
        self.py = self.top or 0
        self.dimen = geom(W, H)
        self.ges_events = { TapOut = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    function Popover:paintTo(bb)
        self[1]:paintTo(bb, self.px, self.py)
    end
    function Popover:onTapOut() UIManager:close(self) return true end
    function Popover:onClose() UIManager:close(self) return true end
    function Popover:onShow() UIManager:setDirty(self, "ui") return true end
    function Popover:onCloseWidget() UIManager:setDirty(nil, "ui") end

    ------------------------------------------------------------------ shared bits for the surfaces
    local ffiUtil = require("ffi/util")
    local T_ = ffiUtil.template
    local function tile(icon) -- .ko-icon-tile (paper: --bg on the sheet), --text-2 icon
        local s = T.px("h-chip")
        local hair = T.px("hairline")
        return FrameContainer:new{ bordersize = hair, color = T.color("border"), background = T.color("bg"),
            radius = T.px("r-md"), padding = 0,
            CenterContainer:new{ dimen = geom(s - 2 * hair, s - 2 * hair), tint(icon, "text-2", "icon-tile") } }
    end
    local function sm_pad(pad) -- trailing .ko-icon-btn--sm (32px) drawn in a 44px hit box
        return pad - math.floor((T.px("hit") - T.px("h-chip")) / 2)
    end
    local function notify(text)
        pcall(function() require("ui/widget/notification"):notify(text) end)
    end

    ------------------------------------------------------------------ 1. Select mode › selected files
    local FileManager = require("apps/filemanager/filemanager")
    local SelPage = Page:extend{}
    function SelPage:build()
        local fm = self.fm
        local W = Screen:getWidth()
        local files = {}
        for f in pairs(fm.selected_files or {}) do table.insert(files, f) end
        table.sort(files, function(a, b)
            local ap, an = util.splitFilePathName(a)
            local bp, bn = util.splitFilePathName(b)
            if ap == bp then return ffiUtil.strcoll(an, bn) end
            return ffiUtil.strcoll(ap, bp)
        end)
        local close = function() UIManager:close(self) end
        local cw, ch = P.px(32), P.px(48)
        local rows = {}
        for _i, f in ipairs(files) do
            local folder, name = util.splitFilePathName(f)
            local deselect = icon_btn("leaf.gl.x", function()
                fm.selected_files[f] = nil
                if fm.file_chooser then fm.file_chooser:refreshPath() end
                if next(fm.selected_files) == nil then close() else self:rebuild() end
            end)
            table.insert(rows, row{ width = W, label = name, sub = (folder:gsub("/$", "")),
                lead = P.coverBox(f, cw, ch, { cache_only = true, title = name }),
                trailing = deselect, trail_pad = sm_pad(T.px("sp-5")),
                callback = function()
                    close()
                    if fm.file_chooser then fm.file_chooser:changeToPath(folder, f) end
                end })
        end
        self:compose{
            head = page_head{ width = W, crumbs = { _("Library"), _("Select mode") },
                title = T_(_("Selected files · %1"), #files), back = close },
            top = { help(_("Tap a file to show it in its folder."), W) },
            rows = rows,
            footer = function(label)
                return foot({ ghost(_("Deselect all"), function()
                    close()
                    for k in pairs(fm.selected_files or {}) do fm.selected_files[k] = nil end
                    if fm.file_chooser then fm.file_chooser:selectAllFilesInFolder(false) end
                end) }, { label, primary(_("Done"), close) }, W)
            end,
        }
    end
    L.wrap(FileManager, "showSelectedFilesList", function(orig, self)
        UIManager:show(SelPage:new{ fm = self })
    end, "FileManager:showSelectedFilesList")

    ------------------------------------------------------------------ 2. Collections › connected folders, filters
    local FMC = require("apps/filemanager/filemanagercollection")
    local ReadCollection = require("readcollection")
    local BookList = require("ui/widget/booklist")
    local STATUSES = { { "new", "leaf.gl.sparkles" }, { "reading", "leaf.lib.bookopen" },
        { "abandoned", "leaf.lib.pause" }, { "complete", "leaf.lib.circlecheck" } }
    local function status_value(filter)
        if not filter then return _("Any") end
        local t = {}
        for _i, s in ipairs(STATUSES) do
            if filter[s[1]] then table.insert(t, BookList.getBookStatusString(s[1])) end
        end
        return #t > 0 and table.concat(t, ", ") or _("None")
    end
    local function coll_changed(mgr)
        if mgr._leaf_page then mgr._leaf_page:rebuild() end
    end

    -- Filter by status (ButtonSelector, multi choice) -> sheet "coll-status"
    local function show_status_sheet(mgr, item)
        local name = item.name
        local cs = ReadCollection.coll_settings[name]
        local cur = util.tableGetValue(cs, "filter", "add", "status")
        local sel = {}
        for _i, s in ipairs(STATUSES) do sel[s[1]] = cur == nil or cur[s[1]] == true end
        local function save(value)
            if value then
                util.tableSetValue(cs, value, "filter", "add", "status")
            else
                util.tableRemoveValue(cs, "filter", "add", "status")
            end
            mgr:refreshCollList(item)
        end
        UIManager:show(Sheet:new{ make = function(s, inner)
            local close = function() UIManager:close(s) end
            local head = K.sheet_head{ width = inner, title = _("Only add books that are"), sub = name, close = close,
                rule = false, parent = s }
            local grp = group(function(w, pad)
                local rows = {}
                for _i, st in ipairs(STATUSES) do
                    local key = st[1]
                    table.insert(rows, row{ width = w, pad = pad, icon = st[2], label = BookList.getBookStatusString(key),
                        trailing = check(sel[key]), callback = function()
                            sel[key] = not sel[key]
                            s:rebuild()
                        end })
                end
                return rows
            end, inner)
            local footer = foot({ ghost(_("Clear filter"), function()
                close()
                save(nil)
            end) }, { primary(_("Done"), function()
                close()
                local n, v = 0, {}
                for _i, st in ipairs(STATUSES) do
                    if sel[st[1]] then n, v[st[1]] = n + 1, true end
                end
                save(n < #STATUSES and v or nil)
            end) }, inner)
            return VerticalGroup:new{ align = "left", head, grp, K.vspan(T.px("sp-3") + T.px("sp-1")), footer }
        end })
    end

    -- folder options (onCollFolderListHold) -> sheet "coll-folder"
    local function show_folder_sheet(mgr, coll_name, folder)
        local cs = ReadCollection.coll_settings[coll_name]
        local function changed()
            mgr.updated_collections = mgr.updated_collections or {}
            mgr.updated_collections[coll_name] = true
            coll_changed(mgr)
        end
        UIManager:show(Sheet:new{ make = function(s, inner)
            local close = function() UIManager:close(s) end
            local fs = cs.folders and cs.folders[folder] or {}
            local head = sheet_head_lead{ width = inner, lead = tile("leaf.lib.symlink"), title = basename(folder),
                sub = folder, close = close }
            local g1 = group(function(w, pad) return {
                row{ width = w, pad = pad, icon = "leaf.gl.foldertree", label = _("Include subfolders"),
                    sub = _("Turning it on scans them now"), trailing = LeafToggle:new{ on = fs.subfolders and true or false },
                    callback = function()
                        if fs.subfolders then
                            fs.subfolders = false
                        else
                            fs.subfolders = true
                            ReadCollection:updateCollectionFromFolder(coll_name)
                        end
                        changed()
                        s:rebuild()
                    end },
                row{ width = w, pad = pad, icon = "leaf.gl.scansearch", label = _("Check for new books when the collection opens"),
                    trailing = LeafToggle:new{ on = fs.scan_on_show and true or false },
                    callback = function()
                        fs.scan_on_show = not fs.scan_on_show
                        changed()
                        s:rebuild()
                    end },
            } end, inner)
            local g2 = group(function(w, pad) return {
                row{ width = w, pad = pad, icon = "leaf.gl.unlink", danger = true, label = _("Disconnect folder"),
                    sub = _("Books already added stay in the collection"), callback = function()
                        close()
                        if cs.folders then
                            cs.folders[folder] = nil
                            if next(cs.folders) == nil then cs.folders = nil end
                        end
                        changed()
                    end },
            } end, inner)
            return sheet_body(head, { g1, g2 }, nil, inner)
        end })
    end

    M.show_status_sheet, M.show_folder_sheet = show_status_sheet, show_folder_sheet

    -- Connect folders (Menu) -> page "coll-folders"
    local FoldersPage = Page:extend{ _leaf = true }
    function FoldersPage:build()
        local mgr, item = self.mgr, self.item
        local coll_name = item.name
        local cs = ReadCollection.coll_settings[coll_name] or {}
        local W = Screen:getWidth()
        local gw = W - 2 * T.px("sp-4") - 2 * T.px("hairline")
        local pad = T.px("sp-4")
        local folders = {}
        for f, fs in pairs(cs.folders or {}) do table.insert(folders, { f, fs }) end
        table.sort(folders, function(a, b) return ffiUtil.strcoll(a[1], b[1]) end)
        local rows = {}
        for _i, e in ipairs(folders) do
            local f, fs = e[1], e[2]
            local sub = f .. (fs.subfolders and _(" · with subfolders") or "") .. (fs.scan_on_show and _(" · checked on open") or "")
            local opts = function() show_folder_sheet(mgr, coll_name, f) end
            table.insert(rows, row{ width = gw, pad = pad, icon = "leaf.lib.symlink", label = basename(f), sub = sub,
                trailing = icon_btn("leaf.gl.more", opts), trail_pad = sm_pad(pad), hold = opts,
                callback = function() -- KOReader: onCollFolderListChoice
                    mgr.update_files = nil
                    self:onClose()
                    if mgr.coll_list and mgr.coll_list.close_callback then mgr.coll_list.close_callback() end
                    if mgr.ui.file_chooser then
                        mgr.ui.file_chooser:changeToPath(f)
                    else
                        mgr.ui:onClose()
                        mgr.ui:showFileManager(f .. "/")
                    end
                end })
        end
        local filter = util.tableGetValue(cs, "filter", "add") or {}
        local filters = group(function(w, p) return {
            row{ width = w, pad = p, icon = "leaf.gl.filetype", label = _("File types"), value = filter.filetype or _("All"),
                trailing = chevron(), callback = function() mgr:showCollFilterTypeDialog(item) end },
            row{ width = w, pad = p, icon = "leaf.gl.bookcheck", label = _("Reading status"), value = status_value(filter.status),
                trailing = chevron(), callback = function() show_status_sheet(mgr, item) end },
        } end, W)
        local close = function() self:onClose() end
        self:compose{
            head = page_head{ width = W, crumbs = { _("Collections"), item.text or coll_name }, title = _("Connected folders"), back = close },
            top = { help(#rows > 0 and _("New books in these folders join the collection automatically.")
                or _("No folders connected yet. New books in a connected folder join the collection automatically."), W) },
            rows = rows,
            after = { section(_("Only add"), W), filters },
            list = function(page_rows)
                if #page_rows == 0 then return VerticalGroup:new{} end
                return group(function() return page_rows end, W)
            end,
            footer = function(label)
                return foot({ ghost(_("Close"), close) }, { label,
                    primary(_("Connect a folder"), function() mgr:showAddCollFolderDialog() end, "leaf.gl.folderplus") }, W)
            end,
        }
    end
    function FoldersPage:onClose()
        UIManager:close(self)
        local mgr, item = self.mgr, self.item
        if mgr.coll_folder_list == self then mgr.coll_folder_list = nil end
        if mgr._leaf_page == self then mgr._leaf_page = nil end
        -- KOReader's close_callback: a connected folder may have added books
        local cl = mgr.coll_list
        if cl and mgr.updated_collections and mgr.updated_collections[item.name] and item.idx and cl.item_table and cl.item_table[item.idx] then
            cl.item_table[item.idx].mandatory = mgr.getCollListItemMandatory(item.name)
            mgr:updateCollListItemTable()
        end
        return true
    end

    L.wrap(FMC, "showCollFolderList", function(orig, self, item)
        local page = FoldersPage:new{ mgr = self, item = item, path = item.name }
        self.coll_folder_list = page
        self._leaf_page = page
        UIManager:show(page)
    end, "FileManagerCollection:showCollFolderList")
    L.wrap(FMC, "updateCollFolderListItemTable", function(orig, self)
        if self.coll_folder_list and self.coll_folder_list._leaf then
            self.coll_folder_list:rebuild()
            return
        end
        return orig(self)
    end, "FileManagerCollection:updateCollFolderListItemTable")
    L.wrap(FMC, "showCollFilterStatusDialog", function(orig, self, item)
        show_status_sheet(self, item)
    end, "FileManagerCollection:showCollFilterStatusDialog")
    -- the filters can now be set from the folders page, where the collections list may be closed
    L.wrap(FMC, "refreshCollList", function(orig, self, item)
        local cl = self.coll_list
        if cl and item.idx and cl.item_table and cl.item_table[item.idx] then
            orig(self, item)
        else
            self.updated_collections = self.updated_collections or {}
            self.updated_collections[item.name] = true
        end
        coll_changed(self)
    end, "FileManagerCollection:refreshCollList")

    ------------------------------------------------------------------ 3. Book information › a field / the cover
    local BookInfo = require("apps/filemanager/filemanagerbookinfo")
    local function oneline(v)
        v = tostring(v or "")
        return (v:gsub("%s*\n%s*", ", "))
    end
    local function custom_cover_box(path, w, h)
        local bb
        pcall(function() bb = require("ui/renderimage"):renderImageFile(path, false) end)
        if not bb then return nil end
        local ImageWidget = require("ui/widget/imagewidget")
        local img = ImageWidget:new{ image = bb, image_disposable = true, width = w, height = h,
            scale_factor = math.max(w / bb:getWidth(), h / bb:getHeight()), center_x_ratio = 0.5, center_y_ratio = 0.5 }
        return P.CoverBox:new{ image = img, width = w, height = h, bg = T.color("bg-raised"), radius = T.px("r-thumb") }
    end
    L.wrap(BookInfo, "showCustomDialog", function(orig, self, file, book_props, prop_key)
        local sheet
        local close = function() UIManager:close(sheet) end
        if prop_key then
            local original, custom
            if self.custom_doc_settings then
                original = (self.custom_doc_settings:readSetting("doc_props") or {})[prop_key]
                custom = (self.custom_doc_settings:readSetting("custom_props") or {})[prop_key]
            else
                original = book_props[prop_key]
            end
            if original and prop_key == "description" then original = util.htmlToPlainTextIfHtml(original) end
            local label = (tostring(self.prop_text[prop_key] or prop_key):gsub(":", ""))
            local current = book_props[prop_key]
            local sub = (current ~= nil and current ~= "") and oneline(current) or _("Empty")
            if custom ~= nil then sub = sub .. " · " .. _("edited") end
            sheet = Sheet:new{ make = function(s, inner)
                local head = sheet_head_lead{ width = inner, lead = tile(custom ~= nil and "leaf.gl.pencil" or "leaf.gl.textinput"),
                    title = label, sub = sub, close = close }
                local g1 = group(function(w, pad) return {
                    row{ width = w, pad = pad, icon = "leaf.gl.pencil", label = _("Edit…"), callback = function()
                        close()
                        self:showCustomEditDialog(file, book_props, prop_key)
                    end },
                    row{ width = w, pad = pad, icon = "leaf.lib.copy", label = _("Copy original"),
                        sub = original ~= nil and oneline(original) or _("Empty in the file"),
                        disabled = not (original ~= nil and Device:hasClipboard()), callback = function()
                            close()
                            Device.input.setClipboardText(original)
                            notify(_("Copied"))
                        end },
                    row{ width = w, pad = pad, icon = "leaf.gl.filesearch", label = _("View original"), disabled = original == nil,
                        callback = function()
                            close()
                            self:showBookProp(prop_key, original)
                        end },
                } end, inner)
                local g2 = group(function(w, pad) return {
                    row{ width = w, pad = pad, icon = "leaf.lib.reset", label = _("Reset to original"), danger = custom ~= nil,
                        disabled = custom == nil, callback = function()
                            UIManager:show(require("ui/widget/confirmbox"):new{
                                text = _("Reset this field?") .. "\n" .. T_(_("%1 goes back to “%2”."), label, oneline(original or "")),
                                ok_text = _("Reset"),
                                ok_callback = function()
                                    close()
                                    self:setCustomMetadata(file, book_props, prop_key)
                                end,
                            })
                        end },
                } end, inner)
                return sheet_body(head, { g1, g2 }, nil, inner)
            end }
        else
            local custom = self.custom_book_cover
            local cw, ch = P.px(40), P.px(60)
            sheet = Sheet:new{ make = function(s, inner)
                local lead = custom and custom_cover_box(custom, cw, ch)
                    or P.coverBox(file, cw, ch, { cache_only = true, bg = T.color("bg-raised"), radius = T.px("r-thumb") })
                local head = sheet_head_lead{ width = inner, lead = lead, title = _("Cover image"),
                    sub = custom and (_("Custom cover") .. " · " .. basename(custom)) or _("The book's own cover"), close = close }
                local g1 = group(function(w, pad) return {
                    row{ width = w, pad = pad, icon = "leaf.gl.eye", label = _("View cover"), callback = function()
                        close()
                        self:onShowBookCover(file)
                    end },
                    row{ width = w, pad = pad, icon = "leaf.gl.imageplus", label = _("Choose another image…"),
                        sub = custom and _("Remove the custom cover first to pick a new one") or nil,
                        disabled = custom ~= nil, callback = function()
                            close()
                            self:setCustomCover(file, book_props)
                        end },
                    row{ width = w, pad = pad, icon = "leaf.lib.image", label = _("View the book's own cover"), callback = function()
                        close()
                        self:onShowBookCover(file, true)
                    end },
                } end, inner)
                local g2 = group(function(w, pad) return {
                    row{ width = w, pad = pad, icon = "leaf.lib.reset", label = _("Remove custom cover"), sub = _("The image file is deleted"),
                        danger = custom ~= nil, disabled = custom == nil, callback = function()
                            UIManager:show(require("ui/widget/confirmbox"):new{
                                text = _("Remove the custom cover?") .. "\n" .. _("The image file will be deleted and the book's own cover comes back."),
                                ok_text = _("Remove"),
                                ok_callback = function()
                                    close()
                                    self:setCustomCover(file, book_props)
                                end,
                            })
                        end },
                } end, inner)
                return sheet_body(head, { g1, g2 }, nil, inner)
            end }
        end
        UIManager:show(sheet)
    end, "BookInfo:showCustomDialog")

    ------------------------------------------------------------------ 4. image viewer title line (archive, OPDS stream)
    -- leaf/imageviewer.lua owns ImageViewer: these hooks hand it the title line through its M.next
    -- (title, sub, per-image names) right before the viewer opens, and clear it after
    local function iv_next(nx) require("leaf/imageviewer").next = nx end

    ------------------------------------------------------------------ 5. archive viewer
    local DocumentRegistry = require("document/documentregistry")
    local function arc_counts(av, key)
        local f, d = 0, 0
        for _n, v in pairs(av.list_table and av.list_table[key] or {}) do
            if v then f = f + 1 else d = d + 1 end
        end
        return f, d
    end
    local function counts_text(f, d)
        local t = {}
        if d > 0 then table.insert(t, string.format(d == 1 and _("%d folder") or _("%d folders"), d)) end
        table.insert(t, string.format(f == 1 and _("%d file") or _("%d files"), f))
        return table.concat(t, ", ")
    end
    local function arc_trail(av, path) -- "comics-pack.zip › Issue 1"
        local parts = { av._leaf_name or "" }
        for seg in (path or ""):gmatch("[^/]+") do table.insert(parts, seg) end
        return table.concat(parts, " › ")
    end
    local function choose_dir(av, after)
        require("ui/downloadmgr"):new{ onConfirm = function(p)
            if p:sub(-1) ~= "/" then p = p .. "/" end
            av.extract_dir = p
            after()
        end }:chooseDir(av.extract_dir)
    end

    local ArcPage = Page:extend{ _leaf = true }
    function ArcPage:build()
        local av = self.av
        local W = Screen:getWidth()
        local path = self.path or ""
        local items = av:getItemTable(path)
        self.item_table = items -- KOReader's viewFile reads the images of the shown folder from it
        local rows = {}
        for i, it in ipairs(items) do
            if it.is_file then
                local img = DocumentRegistry:isImageFile(it.path)
                table.insert(rows, row{ width = W, icon = img and "leaf.gl.fileimage" or "leaf.lib.filetext",
                    label = it.text, value = it.mandatory, callback = function() av:showFileDialog(it.path) end })
            elseif i == 1 and path ~= "" then -- KOReader's "⬆ ../"
                local parent = it.path or ""
                table.insert(rows, row{ width = W, icon = "leaf.lib.upleft", label = _("Up"),
                    sub = parent == "" and av._leaf_name or basename(parent), callback = function()
                        self.path, self.page = parent, 1
                        self:rebuild()
                    end })
            else
                local f, d = arc_counts(av, it.path)
                table.insert(rows, row{ width = W, icon = "leaf.lib.folder", label = (it.text:gsub("/$", "")),
                    sub = counts_text(f, d), trailing = chevron(), callback = function()
                        self.path, self.page = it.path, 1
                        self:rebuild()
                    end })
            end
        end
        local close = function() self:onClose() end
        self._more = icon_btn("leaf.gl.more", function() av:showMenu() end)
        local attr = require("libs/libkoreader-lfs").attributes(av._leaf_file or "")
        local f, d = arc_counts(av, path == "" and "/" or path)
        local info = _("Archive") .. (attr and (" · " .. util.getFriendlySize(attr.size or 0)) or "") .. " · " .. counts_text(f, d)
        self:compose{
            head = page_head{ width = W, crumbs = { basename(av._leaf_dir or "/") }, title = arc_trail(av, path),
                back = close, actions = { self._more } },
            top = { src_line("leaf.gl.filearchive", info, W) },
            rows = rows,
            footer = function(label)
                return foot({ K.text(_("Tap a file to view or extract it"), "ui", "fs-sm", "text-3") }, { label }, W, "compact")
            end,
        }
    end
    function ArcPage:onClose()
        UIManager:close(self)
        local av = self.av
        if av.fm_updated and av.ui and av.ui.onRefresh then av.ui:onRefresh() end
        return true
    end

    local function patch_archive(AV)
        if AV._leaf_gl then return end
        AV._leaf_gl = true
        L.wrap(AV, "openFile", function(orig, self, file)
            local Archiver = require("ffi/archiver")
            local dir, filename = util.splitFilePathName(file)
            self.arc = Archiver.Reader:new()
            self.fm_updated = nil
            self.list_table = {}
            self.extract_dir = dir -- KOReader: the archive's folder
            if self.arc:open(file) then self:getListTable() end
            self._leaf_file, self._leaf_name, self._leaf_dir = file, filename, dir
            local page = ArcPage:new{ av = self, path = "" }
            self.booklist = page
            UIManager:show(page)
        end, "ArchiveViewer:openFile")
        L.wrap(AV, "showMenu", function(orig, self)
            local page = self.booklist
            local b = page and page._leaf and page._more
            if not (b and b.dimen) then return orig(self) end
            UIManager:show(Popover:new{
                items = { { icon = "leaf.gl.packageopen", label = _("Extract all files…"), callback = function() self:extractAllDialog() end } },
                top = b.dimen.y + b.dimen.h + T.px("sp-1"), right = Screen:getWidth() - T.px("sp-2") })
        end, "ArchiveViewer:showMenu")
        L.wrap(AV, "showFileDialog", function(orig, self, filepath)
            if not (self.booklist and self.booklist._leaf) then return orig(self, filepath) end
            local dir = filepath:match("^(.*)/[^/]*$")
            local img = DocumentRegistry:isImageFile(filepath)
            local sheet
            sheet = Sheet:new{ make = function(s, inner)
                local close = function() UIManager:close(s) end
                local head = sheet_head_lead{ width = inner, lead = tile(img and "leaf.gl.fileimage" or "leaf.lib.filetext"),
                    title = basename(filepath), sub = arc_trail(self, dir and (dir .. "/") or ""), close = close }
                local g = group(function(w, pad) return {
                    row{ width = w, pad = pad, icon = "leaf.gl.eye", label = _("View"),
                        sub = img and _("Opens with the other images of the archive") or _("Opens as text"), callback = function()
                            close()
                            self:viewFile(filepath)
                        end },
                    row{ width = w, pad = pad, icon = "leaf.gl.download", label = T_(_("Extract to %1"), basename(self.extract_dir)),
                        callback = function()
                            close()
                            self:extractFile(filepath)
                        end },
                    row{ width = w, pad = pad, icon = "leaf.gl.folderinput", label = _("Extract to…"), trailing = chevron(),
                        callback = function()
                            close()
                            choose_dir(self, function() self:extractFile(filepath) end)
                        end },
                } end, inner)
                return sheet_body(head, { g }, { note(_("A file with the same name in the target folder is replaced."), inner) }, inner)
            end }
            UIManager:show(sheet)
        end, "ArchiveViewer:showFileDialog")
        L.wrap(AV, "extractAllDialog", function(orig, self)
            if not (self.booklist and self.booklist._leaf) then return orig(self) end
            UIManager:show(Dialog:new{
                title = _("Extract all files?"),
                body = T_(_("To %1."), (self.extract_dir:gsub("/$", ""))) .. "\n" .. _("Files with the same name are replaced."),
                left_actions = { { label = _("Choose folder…"), callback = function()
                    choose_dir(self, function() self:extractAllDialog() end)
                end } },
                actions = { { label = _("Cancel") },
                    { label = _("Extract"), kind = "primary", callback = function() self:extractAll() end } },
            })
        end, "ArchiveViewer:extractAllDialog")
        L.wrap(AV, "viewFile", function(orig, self, filepath)
            if DocumentRegistry:isImageFile(filepath) and self.booklist then
                local names = {}
                for _i, it in ipairs(self.booklist.item_table or {}) do
                    if it.is_file and DocumentRegistry:isImageFile(it.path) then table.insert(names, it.text) end
                end
                local dir = filepath:match("^(.*)/[^/]*$")
                iv_next{ names = names, sub = arc_trail(self, dir and (dir .. "/") or ""), paper = true, controls = true }
            end
            local ok, err = pcall(orig, self, filepath)
            iv_next(nil)
            if not ok then error(err, 0) end
        end, "ArchiveViewer:viewFile")
    end
    M.patch_archive = patch_archive

    local PluginLoader = require("pluginloader")
    local function hook_plugins(list)
        for _i, p in ipairs(list or {}) do
            if p.name == "archiveviewer" then patch_archive(p) end
        end
    end
    if PluginLoader.enabled_plugins then hook_plugins(PluginLoader.enabled_plugins) end
    L.wrap(PluginLoader, "loadPlugins", function(orig, self, ...)
        local enabled, disabled = orig(self, ...)
        hook_plugins(enabled)
        return enabled, disabled
    end, "PluginLoader:loadPlugins (gaps library)")

    ------------------------------------------------------------------ 6. OPDS page streaming: the viewer's title line
    local hooks = {
        opdsbrowser = function(OB)
            L.wrap(OB, "showDownloads", function(orig, self, item, ...)
                M._pse_ctx = { title = item and (item.title or item.text), catalog = self.root_catalog_title }
                return orig(self, item, ...)
            end, "OPDSBrowser:showDownloads (gaps library)")
        end,
        opdspse = function(PSE)
            L.wrap(PSE, "streamPages", function(orig, self, ...)
                local ctx = M._pse_ctx
                if ctx and ctx.title then
                    iv_next{ title = ctx.title, paper = true, controls = true,
                        sub = ctx.catalog and (_("Page stream") .. " · " .. ctx.catalog) or _("Page stream") }
                end
                local ok, err = pcall(orig, self, ...)
                iv_next(nil)
                if not ok then error(err, 0) end
            end, "OPDSPSE:streamPages (gaps library)")
        end,
    }
    local done = {}
    local function run_hook(name, mod)
        if done[name] or type(mod) ~= "table" then return end
        done[name] = true
        local ok, err = pcall(hooks[name], mod)
        if ok then L.log("gapslib: hooked", name) else L.err("gapslib: hook", name, "failed:", err) end
    end
    for name in pairs(hooks) do
        if package.loaded[name] then run_hook(name, package.loaded[name]) end
    end
    local prev_require = require
    _G.require = function(name, ...)
        local mod = prev_require(name, ...)
        if hooks[name] and not done[name] then run_hook(name, mod) end
        return mod
    end
    --- scenes: the publication shown by the next page stream
    function M.pse_context(title, catalog) M._pse_ctx = { title = title, catalog = catalog } end
end

return M
