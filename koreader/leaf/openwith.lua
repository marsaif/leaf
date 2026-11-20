--[[
    Leaf "Open with" (Gaps › open-with): KOReader's OpenWithDialog (file long-press › Open with…).

    A bottom sheet: head "Open with" + the file name, × on the right; ENGINE: one radio row per
    engine in a card, with a human name and what it does ("Leaf reflowable reader · EPUB, FB2, MOBI,
    HTML · KOReader: crengine"); the two "always use it" checks (for this file / for .ext files);
    a card with KOReader's other rows (reset the default for this file / for .ext files, defaults
    for file types); foot [Cancel] … [Open]. The "Always open …?" confirmation names the engine the
    same way. Radio table, check buttons and buttons stay KOReader's (the Open callback reads them).
--]]
local Device = require("device")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

local ENGINES = {
    crengine = { icon = "leaf.gw.book-open-text", name = "Leaf reflowable reader", short = "reflowable reader",
        sub = "EPUB, FB2, MOBI, HTML · KOReader: crengine" },
    mupdf = { icon = "leaf.gw.file-text", name = "Leaf page reader", short = "page reader",
        sub = "Keeps the original page layout · KOReader: MuPDF" },
    djvulibre = { icon = "leaf.gw.file-text", name = "DjVu reader", short = "DjVu reader", sub = "KOReader: DjVu Libre" },
    picdocument = { icon = "leaf.gw.file-image", name = "Picture reader", short = "picture reader", sub = "Images as pages · KOReader: Picture Document" },
    texteditor = { icon = "leaf.gw.file-code", name = "Text editor", short = "text editor", sub = "Opens the file as plain text" },
    archiveviewer = { icon = "leaf.gw.file-archive", name = "Archive viewer", short = "archive viewer", sub = "Lists the files inside" },
    imageviewer = { icon = "leaf.gw.file-image", name = "Image viewer", short = "image viewer", sub = "Shows the image full screen" },
    textviewer = { icon = "leaf.gw.text", name = "Text viewer", short = "text viewer", sub = "Shows the text, read-only" },
}

local function engine(provider)
    if not provider then return {} end
    local key = provider.provider or ""
    local e = ENGINES[key]
    if not e then
        local n = (provider.provider_name or ""):lower()
        if n:find("image") then e = ENGINES.imageviewer
        elseif n:find("text viewer") then e = ENGINES.textviewer
        elseif n:find("text") then e = ENGINES.texteditor
        elseif n:find("archive") then e = ENGINES.archiveviewer end
    end
    return e or { icon = "leaf.gw.file", name = provider.provider_name, short = provider.provider_name }
end
M.engine = engine

function M.apply(L)
    local T = L.T
    local GW = require("leaf/widgets/gwkit")(L)
    local Kit = require("leaf/widgets/kit")
    local OpenWithDialog = require("ui/widget/openwithdialog")
    local ConfirmBox = require("ui/widget/confirmbox")
    local DocumentRegistry = require("document/documentregistry")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local GestureRange = require("ui/gesturerange")
    local ffiUtil = require("ffi/util")

    local function file_of(title)
        local pre, post = _("Open %1 with:"):match("^(.-)%%1(.*)$")
        if pre and title:sub(1, #pre) == pre and (post == "" or title:sub(-#post) == post) then
            return title:sub(#pre + 1, #title - #post)
        end
        return title
    end

    local function check_row(w, cb_widget, label)
        local enabled = cb_widget.enabled ~= false
        local h = T.px("hit")
        local g = HorizontalGroup:new{ align = "center", GW.check(cb_widget.checked, enabled), GW.hspan("sp-2h"),
            GW.text(label, "ui", "fs-md", enabled and "text" or "disabled", w - T.px("icon-md") - T.px("sp-2h")) }
        return Kit.Tap:new{ width = w, height = h, enabled = enabled, content = LeftContainer:new{ dimen = GW.geom(w, h), g },
            callback = function() cb_widget:toggleCheck() end }
    end

    local function build(self)
        local W = Screen:getWidth()
        local inner = Kit.inner(W)
        local file = file_of(self.title or "")
        local ext = (file:match("%.([^%.]+)$") or ""):lower()
        local function close() UIManager:close(self) end
        local rbt = self.radio_button_table
        local engines = {}
        for _i, row in ipairs(rbt.radio_buttons_layout or {}) do
            for _j, button in ipairs(row) do
                local p = button.provider
                local e = engine(p)
                local unsupported = button.text and button.text:find("~", 1, true)
                table.insert(engines, GW.row{ width = GW.group_inner(W), pad = T.px("sp-4"), icon = e.icon,
                    label = e.name .. (unsupported and (" · " .. _("unsupported")) or ""), sub = e.sub,
                    trailing = GW.radio(rbt.checked_button == button), callback = function()
                        rbt:checkButton(button)
                        if rbt.button_select_callback then rbt.button_select_callback(button) end
                        self:_leafBuild()
                    end })
            end
        end
        local body = VerticalGroup:new{ align = "left",
            Kit.head{ width = inner, title = _("Open with"), sub = file, on_close = close, parent = self },
            GW.section(_("Engine"), inner, T.px("sp-5")),
            GW.group(engines, inner) }
        local pad = T.px("sp-4")
        local cw = inner - 2 * pad
        table.insert(body, GW.vspan("sp-3"))
        table.insert(body, HorizontalGroup:new{ GW.hspan(pad), check_row(cw, self._check_file_button, _("Always use it for this file")) })
        table.insert(body, HorizontalGroup:new{ GW.hspan(pad), check_row(cw, self._check_global_button,
            ext ~= "" and string.format(_("Always use it for .%s files"), ext) or _("Always use it for this file type")) })
        -- KOReader's other rows (all but the last: Cancel / Open)
        local extra = {}
        local rows = self.buttons or {}
        for i = 1, #rows - 1 do
            local e = rows[i][1]
            if e and e.text then
                local t = e.text
                local o = { width = GW.group_inner(W), pad = T.px("sp-4"), callback = function() e.callback() end }
                if t == _("Reset default for this file") then
                    o.icon, o.label = "leaf.gw.rotate-ccw", _("Reset the default for this file")
                elseif t == ffiUtil.template(_("Reset default for %1 files"), ext) then
                    o.icon, o.label = "leaf.gw.rotate-ccw", string.format(_("Reset the default for .%s files"), ext)
                    local key = DocumentRegistry:getAssociatedProviderKey(self._leaf_file or file, true)
                    local p = key and DocumentRegistry:getProviderFromKey(key)
                    if p then o.sub = _("Now:") .. " " .. (engine(p).name or "") end
                elseif t == _("View defaults for file types") then
                    o.icon, o.label, o.chevron = "leaf.gw.list", _("Defaults for file types"), true
                else
                    o.icon, o.label = "leaf.gw.settings-2", t
                end
                table.insert(extra, GW.row(o))
            end
        end
        if #extra > 0 then
            table.insert(body, GW.vspan("sp-3"))
            table.insert(body, GW.group(extra, inner))
        end
        table.insert(body, GW.vspan("sp-3"))
        local last = rows[#rows] or {}
        local cancel, open = last[1], last[2]
        table.insert(body, GW.foot{ width = inner,
            left = { GW.button{ label = cancel and cancel.text or _("Cancel"), kind = "ghost", callback = function()
                if cancel and cancel.callback then cancel.callback() else close() end
            end } },
            right = { open and GW.button{ label = open.text, kind = "primary", callback = function() self._leaf_open() end } or nil } })
        self._leaf_open = function()
                -- "Always open …?" names the engine as above
                local orig_new = ConfirmBox.new
                local provider = rbt.checked_button and rbt.checked_button.provider
                ConfirmBox.new = function(class, o)
                    o = o or {}
                    local e = engine(provider)
                    if self._check_file_button.checked then
                        o.text = string.format(_("Always open “%s” with the %s?"), file, e.short or "") .. "\n" .. _("You can change it later from Open with.")
                    elseif self._check_global_button.checked then
                        o.text = string.format(_("Always open .%s files with the %s?"), ext, e.short or "") .. "\n" .. _("You can change it later from Open with.")
                    end
                    return orig_new(class, o)
                end
                local ok, err = pcall(open.callback)
                ConfirmBox.new = orig_new
                if not ok then error(err, 0) end
        end
        local frame, container = Kit.sheet{ content = body }
        self.dialog_frame = frame
        self.movable = frame
        self[1] = container
        UIManager:setDirty(self, "ui")
    end

    L.wrap(OpenWithDialog, "init", function(orig, self)
        orig(self)
        self._leaf = true
        self._leafBuild = build
        -- re-render the checks when they toggle
        for _i, cb in ipairs({ self._check_file_button, self._check_global_button }) do
            local toggle = cb.toggleCheck
            cb.toggleCheck = function(this, ...)
                toggle(this, ...)
                if self._leaf then build(self) end
            end
        end
        build(self)
        self.ges_events = self.ges_events or {}
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.ges_events.LeafTapOut = { GestureRange:new{ ges = "tap", range = GW.geom(W, H) } }
        self._leaf_wants_scrim = true
    end, "OpenWithDialog:init")
    function OpenWithDialog:onLeafTapOut(_arg, ges)
        if ges and ges.pos and self.dialog_frame and self.dialog_frame.dimen and ges.pos:intersectWith(self.dialog_frame.dimen) then
            return true
        end
        UIManager:close(self)
        return true
    end
end

return M
