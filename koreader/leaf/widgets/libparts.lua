--[[
    Small pieces shared by the Leaf library and home screens.

      P.Tap{ content =, callback =, hold_callback = }   a tappable wrapper (whole content area)
      P.Bar{ width =, height =, pct = 0..1, dim = bool } .ko-progress: --surface-3 track, accent fill
      P.px(n)                                          a raw prototype px value, scaled like tokens
      P.cover(file, w, h)                              the book cover (PT's cache first), or nil
      P.coverFrame(widget_or_nil, w, h, title)         --r-cover corners + --border hairline; a
                                                       text cover (.lb-tcover) when there is no image
      P.bookInfo(file)                                 title, authors, pages, pct, status, md5
--]]
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local P = {}

local function L() return require("leaf/core") end

function P.px(n)
    return Screen:scaleBySize(n * (L().T.scale or 1))
end

---------------------------------------------------------------- Tap
P.Tap = InputContainer:extend{ content = nil, callback = nil, hold_callback = nil }
function P.Tap:init()
    self[1] = self.content
    local sz = self.content:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }
    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        Hold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
end
function P.Tap:getSize() return self.dimen end
function P.Tap:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    InputContainer.paintTo(self, bb, x, y)
end
function P.Tap:onTap()
    if self.callback then self.callback() end
    return true
end
function P.Tap:onHold()
    if self.hold_callback then self.hold_callback() return true end
    if self.callback then return false end
end

---------------------------------------------------------------- Bar
P.Bar = Widget:extend{ width = 100, height = 3, pct = 0, dim = false }
function P.Bar:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
end
function P.Bar:getSize() return self.dimen end
function P.Bar:paintTo(bb, x, y)
    local T = L().T
    local r = math.min(T.px("r-thumb"), math.floor(self.height / 2))
    bb:paintRoundedRect(x, y, self.width, self.height, T.color("surface-3"), r)
    local fw = math.floor(self.width * math.max(0, math.min(1, self.pct or 0)) + 0.5)
    if fw > 0 then
        bb:paintRoundedRect(x, y, math.max(fw, self.height), self.height, T.color(self.dim and "text-3" or "accent"), r)
    end
end

---------------------------------------------------------------- covers
--- PT's cached cover first (no document opening), then KOReader's own cover extraction.
function P.cover(file, w, h, cache_only)
    local bb
    local BIM = package.loaded["bookinfomanager"]
    if BIM then
        local ok, info = pcall(BIM.getBookInfo, BIM, file, true)
        if ok and info and info.has_cover and info.cover_bb then bb = info.cover_bb end
    end
    if not bb and not cache_only then
        pcall(function() bb = require("apps/filemanager/filemanagerbookinfo"):getCoverImage(nil, file) end)
    end
    if not bb then return nil end
    local ImageWidget = require("ui/widget/imagewidget")
    -- fill the 2:3 box (crop a little rather than letterbox, like .ko-cover)
    return ImageWidget:new{ image = bb, image_disposable = true, width = w, height = h,
        scale_factor = math.max(w / bb:getWidth(), h / bb:getHeight()), center_x_ratio = 0.5, center_y_ratio = 0.5 }
end

--- a cover box: image clipped to w x h, --r-cover corners painted in the surface colour, hairline
P.CoverBox = Widget:extend{ image = nil, width = 0, height = 0, title = nil, author = nil, radius = nil, bg = nil }
function P.CoverBox:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    local T = L().T
    self.radius = self.radius or T.px("r-cover")
    if not self.image then
        -- text cover (.lb-tcover): --surface-2 board, title in the display face
        local tiny = self.width < P.px(48)
        local pad = tiny and T.px("sp-1") or T.px("sp-2")
        local face = L().face("display-semibold", self.width < P.px(60) and "fs-2xs" or "fs-md")
        if tiny then face = require("ui/font"):getFace(require("leaf/fonts").FILES["display-semibold"], 6) end
        self._text = CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height },
            TextBoxWidget:new{ text = self.title or "?", face = face,
                width = self.width - 2 * pad, alignment = "center", bgcolor = T.color("surface-2"),
                height = self.height - 2 * pad, height_overflow_show_ellipsis = true, height_adjust = true } }
    end
end
function P.CoverBox:getSize() return self.dimen end
function P.CoverBox:paintTo(bb, x, y)
    local T = L().T
    self.dimen.x, self.dimen.y = x, y
    local w, h, r = self.width, self.height, self.radius
    if self.image then
        self.image:paintTo(bb, x, y)
        -- round the corners: paint the page background outside a quarter circle
        local bg = self.bg or T.color("bg")
        for dy = 0, r - 1 do
            local yy = r - dy - 0.5
            local inset = r - math.floor(math.sqrt(math.max(0, r * r - yy * yy)) + 0.5)
            if inset > 0 then
                bb:paintRect(x, y + dy, inset, 1, bg)
                bb:paintRect(x + w - inset, y + dy, inset, 1, bg)
                bb:paintRect(x, y + h - 1 - dy, inset, 1, bg)
                bb:paintRect(x + w - inset, y + h - 1 - dy, inset, 1, bg)
            end
        end
    else
        bb:paintRoundedRect(x, y, w, h, T.color("surface-2"), r)
        self._text:paintTo(bb, x, y)
    end
    bb:paintBorder(x, y, w, h, T.px("hairline"), T.color("border"), r)
end
function P.CoverBox:free()
    if self.image then self.image:free() end
    if self._text then self._text:free() end
end

function P.coverBox(file, w, h, opts)
    opts = opts or {}
    return P.CoverBox:new{ image = P.cover(file, w, h, opts.cache_only), width = w, height = h, title = opts.title, bg = opts.bg,
        radius = opts.radius }
end

---------------------------------------------------------------- book info
function P.bookInfo(file)
    local out = { file = file }
    local BookList = require("ui/widget/booklist")
    local ok, info = pcall(BookList.getBookInfo, file)
    info = ok and info or {}
    out.pct = info.percent_finished or 0
    out.status = info.been_opened and (info.status or "reading") or "new"
    out.pages = info.pages
    local BIM = package.loaded["bookinfomanager"]
    if BIM then
        local ok2, bi = pcall(BIM.getBookInfo, BIM, file, false)
        if ok2 and bi then
            out.title = bi.title
            out.authors = bi.authors
            out.pages = out.pages or bi.pages
        end
    end
    if info.been_opened then
        pcall(function()
            local ds = BookList.getDocSettings(file)
            local props = ds:readSetting("doc_props") or {}
            out.title = out.title or props.display_title or props.title
            out.authors = out.authors or props.authors
            out.pages = out.pages or ds:readSetting("doc_pages")
            out.md5 = ds:readSetting("partial_md5_checksum")
        end)
    end
    if not out.title or out.title == "" then
        out.title = (file:match("([^/]+)$") or file):gsub("%.[^.]+$", "")
    end
    if out.authors then out.authors = out.authors:gsub("\n.*", "") end
    return out
end

P.Blitbuffer = Blitbuffer
P.FrameContainer = FrameContainer
return P
