--[[
    Leaf image viewer (Gaps › image-viewer): KOReader's ImageViewer (book covers, images in books,
    screenshots, archive images, OPDS page streaming).

    A full page on --bg. Controls (the title bar, and KOReader's bottom buttons) become:
      * top bar (.gp-iv-top): status strip, × close, the title (--fs-head semibold) over a --fs-xs
        --text-3 sub line, a caption toggle when the image has a caption; hairline under it.
      * the image centred with --sp-6 around it (--sp-2 without controls); its caption under it
        (--fs-sm --text-2, centred) when shown.
      * foot (.gp-iv-foot, --bg-raised, hairline on top): for image lists "3 / 24" + a thin progress
        bar, then tools (.ko-tool: icon over label): Original size / Fit to screen, Rotate / No
        rotation, Go to image (lists), Save view (KOReader's "save image view" screenshot).
      * without controls: a --fs-xs --text-3 hint at the bottom ("Tap to show the controls…").
    Taps: the middle toggles the controls, the sides of an image list go to the previous / next
    image (KOReader's own behaviour); pinch, pan, swipe, zoom, keys stay KOReader's.
    Book covers (Book information › cover) open with the controls and the book's title / author.
--]]
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

local M = {}

function M.apply(L)
    local T = L.T
    local GW = require("leaf/widgets/gwkit")(L)
    local Kit = require("leaf/widgets/kit")
    local ImageViewer = require("ui/widget/imageviewer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local geom = GW.geom

    local function controls(self) return self.with_title_bar or self.buttons_visible end

    -- .ko-tool: icon over a --fs-xs label, in an equal-width cell
    local function tool(w, icon, label, cb)
        local h = T.px("h-row") + T.px("sp-3")
        local g = VerticalGroup:new{ align = "center", GW.icon(icon, "icon-md", "text-2"), GW.vspan("sp-1"),
            GW.text(label, "ui", "fs-xs", "text-2", w) }
        return Kit.Tap:new{ width = w, height = h, callback = cb, content = CenterContainer:new{ dimen = geom(w, h), g } }
    end

    local function top_bar(self, W)
        local close = GW.icon_btn{ icon = "leaf.gw.x", callback = function() self:onClose() end }
        local right = HorizontalGroup:new{ align = "center" }
        if self.caption then
            table.insert(right, GW.icon_btn{ icon = self.caption_visible and "leaf.gw.captions" or "leaf.gw.captions-off",
                callback = function()
                    self.caption_visible = not self.caption_visible
                    self:update()
                end })
        end
        table.insert(right, GW.hspan("sp-3"))
        local rw = right:getSize().w
        right:resetLayout()
        local tw = W - T.px("sp-2") - T.px("hit") - T.px("sp-2") - rw
        local col = VerticalGroup:new{ align = "left", GW.text(self.title_text or "", "ui-semibold", "fs-head", "text", tw) }
        if self.leaf_sub and self.leaf_sub ~= "" then
            table.insert(col, GW.vspan("sp-half"))
            table.insert(col, GW.text(self.leaf_sub, "ui", "fs-xs", "text-3", tw))
        end
        local h = math.max(T.px("h-header"), col:getSize().h + 2 * T.px("sp-1"))
        col:resetLayout()
        local bar = OverlapGroup:new{ dimen = geom(W, h),
            LeftContainer:new{ dimen = geom(W, h), HorizontalGroup:new{ align = "center", GW.hspan("sp-2"), close, GW.hspan("sp-2"), col } },
            RightContainer:new{ dimen = geom(W, h), right } }
        return VerticalGroup:new{ align = "left", Kit.status_strip(W), bar, GW.line(W) }
    end

    local function go_to_image(self)
        local InputDialog = require("ui/widget/inputdialog")
        local d
        d = InputDialog:new{ title = _("Go to image"), input_hint = string.format("1 – %d", self._images_list_nb),
            input_type = "number",
            buttons = { {
                { text = _("Cancel"), id = "close", callback = function() UIManager:close(d) end },
                { text = _("Go"), is_enter_default = true, callback = function()
                    local n = tonumber(d:getInputText())
                    if n and n >= 1 and n <= self._images_list_nb then
                        UIManager:close(d)
                        self:switchToImageNum(math.floor(n))
                    end
                end },
            } } }
        UIManager:show(d)
        d:onShowKeyboard()
    end

    local function foot(self, W)
        local g = VerticalGroup:new{ align = "left" }
        local padx = T.px("sp-3")
        local inner = W - 2 * padx
        if self._images_list and self._images_list_nb > 1 then
            local label = GW.text(string.format("%d / %d", self._images_list_cur, self._images_list_nb), "ui", "fs-xs", "text-3")
            local lw = label:getSize().w
            local pw = inner - 2 * T.px("sp-2") - lw - T.px("sp-3")
            local ProgressWidget = require("ui/widget/progresswidget")
            local bar = ProgressWidget:new{ width = pw, height = T.px("sp-1"),
                percentage = (self._images_list_cur - 1) / math.max(1, self._images_list_nb - 1) }
            table.insert(g, HorizontalGroup:new{ align = "center", GW.hspan("sp-2"), label, GW.hspan("sp-3"), bar })
            table.insert(g, GW.vspan("sp-2"))
        end
        local list = self._images_list and self._images_list_nb > 1
        local n = list and 4 or 3
        local cw = math.floor(inner / n)
        local row = HorizontalGroup:new{ align = "center",
            tool(cw, self._scale_to_fit and "leaf.gw.expand" or "leaf.gw.shrink",
                self._scale_to_fit and _("Original size") or _("Fit to screen"), function()
                    self.scale_factor = self._scale_to_fit and 1 or 0
                    self._scale_to_fit = not self._scale_to_fit
                    self._center_x_ratio, self._center_y_ratio = 0.5, 0.5
                    self:update()
                end),
            tool(cw, "leaf.gw.rotate-cw", self.rotated and _("No rotation") or _("Rotate"), function()
                self.rotated = not self.rotated and true or false
                self:update()
            end) }
        if list then table.insert(row, tool(cw, "leaf.gw.hash", _("Go to image"), function() go_to_image(self) end)) end
        table.insert(row, tool(cw, "leaf.gw.camera", _("Save view"), function() self:onSaveImageView() end))
        table.insert(g, row)
        return FrameContainer:new{ bordersize = 0, margin = 0, background = T.color("bg-raised"),
            padding = 0, padding_left = padx, padding_right = padx, padding_top = T.px("sp-2"), padding_bottom = T.px("sp-3"),
            VerticalGroup:new{ align = "left", g } }, GW.line(W)
    end

    L.wrap(ImageViewer, "init", function(orig, self)
        local cover = ImageViewer._leaf_cover
        if cover then
            ImageViewer._leaf_cover = nil
            self.with_title_bar = true
            self.buttons_visible = true
            self.title_text = cover.title or self.title_text
            self.leaf_sub = cover.sub
        end
        self.fullscreen = true
        orig(self)
    end, "ImageViewer:init")

    L.wrap(ImageViewer, "update", function(orig, self)
        self:_clean_image_wg()
        local W, H = Screen:getWidth(), Screen:getHeight()
        self.width, self.height = W, H
        local orig_dimen = self.main_frame and self.main_frame.dimen
        local top = controls(self) and top_bar(self, W) or nil
        local foot_w, foot_line
        if controls(self) and self.buttons_visible ~= false then foot_w, foot_line = foot(self, W) end
        local cap
        if controls(self) and self.caption and self.caption_visible then
            local pad = T.px("sp-5")
            cap = FrameContainer:new{ bordersize = 0, padding = 0, padding_left = pad, padding_right = pad,
                padding_top = T.px("sp-2"), padding_bottom = T.px("sp-2"),
                TextBoxWidget:new{ text = self.caption, face = L.face("ui", "fs-sm"), fgcolor = T.color("text-2"),
                    width = W - 2 * pad, alignment = "center", bgcolor = T.color("bg") } }
        end
        local used = (top and top:getSize().h or 0) + (foot_w and (foot_w:getSize().h + T.px("hairline")) or 0)
            + (cap and cap:getSize().h or 0)
        self.img_container_h = H - used
        local saved_pad = self.image_padding
        self.image_padding = T.px(controls(self) and "sp-6" or "sp-2")
        local saved_bv, saved_tb = self.buttons_visible, self.with_title_bar
        self.buttons_visible = true -- (_new_image_wg pads the image only when controls show)
        self:_new_image_wg()
        self.buttons_visible, self.with_title_bar = saved_bv, saved_tb
        self.image_padding = saved_pad

        local body = VerticalGroup:new{ align = "left" }
        if top then table.insert(body, top) end
        table.insert(body, self.image_container)
        if cap then table.insert(body, cap) end
        if foot_w then
            table.insert(body, foot_line)
            table.insert(body, foot_w)
        end
        local page = OverlapGroup:new{ dimen = geom(W, H), body }
        if not controls(self) then
            local list = self._images_list and self._images_list_nb > 1
            local hint = GW.text(list and _("Tap the sides for the previous or next image · the middle shows the controls")
                or _("Tap to show the controls · pinch to zoom"), "ui", "fs-xs", "text-3", W - 2 * T.px("sp-4"))
            table.insert(page, BottomContainer:new{ dimen = geom(W, H - T.px("sp-4")),
                CenterContainer:new{ dimen = geom(W, hint:getSize().h), hint } })
        end
        -- (frame_elements: KOReader's onTap measures the title bar from its first element)
        self.frame_elements = body
        self.leaf_top = top
        self.main_frame = FrameContainer:new{ bordersize = 0, padding = 0, margin = 0, background = T.color("bg"),
            width = W, height = H, page }
        self.main_frame.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
        self[1] = self.main_frame
        self.dithered = true
        UIManager:setDirty(self, function()
            local r = self.main_frame.dimen
            if orig_dimen then r = r:combine(orig_dimen) end
            return "ui", r, true
        end)
    end, "ImageViewer:update")

    -- the top bar and the foot handle their own taps; KOReader's onTap does the rest
    L.wrap(ImageViewer, "onTap", function(orig, self, arg, ges)
        local top = self.leaf_top
        if top and top.dimen and ges and ges.pos and ges.pos.y < top.dimen.y + top.dimen.h then return true end
        if not self.with_title_bar then
            -- KOReader skips its title-bar test then: same result
            return orig(self, arg, ges)
        end
        local saved = self.with_title_bar
        self.with_title_bar = false
        local ok, ret = pcall(orig, self, arg, ges)
        self.with_title_bar = saved
        if not ok then error(ret, 0) end
        return ret
    end, "ImageViewer:onTap")

    -- Book information › cover: open with the controls, named after the book
    local BookInfo = require("apps/filemanager/filemanagerbookinfo")
    L.wrap(BookInfo, "onShowBookCover", function(orig, self, file, force_orig)
        pcall(function()
            local props = self:getDocProps(file or (self.document and self.document.file))
            local author = props and props.authors and props.authors:gsub("[\n;].*", "") or nil
            ImageViewer._leaf_cover = { title = props and props.display_title or props.title,
                sub = _("Cover image") .. (author and author ~= "" and (" · " .. author) or "") }
        end)
        local ok, ret = pcall(orig, self, file, force_orig)
        ImageViewer._leaf_cover = nil
        if not ok then error(ret, 0) end
        return ret
    end, "BookInfo:onShowBookCover")
end

return M
