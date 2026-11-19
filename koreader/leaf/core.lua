--[[
    Leaf core: loads the Leaf modules safely. Entry point: koreader/patches/2-leaf.lua.

    Fail-safe rules
      * Kill switch: a file named `leaf.disabled` in the KOReader folder (/mnt/us/koreader on the
        Kindle) or LEAF_DISABLE=1 in the environment -> nothing is loaded, stock KOReader.
      * Every module is applied under pcall: a module that errors is logged and skipped, the
        others still load.
      * Overrides go through L.wrap(): if the Leaf version of a method throws at run time, the
        error is logged once and KOReader's original method is used from then on.
    Modules live in koreader/leaf/ and return { apply = function(L) ... end }.
--]]
local DataStorage = require("datastorage")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local L = {
    version = "0.1.0",
    dir = DataStorage:getDataDir() .. "/leaf",
    status = {},  -- module name -> true | error string
    failed_wraps = {},
}

-- order matters: fonts and sizes must be set before any widget class reads them
L.MODULES = {
    "fonts",
    "frames",
    "buttons",
    "titlebar",
    "controls",
}

function L.log(...) logger.info("Leaf:", ...) end
function L.err(...) logger.err("Leaf:", ...) end

function L.disabled()
    if os.getenv("LEAF_DISABLE") == "1" then return "LEAF_DISABLE=1" end
    local kill = DataStorage:getDataDir() .. "/leaf.disabled"
    if lfs.attributes(kill, "mode") then return kill end
end

--- Replace Class[method] with fn(orig, self, ...); on error fall back to orig for good.
function L.wrap(Class, method, fn, label)
    local orig = Class[method]
    assert(type(orig) == "function", "Leaf.wrap: no method " .. tostring(method))
    label = label or method
    local broken = false
    local function finish(args, ok, ...)
        if ok then return ... end
        local e = ...
        broken = true
        L.failed_wraps[label] = tostring(e)
        L.err("override", label, "failed, using KOReader's original from now on:", e)
        return orig(unpack(args, 1, args.n))
    end
    Class[method] = function(...)
        if broken then return orig(...) end
        return finish({ n = select("#", ...), ... }, pcall(fn, orig, ...))
    end
    return orig
end

function L.load()
    local why = L.disabled()
    if why then
        L.log("disabled by", why)
        return L
    end
    if os.getenv("LEAF_DEBUG") then
        -- widget classes already loaded here copied Size/Font values at require time:
        -- a module that changes those must also patch these classes directly
        local early = {}
        for name in pairs(package.loaded) do
            if name:match("^ui/widget/") then table.insert(early, name) end
        end
        table.sort(early)
        L.log("widgets loaded before Leaf:", #early > 0 and table.concat(early, ", ") or "none")
    end
    L.T = require("leaf/tokens")
    L.T.scale = G_reader_settings:readSetting("leaf_ui_scale") or 1
    for _, name in ipairs(L.MODULES) do
        local ok, err = pcall(function()
            local mod = require("leaf/" .. name)
            mod.apply(L)
        end)
        L.status[name] = ok or tostring(err)
        if ok then L.log("loaded", name) else L.err("module", name, "failed, skipped:", err) end
    end
    return L
end

return L
