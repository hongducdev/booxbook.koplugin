-- Exercise real menu callbacks with KOReader widgets replaced at the UI boundary.
local names = { 'ui/widget/infomessage', 'ui/network/manager', 'apps/reader/readerui',
    'ui/trapper', 'ui/uimanager', 'gettext', 'booxbook.ui.catalog', 'booxbook.ui.series',
    'booxbook.ui.novel-grid' }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
local Docln = require('booxbook.sources.docln')
local Download = require('booxbook.novel-download')
local old = { Docln.search, Docln.getSeries, Docln.browse, Download.range }
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
package.loaded['booxbook.ui.novel-grid'] = {
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
assert(shown.items[1].text == 'Tải khoảng chương' and shown.items[2].text == 'Tập')
local range_item, chapter_item = shown.items[1], shown.items[2].sub_item_table[2]
local first, last
Download.range = function(_, a, b)
    first, last = a, b
    return { saved = { { title = 'Two', path = '/local/ch-2.html' } }, skipped = {} }
end
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
local old_show = package.loaded['booxbook.ui.novel-grid'].show
package.loaded['booxbook.ui.novel-grid'].show = function(opts)
    reopen_count = reopen_count + 1
    return old_show(opts)
end
Novels.openSource(); drain()
assert(reopen_count >= 1 and grid and grid ~= closed_grid and not grid._closed and #grid.opts.items == 7,
    're-open after X must show a new live grid')
package.loaded['booxbook.ui.novel-grid'].show = old_show

online = false
Docln.search = function() return { items = { { title = 'Off', url = '/truyen/2' } }, has_more = false } end
wifi = 0
Novels.search('offline', 1); drain()
assert(wifi == 1, 'offline DocLN search may prompt for Wi-Fi')
online = true

-- Catalog.pop must be re-entrant-safe (TitleBar X + UIManager close).
local catalog_saved = {}
for _, name in ipairs({
    'ui/widget/confirmbox', 'ui/widget/inputdialog', 'ui/widget/menu', 'device', 'ui/uimanager', 'gettext',
}) do
    catalog_saved[name] = package.loaded[name]
end
local BaseMenu = {}
function BaseMenu:extend(value) return setmetatable(value, { __index = self }) end
function BaseMenu:new(value) return setmetatable(value, { __index = self }) end
package.loaded['ui/widget/menu'] = BaseMenu
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
CatalogReal._stack = { parent, child }
CatalogReal.pop(child)
assert(closes == 1 and shows == 1 and #CatalogReal._stack == 1)
CatalogReal.pop(child)
assert(closes == 1 and shows == 1, 'second pop of same widget is ignored')

local cleared_session = 0
local function onClose(self)
    if self._closed then return true end
    self._closed = true
    self._cover_job = false
    self.dimen = nil
    local on_close = self.on_close
    self.on_close = nil
    if on_close then on_close() end
    CatalogReal.pop(self)
    return true
end
fake = { _closed = false, _cover_job = true, dimen = { w = 1 },
    on_close = function() cleared_session = cleared_session + 1 end }
CatalogReal._stack = { parent, fake }
assert(onClose(fake) == true and cleared_session == 1 and fake.dimen == nil and not fake._cover_job,
    'on_close must run before UIManager:close/free')
assert(onClose(fake) == true and cleared_session == 1, 'second close must be a no-op')
for name, value in pairs(catalog_saved) do package.loaded[name] = value end

Docln.search, Docln.getSeries, Docln.browse, Download.range = old[1], old[2], old[3], old[4]
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
package.loaded['booxbook.ui.novels'] = nil
package.loaded['booxbook.ui.catalog'] = nil
print('DocLN browse grid, search, range validation, confirmation, reader and error recovery checks passed')
