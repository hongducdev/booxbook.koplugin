-- Six cover/title cards per screen for source browse/search/news (2×3).
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Catalog = require("booxbook.ui.catalog")
local Covers = require("booxbook.covers")
local Http = require("booxbook.http")
local PagedScreen = require("booxbook.ui.paged-screen")
local Settings = require("booxbook.store.settings")

local Screen = Device.screen
local unpack = rawget(table, "unpack") or unpack
local ImageWidget
do
    local ok, mod = pcall(require, "ui/widget/imagewidget")
    if ok then ImageWidget = mod end
end

local CoverGrid = PagedScreen:extend{
    COLS = 2,
    ROWS = 3,
    name = "booxbook_cover_grid",
}

CoverGrid.PAGE_SIZE = CoverGrid.COLS * CoverGrid.ROWS

function CoverGrid:init()
    self.items = self.items or {}
    self.offset = self.offset or 1
    self.site_page = self.site_page or 1
    self.has_more = not not self.has_more
    self.source_id = self.source_id or "unknown"
    if self.covers_enabled == nil then self.covers_enabled = Settings.includeImages() end
    self._cover_job = false
    self._cover_failed = {}
    PagedScreen.init(self)
end

function CoverGrid:_visibleSlice()
    local slice = {}
    local last = math.min(#self.items, self.offset + self.PAGE_SIZE - 1)
    for i = self.offset, last do
        slice[#slice + 1] = self.items[i]
    end
    return slice
end

function CoverGrid:_coverUrl(item)
    if not item then return nil end
    local cover = item.cover
    if cover == nil or cover == "" then cover = item.thumbnail end
    if type(cover) ~= "string" or cover == "" then return nil end
    return Http.resolveUrl(self.base_url or "", cover)
end

function CoverGrid:_coverPath(item)
    -- Never download during widget build: sync HTTP + ImageWidget decode OOMs after search.
    if not self.covers_enabled then return nil end
    local url = self:_coverUrl(item)
    if not url then return nil end
    return Covers.find(self.source_id, url)
end

function CoverGrid:_queueCoverFetch()
    if self._closed or not self.covers_enabled or self._cover_job or not self.dimen then return end
    self._cover_failed = self._cover_failed or {}
    local pending
    for _, item in ipairs(self:_visibleSlice()) do
        local url = self:_coverUrl(item)
        if url and not self._cover_failed[url] and not Covers.find(self.source_id, url) then
            pending = url
            break
        end
    end
    if not pending then return end
    self._cover_job = true
    UIManager:nextTick(function()
        self._cover_job = false
        if self._closed or not self.dimen then return end
        local ok, path = pcall(Covers.fetch, self.source_id, pending, {
            referer = self.cover_referer,
            cookies = self.cover_cookies,
            delay_ms = self.cover_delay_ms or 0,
        })
        if self._closed or not self.dimen then return end
        if not ok or not path then
            self._cover_failed[pending] = true
            self:_queueCoverFetch()
            return
        end
        self:rebuild()
        UIManager:setDirty(self, "ui")
    end)
end

function CoverGrid:_titleBox(text, width, face, height)
    return TextBoxWidget:new{
        text = text or "",
        face = face,
        width = width,
        height = height,
        alignment = "center",
    }
end

function CoverGrid:_makeCard(item, width, height)
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

function CoverGrid:navState()
    return {
        can_prev = self.offset > 1 or self.site_page > 1,
        can_next = (self.offset + self.PAGE_SIZE) <= #self.items or self.has_more,
        page_no = math.floor((math.max(self.offset, 1) - 1) / self.PAGE_SIZE) + 1,
    }
end

function CoverGrid:buildBody(body_w, body_h)
    local gap = Size.padding.small
    local cell_w = math.floor((body_w - gap * (self.COLS - 1)) / self.COLS)
    local cell_h = math.floor((body_h - gap * (self.ROWS - 1)) / self.ROWS)
    local slice = self:_visibleSlice()
    local rows = {}
    self.item_dimens = {}
    local index = 0
    for row = 1, self.ROWS do
        local cols = {}
        for col = 1, self.COLS do
            index = index + 1
            local item = slice[index]
            local card
            if item then
                card = self:_makeCard(item, cell_w, cell_h)
                self.item_dimens[#self.item_dimens + 1] = { item = item, widget = card }
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
    return VerticalGroup:new{
        align = "center",
        unpack(rows),
    }
end

function CoverGrid:afterRebuild()
    self:_queueCoverFetch()
end

function CoverGrid:onChoose(entry)
    if self.on_select and entry and entry.item then
        self.on_select(entry.item)
    end
    return true
end

function CoverGrid:setPage(data)
    if self._closed then return end
    data = data or {}
    if data.items then self.items = data.items end
    if data.has_more ~= nil then self.has_more = not not data.has_more end
    if data.site_page then self.site_page = data.site_page end
    if data.page_count ~= nil then self.page_count = data.page_count end
    if data.offset then self.offset = data.offset end
    if data.source_id then self.source_id = data.source_id end
    if data.base_url ~= nil then self.base_url = data.base_url end
    if data.cover_referer ~= nil then self.cover_referer = data.cover_referer end
    if data.cover_cookies ~= nil then self.cover_cookies = data.cover_cookies end
    if data.cover_delay_ms ~= nil then self.cover_delay_ms = data.cover_delay_ms end
    if data.covers_enabled ~= nil then self.covers_enabled = data.covers_enabled end
    if data.title then
        self.title = data.title
        if self.title_bar and self.title_bar.setTitle then
            self.title_bar:setTitle(self.title, true)
        end
    end
    self:rebuild()
    if not self._closed then
        UIManager:setDirty(self, "ui")
    end
end

function CoverGrid:onClose()
    if self._closed then return true end
    self._cover_job = false
    return PagedScreen.onClose(self)
end

function CoverGrid:onCloseWidget()
    self._cover_job = false
    PagedScreen.onCloseWidget(self)
end

function CoverGrid.show(opts)
    opts = opts or {}
    local grid = CoverGrid:new{
        title = opts.title,
        items = opts.items or {},
        has_more = opts.has_more,
        site_page = opts.site_page or 1,
        page_count = opts.page_count,
        offset = opts.offset or 1,
        source_id = opts.source_id,
        base_url = opts.base_url,
        cover_referer = opts.cover_referer,
        cover_cookies = opts.cover_cookies,
        cover_delay_ms = opts.cover_delay_ms,
        covers_enabled = opts.covers_enabled,
        on_select = opts.on_select,
        on_search = opts.on_search,
        on_next = opts.on_next,
        on_prev = opts.on_prev,
        on_close = opts.on_close,
    }
    Catalog.push(grid)
    return grid
end

return CoverGrid
