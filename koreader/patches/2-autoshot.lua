-- Dev helper: if KO_AUTOSHOT=/path.png is set, save a screenshot shortly after start and quit.
-- KO_AUTOSHOT_ACTION=menu|plus opens that menu first.
local path = os.getenv("KO_AUTOSHOT")
if path then
    local UIManager = require("ui/uimanager")
    local action = os.getenv("KO_AUTOSHOT_ACTION")
    UIManager:scheduleIn(3, function()
        local FM = require("apps/filemanager/filemanager").instance
        if action == "menu" then FM.menu:onShowMenu()
        elseif action == "plus" then FM:onShowPlusMenu()
        elseif action == "newfolder" then FM:createFolder()
        elseif action and FM.title_bar[action] then FM.title_bar[action].callback() end
    end)
    UIManager:scheduleIn(5, function()
        require("device").screen:shot(path)
        UIManager:quit()
    end)
end
