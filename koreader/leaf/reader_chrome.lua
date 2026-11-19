--[[
    Leaf reader chrome (prototype overlay "reader-chrome"). In KOReader a tap at the top of the
    page opens the top menu and a tap at the bottom the typesetting panel; in Leaf both open the
    chrome, which leads to everything:

      top bar:    ← library · title / author · bookmark · search · ☰ (the main menu)
      bottom bar: chapter · page x / y
                  |◁  skim slider  ▷|      (previous / next chapter; the slider jumps on release)
                  Contents · Typeset · Light · Notes · More

    Every button sends KOReader's own events (ShowToc, ShowConfigMenu, ShowFlDialog, ShowBookmark,
    ToggleBookmark, ShowFulltextSearchInput, GotoPrev/NextChapter, GotoPage). A tap on the page
    between the bars closes the chrome. Swipes keep KOReader's menu / panel behaviour.
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
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local IconButton = require("ui/widget/iconbutton")
    local LeafSlider = require("leaf/widgets/slider")
    local hair = T.px("hairline")

    -- a toolbar tool: icon over a small label (.ko-tool)
    local Tool = InputContainer:extend{}
    function Tool:init()
        local s = T.px("icon-md")
        -- .rd-aa: the Typeset tool shows "Aa" in Playfair semibold instead of an icon
        local glyph = self.icon == "Aa"
            and CenterContainer:new{ dimen = Geom:new{ w = s, h = s }, TextWidget:new{ text = "Aa", face = L.face("display-semibold", "fs-lg"), padding = 0 } }
            or IconWidget:new{ icon = self.icon, width = s, height = s, alpha = true }
        local g = VerticalGroup:new{ align = "center",
            glyph,
            VerticalSpan:new{ width = Screen:scaleBySize(5 * T.scale) },
            TextWidget:new{ text = self.label, face = L.face("ui", "fs-xs"), fgcolor = T.color("text-2") } }
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = T.px("h-nav") }
        self[1] = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.dimen.h }, g }
        self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    end
    function Tool:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        InputContainer.paintTo(self, bb, x, y)
    end
    function Tool:onTap()
        if self.callback then self.callback() end
        return true
    end

    local Chrome = InputContainer:extend{ ui = nil }

    function Chrome:init()
        local ui = self.ui
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
        if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end

        local s = T.px("icon-md")
        local bp = math.floor((T.px("hit") - s) / 2)
        local side = T.px("sp-5")
        local function close_then(fn)
            return function()
                UIManager:close(self)
                if fn then fn() end
            end
        end
        local function send(name, ...)
            local args = { ... }
            return close_then(function() ui:handleEvent(Event:new(name, unpack(args))) end)
        end
        local function icon_button(icon, cb)
            return IconButton:new{ icon = icon, width = s, height = s, padding = bp, callback = cb, show_parent = self }
        end

        -- book facts
        local props = ui.doc_props or {}
        local title = props.display_title or props.title or (ui.document.file or ""):match("([^/]+)$") or ""
        local author = props.authors or ""
        author = author:match("^[^\n]*") or ""
        local doc = ui.document
        local page = (ui.view and ui.view.state and ui.view.state.page) or doc:getCurrentPage() or 1
        local total = doc:getPageCount() or 1
        local chapter = ui.toc and ui.toc.getTocTitleByPage and ui.toc:getTocTitleByPage(page) or ""
        local bookmarked = ui.bookmark and ui.bookmark.isPageBookmarked and ui.bookmark:isPageBookmarked(page)

        ---------------------------------------------------------------- top bar
        local left = HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = T.px("sp-2") },
            icon_button("leaf.kb.left", close_then(function() ui:onClose() end)),
            HorizontalSpan:new{ width = T.px("sp-1") } }
        local right = HorizontalGroup:new{ align = "center",
            icon_button(bookmarked and "leaf.rd.bookmarked" or "leaf.rd.bookmark", send("ToggleBookmark")),
            icon_button("appbar.search", send("ShowFulltextSearchInput")),
            icon_button("appbar.menu", close_then(function() ui.menu:onShowMenu() end)),
            HorizontalSpan:new{ width = T.px("sp-2") } }
        local text_w = W - left:getSize().w - right:getSize().w - T.px("sp-2")
        local texts = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = title, face = L.face("ui-semibold", "fs-md"), max_width = text_w } }
        if author ~= "" then
            table.insert(texts, TextWidget:new{ text = author, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = text_w })
        end
        table.insert(left, texts)
        left:resetLayout()
        local top_h = math.max(T.px("hit") + T.px("sp-2"), texts:getSize().h + 2 * T.px("sp-2"))
        local top = FrameContainer:new{
            bordersize = 0, padding = 0, background = T.color("bg-raised"),
            VerticalGroup:new{
                require("leaf/widgets/kit").status_strip(W),
                OverlapGroup:new{ dimen = Geom:new{ w = W, h = top_h },
                    LeftContainer:new{ dimen = Geom:new{ w = W, h = top_h }, left },
                    RightContainer:new{ dimen = Geom:new{ w = W, h = top_h }, right } },
                LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") } },
        }

        ---------------------------------------------------------------- bottom bar
        -- .rd-scrub: |◁  [chapter ······ page / pages]  ▷|
        --                [── slider with chapter ticks ──]
        local prev = icon_button("leaf.rd.prev", send("GotoPrevChapter"))
        local nxt = icon_button("leaf.rd.next", send("GotoNextChapter"))
        local mid_w = W - 2 * (T.px("sp-2") + prev:getSize().w + T.px("sp-half")) - 2 * T.px("sp-1")
        local page_text = TextWidget:new{ text = string.format("%d / %d", page, total), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") }
        local chap = TextWidget:new{ text = (chapter or ""):gsub("%s+", " "), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"),
            max_width = mid_w - page_text:getSize().w - T.px("sp-3") }
        local info_h = chap:getSize().h + T.px("sp-1")
        local info = OverlapGroup:new{ dimen = Geom:new{ w = mid_w, h = info_h },
            LeftContainer:new{ dimen = Geom:new{ w = mid_w, h = info_h }, chap },
            RightContainer:new{ dimen = Geom:new{ w = mid_w, h = info_h }, page_text } }
        local ticks = {}
        pcall(function()
            for _i, t in ipairs(ui.toc:getTocTicksFlattened() or {}) do
                if t > 1 and total > 1 then table.insert(ticks, (t - 1) / (total - 1)) end
            end
        end)
        local slider = LeafSlider:new{
            width = mid_w, pct = total > 1 and (page - 1) / (total - 1) or 0, show_parent = self, ticks = ticks,
            on_change = function(frac, final)
                local target = math.max(1, math.min(total, math.floor(1 + frac * (total - 1) + 0.5)))
                page_text:setText(string.format("%d / %d", target, total))
                self._slider:setPct(total > 1 and (target - 1) / (total - 1) or 0)
                UIManager:setDirty(self, "ui", self._bottom.dimen)
                if final then
                    UIManager:close(self)
                    ui:handleEvent(Event:new("GotoPage", target))
                end
            end,
        }
        self._slider = slider
        local skim = HorizontalGroup:new{ align = "center",
            HorizontalSpan:new{ width = T.px("sp-2") }, prev, HorizontalSpan:new{ width = T.px("sp-half") + T.px("sp-1") },
            VerticalGroup:new{ align = "left", info, slider },
            HorizontalSpan:new{ width = T.px("sp-half") + T.px("sp-1") }, nxt }

        local tools = {
            { "leaf.rd.listtree", _("Contents"), send("ShowToc") },
            { "Aa", ui.paging and _("Page") or _("Typeset"), send("ShowConfigMenu") },
            { "leaf.rd.light", _("Light"), send("ShowFlDialog") },
            { "leaf.rd.highlighter", _("Notes"), send("ShowBookmark") },
            { "leaf.rd.more", _("More"), close_then(function() ui.menu:onShowMenu() end) },
        }
        local tw = math.floor(W / #tools)
        local toolbar = HorizontalGroup:new{ align = "center" }
        for _, t in ipairs(tools) do
            table.insert(toolbar, Tool:new{ icon = t[1], label = t[2], callback = t[3], width = tw })
        end

        local bottom_frame = FrameContainer:new{
            bordersize = 0, padding = 0, background = T.color("bg-raised"),
            VerticalGroup:new{ align = "left",
                LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border-strong") },
                VerticalSpan:new{ width = T.px("sp-2") },
                skim,
                VerticalSpan:new{ width = T.px("sp-1") },
                LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") },
                toolbar },
        }
        self._top = top
        self._bottom = bottom_frame
        self[1] = OverlapGroup:new{ dimen = Geom:new{ w = W, h = H },
            top,
            BottomContainer:new{ dimen = Geom:new{ w = W, h = H }, bottom_frame },
        }
    end

    function Chrome:onTapClose(arg, ges)
        local t, b = self._top.dimen, self._bottom.dimen
        local inside = (t and not ges.pos:notIntersectWith(t)) or (b and not ges.pos:notIntersectWith(b))
        if not inside then UIManager:close(self) end
        return true
    end
    function Chrome:onClose()
        UIManager:close(self)
        return true
    end
    function Chrome:onShow()
        UIManager:setDirty(self, "ui")
        return true
    end
    function Chrome:onCloseWidget()
        UIManager:setDirty(nil, "ui")
    end

    function M.show(ui)
        UIManager:show(Chrome:new{ ui = ui })
    end

    -- the reader's top / bottom taps open the chrome instead of the menu / panel
    local ReaderMenu = require("apps/reader/modules/readermenu")
    local ReaderConfig = require("apps/reader/modules/readerconfig")
    L.wrap(ReaderMenu, "onTapShowMenu", function(orig, self, ges)
        if self.activation_menu == "swipe" then return orig(self, ges) end
        M.show(self.ui)
        return true
    end, "ReaderMenu:onTapShowMenu")
    L.wrap(ReaderConfig, "onTapShowConfigMenu", function(orig, self)
        if self.activation_menu == "swipe" then return orig(self) end
        M.show(self.ui)
        return true
    end, "ReaderConfig:onTapShowConfigMenu")
end

return M
