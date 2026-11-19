--[[
    Leaf end of book (prototype overlay "book-end", js/screens/reader-panels.js).

    When the reader reaches the end and "End of document action" is "Ask with popup dialog"
    (KOReader's default), Leaf shows this page instead of KOReader's button dialog:

      ←                                                   📚       (back to the book · library)
                         [cover]
                         THE END
                You finished *Animal Farm*
                      George Orwell
      [ 2h 46m reading time | 343 pages | 5 highlights | 6 days ]   (statistics plugin; "—" without)
      YOUR RATING   ★★★★★  Loved it
      ✎ Write a review / the review                         ›
      STATUS        [Reading | On hold | Finished]
      ↺ Go to the beginning                                 ›
      📚 Back to library                                     ›
      ⇢ Open next file in folder                            ›     (disabled when sorted by date)
      🗑 Delete book                                         ›
      ⚙ When reaching the end of a book: show this screen         (tap: change the action)

    Every button of KOReader's dialog is here (mark as finished = the Finished segment, book status
    = rating / review / status on the page, go to beginning, open next file, delete, file browser).
    Rating, review and status are written to the book's summary exactly as KOReader's Book status
    page does. Other end-of-document actions run KOReader's code unchanged.
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

local ACTIONS = {
    { "pop-up", "show this screen" },
    { "nothing", "do nothing" },
    { "book_status", "show book status" },
    { "delete_file", "delete the file" },
    { "next_file", "open the next file" },
    { "goto_beginning", "go to the beginning" },
    { "file_browser", "return to the file browser" },
    { "mark_read", "mark the book as finished" },
    { "book_status_file_browser", "book status, then the file browser" },
}

function M.apply(L)
    local T = L.T
    local Kit = require("leaf/widgets/kit")
    local geom = Kit.geom
    local hair = T.px("hairline")
    local BookList = require("ui/widget/booklist")

    local End = InputContainer:extend{
        name = "end_document", -- KOReader checks this name not to stack a second dialog
        covers_fullscreen = true,
        status = nil, -- the ReaderStatus module
    }

    function End:init()
        self.ui = self.status.ui
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self.ges_events = { Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } } }
        self:build()
    end

    function End:summary()
        local ds = self.ui.doc_settings
        local s = ds:readSetting("summary")
        if not s then
            s = {}
            ds:saveSetting("summary", s)
        end
        return s
    end

    function End:save()
        self.ui.doc_settings:flush()
    end

    function End:stats()
        local time, days
        local st = self.ui.statistics
        if st and st.id_curr_book then
            pcall(function()
                local _pages, secs = st:getPageTimeTotalStats(st.id_curr_book)
                if secs and secs >= 60 then
                    local h = math.floor(secs / 3600)
                    local m = math.floor((secs % 3600) / 60)
                    time = h > 0 and T_(_("%1h %2m"), h, m) or T_(_("%1m"), m)
                end
                local d = st:getDatesForBook(st.id_curr_book)
                if d and #d > 0 then days = #d end
            end)
        end
        return time or "—", days and tostring(days) or "—"
    end

    function End:build()
        local ui = self.ui
        local FW, H = Screen:getWidth(), Screen:getHeight()
        local W = self._w or FW -- narrower when the page scrolls (room for the scroll bar)
        local pad = T.px("sp-5")
        local cw = math.min(W, Screen:scaleBySize(680 * T.scale))
        local inner = cw - 2 * pad
        local summary = self:summary()
        local props = ui.doc_props or {}
        local title = props.display_title or props.title or ""
        local author = (props.authors or ""):match("^[^\n]*") or ""
        local doc = ui.document

        -- header: ← · library
        local hh = Screen:scaleBySize(48 * T.scale)
        local header = OverlapGroup:new{ dimen = geom(W, hh),
            LeftContainer:new{ dimen = geom(W, hh), HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-2") },
                Kit.icon_button("leaf.kb.left", function() self:onClose() end, self) } },
            RightContainer:new{ dimen = geom(W, hh), HorizontalGroup:new{
                Kit.icon_button("leaf.end.library", function() self:library() end, self), HorizontalSpan:new{ width = T.px("sp-2") } } } }

        local g = VerticalGroup:new{ align = "center" }
        -- hero
        local cover_w = Screen:scaleBySize(118 * T.scale) -- .rd-end-hero .cv
        local cover_h = math.floor(cover_w * 1.5)
        pcall(function()
            local bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(doc)
            if bb then
                local img = require("ui/widget/imagewidget"):new{ image = bb, width = cover_w, height = cover_h, scale_factor = 0 }
                table.insert(g, require("ui/widget/container/framecontainer"):new{ bordersize = hair, color = T.color("border"),
                    padding = 0, radius = T.px("r-cover"), img })
                table.insert(g, VerticalSpan:new{ width = T.px("sp-4") })
            end
        end)
        -- letter-spacing .32em: a thin space plus a hair space between letters
        table.insert(g, TextWidget:new{ text = table.concat(require("util").splitToChars(_("THE END")), "\u{2009}\u{200A}"), face = L.face("ui-semibold", "fs-xs"), fgcolor = T.color("accent") })
        table.insert(g, VerticalSpan:new{ width = T.px("sp-2") })
        local lead = TextWidget:new{ text = _("You finished") .. " ", face = L.face("display", "fs-display") }
        local lw = lead:getSize().w
        local h2 = HorizontalGroup:new{ align = "bottom", lead,
            TextWidget:new{ text = title, face = L.face("display-italic", "fs-display"), max_width = math.max(inner - lw, inner / 2) } }
        table.insert(g, h2)
        table.insert(g, VerticalSpan:new{ width = T.px("sp-1h") })
        local by = author
        if props.series and props.series ~= "" then
            by = by .. (by ~= "" and " · " or "") .. props.series .. (props.series_index and (" #" .. props.series_index) or "")
        end
        if by ~= "" then
            table.insert(g, TextWidget:new{ text = by, face = L.face("ui", "fs-md"), fgcolor = T.color("text-3"), max_width = inner })
        end
        table.insert(g, VerticalSpan:new{ width = T.px("sp-4") })

        -- stats card
        local time, days = self:stats()
        local nhl = 0
        for _i, a in ipairs(ui.annotation and ui.annotation.annotations or {}) do
            if a.drawer then nhl = nhl + 1 end
        end
        local tiles = { { time, _("reading time") }, { tostring(doc:getPageCount()), _("pages") },
            { tostring(nhl), _("highlights") }, { days, _("days") } }
        local tile_w = math.floor(inner / #tiles)
        local stat_h = Screen:scaleBySize(56 * T.scale)
        local row = HorizontalGroup:new{ align = "center" }
        for i, t in ipairs(tiles) do
            if i > 1 then
                table.insert(row, require("ui/widget/linewidget"):new{ dimen = geom(hair, stat_h), background = T.color("border") })
            end
            table.insert(row, CenterContainer:new{ dimen = geom(tile_w - (i > 1 and hair or 0), stat_h),
                VerticalGroup:new{ align = "center",
                    TextWidget:new{ text = t[1], face = L.face("ui-semibold", "fs-head") },
                    VerticalSpan:new{ width = T.px("sp-half") },
                    TextWidget:new{ text = t[2], face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3"), max_width = tile_w - T.px("sp-1") } } })
        end
        table.insert(g, Kit.Tap:new{ width = inner, height = stat_h, content = row, radius = T.px("r-lg"),
            bg = T.color("surface"), border = hair, border_color = T.color("border") })

        -- sections (left aligned)
        local sec = VerticalGroup:new{ align = "left" }
        local function label(text)
            table.insert(sec, VerticalSpan:new{ width = T.px("sp-3") })
            table.insert(sec, TextWidget:new{ text = text, face = L.face("ui-semibold", "fs-xs"), fgcolor = T.color("text-3") })
            table.insert(sec, VerticalSpan:new{ width = T.px("sp-1") })
        end
        label(_("YOUR RATING"))
        local rating = summary.rating or 0
        local IconButton = require("ui/widget/iconbutton")
        local ss = T.px("icon-xl")
        local sp = math.floor((T.px("hit") - ss) / 2)
        local stars = HorizontalGroup:new{ align = "center" }
        for i = 1, 5 do
            table.insert(stars, IconButton:new{ icon = i <= rating and "star.full" or "star.empty", width = ss, height = ss, padding = sp,
                show_parent = self, callback = function() self:rate(i) end })
        end
        local words = { _("Didn't like it"), _("It was OK"), _("Liked it"), _("Really liked it"), _("Loved it") }
        table.insert(stars, HorizontalSpan:new{ width = T.px("sp-3") })
        table.insert(stars, TextWidget:new{ text = rating > 0 and words[rating] or _("Tap to rate"), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") })
        table.insert(sec, stars)
        local note = summary.note and summary.note ~= "" and summary.note:gsub("%s+", " ") or nil
        local function linkrow(o)
            return Kit.row{ width = inner, pad = 0, icon = o.icon, label = o.label, sub = o.sub, trailing = "chevron",
                danger = o.danger, enabled = o.enabled, callback = o.callback, label_face = "ui-medium" }
        end
        table.insert(sec, linkrow{ icon = "leaf.end.review",
            label = note and _("Your review") or _("Write a review"),
            sub = note or _("Saved with the book's metadata"), callback = function() self:review() end })
        table.insert(sec, Kit.line(inner))

        label(_("STATUS"))
        local LeafSeg = require("leaf/widgets/seg")
        table.insert(sec, LeafSeg:new{ width = inner, selected = summary.status or "reading",
            items = { { label = _("Reading"), key = "reading", icon = "leaf.lib.bookopen" }, { label = _("On hold"), key = "abandoned", icon = "leaf.end.pause" },
                { label = _("Finished"), key = "complete", icon = "leaf.end.checks" } },
            on_select = function(key) self:setStatus(key) end })

        table.insert(sec, VerticalSpan:new{ width = T.px("sp-4") })
        local collate = G_reader_settings:readSetting("collate")
        local acts = {
            { icon = "leaf.end.restart", label = _("Go to the beginning"), callback = function()
                UIManager:close(self)
                ui.gotopage:onGoToBeginning()
            end },
            { icon = "leaf.end.library", label = _("Back to library"), callback = function() self:library() end },
            { icon = "leaf.end.nextfile", label = _("Open next file in folder"), enabled = collate ~= "access" and collate ~= "date",
                callback = function()
                    UIManager:close(self)
                    self.status:onOpenNextOrPreviousFileInFolder()
                end },
            { icon = "leaf.trash", label = _("Delete book"), danger = true, callback = function()
                UIManager:close(self)
                self.status:deleteFile()
            end },
        }
        for i, a in ipairs(acts) do
            if i > 1 then table.insert(sec, Kit.line(inner)) end
            table.insert(sec, linkrow(a))
        end
        -- the end-of-document preference
        local cur_action = G_reader_settings:readSetting("end_document_action") or "pop-up"
        local action_text = "show this screen"
        for _i, a in ipairs(ACTIONS) do if a[1] == cur_action then action_text = a[2] end end
        local pref = HorizontalGroup:new{ align = "center", Kit.icon("appbar.settings", "icon-sm"), HorizontalSpan:new{ width = T.px("sp-2") },
            TextWidget:new{ text = _("When reaching the end of a book:") .. " ", face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") },
            TextWidget:new{ text = _(action_text), face = L.face("ui-medium", "fs-sm"), fgcolor = T.color("text-2") } }
        local pref_h = T.px("h-chip")
        local pw = pref:getSize().w
        pref:resetLayout()
        table.insert(sec, Kit.Tap:new{ width = math.min(inner, pw), height = pref_h,
            content = LeftContainer:new{ dimen = geom(math.min(inner, pw), pref_h), pref },
            callback = function() self:chooseAction() end })

        local body = VerticalGroup:new{ align = "center", Kit.status_strip(W), header, g, sec }
        local content_h = body:getSize().h
        body:resetLayout()
        local page
        local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
        if content_h > H then
            -- small screens / long titles: let it scroll
            if not self._w then
                self._w = FW - ScrollableContainer:getScrollbarWidth()
                return self:build()
            end
            self.cropping_widget = ScrollableContainer:new{ dimen = geom(FW, H), show_parent = self, body }
            page = self.cropping_widget
        else
            self.cropping_widget = nil
            page = body
        end
        self[1] = require("ui/widget/container/framecontainer"):new{ bordersize = 0, padding = 0, margin = 0,
            background = T.color("bg"), width = FW, height = H,
            require("ui/widget/container/topcontainer"):new{ dimen = geom(FW, H), page } }
    end

    function End:refresh()
        self:build()
        UIManager:setDirty(self, "ui")
    end

    function End:rate(n)
        local s = self:summary()
        n = (n == 1 and s.rating == 1) and 0 or n -- tapping the only star again clears the rating
        s.rating = n ~= 0 and n or nil
        BookList.setBookInfoCacheProperty(self.ui.document.file, "rating", n)
        self:save()
        self:refresh()
    end

    function End:setStatus(key)
        local s = self:summary()
        s.status = key
        s.modified = os.date("%Y-%m-%d", os.time())
        BookList.setBookInfoCacheProperty(self.ui.document.file, "status", key)
        self:save()
        self:refresh()
        local Notification = require("ui/widget/notification")
        Notification:notify(key == "complete" and _("Marked as finished") or _("Status updated"))
    end

    function End:review()
        local s = self:summary()
        local dialog
        dialog = require("ui/widget/inputdialog"):new{
            title = _("Review"), input = s.note or "", input_hint = _("What did you think?"),
            scroll = true, allow_newline = true, text_height = Screen:scaleBySize(150),
            buttons = { {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                { text = _("Save"), is_enter_default = true, callback = function()
                    local text = dialog:getInputText()
                    s.note = text ~= "" and text or nil
                    self:save()
                    UIManager:close(dialog)
                    self:refresh()
                end },
            } },
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    function End:chooseAction()
        local ButtonDialog = require("ui/widget/buttondialog")
        local cur = G_reader_settings:readSetting("end_document_action") or "pop-up"
        local d
        local buttons = {}
        for _i, a in ipairs(ACTIONS) do
            local key = a[1]
            local text = a[2]:sub(1, 1):upper() .. a[2]:sub(2)
            table.insert(buttons, { { text = (key == cur and "✓ " or "") .. _(text), callback = function()
                G_reader_settings:saveSetting("end_document_action", key)
                UIManager:close(d)
                self:refresh()
            end } })
        end
        d = ButtonDialog:new{ title = _("When reaching the end of a book"), buttons = buttons }
        UIManager:show(d)
    end

    function End:library()
        UIManager:close(self)
        UIManager:nextTick(function() self.status:openFileBrowser() end)
    end

    function End:onSwipe(arg, ges)
        if ges.direction == "south" or ges.direction == "east" then self:onClose() end
        return true
    end
    function End:onClose()
        UIManager:close(self, "flashpartial")
        return true
    end
    function End:onShow()
        UIManager:setDirty(self, "full")
        return true
    end
    function End:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end
    M.End = End

    function M.show(status)
        UIManager:show(End:new{ status = status }, "full")
    end

    local ReaderStatus = require("apps/reader/modules/readerstatus")
    L.wrap(ReaderStatus, "onEndOfBook", function(orig, self)
        local action = G_reader_settings:readSetting("end_document_action") or "pop-up"
        local QuickStart = require("ui/quickstart")
        if action ~= "pop-up" or not Device:isTouchDevice()
                or G_reader_settings:readSetting("lastfile") == QuickStart.quickstart_filename then
            return orig(self)
        end
        local top = UIManager:getTopmostVisibleWidget() or {}
        if top.name == "end_document" then return end
        Device:performHapticFeedback("CONTEXT_CLICK")
        if G_reader_settings:isTrue("end_document_auto_mark") then self:markBook(true) end
        M.show(self)
    end, "ReaderStatus:onEndOfBook")
end

return M
