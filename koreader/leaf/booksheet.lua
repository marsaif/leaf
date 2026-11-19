--[[
    Leaf book sheet (prototype overlays "toc" / "bookmarks" / "annotations"): one bottom sheet for
    the book's contents, bookmarks and notes, opened by KOReader's ShowToc and ShowBookmark.

      head:   cover · title / author · progress line + "6% · page 4 of 67" · ×
      tabs:   Contents · Bookmarks n · Notes n
      rows:   contents: title (indented by level), page on the right; the current chapter has an
              accent bar, a --surface-3 fill and "Reading · 80%"
              bookmarks: "Page 12 · Chapter III · Nov 16" + the text at that place (book face)
              notes: the highlighted text (book face) + the note + the same meta line
      footer: Go to page (contents) / Bookmark this page (bookmarks) / Manage… (KOReader's own
              annotation list for editing, deleting, exporting), and ‹ page x of y › when needed.
    Data and navigation are KOReader's (ui.toc, ui.annotation, GotoXPointer / GotoPage with the
    location stack), so going back works as before.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local IconButton = require("ui/widget/iconbutton")
    local Button = require("ui/widget/button")
    local ProgressWidget = require("ui/widget/progresswidget")
    local hair = T.px("hairline")

    ---------------------------------------------------------------- a tappable row
    local Row = InputContainer:extend{}
    function Row:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
        self[1] = self.content
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    function Row:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if self.bg then bb:paintRect(x, y, self.width, self.height, self.bg) end
        if self.bar then bb:paintRect(x, y, T.px("bw-xl"), self.height, self.bar) end
        InputContainer.paintTo(self, bb, x, y)
    end
    function Row:onTap()
        if self.callback then self.callback() end
        return true
    end

    local Grip = Widget:extend{}
    function Grip:init() self.dimen = Geom:new{ w = Screen:scaleBySize(36 * T.scale), h = T.px("sp-1") } end
    function Grip:paintTo(bb, x, y)
        bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, T.color("border-strong"), math.floor(self.dimen.h / 2))
    end

    local Sheet = InputContainer:extend{ ui = nil, tab = "contents", page = 1 }

    local function short_date(dt)
        if not dt then return nil end
        local y, m, d = tostring(dt):match("^(%d+)-(%d+)-(%d+)")
        if not y then return nil end
        local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
        return (MONTHS[tonumber(m)] or m) .. " " .. tonumber(d)
    end

    function Sheet:pageOf(item)
        local ui = self.ui
        if item.pageno then return item.pageno end
        if ui.rolling and type(item.page) == "string" then
            return ui.document:getPageFromXPointer(item.page)
        end
        return item.page
    end

    function Sheet:goTo(item, xpointer)
        local ui = self.ui
        UIManager:close(self)
        if ui.link then ui.link:addCurrentLocationToStack() end
        if ui.rolling and xpointer then
            ui:handleEvent(Event:new("GotoXPointer", xpointer, xpointer))
        else
            ui:handleEvent(Event:new("GotoPage", self:pageOf(item)))
        end
    end

    function Sheet:items()
        local ui = self.ui
        local list = {}
        if self.tab == "contents" then
            if ui.toc.fillToc then ui.toc:fillToc() end
            for _, t in ipairs(ui.toc.toc or {}) do table.insert(list, t) end
        else
            local want_notes = self.tab == "notes"
            for _, a in ipairs(ui.annotation and ui.annotation.annotations or {}) do
                local is_note = a.drawer ~= nil
                if is_note == want_notes then table.insert(list, a) end
            end
        end
        return list
    end

    function Sheet:counts()
        local b, n = 0, 0
        for _, a in ipairs(self.ui.annotation and self.ui.annotation.annotations or {}) do
            if a.drawer then n = n + 1 else b = b + 1 end
        end
        return b, n
    end

    function Sheet:init()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        self.ges_events = {
            TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } },
            Swipe = { GestureRange:new{ ges = "swipe", range = function() return self._frame and self._frame.dimen or self.dimen end } },
        }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end

    function Sheet:build()
        local ui = self.ui
        local W, H = Screen:getWidth(), Screen:getHeight()
        local r = T.px("r-xl")
        local inner = W - 2 * hair
        local pad = T.px("sp-5")
        local sheet_h = math.floor(H * 0.88)
        local s = T.px("icon-md")
        local bp = math.floor((T.px("hit") - s) / 2)

        -- head: cover · title / author / progress · ×
        local doc = ui.document
        local cur = (ui.view and ui.view.state and ui.view.state.page) or doc:getCurrentPage() or 1
        local total = doc:getPageCount() or 1
        local props = ui.doc_props or {}
        local title = props.display_title or props.title or ""
        local author = (props.authors or ""):match("^[^\n]*") or ""
        local pct = math.floor(cur / math.max(1, total) * 100 + 0.5)
        local cover_w, cover_h = Screen:scaleBySize(40 * T.scale), Screen:scaleBySize(60 * T.scale)
        local cover
        pcall(function()
            local bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(doc)
            if bb then
                cover = require("ui/widget/imagewidget"):new{ image = bb, width = cover_w, height = cover_h, scale_factor = 0 }
            end
        end)
        local close = IconButton:new{ icon = "close", width = s, height = s, padding = bp, show_parent = self,
            callback = function() UIManager:close(self) end }
        local text_w = inner - pad - (cover and (cover_w + T.px("sp-3")) or 0) - close:getSize().w - T.px("sp-3")
        local bar_w = math.floor(text_w * 0.55)
        local meta = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = title, face = L.face("ui-semibold", "fs-head"), max_width = text_w },
            TextWidget:new{ text = author, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"), max_width = text_w },
            VerticalSpan:new{ width = T.px("sp-1h") },
            HorizontalGroup:new{ align = "center",
                ProgressWidget:new{ width = bar_w, height = T.px("bw-lg"), percentage = cur / math.max(1, total) },
                HorizontalSpan:new{ width = T.px("sp-2") },
                TextWidget:new{ text = T_(_("%1% · page %2 of %3"), pct, cur, total), face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3") } },
        }
        local head_left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad } }
        if cover then
            table.insert(head_left, FrameContainer:new{ bordersize = hair, color = T.color("border"), padding = 0, radius = T.px("r-thumb"), cover })
            table.insert(head_left, HorizontalSpan:new{ width = T.px("sp-3") })
        end
        table.insert(head_left, meta)
        local head_h = math.max(cover_h, meta:getSize().h) + 2 * T.px("sp-2")
        local head = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = head_h },
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = head_h }, head_left },
            RightContainer:new{ dimen = Geom:new{ w = inner, h = head_h }, HorizontalGroup:new{ close, HorizontalSpan:new{ width = T.px("sp-3") - bp } } } }

        -- tabs
        local nb, nn = self:counts()
        local function tab(key, label, n)
            local on = self.tab == key
            local face = on and "ui-semibold" or "ui"
            local text = label .. (n and n > 0 and ("  " .. n) or "")
            local probe = TextWidget:new{ text = text, face = L.face(face, "fs-md") }
            local w = probe:getSize().w
            probe:free()
            local b = Button:new{ text = text, bordersize = 0, padding = 0, padding_h = 0, radius = 0,
                text_font_face = require("leaf/fonts").FILES[face], text_font_size = T.fs("fs-md"),
                width = w, height = T.px("hit") - T.px("bw-lg"), show_parent = self,
                callback = function() self.tab = key; self.page = 1; self:rebuild() end }
            if b.label_widget then
                b.label_widget.fgcolor = T.color(on and "text" or "text-2")
                if b.label_widget.update then b.label_widget:update() end
            end
            return VerticalGroup:new{ align = "left", b,
                on and LineWidget:new{ dimen = Geom:new{ w = w, h = T.px("bw-lg") }, background = T.color("accent") }
                    or VerticalSpan:new{ width = T.px("bw-lg") } }
        end
        local tabs = HorizontalGroup:new{ align = "bottom", HorizontalSpan:new{ width = pad },
            tab("contents", _("Contents")), HorizontalSpan:new{ width = T.px("sp-5") },
            tab("bookmarks", _("Bookmarks"), nb), HorizontalSpan:new{ width = T.px("sp-5") },
            tab("notes", _("Notes"), nn) }

        -- footer: actions + pager
        local footer_h = T.px("h-control") + 2 * T.px("sp-3")
        local function action(label, kind, cb)
            return Button:new{ text = label, _leaf_kind = kind, padding_h = T.px("sp-4"), bordersize = 0,
                height = T.px("h-control") - 2 * require("ui/size").padding.button, callback = cb, show_parent = self }
        end
        local fl = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad } }
        local fr = HorizontalGroup:new{ align = "center" }
        if self.tab == "contents" then
            table.insert(fr, action(_("Go to page"), "secondary", function()
                UIManager:close(self)
                ui:handleEvent(Event:new("ShowGotoDialog"))
            end))
        else
            table.insert(fl, TextWidget:new{ text = self.tab == "bookmarks" and T_(_("%1 bookmarks"), nb) or T_(_("%1 notes"), nn),
                face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") })
            table.insert(fr, action(_("Manage…"), "ghost", function()
                UIManager:close(self)
                self._orig_show_bookmark(ui.bookmark)
            end))
            if self.tab == "bookmarks" then
                table.insert(fr, HorizontalSpan:new{ width = T.px("sp-1") })
                local marked = ui.bookmark.isPageBookmarked and ui.bookmark:isPageBookmarked(cur)
                table.insert(fr, action(marked and _("Remove bookmark") or _("Bookmark this page"), "primary", function()
                    ui:handleEvent(Event:new("ToggleBookmark"))
                    self:rebuild()
                end))
            end
        end
        table.insert(fr, HorizontalSpan:new{ width = pad })

        -- rows
        local list = self:items()
        local avail = sheet_h - (T.px("sp-2") + T.px("sp-1") + T.px("sp-1")) - head_h - T.px("hit") - hair - footer_h - hair - T.px("sp-2")
        local row_h = (self.tab == "contents") and T.px("h-row") or (self.tab == "bookmarks" and Screen:scaleBySize(76 * T.scale) or Screen:scaleBySize(108 * T.scale))
        local cur_idx = (self.tab == "contents") and ui.toc:getTocIndexByPage(cur) or nil
        local per = math.max(1, math.floor((avail - (cur_idx and T.px("sp-5") or 0)) / (row_h + hair)))
        local pages = math.max(1, math.ceil(#list / per))
        if self._first and cur_idx then self.page = math.floor((cur_idx - 1) / per) + 1 end
        self._first = false
        self.page = math.max(1, math.min(self.page, pages))
        local body = VerticalGroup:new{ align = "left" }
        local first = (self.page - 1) * per + 1
        for i = first, math.min(#list, first + per - 1) do
            local item = list[i]
            local content, h, bg, bar
            if self.tab == "contents" then
                local depth = math.max(1, item.depth or 1)
                local indent = pad + (depth - 1) * T.px("sp-4")
                local is_cur = i == cur_idx
                local pg = TextWidget:new{ text = tostring(item.page or ""), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") }
                local tw = inner - indent - pad - pg:getSize().w - T.px("sp-3")
                local left = VerticalGroup:new{ align = "left",
                    TextWidget:new{ text = item.title or "", face = L.face(is_cur and "ui-semibold" or "ui", "fs-md"), max_width = tw } }
                h = row_h
                if is_cur then
                    local cpct = 0
                    pcall(function()
                        local cstart = item.page
                        local ccount = ui.toc:getChapterPageCount(cur) or 1
                        cpct = math.floor((cur - cstart) / math.max(1, ccount) * 100 + 0.5)
                    end)
                    table.insert(left, TextWidget:new{ text = T_(_("Reading · %1%"), math.max(0, math.min(100, cpct))),
                        face = L.face("ui", "fs-xs"), fgcolor = T.color("accent") })
                    h = row_h + T.px("sp-5")
                    bg, bar = T.color("surface-3"), T.color("accent")
                end
                content = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = h },
                    LeftContainer:new{ dimen = Geom:new{ w = inner, h = h }, HorizontalGroup:new{ HorizontalSpan:new{ width = indent }, left } },
                    RightContainer:new{ dimen = Geom:new{ w = inner, h = h }, HorizontalGroup:new{ pg, HorizontalSpan:new{ width = pad } } } }
                local xp = item.xpointer
                table.insert(body, Row:new{ width = inner, height = h, content = content, bg = bg, bar = bar,
                    callback = function() self:goTo(item, xp) end })
            else
                h = row_h
                local p = self:pageOf(item)
                local chapter = item.chapter or (ui.toc and ui.toc:getTocTitleByPage(item.page)) or ""
                local bits = { T_(_("Page %1"), p) }
                if chapter ~= "" then table.insert(bits, chapter) end
                local date = short_date(item.datetime)
                if date then table.insert(bits, date) end
                local tw = inner - 2 * pad - s - T.px("sp-3")
                local col = VerticalGroup:new{ align = "left",
                    TextWidget:new{ text = table.concat(bits, " · "), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = tw } }
                local quote = item.text and item.text ~= "" and item.text or nil
                if quote then
                    table.insert(col, VerticalSpan:new{ width = T.px("sp-half") })
                    table.insert(col, TextBoxWidget:new{ text = quote:gsub("%s+", " "), face = L.face("book", "fs-md"), width = tw,
                        height = self.tab == "notes" and math.floor(row_h * 0.45) or math.floor(row_h * 0.4), height_overflow_show_ellipsis = true })
                end
                if self.tab == "notes" and item.note and item.note ~= "" then
                    table.insert(col, TextWidget:new{ text = "✎ " .. item.note:gsub("%s+", " "), face = L.face("ui", "fs-sm"),
                        fgcolor = T.color("text-2"), max_width = tw })
                end
                content = LeftContainer:new{ dimen = Geom:new{ w = inner, h = h },
                    HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = pad },
                        VerticalGroup:new{ VerticalSpan:new{ width = T.px("sp-1") },
                            IconWidget:new{ icon = self.tab == "notes" and "leaf.rd.notes" or "leaf.rd.bookmark", width = s, height = s, alpha = true } },
                        HorizontalSpan:new{ width = T.px("sp-3") }, col } }
                local xp = ui.rolling and type(item.page) == "string" and (item.pos0 or item.page) or nil
                table.insert(body, Row:new{ width = inner, height = h, content = content,
                    callback = function() self:goTo(item, xp) end })
            end
            table.insert(body, LineWidget:new{ dimen = Geom:new{ w = inner, h = hair }, background = T.color("border") })
        end
        if #list == 0 then
            local msg = self.tab == "contents" and _("This book has no table of contents.")
                or (self.tab == "bookmarks" and _("No bookmarks yet. Use Bookmark this page below.")
                or _("No notes yet. Long-press a word, then drag to select text."))
            table.insert(body, CenterContainer:new{ dimen = Geom:new{ w = inner, h = math.floor(avail / 2) },
                TextBoxWidget:new{ text = msg, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), width = inner - 4 * pad, alignment = "center" } })
        end
        if pages > 1 then
            local p = math.floor((T.px("hit") - s) / 2)
            local prev = IconButton:new{ icon = "chevron.left", width = s, height = s, padding = p, show_parent = self,
                callback = function() self.page = math.max(1, self.page - 1); self:rebuild() end }
            local nxt = IconButton:new{ icon = "chevron.right", width = s, height = s, padding = p, show_parent = self,
                callback = function() self.page = math.min(pages, self.page + 1); self:rebuild() end }
            table.insert(fl, HorizontalSpan:new{ width = T.px("sp-2") })
            table.insert(fl, prev)
            table.insert(fl, TextWidget:new{ text = T_(_("%1 / %2"), self.page, pages), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") })
            table.insert(fl, nxt)
        end
        self._pages = pages

        local footer = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = footer_h },
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = footer_h }, fl },
            RightContainer:new{ dimen = Geom:new{ w = inner, h = footer_h }, fr } }

        local frame = FrameContainer:new{
            bordersize = hair, color = T.color("border-strong"), background = T.color("bg-raised"),
            radius = r, padding = 0, padding_bottom = r,
            OverlapGroup:new{ dimen = Geom:new{ w = inner, h = sheet_h - hair },
                VerticalGroup:new{ align = "left",
                    VerticalSpan:new{ width = T.px("sp-2") },
                    CenterContainer:new{ dimen = Geom:new{ w = inner, h = T.px("sp-1") }, Grip:new{} },
                    VerticalSpan:new{ width = T.px("sp-1") },
                    head, tabs,
                    LineWidget:new{ dimen = Geom:new{ w = inner, h = hair }, background = T.color("border") },
                    body },
                BottomContainer:new{ dimen = Geom:new{ w = inner, h = sheet_h - hair },
                    VerticalGroup:new{ LineWidget:new{ dimen = Geom:new{ w = inner, h = hair }, background = T.color("border") }, footer } },
            },
        }
        self._frame = frame
        self[1] = BottomContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = W, h = H + r }, frame }
    end

    function Sheet:rebuild()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function Sheet:onTapClose(arg, ges)
        local f = self._frame and self._frame.dimen
        if f and ges.pos:notIntersectWith(f) then UIManager:close(self) end
        return true
    end
    function Sheet:onSwipe(arg, ges)
        local dir = ges.direction
        if dir == "west" and self.page < (self._pages or 1) then self.page = self.page + 1; self:rebuild()
        elseif dir == "east" and self.page > 1 then self.page = self.page - 1; self:rebuild()
        elseif dir == "south" then UIManager:close(self) end
        return true
    end
    function Sheet:onClose()
        UIManager:close(self)
        return true
    end
    function Sheet:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function Sheet:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end

    function M.show(ui, tab)
        UIManager:show(Sheet:new{ ui = ui, tab = tab or "contents", _first = true, _orig_show_bookmark = M.orig_show_bookmark })
    end

    local ReaderToc = require("apps/reader/modules/readertoc")
    local ReaderBookmark = require("apps/reader/modules/readerbookmark")
    M.orig_show_bookmark = ReaderBookmark.onShowBookmark
    L.wrap(ReaderToc, "onShowToc", function(orig, self, ...)
        M.show(self.ui, "contents")
        return true
    end, "ReaderToc:onShowToc")
    L.wrap(ReaderBookmark, "onShowBookmark", function(orig, self, ...)
        M.show(self.ui, "bookmarks")
        return true
    end, "ReaderBookmark:onShowBookmark")
end

return M
