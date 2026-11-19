--[[
    Leaf fonts (safety-net item 1): Inter for the UI, Playfair Display for top-level titles,
    Literata for book text in panels, Noto Naskh Arabic for Arabic.

    * Font.fontmap: every Noto Sans entry -> Inter (bold entries -> Inter SemiBold:
      "bold in UI = semibold"). Mono entries (input fields, code) stay until their widget is redone.
    * Bold: Inter Regular's real bold variant is Inter SemiBold, so `bold = true` text never gets
      synthetic bold.
    * Sizes: KOReader's stock sizes are larger than Leaf's type scale (menu text 24 vs Leaf's 15).
      Stock sizes are mapped onto the Leaf scale: size x (fs-md / 24), snapped to the nearest
      Leaf step (ties go up). This applies to Font.sizemap and to stock callers that pass an
      explicit size; faces Leaf asks for itself (`leaf/...` files, L.face) are exact.
    * Fallbacks: Inter first, Noto Naskh Arabic instead of Noto Sans Arabic UI.

    L.face(role, size_token) -> a Font face for Leaf's own widgets, e.g. L.face("ui-semibold", "fs-head").
--]]
local Font = require("ui/font")

local M = {}

local DIR = "leaf/"
M.FILES = {
    ["ui"] = DIR .. "Inter-Regular.ttf",
    ["ui-medium"] = DIR .. "Inter-Medium.ttf",
    ["ui-semibold"] = DIR .. "Inter-SemiBold.ttf",
    ["ui-bold"] = DIR .. "Inter-Bold.ttf",
    ["display"] = DIR .. "PlayfairDisplay-Regular.ttf",
    ["display-semibold"] = DIR .. "PlayfairDisplay-SemiBold.ttf",
    ["display-italic"] = DIR .. "PlayfairDisplay-Italic.ttf",
    ["book"] = DIR .. "Literata-Regular.ttf",
    ["book-italic"] = DIR .. "Literata-Italic.ttf",
    ["book-bold"] = DIR .. "Literata-Bold.ttf",
    ["book-bolditalic"] = DIR .. "Literata-BoldItalic.ttf",
    ["arabic"] = "NotoNaskhArabic-Regular.ttf",
    ["arabic-bold"] = "NotoNaskhArabic-Bold.ttf",
}

-- stock files -> Leaf files (callers that name a file instead of a fontmap key)
local REDIRECT = {
    ["NotoSans-Regular.ttf"] = M.FILES["ui"],
    ["NotoSans-Bold.ttf"] = M.FILES["ui-semibold"],
    ["source/SourceSans3-Regular.ttf"] = M.FILES["ui"],
    ["source/SourceSans3-Bold.ttf"] = M.FILES["ui-semibold"],
    ["source/SourceSans3-It.ttf"] = M.FILES["ui"],
    ["source/SourceSans3-BoldIt.ttf"] = M.FILES["ui-semibold"],
    -- Project: Title's serif (folder names, some captions) -> Leaf's book face
    ["source/SourceSerif4-Regular.ttf"] = M.FILES["book"],
    ["source/SourceSerif4-Bold.ttf"] = M.FILES["book-bold"],
    ["source/SourceSerif4-It.ttf"] = M.FILES["book-italic"],
    ["source/SourceSerif4-BoldIt.ttf"] = M.FILES["book-bolditalic"],
}

-- regular -> real bold variant
local BOLD = {
    [M.FILES["ui"]] = M.FILES["ui-semibold"],
    [M.FILES["ui-medium"]] = M.FILES["ui-semibold"],
    [M.FILES["display"]] = M.FILES["display-semibold"],
    [M.FILES["book"]] = M.FILES["book-bold"],
    [M.FILES["book-italic"]] = M.FILES["book-bolditalic"],
    [M.FILES["arabic"]] = M.FILES["arabic-bold"],
}

--- KOReader stock size -> Leaf type scale (before T.scale)
function M.leaf_size(T, ko_size)
    local steps = { "fs-2xs", "fs-xs", "fs-sm", "fs-md", "fs-head", "fs-lg", "fs-xl", "fs-glyph",
        "fs-display", "fs-2xl", "fs-3xl", "fs-hero", "fs-jumbo" }
    local want = ko_size * T.size["fs-md"] / 24
    local best, best_d
    for _, k in ipairs(steps) do
        local v = T.size[k]
        local d = math.abs(v - want)
        if not best_d or d < best_d or (d == best_d and v > best) then best, best_d = v, d end
    end
    return best
end

function M.apply(L)
    local T = L.T

    -- fail-safe: if the Leaf font files are missing (fonts/leaf not copied to the device),
    -- stop here and keep KOReader's fonts; switching the fontmap to missing files crashes it
    for _, role in ipairs({ "ui", "ui-medium", "ui-semibold", "display", "book" }) do
        if not Font:getFace(M.FILES[role], 15) then
            error("font file missing: koreader/fonts/" .. M.FILES[role] .. " (keeping KOReader fonts)")
        end
    end

    -- fontmap: Noto Sans -> Inter; keep mono entries
    for key, file in pairs(Font.fontmap) do
        if REDIRECT[file] then Font.fontmap[key] = REDIRECT[file] end
    end
    -- sizemap: onto the Leaf scale (getFace scales again by screen size)
    local stock_sizes = {}
    for key, size in pairs(Font.sizemap) do
        stock_sizes[key] = size
        Font.sizemap[key] = M.leaf_size(T, size) * T.scale
    end
    M.stock_sizes = stock_sizes

    -- real bold variants
    for regular, bold in pairs(BOLD) do
        Font.bold_font_variant[regular] = bold
        Font.regular_font_variant[bold] = regular
    end

    -- fallbacks: Inter first, Naskh for Arabic
    local is_fallback = {}
    for i, f in ipairs(Font.fallbacks) do
        if f == "NotoSans-Regular.ttf" then Font.fallbacks[i] = M.FILES["ui"]
        elseif f == "NotoSansArabicUI-Regular.ttf" then Font.fallbacks[i] = M.FILES["arabic"] end
        is_fallback[Font.fallbacks[i]] = true
    end

    -- stock callers with an explicit size: redirect stock files and map the size
    L.wrap(Font, "getFace", function(orig, self, font, size, faceindex)
        if font and size and not is_fallback[font] then
            local stock_key = self.fontmap[font] ~= nil
            local redirected = REDIRECT[font]
            if stock_key or redirected then
                size = M.leaf_size(T, size) * T.scale
            end
            if redirected then font = redirected end
        elseif font and REDIRECT[font] then
            font = REDIRECT[font]
        end
        return orig(self, font, size, faceindex)
    end, "Font:getFace")

    --- a face for Leaf's own widgets: exact token size
    function L.face(role, size_token)
        local file = M.FILES[role]
        assert(file, "Leaf.face: unknown role " .. tostring(role))
        return Font:getFace(file, T.fs(size_token))
    end
end

return M
