local out = os.getenv("KO_PROBE")
if out then
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(4, function()
        local RUI = require("apps/reader/readerui").instance
        local doc = RUI.document
        for _, t in ipairs(RUI.toc.toc or {}) do
            if t.title:find("Chapter I ", 1, true) then RUI.rolling:onGotoXPointer(t.xpointer) end
        end
        local Screen = require("device").screen
        local pos = { x = math.floor(Screen:getWidth()/2), y = math.floor(Screen:getHeight()*(tonumber(os.getenv("KO_PROBE_Y")) or 0.6)) }
        local w = doc:getWordFromPosition(pos, true)
        RUI.highlight.selected_text = { text = w.word, pos0 = w.pos0, pos1 = w.pos1, sboxes = {} }
        RUI.highlight.hold_pos = pos
        RUI.highlight:lookupDictWord()
        if os.getenv("KO_PROBE_NEXT") then
            UIManager:scheduleIn(1, function()
                local top = UIManager._window_stack[#UIManager._window_stack].widget
                top:go(1)
            end)
        end
    end)
    UIManager:scheduleIn(7, function()
        require("device").screen:shot(out)
        UIManager:quit()
    end)
end
