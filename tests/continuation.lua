-- Tests for comic continuation on EndOfBook event.
local stub_names = {
    "booxbook.ui.truyenqq",
    "booxbook.ui.novels",
    "apps/reader/readerui",
    "ui/widget/confirmbox",
    "ui/widget/inputdialog",
    "ui/uimanager",
    "ui/network/manager",
    "dispatcher",
    "ui/widget/container/widgetcontainer",
    "ffi/util",
    "ui/widget/infomessage",
    "ui/trapper",
    "json",
    "booxbook.continuation",
}
local saved_stubs = {}
for _, name in ipairs(stub_names) do
    saved_stubs[name] = package.loaded[name]
end

local downloaded_url = nil
package.loaded["booxbook.ui.truyenqq"] = {
    download = function(url)
        downloaded_url = url
    end,
}

local downloaded_novel_series, downloaded_novel_first, downloaded_novel_last
local downloaded_chapter_src, downloaded_chapter_series_id, downloaded_chapter_num, downloaded_chapter_url
package.loaded["booxbook.ui.novels"] = {
    download = function(series, first, last, confirmed, open_after)
        downloaded_novel_series = series
        downloaded_novel_first = first
        downloaded_novel_last = last
    end,
    downloadChapter = function(source_id, series_id, chapter_number, chapter_url)
        downloaded_chapter_src = source_id
        downloaded_chapter_series_id = series_id
        downloaded_chapter_num = chapter_number
        downloaded_chapter_url = chapter_url
    end,
}
local shown_reader_path = nil
package.loaded["apps/reader/readerui"] = {
    showReader = function(self, path)
        shown_reader_path = path
    end,
}

local top_widget = nil
local closed_widgets = {}
local UIManager = {
    show = function(self, w) top_widget = w end,
    close = function(self, w)
        closed_widgets[#closed_widgets + 1] = w
        if top_widget == w then top_widget = nil end
    end,
    getTopmostVisibleWidget = function(self) return top_widget end,
    nextTick = function(self, fn) fn() end,
}
package.loaded["ui/uimanager"] = UIManager

package.loaded["ui/widget/confirmbox"] = {
    new = function(self, opts)
        opts = opts or {}
        return { name = opts.name, text = opts.text, ok = opts.ok_callback, cancel = opts.cancel_callback }
    end
}
package.loaded["ui/widget/inputdialog"] = package.loaded["ui/widget/inputdialog"] or {}
package.loaded["ui/network/manager"] = package.loaded["ui/network/manager"] or {}
package.loaded["dispatcher"] = package.loaded["dispatcher"] or { registerAction = function() end }
package.loaded["ui/widget/container/widgetcontainer"] = package.loaded["ui/widget/container/widgetcontainer"] or { extend = function(self, t) return t end }
package.loaded["ffi/util"] = package.loaded["ffi/util"] or { realpath = function(p) return p end }
package.loaded["ui/widget/infomessage"] = package.loaded["ui/widget/infomessage"] or { new = function(_, t) return t end }
package.loaded["ui/trapper"] = package.loaded["ui/trapper"] or {
    info = function() end,
    clear = function() end,
    wrap = function(self, fn)
        local cb = type(self) == "function" and self or fn
        if cb then cb() end
    end,
}

-- Lossless JSON test double: stores deep-copies keyed by token string
local json_store = {}
local json_counter = 0

local function deepcopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = deepcopy(v)
    end
    return copy
end

package.loaded["json"] = {
    encode = function(val)
        if type(val) ~= "table" then return nil end
        json_counter = json_counter + 1
        local token = "__JSON_TOKEN_" .. json_counter .. "__"
        json_store[token] = deepcopy(val)
        return token
    end,
    decode = function(str)
        if type(str) ~= "string" then return nil end
        local token = str:match("(__JSON_TOKEN_%d+__)")
        if token and json_store[token] then
            return deepcopy(json_store[token])
        end
        return nil
    end,
}

local Settings = require("booxbook.store.settings")
local old_downloadDir = Settings.downloadDir
Settings.downloadDir = function() return "@cont" end

package.loaded["booxbook.continuation"] = nil
local Continuation = require("booxbook.continuation")
local Download = require("booxbook.comic-download")
local Catalog = require("booxbook.ui.catalog")
local ReaderUI = require("apps/reader/readerui")
local Cbz = require("booxbook.comic-cbz")
local old_verify = Cbz.verify
Cbz.verify = function(path)
    if type(path) == "string" and path:find("corrupt") then
        return false, "archive corrupt"
    end
    return true
end

-- Virtual filesystem mapping for isolated portable tests
local paths = {}
local old_open, old_remove, old_rename = io.open, os.remove, os.rename
local function mapped(path)
    if type(path) ~= "string" then return path end
    if not paths[path] then
        paths[path] = os.tmpname()
    end
    return paths[path]
end

io.open = function(path, mode)
    if type(path) == "string" and path:find("^@cont") then
        return old_open(mapped(path), mode)
    end
    return old_open(path, mode)
end

os.remove = function(path)
    if type(path) == "string" and paths[path] then
        local real = paths[path]
        paths[path] = nil
        return old_remove(real)
    end
    return old_remove(path)
end

os.rename = function(a, b)
    if type(a) == "string" and a:find("^@cont") then
        local real_a = mapped(a)
        local real_b = mapped(b)
        old_remove(real_b)
        paths[a] = nil
        return old_rename(real_a, real_b)
    end
    return old_rename(a, b)
end

local cbz1_path = "@cont/comics/truyenqq/test-series/chap-1.cbz"
local cbz2_path = "@cont/comics/truyenqq/test-series/chap-2.cbz"
local cbz3_path = "@cont/comics/truyenqq/test-series/chap-3.cbz"
local non_comic_path = "@cont/received/book.epub"

local function touch(path)
    local f = io.open(path, "wb")
    if f then
        f:write("dummy")
        f:close()
    end
end

touch(cbz1_path)
touch(non_comic_path)

-- 1. Test Download.writeMeta and bounded Download.readMeta
assert(Download.writeMeta(nil, {}) == false, "writeMeta rejects nil path")
assert(Download.writeMeta(cbz1_path, "not a table") == false, "writeMeta rejects non-table meta")
assert(Download.readMeta(nil) == nil, "readMeta rejects nil path")
assert(Download.readMeta(cbz1_path) == nil, "readMeta returns nil when meta doesn't exist")

local sample_meta = {
    source_id = "truyenqq",
    series_id = "test-series",
    series_title = "Test Series",
    chapter = "chap-1",
    chapter_title = "Chương 1",
    chapter_url = "https://truyenqqko.com/truyen-tranh/test-series-chap-1",
    chapter_index = 1,
    next_url = "https://truyenqqko.com/truyen-tranh/test-series-chap-2",
    next_title = "Chương 2",
    next_chapter = "chap-2",
}

assert(Download.writeMeta(cbz1_path, sample_meta) == true, "writeMeta succeeds")
local read_back = assert(Download.readMeta(cbz1_path), "readMeta loads saved metadata")
assert(read_back.source_id == "truyenqq" and read_back.chapter == "chap-1", "metadata values match")
assert(read_back.next_url == "https://truyenqqko.com/truyen-tranh/test-series-chap-2", "next_url preserved")

-- Test metadata validation: invalid scalar fields are rejected
local bad_meta_path = "@cont/comics/truyenqq/test-series/bad.cbz"
touch(bad_meta_path)
Download.writeMeta(bad_meta_path, { source_id = "", chapter = "chap-1" })
assert(Download.readMeta(bad_meta_path) == nil, "readMeta rejects empty source_id")
Download.writeMeta(bad_meta_path, { source_id = "truyenqq", chapter = "" })
assert(Download.readMeta(bad_meta_path) == nil, "readMeta rejects empty chapter")
os.remove(bad_meta_path .. ".meta.json")
os.remove(bad_meta_path)

-- Test oversized metadata (> 64 KiB) rejection via 65537-byte read
local oversized_meta_path = "@cont/comics/truyenqq/test-series/oversized.cbz"
touch(oversized_meta_path)
local valid_token = package.loaded["json"].encode(sample_meta)
local padded_oversized = valid_token .. string.rep(" ", 65537)
local f_over = io.open(oversized_meta_path .. ".meta.json", "wb")
f_over:write(padded_oversized)
f_over:close()
assert(Download.readMeta(oversized_meta_path) == nil, "readMeta rejects sidecars larger than 64 KiB")
os.remove(oversized_meta_path .. ".meta.json")
os.remove(oversized_meta_path)

-- 2. Test Continuation.resolveComicNext
-- Non-comic file returns nil
assert(Continuation.resolveComicNext(non_comic_path) == nil, "non-comic file ignored")
assert(Continuation.resolveComicNext("/other/dir/chap-1.cbz") == nil, "file outside downloadDir ignored")

-- Security/integrity: foreign host or wrong adapter next_url is rejected
local foreign_meta_path = "@cont/comics/truyenqq/test-series/foreign.cbz"
touch(foreign_meta_path)
Download.writeMeta(foreign_meta_path, {
    source_id = "truyenqq",
    chapter = "chap-1",
    next_url = "https://evil.test/manga/test-chap-2",
})
assert(Continuation.resolveComicNext(foreign_meta_path) == nil, "foreign next_url fails closed")

-- Next chapter not yet downloaded
local next_info = assert(Continuation.resolveComicNext(cbz1_path), "resolves next chapter info")
assert(next_info.source_id == "truyenqq", "source matches")
assert(next_info.current_title == "Chương 1", "current title matches")
assert(next_info.next_title == "Chương 2", "next title matches")
assert(next_info.downloaded == false, "detects chapter 2 is not yet downloaded")
assert(next_info.next_url == "https://truyenqqko.com/truyen-tranh/test-series-chap-2", "next url matches")


-- Android symlink / path alias test: /sdcard/... resolves to canonical downloadDir
local ffi_util = require("ffi/util")
local old_realpath = ffi_util.realpath
ffi_util.realpath = function(p)
    if type(p) == "string" and p:find("^/sdcard/koreader/booxbook") then
        return p:gsub("^/sdcard/koreader/booxbook", "@cont")
    end
    return p
end
local alias_info = assert(Continuation.resolveComicNext("/sdcard/koreader/booxbook/comics/truyenqq/test-series/chap-1.cbz"),
    "resolves chapter through Android /sdcard symlink alias")
assert(alias_info.source_id == "truyenqq", "alias resolves source correctly")
assert(alias_info.next_url == "https://truyenqqko.com/truyen-tranh/test-series-chap-2", "alias resolves next url")
ffi_util.realpath = old_realpath
-- When next chapter file exists on disk and is valid
touch(cbz2_path)
local next_info_dl = assert(Continuation.resolveComicNext(cbz1_path), "resolves next chapter info when downloaded")
assert(next_info_dl.downloaded == true, "detects chapter 2 is now downloaded")
os.remove(cbz2_path)

-- When next chapter file on disk is corrupt: savedPath fails -> resolveComicNext fails closed
local corrupt_meta_path = "@cont/comics/truyenqq/test-series/corrupt-prev.cbz"
local corrupt_next_path = "@cont/comics/truyenqq/test-series/corrupt-next.cbz"
touch(corrupt_meta_path)
touch(corrupt_next_path)
Download.writeMeta(corrupt_meta_path, {
    source_id = "truyenqq",
    chapter = "corrupt-prev",
    next_url = "https://truyenqqko.com/truyen-tranh/test-series-corrupt-next",
})
assert(Continuation.resolveComicNext(corrupt_meta_path) == nil, "corrupt next CBZ fails closed")
os.remove(corrupt_meta_path .. ".meta.json")
os.remove(corrupt_meta_path)
os.remove(corrupt_next_path)

-- When chapter is the last chapter (no next_url)
local last_meta = {
    source_id = "truyenqq",
    series_id = "test-series",
    chapter = "chap-99",
    chapter_title = "Chapter 99",
}
local cbz99_path = "@cont/comics/truyenqq/test-series/chap-99.cbz"
touch(cbz99_path)
Download.writeMeta(cbz99_path, last_meta)
local last_info = assert(Continuation.resolveComicNext(cbz99_path), "last chapter resolves end of series")
assert(last_info.end_of_series == true, "identifies end of series")
assert(last_info.next_url == nil, "has no next_url")

-- 3. Test Continuation.onEndOfBook UI interactions & Handler-Order Race
local ui_mock = { document = { file = cbz1_path } }

-- Order A: "default already topmost" -> ReaderStatus dialog was already opened before BooxBook ran
local default_koreader_dialog = { name = "end_document", is_default = true }
top_widget = default_koreader_dialog
closed_widgets = {}
Continuation.reset()
downloaded_url = nil

local handled_a = Continuation.onEndOfBook(ui_mock)
assert(handled_a == true, "consumes event when default dialog was topmost")
assert(closed_widgets[1] == default_koreader_dialog, "closes existing default end_document dialog")
assert(top_widget ~= nil and top_widget.name == "end_document", "names own confirm box end_document")
assert(top_widget.text:find("Chương 1", 1, true) and top_widget.text:find("Chương 2", 1, true),
    "confirm message mentions current and next chapter")

-- User confirms download:
top_widget.ok()
assert(downloaded_url == "https://truyenqqko.com/truyen-tranh/test-series-chap-2", "triggers download of next chapter")

-- Order B: "custom runs first" -> BooxBook runs before ReaderStatus
top_widget = nil
closed_widgets = {}
Continuation.reset()

local handled_b = Continuation.onEndOfBook(ui_mock)
assert(handled_b == true, "consumes event when running first")
assert(top_widget ~= nil and top_widget.name == "end_document", "top widget is named end_document so ReaderStatus skips")

-- Second EndOfBook on same open document:
local handled_second = Continuation.onEndOfBook(ui_mock)
assert(handled_second == true, "second EndOfBook remains consumed so default dialog is never triggered")

-- Closing document resets guard
Continuation.reset()
top_widget = nil
local handled_reset = Continuation.onEndOfBook(ui_mock)
assert(handled_reset == true, "resetting guard allows prompt on next open")
assert(top_widget ~= nil, "prompt displayed after reset")

-- Test prompt when next chapter IS downloaded
touch(cbz2_path)
Continuation.reset()
top_widget = nil
shown_reader_path = nil

local handled_dl = Continuation.onEndOfBook(ui_mock)
assert(handled_dl == true, "consumes event for downloaded chapter")
assert(top_widget ~= nil and top_widget.name == "end_document", "shows confirm dialog when next chapter is already downloaded")

-- User confirms opening:
top_widget.ok()
assert(shown_reader_path:find("chap-2.cbz", 1, true), "opens chapter 2 CBZ in reader")

-- Test non-comic file does not trigger popup and returns nil
Continuation.reset()
top_widget = nil
local handled_non = Continuation.onEndOfBook({ document = { file = non_comic_path } })
assert(handled_non == nil, "non-comic document returns nil to allow normal KOReader behavior")
assert(top_widget == nil, "non-comic document does not open popup")

-- 4. Test multi-hop continuation (1 -> 2 -> 3) through series manifest
local series_dir = "@cont/comics/truyenqq/test-series"
local mock_series = {
    source_id = "truyenqq",
    id = "test-series",
    title = "Test Series",
    url = "https://truyenqqko.com/truyen-tranh/test-series",
    chapters = {
        { url = "https://truyenqqko.com/truyen-tranh/test-series-chap-1", title = "Chương 1", chapter = "chap-1", index = 1 },
        { url = "https://truyenqqko.com/truyen-tranh/test-series-chap-2", title = "Chương 2", chapter = "chap-2", index = 2 },
        { url = "https://truyenqqko.com/truyen-tranh/test-series-chap-3", title = "Chương 3", chapter = "chap-3", index = 3 },
    }
}
local range_res = assert(Download.range(mock_series, 1, 1), "production Download.range initiates series")
assert(range_res.saved[1].path == cbz1_path, "chapter 1 saved in range")
assert(Download.readManifest(series_dir) ~= nil, "production Download.range wrote manifest.json")

-- Chapter 2 exists on disk from a legacy/pre-feature download with NO sidecar
touch(cbz2_path)
os.remove(cbz2_path .. ".meta.json")
assert(Download.readMeta(cbz2_path) == nil, "chapter 2 initially has no sidecar (legacy file)")

-- When chapter 1 finishes, resolveComicNext finds chapter 2 on disk and backfills its metadata!
local ch1_next_info = assert(Continuation.resolveComicNext(cbz1_path), "resolves chapter 2 from chapter 1")
assert(ch1_next_info.downloaded == true, "chapter 2 detected as downloaded")

-- Verify chapter 2 has now gained metadata pointing to chapter 3 without re-downloading
local ch2_backfilled = assert(Download.readMeta(cbz2_path), "chapter 2 gained backfilled metadata")
assert(ch2_backfilled.next_url == "https://truyenqqko.com/truyen-tranh/test-series-chap-3", "backfill points to chapter 3")
assert(ch2_backfilled.next_title == "Chương 3", "backfill has chapter 3 title")

-- Now when user finishes reading chapter 2, it seamlessly offers chapter 3!
local ch2_next_info = assert(Continuation.resolveComicNext(cbz2_path), "resolves chapter 3 from chapter 2")
assert(ch2_next_info.next_url == "https://truyenqqko.com/truyen-tranh/test-series-chap-3",
    "multi-hop chain succeeds: 1 -> legacy 2 -> 3")
assert(ch2_next_info.downloaded == false, "chapter 3 is not yet downloaded")

-- Test manifest identity validation in buildMeta:
-- Mismatched series id in manifest is rejected
local tampered_series = {
    source_id = "truyenqq",
    id = "other-series",
    title = "Other Series",
    chapters = mock_series.chapters,
}
local meta_tampered = Download.buildMeta("https://truyenqqko.com/truyen-tranh/test-series-chap-1", tampered_series, 1)
assert(meta_tampered.next_url == nil, "buildMeta rejects manifest with mismatched series id")

-- Mismatched source_id in manifest is rejected
local wrong_source_series = {
    source_id = "truyentuoitho",
    id = "test-series",
    title = "Wrong Source",
    chapters = mock_series.chapters,
}
local meta_wrong_src = Download.buildMeta("https://truyenqqko.com/truyen-tranh/test-series-chap-1", wrong_source_series, 1)
assert(meta_wrong_src.next_url == nil, "buildMeta rejects manifest with mismatched source_id")

-- Manifest with cross-series next chapter is rejected
local cross_series_chapters = {
    source_id = "truyenqq",
    id = "test-series",
    chapters = {
        { url = "https://truyenqqko.com/truyen-tranh/test-series-chap-1", title = "Chương 1", chapter = "chap-1", index = 1 },
        { url = "https://truyenqqko.com/truyen-tranh/injected-evil-chap-2", title = "Evil 2", chapter = "chap-2", index = 2 },
    }
}
local meta_cross = Download.buildMeta("https://truyenqqko.com/truyen-tranh/test-series-chap-1", cross_series_chapters, 1)
assert(meta_cross.next_url == nil, "buildMeta rejects next chapter from a different series")

-- Live UI series without source_id must remain functional
local series_no_src = {
    id = "test-series",
    title = "Test Series",
    chapters = mock_series.chapters,
}
local meta_no_src = Download.buildMeta("https://truyenqqko.com/truyen-tranh/test-series-chap-2", series_no_src, 2)
assert(meta_no_src ~= nil, "buildMeta accepts live series lacking source_id")
assert(meta_no_src.next_url == "https://truyenqqko.com/truyen-tranh/test-series-chap-3", "live series without source_id emits next_url")

-- Manifest with matching identity but unparseable/foreign next chapter is rejected
local malformed_next_series = {
    source_id = "truyenqq",
    id = "test-series",
    chapters = {
        { url = "https://truyenqqko.com/truyen-tranh/test-series-chap-1", title = "Chương 1", chapter = "chap-1", index = 1 },
        { url = "https://evil.test/not-a-chapter", title = "Evil", chapter = "evil", index = 2 },
    }
}
local meta_malformed = Download.buildMeta("https://truyenqqko.com/truyen-tranh/test-series-chap-1", malformed_next_series, 1)
assert(meta_malformed.next_url == nil, "buildMeta emits nil when next chapter URL is unparseable")

-- 5. Test novel continuation (EPUB and HTML)
local novel_dir = "@cont/novels/truyenfull/test-novel"
local epub1_path = novel_dir .. "/chapters-1-1.epub"
local epub2_path = novel_dir .. "/chapters-2-2.epub"
local html1_path = novel_dir .. "/chapter-1.html"
touch(epub1_path)
touch(html1_path)

local mock_novel_index = {
    id = "test-novel",
    title = "Test Novel Title",
    chapters = {
        ["1"] = { number = 1, title = "Chương 1", file = "chapters-1-1.epub", url = "https://truyenfull.live/test-novel/chuong-1/" },
    }
}
local index_file = io.open(novel_dir .. "/index.json", "wb")
index_file:write(package.loaded["json"].encode(mock_novel_index))
index_file:close()

-- Test resolveNovelNext when chapter 2 is not yet downloaded
local novel_next_info = assert(Continuation.resolveNovelNext(epub1_path), "resolves novel next chapter from EPUB")
assert(novel_next_info.kind == "novel", "kind is novel")
assert(novel_next_info.series_id == "test-novel", "series_id matches")
assert(novel_next_info.current_title == "Chương 1", "current title matches")
assert(novel_next_info.next_title == "Chương 2", "next title matches")
assert(novel_next_info.next_number == 2, "next number is 2")
assert(novel_next_info.downloaded == false, "chapter 2 is not downloaded yet")

-- Test resolveNovelNext for HTML format
local html_next_info = assert(Continuation.resolveNovelNext(html1_path), "resolves novel next chapter from HTML")
assert(html_next_info.next_number == 2, "HTML next number is 2")

-- Test Continuation.onEndOfBook prompt for novel when not downloaded
Continuation.reset()
top_widget = nil
downloaded_novel_series = nil
local handled_novel = Continuation.onEndOfBook({ document = { file = epub1_path } })
assert(handled_novel == true, "consumes EndOfBook for novel EPUB")
assert(top_widget ~= nil and top_widget.name == "end_document", "shows confirm box named end_document for novel")
assert(top_widget.text:find("Chương 1", 1, true) and top_widget.text:find("Chương 2", 1, true), "prompt mentions chapters")

-- User confirms download:
top_widget.ok()
assert(downloaded_chapter_src == "truyenfull", "initiates download for truyenfull")
assert(downloaded_chapter_series_id == "test-novel", "initiates download for correct novel")
assert(downloaded_chapter_num == 2, "downloads chapter 2")
assert(downloaded_chapter_url == "https://truyenfull.live/test-novel/chuong-1/", "passes chapter url")
-- Test prompt when novel chapter 2 IS downloaded
touch(epub2_path)
mock_novel_index.chapters["2"] = { number = 2, title = "Chương 2", file = "chapters-2-2.epub" }
local index_file2 = io.open(novel_dir .. "/index.json", "wb")
index_file2:write(package.loaded["json"].encode(mock_novel_index))
index_file2:close()

Continuation.reset()
top_widget = nil
shown_reader_path = nil
local handled_novel_dl = Continuation.onEndOfBook({ document = { file = epub1_path } })
assert(handled_novel_dl == true, "consumes EndOfBook for downloaded novel chapter")
assert(top_widget ~= nil, "shows open prompt for downloaded novel chapter")
top_widget.ok()
assert(shown_reader_path:find("chapters-2-2.epub", 1, true), "opens next EPUB chapter directly")

-- Test real Novels.downloadChapter builds correct series ref and does not pass chapter URL
local RealNovels = dofile("booxbook.koplugin/booxbook/ui/novels.lua")
local received_ref = nil
local Source = require("booxbook.source")
local old_tf = Source.get("truyenfull")
Source.adapters["truyenfull"] = {
    id = "truyenfull",
    getSeries = function(ref)
        received_ref = ref
        return {
            id = "test-novel",
            title = "Test Novel",
            chapters = { { index = 1 }, { index = 2 } },
        }
    end,
}
RealNovels.downloadChapter("truyenfull", "test-novel", 2, "https://truyenfull.live/test-novel/chuong-1/")
assert(received_ref == "/test-novel/", "downloadChapter passes series ref not chapter url")
assert(not received_ref:find("chuong"), "series ref does not contain chapter segment")
Source.adapters["truyenfull"] = old_tf

-- 6. Test main.lua BooxBook:onEndOfBook and onCloseDocument
local BooxBook = dofile("booxbook.koplugin/main.lua")
BooxBook.ui = { document = { file = cbz1_path } }
Continuation.reset()
top_widget = nil

local handled_main = BooxBook:onEndOfBook()
assert(handled_main == true, "BooxBook:onEndOfBook returns true to consume event")
BooxBook:onCloseDocument()
assert(Continuation.prompted_path == nil, "onCloseDocument resets continuation guard")

-- 7. Regression: unresolvable BooxBook file must NOT swallow EndOfBook
local orphan_cbz = "@cont/comics/truyenqq/orphan.cbz"
touch(orphan_cbz)
os.remove(orphan_cbz .. ".meta.json")
Continuation.reset()
top_widget = nil
local handled_orphan = Continuation.onEndOfBook({ document = { file = orphan_cbz } })
assert(handled_orphan == nil, "unresolvable comic returns nil so KOReader default dialog shows")
assert(top_widget == nil, "no prompt for unresolvable comic")
os.remove(orphan_cbz)

-- 8. Regression: auto-built terminal meta must not seal bootstrap path
os.remove(series_dir .. "/manifest.json")
local auto_meta = Download.buildMeta("https://truyenqqko.com/truyen-tranh/test-series-chap-1")
assert(auto_meta ~= nil and auto_meta.next_url == nil, "no manifest yields terminal auto-meta")
local noseal_cbz = "@cont/comics/truyenqq/test-series/chap-9.cbz"
touch(noseal_cbz)
os.remove(noseal_cbz .. ".meta.json")
local existing_meta = Download.chapter("https://truyenqqko.com/truyen-tranh/test-series-chap-9")
assert(existing_meta ~= nil, "existing chapter returns saved path")
assert(Download.readMeta(noseal_cbz) == nil, "existing chapter without manifest leaves no terminal sidecar")
os.remove(noseal_cbz)
Download.writeManifest(series_dir, mock_series)

-- 9. Regression: cross-series next rejected in range meta
local evil_series = {
    source_id = "truyenqq",
    id = "test-series",
    title = "Test Series",
    chapters = {
        { url = "https://truyenqqko.com/truyen-tranh/test-series-chap-1", title = "Ch 1" },
        { url = "https://truyenqqko.com/truyen-tranh/other-series-chap-2", title = "Evil" },
    },
}
local evil_dir = "@cont/comics/truyenqq/evil-series"
Download.writeManifest(evil_dir, evil_series)
assert(Download.readManifest(evil_dir) == nil, "manifest with cross-series chapter refused")

-- 10. Regression: downloadChapter validates chapter number
RealNovels.downloadChapter("truyenfull", "test-novel", "not-a-number", nil)
assert(received_ref == "/test-novel/", "invalid chapter number does not trigger fetch")

-- Restore mocks and cleanup
Cbz.verify = old_verify
for _, name in ipairs(stub_names) do
    package.loaded[name] = saved_stubs[name]
end

for p, real in pairs(paths) do
    old_remove(real)
end
io.open = old_open
os.remove = old_remove
os.rename = old_rename
Settings.downloadDir = old_downloadDir

print("Continuation unit and integration checks passed")
