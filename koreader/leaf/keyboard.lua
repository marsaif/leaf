--[[
    Leaf on-screen keyboard (safety-net item 14; prototype .kb, App.keyboardHTML).

    * Dock: --bg-raised, --border-strong hairline on top, --sp-2 padding, --sp-1h gaps; keys are
      exactly --h-row (48px) tall (KOReader sizes rows at 64px).
    * Keys (.kb-key): --surface, --r-sm corners, --border-strong hairline, label Inter --fs-key.
      Function keys (shift, symbols, backspace, globe, arrows): --surface-3, --text-2, Lucide icons.
      An active shift/symbol key: --surface with a --bw-lg --text outline (.kb-shift.on); caps
      lock: --text fill (.kb-shift.caps). Enter: accent; "Done" when Enter submits the field,
      a return icon in multi-line fields. Long-press alternatives show small (--fs-2xs) top right.
    KOReader still builds every key (size, callbacks, popups, swipes, layouts); only its drawing
    is replaced.
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local M = {}

-- function-key labels used by KOReader's layouts (private-use glyphs of its symbol font)
local SHIFT, CAPS, BACKSPACE = "\u{ED35}", "\u{ED31}", "\u{E76D}"
local ICONS = {
    [SHIFT] = "leaf.kb.shift",
    [CAPS] = "leaf.kb.caps",
    [BACKSPACE] = "leaf.kb.backspace",
    ["🌐"] = "leaf.kb.globe",
    ["←"] = "leaf.kb.left",
    ["→"] = "leaf.kb.right",
}
local ENTER = "⮠"

--[[ The Leaf English layout (prototype LAYOUTS.qwerty): three letter rows and a bottom row
     ?123 · globe · , · space · . · enter; digits live on the ?123 layer. Built from KOReader's
     English layout so every letter keeps its long-press accents. Layers: 1 upper, 2 lower,
     3 symbols (shifted, prototype sym2), 4 symbols (prototype sym). ]]
local function leaf_english(en)
    local k = en.keys
    local function chars(str)
        local t = {}
        for c in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do table.insert(t, c) end
        return t
    end
    local function letters(row, sym, sym2, first, last)
        local out = {}
        for i = first or 1, last or #row do
            local key = row[i]
            table.insert(out, { key[1], key[2], sym2[#out + 1], sym[#out + 1] })
        end
        return out
    end
    local digits = {}
    for i, key in ipairs(k[1]) do digits[i] = key[2] end -- KOReader's digit keys, with their popups
    local row1 = letters(k[2], digits, chars("~`|•√π÷×¶∆"))
    local row2 = letters(k[3], chars("@#€_&-+()"), chars("£¥$¢^°={}"), 1, 9)
    local row3 = { k[4][1] }
    for _, key in ipairs(letters(k[4], chars("*\"':;!?"), chars("%©®™✓[]"), 2, 8)) do table.insert(row3, key) end
    table.insert(row3, k[4][9])
    local bottom = {
        k[5][1],                    -- ?123 (KOReader's symbols key)
        k[5][2],                    -- globe
        k[3][10],                   -- comma (with KOReader's popup)
        { label = "_", " ", " ", " ", " ", width = 4.0 }, -- space
        k[5][3],                    -- period (with KOReader's popup)
        k[5][7],                    -- enter
    }
    local out = {}
    for key, v in pairs(en) do out[key] = v end
    out.keys = { row1, row2, row3, bottom }
    return out
end

--[[ The Leaf Arabic layout (prototype LAYOUTS.arabic): rows of 12, 12 and shift + 9 + backspace;
     shift = harakat and alef forms, ?١٢٣ = Arabic-Indic digits. Letters reuse KOReader's Arabic
     keys (with their long-press variants); layers as KOReader: 1 shift, 2 letters, 3 sym2, 4 sym. ]]
local function leaf_arabic(ar)
    local function chars(str)
        local t = {}
        for c in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do table.insert(t, c) end
        return t
    end
    -- KOReader's letter keys by character (layer 2), so popups come along
    local by_char = {}
    for _, row in ipairs(ar.keys) do
        for _, e in ipairs(row) do
            local v = e[2]
            local ch = type(v) == "table" and v[1] or v
            if type(ch) == "string" then by_char[ch] = v end
        end
    end
    local function mark(c) -- combining marks show on a tatweel, as the prototype's labelOf()
        if c:match("^[\204-\205][\128-\191]$") or c:match("^\217[\139-\146]$") or c == "\217\176" then
            return { c, label = "ـ" .. c }
        end
        return c
    end
    local function row(letters, shift, sym, sym2)
        local out = {}
        for i, c in ipairs(letters) do
            out[i] = { mark(shift[i] or c), by_char[c] or c, sym2[i] or "", sym[i] or "" }
        end
        return out
    end
    local shift1 = { "َ", "ً", "ُ", "ٌ", "ِ", "ٍ", "ْ", "ّ", "ـ", "«", "»", "؟" }
    local shift2 = { "أ", "إ", "آ", "ٱ", "لا", "لأ", "لإ", "لآ", "؛", "،", ":", "!" }
    local shift3 = { "ذ", "ئ", "ء", "ؤ", "ة", "ى", "٫", "…", "-" }
    local row1 = row(chars("ضصثقفغعهخحجد"), shift1, chars("١٢٣٤٥٦٧٨٩٠−="), chars("~`|•√π÷×¶∆<>"))
    local row2 = row(chars("شسيبلاتنمكطذ"), shift2, chars("@#_&-+()/٪{}"), chars("£¥$¢^°={}\\[]"))
    local shift_key, backspace
    for _, r in ipairs(ar.keys) do
        for _, e in ipairs(r) do
            if e.label == "\u{ED35}" then shift_key = e end
            if e.label == "\u{E76D}" then backspace = e end
        end
    end
    local row3 = { { label = "\u{ED35}", width = 1.5 } }
    for _, e in ipairs(row(chars("ئءؤرىةوزظ"), shift3, chars("*\"':؛!؟«»"), chars("%©®™✓[]§¶"))) do table.insert(row3, e) end
    table.insert(row3, { label = "\u{E76D}", width = 1.5, bold = backspace and backspace.bold })
    local bottom = {
        -- the prototype's flex grows (1.5 · 1.1 · .8 · 5 · .8 · 2) stretched over the 12-key row
        { "رمز", "رمز", "حرف", "حرف", width = 1.61 }, -- ?١٢٣ / أبج (KOReader's symbols key)
        { label = "🌐", width = 1.18 },
        { "،", "،", "،", "،", width = 0.86 },
        { label = "مسافة", " ", " ", " ", " ", width = 5.35 },
        { ".", ".", ".", ".", width = 0.86 },
        { label = "⮠", "\n", "\n", "\n", "\n", width = 2.14 },
    }
    local out = {}
    for key, v in pairs(ar) do out[key] = v end
    out.keys = { row1, row2, row3, bottom }
    return out
end

local function HorizontalGroupNew(pad, w)
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    return VerticalGroup:new{ align = "left", VerticalSpan:new{ width = require("leaf/core").T.px("sp-2") },
        HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, w } }
end
local function TextBoxWidgetNew(text, width)
    local L = require("leaf/core")
    return require("ui/widget/textboxwidget"):new{ text = text, face = L.face("ui", "fs-xs"), fgcolor = L.T.color("text-3"),
        width = width, bgcolor = L.T.color("surface") }
end

function M.apply(L)
    local T = L.T
    do
        local name = "ui/data/keyboardlayouts/ar_keyboard"
        local ok, ar = pcall(require, name)
        if ok and type(ar) == "table" and ar.keys then
            package.loaded[name] = leaf_arabic(ar)
        end
    end
    do
        local name = "ui/data/keyboardlayouts/en_keyboard"
        local ok, en = pcall(require, name)
        if ok and type(en) == "table" and en.keys and #en.keys == 5 then
            package.loaded[name] = leaf_english(en)
        end
    end
    local VK = require("ui/widget/virtualkeyboard")
    -- VirtualKey is local to virtualkeyboard.lua: reach it through VirtualKeyboard.addKeys' upvalues
    local VirtualKey
    do
        local i = 1
        while true do
            local name, value = debug.getupvalue(VK.addKeys, i)
            if not name then break end
            if name == "VirtualKey" then VirtualKey = value end
            i = i + 1
        end
    end
    assert(VirtualKey, "VirtualKey not found")
    local vk_init_orig = VirtualKey.init -- (VirtualKeyPopup is one of its upvalues; read before wrapping)

    local function kind(self)
        local kb, label = self.keyboard, self.label
        if label == ENTER then return "enter" end
        local modifier = kb.shiftmode_keys[label] ~= nil or kb.shiftmode_keys[self.key] ~= nil
            or kb.symbolmode_keys[label] ~= nil or kb.umlautmode_keys[label] ~= nil
        if modifier then
            local active = (kb.shiftmode and (kb.shiftmode_keys[label] ~= nil or kb.shiftmode_keys[self.key] ~= nil))
                or (kb.umlautmode and kb.umlautmode_keys[label] ~= nil)
            if label == CAPS then return "caps" end
            return active and "on" or "fn"
        end
        if ICONS[label] then return "fn" end
        return "char"
    end

    L.wrap(VirtualKey, "init", function(orig, self)
        orig(self)
        local k = kind(self)
        -- on the symbol layers the shift key switches symbol pages: "=\<" / "?123" (.kb-t), not a shift
        local sym_shift = self.keyboard.symbolmode and (self.label == SHIFT or self.label == CAPS)
        if sym_shift then k = "fn" end
        local w, h = self.width, self.height
        local fg = (k == "fn") and "text-2" or (k == "enter" and "accent-ink") or (k == "caps" and "bg") or "text"
        local bg = ({ fn = "surface-3", enter = "accent", caps = "text" })[k] or "surface"

        local label
        local icon = ICONS[self.label]
        if k == "enter" then
            local submits = self.keyboard.inputbox and self.keyboard.inputbox.enter_callback
            if submits then
                -- the field may name its action (a search field: "Search"); else "Done"
                local t = self.keyboard.inputbox._leaf_enter_label or require("gettext")("Done")
                label = TextWidget:new{ text = t, face = L.face("ui-semibold", "fs-md"), fgcolor = T.color(fg) }
            else
                icon = "leaf.kb.enter"
            end
        end
        local kb = self.keyboard
        if not label and sym_shift then
            local arabic = (kb.getKeyboardLayout and kb:getKeyboardLayout() or ""):match("^ar")
            local text = kb.shiftmode and (arabic and "?١٢٣" or "?123") or "=\\<"
            label = TextWidget:new{ text = text, face = L.face("ui-semibold", "fs-sm"), fgcolor = T.color(fg) }
        elseif not label and kb.symbolmode_keys[self.label] ~= nil then
            -- the symbols key reads ?123 / ABC (.kb-t)
            local arabic = (kb.getKeyboardLayout and kb:getKeyboardLayout() or ""):match("^ar")
            local text = kb.symbolmode and (arabic and "أبج" or "ABC") or (arabic and "?١٢٣" or "?123")
            label = TextWidget:new{ text = text, face = L.face("ui-semibold", "fs-sm"), fgcolor = T.color(fg) }
        elseif not label and self.key == " " then
            -- the space bar names the keyboard language (.kb-lang)
            local lang = kb.getKeyboardLayout and kb:getKeyboardLayout() or "en"
            local NAMES = { ar = "العربية", en = "English" } -- as the prototype's LAYOUTS[].name
            local name = NAMES[lang] or require("ui/language"):getLanguageName(lang) or lang
            label = TextWidget:new{ text = name, face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3") }
        end
        if not label and icon then
            local s = T.px("icon-key")
            label = IconWidget:new{ icon = icon, width = s, height = s, alpha = true }
        elseif not label and self.icon then
            label = self.label_widget -- a key that already draws its own icon
        elseif not label then
            local text = self.label
            -- Arabic letters: Noto Naskh at --fs-key-ar (.kb-ar)
            local is_ar = text:find("[\216-\219]") ~= nil
            label = TextWidget:new{ text = text, face = is_ar and L.face("arabic", "fs-key-ar") or L.face("ui", "fs-key"), fgcolor = T.color(fg),
                max_width = w - 2 * T.px("sp-1") }
        end
        local content = CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, label }
        if false then -- .kb-key shows no long-press hints (holding a key still offers them)
            content = OverlapGroup:new{ dimen = Geom:new{ w = w, h = h },
                content,
                RightContainer:new{ dimen = Geom:new{ w = w - T.px("sp-1h"), h = T.px("sp-5") },
                    VerticalGroup:new{ VerticalSpan:new{ width = T.px("sp-half") },
                        TextWidget:new{ text = self.alt_label, face = L.face("ui", "fs-2xs"), fgcolor = T.color("text-3") } } },
            }
        end
        local frame = FrameContainer:new{
            margin = 0, padding = 0, allow_mirroring = false,
            radius = T.px("r-sm"),
            bordersize = (k == "on") and T.px("bw-lg") or T.px("hairline"),
            color = (k == "on") and T.color("text") or ((k == "enter" or k == "caps") and T.color(bg) or T.color("border-strong")),
            background = T.color(bg),
            content,
        }
        self[1] = frame
        -- holding the globe key always opens the layout chooser (KOReader shows a popup of the
        -- layouts when several are enabled; Leaf's chooser lists them with the rotation and default)
        if self.label == "🌐" and self.hold_callback then
            local state
            local i = 1
            while true do
                local name, value = debug.getupvalue(self.hold_callback, i)
                if not name then break end
                if name == "keyboard_state" then state = value end
                i = i + 1
            end
            if state then
                local key = self
                self.hold_callback = function()
                    key.keyboard:onSwitchingKeyboardLayout()
                    key.keyboard_layout_dialog = require("ui/widget/keyboardlayoutdialog"):new{ parent = key, keyboard_state = state }
                    require("ui/uimanager"):show(key.keyboard_layout_dialog)
                end
            end
        end
    end, "VirtualKey:init")

    L.wrap(VK, "addKeys", function(orig, self)
        -- 48px keys: size the keyboard from the key height instead of KOReader's 64px rows
        self.padding = T.px("sp-2")
        self.key_padding = T.px("sp-1h")
        local rows = #self.KEYS
        self.height = rows * T.px("h-row") + (rows + 1) * self.key_padding + 2 * self.padding
        orig(self)
        local frame = self[1] and self[1][1]
        if frame then
            frame.background = T.color("bg-raised")
            frame.color = T.color("border-strong")
            frame.bordersize = T.px("hairline")
        end
    end, "VirtualKeyboard:addKeys")
    ---------------------------------------------------------------- key popup (Gaps › key-popup)
    -- KOReader's VirtualKeyPopup (hold a key: accents and variants) keeps its keys and its place
    -- under the finger; it gets the popover look (.ko-popover.gp-kp: --surface, --r-lg, hairline
    -- --border-strong, --sp-2 padding), the held key as a function key (--surface-3) and a hint under
    -- the keys: "Slide to a letter and lift · or swipe on the key".
    local GW = require("leaf/widgets/gwkit")(L)
    local VirtualKeyPopup
    do
        local i = 1
        while true do
            local name, value = debug.getupvalue(vk_init_orig, i)
            if not name then break end
            if name == "VirtualKeyPopup" then VirtualKeyPopup = value end
            i = i + 1
        end
    end
    if VirtualKeyPopup then
        L.wrap(VirtualKeyPopup, "init", function(orig, self)
            orig(self)
            local pos = self[1]
            local frame = pos and pos[1]
            if not (frame and frame[1]) then return end
            frame.background = T.color("surface")
            frame.color = T.color("border-strong")
            frame.bordersize = T.px("hairline")
            frame.radius = T.px("r-lg")
            -- the held key: a function key (.kb-fn), not KOReader's light grey
            for _i, row in ipairs(self.layout or {}) do
                for _j, key in ipairs(row) do
                    if key.key == self.parent_key.key_chars[1] and key[1] then key[1].background = T.color("surface-3") end
                end
            end
            local keys = frame[1]
            local w = keys.dimen.w
            local hint = require("ui/widget/textboxwidget"):new{ text = require("gettext")("Slide to a letter and lift · or swipe on the key"),
                face = L.face("ui", "fs-xs"), fgcolor = T.color("text-3"), width = w, bgcolor = T.color("surface") }
            frame[1] = VerticalGroup:new{ align = "left", keys,
                VerticalSpan:new{ width = T.px("sp-1") }, CenterContainer:new{ dimen = Geom:new{ w = w, h = hint:getSize().h }, hint } }
            frame.dimen = frame:getSize()
            local x, y = pos.dimen.x, pos.dimen.y
            -- keep the whole popup on screen
            local H = require("device").screen:getHeight()
            if y + frame.dimen.h > H then pos.dimen.y = H - frame.dimen.h end
            self.dimen = Geom:new{ x = x, y = pos.dimen.y, w = frame.dimen.w, h = frame.dimen.h }
        end, "VirtualKeyPopup:init")
    end

    ---------------------------------------------------------------- layout chooser (Gaps › kb-layouts)
    -- KOReader's KeyboardLayoutDialog (hold the globe key) becomes a popover over the globe key:
    -- KEYBOARD LAYOUT, one radio row per layout (native name · in the rotation · default), tap =
    -- switch; then "All keyboard layouts…" (KOReader's own list) and a hint.
    local KeyboardLayoutDialog = require("ui/widget/keyboardlayoutdialog")
    L.wrap(KeyboardLayoutDialog, "init", function(orig, self)
        orig(self)
        if self._leaf_plain then return end
        local _ = require("gettext")
        local Language = require("ui/language")
        local util = require("util")
        local Screen = require("device").screen
        local UIManager = require("ui/uimanager")
        local W = math.floor(Screen:scaleBySize(320 * T.scale))
        local layouts = G_reader_settings:readSetting("keyboard_layouts", {})
        local default = G_reader_settings:readSetting("keyboard_layout_default")
        local kb = self.parent.keyboard
        local current
        self.keyboard_state.force_current_layout = true
        current = kb:getKeyboardLayout()
        self.keyboard_state.force_current_layout = false
        -- (KOReader falls back to the UI language, then English, as VirtualKeyboard:init does)
        if not kb.lang_to_keyboard_layout[current or ""] then
            current = (current or ""):sub(1, 2)
            if not kb.lang_to_keyboard_layout[current] then current = "en" end
        end
        local function close() UIManager:close(self.parent.keyboard_layout_dialog or self) end
        -- the layouts in the rotation, the current and the default first, then the others
        local list, seen = {}, {}
        local function add(k) if k and kb.lang_to_keyboard_layout[k] and not seen[k] then seen[k] = true table.insert(list, k) end end
        add(current) add(default)
        for _i, k in ipairs(layouts) do add(k) end
        for k in require("ffi/util").orderedPairs(kb.lang_to_keyboard_layout) do add(k) end
        -- "العربية · Arabic": KOReader's (native) name, then the English one
        local ENGLISH = { ar = "Arabic", bg = "Bulgarian", bn = "Bengali", ca = "Catalan", cs = "Czech", da = "Danish",
            de = "German", el = "Greek", eo = "Esperanto", es = "Spanish", fa = "Persian", fr = "French", he = "Hebrew",
            hr = "Croatian", hu = "Hungarian", it = "Italian", ja = "Japanese", ka = "Georgian", ko_KR = "Korean",
            lt = "Lithuanian", nb = "Norwegian", nl = "Dutch", pl = "Polish", pt_BR = "Portuguese", ro = "Romanian",
            ru = "Russian", sk = "Slovak", sv = "Swedish", th = "Thai", tr = "Turkish", uk = "Ukrainian", vi = "Vietnamese",
            zh = "Chinese", zh_CN = "Chinese" }
        local rows = VerticalGroup:new{ align = "left", GW.section(_("Keyboard layout"), W) }
        local max_rows = math.max(3, math.floor((Screen:getHeight() * 0.45) / T.px("h-row")))
        for i, k in ipairs(list) do
            if i > max_rows then break end
            local name = Language:getLanguageName(k) or k
            local label = (ENGLISH[k] and ENGLISH[k] ~= name) and (name .. " · " .. ENGLISH[k]) or name
            local sub = {}
            if util.arrayContains(layouts, k) then table.insert(sub, _("In the globe-key rotation")) end
            if k == default then table.insert(sub, _("Default")) end
            table.insert(rows, GW.pop_row{ width = W, label = label, sub = #sub > 0 and table.concat(sub, " · ") or nil,
                trailing = GW.radio(k == current), callback = function()
                    close()
                    kb:setKeyboardLayout(k)
                end })
        end
        table.insert(rows, GW.divider(W))
        table.insert(rows, GW.pop_row{ width = W, icon = "leaf.gw.settings-2", label = _("All keyboard layouts…"), callback = function()
            close()
            local d = KeyboardLayoutDialog:new{ parent = self.parent, keyboard_state = self.keyboard_state, _leaf_plain = true }
            self.parent.keyboard_layout_dialog = d
            UIManager:show(d)
        end })
        local pad = T.px("sp-4")
        table.insert(rows, HorizontalGroupNew(pad, TextBoxWidgetNew(_("Tap the globe key to switch between the layouts in the rotation."), W - 2 * pad)))
        table.insert(rows, VerticalSpan:new{ width = T.px("sp-1") })
        local pop = GW.Popover:new{ content = rows, anchor = self.parent.dimen, above = true, align = "left" }
        self[1] = pop.frame
        self.leaf_pop = pop
        self.dialog_frame = pop.frame
        self.movable = pop.frame
        self.paintTo = function(this, bb, x, y) pop.frame:paintTo(bb, pop.frame_dimen.x, pop.frame_dimen.y) end
        self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
        local GestureRange = require("ui/gesturerange")
        self.ges_events = self.ges_events or {}
        self.ges_events.TapLeafOutside = { GestureRange:new{ ges = "tap", range = self.dimen } }
        self.onTapLeafOutside = function(this, _arg, ges)
            if ges and ges.pos and ges.pos:intersectWith(pop.frame_dimen) then return false end
            close()
            return true
        end
        self.onShow = function()
            UIManager:setDirty(self, function() return "ui", pop.frame_dimen end)
        end
        self.onCloseWidget = function()
            UIManager:setDirty(nil, "ui", pop.frame_dimen)
        end
    end, "KeyboardLayoutDialog:init")
end

return M
