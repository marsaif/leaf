--[[
    Long-press a word in a book -> a panel shows the Arabic translation of the whole paragraph,
    with a button to still look up the pressed word in the dictionary.

    - Books that carry their own translations (the EN-AR Animal Farm edition: each paragraph is
      followed by a link to "#ar-NNN-K") are translated offline from the book itself.
    - Any other book falls back to KOReader's Google translation (needs internet).
    - Pressing Arabic text, notes, or anything that isn't a normal paragraph keeps the normal
      dictionary behaviour.
--]]
local Device = require("device")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local TextViewer = require("ui/widget/textviewer")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen

local TARGET_LANG = "ar"

local INLINE = {
    span = true, a = true, b = true, i = true, em = true, strong = true, sup = true, sub = true,
    small = true, u = true, font = true, big = true, code = true, cite = true, q = true, abbr = true,
}
local VOID = { br = true, img = true, hr = true, input = true, meta = true, link = true, col = true, wbr = true }

-- "/body/DocFragment[7]/body/div[1]/p[3]/span/text()[2].329" -> "/body/DocFragment[7]/body/div[1]/p[3]"
local function block_xpointer(xp)
    xp = xp:gsub("/text%(%)[^/]*$", ""):gsub("%.%d+$", "")
    while true do
        local tag = xp:match("/([%w_]+)[^/]*$")
        if tag and INLINE[tag:lower()] then
            xp = xp:gsub("/[^/]+$", "")
        else
            break
        end
    end
    return xp
end

-- Find the book's own translation: the first "#...ar-NNN-K" link after this paragraph.
local function offline_translation(doc, block)
    local parent, step = block:match("^(.*)/([^/]+)$")
    if not parent then return nil end
    local tag = step:match("^([%w_]+)")
    local idx = tonumber(step:match("%[(%d+)%]")) or 1
    if not tag then return nil end
    tag = tag:lower()
    local html = doc:getHTMLFromXPointer(parent, 0, false)
    if not html or not html:find('href="[^"]*ar%-%d+%-%d+"') then return nil end

    local depth, count, in_target, after = 0, 0, false, nil
    for _, closing, name, rest, e in html:gmatch("()<(/?)([%w_]+)([^>]*)>()") do
        name = name:lower()
        if closing == "/" then
            depth = depth - 1
            if in_target and depth == 1 and name == tag then
                after = e
                break
            end
        else
            if depth == 1 and name == tag then
                count = count + 1
                if count == idx then in_target = true end
            end
            if not (VOID[name] or rest:sub(-1) == "/") then
                depth = depth + 1
            end
        end
    end
    if not after then return nil end
    local href = html:match('href="(#[^"]*ar%-%d+%-%d+)"', after)
    if not href then return nil end
    local text = doc:getTextFromXPointer(href)
    if not text or text == "" then
        local id = href:match("(ar%-%d+%-%d+)$")
        local prefix = parent:match("DocFragment%[(%d+)%]")
        if id and prefix then
            text = doc:getTextFromXPointer("#_doc_fragment_" .. (tonumber(prefix) - 1) .. "_ " .. id)
        end
    end
    if not text or text == "" then return nil end
    text = text:gsub("%s*↩%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- ---------------------------------------------------------------------------
-- Panel: English paragraph (small, grey) above its Arabic translation,
-- with Previous / Define / Next buttons. Square, thin border (Kindle style).
-- ---------------------------------------------------------------------------
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local LineWidget = require("ui/widget/linewidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local CSS = [[
    @page { margin: 0; }
    body { margin: 0; }
    .en { font-family: 'Noto Serif'; font-size: 0.78em; color: #666666; line-height: 1.35; margin: 1em 0 0 0; padding-top: 0.6em; border-top: 1px solid #bbbbbb; }
    .ar { font-family: 'Noto Naskh Arabic'; font-size: 1.12em; line-height: 1.75; direction: rtl; text-align: right; margin: 0; }
    .none { font-family: 'Noto Sans'; color: #666666; text-align: center; }
]]

local function html_escape(t)
    return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- neighbouring paragraph (same parent, same tag), skipping ones with no English text
local function neighbor(doc, block, delta)
    local parent, step = block:match("^(.*)/([^/]+)$")
    if not parent then return nil end
    local tag = step:match("^([%w_]+)")
    local idx = tonumber(step:match("%[(%d+)%]")) or 1
    for _ = 1, 8 do
        idx = idx + delta
        if idx < 1 then return nil end
        local xp = parent .. "/" .. tag .. "[" .. idx .. "]"
        local ok, text = pcall(doc.getTextFromXPointer, doc, xp)
        if not ok or not text or text == "" then return nil end
        if text:find("%a%a%a") then return xp, text end
    end
end

local function translate(doc, block, para)
    local ok, arabic = pcall(offline_translation, doc, block)
    if ok and arabic then return arabic end
    -- other books: online translation (blocks briefly; needs internet)
    local ok2, online = pcall(Translator.translate, Translator, para, TARGET_LANG)
    if ok2 and type(online) == "string" and online ~= "" then return online end
    return nil
end

local Panel = InputContainer:extend{
    ui = nil, doc = nil, block = nil, para = nil, word = nil,
}

function Panel:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    -- bottom sheet, full width (like the Kindle look-up card)
    self.width = sw
    self.body_h = math.floor(sh * 0.36)
    if Device:isTouchDevice() then
        self.ges_events = { TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:build()
end

function Panel:build()
    local arabic = translate(self.doc, self.block, self.para)
    local body
    if arabic then
        body = '<p class="ar" dir="rtl">' .. html_escape(arabic):gsub("\n", "<br/>") .. '</p>'
    else
        body = '<p class="none">No translation available (needs internet for this book).</p>'
    end
    body = body .. '<p class="en">' .. html_escape(self.para) .. '</p>'
    local inner_w = self.width - 2 * Screen:scaleBySize(18)
    local title = TitleBar:new{
        width = self.width,
        title = "Translation",
        title_face = require("ui/font"):getFace("source/SourceSans3-Bold.ttf", 20),
        align = "left",
        with_bottom_line = true,
        bottom_line_color = Blitbuffer.COLOR_LIGHT_GRAY,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    self.html = ScrollHtmlWidget:new{
        html_body = body,
        css = CSS,
        default_font_size = Screen:scaleBySize(20),
        width = inner_w,
        height = self.body_h,
        dialog = self,
    }
    local prev_xp = neighbor(self.doc, self.block, -1)
    local next_xp = neighbor(self.doc, self.block, 1)
    local row = {
        { text = "‹ Previous", enabled = prev_xp ~= nil, callback = function() self:go(-1) end },
    }
    if self.word and self.word ~= "" then
        table.insert(row, { text = 'Define "' .. self.word .. '"', callback = function()
            self:onClose()
            self.ui.dictionary:onLookupWord(self.word)
        end })
    end
    table.insert(row, { text = "Next ›", enabled = next_xp ~= nil, callback = function() self:go(1) end })
    local buttons = ButtonTable:new{
        width = self.width - 2 * Size.padding.default,
        buttons = { row },
        zero_sep = true,
        show_parent = self,
    }
    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius = 0,
        padding = 0,
        VerticalGroup:new{
            align = "center",
            LineWidget:new{ background = Blitbuffer.COLOR_BLACK, dimen = Geom:new{ w = self.width, h = Size.border.thick } },
            title,
            VerticalSpan:new{ width = Size.padding.large },
            self.html,
            VerticalSpan:new{ width = Size.padding.default },
            buttons,
            VerticalSpan:new{ width = Size.padding.small },
        },
    }
    self[1] = BottomContainer:new{ dimen = self.dimen, self.frame }
end

function Panel:go(delta)
    local xp, text = neighbor(self.doc, self.block, delta)
    if not xp then return end
    self.block, self.para, self.word = xp, text, nil
    self:build()
    UIManager:setDirty(self, "ui")
end

function Panel:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

function Panel:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

function Panel:onTapClose(arg, ges)
    if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end

function Panel:onClose()
    UIManager:close(self)
    return true
end

local orig_lookupDictWord = ReaderHighlight.lookupDictWord
ReaderHighlight.lookupDictWord = function(self)
    local sel = self.selected_text
    if not (self.ui.rolling and sel and type(sel.pos0) == "string") then
        return orig_lookupDictWord(self)
    end
    local doc = self.ui.document
    local ok, block = pcall(block_xpointer, sel.pos0)
    if not ok or not block or block:find("/aside") then
        return orig_lookupDictWord(self)
    end
    local para = doc:getTextFromXPointer(block) or ""
    if not para:find("%a%a%a") then -- no English words here (Arabic text, numbers...): normal dictionary
        return orig_lookupDictWord(self)
    end
    local word = sel.text
    self:clear()
    UIManager:show(Panel:new{ ui = self.ui, doc = doc, block = block, para = para, word = word })
end
