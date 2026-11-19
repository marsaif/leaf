--[[
    Leaf: the KOReader redesign (https://github.com/marsaif/leaf). Single entry point.
    The code lives in koreader/leaf/ (see leaf/core.lua for the fail-safe rules).
    To turn Leaf off without deleting anything, create an empty file `koreader/leaf.disabled`.
--]]
local DataStorage = require("datastorage")
local data_dir = DataStorage:getDataDir()
if not package.path:find(data_dir .. "/?.lua", 1, true) then
    package.path = data_dir .. "/?.lua;" .. package.path
end

local ok, err = pcall(function() require("leaf/core").load() end)
if not ok then
    require("logger").err("Leaf: failed to start, running stock KOReader:", err)
end
