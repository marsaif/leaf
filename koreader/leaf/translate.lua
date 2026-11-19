--[[
    Leaf paragraph translation sheet (prototype overlay "translate", js/screens/reader-panels.js):
    restyles the panel of koreader/patches/2-paragraph-translate.lua (long-press a word -> the
    paragraph's Arabic translation). Applied from leaf/kvpages.lua once the patches have loaded;
    the patch keeps working on its own (stock look) when Leaf is off.

      sheet:   --bg-raised, --r-xl top corners, grip
      head:    "Translation" (Inter --fs-head semibold) + source line (--fs-sm --text-3) ·
               "English → العربية" pill · ✕
      body:    ENGLISH eyebrow + the paragraph (Literata --fs-md), dashed rule, then
               the translation (Noto Naskh Arabic, right-to-left); scrolls with a thin bar
      footer:  ‹ Previous (secondary) · Define “word” (ghost) · Next › (secondary)
    Same behaviour as the patch: offline translation from the book first, Google otherwise;
    Previous / Next walk the neighbouring paragraphs; Define looks the pressed word up.
--]]
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

local function hex(T, name)
    local g = T.gray(name)
    return string.format("#%02x%02x%02x", g, g, g)
end

function M.restyle(L, Panel, translate, neighbor, html_escape)
    -- leaf/lookup.lua draws the panel (M.build_translate, called by the patch itself): that is the
    -- prototype's sheet; this older restyle is only the fallback when the lookup module failed
    if L.status and L.status.lookup == true then return end
    if not (translate and neighbor) then
        L.err("translate: patch internals not found, panel keeps its own look")
        return
    end
    local T = L.T
    local IconButton = require("ui/widget/iconbutton")
    local Button = require("ui/widget/button")
    local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
    local Size = require("ui/size")
    local hair = T.px("hairline")
    local esc = html_escape or function(t) return (t:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

    -- which source answered: the book's own translation (offline) or Google
    local offline = (function()
        local i = 1
        while true do
            local name, value = debug.getupvalue(translate, i)
            if not name then return end
            if name == "offline_translation" then return value end
            i = i + 1
        end
    end)()

    local Grip = Widget:extend{}
    function Grip:init() self.dimen = Geom:new{ w = Screen:scaleBySize(36 * T.scale), h = T.px("sp-1") } end
    function Grip:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        bb:paintRoundedRect(x, y, self.dimen.w, self.dimen.h, T.color("border-strong"), math.floor(self.dimen.h / 2))
    end

    -- MuPDF only knows KOReader's own font names: load Leaf's faces with @font-face from their folder
    local font_dir
    local function find_font_dir()
        if font_dir ~= nil then return font_dir end
        font_dir = false
        local ok, list = pcall(function() return require("fontlist"):getFontList() end)
        if ok and list then
            for _i, path in ipairs(list) do
                local dir = path:match("^(.*)/Literata%-Regular%.ttf$")
                if dir then font_dir = dir break end
            end
        end
        return font_dir
    end

    local function css()
        local faces = ""
        if find_font_dir() then
            faces = [[
            @font-face { font-family: 'LeafBook'; src: url('Literata-Regular.ttf'); }
            @font-face { font-family: 'LeafUI'; font-weight: 600; src: url('Inter-SemiBold.ttf'); }
            @font-face { font-family: 'LeafUI'; src: url('Inter-Regular.ttf'); }
            ]]
        end
        return faces .. string.format([[
            @page { margin: 0; }
            body { margin: 0; }
            .lbl { font-family: 'LeafUI', 'Noto Sans'; font-size: 0.73em; font-weight: 600; letter-spacing: 0.06em; color: %s; margin: 0 0 0.4em 0; }
            .en { font-family: 'LeafBook', 'Noto Serif'; line-height: 1.6; color: %s; margin: 0; }
            .ar { font-family: 'Noto Naskh Arabic'; font-size: 1.25em; line-height: 1.75; direction: rtl; text-align: right; color: %s; margin: 0; }
            .rule { border-top: 1px dashed %s; margin: 1.1em 0 0.9em 0; height: 0; }
            .none { font-family: 'LeafUI', 'Noto Sans'; color: %s; }
        ]], hex(T, "text-3"), hex(T, "text"), hex(T, "text"), hex(T, "border-strong"), hex(T, "text-3"))
    end

    L.wrap(Panel, "build", function(orig, self)
        local SW, H = Screen:getWidth(), Screen:getHeight()
        local W = SW - 2 * T.px("hairline") -- inside the sheet's side borders
        local pad = T.px("sp-5")
        local r = T.px("r-xl")

        local arabic, source
        local ok, a = pcall(offline or function() end, self.doc, self.block)
        if ok and a then
            arabic, source = a, _("In this edition · offline")
        else
            local ok2, online = pcall(translate, self.doc, self.block, self.para)
            if ok2 and online then arabic, source = online, _("Google Translate · online") end
        end

        -- head
        local s = T.px("icon-md")
        local bp = math.floor((T.px("hit") - s) / 2)
        local close = IconButton:new{ icon = "close", width = s, height = s, padding = bp, allow_flash = false,
            callback = function() self:onClose() end, show_parent = self }
        local pill = FrameContainer:new{ bordersize = 0, background = T.color("surface-2"), radius = T.px("r-pill"),
            padding = 0, padding_left = T.px("sp-2h"), padding_right = T.px("sp-2h"),
            padding_top = T.px("sp-1"), padding_bottom = T.px("sp-1"),
            HorizontalGroup:new{ align = "center",
                TextWidget:new{ text = _("English"), face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2") },
                TextWidget:new{ text = " → ", face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3") },
                TextWidget:new{ text = "العربية", face = L.face("arabic", "fs-sm"), fgcolor = T.color("text-2") } } }
        local right = HorizontalGroup:new{ align = "center", pill, HorizontalSpan:new{ width = T.px("sp-1") }, close,
            HorizontalSpan:new{ width = T.px("sp-3") - bp } }
        local text_w = W - pad - right:getSize().w - T.px("sp-2")
        local texts = VerticalGroup:new{ align = "left",
            TextWidget:new{ text = _("Translation"), face = L.face("ui-semibold", "fs-head"), max_width = text_w } }
        if source then
            table.insert(texts, TextWidget:new{ text = source, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-3"), max_width = text_w })
        end
        local hh = math.max(T.px("h-header"), texts:getSize().h + 2 * T.px("sp-2"))
        local head = OverlapGroup:new{ dimen = Geom:new{ w = W, h = hh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = hh }, HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, texts } },
            RightContainer:new{ dimen = Geom:new{ w = W, h = hh }, right } }

        -- body
        local body = '<p class="lbl">' .. _("ENGLISH") .. '</p><p class="en">' .. esc(self.para) .. '</p><div class="rule"></div>'
        if arabic then
            body = body .. '<p class="ar" dir="rtl">'
                .. esc(arabic):gsub("\n", "<br/>") .. '</p>'
        else
            body = body .. '<p class="none">' .. esc(_("No translation available (needs internet for this book).")) .. '</p>'
        end
        self.html = ScrollHtmlWidget:new{
            html_body = body, css = css(),
            default_font_size = Screen:scaleBySize(T.size["fs-md"] * T.scale),
            width = W - 2 * pad, height = self.body_h, dialog = self,
            html_resource_directory = find_font_dir() or nil,
        }

        -- footer
        local prev_xp = neighbor(self.doc, self.block, -1)
        local next_xp = neighbor(self.doc, self.block, 1)
        local function action(label, kind, cb, enabled)
            return Button:new{ text = label, _leaf_kind = kind, padding_h = T.px("sp-4"), bordersize = 0,
                enabled = enabled ~= false,
                height = T.px("h-control") - 2 * Size.padding.button, callback = cb, show_parent = self }
        end
        local fh = T.px("h-control") + 2 * T.px("sp-3")
        local foot = OverlapGroup:new{ dimen = Geom:new{ w = W, h = fh },
            LeftContainer:new{ dimen = Geom:new{ w = W, h = fh }, HorizontalGroup:new{ HorizontalSpan:new{ width = T.px("sp-4") },
                action("‹  " .. _("Previous"), "secondary", function() self:go(-1) end, prev_xp ~= nil) } },
            RightContainer:new{ dimen = Geom:new{ w = W, h = fh }, HorizontalGroup:new{
                action(_("Next") .. "  ›", "secondary", function() self:go(1) end, next_xp ~= nil),
                HorizontalSpan:new{ width = T.px("sp-4") } } } }
        if self.word and self.word ~= "" then
            table.insert(foot, CenterContainer:new{ dimen = Geom:new{ w = W, h = fh },
                action(_("Define") .. " “" .. self.word .. "”", "ghost", function()
                    self:onClose()
                    self.ui.dictionary:onLookupWord(self.word)
                end) })
        end

        local content = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = Geom:new{ w = W, h = T.px("sp-1") }, Grip:new{} },
            VerticalSpan:new{ width = T.px("sp-1") },
            head,
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") },
            VerticalSpan:new{ width = T.px("sp-4") },
            self.html,
            VerticalSpan:new{ width = T.px("sp-4") },
            LineWidget:new{ dimen = Geom:new{ w = W, h = hair }, background = T.color("border") },
            foot,
            VerticalSpan:new{ width = r }, -- under the screen edge, with the rounded bottom corners
        }
        self.frame = FrameContainer:new{
            bordersize = hair, color = T.color("border-strong"), background = T.color("bg-raised"),
            radius = r, padding = 0,
            content,
        }
        -- the rounded bottom corners sit below the screen edge
        self[1] = BottomContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = SW, h = H + r }, self.frame }
    end, "TranslatePanel:build")
end

return M
