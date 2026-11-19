--[[
    Leaf book actions (prototype overlay "book-actions"): the long-press sheet of a book in the
    library, folders, favorites / collections and history.

      head:   cover · title · file name · "EPUB · 0.3 MB · Reading · 8%" · ×
      tools:  Copy · Cut · Paste · Select · Rename · Delete (.ko-tool--lg, Delete in --danger)
      MARK AS: Reading | On hold | Finished (.ko-seg, selected = ✓ + accent) · ↺ Reset
      BOOK:   Book information › · Book description › · Book cover › · Collections… (n) › ·
              Bookmarks › · Export highlights · Open with… ›
      METADATA & CACHE: Ignore cover (toggle) · Ignore metadata (toggle) · Refresh cached book information
      MORE:   every other button KOReader / plugins put in that dialog (Convert, Remove from
              history, Remove from collection, …)

    KOReader still builds its dialog (the file manager's, history's or a collection's, with Project:
    Title's buttons): this module finds it by its "Book information" button, takes the file from
    that button, and draws the sheet from the dialog's own buttons, so every action (and anything
    a plugin adds) keeps its callback. Other ButtonDialogs are left to leaf/sheets.lua.
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen

local M = {}

-- the file a KOReader file dialog is about (from its "Book information" button)
local function dialog_file(buttons)
    local info = _("Book information")
    for _i, row in ipairs(buttons or {}) do
        for _j, b in ipairs(row) do
            if b.text == info and type(b.callback) == "function" then
                for k = 1, 30 do
                    local n, v = debug.getupvalue(b.callback, k)
                    if not n then break end
                    if n == "doc_settings_or_file" then
                        if type(v) == "string" then return v end
                        if type(v) == "table" and v.readSetting then return v:readSetting("doc_path") end
                    end
                end
            end
        end
    end
end
M.dialogFile = dialog_file

function M.apply(L)
    local T = L.T
    local ButtonDialog = require("ui/widget/buttondialog")
    local K = require("leaf/syskit")(L)
    local P = require("leaf/widgets/libparts")

    local function geom(w, h) return Geom:new{ x = 0, y = 0, w = math.floor(w), h = math.floor(h) } end
    local function strip(t) return (tostring(t or ""):gsub("%s*✓%s*$", "")) end

    -- .ko-tool--lg: icon over label, 64px
    local function tool(icon, label, b, w)
        local enabled = b and b.enabled ~= false
        local I = require("leaf/libitems")(L)
        local danger = label == _("Delete")
        local col = VerticalGroup:new{ align = "center",
            enabled and (danger and I.InkIcon:new{ icon = icon, size = T.px("icon-md"), color = T.color("danger") } or K.icon(icon, "icon-md"))
                or K.icon(icon, "icon-md", true),
            K.vspan("sp-1h"),
            K.text(label, "ui", "fs-sm", not enabled and "disabled" or (danger and "danger" or "text-2"), w) }
        local box = CenterContainer:new{ dimen = geom(w, P.px(64)), col }
        if not enabled then return box end
        return K.tap(box, function() b.callback() end)
    end

    local function seg(width, cur, handlers)
        local I = require("leaf/libitems")(L)
        local en = {}
        for k, b in pairs(handlers) do en[k] = b.enabled ~= false end
        return I.statusSeg(width, cur, function(key) if handlers[key] then handlers[key].callback() end end,
            setmetatable(en, { __index = function() return false end }))
    end

    -- a .ko-group: card of rows with inset hairlines
    local function group(rows, W)
        local gw = W - 2 * T.px("sp-4")
        local inner = gw - 2 * T.px("hairline")
        local built = {}
        for _i, r in ipairs(rows) do
            local b = r.button
            local enabled = not b or b.enabled ~= false
            local trailing = r.trailing
            if not trailing and r.value then
                trailing = HorizontalGroup:new{ align = "center", K.text(r.value, "ui", "fs-sm", "text-3"),
                    r.chev and K.hspan("sp-2") or nil, r.chev and K.icon("leaf.lib.chevright", "icon-sm") or nil }
            elseif not trailing and r.chev then
                trailing = K.icon("leaf.lib.chevright", "icon-sm")
            end
            table.insert(built, K.row{ width = inner, icon = r.icon, label = r.label, trailing = trailing, dim = not enabled,
                pad = T.px("sp-4"), height = r.height, danger = r.danger,
                callback = enabled and b and function() b.callback() end or nil })
        end
        return HorizontalGroup:new{ K.hspan("sp-4"), K.card(gw, K.list(built, inner, { inset = T.px("sp-4") }), { flush = true }) }
    end

    local function section(text, W)
        return VerticalGroup:new{ align = "left", K.vspan("sp-4"),
            HorizontalGroup:new{ K.hspan("sp-5"), K.text(text:upper(), "ui-semibold", "fs-xs", "text-3") }, K.vspan("sp-2") }
    end

    function M.build(dialog, file, W)
        local I = require("leaf/libitems")(L)
        local by = {}
        local rest = {}
        local known = {
            [C_("File", "Copy")] = true, [_("Cut")] = true, [C_("File", "Paste")] = true, [_("Select")] = true,
            [_("Rename")] = true, [_("Delete")] = true, [_("Reset")] = true, [_("Book information")] = true,
            [_("Book description")] = true, [_("Book cover")] = true, [_("Collections…")] = true, [_("Bookmarks")] = true,
            [_("Export highlights")] = true, [_("Open with…")] = true, [_("Ignore cover")] = true, [_("Unignore cover")] = true,
            [_("Ignore metadata")] = true, [_("Unignore metadata")] = true, [_("Refresh cached book information")] = true,
        }
        local status_of = { [C_("Status of single book", "Reading")] = "reading",
            [C_("Status of single book", "On hold")] = "abandoned", [C_("Status of single book", "Finished")] = "complete" }
        local status_btn = {}
        for _i, row in ipairs(dialog.buttons or {}) do
            for _j, b in ipairs(row) do
                local t = b.text or (b.text_func and b.text_func())
                if t then
                    local st = status_of[strip(t)]
                    if st then status_btn[st] = b
                    elseif known[t] then by[t] = b
                    else table.insert(rest, b) end
                end
            end
        end
        local d = I.data(file)
        local inner = W - 2 * T.px("hairline")
        local close = function() dialog:onClose() end

        -- head (.lba-head)
        local cov = P.coverBox(file, T.px("hit"), P.px(66), { title = d.title, cache_only = false, radius = T.px("r-thumb"), bg = T.color("bg-raised") })
        local tw = inner - T.px("sp-5") - T.px("hit") - T.px("sp-4") - T.px("hit") - T.px("sp-3")
        local stat = I.STATUS_LABEL[d.status] or ""
        local meta = { d.ext }
        if d.size then table.insert(meta, d.size) end
        table.insert(meta, stat)
        if d.status == "reading" or d.status == "abandoned" then table.insert(meta, d.pct100 .. "%") end
        local texts = VerticalGroup:new{ align = "left",
            K.text(d.title, "ui-semibold", "fs-lg", "text", tw), K.vspan("sp-half"),
            K.text(d.name, "ui", "fs-sm", "text-2", tw), K.vspan("sp-1"),
            K.text(table.concat(meta, " · "), "ui", "fs-sm", "text-3", tw) }
        local hh = math.max(P.px(66), texts:getSize().h) + T.px("sp-2") + T.px("sp-4")
        texts:resetLayout()
        local head = OverlapGroup:new{ dimen = geom(inner, hh),
            LeftContainer:new{ dimen = geom(inner, hh), HorizontalGroup:new{ align = "center", K.hspan("sp-5"), cov, K.hspan("sp-4"), texts } },
            RightContainer:new{ dimen = geom(inner, hh), VerticalGroup:new{ align = "right",
                K.icon_button("close", close, dialog), K.vspan(hh - T.px("hit")) } } }

        -- tools (.lba-tools: 6 columns)
        local tcw = math.floor((inner - 2 * T.px("sp-3")) / 6)
        local tools = HorizontalGroup:new{ align = "center", K.hspan("sp-3"),
            tool("leaf.lib.copy", C_("File", "Copy"), by[C_("File", "Copy")], tcw),
            tool("leaf.lib.scissors", _("Cut"), by[_("Cut")], tcw),
            tool("leaf.lib.paste", C_("File", "Paste"), by[C_("File", "Paste")], tcw),
            tool("leaf.lib.squarecheck", _("Select"), by[_("Select")], tcw),
            tool("leaf.lib.pencil", _("Rename"), by[_("Rename")], tcw),
            tool("leaf.lib.trash", _("Delete"), by[_("Delete")], tcw) }

        local body = VerticalGroup:new{ align = "left", head, K.line(inner), K.vspan("sp-3"), tools, K.vspan("sp-1") }

        -- Mark as (only for books KOReader can open / has opened)
        if next(status_btn) then
            table.insert(body, section(_("Mark as"), inner))
            local reset = by[_("Reset")]
            local rb = HorizontalGroup:new{ align = "center", K.icon("leaf.lib.reset", "icon-sm", not (reset and reset.enabled ~= false)), K.hspan("sp-1h"),
                K.text(_("Reset"), "ui-medium", "fs-sm", (reset and reset.enabled ~= false) and "text-2" or "disabled") }
            local rbw = rb:getSize().w + 2 * T.px("sp-3")
            rb:resetLayout()
            local rbox = CenterContainer:new{ dimen = geom(rbw, T.px("h-control")), rb }
            local sw = inner - 2 * T.px("sp-4") - T.px("sp-2") - rbw
            table.insert(body, HorizontalGroup:new{ align = "center", K.hspan("sp-4"),
                seg(sw, d.status, status_btn), K.hspan("sp-2"),
                (reset and reset.enabled ~= false) and K.tap(rbox, function() reset.callback() end) or rbox })
        end

        -- Book
        local nColl = 0
        pcall(function()
            for _k in pairs(require("readcollection"):getCollectionsWithFile(file) or {}) do nColl = nColl + 1 end
        end)
        local nbm, nhl = 0, 0
        if d.status ~= "new" then
            pcall(function()
                local ann = require("ui/widget/booklist").getDocSettings(file):readSetting("annotations") or {}
                for _i, a in ipairs(ann) do if a.text and a.text ~= "" then nhl = nhl + 1 else nbm = nbm + 1 end end
            end)
        end
        local book_rows = {}
        local function add(rows, b, icon, label, extra)
            if not b then return end
            local r = { button = b, icon = icon, label = label or b.text }
            for k, v in pairs(extra or {}) do r[k] = v end
            table.insert(rows, r)
        end
        add(book_rows, by[_("Book information")], "leaf.lib.info", nil, { chev = true })
        add(book_rows, by[_("Book description")], "leaf.lib.text", nil, { chev = true })
        add(book_rows, by[_("Book cover")], "leaf.lib.image", nil, { chev = true })
        add(book_rows, by[_("Collections…")], "leaf.lib.library", nil,
            { chev = true, value = nColl > 0 and string.format(nColl == 1 and _("%d collection") or _("%d collections"), nColl) or _("None") })
        add(book_rows, by[_("Bookmarks")], "leaf.lib.bookmark", nil, { chev = true, value = tostring(nbm) })
        add(book_rows, by[_("Export highlights")], "leaf.lib.fileoutput", nil, { value = tostring(nhl) })
        add(book_rows, by[_("Open with…")], "leaf.lib.appwindow", nil, { chev = true })

        local meta_rows = {}
        for _i, pair in ipairs({ { _("Ignore cover"), _("Unignore cover"), "leaf.lib.imageoff" },
                                 { _("Ignore metadata"), _("Unignore metadata"), "leaf.lib.tag" } }) do
            local b = by[pair[1]] or by[pair[2]]
            if b then
                local on = by[pair[2]] ~= nil
                add(meta_rows, b, pair[3], pair[1], { trailing = require("leaf/widgets/toggle"):new{ on = on, enabled = b.enabled ~= false } })
            end
        end
        add(meta_rows, by[_("Refresh cached book information")], "leaf.lib.refresh")

        local more_rows = {}
        for _i, b in ipairs(rest) do
            local t = b.text or (b.text_func and b.text_func()) or ""
            local w = (t:match("^%s*([%a]+)") or ""):lower()
            add(more_rows, b, (w == "remove" or w == "delete") and "leaf.lib.trash" or "leaf.lib.ellipsis", t,
                { danger = w == "remove" or w == "delete" })
        end

        -- fit the screen: compact rows (--h-row-compact) when the sheet would be too tall
        local function blocks(row_h)
            local out = {}
            for _i, r in ipairs(book_rows) do r.height = row_h end
            for _i, r in ipairs(meta_rows) do r.height = row_h end
            for _i, r in ipairs(more_rows) do r.height = row_h end
            if #book_rows > 0 then table.insert(out, section(_("Book"), inner)) table.insert(out, group(book_rows, inner)) end
            if #meta_rows > 0 then table.insert(out, section(_("Metadata & cache"), inner)) table.insert(out, group(meta_rows, inner)) end
            if #more_rows > 0 then table.insert(out, section(_("More"), inner)) table.insert(out, group(more_rows, inner)) end
            return out
        end
        local top_h = body:getSize().h
        body:resetLayout()
        local max_h = Screen:getHeight() - T.px("h-header") - T.px("sp-8")
        local rest_blocks
        for _i, rh in ipairs({ T.px("h-row"), T.px("h-row-compact"), math.floor(T.px("h-row-compact") * 0.85) }) do
            rest_blocks = blocks(rh)
            local h = top_h
            for _j, b in ipairs(rest_blocks) do h = h + b:getSize().h end
            if h <= max_h then break end
        end
        for _i, b in ipairs(rest_blocks) do table.insert(body, b) end
        table.insert(body, K.vspan("sp-5"))
        return body
    end

    L.wrap(ButtonDialog, "init", function(orig, self)
        local file = not self.anchor and dialog_file(self.buttons)
        orig(self)
        if not file then return end
        local frame = self.movable and self.movable[1]
        if not frame then return end
        local W = Screen:getWidth()
        local inner = W - 2 * T.px("hairline")
        local body = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = T.px("sp-2") },
            CenterContainer:new{ dimen = geom(inner, T.px("sp-1")), K.Grip:new{} },
            VerticalSpan:new{ width = T.px("sp-1") },
            LeftContainer:new{ dimen = geom(inner, 0), HorizontalSpan:new{ width = 0 } },
        }
        body[4] = M.build(self, file, W)
        frame[1] = body
        self._leaf_book_actions = file
    end, "ButtonDialog:init (book actions)")
end

return M
