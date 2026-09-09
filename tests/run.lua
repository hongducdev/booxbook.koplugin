local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

package.preload["socket"] = function()
    return {
        gettime = function()
            return os.time()
        end,
        sleep = function() end,
        skip = function(count, ...)
            return select(count + 1, ...)
        end,
    }
end

package.preload["socket.http"] = function()
    return {
        request = function()
            return 1, 200, { ["set-cookie"] = "sid=abc; Path=/" }, "OK"
        end,
    }
end

package.preload["ltn12"] = function()
    return {
        sink = {
            table = function(t)
                return function(chunk)
                    if chunk then
                        t[#t + 1] = chunk
                    end
                    return true
                end
            end,
        },
        source = {
            string = function(s)
                local sent = false
                return function()
                    if sent then
                        return nil
                    end
                    sent = true
                    return s
                end
            end,
        },
    }
end

local failures = 0

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n  expected: " .. tostring(expected) .. "\n  actual:   " .. tostring(actual) .. "\n")
    end
end

local function assert_true(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    end
end

local generic_module_names = {
    "epub",
    "html",
    "http",
    "rate_limit",
    "source",
    "sources.feeds",
    "sources.rss",
    "store.settings",
    "ui.catalog",
    "ui.news",
    "ui.series",
}
for _, name in ipairs(generic_module_names) do
    package.loaded[name] = { collision = name }
end

local Html = require("booxbook.html")
local Source = require("booxbook.source")
local RateLimit = require("booxbook.rate_limit")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Rss = require("booxbook.sources.rss")
assert_true(not Html.collision and not Http.collision and not Rss.collision, "internal modules ignore generic collisions")
assert_eq(require("html").collision, "html", "generic html name stays colliding")
assert_eq(require("ui.catalog").collision, "ui.catalog", "generic catalog name stays colliding")

-- sanitize: drop script, keep paragraphs, keep closing tags
local dirty = '<p>Hi</p><script>alert(1)</script><p onclick="x">Tiếng Việt</p><iframe src="x"></iframe>'
local clean = Html.sanitize(dirty)
assert_true(not clean:find("script", 1, true), "script removed")
assert_true(not clean:find("iframe", 1, true), "iframe removed")
assert_true(clean:find("</p>", 1, true), "closing p kept")
assert_true(clean:find("Tiếng Việt", 1, true), "utf8 kept")
assert_true(not clean:find("onclick", 1, true), "onclick removed")

-- select #id .class tag
local sample = [[<div class="wrap"><h1 id="title">Hello</h1><div class="chapter-content"><p>One</p></div></div>]]
assert_eq(Html.select(sample, "#title"), "Hello", "select #id")
assert_true((Html.select(sample, ".chapter-content") or ""):find("<p>One</p>", 1, true), "select .class")
assert_eq(Html.select(sample, "h1"), "Hello", "select tag")
assert_eq(Html.select([[<div id="chapter-content">Body</div>]], "#chapter-content"), "Body", "select hyphen id")
assert_eq(Http.sameOrigin("https://a.com/x", "https://a.com/y"), true, "same origin")
assert_eq(Http.sameOrigin("https://a.com/x", "https://b.com/x"), false, "cross origin")
assert_eq(Http.resolveUrl("https://a.com/dir/page", "/z"), "https://a.com/z", "resolve absolute path")

assert_eq(Html.escape("<a>"), "&lt;a&gt;", "escape")

local wrapped = Html.wrapDocument("T", "<p>x</p>")
assert_true(wrapped:find('charset="utf-8"', 1, true), "wrap charset")

assert_eq(Source.get("docln").kind, "novel", "DocLN adapter registered")
assert_eq(Source.get("docln").name, "DocLN", "source get")
assert_eq(#Source.list(), 8, "source list")
assert_eq(Source.get("truyentuoitho").kind, "comic", "TruyenTuoiTho registered")
assert_eq(Source.get("metruyencv").kind, "novel", "MeTruyenCV registered")
assert_eq(Source.get("truyenfull").kind, "novel", "TruyenFull registered")
assert_eq(Source.get("wattpad").kind, "novel", "Wattpad adapter registered")
assert_eq(Source.get("rss").kind, "news", "rss adapter registered")

local rss_items = Rss.parse([=[<?xml version="1.0"?><rss><channel><item><title><![CDATA[Tin Việt &amp; test]]></title><link>https://example.com/a</link><description><![CDATA[<p>Tóm tắt</p>]]></description><pubDate>Thu, 03 Sep 2026</pubDate></item></channel></rss>]=])
assert_eq(#rss_items, 1, "parse rss item")
assert_eq(rss_items[1].title, "Tin Việt & test", "decode rss title")
assert_true(rss_items[1].summary:find("Tóm tắt", 1, true) ~= nil, "rss utf8 summary")

local atom_items = Rss.parse([[<feed><entry><title>H&#7879; Atom</title><link href="https://example.com/b"/><summary>Summary</summary><updated>2026-09-03</updated></entry></feed>]])
assert_eq(#atom_items, 1, "parse atom entry")
assert_eq(atom_items[1].link, "https://example.com/b", "parse atom link")
assert_eq(atom_items[1].title, "Hệ Atom", "decode unicode numeric entity")

local fallback = Rss.renderArticle({
    title = "Fallback",
    link = "https://example.com",
    summary = "<p>Readable</p>",
    date = "Today",
}, nil, {})
assert_true(fallback:find("Readable", 1, true) ~= nil, "summary fallback")
assert_true(fallback:find("<h1>Fallback</h1>", 1, true) ~= nil, "visible article title")
local full_article = Rss.renderArticle({
    title = "Full",
    link = "https://example.com",
    summary = "<p>Fallback</p>",
    date = "Today",
}, "<html><body><article><p>Full text</p></article></body></html>", {})
assert_true(full_article:find("Full text", 1, true) ~= nil, "full article without custom filter")

local feed_items = {}
for index = 1, 21 do
    feed_items[index] = "<item><title>Item " .. index .. "</title><link>https://example.com/" .. index
        .. "</link><description><p>Summary " .. index .. "</p></description></item>"
end
local original_get = Http.get
local original_dir = Settings.downloadDir
local original_ensure_dir = Settings.ensureDir
local original_write = Html.writeFile
local original_open = io.open
local request_count = 0
local writes = {}
Http.get = function()
    request_count = request_count + 1
    if request_count == 1 then
        return true, 200, "<rss><channel>" .. table.concat(feed_items) .. "</channel></rss>"
    end
    return false, 500
end
Settings.downloadDir = function() return "." end
Settings.ensureDir = function() return true end
Html.writeFile = function(path, body)
    writes[#writes + 1] = { path = path, body = body }
    return true
end
io.open = function() return nil end
local fetch_ok, fetched = pcall(Rss.list, {
    id = "test",
    url = "https://example.com/feed.xml",
    full_article = true,
}, 50)
Http.get = original_get
Settings.downloadDir = original_dir
Settings.ensureDir = original_ensure_dir
Html.writeFile = original_write
io.open = original_open
assert_true(fetch_ok, "fetch pipeline does not throw")
assert_eq(#(fetched or {}), 20, "fetch limit capped at 20")
assert_eq(request_count, 1, "list requests only feed XML")
assert_eq(#writes, 0, "list writes no article files")

assert_eq(RateLimit.hostFromUrl("https://docln.net/truyen/1"), "docln.net", "host parse")
RateLimit.reset()
RateLimit.wait("example", 0)

local parsed = Http.parseSetCookie("sid=abc; Path=/; HttpOnly")
assert_eq(parsed.sid, "abc", "parse set-cookie")
assert_eq(Http.cookieHeader({ b = "2", a = "1" }), "a=1; b=2", "cookie header sorted")

Settings.bind(nil)
Settings.load()
assert_eq(Settings.sangtacvietEnabled(), false, "stv default off")
assert_eq(Settings.includeImages(), true, "images default on")
assert_eq(Settings.get("novel_epub"), false, "EPUB defaults off")
assert_eq(Settings.get("novel_keep_html"), true, "HTML retention defaults on")
assert_eq(Settings.get("news_delete_finished"), false, "news cleanup defaults off")
Settings.set("custom_rss_feeds", { "https://example.com/feed.xml" })
assert_eq(Settings.get("custom_rss_feeds")[1], "https://example.com/feed.xml", "custom rss round trip")
Settings.setCookie("wattpad", "secret")
assert_eq(Settings.cookie("wattpad"), "secret", "cookie store")
Settings.setCookie("wattpad", "")
assert_eq(Settings.cookie("wattpad"), "", "cookie clear")

local menu_events = {}
local shown_menu
local scheduled
local module_names = {
    "dispatcher",
    "ui/widget/infomessage",
    "ui/network/manager",
    "ui/uimanager",
    "ui/widget/container/widgetcontainer",
    "gettext",
    "booxbook.ui.catalog",
    "booxbook.epub",
    "booxbook.html",
    "booxbook.http",
    "booxbook.store.settings",
    "booxbook.ui.news",
    "booxbook.ui.novels",
    "ffi/util",
}
local saved_modules = {}
for _, name in ipairs(module_names) do
    saved_modules[name] = package.loaded[name]
end
package.loaded["dispatcher"] = { registerAction = function() end }
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/network/manager"] = {}
package.loaded["ui/uimanager"] = {
    nextTick = function(_, callback)
        menu_events[#menu_events + 1] = "nextTick"
        scheduled = callback
    end,
}
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(_, value) return value end,
}
package.loaded["gettext"] = function(value) return value end
package.loaded["booxbook.network"] = {
    whenOnline = function(callback) callback() end,
    statusText = function() return "Đã kết nối mạng" end,
}
package.loaded["booxbook.ui.catalog"] = {
    clearStack = function()
        menu_events[#menu_events + 1] = "clear"
    end,
    show = function(options)
        shown_menu = options
        menu_events[#menu_events + 1] = "show"
    end,
}
package.loaded["booxbook.epub"] = {}
package.loaded["booxbook.html"] = {}
package.loaded["booxbook.http"] = {}
package.loaded["booxbook.store.settings"] = {}
package.loaded["booxbook.ui.news"] = { menu = function() return { { text = "Publisher" } } end }

package.loaded["booxbook.ui.novels"] = { openSource = function() end, promptSearch = function() end }
package.loaded["ffi/util"] = { realpath = function(path)
    return path:gsub("^/sdcard/", "/storage/emulated/0/")
end }

local BooxBook = dofile(plugin_root .. "/main.lua")
local menu_items = {}
BooxBook:addToMainMenu(menu_items)
assert_eq(menu_items.booxbook.sorting_hint, "tools", "plugin is top-level in Tools")
assert_eq(menu_items.booxbook.keep_menu_open, true, "plugin owns Tools menu lifecycle")
menu_items.booxbook.callback({
    closeMenu = function()
        menu_events[#menu_events + 1] = "close"
    end,
})
assert_eq(table.concat(menu_events, ","), "close,nextTick", "Tools closes before fullscreen work")
assert_true(type(scheduled) == "function", "fullscreen work is deferred")
scheduled()
assert_eq(table.concat(menu_events, ","), "close,nextTick,clear,show", "fullscreen menu resets and opens in order")
assert_eq(shown_menu.subtitle, "Đã kết nối mạng", "home TitleBar shows network status")
assert_eq(#shown_menu.items, 5, "home actions fit comfortably on one page")
assert_eq(shown_menu.items[4].text, "Gửi sách qua Wi-Fi", "primary transfer action precedes settings")
assert_eq(shown_menu.items[5].text, "Cài đặt", "settings remain available last")
assert_eq(shown_menu.footer_slots[2].text, "v0.0.9", "home footer shows the plugin version")
assert_eq(shown_menu.footer_slots[3].action, "update", "home footer exposes one labeled update action")
assert_eq(shown_menu.footer_slots[4].text, "1/1", "home footer confirms all actions fit on one page")
assert_true(type(shown_menu.on_footer) == "function", "home footer actions are handled")
local library = shown_menu.items[3]
local old_fm = package.loaded["apps/filemanager/filemanager"]
local old_reader = package.loaded["apps/reader/readerui"]
local library_path, reader_closed
local fm = { showFiles = function(_, path) library_path = path end }
local reader = {}
package.loaded["apps/filemanager/filemanager"] = fm
package.loaded["apps/reader/readerui"] = reader
local menu_settings = package.loaded["booxbook.store.settings"]
menu_settings.downloadDir = function() return "/downloads" end
menu_settings.ensureDir = function() return true end
menu_settings.downloadDir = function() return "/storage/emulated/0/downloads" end
local comic_options, layout_events = {}, {}
local comic_config = {
    readSetting = function(self, key) return comic_options[key] end,
    saveSetting = function(self, key, value) comic_options[key] = value end,
}
BooxBook.ui = { document = { file = "/sdcard/downloads/comics/truyentuoitho/test/tap-1.cbz" }, paging = {},
    view = { onSetScrollMode = function(self, value) assert(value == false); layout_events[#layout_events + 1] = "paged" end },
    zooming = { setZoomMode = function(self, mode, quiet) assert(mode == "page" and quiet); layout_events[#layout_events + 1] = "fit" end } }
BooxBook:onReaderReady(comic_config)
assert_eq(table.concat(layout_events, ","), "paged,fit", "comics default to whole pages instead of continuous slices")
assert_eq(comic_options.kopt_page_scroll, 0, "paged mode persists per comic")
comic_options.zoom_mode = "pagewidth"
BooxBook:onReaderReady(comic_config)
assert_eq(#layout_events, 2, "later reader preferences preserved")
comic_options.booxbook_comic_page_layout = nil
BooxBook.ui.document.file = "/downloads/novels/book.epub"
BooxBook:onReaderReady(comic_config)
assert_eq(#layout_events, 2, "other documents unchanged")
BooxBook.ui = nil
menu_settings.downloadDir = function() return "/downloads" end
local retention_settings = { novel_epub = false, novel_keep_html = true, news_delete_finished = false }
menu_settings.get = function(key) return retention_settings[key] end
menu_settings.set = function(key, value) retention_settings[key] = value end
local settings_groups = BooxBook:settingsMenu()
assert_eq(#settings_groups, 4, "settings fit on one grouped page")
local setting_count, group_names = 0, {}
for _, group in ipairs(settings_groups) do
    group_names[#group_names + 1] = group.text
    setting_count = setting_count + #group.sub_item_table
    assert_true(#group.sub_item_table <= 5, "each settings group fits on one child page")
end
assert_eq(table.concat(group_names, ","), "Đọc và tải,Bộ nhớ,Nguồn và cookie,Hệ thống",
    "settings groups follow task order")
assert_eq(setting_count, 15, "grouping preserves every setting")
local toggle_count = 0
for _, group in ipairs(settings_groups) do
    for _, item in ipairs(group.sub_item_table) do
        if item.text == "Lưu truyện thành EPUB" or item.text == "Giữ bản HTML khi lưu EPUB"
            or item.text == "Tự xóa HTML báo sau khi đọc xong" then
            toggle_count = toggle_count + 1
            local before = item.checked_func()
            if item.select_enabled_func then
                assert_eq(item.select_enabled_func(), false, "retention requires EPUB")
                retention_settings.novel_epub = true
                assert_eq(item.select_enabled_func(), true, "retention available with EPUB")
            end
            item.callback()
            assert_eq(item.checked_func(), not before, "retention toggle changes setting")
            item.callback()
            assert_eq(item.checked_func(), before, "retention toggle restores setting")
        end
    end
end
assert_eq(toggle_count, 3, "all three retention settings are visible")
local old_cleanup = package.loaded["booxbook.news-cleanup"]
local closed_news
package.loaded["booxbook.news-cleanup"] = { afterClose = function(ui, finished_path)
    closed_news = { ui, finished_path }
end }
BooxBook.ui = { document = { file = "/downloads/news/feed/article.html" } }
BooxBook:onEndOfBook()
BooxBook:onCloseDocument()
assert_eq(closed_news[2], BooxBook.ui.document.file, "reader lifecycle passes finished article")
assert_eq(BooxBook.finished_news_path, nil, "finished state reset after close")
BooxBook.ui = nil
package.loaded["booxbook.news-cleanup"] = old_cleanup
library.callback()
assert_eq(library_path, nil, "library navigation deferred")
scheduled()
assert_eq(library_path, "/downloads", "library opens actual download folder")
fm.instance = { file_chooser = { changeToPath = function(_, path) library_path = path end } }
fm.showFiles = function() error("must reuse existing manager") end
library_path = nil
library.callback(); scheduled()
assert_eq(library_path, "/downloads", "existing file manager reused")
fm.instance = nil
fm.showFiles = function(_, path) assert(reader_closed); library_path = path end
reader.instance = { onClose = function() reader_closed = true end }
library.callback(); scheduled()
assert_true(reader_closed, "reader closed normally before library to save reading state")
package.loaded["apps/filemanager/filemanager"] = old_fm
package.loaded["apps/reader/readerui"] = old_reader
assert_eq(shown_menu.items[1].keep_menu_open, true, "news navigation keeps its parent menu")
shown_menu.items[1].callback()
assert_eq(shown_menu.title, "BooxBook", "news screen is deferred")
scheduled()
assert_eq(shown_menu.title, "Báo", "news screen opens after selection")

-- Truyện always lists Sangtacviet (first open still gated by ConfirmBox).
package.loaded["booxbook.store.settings"] = {
    sangtacvietEnabled = function() return false end,
    setSangtacvietEnabled = function() end,
    set = function() end,
}
BooxBook = dofile(plugin_root .. "/main.lua")
menu_items = {}
BooxBook:addToMainMenu(menu_items)
menu_items.booxbook.callback({ closeMenu = function() end })
scheduled()
local truyen
for _, item in ipairs(shown_menu.items) do
    if item.text == "Truyện" then truyen = item; break end
end
assert_true(truyen ~= nil, "Truyện menu entry exists")
truyen.callback()
scheduled()
assert_eq(shown_menu.title, "Truyện", "Truyện catalog opens")
assert_eq(#shown_menu.items, 7, "Truyện lists six novel sources and comic trial")
assert_eq(shown_menu.items[7].text, "Truyện Tuổi Thơ", "comic source discoverable")
assert_eq(shown_menu.items[6].text, "Truyện Full", "TruyenFull discoverable")
assert_eq(shown_menu.items[5].text, "TVTruyen", "TVTruyen discoverable")
assert_eq(shown_menu.items[4].text, "MeTruyenCV", "MeTruyenCV discoverable")
assert_eq(shown_menu.items[3].text, "Sangtacviet", "Sangtacviet is discoverable when disabled")

for _, name in ipairs(module_names) do
    package.loaded[name] = saved_modules[name]
end
package.loaded["booxbook.network"] = nil
package.loaded["booxbook.ui.news"] = nil
package.loaded["booxbook.ui.novels"] = nil
local catalog_module_names = {
    "ui/widget/confirmbox",
    "ui/widget/inputdialog",
    "ui/uimanager",
    "gettext",
}
local saved_catalog_modules = {}
for _, name in ipairs(catalog_module_names) do
    saved_catalog_modules[name] = package.loaded[name]
end
package.loaded["ui/widget/confirmbox"] = {}
package.loaded["ui/widget/inputdialog"] = {}
package.loaded["gettext"] = function(value) return value end
package.loaded["ui/uimanager"] = { show = function() end, close = function() end }
local Catalog = dofile(plugin_root .. "/booxbook/ui/catalog.lua")
package.loaded["booxbook.ui.catalog"] = Catalog
local parent = { name = "menu" }
Catalog.push(parent)
assert_eq(#Catalog._stack, 1, "push keeps the parent catalog")
local pushed = { name = "grid" }
Catalog.push(pushed)
assert_eq(#Catalog._stack, 2, "push stacks custom widgets with lists")
Catalog.pop(pushed)
assert_eq(Catalog._stack[1], parent, "pop restores parent after grid")
Catalog.clearStack()
assert_eq(#Catalog._stack, 0, "clearStack empties retained widgets")
for _, name in ipairs(catalog_module_names) do
    package.loaded[name] = saved_catalog_modules[name]
end
package.loaded["booxbook.ui.catalog"] = nil

dofile("tests/news-online.lua")
dofile("tests/news-categories.lua")
dofile("tests/news-images.lua")
dofile("tests/doh.lua")
dofile("tests/news-http.lua")
dofile("tests/docln.lua")
dofile("tests/wattpad.lua")
dofile("tests/metruyencv.lua")
dofile("tests/tvtruyen.lua")
dofile("tests/tvtruyen-ui.lua")
dofile("tests/truyenfull.lua")
dofile("tests/truyenfull-ui.lua")
dofile("tests/metruyencv-ui.lua")
dofile("tests/wattpad-ui.lua")
dofile("tests/sangtacviet.lua")
dofile("tests/sangtacviet-ui.lua")
dofile("tests/catalog-ui.lua")
dofile("tests/novel-offline.lua")
dofile("tests/epub.lua")
dofile("tests/news-cleanup.lua")
dofile("tests/docln-ui.lua")
dofile("tests/network.lua")
dofile("tests/update.lua")
dofile("tests/truyentuoitho.lua")
dofile("tests/comic-download.lua")
dofile("tests/storage-cache.lua")
dofile("tests/truyentuoitho-ui.lua")
dofile("tests/wifi-transfer.lua")

if failures > 0 then
    io.stderr:write(tostring(failures) .. " test(s) failed\n")
    os.exit(1)
end
print("All tests passed")
