local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local Export = require("booxbook.novel-export")
local Settings = require("booxbook.store.settings")
local Continuation = require("booxbook.continuation")
local Epub = require("booxbook.epub")
local Html = require("booxbook.html")

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)), 2)
    end
end

local function assert_true(cond, msg)
    if not cond then error(msg or "expected true", 2) end
end

-- 1. Test splitIntoVolumes
local saved_5 = {
    { id = "c1", number = 1, title = "Chap 1", path = "/tmp/c1.html" },
    { id = "c2", number = 2, title = "Chap 2", path = "/tmp/c2.html" },
    { id = "c3", number = 3, title = "Chap 3", path = "/tmp/c3.html" },
    { id = "c4", number = 4, title = "Chap 4", path = "/tmp/c4.html" },
    { id = "c5", number = 5, title = "Chap 5", path = "/tmp/c5.html" },
}

local chunks_0 = Export.splitIntoVolumes(saved_5, 0)
assert_eq(#chunks_0, 1, "volume_size=0 keeps single volume")
assert_eq(#chunks_0[1], 5, "single volume contains all 5 chapters")

local chunks_2 = Export.splitIntoVolumes(saved_5, 2)
assert_eq(#chunks_2, 3, "volume_size=2 splits 5 chapters into 3 volumes")
assert_eq(#chunks_2[1], 2, "vol 1 has 2 chapters")
assert_eq(#chunks_2[2], 2, "vol 2 has 2 chapters")
assert_eq(#chunks_2[3], 1, "vol 3 has 1 chapter")

local chunks_5 = Export.splitIntoVolumes(saved_5, 5)
assert_eq(#chunks_5, 1, "volume_size=5 keeps single volume")

local chunks_10 = Export.splitIntoVolumes(saved_5, 10)
assert_eq(#chunks_10, 1, "volume_size=10 keeps single volume")

-- 2. Test multi-volume Export.finish
local test_dir = "/tmp/volume_test"

local html_files = {}
for i = 1, 5 do
    html_files[#html_files + 1] = {
        id = "chap-" .. i,
        number = i,
        title = "Chương " .. i,
        path = test_dir .. "/chapter-" .. i .. ".html",
    }
end

local index = {
    id = "test-series",
    title = "Bộ Truyện Test",
    chapters = {},
}
for i = 1, 5 do
    index.chapters["chap-" .. i] = {
        number = i,
        title = "Chương " .. i,
        file = "chapter-" .. i .. ".html",
    }
end

local series = {
    id = "test-series",
    source_id = "testsource",
    title = "Bộ Truyện Test",
    author = "Tác Giả A",
    chapters = {
        { id = "chap-1", title = "Chương 1" },
        { id = "chap-2", title = "Chương 2" },
        { id = "chap-3", title = "Chương 3" },
        { id = "chap-4", title = "Chương 4" },
        { id = "chap-5", title = "Chương 5" },
    },
}

-- Isolated JSON helper
local json_store = {}
local json_counter = 0
local function deepcopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do copy[k] = deepcopy(v) end
    return copy
end

local orig_json = package.loaded["json"]
local Json = {
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
package.loaded["json"] = Json

local written_epubs = {}
local old_epub_write = Epub.write
Epub.write = function(target, meta)
    written_epubs[#written_epubs + 1] = {
        target = target,
        title = meta.title,
        chapters = meta.chapters,
        identifier = meta.identifier,
    }
    return true
end

local old_html_write = Html.writeFile
Html.writeFile = function() return true end

local deleted_files = {}
local old_remove = os.remove
os.remove = function(path)
    deleted_files[#deleted_files + 1] = path
    return true
end

local result = { saved = { unpack(html_files) }, skipped = {}, keep_html = true }
Settings.set("novel_epub", true)
Settings.set("novel_volume_size", 2)

Export.finish(series, test_dir, 1, 5, index, result, Json, true, 2)

assert_eq(#written_epubs, 3, "wrote 3 volume EPUB files")
assert_true(written_epubs[1].target:find("chapters%-1%-2%.epub$") ~= nil, "vol 1 filename chapters-1-2.epub")
assert_true(written_epubs[2].target:find("chapters%-3%-4%.epub$") ~= nil, "vol 2 filename chapters-3-4.epub")
assert_true(written_epubs[3].target:find("chapters%-5%-5%.epub$") ~= nil, "vol 3 filename chapters-5-5.epub")
assert_eq(#written_epubs[1].chapters, 2, "vol 1 has 2 chapters")
assert_eq(#written_epubs[2].chapters, 2, "vol 2 has 2 chapters")
assert_eq(#written_epubs[3].chapters, 1, "vol 3 has 1 chapter")

-- Test keep_html = false commits to index and removes html
result = { saved = { unpack(html_files) }, skipped = {}, keep_html = false }
Export.finish(series, test_dir, 1, 5, index, result, Json, true, 2)

assert_eq(#result.saved, 3, "result.saved now holds the 3 epubs")
assert_eq(index.chapters["chap-1"].file, "chapters-1-2.epub", "chapter 1 mapped to vol 1 epub")
assert_eq(index.chapters["chap-2"].file, "chapters-1-2.epub", "chapter 2 mapped to vol 1 epub")
assert_eq(index.chapters["chap-3"].file, "chapters-3-4.epub", "chapter 3 mapped to vol 2 epub")
assert_eq(index.chapters["chap-4"].file, "chapters-3-4.epub", "chapter 4 mapped to vol 2 epub")
assert_eq(index.chapters["chap-5"].file, "chapters-5-5.epub", "chapter 5 mapped to vol 3 epub")
assert_eq(#deleted_files, 5, "all 5 html files deleted")

-- 3. Test Continuation from vol 1 to vol 2
local old_download_dir = Settings.downloadDir
Settings.downloadDir = function() return "/downloads" end
local mock_novel_dir = "/downloads/novels/testsource/test-series"

local mock_index = {
    id = "test-series",
    title = "Bộ Truyện Test",
    chapters = {
        ["1"] = { number = 1, title = "Chương 1", file = "chapters-1-2.epub" },
        ["2"] = { number = 2, title = "Chương 2", file = "chapters-1-2.epub" },
        ["3"] = { number = 3, title = "Chương 3", file = "chapters-3-4.epub" },
        ["4"] = { number = 4, title = "Chương 4", file = "chapters-3-4.epub" },
    },
}

local encoded_mock = Json.encode(mock_index)

local old_open = io.open
io.open = function(path, mode)
    if type(path) == "string" and path:find("index%.json") then
        return {
            read = function() return encoded_mock end,
            close = function() end,
        }
    end
    if type(path) == "string" and path:find("chapters%-3%-4%.epub") then
        return {
            close = function() end,
        }
    end
    return old_open(path, mode)
end

local next_info = Continuation.resolveNovelNext(mock_novel_dir .. "/chapters-1-2.epub")
assert_true(next_info ~= nil, "Continuation resolved next volume")
assert_eq(next_info.next_number, 3, "next chapter is 3")
assert_true(next_info.downloaded, "vol 2 is marked downloaded")
assert_true(next_info.next_path:find("chapters%-3%-4%.epub$") ~= nil, "next_path points to vol 2 epub")

-- Cleanup
Settings.downloadDir = old_download_dir
Epub.write = old_epub_write
Html.writeFile = old_html_write
os.remove = old_remove
io.open = old_open
package.loaded["json"] = orig_json
Settings.set("novel_volume_size", 0)

print("EPUB volume splitter checks passed: chunking, multi-volume packaging, index mapping and continuation verified")
