-- Exercise real menu callbacks with KOReader widgets replaced at the UI boundary.
local names = { 'ui/widget/infomessage', 'ui/network/manager', 'apps/reader/readerui',
    'ui/trapper', 'ui/uimanager', 'gettext', 'booxbook.ui.catalog', 'booxbook.ui.series',
    'booxbook.ui.cover-grid' }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
local Docln = require('booxbook.sources.docln')
local Download = require('booxbook.novel-download')
local old = { Docln.search, Docln.getSeries, Docln.browse, Download.range, Download.savedList }
local shown, prompt, confirm, opened, notice, grid
local wifi, cleared, queue = 0, 0, {}
local online = true
local function drain() while #queue > 0 do table.remove(queue, 1)() end end
package.loaded.gettext = function(text) return text end
package.loaded['ui/widget/infomessage'] = { new = function(_, value) return value end }
package.loaded['ui/uimanager'] = { show = function(_, value) notice = value.text end,
    nextTick = function(_, callback) queue[#queue + 1] = callback end }
package.loaded['ui/network/manager'] = {
    isOnline = function() return online end,
    isConnected = function() return online end,
    beforeWifiAction = function(_, fn) wifi = wifi + 1; fn() end,
}
package.loaded['ui/trapper'] = { wrap = function(_, fn) fn() end, info = function() end,
    clear = function() cleared = cleared + 1 end }
package.loaded['apps/reader/readerui'] = { showReader = function(_, path) opened = path end }
package.loaded['booxbook.ui.catalog'] = { show = function(value) shown = value end,
    promptText = function(value) prompt = value end, clearStack = function() end,
    confirm = function(_, callback) confirm = callback end, push = function() end, pop = function() end }
package.loaded['booxbook.ui.series'] = nil
package.loaded['booxbook.ui.cover-grid'] = {
    PAGE_SIZE = 6,
    show = function(opts)
        grid = {
            opts = opts,
            pages = {},
            setPage = function(self, page) self.pages[#self.pages + 1] = page; self.opts.offset = page.offset end,
        }
        return grid
    end,
}
package.loaded['booxbook.network'] = nil
package.loaded['booxbook.ui.novels'] = nil
local SeriesUI = require('booxbook.ui.series')
local Novels = dofile('booxbook.koplugin/booxbook/ui/novels.lua')
local chapters = { { title = 'One', index = 1 }, { title = 'Two', index = 2 } }
local series = { title = 'Book', chapters = chapters, volumes = { { chapters = chapters } } }

local function sevenItems()
    local items = {}
    for i = 1, 7 do items[i] = { title = 'Book' .. i, url = '/truyen/' .. i } end
    return items
end

Docln.browse = function(kind, page)
    assert(kind == 'latest' and page == 1)
    return { items = sevenItems(), has_more = true }
end
Novels.openSource(); assert(wifi == 0, 'network must be deferred beyond menu selection')
drain()
assert(wifi == 0 and grid and #grid.opts.items == 7 and grid.opts.offset == 1)
assert(grid.opts.source_id == 'docln' and grid.opts.cover_referer == grid.opts.base_url .. '/',
    'DocLN grid supplies source cover context')
assert(grid.opts.title:find('Mới cập nhật', 1, true))

-- Local pagination keeps one HTTP page and advances six cards at a time.
wifi = 0
Docln.browse = function() error('must not refetch for local next') end
grid.opts.on_next(); assert(wifi == 0 and grid.opts.offset == 7)
grid.opts.on_prev(); assert(wifi == 0 and grid.opts.offset == 1)
grid.opts.on_next(); assert(grid.opts.offset == 7)

-- Exhausting the local window fetches the next site page.
Docln.browse = function(kind, page)
    assert(kind == 'latest' and page == 2)
    return { items = { { title = 'Next', url = '/truyen/9' } }, has_more = false }
end
wifi = 0
grid.opts.on_next(); drain()
assert(wifi == 0 and grid.pages[#grid.pages].items[1].title == 'Next')

-- Top-bar search reuses the same grid.
Docln.search = function(query, page)
    assert(query == 'query' and page == 1)
    return { items = { { title = 'Book', url = '/truyen/1' } }, has_more = true }
end
grid.opts.on_search(); assert(prompt)
prompt.on_submit('query'); drain()
assert(grid.pages[#grid.pages].title:find('query', 1, true))

Docln.getSeries = function(ref) assert(ref.url == '/truyen/1'); return series end
grid.opts.on_select({ title = 'Book', url = '/truyen/1' }); drain()
assert(shown.left_icon == 'appbar.menu' and type(shown.on_left_icon) == 'function')
assert(shown.items[1].text == 'Chương đã tải (offline)')
assert(shown.items[2].text == 'Tập')
local offline_item = shown.items[1]
local chapter_item = shown.items[2].sub_item_table[2]
local open_downloads = shown.on_left_icon
local first, last
Download.range = function(_, a, b)
    first, last = a, b
    return { saved = { { title = 'Two', path = '/local/ch-2.html' } }, skipped = {} }
end
Download.savedList = function()
    return { { title = 'Saved', path = '/offline/ch.html', number = 1 } }
end
offline_item.callback()
assert(shown.title == 'Chương đã tải (offline)' and shown.items[1].text == 'Saved')
shown.items[1].callback(); drain(); assert(opened == '/offline/ch.html')
Download.savedList = function() return {} end
offline_item.callback(); assert(notice == 'Chưa có chương đã tải.')
grid.opts.on_select({ title = 'Book', url = '/truyen/1' }); drain()
open_downloads = shown.on_left_icon
chapter_item = shown.items[2].sub_item_table[2]
open_downloads()
assert(shown.title == 'Tải chương')
assert(shown.items[1].text == 'Tải khoảng chương' and shown.items[2].text == 'Tải toàn bộ chương')
local range_item, all_item = shown.items[1], shown.items[2]
all_item.callback(); assert(confirm, 'download-all requires confirmation')
confirm(); drain(); assert(first == 1 and last == 2)
grid.opts.on_select({ title = 'Book', url = '/truyen/1' }); drain()
open_downloads = shown.on_left_icon
chapter_item = shown.items[2].sub_item_table[2]
open_downloads()
range_item = shown.items[1]
range_item.callback(); prompt.on_submit('1'); prompt.on_submit('2'); drain()
assert(first == 1 and last == 2)
shown.items[1].callback(); drain(); assert(opened == '/local/ch-2.html')
chapter_item.callback(); drain(); assert(first == 2 and last == 2)
first = nil
SeriesUI.askRange(2, function(a) first = a end); prompt.on_submit('3'); assert(not first)
SeriesUI.askRange(2, function(a) first = a end); prompt.on_submit('1.5'); assert(not first)
SeriesUI.askRange(2, function(a) first = a end); prompt.on_submit('1'); prompt.on_submit('0'); assert(not first)
local before = wifi
Novels.download(series, 1, 51); assert(confirm and wifi == before, 'large download requires confirmation')
confirm(); drain(); assert(last == 51)
Docln.search = function() error('network failure') end
Novels.search('query', 1); drain(); assert(notice:find('network failure', 1, true))
Docln.search = function() return { items = {}, has_more = false } end
Novels.search('query', 1); drain(); assert(notice == 'Không tìm thấy truyện phù hợp.')
assert(cleared >= 1 and wifi == 0, 'online path clears progress without Wi-Fi prompts')

-- Returning from TOC must leave the grid session available for Catalog stack restore.
assert(grid ~= nil)

-- Close via X then re-open must create a fresh grid (stale _closed grid must not block setPage).
local closed_grid = grid
closed_grid._closed = true
-- Intentionally skip on_close: simulates UIManager:free wiping the callback before session clear.
Docln.browse = function(kind, page)
    assert(kind == 'latest' and page == 1)
    return { items = sevenItems(), has_more = true }
end
local reopen_count = 0
local old_show = package.loaded['booxbook.ui.cover-grid'].show
package.loaded['booxbook.ui.cover-grid'].show = function(opts)
    reopen_count = reopen_count + 1
    return old_show(opts)
end
Novels.openSource(); drain()
assert(reopen_count >= 1 and grid and grid ~= closed_grid and not grid._closed and #grid.opts.items == 7,
    're-open after X must show a new live grid')
package.loaded['booxbook.ui.cover-grid'].show = old_show

online = false
Docln.search = function() return { items = { { title = 'Off', url = '/truyen/2' } }, has_more = false } end
wifi = 0
Novels.search('offline', 1); drain()
assert(wifi == 1, 'offline DocLN search may prompt for Wi-Fi')
online = true
-- Shared cover grid UI boundary: no search icon without search, footer back is a safe close.
local grid_stub_names = {
    'ffi/blitbuffer', 'ui/widget/container/centercontainer', 'device', 'ui/font',
    'ui/widget/container/framecontainer', 'ui/geometry', 'ui/gesturerange',
    'ui/widget/horizontalgroup', 'ui/widget/horizontalspan', 'ui/widget/container/inputcontainer',
    'ui/size', 'ui/widget/textboxwidget', 'ui/widget/titlebar', 'ui/uimanager',
    'ui/widget/verticalgroup', 'ui/widget/verticalspan', 'booxbook.ui.catalog',
    'booxbook.covers', 'booxbook.store.settings', 'booxbook.ui.cover-grid',
    'booxbook.ui.paged-screen', 'ui/widget/container/bottomcontainer', 'ui/widget/overlapgroup', 'ui/widget/container/widgetcontainer',
}
local grid_saved = {}
for _, name in ipairs(grid_stub_names) do
    grid_saved[name] = package.loaded[name]
end
package.loaded['booxbook.ui.cover-grid'] = nil
package.loaded['booxbook.ui.paged-screen'] = nil
package.loaded['ffi/blitbuffer'] = { COLOR_WHITE = 0, COLOR_BLACK = 1, COLOR_DARK_GRAY = 2 }
local function passthroughNew(_, value)
    value = value or {}
    value.dimen = value.dimen or { intersectWith = function() return false end }
    function value:free()
        if self._freed then return end
        self._freed = true
        for _, child in ipairs(self) do
            if type(child) == 'table' and child.free then child:free() end
        end
    end
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
package.loaded['ui/widget/container/widgetcontainer'] = { new = passthroughNew }
package.loaded['device'] = {
    screen = { getWidth = function() return 600 end, getHeight = function() return 800 end,
        scaleBySize = function(_, value) return value end },
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
package.loaded['ui/size'] = { padding = { small = 2, large = 4 }, border = { thin = 1 }, item = { height_default = 20 } }
local titlebars = {}
package.loaded['ui/widget/titlebar'] = { new = function(_, value)
    value.getHeight = function() return 30 end
    value.free = function(self)
        if self._tb_freed then error('TitleBar double-free') end
        self._tb_freed = true
    end
    titlebars[#titlebars + 1] = value
    return value
end }
package.loaded['ui/uimanager'] = { nextTick = function() end, setDirty = function() end }
local pushed, popped, closed = 0, 0, 0
package.loaded['booxbook.ui.catalog'] = {
    push = function() pushed = pushed + 1 end,
    pop = function() popped = popped + 1 end,
}
package.loaded['booxbook.covers'] = { find = function() return nil end, fetch = function() return nil end }
package.loaded['booxbook.store.settings'] = { includeImages = function() return false end }
local CoverGridReal = dofile('booxbook.koplugin/booxbook/ui/cover-grid.lua')
local grid_no_search = CoverGridReal.show{ title = 'Tin', items = {}, covers_enabled = false,
    on_close = function() closed = closed + 1 end }
assert(pushed == 1 and titlebars[1].left_icon == nil, 'cover grid hides search icon without search callback')
assert(grid_no_search.nav_dimens[1].action == 'back' and grid_no_search.nav_dimens[2].action == 'prev'
    and grid_no_search.nav_dimens[4].action == 'next', 'cover grid footer keeps back separate from page controls')
grid_no_search.nav_dimens[1].widget.dimen.hit = true
grid_no_search:onTap(nil, { pos = { intersectWith = function(_, dimen) return dimen and dimen.hit end } })
grid_no_search:onClose()
assert(closed == 1 and popped == 1, 'footer back and repeated close share one safe close path')
local searched = CoverGridReal.show{ title = 'DocLN', items = {}, covers_enabled = false, on_search = function() end }
assert(titlebars[#titlebars].left_icon == 'appbar.search', 'cover grid shows search icon when supplied')
titlebars[#titlebars].close_callback()
searched:onClose()
assert(popped == 2, 'titlebar X and repeated close share one safe close path')
local x_closed = 0
local x_grid = CoverGridReal.show{ title = 'X', items = {}, covers_enabled = false,
    on_search = function() end,
    on_close = function() x_closed = x_closed + 1 end }
local x_popped = popped
local x_tap = { pos = {
    x = 595, y = 5,
    intersectWith = function() return false end,
} }
assert(x_grid:onTap(nil, x_tap) == true)
assert(x_closed == 1 and popped == x_popped + 1,
    'titlebar X tap must close the grid without leaking to the parent catalog')
assert(x_grid:onTap(nil, x_tap) == true)
assert(x_closed == 1, 'repeated titlebar X after close is ignored')
-- Search/setPage rebuilds the page tree but reuses TitleBar. Freeing the old
-- root must not free TitleBar: a later X would native-crash on double-free.
local search_grid = CoverGridReal.show{
    title = 'DocLN',
    items = { { title = 'One', url = '/truyen/1' } },
    covers_enabled = false,
    on_search = function() end,
}
local search_tb = search_grid.title_bar
search_grid:setPage({
    title = 'DocLN — query',
    items = { { title = 'Hit', url = '/truyen/2' } },
})
assert(search_grid.title_bar == search_tb, 'search keeps the same TitleBar')
assert(not search_tb._tb_freed, 'rebuild after search must not free reused TitleBar')
search_tb.close_callback()
assert(search_grid._closed)
if search_grid[1] and search_grid[1].free then search_grid[1]:free() end
assert(search_tb._tb_freed, 'UIManager close may free TitleBar once')

-- Even gutters: leftover pixels are split across cells; sum matches the body.
local sizes = CoverGridReal._cellSizes(101, 2, 5)
assert(sizes[1] + sizes[2] + 5 == 101 and sizes[1] == 48 and sizes[2] == 48)
sizes = CoverGridReal._cellSizes(100, 2, 5)
assert(sizes[1] + sizes[2] + 5 == 100 and math.abs(sizes[1] - sizes[2]) <= 1)
sizes = CoverGridReal._cellSizes(200, 3, 4)
local sum = sizes[1] + sizes[2] + sizes[3] + 4 * 2
assert(sum == 200, 'row/column sizes fill the body without ragged remainder')

for _, name in ipairs(grid_stub_names) do package.loaded[name] = grid_saved[name] end


-- Catalog.pop must be re-entrant-safe (TitleBar X + UIManager close).
local catalog_saved = {}
local catalog_stub_names = {
    'ui/widget/confirmbox', 'ui/widget/inputdialog', 'device', 'ui/uimanager', 'gettext',
}
for _, name in ipairs(catalog_stub_names) do
    catalog_saved[name] = package.loaded[name]
end
package.loaded['ui/widget/confirmbox'] = {}
package.loaded['ui/widget/inputdialog'] = {}
package.loaded['device'] = { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end } }
package.loaded['gettext'] = function(value) return value end
local shows, closes = 0, 0
local parent = { name = 'parent' }
local child = { name = 'child' }
local fake
package.loaded['ui/uimanager'] = {
    show = function(_, w) if w == parent then shows = shows + 1 end end,
    close = function(_, w)
        if w == child or w == fake then
            closes = closes + 1
            -- Simulate free wiping callbacks before onClose resumes (old bug).
            if w == fake then w.on_close = nil end
        end
    end,
}
package.loaded['booxbook.ui.catalog'] = nil
local CatalogReal = dofile('booxbook.koplugin/booxbook/ui/catalog.lua')
-- Closing a covered parent releases TextBoxWidget buffers in real KOReader.
-- Exercise stack navigation with a resource that cannot be painted after close.
local manager = package.loaded['ui/uimanager']
local old_manager_show, old_manager_close = manager.show, manager.close
local windows = {}
manager.show = function(_, widget)
    assert(widget.buffer, 'cannot paint a closed parent: text buffer was freed')
    windows[#windows + 1] = widget
end
manager.close = function(_, widget)
    widget.buffer = nil
    for i = #windows, 1, -1 do
        if windows[i] == widget then table.remove(windows, i) end
    end
end
CatalogReal._stack = {}
local menu_parent = { buffer = true }
local browse_grid = { buffer = true }
local toc = { buffer = true }
CatalogReal.push(menu_parent)
CatalogReal.push(browse_grid)
CatalogReal.push(toc)
CatalogReal.pop(toc)
assert(windows[#windows] == browse_grid and browse_grid.buffer,
    'return from TOC preserves the live grid')
CatalogReal.pop(browse_grid)
assert(#windows == 1 and windows[1] == menu_parent and menu_parent.buffer,
    'closing browse grid reveals one live parent')
local search_grid = { buffer = true }
CatalogReal.push(search_grid)
CatalogReal.pop(search_grid)
assert(#windows == 1 and windows[1] == menu_parent and menu_parent.buffer,
    'closing search grid after reopening preserves the parent')
CatalogReal.clearStack()
assert(#windows == 0 and not menu_parent.buffer, 'clearStack closes all retained parents')
manager.show, manager.close = old_manager_show, old_manager_close
CatalogReal._stack = { parent, child }
CatalogReal.pop(child)
assert(closes == 1 and shows == 0 and #CatalogReal._stack == 1)
CatalogReal.pop(child)
assert(closes == 1 and shows == 0, 'second pop of same widget is ignored')

for _, name in ipairs(catalog_stub_names) do package.loaded[name] = catalog_saved[name] end

Docln.search, Docln.getSeries, Docln.browse, Download.range, Download.savedList = old[1], old[2], old[3], old[4], old[5]
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
package.loaded['booxbook.ui.novels'] = nil
package.loaded['booxbook.ui.catalog'] = nil
print('DocLN browse grid, search, range validation, confirmation, reader and error recovery checks passed')
