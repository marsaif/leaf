--[[
    Leaf title bars (safety-net item 6): TitleBar is the header of 28 widgets (lists, text viewers,
    pickers, book info, dictionary, frontlight...). Target: .ko-sheet-head / .ko-header .title.l2.

    * Title: Inter SemiBold --fs-head (17), left-aligned (close button stays on the right).
      Callers that ask for a specific face or alignment keep it.
    * Subtitle: Inter --fs-sm in --text-3.
    * Bottom rule: a --hairline in --border (KOReader draws Size.line.thick in black).
--]]
local Size = require("ui/size")

local M = {}

function M.apply(L)
    local T = L.T
    local TitleBar = require("ui/widget/titlebar")

    TitleBar.align = "left"
    TitleBar.title_face_fullscreen = L.face("ui-semibold", "fs-head")
    TitleBar.title_face_not_fullscreen = L.face("ui-semibold", "fs-head")
    TitleBar.subtitle_face = L.face("ui", "fs-sm")
    TitleBar.info_text_face = L.face("ui", "fs-sm")

    local hair = T.px("hairline")
    L.wrap(TitleBar, "init", function(orig, self)
        if self.with_bottom_line and not self.bottom_line_color then
            self.bottom_line_color = T.color("border")
        end
        -- the rule's thickness is read from Size.line.thick while building: narrow it for this
        -- build only, and always put it back
        local thick = Size.line.thick
        Size.line.thick = hair
        local ok, err = pcall(orig, self)
        Size.line.thick = thick
        if not ok then error(err, 0) end

        -- info text (InputDialog's description): --text-3, like a sub line
        if self.info_text then
            local last = self[#self]
            local hg = last and last[2]
            local tb = hg and hg[2]
            if type(tb) == "table" and tb.text == self.info_text and tb.face then
                hg[2] = require("ui/widget/textboxwidget"):new{ text = tb.text, face = tb.face, width = tb.width,
                    lang = tb.lang, fgcolor = T.color("text-3") }
                tb:free()
            end
        end
        local sub = self.subtitle_widget
        if sub then
            sub.fgcolor = T.color("text-3")
            if sub.update then sub:update() end
        end
    end, "TitleBar:init")
end

return M
