-- Text catalog pages using the same TitleBar/footer as the DocLN cover grid.
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local Device = require("device")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local PagedScreen = require("booxbook.ui.paged-screen")

local Screen = Device.screen
local unpack = rawget(table, "unpack") or unpack

local ItemList = PagedScreen:extend{
    name = "booxbook_item_list",
}

local function rowPadding()
    return Size.padding.large or Size.padding.small * 2
end

local function dividerHeight()
    return (Size.line and Size.line.thin) or 1
end

local function rowHeight()
    -- Larger than KOReader Menu rows so category taps have a comfortable target.
    local pad = rowPadding()
    local min_h = Screen:scaleBySize(48)
    if Size.item and Size.item.height_default then
        min_h = math.max(min_h, Size.item.height_default + pad * 2)
    end
    return min_h + dividerHeight()
end

function ItemList:init()
    self.items = self.items or {}
    self.offset = self.offset or 1
    PagedScreen.init(self)
end

function ItemList:_pageSize(body_h)
    local size = math.max(1, math.floor((body_h or 1) / rowHeight()))
    self.page_size = size
    local total = #self.items
    self.page_count = math.max(1, math.ceil(math.max(total, 1) / size))
    if total == 0 then
        self.offset = 1
        return size
    end
    if self.offset > total then
        self.offset = math.floor((total - 1) / size) * size + 1
    end
    if self.offset < 1 then self.offset = 1 end
    return size
end

function ItemList:navState()
    local page_size = self.page_size or 1
    return {
        can_prev = self.offset > 1,
        can_next = (self.offset + page_size) <= #self.items,
        page_no = math.floor((math.max(self.offset, 1) - 1) / page_size) + 1,
    }
end

function ItemList:_rowLabel(item)
    local text = item.text or ""
    if item.checked_func then
        if item.checked_func() then
            text = "✓ " .. text
        else
            text = "○ " .. text
        end
    end
    return text
end

function ItemList:_makeRow(item, width, height)
    local enabled = item.select_enabled ~= false
    if enabled and item.select_enabled_func then
        enabled = not not item.select_enabled_func()
    end
    local face = Font:getFace("smallinfofont")
    local pad = rowPadding()
    local inner_w = math.max(1, width - pad * 2)
    local color = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    local title = TextBoxWidget:new{
        text = self:_rowLabel(item),
        face = face,
        width = item.mandatory and math.floor(inner_w * 0.78) or inner_w,
        height = height - pad * 2,
        fgcolor = color,
    }
    local row = { title }
    if item.mandatory then
        row[#row + 1] = HorizontalSpan:new{ width = pad }
        row[#row + 1] = TextBoxWidget:new{
            text = tostring(item.mandatory),
            face = Font:getFace("xx_smallinfofont"),
            width = math.max(1, inner_w - (item.mandatory and math.floor(inner_w * 0.78) or inner_w) - pad),
            height = height - pad * 2,
            alignment = "right",
            fgcolor = color,
        }
    end
    local content = HorizontalGroup:new{ unpack(row) }
    -- TextBoxWidget already reserves height - pad * 2, even for one line.
    return FrameContainer:new{
        bordersize = 0,
        padding = pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            align = "left",
            content,
        },
    }, enabled
end

function ItemList:buildBody(body_w, body_h)
    local page_size = self:_pageSize(body_h)
    local row_h = rowHeight()
    local content_h = math.max(1, row_h - dividerHeight())
    local last = math.min(#self.items, self.offset + page_size - 1)
    local rows = {}
    self.item_dimens = {}
    for index = self.offset, last do
        local item = self.items[index]
        local row, enabled = self:_makeRow(item, body_w, content_h)
        local divider = LineWidget:new{
            background = Blitbuffer.COLOR_DARK_GRAY,
            dimen = Geom:new{ w = body_w, h = dividerHeight() },
        }
        local slot = VerticalGroup:new{
            align = "left",
            row,
            divider,
        }
        -- Hit the row FrameContainer: VerticalGroup does not set dimen in paintTo.
        self.item_dimens[#self.item_dimens + 1] = {
            widget = row,
            item = item,
            enabled = enabled,
            divider = divider,
        }
        rows[#rows + 1] = slot
    end
    if #rows == 0 then
        rows[1] = HorizontalSpan:new{ width = body_w }
    end
    return VerticalGroup:new{
        align = "left",
        unpack(rows),
    }
end

function ItemList:_turn(delta)
    if self._closed then return true end
    local page_size = self.page_size or 1
    if delta > 0 then
        if self.offset + page_size <= #self.items then
            self.offset = self.offset + page_size
            self:rebuild()
            UIManager:setDirty(self, "ui")
        end
        return true
    end
    if self.offset > 1 then
        self.offset = math.max(1, self.offset - page_size)
        self:rebuild()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function ItemList:onNextPage()
    return self:_turn(1)
end

function ItemList:onPrevPage()
    return self:_turn(-1)
end

function ItemList:onChoose(entry)
    if self._closed or not entry or not entry.item then return true end
    local item = entry.item
    if item.select_enabled == false then return true end
    if item.select_enabled_func and not item.select_enabled_func() then return true end
    if item.sub_item_table then
        Catalog.show{
            title = item.text,
            items = item.sub_item_table,
        }
        return true
    end
    if item.callback then
        item.callback()
    end
    if self._closed then return true end
    -- Cover-grid selection never dismisses the page; only Quay lại / TitleBar X close.
    if item.checked_func then
        self:rebuild()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function ItemList:paintTo(bb, x, y)
    PagedScreen.paintTo(self, bb, x, y)
    if self._closed or not self.dimen then return end
    local title_h = 0
    if self.title_bar and self.title_bar.getHeight then
        title_h = self.title_bar:getHeight() or 0
    end
    local gap = Size.padding.small
    local row_h = rowHeight()
    local x0 = (self.dimen.x or 0) + gap
    local y0 = (self.dimen.y or 0) + title_h + gap
    local width = math.max(1, self.dimen.w - gap * 2)
    for index, entry in ipairs(self.item_dimens) do
        if entry.widget then
            entry.widget.dimen = Geom:new{
                x = x0,
                y = y0 + (index - 1) * row_h,
                w = width,
                h = row_h,
            }
        end
    end
end

function ItemList.show(opts)
    opts = opts or {}
    local list = ItemList:new{
        title = opts.title,
        subtitle = opts.subtitle,
        items = opts.items or {},
        on_search = opts.on_search,
        left_icon = opts.left_icon,
        on_left_icon = opts.on_left_icon,
        on_close = opts.on_close,
    }
    Catalog.push(list)
    return list
end

return ItemList
