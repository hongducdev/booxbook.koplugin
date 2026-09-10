local Library = require("booxbook.library")

assert(Library.matchQuery("One Piece CBZ", "") == true, "empty query matches all")
assert(Library.matchQuery("One Piece", "one") == true, "query is case-insensitive")
assert(Library.matchQuery("Naruto", "one") == false, "non-matching query rejected")

local items = { { name = "One Piece 1.cbz" }, { name = "Naruto 1.cbz" } }
assert(#Library.filter(items, "one") == 1, "filter keeps one match")
assert(#Library.filter(items, "") == 2, "empty filter keeps all")

local summary = Library.summarize({ { size = 100 }, { size = 200 } })
assert(summary.count == 2 and summary.bytes == 300, "summarize counts files and bytes")
assert(Library.formatBytes(512) == "512 B", "bytes format")
assert(Library.formatBytes(2048) == "2 KB", "kilobytes format")

local files = { { name = "a", mtime = 1 }, { name = "b", mtime = 3 }, { name = "c", mtime = 2 } }
local recent = Library.recent(files, 2)
assert(#recent == 2 and recent[1].name == "b" and recent[2].name == "c", "recent sorts by mtime")

local function listFn(dir)
    assert(dir == "/lib", "scan uses given dir")
    return { "a.epub", ".", ".." }
end
local function statFn(path) return { mode = "file", size = 10, mtime = 5 } end
local scanned = Library.scanFlat("/lib", listFn, statFn)
assert(#scanned == 1 and scanned[1].name == "a.epub", "scanFlat skips dot entries")

-- Accent folding and smart search
assert(Library.fold("Đấu La Đại Lục") == "dau la dai luc", "fold handles uppercase and lowercase Vietnamese accents")
assert(Library.matchQuery("Đấu La Đại Lục - Chương 1", "dau la") == true, "unaccented query matches accented title")
assert(Library.matchQuery("Đấu La Đại Lục - Chương 1", "Chương 1") == true, "accented query matches accented title")
assert(Library.matchQuery("Doraemon", "dora") == true, "substring query matches")
assert(Library.matchQuery("Doraemon", "naruto") == false, "unrelated query does not match")

-- Extended filter matching by title, name, series, or path
local multi_items = {
    { name = "01.cbz", title = "Doraemon - 01.cbz", series = "Doraemon", path = "/comics/doraemon/01.cbz" },
    { name = "chap-1.html", title = "Đấu La Đại Lục - chap-1.html", series = "Đấu La Đại Lục", path = "/novels/123/chap-1.html" },
    { name = "received.epub", title = "received.epub", path = "/received/received.epub" },
}
assert(#Library.filter(multi_items, "doraemon") == 1, "filter matches series title")
assert(#Library.filter(multi_items, "dau la") == 1, "filter matches novel series with folded accents")
assert(#Library.filter(multi_items, "01.cbz") == 1, "filter matches filename")
assert(#Library.filter(multi_items, "") == 3, "empty query keeps all")

-- Book file extension check
assert(Library.isBookFile("book.epub") == true, "lowercase epub is book")
assert(Library.isBookFile("comic.CBZ") == true, "uppercase CBZ is book")
assert(Library.isBookFile("document.PDF") == true, "uppercase PDF is book")
assert(Library.isBookFile(".hidden.epub") == false, "hidden file rejected")
assert(Library.isBookFile("download.part") == false, "part file rejected")
assert(Library.isBookFile("_selftest.html") == false, "selftest file rejected")
assert(Library.isBookFile("cover.jpg") == false, "jpg is not book")
assert(Library.isBookFile("index.json") == false, "json is not book")

-- Mock tree for Library.collect testing depth 4/5 traversal and manifest/index title resolution
local mock_tree = {
    ["/root"] = { "novels", "comics", "received", "covers", "_update" },
    ["/root/covers"] = { "cover1.jpg" },
    ["/root/received"] = { "sach-hay.epub" },
    ["/root/novels"] = { "docln" },
    ["/root/novels/docln"] = { "123" },
    ["/root/novels/docln/123"] = { "index.json", "chap-1.html", "truyen.epub" },
    ["/root/comics"] = { "truyentuoitho" },
    ["/root/comics/truyentuoitho"] = { "doraemon" },
    ["/root/comics/truyentuoitho/doraemon"] = { "manifest.json", "tap-1.cbz" },
}
local function mockList(dir) return mock_tree[dir] or {} end
local function mockStat(path, req)
    if mock_tree[path] then
        return { mode = "directory", size = 0, modification = 100 }
    else
        return { mode = "file", size = 1024, modification = 200 }
    end
end
local function mockJson(path)
    if path == "/root/novels/docln/123/index.json" then
        return { title = "Đấu La Đại Lục" }
    elseif path == "/root/comics/truyentuoitho/doraemon/manifest.json" then
        return { title = "Doraemon" }
    end
    return nil
end

local collected = Library.collect("/root", { listFn = mockList, statFn = mockStat, readJson = mockJson, max_depth = 5 })
assert(#collected == 4, "collected 4 books across depth 2, 4, 5 and ignored covers/update: got " .. #collected)
local found_comic, found_novel_html, found_novel_epub, found_received = false, false, false, false
for _, book in ipairs(collected) do
    if book.name == "tap-1.cbz" then
        assert(book.series == "Doraemon", "comic series resolved from manifest.json")
        assert(book.title == "Doraemon - tap-1.cbz", "comic title formatted with series")
        assert(book.category == "comics", "comic category is comics")
        found_comic = true
    elseif book.name == "chap-1.html" then
        assert(book.series == "Đấu La Đại Lục", "novel series resolved from index.json")
        assert(book.title == "Đấu La Đại Lục - chap-1.html", "novel title formatted with series")
        assert(book.category == "novels", "novel category is novels")
        found_novel_html = true
    elseif book.name == "truyen.epub" then
        assert(book.category == "novels", "novel epub category is novels")
        found_novel_epub = true
    elseif book.name == "sach-hay.epub" then
        assert(book.category == "received", "received category is received")
        assert(book.title == "sach-hay.epub", "received title is filename")
        found_received = true
    end
end
assert(found_comic and found_novel_html and found_novel_epub and found_received, "all expected book types found")

-- UI tests for booxbook.ui.library
local last_shown, last_prompt
local Catalog = {
    show = function(opts) last_shown = opts end,
    promptText = function(opts) last_prompt = opts end,
    clearStack = function() end,
}
local old_catalog = package.loaded["booxbook.ui.catalog"]
local old_settings = package.loaded["booxbook.store.settings"]
local old_uimanager = package.loaded["ui/uimanager"]
local old_readerui = package.loaded["apps/reader/readerui"]

package.loaded["booxbook.ui.catalog"] = Catalog
package.loaded["ui/widget/infomessage"] = package.loaded["ui/widget/infomessage"] or { new = function(_, value) return value end }
package.loaded["ui/uimanager"] = {
    nextTick = function(_, cb) cb() end,
    show = function() end,
}
package.loaded["booxbook.store.settings"] = {
    downloadDir = function() return "/root" end,
    ensureDir = function() return true end,
    get = function() return nil end,
    set = function() end,
}
local reader_path
package.loaded["apps/reader/readerui"] = { showReader = function(_, path) reader_path = path end }
package.loaded["booxbook.ui.library"] = nil

local old_collect = Library.collect
Library.collect = function() return collected end

local LibraryUI = require("booxbook.ui.library")

-- 1. Open without query -> shows categories
LibraryUI.open()
assert(last_shown ~= nil, "UI.open shows screen")
assert(last_shown.title == "Thư mục trên máy", "Title is Thư mục trên máy")
assert(type(last_shown.on_search) == "function", "Search icon handler registered on titlebar")
local found_search_btn, found_novels_cat, found_comics_cat, found_received_cat, found_fm_cat = false, false, false, false, false
for _, item in ipairs(last_shown.items) do
    if item.text:find("Tìm sách offline") then found_search_btn = true end
    if item.text:find("Truyện chữ") then found_novels_cat = true end
    if item.text:find("Truyện tranh") then found_comics_cat = true end
    if item.text:find("Sách đã nhận") then found_received_cat = true end
    if item.text:find("Trình quản lý file") then found_fm_cat = true end
end
assert(found_search_btn and found_novels_cat and found_comics_cat and found_received_cat and found_fm_cat, "all category rows displayed")

-- Test category screens directly
local test_novels = {
    { name = "c1.html", series = "Truyện A", category = "novels", size = 100, mtime = 1 },
    { name = "c2.html", series = "Truyện A", category = "novels", size = 100, mtime = 2 },
    { name = "standalone.epub", series = nil, category = "novels", size = 300, mtime = 3 },
}
LibraryUI.showNovels(test_novels)
assert(last_shown ~= nil and last_shown.title == "Truyện chữ đã tải", "showNovels sets title")
assert(#last_shown.items == 2, "2 series in novels including fallback Truyện khác")
assert(last_shown.items[1].text == "Truyện A", "series name matches")
assert(last_shown.items[1].mandatory:find("2"), "chapter count matches")
assert(last_shown.items[2].text == "Truyện khác", "series without title falls back to Truyện khác without shadowing gettext")
assert(last_shown.items[2].mandatory:find("1"), "standalone count matches")
local test_comics = {
    { name = "t1.cbz", series = "Comic B", category = "comics", size = 500, mtime = 1 },
}
LibraryUI.showComics(test_comics)
assert(last_shown ~= nil and last_shown.title == "Truyện tranh đã tải", "showComics sets title")
assert(#last_shown.items == 1, "1 series in comics")
assert(last_shown.items[1].text == "Comic B", "series name matches")
assert(last_shown.items[1].mandatory:find("1"), "volume count matches")

LibraryUI.showFileList("Test Files", test_comics)
assert(last_shown ~= nil and last_shown.title == "Test Files", "showFileList sets title")
assert(#last_shown.items == 1, "1 file in list")

-- 2. Open with query -> shows search results directly
LibraryUI.open("doraemon")
assert(last_shown.title == "Tìm sách offline", "Search title shown")
assert(#last_shown.items == 1, "only 1 search result for doraemon")
assert(last_shown.items[1].text:find("Doraemon"), "result text has Doraemon")

-- 3. Search prompt opens InputDialog
LibraryUI.searchPrompt("test")
assert(last_prompt ~= nil and last_prompt.title == "Tìm sách offline", "search prompt opens with title")
assert(last_prompt.input == "test", "search prompt preserves input")

-- 4. Open empty query -> all books
LibraryUI.showSearchResults("")
assert(last_shown.title == "Tất cả sách trên máy", "Empty search shows all books")
assert(#last_shown.items == 4, "all 4 books listed")

-- 5. Open book launches reader
LibraryUI.openBook("/root/comics/truyentuoitho/doraemon/tap-1.cbz")
assert(reader_path == "/root/comics/truyentuoitho/doraemon/tap-1.cbz", "openBook dispatches to ReaderUI")

-- Restore mocks
Library.collect = old_collect
package.loaded["booxbook.ui.catalog"] = old_catalog
package.loaded["booxbook.store.settings"] = old_settings
package.loaded["ui/uimanager"] = old_uimanager
package.loaded["apps/reader/readerui"] = old_readerui
package.loaded["booxbook.ui.library"] = nil
print("Library checks passed")
