local names = { 'booxbook.ui.catalog', 'booxbook.ui.novels', 'booxbook.network',
    'booxbook.store.settings', 'ui/trapper', 'ui/uimanager', 'ui/widget/infomessage',
    'gettext', 'booxbook.ui.cover-grid' }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
local S = require('booxbook.sources.sangtacviet')
local browse, search = S.browse, S.search
local shown, prompt, selected, notice, page_seen, grid
local grid_count, requests = 0, 0
package.loaded['booxbook.ui.cover-grid'] = { PAGE_SIZE = 6, show = function(opts)
    grid_count = grid_count + 1
    grid = opts
    grid.setPage = function(self, data) for k, v in pairs(data) do self[k] = v end end
    return grid
end }
package.loaded.gettext = function(text) return text end
package.loaded['booxbook.store.settings'] = {
    get = function(key)
        if key == 'stv_home' then return 'https://sangtacviet.com' end
        return nil
    end,
    sangtacvietEnabled = function() return true end,
}
package.loaded['booxbook.ui.catalog'] = { show = function(opts) shown = opts end,
    promptText = function(opts) prompt = opts end }
package.loaded['booxbook.ui.novels'] = { showSeries = function(ref, adapter)
    assert(adapter == S); selected = ref
end }
package.loaded['booxbook.network'] = { whenOnline = function(fn) fn() end }
package.loaded['ui/trapper'] = { wrap = function(_, fn) fn() end, info = function() end, clear = function() end }
package.loaded['ui/uimanager'] = { nextTick = function(_, fn) fn() end,
    show = function(_, opts) notice = opts.text end }
package.loaded['ui/widget/infomessage'] = { new = function(_, opts) return opts end }
S.browse = function(kind, page)
    assert(kind == 'update'); page_seen = page
    requests = requests + 1
    local items = {}
    for i = 1, 8 do items[i] = { title = 'Public', ref = 'fanqie-' .. i, cover = 'https://x/c.jpg' } end
    return { items = items, has_more = page == 1 }
end
S.search = function(query) assert(query == 'test'); return nil, 'API changed' end
local UI = dofile('booxbook.koplugin/booxbook/ui/sangtacviet.lua')
UI.openSource(); assert(#shown.items == 2 and shown.on_search == UI.promptSearch)
shown.items[1].callback(); assert(page_seen == 1)
assert(grid.on_search == UI.promptSearch, 'result grid keeps title-bar search')
assert(grid.source_id == 'sangtacviet' and grid.cover_delay_ms == 2000)
grid.on_select(grid.items[1]); assert(selected.ref == 'fanqie-1')
grid.on_next(); assert(grid.offset == 7 and requests == 1)
grid.on_next(); assert(page_seen == 2 and grid.offset == 1 and grid_count == 1)
grid.on_prev(); assert(page_seen == 1 and grid.offset == 7)
UI.openSource(); shown.on_search(); prompt.on_submit(' test '); assert(notice == 'API changed')
UI.openSource(); shown.on_search()
prompt.on_submit(' https://sangtacviet.com/truyen/fanqie/1/55/ ')
assert(selected == 'https://sangtacviet.com/truyen/fanqie/1/55/')
prompt.on_submit('/truyen/fanqie/1/66/'); assert(selected == '/truyen/fanqie/1/66/')
UI.list('update'); assert(page_seen == 1, 'error must release busy guard')
S.search = function(query) assert(query == 'test'); return { items = {}, has_more = true } end
UI.list(nil, 'test'); assert(#grid.items == 0 and grid.has_more and grid.on_search)
local previous_grid = grid
grid._closed = true
grid.on_next(); assert(grid == previous_grid, 'closed grid ignores paging')
S.browse, S.search = browse, search
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print('Sangtacviet menu, pagination, URL fallback and error recovery checks passed')
