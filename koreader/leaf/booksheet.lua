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
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
            Hold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } } }
    end
    function Row:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if self.bg then bb:paintRect(x, y, self.width, self.height, self.bg) end
        if self.bar then
            local t, b = self.bar_top or 0, self.bar_bottom or 0
            bb:paintRect(x, y + t, T.px("bw-xl"), self.height - t - b, self.bar)
        end
        InputContainer.paintTo(self, bb, x, y)
    end
    function Row:onTap()
        if self.callback then self.callback() end
        return true
    end
    function Row:onHold()
        if self.hold_callback then self.hold_callback() end
        return true
    end

    local Grip = Widget:extend{}
    function Grip:init() self.dimen = Geom:new{ w = Screen:scaleBySize(36 * T.scale), h = T.px("sp-1") } end
    function Grip:paintTo(bb, x, y)
        bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, T.color("border-strong"), math.floor(self.dimen.h / 2))
    end

    -- (dims the page behind, like the prototype's .ko-scrim under .rd-nav)
    local Sheet = InputContainer:extend{ ui = nil, tab = "contents", page = 1, _leaf_wants_scrim = true }

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

    -- "Chapter I · Silence" -> "CHAPTER I", "Silence" (the prototype's .lbl eyebrow over .ttl);
    -- a title with no such label is returned as is
    local LABEL_WORDS = { chapter = true, part = true, book = true, section = true, act = true, volume = true,
        letter = true, chapitre = true, partie = true, livre = true, canto = true, scene = true, appendix = true }
    local SEPS = { " · ", ": ", " – ", " — ", ". ", " - " }
    local function split_title(t)
        t = (t or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
        for _i, sep in ipairs(SEPS) do
            local at = t:find(sep, 1, true)
            if at then
                local head, rest = t:sub(1, at - 1), t:sub(at + #sep)
                local word = head:match("^(%a+) [%w%.]+$")
                if word and LABEL_WORDS[word:lower()] and rest ~= "" then return head, rest end
            end
        end
        return nil, t
    end
    M.split_title = split_title

    -- expanded TOC nodes: by default the current chapter and its parents (follows the reading
    -- position until the reader expands / collapses something, like the prototype's RD.tocOpen)
    function Sheet:openSet(list, cur_idx)
        local ui = self.ui
        local st = ui._leaf_toc_open
        if st and st.user then return st.set end
        local set = {}
        if cur_idx and list[cur_idx] then
            set[cur_idx] = true
            local d = list[cur_idx].depth or 1
            for j = cur_idx - 1, 1, -1 do
                local dj = list[j].depth or 1
                if dj < d then set[j] = true; d = dj end
            end
        end
        ui._leaf_toc_open = { set = set }
        return set
    end
    local function has_children(list, i) return list[i + 1] and (list[i + 1].depth or 1) > (list[i].depth or 1) end
    function Sheet:allOpen(list)
        local set = self:openSet(list, self.ui.toc:getTocIndexByPage(self._cur or 1))
        for i = 1, #list do
            if has_children(list, i) and not set[i] then return false end
        end
        return true
    end
    function Sheet:setAllOpen(list, on)
        local set = {}
        if on then for i = 1, #list do if has_children(list, i) then set[i] = true end end end
        self.ui._leaf_toc_open = { set = set, user = true }
    end
    function Sheet:toggleOpen(list, i)
        local set = self:openSet(list, self.ui.toc:getTocIndexByPage(self._cur or 1))
        set[i] = not set[i] or nil
        self.ui._leaf_toc_open = { set = set, user = true }
    end

    -- contents rows (.rd-toc-ch / .rd-toc-row): returns the row widgets and the current chapter's row
    function Sheet:buildRows(list, inner, cur)
        if self.tab ~= "contents" then return self:buildMarkRows(list, inner, cur) end
        local ui = self.ui
        local Kit = require("leaf/widgets/kit")
        self._cur = cur
        local total = ui.document:getPageCount() or 1
        local cur_idx = ui.toc:getTocIndexByPage(cur)
        local open = self:openSet(list, cur_idx)
        local min_d = math.huge
        for _i, t in ipairs(list) do min_d = math.min(min_d, t.depth or 1) end
        -- top-level chapter of every entry: the current one is the "here" group
        local top, last_top = {}, nil
        for i, t in ipairs(list) do
            if (t.depth or 1) == min_d then last_top = i end
            top[i] = last_top or i
        end
        local here_top = cur_idx and top[cur_idx]
        local exp_w = Screen:scaleBySize(32 * T.scale)
        local rpad = T.px("sp-5")
        local rows, cur_row = {}, nil
        local stack = {}
        for i, t in ipairs(list) do
            local d = t.depth or 1
            while #stack > 0 and stack[#stack].depth >= d do table.remove(stack) end
            local visible = #stack == 0 or stack[#stack].show
            table.insert(stack, { depth = d, show = visible and open[i] or false })
            if visible then
                local level = d - min_d
                local sub = level > 0
                local in_here = here_top ~= nil and top[i] == here_top
                local is_here = i == here_top
                -- end of this entry: the next entry at its level or above
                local next_page = total + 1
                for j = i + 1, #list do
                    if (list[j].depth or 1) <= d then next_page = list[j].page or next_page break end
                end
                local read = not in_here and next_page <= cur
                local gx = T.px("sp-3") + level * T.px("sp-5")
                local pg = TextWidget:new{ text = tostring(t.page or ""), face = L.face(in_here and "ui-semibold" or "ui", "fs-sm"),
                    fgcolor = T.color(in_here and "text" or "text-3") }
                local tx = gx + exp_w + T.px("sp-2")
                local tw = inner - tx - rpad - pg:getSize().w - T.px("sp-3")
                local eyebrow, title = split_title(t.title)
                local col = VerticalGroup:new{ align = "left" }
                if eyebrow then
                    table.insert(col, TextWidget:new{ text = eyebrow:upper(), face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3"), max_width = tw })
                    table.insert(col, VerticalSpan:new{ width = T.px("sp-half") })
                end
                local tcolor = sub and ((in_here and (t.page or 0) <= cur) and "text-2" or (read and "text-3" or "text-2"))
                    or (read and "text-2" or "text")
                table.insert(col, TextWidget:new{ text = title, face = L.face(is_here and "ui-semibold" or "ui", "fs-md"),
                    fgcolor = T.color(tcolor), max_width = tw })
                if is_here then
                    local prog = math.floor((cur - (t.page or cur) + 1) / math.max(1, next_page - (t.page or cur)) * 100 + 0.5)
                    prog = math.max(0, math.min(100, prog))
                    table.insert(col, VerticalSpan:new{ width = T.px("sp-1h") })
                    table.insert(col, HorizontalGroup:new{ align = "center",
                        ProgressWidget:new{ width = Screen:scaleBySize(90 * T.scale), height = T.px("bw-lg"), percentage = prog / 100 },
                        HorizontalSpan:new{ width = T.px("sp-2") },
                        TextWidget:new{ text = T_(_("Reading · %1%"), prog), face = L.face("ui", "fs-xs"), fgcolor = T.color("text-2") } })
                end
                local min_h = Screen:scaleBySize((sub and 42 or 58) * T.scale)
                local h = math.max(min_h, col:getSize().h + 2 * T.px("sp-2"))
                col:resetLayout()
                local exp
                if has_children(list, i) then
                    local idx = i
                    exp = Kit.Tap:new{ width = exp_w, height = exp_w,
                        content = CenterContainer:new{ dimen = Geom:new{ w = exp_w, h = exp_w },
                            Kit.TintIcon:new{ icon = open[i] and "control.expand" or "chevron.right", size_token = "icon-sm", color = T.color("text-3") } },
                        callback = function() self:toggleOpen(list, idx); self:rebuild() end }
                elseif read and not sub then
                    exp = CenterContainer:new{ dimen = Geom:new{ w = exp_w, h = exp_w },
                        Kit.TintIcon:new{ icon = "check", size_token = "icon-sm", color = T.color("text-3") } }
                else
                    exp = HorizontalSpan:new{ width = exp_w }
                end
                local content = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = h },
                    LeftContainer:new{ dimen = Geom:new{ w = inner, h = h }, HorizontalGroup:new{ align = "center",
                        HorizontalSpan:new{ width = gx }, exp, HorizontalSpan:new{ width = T.px("sp-2") }, col } },
                    RightContainer:new{ dimen = Geom:new{ w = inner, h = h }, HorizontalGroup:new{ pg, HorizontalSpan:new{ width = rpad } } } }
                local xp = t.xpointer
                local row = Row:new{ width = inner, height = h, content = content,
                    bg = in_here and T.color("accent-soft") or nil, bar = in_here and T.color("accent") or nil,
                    sep = not sub and #rows > 0 and not (in_here and not is_here), callback = function() self:goTo(t, xp) end }
                row.in_here = in_here
                table.insert(rows, row)
                if is_here then cur_row = #rows end
            end
        end
        -- the accent bar runs along the whole current chapter, inset at its ends
        for k, row in ipairs(rows) do
            if row.in_here then
                if not (rows[k - 1] and rows[k - 1].in_here) then row.bar_top = T.px("sp-2h") end
                if not (rows[k + 1] and rows[k + 1].in_here) then row.bar_bottom = T.px("sp-2h") end
            end
        end
        return rows, cur_row
    end

    -- bookmark / note rows (.rd-bm): ribbon · "Page 12 · Chapter III · Nov 16" · the text there · note · trash
    function Sheet:buildMarkRows(list, inner, cur)
        local ui = self.ui
        local Kit = require("leaf/widgets/kit")
        local rows = {}
        local doc = ui.document
        local is_bm = self.tab == "bookmarks"
        local hit = T.px("hit")
        local lpad = T.px("sp-4")
        local rib_w = Screen:scaleBySize(26 * T.scale)
        local tx = lpad + rib_w + T.px("sp-3")
        local tw = inner - tx - hit - T.px("sp-2")
        for _i, item in ipairs(list) do
            local p = self:pageOf(item)
            local here = p == cur
            local chapter = item.chapter or (ui.toc and ui.toc:getTocTitleByPage(item.page)) or ""
            local label = split_title(chapter) or chapter
            local bits = {}
            if label ~= "" then table.insert(bits, label) end
            local date = short_date(item.datetime)
            if date then table.insert(bits, date) end
            local pw = TextWidget:new{ text = T_(_("Page %1"), p), face = L.face("ui-semibold", "fs-sm") }
            local meta = HorizontalGroup:new{ align = "center", pw }
            if #bits > 0 then
                table.insert(meta, TextWidget:new{ text = " · " .. table.concat(bits, " · "), face = L.face("ui", "fs-sm"),
                    fgcolor = T.color("text-3"), max_width = tw - pw:getSize().w })
            end
            local col = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-3") }, meta }
            -- the text at that place: a highlight's own text, or the paragraph a bookmark points into
            local snip = item.drawer and item.text or nil
            if not snip and doc.getTextFromXPointer and type(item.page) == "string" then
                pcall(function() snip = doc:getTextFromXPointer(item.page) end)
            end
            if not snip or snip == "" then snip = not item.drawer and item.text or nil end
            if snip and snip ~= "" then
                snip = snip:gsub("%s+", " ")
                local face = L.face("book", "fs-md")
                local tb = TextBoxWidget:new{ text = snip, face = face, width = tw, fgcolor = T.color("text-2"),
                    bgcolor = T.color("bg-raised"), line_height = 0.3 }
                local two = 2 * tb.line_height_px
                if tb:getSize().h > two then
                    tb:free()
                    tb = TextBoxWidget:new{ text = snip, face = face, width = tw, fgcolor = T.color("text-2"), bgcolor = T.color("bg-raised"),
                        line_height = 0.3, height = two, height_overflow_show_ellipsis = true }
                end
                table.insert(col, VerticalSpan:new{ width = T.px("sp-1") })
                table.insert(col, tb)
            end
            if item.note and item.note ~= "" then
                table.insert(col, VerticalSpan:new{ width = T.px("sp-1") })
                table.insert(col, HorizontalGroup:new{ align = "center",
                    Kit.TintIcon:new{ icon = "leaf.rd.notes", size_token = "icon-sm", color = T.color("text") },
                    HorizontalSpan:new{ width = T.px("sp-1h") },
                    TextWidget:new{ text = item.note:gsub("%s+", " "), face = L.face("ui", "fs-sm"), max_width = tw - T.px("icon-sm") - T.px("sp-1h") } })
            end
            table.insert(col, VerticalSpan:new{ width = T.px("sp-3") })
            local h = math.max(T.px("h-row"), col:getSize().h)
            col:resetLayout()
            local content = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = h },
                HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = lpad },
                    VerticalGroup:new{ VerticalSpan:new{ width = T.px("sp-3") + T.px("sp-half") },
                        CenterContainer:new{ dimen = Geom:new{ w = rib_w, h = T.px("icon-sm") },
                            Kit.TintIcon:new{ icon = is_bm and "leaf.rd.bookmark" or "leaf.rd.notes", size_token = "icon-sm",
                                color = T.color(here and "accent" or "text-2") } } },
                    HorizontalSpan:new{ width = T.px("sp-3") }, col } }
            if is_bm then
                -- remove (KOReader's ReaderBookmark:removeItem, as its list's "Remove bookmark")
                table.insert(content, RightContainer:new{ dimen = Geom:new{ w = inner, h = hit + T.px("sp-2") },
                    HorizontalGroup:new{ Kit.Tap:new{ width = hit, height = hit,
                        content = CenterContainer:new{ dimen = Geom:new{ w = hit, h = hit },
                            Kit.TintIcon:new{ icon = "leaf.trash", size_token = "icon-sm", color = T.color("text-3") } },
                        callback = function()
                            ui.bookmark:removeItem(item)
                            self:rebuild()
                        end }, HorizontalSpan:new{ width = T.px("sp-2") } } })
            end
            local xp = ui.rolling and type(item.page) == "string" and (item.pos0 or item.page) or nil
            table.insert(rows, Row:new{ width = inner, height = h, content = content, sep = #rows > 0,
                callback = function() self:goTo(item, xp) end,
                -- long-press: the bookmark / highlight actions sheet (leaf/readerlists.lua)
                hold_callback = function()
                    local rl = package.loaded["leaf/readerlists"]
                    if not rl or not rl.show_actions then return end
                    UIManager:close(self)
                    rl.show_actions(ui, item)
                end })
        end
        return rows, nil
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
            -- .ko-tab: label (semibold when on) + a small --text-3 count (.n)
            local g = HorizontalGroup:new{ align = "center",
                TextWidget:new{ text = label, face = L.face(on and "ui-semibold" or "ui", "fs-md"), fgcolor = T.color(on and "text" or "text-2") } }
            if n and n > 0 then
                table.insert(g, HorizontalSpan:new{ width = T.px("sp-1h") })
                table.insert(g, TextWidget:new{ text = tostring(n), face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3") })
            end
            local w = g:getSize().w
            g:resetLayout()
            local h = T.px("hit") - T.px("bw-lg")
            local b = require("leaf/widgets/kit").Tap:new{ width = w, height = h,
                content = CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, g },
                callback = function() self.tab = key; self.page = 1; self:rebuild() end }
            return VerticalGroup:new{ align = "left", b,
                on and LineWidget:new{ dimen = Geom:new{ w = w, h = T.px("bw-lg") }, background = T.color("accent") }
                    or VerticalSpan:new{ width = T.px("bw-lg") } }
        end
        local tabs = HorizontalGroup:new{ align = "bottom", HorizontalSpan:new{ width = pad },
            tab("contents", _("Contents")), HorizontalSpan:new{ width = T.px("sp-5") },
            tab("bookmarks", _("Bookmarks"), nb), HorizontalSpan:new{ width = T.px("sp-5") },
            tab("notes", _("Notes"), nn) }

        -- footer: actions + pager
        local Kit = require("leaf/widgets/kit")
        local footer_h = T.px("h-control") + 2 * T.px("sp-2")
        local fpad = T.px("sp-4")
        local fl = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = fpad } }
        local fr = HorizontalGroup:new{ align = "center" }
        local list = self:items()
        if self.tab == "contents" then
            local any_children = false
            for i = 1, #list - 1 do
                if (list[i + 1].depth or 1) > (list[i].depth or 1) then any_children = true break end
            end
            if any_children then
                local all = self:allOpen(list)
                table.insert(fl, Kit.icon_label_button{ icon = "leaf.rd.listtree", kind = "ghost",
                    label = all and _("Collapse all") or _("Expand all"),
                    callback = function() self:setAllOpen(list, not all); self:rebuild() end })
            end
            table.insert(fr, Kit.icon_label_button{ icon = "leaf.rd.hash", label = _("Go to page"), kind = "secondary",
                callback = function()
                    UIManager:close(self)
                    ui:handleEvent(Event:new("ShowGotoDialog"))
                end })
        else
            table.insert(fl, TextWidget:new{ text = self.tab == "bookmarks" and T_(_("%1 bookmarks"), nb) or T_(_("%1 notes"), nn),
                face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") })
            -- KOReader's own list: edit, delete, export, filters
            table.insert(fr, Kit.button{ label = _("Manage…"), kind = "ghost", parent = self, callback = function()
                UIManager:close(self)
                self._orig_show_bookmark(ui.bookmark)
            end })
            if self.tab == "bookmarks" then
                table.insert(fr, HorizontalSpan:new{ width = T.px("sp-1") })
                local marked = ui.bookmark.isPageBookmarked and ui.bookmark:isPageBookmarked(ui.bookmark:getCurrentPageNumber())
                table.insert(fr, Kit.icon_label_button{ icon = marked and "leaf.rd.bmminus" or "leaf.rd.bmplus",
                    label = marked and _("Remove this page") or _("Bookmark this page"), kind = marked and "secondary" or "primary",
                    callback = function()
                        ui:handleEvent(Event:new("ToggleBookmark"))
                        self:rebuild()
                    end })
            end
        end
        table.insert(fr, HorizontalSpan:new{ width = fpad })

        -- rows (variable heights), packed into pages
        local avail = sheet_h - (T.px("sp-2") + T.px("sp-1") + T.px("sp-1")) - head_h - T.px("hit") - hair - footer_h - hair - T.px("sp-2")
        local rows, cur_row = self:buildRows(list, inner, cur)
        local pages, page_of, used = 1, {}, 0
        for i, rw in ipairs(rows) do
            local h = rw.height + (rw.sep and hair or 0)
            if used > 0 and used + h > avail then pages = pages + 1; used = 0; rw.sep = false; h = rw.height end
            if used == 0 then rw.sep = false end
            used = used + h
            page_of[i] = pages
        end
        if self._first and cur_row then self.page = page_of[cur_row] or 1 end
        self._first = false
        self.page = math.max(1, math.min(self.page, pages))
        local body = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = T.px("sp-1") } }
        local sep_x = T.px("sp-3") + Screen:scaleBySize(32 * T.scale) + T.px("sp-2")
        for i, rw in ipairs(rows) do
            if page_of[i] == self.page then
                if rw.sep then
                    table.insert(body, HorizontalGroup:new{ HorizontalSpan:new{ width = sep_x },
                        LineWidget:new{ dimen = Geom:new{ w = inner - sep_x, h = hair }, background = T.color("border") } })
                end
                table.insert(body, rw)
            end
        end
        if #list == 0 then
            local msg = self.tab == "contents" and _("This book has no table of contents.")
                or (self.tab == "bookmarks" and _("No bookmarks yet. Use Bookmark this page below.")
                or _("No notes yet. Long-press a word, then drag to select text."))
            table.insert(body, CenterContainer:new{ dimen = Geom:new{ w = inner, h = math.floor(avail / 2) },
                TextBoxWidget:new{ text = msg, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), width = inner - 4 * pad, alignment = "center" } })
        end
        local fc = HorizontalGroup:new{ align = "center" }
        if pages > 1 then
            local p = math.floor((T.px("hit") - s) / 2)
            local prev = IconButton:new{ icon = "chevron.left", width = s, height = s, padding = p, show_parent = self,
                callback = function() self.page = math.max(1, self.page - 1); self:rebuild() end }
            local nxt = IconButton:new{ icon = "chevron.right", width = s, height = s, padding = p, show_parent = self,
                callback = function() self.page = math.min(pages, self.page + 1); self:rebuild() end }
            table.insert(fc, prev)
            table.insert(fc, TextWidget:new{ text = T_(_("%1 / %2"), self.page, pages), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") })
            table.insert(fc, nxt)
        end
        self._pages = pages

        local footer = OverlapGroup:new{ dimen = Geom:new{ w = inner, h = footer_h },
            LeftContainer:new{ dimen = Geom:new{ w = inner, h = footer_h }, fl },
            CenterContainer:new{ dimen = Geom:new{ w = inner, h = footer_h }, fc },
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
