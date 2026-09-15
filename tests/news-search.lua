-- News menu entry for offline full-text search over downloaded articles.
local names = { 'ui/widget/infomessage', 'apps/reader/readerui', 'ui/trapper', 'ui/uimanager',
    'gettext', 'booxbook.ui.library', 'booxbook.ui.catalog', 'booxbook.network' }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

local Settings = require('booxbook.store.settings')
local saved_dir = Settings.downloadDir
Settings.downloadDir = function() return '/dl' end

package.loaded.gettext = function(text) return text end
package.loaded['ui/widget/infomessage'] = { new = function(_, opts) return opts end }
package.loaded['apps/reader/readerui'] = {}
package.loaded['ui/trapper'] = { wrap = function(_, fn) fn() end, info = function() end, clear = function() end }
package.loaded['ui/uimanager'] = { nextTick = function(_, fn) fn() end, show = function() end }
local captured
package.loaded['booxbook.ui.catalog'] = {}
package.loaded['booxbook.network'] = { whenOnline = function(fn) fn() end }
package.loaded['booxbook.ui.library'] = { searchFullTextPrompt = function(...)
    captured = { ... }
end }

local News = dofile('booxbook.koplugin/booxbook/ui/news.lua')
local entry
for _, item in ipairs(News.menu()) do
    if item.text == 'Tìm trong tin đã tải' then entry = item end
end
assert(entry, 'news menu exposes offline search')
entry.callback()
assert(captured and captured[1] == nil and captured[2] == '/dl/news'
    and captured[3] == 'Tìm trong tin đã tải', 'search is scoped to downloaded news')

Settings.downloadDir = saved_dir
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print('News offline search menu checks passed')
