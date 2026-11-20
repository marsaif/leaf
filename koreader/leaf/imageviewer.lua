--[[
    Leaf image viewer (prototype overlay "image-viewer", js/screens/gaps.js): ImageViewer for covers,
    images in books, screenshots, archives and OPDS page streaming. The shared restyle lives here;
    callers add their specifics through M.next (consumed by the next ImageViewer:new):
        M.next = { title, sub, paper = true (the image sits on a --page card), ring = true (a hairline
                   around the image), fullscreen = true, no_save = true }

      controls shown:   status strip · top bar (× · title / sub · caption toggle) with a hairline under it
                        stage (--sp-6 around the image; book images on a --page card, --r-sm, --sp-4 padding)
                        caption (--fs-sm --text-2, centred) when there is one and it is shown
                        foot on --bg-raised: "3 / 24" + thin progress (image lists), then tools
                        (.ko-tool: Original size / Fit to screen · Rotate / No rotation · Save view)
      controls hidden:  the image (--sp-2 around it) and the hint "Tap to show the controls · pinch to zoom"

    KOReader's viewer keeps zoom, pan, rotation, image lists, keys and Save view; a tap still toggles the
    controls (KOReader's buttons_visible). A viewer opened with a title bar starts with its controls shown.
--]]
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Widget = require("ui/widget/widget")
local _ = require("gettext")
local Device = require("device")
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local K = require("leaf/syskit")(L)
    local Kit = require("leaf/widgets/kit")
    local geom = K.geom
    local ImageViewer = require("ui/widget/imageviewer")

    -- .ko-tool: icon over label, 58px high, --fs-xs --text-2
    local function tool(icon, label, w, cb)
        local h = Screen:scaleBySize(58 * T.scale)
        local g = VerticalGroup:new{ align = "center",
            Kit.TintIcon:new{ icon = icon, size_token = "icon-md", color = T.color("text-2") },
            K.vspan(Screen:scaleBySize(5 * T.scale)),
            K.text(label, "ui", "fs-xs", "text-2", w) }
        return Kit.Tap:new{ width = w, height = h, content = CenterContainer:new{ dimen = geom(w, h), g }, callback = cb }
    end

    -- a filled rectangle of a given size (backgrounds and bars)
    local Fill = Widget:extend{ w = 0, h = 0, color = nil, radius = 0 }
    function Fill:init() self.dimen = geom(self.w, self.h) end
    function Fill:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        if self.w > 0 and self.h > 0 then bb:paintRoundedRect(x, y, self.w, self.h, self.color, self.radius) end
    end

    local function band(w, h, color, content)
        return OverlapGroup:new{ dimen = geom(w, h), Fill:new{ w = w, h = h, color = T.color(color) }, content }
    end

    local function top_bar(self, W)
        local hair = T.px("hairline")
        local close = K.icon_button("leaf.gr.x", function() self:onClose() end, self)
        local right = HorizontalGroup:new{ align = "center" }
        if self.caption then
            table.insert(right, K.icon_button(self.caption_visible and "leaf.gr.captions" or "leaf.gr.captions-off", function()
                self.caption_visible = not self.caption_visible
                self:update()
            end, self))
        end
        table.insert(right, K.hspan("sp-3"))
        local rw = right:getSize().w
        right:resetLayout()
        local lw = T.px("sp-2") + close:getSize().w + T.px("sp-2")
        local tw = W - lw - rw
        local col = VerticalGroup:new{ align = "left", K.text(self._leaf_title or self.title_text or _("Image"), "ui-semibold", "fs-head", "text", tw) }
        local sub = self._leaf_sub
        if sub and sub ~= "" then
            table.insert(col, K.vspan("sp-half"))
            table.insert(col, K.text(sub, "ui", "fs-xs", "text-3", tw))
        end
        local h = math.max(T.px("hit"), col:getSize().h) + 2 * T.px("sp-1")
        col:resetLayout()
        local bar = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", K.hspan("sp-2"), close, K.hspan("sp-2"), col } },
            RightContainer:new{ dimen = geom(W, h), right } }
        return VerticalGroup:new{ band(W, h, "bg", bar), K.line(W) }, h + hair
    end

    local function foot(self, W)
        local hair = T.px("hairline")
        local g = VerticalGroup:new{ align = "left", K.vspan("sp-2") }
        local iw = W - 2 * T.px("sp-3")
        if self._images_list and (self._images_list_nb or 0) > 1 then
            local cur, n = self._images_list_cur or 1, self._images_list_nb
            local label = K.text(string.format("%d / %d", cur, n), "ui", "fs-xs", "text-3")
            local bw = iw - 2 * T.px("sp-2") - label:getSize().w - T.px("sp-3")
            local th = Screen:scaleBySize(2 * T.scale)
            local fill = math.floor(bw * cur / n + 0.5)
            local bar = OverlapGroup:new{ dimen = geom(bw, th),
                Fill:new{ w = bw, h = th, color = T.color("surface-3"), radius = T.px("r-tick") },
                Fill:new{ w = fill, h = th, color = T.color("accent"), radius = T.px("r-tick") } }
            table.insert(g, HorizontalGroup:new{ align = "center", K.hspan("sp-3"), K.hspan("sp-2"), label, K.hspan("sp-3"), bar })
            table.insert(g, K.vspan("sp-2"))
        end
        local tools = {}
        local scale_b = self.button_table and self.button_table:getButtonById("scale")
        local rot_b = self.button_table and self.button_table:getButtonById("rotate")
        table.insert(tools, { self._scale_to_fit and "leaf.gr.expand" or "leaf.gr.shrink",
            self._scale_to_fit and _("Original size") or _("Fit to screen"), function() if scale_b then scale_b.callback() end end })
        table.insert(tools, { "leaf.gr.rotate-cw", self.rotated and _("No rotation") or _("Rotate"), function() if rot_b then rot_b.callback() end end })
        if not self._leaf_no_save then
            table.insert(tools, { "leaf.gr.camera", _("Save view"), function() self:onSaveImageView() end })
        end
        local cw = math.floor(iw / #tools)
        local row = HorizontalGroup:new{ align = "center", K.hspan("sp-3") }
        for _i, t in ipairs(tools) do table.insert(row, tool(t[1], t[2], cw, t[3])) end
        table.insert(g, row)
        table.insert(g, K.vspan("sp-3"))
        local h = g:getSize().h
        g:resetLayout()
        return VerticalGroup:new{ K.line(W), band(W, h, "bg-raised", g) }, h + hair
    end

    -- the image on a --page card (book illustrations): the card hugs the scaled bitmap, which
    -- ImageWidget centres in its (larger) box
    local Paper = Widget:extend{}
    function Paper:init() self.dimen = self[1]:getSize() end
    function Paper:getSize() return self.dimen end
    function Paper:paintTo(bb, x, y)
        local img = self[1]
        local box = img:getSize()
        local bw, bh = box.w, box.h
        if img._bb then bw, bh = math.min(bw, img._bb:getWidth()), math.min(bh, img._bb:getHeight()) end
        local pad = self.pad or T.px("sp-4")
        local cw, ch = bw + 2 * pad, bh + 2 * pad
        local cx, cy = x + math.floor((box.w - cw) / 2), y + math.floor((box.h - ch) / 2)
        local hair = T.px("hairline")
        bb:paintRoundedRect(cx, cy, cw, ch, T.color("border"), T.px("r-sm"))
        bb:paintRoundedRect(cx + hair, cy + hair, cw - 2 * hair, ch - 2 * hair, T.color("page"), T.px("r-sm") - hair)
        img:paintTo(bb, x, y)
    end
    local function paper(img, pad) return Paper:new{ img, pad = pad } end

    L.wrap(ImageViewer, "init", function(orig, self, ...)
        local nx = M.next
        if nx then
            M.next = nil
            self._leaf_title, self._leaf_sub, self._leaf_paper, self._leaf_no_save = nx.title, nx.sub, nx.paper, nx.no_save
            self._leaf_ring = nx.ring
            if nx.fullscreen then self.fullscreen = true end
        end
        if self.with_title_bar and not self.buttons_visible then self.buttons_visible = true end
        self._leaf = true
        return orig(self, ...)
    end, "ImageViewer:init")

    L.wrap(ImageViewer, "update", function(orig, self)
        if not self._leaf then return orig(self) end
        self:_clean_image_wg()
        local orig_dimen = self.main_frame.dimen
        if self.fullscreen then
            self.height, self.width = Screen:getHeight(), Screen:getWidth()
        else
            self.height, self.width = Screen:getHeight() - Screen:scaleBySize(40), Screen:getWidth() - Screen:scaleBySize(40)
        end
        local W, H = self.width, self.height
        while table.remove(self.frame_elements) do end
        self.frame_elements:resetLayout()
        local ui = self.buttons_visible
        local above, below = {}, {}
        local top_h, bottom_h = 0, 0
        if ui then
            if self.fullscreen then
                table.insert(above, band(W, T.px("h-status"), "bg", Kit.status_strip(W)))
                top_h = top_h + T.px("h-status")
            end
            local bar, bh = top_bar(self, W)
            table.insert(above, bar)
            top_h = top_h + bh
            if self.caption and self.caption_visible then
                local c = K.textbox(self.caption, "ui", "fs-sm", "text-2", W - 2 * T.px("sp-5"), "bg", { align = "center" })
                local ch = c:getSize().h + 2 * T.px("sp-2")
                table.insert(below, band(W, ch, "bg", CenterContainer:new{ dimen = geom(W, ch), c }))
                bottom_h = bottom_h + ch
            end
            local f, fh = foot(self, W)
            table.insert(below, f)
            bottom_h = bottom_h + fh
        end
        self.img_container_h = H - top_h - bottom_h
        -- room around the image: --sp-6 with controls (+ the paper card), --sp-2 without
        local pad = ui and T.px("sp-6") or T.px("sp-2")
        if self._leaf_paper then pad = pad + T.px("sp-4") end
        local saved_pad, saved_title = self.image_padding, self.with_title_bar
        self.image_padding, self.with_title_bar = pad, true
        if self._leaf_saving then self.image_padding, self.with_title_bar = 0, false end
        local ok, err = pcall(self._new_image_wg, self)
        self.image_padding, self.with_title_bar = saved_pad, saved_title
        if not ok then error(err, 0) end
        local stage_content = self._image_wg
        if self._leaf_paper and not self._leaf_saving then stage_content = paper(self._image_wg)
        elseif self._leaf_ring and not self._leaf_saving then stage_content = paper(self._image_wg, 0) end
        local stage = OverlapGroup:new{ dimen = geom(W, self.img_container_h),
            Fill:new{ w = W, h = self.img_container_h, color = T.color("bg") },
            CenterContainer:new{ dimen = geom(W, self.img_container_h), stage_content } }
        if not ui and not self._leaf_saving then
            local hint = K.text(self._images_list and _("Tap the sides for the previous or next image · the middle shows the controls")
                or _("Tap to show the controls · pinch to zoom"), "ui", "fs-xs", "text-3", W - 2 * T.px("sp-4"))
            local hh = hint:getSize().h
            table.insert(stage, VerticalGroup:new{ K.vspan(self.img_container_h - T.px("sp-4") - hh),
                CenterContainer:new{ dimen = geom(W, hh), hint } })
        end
        self.image_container = stage
        for _i, w in ipairs(above) do table.insert(self.frame_elements, w) end
        table.insert(self.frame_elements, stage)
        for _i, w in ipairs(below) do table.insert(self.frame_elements, w) end
        self.frame_elements:resetLayout()
        self._leaf_stage_y = { top_h, top_h + self.img_container_h }
        self.main_frame.background = T.color("bg")
        self.main_frame.radius = not self.fullscreen and T.px("r-lg") or nil
        local wfm_mode = Device:hasKaleidoWfm() and "partial" or "ui"
        self.dithered = true
        UIManager:setDirty(self, function()
            local update_region = self.main_frame.dimen and orig_dimen and self.main_frame.dimen:combine(orig_dimen)
                or geom(Screen:getWidth(), Screen:getHeight())
            return wfm_mode, update_region, true
        end)
    end, "ImageViewer:update")

    -- taps on the bars stay on the bars; the stage toggles the controls (or steps through image lists)
    L.wrap(ImageViewer, "onTap", function(orig, self, arg, ges)
        if not self._leaf then return orig(self, arg, ges) end
        if self.main_frame.dimen and ges.pos:notIntersectWith(self.main_frame.dimen) then
            self:onClose()
            return true
        end
        local s = self._leaf_stage_y
        if self.buttons_visible and s and self.main_frame.dimen then
            local y = ges.pos.y - self.main_frame.dimen.y
            if y < s[1] or y >= s[2] then return true end
        end
        local wtb = self.with_title_bar
        self.with_title_bar = false
        local ok, ret = pcall(orig, self, arg, ges)
        self.with_title_bar = wtb
        if not ok then error(ret, 0) end
        return ret
    end, "ImageViewer:onTap")

    L.wrap(ImageViewer, "onSaveImageView", function(orig, self)
        self._leaf_saving = true
        local ok, ret = pcall(orig, self)
        self._leaf_saving = nil
        if not ok then error(ret, 0) end
        return ret
    end, "ImageViewer:onSaveImageView")
end

return M
