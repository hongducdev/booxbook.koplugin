-- Six cover/title cards per screen for DocLN browse/search (2×3).
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Covers = require("booxbook.covers")
local Settings = require("booxbook.store.settings")

local Screen = Device.screen
local unpack = rawget(table, "unpack") or unpack
local ImageWidget
do
    local ok, mod = pcall(require, "ui/widget/imagewidget")
    if ok then ImageWidget = mod end
end
local flipDirection
do
    local ok, BD = pcall(require, "ui/bidi")
    if ok and BD.flipDirectionIfMirroredUILayout then
        flipDirection = function(direction)
            return BD.flipDirectionIfMirroredUILayout(direction)
        end
    else
        flipDirection = function(direction) return direction end
    end
end

local NovelGrid = InputContainer:extend{
    COLS = 2,
    ROWS = 3,
    name = "booxbook_novel_grid",
}

NovelGrid.PAGE_SIZE = NovelGrid.COLS * NovelGrid.ROWS

local function safeFree(widget)
    if not widget then return end
    pcall(function()
        if widget.free then widget:free() end
    end)
end

function NovelGrid:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.items = self.items or {}
    self.offset = self.offset or 1
    self.site_page = self.site_page or 1
    self.has_more = not not self.has_more
    self.covers_enabled = Settings.includeImages()
    self.card_dimens = {}
    self.nav_dimens = {}
    self._closed = false
    self._cover_job = false
    self._cover_failed = {}

    self.title_bar = TitleBar:new{
        fullscreen = true,
        title = self.title or _("DocLN"),
        title_multilines = false,
        with_bottom_line = true,
        left_icon = "appbar.search",
        left_icon_tap_callback = function()
            if self._closed then return end
            if self.on_search then self.on_search() end
        end,
        close_callback = function()
            self:onClose()
        end,
        show_parent = self,
    }

    self:_rebuildBody()

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            },
        },
    }
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            NextPage = { { "RPgFwd" }, { "Right" } },
            PrevPage = { { "RPgBack" }, { "Left" } },
        }
    end
end

function NovelGrid:_visibleSlice()
    local slice = {}
    local last = math.min(#self.items, self.offset + self.PAGE_SIZE - 1)
    for i = self.offset, last do
        slice[#slice + 1] = self.items[i]
    end
    return slice
end

function NovelGrid:_coverPath(item)
    -- Never download during widget build: sync HTTP + ImageWidget decode OOMs after search.
    if not self.covers_enabled or not item or type(item.cover) ~= "string" or item.cover == "" then
        return nil
    end
    local home = Settings.get("docln_home") or "https://docln.net"
    local url = item.cover
    if url:sub(1, 2) == "//" then
        url = "https:" .. url
    elseif url:sub(1, 1) == "/" then
        url = home .. url
    end
    return Covers.find("docln", url)
end

function NovelGrid:_queueCoverFetch()
    if self._closed or not self.covers_enabled or self._cover_job or not self.dimen then return end
    self._cover_failed = self._cover_failed or {}
    local home = Settings.get("docln_home") or "https://docln.net"
    local pending
    for _, item in ipairs(self:_visibleSlice()) do
        if type(item.cover) == "string" and item.cover ~= "" then
            local url = item.cover
            if url:sub(1, 2) == "//" then url = "https:" .. url
            elseif url:sub(1, 1) == "/" then url = home .. url end
            if not self._cover_failed[url] and not Covers.find("docln", url) then
                pending = url
                break
            end
        end
    end
    if not pending then return end
    self._cover_job = true
    UIManager:nextTick(function()
        self._cover_job = false
        if self._closed or not self.dimen then return end
        local ok, path = pcall(Covers.fetch, "docln", pending, {
            referer = home .. "/",
            cookies = Settings.cookie("docln"),
            delay_ms = 0,
        })
        if self._closed or not self.dimen then return end
        if not ok or not path then
            self._cover_failed[pending] = true
            self:_queueCoverFetch()
            return
        end
        self:_rebuildBody()
        UIManager:setDirty(self, "ui")
    end)
end

function NovelGrid:_titleBox(text, width, face, height)
    return TextBoxWidget:new{
        text = text or "",
        face = face,
        width = width,
        height = height,
        alignment = "center",
    }
end

function NovelGrid:_makeCard(item, width, height)
    local face = Font:getFace("xx_smallinfofont")
    local pad = Size.padding.small
    local title_h = math.floor(face.size * 2.6)
    local min_cover = Screen:scaleBySize(80)
    if Size.item and Size.item.height_default then
        min_cover = math.max(min_cover, Size.item.height_default)
    end
    local cover_h = math.max(min_cover, height - title_h - pad * 3)
    local inner_w = width - pad * 2
    local stack = {}
    local cover_path = self:_coverPath(item)
    local used_image = false
    if cover_path and ImageWidget then
        local ok, image = pcall(function()
            return ImageWidget:new{
                file = cover_path,
                width = inner_w,
                height = cover_h,
                scale_factor = 0,
                file_do_cache = false,
            }
        end)
        if ok and image then
            used_image = true
            stack[#stack + 1] = CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = cover_h },
                image,
            }
            stack[#stack + 1] = VerticalSpan:new{ width = Size.padding.small }
            stack[#stack + 1] = self:_titleBox(item.title, inner_w, face, title_h)
        end
    end
    if not used_image then
        stack[#stack + 1] = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = cover_h + title_h },
            self:_titleBox(item and item.title or "", inner_w, Font:getFace("smallinfofont"), cover_h + title_h),
        }
    end
    return FrameContainer:new{
        bordersize = Size.border.thin,
        padding = pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "center",
            unpack(stack),
        },
    }
end

function NovelGrid:_navLabel(text, enabled)
    return FrameContainer:new{
        bordersize = Size.border.thin,
        padding = Size.padding.small,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        TextBoxWidget:new{
            text = text,
            face = Font:getFace("xx_smallinfofont"),
            width = math.floor(self.dimen.w / 3) - Size.padding.large,
            alignment = "center",
            fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        },
    }
end

function NovelGrid:_rebuildBody()
    if self._closed or not self.dimen or not self.title_bar then return end
    local title_h = self.title_bar:getHeight()
    local gap = Size.padding.small
    local nav_h = Screen:scaleBySize(44)
    local body_h = self.dimen.h - title_h - nav_h - gap * 2
    local body_w = self.dimen.w - gap * 2
    local cell_w = math.floor((body_w - gap * (self.COLS - 1)) / self.COLS)
    local cell_h = math.floor((body_h - gap * (self.ROWS - 1)) / self.ROWS)

    local slice = self:_visibleSlice()
    local rows = {}
    self.card_dimens = {}
    local index = 0
    for row = 1, self.ROWS do
        local cols = {}
        for col = 1, self.COLS do
            index = index + 1
            local item = slice[index]
            local card
            if item then
                card = self:_makeCard(item, cell_w, cell_h)
                self.card_dimens[#self.card_dimens + 1] = { item = item, widget = card }
            else
                card = HorizontalSpan:new{ width = cell_w }
            end
            cols[#cols + 1] = CenterContainer:new{
                dimen = Geom:new{ w = cell_w, h = cell_h },
                card,
            }
            if col < self.COLS then
                cols[#cols + 1] = HorizontalSpan:new{ width = gap }
            end
        end
        rows[#rows + 1] = HorizontalGroup:new{ unpack(cols) }
        if row < self.ROWS then
            rows[#rows + 1] = VerticalSpan:new{ width = gap }
        end
    end

    local can_prev = self.offset > 1 or self.site_page > 1
    local can_next = (self.offset + self.PAGE_SIZE) <= #self.items or self.has_more
    local page_no = math.floor((math.max(self.offset, 1) - 1) / self.PAGE_SIZE) + 1
    local prev = self:_navLabel(_("Trước"), can_prev)
    local mid = self:_navLabel(tostring(page_no), false)
    local nextb = self:_navLabel(_("Sau"), can_next)
    self.nav_dimens = {
        { widget = prev, action = "prev", enabled = can_prev },
        { widget = mid, action = nil, enabled = false },
        { widget = nextb, action = "next", enabled = can_next },
    }

    -- Body excludes title_bar so rebuild/free cannot destroy the TitleBar used by close/X.
    local new_body = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = self.dimen.w,
        VerticalGroup:new{
            align = "left",
            HorizontalGroup:new{
                HorizontalSpan:new{ width = gap },
                VerticalGroup:new{
                    align = "center",
                    unpack(rows),
                },
            },
            VerticalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = self.dimen.w, h = nav_h },
                HorizontalGroup:new{
                    prev,
                    HorizontalSpan:new{ width = gap },
                    mid,
                    HorizontalSpan:new{ width = gap },
                    nextb,
                },
            },
        },
    }
    local new_root = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = self.dimen.w,
        height = self.dimen.h,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            VerticalSpan:new{ width = gap },
            new_body,
        },
    }
    local old_body = self._body
    self._body = new_body
    self[1] = new_root
    -- Free previous cards/images only. Never free the root (it shared title_bar).
    safeFree(old_body)
    self:_queueCoverFetch()
end

function NovelGrid:setPage(data)
    if self._closed then return end
    data = data or {}
    if data.items then self.items = data.items end
    if data.has_more ~= nil then self.has_more = not not data.has_more end
    if data.site_page then self.site_page = data.site_page end
    if data.offset then self.offset = data.offset end
    if data.title then
        self.title = data.title
        if self.title_bar and self.title_bar.setTitle then
            self.title_bar:setTitle(self.title, true)
        end
    end
    self:_rebuildBody()
    if not self._closed then
        UIManager:setDirty(self, "ui")
    end
end

function NovelGrid:paintTo(bb, x, y)
    if self._closed or not self.dimen then return end
    self.dimen.x = x
    self.dimen.y = y
    InputContainer.paintTo(self, bb, x, y)
end

function NovelGrid:onClose()
    if self._closed then return true end
    self._closed = true
    self._cover_job = false
    -- Stop deferred cover work before widgets are torn down.
    self.dimen = nil
    -- Clear session before UIManager:close/free — after free, on_close may be gone
    -- and a stale session.grid makes the next DocLN open call setPage on a dead widget.
    local on_close = self.on_close
    self.on_close = nil
    if on_close then
        pcall(on_close)
    end
    Catalog.pop(self)
    return true
end

function NovelGrid:onCloseWidget()
    -- Mark closed so pending nextTick cover jobs no-op. Do not free children here:
    -- UIManager/WidgetContainer:free will walk self[1] once; freeing twice crashes.
    self._closed = true
    self._cover_job = false
    self.dimen = nil
    self._body = nil
    self.title_bar = nil
    self.card_dimens = {}
    self.nav_dimens = {}
    local on_close = self.on_close
    self.on_close = nil
    if on_close then
        pcall(on_close)
    end
end

function NovelGrid:onTap(_, ges)
    if self._closed or not ges or not ges.pos then return false end
    if self.title_bar and self.title_bar.dimen and ges.pos:intersectWith(self.title_bar.dimen) then
        return false
    end
    for _, entry in ipairs(self.card_dimens) do
        local dimen = entry.widget and entry.widget.dimen
        if dimen and ges.pos:intersectWith(dimen) then
            if self.on_select and entry.item then
                self.on_select(entry.item)
            end
            return true
        end
    end
    for _, entry in ipairs(self.nav_dimens) do
        local dimen = entry.widget and entry.widget.dimen
        if dimen and ges.pos:intersectWith(dimen) and entry.enabled and entry.action then
            if entry.action == "next" and self.on_next then self.on_next() end
            if entry.action == "prev" and self.on_prev then self.on_prev() end
            return true
        end
    end
    return true
end

function NovelGrid:onSwipe(_, ges)
    if self._closed or not ges then return false end
    local direction = flipDirection(ges.direction)
    if direction == "west" and self.on_next then
        self.on_next()
        return true
    elseif direction == "east" and self.on_prev then
        self.on_prev()
        return true
    elseif direction == "south" then
        return self:onClose()
    end
    return false
end

function NovelGrid:onNextPage()
    if self._closed then return true end
    if self.on_next then self.on_next() end
    return true
end

function NovelGrid:onPrevPage()
    if self._closed then return true end
    if self.on_prev then self.on_prev() end
    return true
end

function NovelGrid.show(opts)
    opts = opts or {}
    local grid = NovelGrid:new{
        title = opts.title,
        items = opts.items or {},
        has_more = opts.has_more,
        site_page = opts.site_page or 1,
        offset = opts.offset or 1,
        on_select = opts.on_select,
        on_search = opts.on_search,
        on_next = opts.on_next,
        on_prev = opts.on_prev,
        on_close = opts.on_close,
    }
    Catalog.push(grid)
    return grid
end

return NovelGrid
