--[[
    Leaf book details (prototype overlay "book-details"): KOReader's "Book information" opens this
    page; ⋮ still shows KOReader's full information list (all metadata, editing, cover, notebook).

      header:  ‹ Book details · ♡ favourite · ⋮
      hero:    cover · series / collection eyebrow · title (Playfair --fs-2xl) · author ·
               pages · FORMAT · size · language
      card:    "8%" · page x of y · progress line · Status: Reading | On hold | Finished
      about:   ABOUT THIS BOOK + the description (book face), "More" opens the full text
      bottom:  Resume / Start reading (primary)
    Status and favourites write through KOReader's own code (summary + BookList cache,
    ReadCollection), so the library and reader see the same values.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T_ = require("ffi/util").template
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local IconButton = require("ui/widget/iconbutton")
    local Button = require("ui/widget/button")
    local ProgressWidget = require("ui/widget/progresswidget")
    local LeafSeg = require("leaf/widgets/seg")
    local BookInfo = require("apps/filemanager/filemanagerbookinfo")
    local BookList = require("ui/widget/booklist")
    local ReadCollection = require("readcollection")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local util = require("util")
    local lfs = require("libs/libkoreader-lfs")

    local Page = InputContainer:extend{ covers_fullscreen = true }

    function Page:init()
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
        self:build()
    end

    function Page:build()
        local W, H = Screen:getWidth(), Screen:getHeight()
        local pad = T.px("sp-5")
        local s = T.px("icon-md")
        local bp = math.floor((T.px("hit") - s) / 2)
        local file = self.file
        local props = self.props or {}
        local info = BookList.getBookInfo(file) or {}
        local function icon_button(icon, cb)
            return IconButton:new{ icon = icon, width = s, height = s, padding = bp, callback = cb, show_parent = self }
        end

        -- header
        local fav = ReadCollection:isFileInCollection(file, ReadCollection.default_collection_name)
        local left = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = T.px("sp-2") },
            icon_button("chevron.left", function() UIManager:close(self) end),
            TextWidget:new{ text = _("Book details"), face = L.face("ui-semibold", "fs-head") } }
        local right = HorizontalGroup:new{ align = "center",
            icon_button(fav and "leaf.heart.on" or "leaf.heart", function()
                if fav then ReadCollection:removeItem(file, ReadCollection.default_collection_name)
                else ReadCollection:addItem(file, ReadCollection.default_collection_name) end
                ReadCollection:write({ [ReadCollection.default_collection_name] = true })
                self:rebuild()
            end),
            icon_button("leaf.more.v", function() self.orig_show(self.bookinfo, self.doc_settings_or_file, self.props_in) end),
            HorizontalSpan:new{ width = T.px("sp-2") } }
        local hh = T.px("h-header")
        local header = OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, left },
            RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, right } }

        -- hero
        local cover_w = math.floor(W * 0.3)
        local cover_h = math.floor(cover_w * 1.5)
        local cover
        pcall(function()
            local bb = BookInfo:getCoverImage(nil, file)
            if bb then cover = require("ui/widget/imagewidget"):new{ image = bb, width = cover_w, height = cover_h, scale_factor = 0 } end
        end)
        local col_w = W - 2 * pad - cover_w - T.px("sp-4")
        local col = VerticalGroup:new{ align = "left" }
        local eyebrow
        if props.series and props.series ~= "" then
            eyebrow = props.series .. (props.series_index and (" · " .. props.series_index) or "")
        else
            local colls = ReadCollection:getCollectionsWithFile(file) or {}
            for name in pairs(colls) do
                if name ~= ReadCollection.default_collection_name then eyebrow = name break end
            end
        end
        if eyebrow then
            table.insert(col, TextWidget:new{ text = eyebrow:upper(), face = L.face("ui-semibold", "fs-xs"), fgcolor = T.color("accent"), max_width = col_w })
            table.insert(col, VerticalSpan:new{ width = T.px("sp-1h") })
        end
        local title = props.display_title or props.title or (file:match("([^/]+)$") or "")
        table.insert(col, TextBoxWidget:new{ text = title, face = L.face("display-semibold", "fs-2xl"), width = col_w, bgcolor = T.color("bg"),
            height = math.floor(cover_h * 0.5), height_overflow_show_ellipsis = true, height_adjust = true })
        if props.authors and props.authors ~= "" then
            table.insert(col, VerticalSpan:new{ width = T.px("sp-1") })
            table.insert(col, TextWidget:new{ text = props.authors:gsub("\n", " · "), face = L.face("ui", "fs-md"), fgcolor = T.color("text-2"), max_width = col_w })
        end
        local attr = lfs.attributes(file) or {}
        local _dir, fname = util.splitFilePathName(file)
        local _base, ftype = filemanagerutil.splitFileNameType(fname or "")
        local bits = {}
        local pages = props.pages or info.pages
        if pages then table.insert(bits, T_(_("%1 pages"), pages)) end
        if ftype and ftype ~= "" then table.insert(bits, ftype:upper()) end
        if attr.size then table.insert(bits, util.getFriendlySize(attr.size)) end
        if props.language and props.language ~= "" then table.insert(bits, props.language) end
        table.insert(col, VerticalSpan:new{ width = T.px("sp-2") })
        table.insert(col, TextBoxWidget:new{ text = table.concat(bits, " · "), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), width = col_w, bgcolor = T.color("bg") })
        local hero = HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = pad } }
        if cover then
            table.insert(hero, FrameContainer:new{ bordersize = T.px("hairline"), color = T.color("border"), padding = 0, radius = T.px("r-cover"), cover })
            table.insert(hero, HorizontalSpan:new{ width = T.px("sp-4") })
        end
        table.insert(hero, col)

        -- progress card
        local card_w = W - 2 * T.px("sp-4")
        local cin = card_w - 2 * T.px("sp-4")
        local pct = math.floor((info.percent_finished or 0) * 100 + 0.5)
        local status = info.been_opened and (info.status or "reading") or nil
        local line
        if info.been_opened and pages then
            line = T_(_("Page %1 of %2"), math.max(1, math.floor((info.percent_finished or 0) * pages + 0.5)), pages)
        else
            line = _("Not started yet")
        end
        local card = FrameContainer:new{
            bordersize = T.px("hairline"), color = T.color("border"), background = T.color("surface"),
            radius = T.px("r-lg"), padding = T.px("sp-4"),
            VerticalGroup:new{ align = "left",
                HorizontalGroup:new{ align = "center",
                    TextWidget:new{ text = pct .. "%", face = L.face("ui-semibold", "fs-2xl") },
                    HorizontalSpan:new{ width = T.px("sp-3") },
                    TextWidget:new{ text = line, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"), max_width = cin - T.px("h-row") * 2 } },
                VerticalSpan:new{ width = T.px("sp-2") },
                ProgressWidget:new{ width = cin, height = T.px("bw-xl"), percentage = (info.percent_finished or 0) },
                VerticalSpan:new{ width = T.px("sp-3") },
                HorizontalGroup:new{ align = "center",
                    TextWidget:new{ text = _("Status"), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2") },
                    HorizontalSpan:new{ width = T.px("sp-3") },
                    LeafSeg:new{ width = cin - T.px("h-row") - T.px("sp-3"), selected = status,
                        items = { { label = _("Reading"), key = "reading" }, { label = _("On hold"), key = "abandoned" },
                                  { label = _("Finished"), key = "complete" } },
                        on_select = function(key)
                            local ds = self.doc_settings_or_file
                            local summary = type(ds) == "table" and ds:readSetting("summary") or {}
                            summary.status = key
                            filemanagerutil.saveSummary(ds, summary)
                            BookList.setBookInfoCacheProperty(file, "status", key)
                            self:rebuild()
                        end } } },
        }

        -- about
        local about = VerticalGroup:new{ align = "left" }
        local desc = props.description
        if desc and desc ~= "" then
            desc = util.htmlToPlainTextIfHtml and util.htmlToPlainTextIfHtml(desc) or desc
            table.insert(about, TextWidget:new{ text = _("ABOUT THIS BOOK"), face = L.face("ui-semibold", "fs-xs"), fgcolor = T.color("text-3") })
            table.insert(about, VerticalSpan:new{ width = T.px("sp-2") })
            table.insert(about, TextBoxWidget:new{ text = desc, face = L.face("book", "fs-md"), width = W - 2 * pad, bgcolor = T.color("bg"),
                height = Screen:scaleBySize(120 * T.scale), height_overflow_show_ellipsis = true })
            table.insert(about, Button:new{ text = _("More"), _leaf_kind = "caption", bordersize = 0, padding = 0,
                callback = function() BookInfo:onShowBookDescription(props.description, file) end, show_parent = self })
        end

        -- bottom action
        local resume = Button:new{
            text = info.been_opened and _("Resume reading") or _("Start reading"), _leaf_kind = "primary", bordersize = 0,
            width = W - 2 * pad, height = T.px("h-control") - 2 * require("ui/size").padding.button,
            show_parent = self,
            callback = function()
                UIManager:close(self)
                local RUI = package.loaded["apps/reader/readerui"]
                local cur = RUI and RUI.instance
                if cur and cur.document and cur.document.file == file then return end
                require("apps/reader/readerui"):showReader(file)
            end,
        }
        local bottom_h = T.px("h-control") + 2 * T.px("sp-3")

        local body = VerticalGroup:new{ align = "left",
            header,
            VerticalSpan:new{ width = T.px("sp-2") },
            hero,
            VerticalSpan:new{ width = T.px("sp-5") },
            HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-4") }, card },
            VerticalSpan:new{ width = T.px("sp-5") },
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, about },
        }
        self[1] = FrameContainer:new{ bordersize = 0, padding = 0, background = T.color("bg"), width = W, height = H,
            OverlapGroup:new{ dimen = Geom:new{ w = W, h = H },
                body,
                BottomContainer:new{ dimen = Geom:new{ w = W, h = H },
                    FrameContainer:new{ bordersize = 0, padding = 0, padding_bottom = T.px("sp-3"), padding_left = pad,
                        background = T.color("bg"), VerticalGroup:new{ VerticalSpan:new{ width = T.px("sp-3") }, resume } } },
            } }
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        local _unused = bottom_h
    end

    function Page:rebuild()
        self:build()
        UIManager:setDirty(self, "ui")
    end
    function Page:onClose()
        UIManager:close(self)
        return true
    end
    function Page:onShow()
        UIManager:setDirty(self, "full")
        return true
    end
    function Page:onCloseWidget()
        UIManager:setDirty(nil, "full")
    end

    L.wrap(BookInfo, "show", function(orig, self, doc_settings_or_file, book_props)
        local has_sidecar = type(doc_settings_or_file) == "table"
        local file = has_sidecar and doc_settings_or_file:readSetting("doc_path") or doc_settings_or_file
        if not file or not lfs.attributes(file, "mode") then return orig(self, doc_settings_or_file, book_props) end
        if not has_sidecar and BookList.hasBookBeenOpened(file) then
            doc_settings_or_file = BookList.getDocSettings(file)
        end
        local props = book_props or self:getDocProps(file, book_props)
        UIManager:show(Page:new{ file = file, props = props, props_in = book_props, bookinfo = self,
            doc_settings_or_file = doc_settings_or_file, orig_show = orig })
    end, "BookInfo:show")
end

return M
