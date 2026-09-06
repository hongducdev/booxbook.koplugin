-- Catalog lists use the same TitleBar/footer chrome as the DocLN cover grid.
local names = {
    'ffi/blitbuffer', 'ui/widget/container/centercontainer', 'device', 'ui/font',
    'ui/widget/container/framecontainer', 'ui/geometry', 'ui/gesturerange',
    'ui/widget/horizontalgroup', 'ui/widget/horizontalspan', 'ui/widget/container/inputcontainer',
    'ui/size', 'ui/widget/textboxwidget', 'ui/widget/titlebar', 'ui/uimanager',
    'ui/widget/verticalgroup', 'ui/widget/verticalspan', 'booxbook.ui.catalog',
    'booxbook.ui.paged-screen', 'ui/widget/container/bottomcontainer', 'ui/widget/overlapgroup', 'booxbook.ui.item-list', 'gettext',
    'ui/widget/confirmbox', 'ui/widget/inputdialog',
    'ui/widget/linewidget', 'ui/widget/container/widgetcontainer',
}
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

package.loaded['booxbook.ui.catalog'] = nil
package.loaded['booxbook.ui.paged-screen'] = nil
package.loaded['booxbook.ui.item-list'] = nil
package.loaded.gettext = function(text) return text end
package.loaded['ffi/blitbuffer'] = { COLOR_WHITE = 0, COLOR_BLACK = 1, COLOR_DARK_GRAY = 2 }
local function passthroughNew(_, value)
    value = value or {}
    value.dimen = value.dimen or { intersectWith = function() return false end }
    return value
end
package.loaded['ui/widget/container/centercontainer'] = { new = passthroughNew }
package.loaded['ui/widget/container/framecontainer'] = { new = passthroughNew }
package.loaded['ui/widget/horizontalgroup'] = { new = passthroughNew }
package.loaded['ui/widget/horizontalspan'] = { new = passthroughNew }
package.loaded['ui/widget/textboxwidget'] = { new = passthroughNew }
package.loaded['ui/widget/verticalgroup'] = { new = passthroughNew }
package.loaded['ui/widget/verticalspan'] = { new = passthroughNew }
package.loaded['ui/widget/container/bottomcontainer'] = { new = passthroughNew }
package.loaded['ui/widget/overlapgroup'] = { new = passthroughNew }
package.loaded['ui/widget/linewidget'] = { new = passthroughNew }
package.loaded['ui/widget/container/widgetcontainer'] = { new = passthroughNew }
package.loaded['device'] = {
    screen = {
        getWidth = function() return 600 end,
        getHeight = function() return 400 end,
        scaleBySize = function(_, value) return value end,
    },
    hasKeys = function() return false end,
    input = { group = { Back = 'Back' } },
}
package.loaded['ui/font'] = { getFace = function() return { size = 10 } end }
package.loaded['ui/geometry'] = { new = function(_, value)
    value = value or {}
    value.intersectWith = value.intersectWith or function() return false end
    return value
end }
package.loaded['ui/gesturerange'] = { new = passthroughNew }
local Input = { paintTo = function() end }
function Input:extend(value)
    setmetatable(value, { __index = self })
    value.__index = value
    function value:new(opts)
        local obj = setmetatable(opts or {}, value)
        if obj.init then obj:init() end
        return obj
    end
    return value
end
package.loaded['ui/widget/container/inputcontainer'] = Input
package.loaded['ui/size'] = {
    padding = { small = 2, large = 4 },
    border = { thin = 1 },
    line = { thin = 1 },
    item = { height_default = 16 },
}
local titlebars = {}
package.loaded['ui/widget/titlebar'] = { new = function(_, value)
    value.getHeight = function() return 30 end
    titlebars[#titlebars + 1] = value
    return value
end }
local shown, closed = {}, {}
package.loaded['ui/uimanager'] = {
    show = function(_, widget) shown[#shown + 1] = widget end,
    close = function(_, widget) closed[#closed + 1] = widget end,
    setDirty = function() end,
    nextTick = function() end,
}
package.loaded['ui/widget/confirmbox'] = {}
package.loaded['ui/widget/inputdialog'] = {}

local Catalog = dofile('booxbook.koplugin/booxbook/ui/catalog.lua')
package.loaded['booxbook.ui.catalog'] = Catalog

local items = {}
for i = 1, 10 do
    items[i] = { text = 'Item ' .. i, keep_menu_open = true, callback = function() end }
end
local toggled = 0
items[1].checked_func = function() return toggled % 2 == 1 end
items[1].callback = function() toggled = toggled + 1 end
local nested_called = 0
items[2].sub_item_table = {
    { text = 'Child', keep_menu_open = true, callback = function() nested_called = nested_called + 1 end },
}
items[3].select_enabled = false
items[3].callback = function() error('disabled item selected') end
local closed_parent = 0
local list = Catalog.show{
    title = 'Catalog',
    items = items,
    on_close = function() closed_parent = closed_parent + 1 end,
}
assert(list.nav_dimens[1].action == 'back' and list.nav_dimens[2].action == 'prev'
    and list.nav_dimens[4].action == 'next',
    'catalog footer matches cover-grid back/prev/page/next')
local updated = 0
local home = Catalog.show{
    title = 'Home',
    items = { { text = 'News' } },
    footer_slots = {
        { text = 'Quay lại', action = 'back', enabled = true },
        { text = 'v0.0.1', action = nil, enabled = false },
        { text = 'Cập nhật', action = 'update', enabled = true },
        { text = '1/1', action = nil, enabled = false },
    },
    on_footer = function(action)
        if action == 'update' then updated = updated + 1 end
    end,
}
assert(home.nav_dimens[2].action == nil and home.nav_dimens[2].enabled == false,
    'home footer version slot is visible but not tappable')
assert(home.nav_dimens[3].action == 'update' and home.nav_dimens[3].enabled,
    'home footer Cập nhật is tappable')
home:_runNavAction('update')
assert(updated == 1, 'home footer Cập nhật runs on_footer')
Catalog.pop(home)
assert(titlebars[1].left_icon == nil, 'catalog lists have no search icon by default')
local download_list = Catalog.show{
    title = 'Series',
    items = { { text = 'Vol' } },
    left_icon = 'appbar.menu',
    on_left_icon = function() end,
}
assert(titlebars[#titlebars].left_icon == 'appbar.menu', 'series details can put a menu icon on the title bar')
Catalog.pop(download_list)
assert(list._body_h == 400 - 30 - 44 - 4, 'body slot fills the screen so the footer stays at the bottom')
assert(list._body_slot and list._body_slot.dimen.h == list._body_h,
    'short lists still reserve the full canvas height under the title bar')
assert(list.dimen.h == 400, 'paged screens use the KOReader canvas height')
assert(list.page_size == 6, 'taller rows still paginate a full screen of categories')
local covered = {}
list:paintTo({
    paintRect = function(_, x, y, w, h)
        covered[#covered + 1] = { x = x, y = y, w = w, h = h }
    end,
}, 0, 0)
assert(covered[1] and covered[1].w == 600 and covered[1].h == 400,
    'paintTo fills the full canvas so a short catalog cannot leak the parent UI')
assert(list.nav_dimens[4].enabled, 'long lists paginate with Sau')
assert(#list.item_dimens == 6, 'first page shows one screen of rows')
assert(list.item_dimens[1].divider and list.item_dimens[1].divider.dimen.h == 1,
    'each category row has a divider under it')

list:onNextPage()
assert(list.offset == 7, 'Sau advances a local page')
list:onPrevPage()
assert(list.offset == 1, 'Trước returns to the previous local page')

list:onChoose(list.item_dimens[3])
assert(#Catalog._stack == 1, 'disabled rows do not close the list')
list:onChoose(list.item_dimens[1])
assert(toggled == 1 and #Catalog._stack == 1, 'checked rows stay open and refresh')
list:onChoose(list.item_dimens[2])
assert(#Catalog._stack == 2, 'nested tables open a child list, not KOReader submenus')
Catalog._stack[2]:onClose()
assert(Catalog._stack[1] == list, 'Quay lại restores the parent list')

local x_tap = { pos = {
    x = 595, y = 5,
    intersectWith = function() return false end,
} }
assert(list:onTap(nil, x_tap) == true)
assert(closed_parent == 1 and list._closed, 'TitleBar X closes the list without Menu onCloseAllMenus')
assert(list:onTap(nil, x_tap) == true)
assert(closed_parent == 1, 'repeated TitleBar X after close is ignored')

local menu_taps = 0
local menu_list = Catalog.show{
    title = 'Menu icon',
    items = { { text = 'Row' } },
    left_icon = 'appbar.menu',
    on_left_icon = function() menu_taps = menu_taps + 1 end,
}
assert(menu_list:onTap(nil, { pos = { x = 10, y = 5, intersectWith = function() return false end } }) == true)
assert(menu_taps == 1, 'left title-bar edge invokes on_left_icon')
Catalog.pop(menu_list)

local nested_closed = 0
local nested = Catalog.show{
    title = 'Nested',
    items = { { text = 'Open', callback = function() nested_closed = nested_closed + 1 end } },
}
nested.item_dimens[1].widget.dimen = { x = 0, y = 40, w = 200, h = 40 }
local row_event = {
    name = 'Gesture',
    handler = 'onGesture',
    args = { { ges = 'tap', pos = { x = 20, y = 50 } }, n = 1 },
}
for _, gesture in ipairs({ 'touch', 'hold', 'hold_release', 'pan', 'pan_release' }) do
    assert(nested:handleEvent{
        name = 'Gesture', handler = 'onGesture',
        args = { { ges = gesture, pos = { x = 20, y = 50 } }, n = 1 },
    } == true)
end
assert(nested_closed == 0, 'only tap selects: touch must not open a child before finger-up')
assert(nested:handleEvent(row_event) == true)
assert(nested_closed == 1, 'fullscreen page handles row taps before nested TextBoxWidget InputContainers')
nested.item_dimens[1].item.callback = function() nested_closed = nested_closed + 1 end
local row_tap = {
    handler = 'onTap',
    args = { { ges = 'tap', pos = { x = 20, y = 50 } }, n = 1 },
}
assert(nested:handleEvent(row_tap) == true)
assert(nested_closed == 2, 'onTap events are handled on the page, not by nested InputContainers')

local row_hits = 0
local tall_title = Catalog.show{
    title = 'Tall',
    items = { { text = 'Open', callback = function() row_hits = row_hits + 1 end } },
}
tall_title.title_bar.dimen = { x = 0, y = 0, w = 600, h = 400 }
tall_title.item_dimens[1].widget.dimen = { x = 0, y = 40, w = 200, h = 40 }
assert(tall_title:onTap(nil, { pos = { x = 20, y = 50 } }) == true)
assert(row_hits == 1, 'a fullscreen TitleBar.dimen must not swallow the first catalog row')

local gone = 0
local transient = Catalog.show{
    title = 'Transient',
    items = { { text = 'Go', callback = function() gone = gone + 1 end } },
}
transient:onChoose(transient.item_dimens[1])
assert(gone == 1 and not transient._closed,
    'row selection keeps the list open; only footer/X close, like the cover grid')

local closed_footer = 0
local paged = Catalog.show{
    title = 'Footer',
    items = { { text = 'A' }, { text = 'B' }, { text = 'C' }, { text = 'D' } },
    on_close = function() closed_footer = closed_footer + 1 end,
}
-- Point-sized taps (w=0) must still hit Quay lại via the footer band.
local back_tap = { pos = {
    x = 40, y = 370, w = 0, h = 0,
    intersectWith = function() return false end,
} }
assert(paged:onTap(nil, back_tap) == true)
assert(closed_footer == 1 and paged._closed,
    'footer band closes the list even when widget.dimen intersectWith fails')

package.loaded.android = {
    getStatusBarHeight = function() return 139 end,
    getNavigationBarHeight = function() return 80 end,
    getScreenAvailableHeight = function() return 300 end,
}
local inset_list = Catalog.show{
    title = 'Inset',
    items = { { text = 'A' } },
}
assert(inset_list.dimen.h == 400 and inset_list._body_slot.dimen.h == inset_list._body_h,
    'Android nav/status insets must not shrink the catalog below the KOReader canvas')
inset_list:onClose()

local closed_offset = 0
local offset_list = Catalog.show{
    title = 'Offset',
    items = { { text = 'A' } },
    on_close = function() closed_offset = closed_offset + 1 end,
}
offset_list.nav_dimens[1].widget.dimen = { x = 0, y = 200, w = 140, h = 44 }
local offset_tap = { pos = { x = 40, y = 61, w = 0, h = 0 } }
assert(offset_list:onTap(nil, offset_tap) == true)
assert(closed_offset == 0, 'a row tap must not hit a footer shifted by a system inset')
assert(offset_list:onTap(nil, { pos = { x = 40, y = 210 } }) == true)
assert(closed_offset == 1 and offset_list._closed,
    'canvas coordinates hit the painted Quay lại button')

local status_row = 0
local painted = Catalog.show{
    title = 'Painted',
    items = { { text = 'Hit', callback = function() status_row = status_row + 1 end } },
}
painted.item_dimens[1].widget.dimen = { x = 0, y = 139, w = 200, h = 40 }
assert(painted:onTap(nil, { pos = { x = 20, y = 149 } }) == true)
assert(status_row == 1, 'row taps must not be swallowed by an inset-shifted title band')
local closed_title_x = 0
local title_x_list = Catalog.show{
    title = 'TitleX',
    items = { { text = 'Row' } },
    on_close = function() closed_title_x = closed_title_x + 1 end,
}
assert(title_x_list:onTap(nil, { pos = { x = 580, y = 149, w = 0, h = 0 } }) == true)
assert(closed_title_x == 0, 'tapping below X must not close the page')
assert(title_x_list:onTap(nil, { pos = { x = 580, y = 10, w = 0, h = 0 } }) == true)
assert(closed_title_x == 1 and title_x_list._closed,
    'titlebar X closes using canvas coordinates')
package.loaded.android = nil

-- TextBoxWidget already reserves its explicit height; padding must not add it twice.
local row = list.item_dimens[1].widget
local content = row[1]
local measured_height = content[1][1].height + row.padding * 2
for i = 2, #content do measured_height = measured_height + (content[i].width or 0) end
assert(measured_height == 48, 'painted row height must match pagination and tap spacing')

for _, name in ipairs(names) do package.loaded[name] = saved[name] end
package.loaded['booxbook.ui.catalog'] = nil
package.loaded['booxbook.ui.paged-screen'] = nil
package.loaded['booxbook.ui.item-list'] = nil
print('Catalog list navigation matches cover-grid chrome and drops KOReader Menu paging')
