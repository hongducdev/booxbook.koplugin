local names = { "gettext", "booxbook.ui.catalog", "booxbook.comic-download", "booxbook.network",
    "ui/trapper", "ui/uimanager", "ui/widget/infomessage", "apps/reader/readerui",
    "booxbook.ui.cover-grid", "booxbook.ui.series" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
local prompt, notice, opened, cleared, scheduled, fail, downloads, menu, grid, series_opts
downloads = 0
package.loaded.gettext = function(s) return s end
package.loaded["booxbook.ui.catalog"] = {
    show = function(opts) menu = opts end, confirm = function(text, fn) fn() end,
    promptText = function(opts) prompt = opts end, clearStack = function() cleared = true end }
package.loaded["booxbook.network"] = { whenOnline = function(fn) fn() end }
package.loaded["ui/uimanager"] = { nextTick = function(self, fn) scheduled = fn end,
    show = function(self, opts) notice = opts.text end }
package.loaded["ui/widget/infomessage"] = { new = function(self, opts) return opts end }
package.loaded["ui/trapper"] = { wrap = function(self, fn) fn() end,
    info = function() return true end, clear = function() end }
package.loaded["apps/reader/readerui"] = { showReader = function(self, path) assert(cleared); opened = path end }
package.loaded["booxbook.comic-download"] = { savedPath = function() end,
    path = function(chapter) return "/" .. chapter.url .. ".cbz" end,
    chapter = function(url, progress)
    downloads = downloads + 1; assert(progress(1, 2, false))
    if fail then error("download failed") end
    return "/book.cbz"
end }
package.loaded["booxbook.ui.cover-grid"] = { PAGE_SIZE = 6, show = function(opts)
    grid = opts
    grid.setPage = function(self, payload) for k, v in pairs(payload) do self[k] = v end end
    return grid
end }
package.loaded["booxbook.ui.series"] = { show = function(series, opts) series_opts = opts end }
local UI = dofile("booxbook.koplugin/booxbook/ui/truyentuoitho.lua")
UI.openSource(); assert(#menu.items == 6); menu.on_search(); prompt.on_submit("https://evil.test/a")
assert(notice and downloads == 0)
prompt.on_submit("https://truyentuoitho.com/manga/test/tap-1/")
assert(downloads == 0 and not opened, "download deferred until dialog closed")
scheduled(); assert(downloads == 1 and not opened)
scheduled(); assert(opened == "/book.cbz")
fail = true
UI.download("https://truyentuoitho.com/manga/test/tap-1/"); scheduled()
assert(notice:find("download failed", 1, true))
fail = false
UI.download("https://truyentuoitho.com/manga/test/tap-1/"); scheduled()
assert(downloads == 3, "error releases busy guard")
local Source = require("booxbook.sources.truyentuoitho")
local old_browse, old_search, old_series = Source.browse, Source.search, Source.getSeries
local calls = 0
Source.browse = function(kind, page)
    calls = calls + 1
    local items = {}
    for i = 1, 9 do items[i] = { title = tostring(i) } end
    return { items = items, has_more = page == 1 }
end
UI.list("latest"); scheduled(); scheduled()
assert(grid.offset == 1 and calls == 1)
grid.on_next(); assert(grid.offset == 7 and calls == 1)
grid.on_next(); scheduled(); scheduled(); assert(grid.site_page == 2 and grid.offset == 1)
grid.on_prev(); scheduled(); scheduled(); assert(grid.site_page == 1 and grid.offset == 7)
Source.search = function(q, page) assert(q == "shin" and page == 1); return { items = {} } end
UI.promptSearch(); prompt.on_submit("shin"); scheduled(); scheduled()
assert(#grid.items == 0 and notice:find("Không tìm thấy", 1, true))
Source.getSeries = function(ref) return { id = "test", chapters = {
    { url = "book-1", title = "Tập 1", index = 1 },
    { url = "book-2", title = "Tập 2", index = 2 },
} } end
UI.showSeries("book"); scheduled(); scheduled()
assert(series_opts.on_chapter and series_opts.on_range and series_opts.on_download_all and series_opts.on_offline)
local old_open = io.open
io.open = function() return { close = function() end } end
series_opts.on_offline()
io.open = old_open
assert(#menu.items == 2, "offline list includes both downloaded books")
package.loaded["booxbook.comic-download"].savedPath = function(url) return "/" .. url .. ".cbz" end
menu.items[1].callback(); scheduled(); assert(opened == "/book-1.cbz")
menu.items[2].callback(); scheduled(); assert(opened == "/book-2.cbz", "offline callbacks keep their own book")
-- Confirm is captured, not auto-OK: list/toast must wait so they cannot cover the dialog.
local listed, confirm_text, confirm_ok, confirm_opts = 0
package.loaded["booxbook.ui.catalog"].show = function(opts)
    menu = opts
    listed = listed + 1
end
package.loaded["booxbook.ui.catalog"].confirm = function(text, fn, opts)
    confirm_text, confirm_ok, confirm_opts = text, fn, opts
end
notice, opened = nil, nil
package.loaded["booxbook.comic-download"].savedPath = function() end
package.loaded["booxbook.comic-download"].isCancelErr = function(err)
    return err == "booxbook:cancelled"
end
package.loaded["booxbook.comic-download"].chapter = function(url)
    return nil, "booxbook:cancelled", { cancelled = true, downloaded = 2, total = 10, url = url }
end
package.loaded["booxbook.comic-download"].packageStaging = function()
    return "/partial.cbz"
end
UI.download("https://truyentuoitho.com/manga/test/tap-1/")
scheduled(); scheduled()
assert(confirm_text and confirm_text:find("2/10", 1, true), "cancel shows pack confirm")
assert(listed == 0 and not notice and not opened, "confirm is not covered by list or toast")
assert(confirm_opts and confirm_opts.cancel_callback)
confirm_ok()
scheduled()
assert(opened == "/partial.cbz" and notice:find("2", 1, true), "pack confirm publishes CBZ")
package.loaded["booxbook.ui.catalog"].show = function(opts) menu = opts end
package.loaded["booxbook.ui.catalog"].confirm = function(text, fn) fn() end
package.loaded["booxbook.comic-download"].chapter = function(url, progress)
    downloads = downloads + 1; assert(progress(1, 2, false))
    if fail then error("download failed") end
    return "/book.cbz"
end
local network_calls = 0
package.loaded["booxbook.network"].whenOnline = function() network_calls = network_calls + 1 end
package.loaded["booxbook.comic-download"].savedPath = function() return "/offline.cbz" end
UI.download("book"); scheduled()
assert(opened == "/offline.cbz" and network_calls == 0, "saved comic opens without Wi-Fi")
Source.browse, Source.search, Source.getSeries = old_browse, old_search, old_series
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Comic UI: search/URL, grid paging, series actions, offline open and error recovery passed")
