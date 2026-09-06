-- Full-screen TitleBar + footer used by cover grids and catalog lists.
-- Do not use KOReader Menu chevrons or page_return_arrow.
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
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")

local Screen = Device.screen
local unpack = rawget(table, "unpack") or unpack
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

local function safeFree(widget)
    if not widget then return end
    pcall(function()
        if widget.free then widget:free() end
    end)
end

-- TitleBar is reused across rebuilds. WidgetContainer:free walks children, so
-- freeing the previous root would free TitleBar while the new tree still holds
-- it. A later title-bar X is a native double-free (search results included).
local function detachKeep(widget, keep)
    if type(widget) ~= "table" or widget == keep then return end
    for i = #widget, 1, -1 do
        if widget[i] == keep then
            table.remove(widget, i)
        else
            detachKeep(widget[i], keep)
        end
    end
end

local function safeFreeTree(widget, keep)
    if not widget or widget == keep then return end
    if keep then detachKeep(widget, keep) end
    safeFree(widget)
end

local function navHeight()
    return Screen:scaleBySize(44)
end

-- Match KOReader FileManager: the canvas is Screen:getWidth/Height.
-- Do not shrink by Android nav/status insets; that leaves the parent screen showing through.
local function displaySize()
    return Screen:getWidth(), Screen:getHeight()
end

-- KOReader supplies canvas coordinates. Applying Android insets again makes
-- a single tap overlap the title, another row, or the footer.
local function pointHits(pos, dimen)
    if not pos or not dimen or pos.x == nil or pos.y == nil then return false end
    local x0 = dimen.x or 0
    local y0 = dimen.y or 0
    local w = dimen.w or 0
    local h = dimen.h or 0
    local function inside(y)
        return pos.x >= x0 and pos.x < x0 + w and y >= y0 and y < y0 + h
    end
    return inside(pos.y)
end

local PagedScreen = InputContainer:extend{
    name = "booxbook_paged_screen",
}

function PagedScreen:init()
    local width, height = displaySize()
    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    self.covers_fullscreen = true
    self.item_dimens = {}
    self.nav_dimens = {}
    self._closed = false
    -- Covered Catalog parents stay on the UIManager stack; do not leak taps to them.
    self.stop_events_propagation = true

    local titlebar_opts = {
        fullscreen = true,
        title = self.title or "",
        subtitle = self.subtitle,
        title_multilines = false,
        with_bottom_line = true,
        close_callback = function()
            self:onClose()
        end,
        show_parent = self,
    }
    if self.on_search then
        titlebar_opts.left_icon = "appbar.search"
        titlebar_opts.left_icon_tap_callback = function()
            if self._closed then return end
            self.on_search()
        end
    elseif self.left_icon and self.on_left_icon then
        titlebar_opts.left_icon = self.left_icon
        titlebar_opts.left_icon_tap_callback = function()
            if self._closed then return end
            self.on_left_icon()
        end
    end
    self.title_bar = TitleBar:new(titlebar_opts)
    self:rebuild()

    self._touch_range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self._touch_range end,
            },
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self._touch_range end,
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

function PagedScreen:navState()
    return {
        can_prev = false,
        can_next = false,
        page_no = 1,
    }
end

function PagedScreen:buildBody(_body_w, _body_h)
    return HorizontalSpan:new{ width = 0 }
end

function PagedScreen:onChoose(_entry)
    return true
end

function PagedScreen:_navLabel(text, enabled, width)
    return FrameContainer:new{
        bordersize = Size.border.thin,
        padding = Size.padding.small,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        TextBoxWidget:new{
            text = text,
            face = Font:getFace("xx_smallinfofont"),
            width = width,
            alignment = "center",
            fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        },
    }
end

function PagedScreen:_pageLabel(page_no)
    if self.page_count and self.page_count > 0 then
        return tostring(math.min(page_no, self.page_count)) .. "/" .. tostring(self.page_count)
    end
    return tostring(page_no)
end

function PagedScreen:_footerSlots()
    if type(self.footer_slots) == "table" and #self.footer_slots > 0 then
        return self.footer_slots
    end
    local state = self:navState() or {}
    return {
        { text = _("Quay lại"), action = "back", enabled = true },
        { text = _("Trước"), action = "prev", enabled = not not state.can_prev },
        { text = self:_pageLabel(state.page_no or 1), action = nil, enabled = false },
        { text = _("Sau"), action = "next", enabled = not not state.can_next },
    }
end

function PagedScreen:_makeFooter(nav_h)
    local gap = Size.padding.small
    local slots = self:_footerSlots()
    local count = math.max(#slots, 1)
    local label_w = math.floor((self.dimen.w - gap * (count + 1)) / count)
        - Size.padding.small * 2 - Size.border.thin * 2
    local widgets = {}
    self.nav_dimens = {}
    for index, slot in ipairs(slots) do
        local enabled = slot.action ~= nil
        if slot.enabled == false then
            enabled = false
        elseif slot.enabled == true then
            enabled = true
        end
        local widget = self:_navLabel(slot.text or "", enabled, label_w)
        self.nav_dimens[#self.nav_dimens + 1] = {
            widget = widget,
            action = slot.action,
            enabled = enabled,
        }
        if index > 1 then
            widgets[#widgets + 1] = HorizontalSpan:new{ width = gap }
        end
        widgets[#widgets + 1] = widget
    end
    return CenterContainer:new{
        dimen = Geom:new{ w = self.dimen.w, h = nav_h },
        HorizontalGroup:new{ unpack(widgets) },
    }
end

function PagedScreen:rebuild()
    if self._closed or not self.dimen or not self.title_bar then return end
    local title_h = self.title_bar:getHeight()
    local gap = Size.padding.small
    local nav_h = navHeight()
    local body_h = math.max(1, self.dimen.h - title_h - nav_h - gap * 2)
    local body_w = self.dimen.w - gap * 2
    self.item_dimens = {}
    self._body_h = body_h
    local body = self:buildBody(body_w, body_h) or HorizontalSpan:new{ width = 0 }
    local footer = self:_makeFooter(nav_h)
    -- WidgetContainer:getSize() honors dimen, so a short list still fills the canvas
    -- and keeps the footer on the last row instead of floating over the parent UI.
    local body_slot = WidgetContainer:new{
        dimen = Geom:new{ w = self.dimen.w, h = body_h },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = gap },
            body,
        },
    }
    self._body_slot = body_slot
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
            body_slot,
            VerticalSpan:new{ width = gap },
            footer,
        },
    }
    local old_body = self._body
    self._body = new_root
    self[1] = new_root
    safeFreeTree(old_body, self.title_bar)
    if self.afterRebuild then
        self:afterRebuild()
    end
end

function PagedScreen:getSize()
    local width, height = displaySize()
    return Geom:new{ x = 0, y = 0, w = width, h = height }
end

function PagedScreen:paintTo(bb, x, y)
    if self._closed then return end
    local width, height = displaySize()
    if not self.dimen then
        self.dimen = Geom:new{ x = x, y = y, w = width, h = height }
    else
        self.dimen.x = x
        self.dimen.y = y
        self.dimen.w = width
        self.dimen.h = height
    end
    if self._touch_range then
        self._touch_range.x = 0
        self._touch_range.y = 0
        self._touch_range.w = width
        self._touch_range.h = height
    end
    -- FrameContainer:getSize() ignores width/height, so paint the canvas ourselves
    -- or the FileManager (or any parent) shows through under a short list.
    if bb and bb.paintRect then
        bb:paintRect(x, y, width, height, Blitbuffer.COLOR_WHITE)
    end
    if self[1] and self[1].paintTo then
        self[1]:paintTo(bb, x, y)
    end
    self.dimen.x = x
    self.dimen.y = y
    self.dimen.w = width
    self.dimen.h = height
end

function PagedScreen:onClose()
    if self._closed then return true end
    self._closed = true
    self.dimen = nil
    local on_close = self.on_close
    self.on_close = nil
    if on_close then
        pcall(on_close)
    end
    Catalog.pop(self)
    return true
end

function PagedScreen:onCloseWidget()
    self._closed = true
    self.dimen = nil
    self._body = nil
    self._body_slot = nil
    self.title_bar = nil
    self.item_dimens = {}
    self.nav_dimens = {}
    local on_close = self.on_close
    self.on_close = nil
    if on_close then
        pcall(on_close)
    end
end

function PagedScreen:_inTitleBand(pos)
    -- TitleBar.dimen can be the full canvas (OverlapGroup). Only the
    -- getHeight() band is the title; otherwise the first catalog rows
    -- are swallowed as title taps.
    if not pos or pos.y == nil or not self.title_bar then return false end
    local title_h = 0
    if self.title_bar.getHeight then title_h = self.title_bar:getHeight() or 0 end
    if title_h <= 0 then return false end
    local y0 = self.dimen and self.dimen.y or 0
    local function inside(y)
        return y >= y0 and y < y0 + title_h
    end
    return inside(pos.y)
end

function PagedScreen:_inFooterBand(pos)
    if not pos or pos.y == nil then return false end
    if self.nav_dimens then
        for _, entry in ipairs(self.nav_dimens) do
            local dimen = entry.widget and entry.widget.dimen
            if dimen and (tonumber(dimen.h) or 0) > 0 then
                local y0 = dimen.y or 0
                local y1 = y0 + dimen.h
                if pos.y >= y0 and pos.y < y1 then return true end
            end
        end
    end
    if not self.dimen then return false end
    local y0 = (self.dimen.y or 0) + self.dimen.h - navHeight()
    local y1 = (self.dimen.y or 0) + self.dimen.h
    return pos.y >= y0 and pos.y < y1
end

function PagedScreen:_footerActionAt(pos)
    if not pos or not self.nav_dimens then return nil end
    for _, entry in ipairs(self.nav_dimens) do
        if pointHits(pos, entry.widget and entry.widget.dimen) and entry.enabled and entry.action then
            return entry.action
        end
    end
    if not self:_inFooterBand(pos) then return nil end
    local gap = Size.padding.small
    local count = math.max(#self.nav_dimens, 1)
    local slot = math.max(1, math.floor((self.dimen.w - gap * (count + 1)) / count))
    local x0 = self.dimen.x or 0
    local x = pos.x
    if x == nil then return nil end
    for index, entry in ipairs(self.nav_dimens) do
        local left = x0 + gap + (index - 1) * (slot + gap)
        if x >= left and x < left + slot and entry.enabled and entry.action then
            return entry.action
        end
    end
    return nil
end

function PagedScreen:_runNavAction(action)
    if action == "back" then return self:onClose() end
    if action == "next" then return self:onNextPage() end
    if action == "prev" then return self:onPrevPage() end
    if type(self.on_footer) == "function" then
        self.on_footer(action)
    end
    return true
end

function PagedScreen:handleEvent(event)
    -- Nested TitleBar IconButtons and TextBoxWidgets are InputContainers.
    -- WidgetContainer walks children first, so those widgets would eat taps
    -- before this fullscreen page can close, page, or select a row.
    if event then
        local handler = event.handler
        local ges = event.args and event.args[1]
        if handler == "onTap" then
            return self:onTap(nil, ges)
        end
        if handler == "onSwipe" then
            return self:onSwipe(nil, ges)
        end
        if event.name == "Gesture" or handler == "onGesture" then
            if not ges then return true end
            if ges.ges == "swipe" then
                return self:onSwipe(nil, ges)
            elseif ges.ges == "tap" then
                return self:onTap(nil, ges)
            end
            -- Touch/hold/release must not select before the final tap arrives.
            return true
        end
    end
    if InputContainer.handleEvent then
        return InputContainer.handleEvent(self, event)
    end
end

function PagedScreen:onTap(_, ges)
    if self._closed or not ges or not ges.pos then return true end
    if self:_inTitleBand(ges.pos) then
        local pos, dimen = ges.pos, self.dimen
        local edge = math.max(Screen:scaleBySize(48), math.floor((dimen and dimen.w or 0) * 0.12))
        local x0 = dimen and dimen.x or 0
        local x = pos.x
        if x and dimen and x >= x0 + dimen.w - edge then
            return self:onClose()
        end
        if x and x <= x0 + edge then
            if self.on_search then
                self.on_search()
            elseif self.on_left_icon then
                self.on_left_icon()
            end
        end
        return true
    end
    local action = self:_footerActionAt(ges.pos)
    if action then
        return self:_runNavAction(action)
    end
    for _, entry in ipairs(self.item_dimens) do
        if pointHits(ges.pos, entry.widget and entry.widget.dimen) then
            if entry.enabled ~= false then
                self:onChoose(entry)
            end
            return true
        end
    end
    return true
end

function PagedScreen:onSwipe(_, ges)
    if self._closed or not ges then return true end
    local direction = flipDirection(ges.direction)
    if direction == "west" then
        self:onNextPage()
    elseif direction == "east" then
        self:onPrevPage()
    elseif direction == "south" then
        return self:onClose()
    end
    return true
end

function PagedScreen:onNextPage()
    if self._closed then return true end
    if self.on_next then self.on_next() end
    return true
end

function PagedScreen:onPrevPage()
    if self._closed then return true end
    if self.on_prev then self.on_prev() end
    return true
end

return PagedScreen
