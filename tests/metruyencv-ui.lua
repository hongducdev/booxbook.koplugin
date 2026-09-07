local names = { 'booxbook.ui.catalog', 'booxbook.ui.novels', 'booxbook.network',
    'ui/trapper', 'ui/uimanager', 'ui/widget/infomessage', 'gettext', 'booxbook.ui.cover-grid' }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
local W = require('booxbook.sources.metruyencv')
local browse, search = W.browse, W.search
local shown, prompt, selected, notice, page_seen, grid
local grid_count, requests = 0, 0
package.loaded['booxbook.ui.cover-grid'] = { PAGE_SIZE = 6, show = function(opts)
    grid_count = grid_count + 1
    grid = opts
    grid.setPage = function(self, data) for k, v in pairs(data) do self[k] = v end end
    return grid
end }
package.loaded.gettext = function(text) return text end
package.loaded['booxbook.ui.catalog'] = { show = function(opts) shown = opts end,
    promptText = function(opts) prompt = opts end }
package.loaded['booxbook.ui.novels'] = { showSeries = function(ref, adapter)
    assert(adapter == W); selected = ref
end }
package.loaded['booxbook.network'] = { whenOnline = function(fn) fn() end }
package.loaded['ui/trapper'] = { wrap = function(_, fn) fn() end, info = function() end, clear = function() end }
package.loaded['ui/uimanager'] = { nextTick = function(_, fn) fn() end,
    show = function(_, opts) notice = opts.text end }
package.loaded['ui/widget/infomessage'] = { new = function(_, opts) return opts end }
W.browse = function(kind, page)
    assert(kind == 'latest'); page_seen = page
    requests = requests + 1
    local items = {}
    for i = 1, 8 do items[i] = { title = 'Public', ref = tostring(i), cover = 'https://img.metruyencv.com/cover.jpg' } end
    return { items = items, has_more = page == 1 }
end
W.search = function(query) assert(query == 'test'); return nil, 'API changed' end
local UI = dofile('booxbook.koplugin/booxbook/ui/metruyencv.lua')
UI.openSource(); assert(#shown.items == 2 and shown.on_search == UI.promptSearch)
shown.items[1].callback(); assert(page_seen == 1)
assert(grid.on_search == UI.promptSearch, 'result grid keeps title-bar search')
assert(grid.source_id == 'metruyencv' and grid.items[1].cover and not grid.cover_cookies)
grid.on_select(grid.items[1]); assert(selected.ref == '1')
grid.on_next(); assert(grid.offset == 7 and requests == 1)
grid.on_next(); assert(page_seen == 2 and grid.offset == 1 and grid_count == 1)
grid.on_prev(); assert(page_seen == 1 and grid.offset == 7 and grid_count == 1)
grid.on_prev(); assert(grid.offset == 1)
UI.openSource(); shown.on_search(); prompt.on_submit(' test '); assert(notice == 'API changed')
UI.openSource(); shown.on_search(); prompt.on_submit(' https://metruyencv.com/truyen/1 ')
assert(selected == 'https://metruyencv.com/truyen/1')
prompt.on_submit('  '); assert(selected == 'https://metruyencv.com/truyen/1')
prompt.on_submit('/truyen/2'); assert(selected == '/truyen/2')
prompt.on_submit('3'); assert(selected == '3')
UI.list('latest'); assert(page_seen == 1, 'error must release busy guard')
W.search = function(query) assert(query == 'test'); return { items = {}, has_more = true } end
UI.list(nil, 'test'); assert(#grid.items == 0 and grid.has_more and grid.on_search)
local previous_grid = grid
grid._closed = true
grid.on_next(); assert(grid == previous_grid, 'closed grid ignores paging')
W.browse, W.search = browse, search
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print('MeTruyenCV menu, pagination, URL fallback and error recovery checks passed')
