--[[
    Leaf text input (safety-net item 13): InputDialog, MultiInputDialog, InputText.
    Replaces the pre-Leaf patch 2-dialogs.lua (patches/legacy/). Target: prototype overlay "input".

    * Field (.kb-field--compact): soft filled --surface-2, --r-md corners, a hairline ring (--border), Inter --fs-md, --sp-3 padding (44px tall).
    * Compact dialogs: the title (Leaf TitleBar) has no rule under it; width is the Leaf dialog width
      (min(86%, 400px)) unless the caller chose one. Fullscreen editors keep their layout.
    * Actions: buttons.lua's action row (right-aligned, the last one primary).
--]]
local Device = require("device")
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local InputText = require("ui/widget/inputtext")
    local InputDialog = require("ui/widget/inputdialog")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TitleBar = require("ui/widget/titlebar")

    local field_bg = T.color("surface-2")
    InputDialog.input_face = L.face("ui", "fs-md")
    InputDialog.input_padding = T.px("sp-3")
    InputDialog.input_margin = 0 -- .kb-field--compact is 44px: no extra margin around the field

    local function style_field(input)
        local frame = input._frame_textwidget
        if not frame then return end
        frame.background = field_bg
        frame.radius = T.px("r-md")
        -- .kb-field: --ring-inset hairline (stronger on the field being typed in when there are several)
        frame.color = T.color("border")
        local tw = input.text_widget
        if tw then
            tw.bgcolor = field_bg
            if tw.text_widget then tw.text_widget.bgcolor = field_bg end -- ScrollTextWidget's inner box
        end
    end

    -- .dl-input.is-empty: the primary action looks unavailable (--disabled fill) until something is
    -- typed; it stays tappable (KOReader decides what an empty value does)
    local function primary_of(dialog)
        local bt = dialog and dialog.button_table
        local rows = bt and bt.buttons_layout
        local row = rows and rows[#rows]
        local b = row and row[#row]
        if b and b._leaf_kind == "primary" and b.frame then return b end
    end
    local function sync_primary(dialog, input)
        local b = primary_of(dialog)
        if not b then return end
        local empty = (input and input.text or "") == ""
        if b._leaf_empty == empty then return end
        b._leaf_empty = empty
        local c = T.color((empty or not b.enabled) and "disabled" or "accent")
        b.frame.background = c
        b.frame.color = c
        if b[1] and b[1].dimen then b:refresh() end
    end

    L.wrap(InputText, "initTextBox", function(orig, self, ...)
        local saved = TextBoxWidget.bgcolor
        TextBoxWidget.bgcolor = field_bg
        local ok, err = pcall(orig, self, ...)
        TextBoxWidget.bgcolor = saved
        if not ok then error(err, 0) end
        style_field(self)
        local d = self.parent
        if type(d) == "table" and d._leaf_compact and not self.for_measurement_only then sync_primary(d, self) end
    end, "InputText:initTextBox")
    for _, name in ipairs({ "focus", "unfocus" }) do
        if InputText[name] then
            L.wrap(InputText, name, function(orig, self, ...)
                local ret = orig(self, ...)
                style_field(self)
                return ret
            end, "InputText:" .. name)
        end
    end

    L.wrap(InputDialog, "init", function(orig, self)
        if self.fullscreen then return orig(self) end
        local pad = T.px("sp-5")
        -- the frame gets --sp-5 side padding: lay the content out in the inner width, and let the
        -- field fill it (KOReader uses 90%). KOReader re-runs init() (keyboard toggle, rotation):
        -- start from the original width every time.
        if not self._leaf_width then
            self._leaf_width = self.width or math.min(math.floor(Screen:getWidth() * 0.86), Screen:scaleBySize(400 * T.scale))
        end
        self.width = self._leaf_width - 2 * pad
        if not self.text_width then
            self.text_width = self.width - 2 * ((self.border_size or 0) + self.input_padding + self.input_margin)
        end
        -- compact dialogs: no rule under the title, title aligned with the field
        local orig_new = TitleBar.new
        TitleBar.new = function(class, o)
            o = o or {}
            o.with_bottom_line = false
            o.title_h_padding = 0
            o.bottom_v_padding = o.bottom_v_padding or T.px("sp-3") -- .kb-field--compact margin-top
            return orig_new(class, o)
        end
        local ok, err = pcall(orig, self)
        TitleBar.new = orig_new
        if not ok then error(err, 0) end
        -- (one-line compact dialogs only: editors and multi-field dialogs keep their buttons as they are)
        self._leaf_compact = not self.allow_newline and not self._added_widgets
        if self._leaf_compact then sync_primary(self, self._input_widget) end
        local frame = self.dialog_frame
        -- .ko-dialog-actions margin-top: --sp-4 between the field and the buttons
        local vg = frame and frame[1]
        if type(vg) == "table" and vg.resetLayout then
            for k = #vg, 2, -1 do
                if vg[k][1] == self.button_table and vg[k - 1].width and not vg[k - 1][1] then
                    vg[k - 1].width = T.px("sp-4") - require("ui/size").padding.buttontable
                    vg:resetLayout()
                    break
                end
            end
        end
        if frame then
            frame.padding_left = pad
            frame.padding_right = pad
            frame.background = T.color("surface")
        end
    end, "InputDialog:init")
    ---------------------------------------------------------------- clipboard (Gaps › clipboard, snippets, snippet-edit)
    -- Hold a text field: KOReader's clipboard viewer (a TextViewer with a grid of buttons) becomes a
    -- popover under the field: CLIPBOARD + the copied text (one line), Paste, Snippets (count ›),
    -- Copy all / line / word, Select text…, Undo last deletion, Delete all text (danger).
    -- Snippets: a bottom sheet (tap = insert, ⋯ = edit, New snippet); editing: a form dialog with
    -- TEXT and NAME · OPTIONAL fields and [Remove] … [Cancel] [Save]. Same actions as KOReader.
    local GW = require("leaf/widgets/gwkit")(L)
    local Kit = require("leaf/widgets/kit")
    local UIManager = require("ui/uimanager")
    local Notification = require("ui/widget/notification")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local _ = require("gettext")

    local function notify(text) UIManager:show(Notification:new{ text = text }) end

    local function clipboard_popover(self)
        local W = math.floor(Screen:scaleBySize(320 * T.scale))
        local clip = Device.input.getClipboardText() or ""
        local empty = clip == ""
        local pop
        local function act(cb) return function() UIManager:close(pop) cb() end end
        local snippets = self.clipboard_settings.snippets
        local inner = W - 2 * T.px("sp-4")
        local one_line = clip:gsub("%s+", " ")
        local top = VerticalGroup:new{ align = "left",
            GW.vspan("sp-1"),
            HorizontalGroup:new{ GW.hspan("sp-4"), HorizontalGroup:new{ align = "center",
                GW.icon("leaf.gw.clipboard", "icon-xs", "text-3"), GW.hspan("sp-1"),
                GW.text(_("Clipboard"):upper(), "ui-semibold", "fs-xs", "text-3") } },
            GW.vspan("sp-1"),
            HorizontalGroup:new{ GW.hspan("sp-4"),
                GW.text(empty and _("Nothing copied yet") or ("“" .. one_line .. "”"), "ui", "fs-sm", empty and "text-3" or "text-2", inner) },
            GW.vspan("sp-3"), GW.line(W), GW.vspan("sp-1") }
        local content = VerticalGroup:new{ align = "left", top,
            GW.pop_row{ width = W, icon = "leaf.gw.clipboard-paste", label = _("Paste"), disabled = empty,
                callback = act(function() self:addChars(clip) end) },
            GW.pop_row{ width = W, icon = "leaf.gw.pin", label = _("Snippets"), value = snippets and tostring(#snippets) or nil,
                chevron = true, disabled = self.disable_clipboard_snippet_edit and not snippets,
                callback = act(function() self:showClipboardSnippets() end) },
            GW.divider(W),
            GW.pop_row{ width = W, icon = "leaf.gw.copy", label = _("Copy all"), callback = act(function()
                Device.input.setClipboardText(table.concat(self.charlist))
                notify(_("All text copied to clipboard."))
            end) },
            GW.pop_row{ width = W, icon = "leaf.gw.text", label = _("Copy line"), callback = act(function()
                Device.input.setClipboardText(table.concat(self.charlist, "", self:getStringPos()))
                notify(_("Line copied to clipboard."))
            end) },
            GW.pop_row{ width = W, icon = "leaf.gw.type", label = _("Copy word"), callback = act(function()
                Device.input.setClipboardText(table.concat(self.charlist, "", self:getStringPos(true)))
                notify(_("Word copied to clipboard."))
            end) },
            GW.pop_row{ width = W, icon = "leaf.gw.text-select", label = _("Select text…"),
                sub = _("Long-press the start, then the end"), callback = act(function()
                    notify(_("Set cursor to start of selection, then long-press in text box."))
                    self.do_select = true
                    self:initTextBox()
                end) },
            GW.divider(W),
            GW.pop_row{ width = W, icon = "leaf.gw.undo-2", label = _("Undo last deletion"), disabled = self.undo_charlist == nil,
                callback = act(function() self:undoLastDeletion() end) },
            GW.pop_row{ width = W, icon = "leaf.gw.trash-2", label = _("Delete all text"), danger = true,
                disabled = #self.charlist == 0, callback = act(function() self:delAll() end) },
        }
        local anchor = self._frame_textwidget and self._frame_textwidget.dimen or self.dimen
        pop = GW.Popover:new{ content = content, anchor = anchor, align = "left" }
        UIManager:show(pop)
        return pop
    end
    M.clipboard_popover = clipboard_popover

    L.wrap(InputText, "holdTextBox", function(orig, self, arg, ges)
        if not self.clipboard_settings or self.do_select then return orig(self, arg, ges) end
        if self.parent and self.parent.onSwitchFocus then self.parent:onSwitchFocus(self) end
        self._hold_handled = nil
        clipboard_popover(self)
        self._hold_handled = true
        return true
    end, "InputText:holdTextBox")

    -- snippets sheet
    local SnippetSheet = require("ui/widget/container/inputcontainer"):extend{ modal = true, _leaf_wants_scrim = true }
    function SnippetSheet:init()
        local W = Screen:getWidth()
        local it = self.input
        local inner = Kit.inner(W)
        local function close() UIManager:close(self) end
        local rows = {}
        for i, v in ipairs(it.clipboard_settings.snippets or {}) do
            local edit = not it.disable_clipboard_snippet_edit and GW.icon_btn{ icon = "leaf.gw.ellipsis", size = "icon-sm", callback = function()
                close()
                it:editClipboardSnippet(i)
            end } or nil
            table.insert(rows, GW.row{ width = inner, icon = "leaf.gw.pin", label = v.name or v.text, sub = v.name and v.text or nil,
                trailing = edit, callback = function()
                    close()
                    it:addChars(v.text)
                end, hold_callback = edit and function()
                    close()
                    it:editClipboardSnippet(i)
                end or nil })
        end
        local list = VerticalGroup:new{ align = "left" }
        for i, r in ipairs(rows) do
            if i > 1 then
                local inset = T.px("sp-5") + T.px("icon-md") + T.px("sp-3")
                table.insert(list, HorizontalGroup:new{ GW.hspan(inset), GW.line(inner - inset) })
            end
            table.insert(list, r)
        end
        if #rows == 0 then
            table.insert(list, GW.help(_("No snippets yet. Save text you type often, then insert it from here."), inner))
        end
        local right = { GW.button{ label = _("New snippet"), icon = "leaf.gw.plus", kind = "primary",
            enabled = not it.disable_clipboard_snippet_edit, callback = function()
                close()
                it:editClipboardSnippet()
            end } }
        local content = VerticalGroup:new{ align = "left",
            Kit.head{ width = inner, title = _("Snippets"), sub = _("Tap to insert · ⋯ to edit"), on_close = close, parent = self },
            list, GW.vspan("sp-3"),
            GW.foot{ width = inner, left = { GW.button{ label = _("Close"), kind = "ghost", callback = close } }, right = right } }
        local frame, container = Kit.sheet{ content = content }
        self.frame = frame
        self[1] = container
        self.dimen = GW.geom(W, Screen:getHeight())
        local GestureRange = require("ui/gesturerange")
        self.ges_events = { TapOut = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    end
    function SnippetSheet:onTapOut(_arg, ges)
        if ges and ges.pos and self.frame.dimen and ges.pos:intersectWith(self.frame.dimen) then return true end
        UIManager:close(self)
        return true
    end
    function SnippetSheet:onClose() UIManager:close(self) return true end
    function SnippetSheet:onShow() UIManager:setDirty(self, "ui") return true end
    function SnippetSheet:onCloseWidget() UIManager:setDirty(nil, "ui") end

    L.wrap(InputText, "showClipboardSnippets", function(orig, self)
        UIManager:show(SnippetSheet:new{ input = self })
    end, "InputText:showClipboardSnippets")

    -- replace a field description (TextBoxWidget) by a .ko-eyebrow label
    local function eyebrow(widget, text)
        if type(widget) ~= "table" then return false end
        for k, child in ipairs(widget) do
            if type(child) == "table" then
                if child.text == text and child.face and child.width then
                    local lbl = GW.text(text:upper(), "ui-semibold", "fs-xs", "text-3", child.width)
                    widget[k] = require("ui/widget/container/leftcontainer"):new{
                        dimen = GW.geom(child.width, child:getSize().h), lbl }
                    return true
                end
                if eyebrow(child, text) then return true end
            end
        end
        return false
    end
    M.eyebrow = eyebrow

    L.wrap(InputText, "editClipboardSnippet", function(orig, self, idx)
        local MultiInputDialog = require("ui/widget/multiinputdialog")
        local item = idx and self.clipboard_settings.snippets[idx]
        local d
        local buttons = {}
        if idx then
            table.insert(buttons, { text = _("Remove"), leaf_left = true, callback = function()
                UIManager:close(d)
                table.remove(self.clipboard_settings.snippets, idx)
                if not next(self.clipboard_settings.snippets) then self.clipboard_settings.snippets = nil end
                self:showClipboardSnippets()
            end })
        end
        table.insert(buttons, { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end })
        table.insert(buttons, { text = _("Save"), callback = function()
            local fields = d:getFields()
            if fields[1] ~= "" then
                UIManager:close(d)
                self.clipboard_settings.snippets = self.clipboard_settings.snippets or {}
                idx = idx or #self.clipboard_settings.snippets + 1
                self.clipboard_settings.snippets[idx] = { text = fields[1], name = fields[2] ~= "" and fields[2] or nil }
                self:showClipboardSnippets()
            end
        end })
        local text_label, name_label = _("Text"), _("Name · optional")
        d = MultiInputDialog:new{
            title = item and _("Edit snippet") or _("New snippet"),
            fields = {
                { text = item and item.text or Device.input.getClipboardText(), hint = _("Snippet text"),
                    allow_newline = true, description = text_label, height = Screen:scaleBySize(88 * T.scale) },
                { text = item and item.name, hint = _("Shown instead of the text"), description = name_label },
            },
            disable_clipboard_snippet_edit = true,
            buttons = { buttons },
        }
        eyebrow(d, text_label)
        eyebrow(d, name_label)
        -- the Leaf dialog padding around KOReader's form (it builds its own frame)
        if d.dialog_frame then
            d.dialog_frame.padding_left = T.px("sp-5")
            d.dialog_frame.padding_right = T.px("sp-5")
            d.dialog_frame.background = T.color("surface")
        end
        UIManager:show(d)
        d:onShowKeyboard()
        return d
    end, "InputText:editClipboardSnippet")
end

return M
