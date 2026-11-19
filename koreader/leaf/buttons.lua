--[[
    Leaf buttons (safety-net item 5): Button, ButtonTable.

    Every Button: Inter Medium --fs-md label, --r-md corners; bold = Inter SemiBold.

    Dialog action rows: the last row of a ButtonTable, when it has 1-3 text buttons and the table is
    inside one of the ACTION_PARENTS dialogs (confirm, input, spin, text viewer...) is laid out like .ko-dialog-actions:
    buttons at their natural width, --h-control (40px) high, right-aligned with --sp-1 gaps, no grid
    lines. Kinds, as in UI.dialog():
      * several buttons: the last one is primary (accent fill), or danger when its label starts with
        Delete/Remove/Erase/Reset/Clear/Purge; the others are ghost (no fill, --text-2 label).
        If the last one is a Cancel/Close, nothing is primary.
      * a single button: secondary (--surface-2 fill).
    Rows that do not fit, icon buttons, multi-row tables (ButtonDialog grids) keep KOReader's layout
    with the Leaf font and separators: those surfaces get their own design later.
--]]
local Blitbuffer = require("ffi/blitbuffer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalSpan = require("ui/widget/verticalspan")

local M = {}

M.ACTION_PARENTS = {
    "ui/widget/confirmbox", "ui/widget/multiconfirmbox", "ui/widget/inputdialog",
    "ui/widget/multiinputdialog", "ui/widget/spinwidget", "ui/widget/doublespinwidget",
    "ui/widget/datetimewidget", "ui/widget/textviewer",
}
local DANGER = { delete = true, remove = true, erase = true, reset = true, clear = true, purge = true }
local CANCEL = { cancel = true, close = true, no = true, back = true }

local function first_word(text)
    return (tostring(text or ""):match("^%s*([%a]+)") or ""):lower()
end

local function is_a(obj, class)
    local mt = getmetatable(obj)
    while mt do
        if mt == class then return true end
        mt = getmetatable(mt)
    end
    return false
end

function M.apply(L)
    local T = L.T
    local fonts = require("leaf/fonts")
    local Button = require("ui/widget/button")
    local ButtonTable = require("ui/widget/buttontable")

    local medium = fonts.FILES["ui-medium"]
    Button.text_font_face = medium
    Button.text_font_size = T.fs("fs-md")
    Button.text_font_bold = false
    Button.radius = T.px("r-md")

    local KIND = {
        primary = { bg = "accent", fg = "accent-ink", bold = true },
        danger = { bg = "danger", fg = "danger-ink", bold = true },
        secondary = { bg = "surface-2", fg = "text" },
        ghost = { fg = "text-2" },
        -- list rows built from buttons (sheets): regular weight, --text / --danger label
        row = { fg = "text", face = "ui" },
        ["row-danger"] = { fg = "danger", face = "ui" },
        -- small text buttons (footers: "Page 1 of 4")
        caption = { fg = "text-2", face = "ui", size = "fs-sm" },
    }
    -- on e-ink the danger red is only a mid grey: make it the strongest button (.eink .ko-btn--danger)
    local DANGER_EINK = { bg = "text", fg = "bg", bold = true }
    local function kind(name)
        if name == "danger" and not require("device").screen:isColorEnabled() then return DANGER_EINK end
        return KIND[name]
    end

    local function color_label(self)
        local k = kind(self._leaf_kind)
        local lw = self.label_widget
        -- (truthiness, not ~= nil: LuaJIT calls a cdata colour's __eq even against nil)
        if not (k and lw and lw.fgcolor) then return end
        lw.fgcolor = T.color(self.enabled and k.fg or "disabled")
        if lw.update then lw:update() end
        -- a disabled filled button loses its fill (like .ko-btn:disabled), so it can't read as the action
        if k.bg and self.frame then
            local bg = T.color(self.enabled and k.bg or "surface-2")
            self.frame.background = bg
            self.frame.color = bg
        end
    end

    L.wrap(Button, "init", function(orig, self)
        local k = kind(self._leaf_kind)
        if k then
            self.background = k.bg and T.color(k.bg) or nil
            self.radius = T.px("r-md")
            self.text_font_face = k.face and fonts.FILES[k.face] or medium
            self.text_font_size = T.fs(k.size or "fs-md")
            self.text_font_bold = k.bold or false
        end
        orig(self)
        color_label(self)
    end, "Button:init")
    for _, method in ipairs({ "enable", "disable" }) do
        L.wrap(Button, method, function(orig, self, ...)
            orig(self, ...)
            color_label(self)
        end, "Button:" .. method)
    end

    local parents = {}
    for _, mod in ipairs(M.ACTION_PARENTS) do
        local ok, class = pcall(require, mod)
        if ok then table.insert(parents, class) end
    end
    local function is_action_parent(p)
        if not p then return false end
        for _, class in ipairs(parents) do
            if is_a(p, class) then return true end
        end
        return false
    end

    -- the action row is the LAST row of an action dialog's table (rows above it, like the
    -- spin widget's "Default value", keep KOReader's layout)
    local function action_row(self)
        local rows = self.buttons
        local last = rows and rows[#rows]
        if not (last and #last >= 1 and #last <= 3) then return end
        if not is_action_parent(self.show_parent) then return end
        for _, e in ipairs(last) do
            if e.icon or e.width or not (e.text or e.text_func) then return end
        end
        return last
    end

    L.wrap(ButtonTable, "init", function(orig, self)
        local row = action_row(self)
        if not row then return orig(self) end

        local n = #row
        local kinds = {}
        for i, e in ipairs(row) do
            local word = first_word(e.text or (e.text_func and e.text_func()))
            if e.leaf_left then kinds[i] = "ghost" -- e.g. "Default · 14": a side action at the left edge
            elseif n == 1 then kinds[i] = "secondary"
            elseif i < n then kinds[i] = "ghost"
            elseif DANGER[word] then kinds[i] = "danger"
            elseif CANCEL[word] then kinds[i] = "ghost"
            else kinds[i] = "primary" end
        end

        -- natural widths at the label font (+ --sp-4 each side), 40px tall
        local pad_h = T.px("sp-4")
        local min_w = math.floor(T.px("h-control") * 1.6)
        local gap = T.px("sp-1")
        local widths, total = {}, 0
        for i, e in ipairs(row) do
            local tw = TextWidget:new{
                text = e.text or e.text_func(),
                face = require("ui/font"):getFace(medium, T.fs("fs-md")),
                bold = KIND[kinds[i]].bold or false,
            }
            widths[i] = math.max(min_w, tw:getSize().w + 2 * pad_h + 2 * Size.padding.button)
            tw:free()
            total = total + widths[i] + (i > 1 and gap or 0)
        end
        if total > (self.width or 0) then return orig(self) end

        -- let KOReader build it (ids, focus layout, callbacks), with our sizes
        local saved = {}
        for i, e in ipairs(row) do
            saved[i] = { e.width, e.height }
            e.width = widths[i]
            e.height = T.px("h-control") - 2 * Size.padding.buttontable
        end
        local ok, err = pcall(orig, self)
        for i, e in ipairs(row) do e.width, e.height = saved[i][1], saved[i][2] end
        if not ok then error(err, 0) end

        -- restyle the buttons, then rebuild the row: right-aligned, gaps, no lines
        local buttons = self.buttons_layout[#self.buttons_layout]
        -- [leaf_left buttons] <free space> [the others], like .ko-dialog-actions with a .grow
        local left, right = {}, {}
        for i, b in ipairs(buttons) do
            b._leaf_kind = kinds[i]
            b:free()
            b:init()
            table.insert(row[i].leaf_left and left or right, b)
        end
        local group = HorizontalGroup:new{ align = "center" }
        local function add(list)
            for k, b in ipairs(list) do
                if k > 1 then table.insert(group, HorizontalSpan:new{ width = gap }) end
                table.insert(group, b)
            end
        end
        -- `total` counted a gap between every pair of buttons; the free space replaces the one
        -- between the left and the right group (if both exist)
        local free = self.width - total + ((#left > 0 and #right > 0) and gap or 0)
        add(left)
        table.insert(group, HorizontalSpan:new{ width = free })
        add(right)
        local c = self.container
        local replaced = false
        for i = #c, 1, -1 do
            local w = c[i]
            if is_a(w, LineWidget) then
                table.remove(c, i)
            elseif is_a(w, HorizontalGroup) and not replaced then
                c[i] = group  -- the last row
                replaced = true
            end
        end
        -- breathing room under the actions (dialogs put no padding under their button table)
        table.insert(c, VerticalSpan:new{ width = T.px("sp-5") }) -- = the dialog's --sp-5 padding
        c:resetLayout()
    end, "ButtonTable:init")
end

return M
