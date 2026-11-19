--[[
    Dev helper (inert unless KO_SANDBOX_KINDLE is set, which tools/ko-sandbox.sh does):
    make desktop KOReader look like a touch Kindle, which has no keyboard. Without this,
    lists show Q/W/E… shortcut boxes and dialogs grow keyboard hints that never appear on the device.
--]]
if not os.getenv("KO_SANDBOX_KINDLE") then return end

local Device = require("device")
local no = function() return false end
Device.hasKeyboard = no

-- Menu reads Device:hasKeyboard() once, when its class table is built
require("ui/widget/menu").is_enable_shortcut = false
