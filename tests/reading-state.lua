-- Unit tests for ReadingState (Phase 03)
local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local ReadingState = require("booxbook.reading-state")
package.loaded["json"] = {
    encode = function(t)
        -- Lightweight deterministic serializer for test fixtures
        if type(t) ~= "table" then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do
            local val_str = type(v) == "table" and "{}" or string.format("%q", tostring(v))
            if type(v) == "number" or type(v) == "boolean" then val_str = tostring(v) end
            parts[#parts + 1] = string.format("%q:%s", tostring(k), val_str)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end,
    decode = function(s)
        if type(s) ~= "string" or s == "" then return nil end
        local res = {}
        for k, v in s:gmatch('"([^"]+)"%s*:%s*"?([^",}]+)"?') do
            if v == "true" then res[k] = true
            elseif v == "false" then res[k] = false
            elseif tonumber(v) then res[k] = tonumber(v)
            else res[k] = v end
        end
        if s:find('"chapters"%s*:%s*{}') or s:find('"chapters"%s*:%s*%{') then
            res.chapters = res.chapters or {}
        end
        return res
    end,
}
local Json = package.loaded["json"]
-- 1. Key generation
assert(ReadingState.key("novel", "docln", "123") == "novel:docln:123", "key format")
assert(ReadingState.key("", "docln", "123") == nil, "empty kind returns nil")
assert(ReadingState.key("novel", "", "123") == nil, "empty source returns nil")

-- 2. Mock storage & settings
local mock_store = {}
local orig_get = Settings.get
local orig_set = Settings.set
local orig_dl = Settings.downloadDir

Settings.get = function(k) return mock_store[k] end
Settings.set = function(k, v) mock_store[k] = v end
Settings.downloadDir = function() return "test-output" end

-- Fixtures live in memory: plain LuaJIT has no mkdir, and what matters here is what
-- recordProgress stores, not the filesystem. readJson reads through io.open, so both
-- halves of the write/read pair have to be doubled.
local files = {}
local orig_html_write, orig_io_open = Html.writeFile, io.open
Html.writeFile = function(path, body) files[path] = body; return true end
io.open = function(path)
    local body = files[path]
    if not body then return nil end
    local pos = 0
    return {
        read = function(_, count)
            if type(count) == "number" then
                local chunk = body:sub(pos + 1, pos + count)
                pos = pos + #chunk
                if chunk == "" then return nil end
                return chunk
            end
            local rest = body:sub(pos + 1)
            pos = #body
            if rest == "" then return nil end
            return rest
        end,
        close = function() return true end,
        write = function() return true end,
    }
end

-- 3. Resolve target
local novel_path = "test-output/novels/docln/truyen-1/chapter-1.html"
local target_novel = ReadingState.resolveTarget(novel_path)
assert(target_novel ~= nil, "novel target resolved")
assert(target_novel.kind == "novel", "kind is novel")
assert(target_novel.source_id == "docln", "source is docln")
assert(target_novel.series_id == "truyen-1", "series is truyen-1")
assert(target_novel.file == "chapter-1.html", "filename resolved")

local comic_path = "test-output/comics/truyenqq/comic-1/tap-1.cbz"
local target_comic = ReadingState.resolveTarget(comic_path)
assert(target_comic ~= nil, "comic target resolved")
assert(target_comic.kind == "comic", "kind is comic")
assert(target_comic.source_id == "truyenqq", "source is truyenqq")
assert(target_comic.series_id == "comic-1", "series is comic-1")

assert(target_comic.file == "tap-1.cbz", "filename resolved")
local novel_dir = "test-output/novels/docln/truyen-1"
local mock_index = {
    id = "truyen-1",
    title = "Test Novel",
    chapters = {
        ["1"] = { number = 1, title = "Chương 1" },
        ["2"] = { number = 2, title = "Chương 2" },
        ["3"] = { number = 3, title = "Chương 3" },
        ["4"] = { number = 4, title = "Chương 4" },
    },
}
Html.writeFile(novel_dir .. "/index.json", Json.encode(mock_index))

-- Record reading page 5 of 10 in chapter 2 (chapter 2 of 4 = ~50%)
local res = ReadingState.recordProgress(novel_path, 5, 10, false)
assert(res ~= nil, "recorded novel progress")
assert(res.status == "reading", "status is reading")

-- Verify primary store in Settings
local history = mock_store["reading_history"]
assert(history ~= nil, "reading_history exists in Settings")
local novel_entry = history["novel:docln:truyen-1"]
assert(novel_entry ~= nil, "novel entry in Settings")
assert(novel_entry.status == "reading", "entry status reading")

-- Verify badge formatting
local badge = ReadingState.formatStatusBadge(novel_entry)
assert(badge:find("%]") ~= nil, "badge formatted with brackets")

-- End of book transition
local res_end = ReadingState.recordProgress(novel_path, 10, 10, true)
assert(res_end.status == "complete", "status becomes complete on end of book")
assert(res_end.read_percent == 100, "read_percent is 100")
assert(ReadingState.formatStatusBadge(res_end) == "[Đã xong]", "badge displays [Đã xong]")

-- 5. Comic progress & manifest mirror
local comic_dir = "test-output/comics/truyenqq/comic-1"
local mock_manifest = {
    source_id = "truyenqq",
    id = "comic-1",
    title = "Test Comic",
    chapters = {
        { chapter = "1", title = "Tập 1" },
        { chapter = "2", title = "Tập 2" },
    },
}
Html.writeFile(comic_dir .. "/manifest.json", Json.encode(mock_manifest))

local comic_res = ReadingState.recordProgress(comic_path, 10, 20, false)
assert(comic_res ~= nil, "recorded comic progress")
assert(comic_res.kind == "comic", "kind is comic")

-- Verify two-tier persistence: delete manifest.json from disk
os.remove(comic_dir .. "/manifest.json")
-- Progress must still be retrieved cleanly from Settings!
local retrieved = ReadingState.getProgress("comic", "truyenqq", "comic-1", comic_dir)
assert(retrieved ~= nil, "progress survives missing on-disk manifest")
assert(retrieved.status == "reading", "retrieved status is reading")

-- 6. Manual status toggles
ReadingState.markComplete("novel", "docln", "truyen-1", novel_dir)
local marked = ReadingState.getProgress("novel", "docln", "truyen-1", novel_dir)
assert(marked.status == "complete", "manual markComplete works")
assert(marked.read_percent == 100, "markComplete sets 100%")

ReadingState.markReading("novel", "docln", "truyen-1", novel_dir)
local marked_reading = ReadingState.getProgress("novel", "docln", "truyen-1", novel_dir)
assert(marked_reading.status == "reading", "manual markReading works")

-- 7. listHistory / historyPath: the "Đang đọc dở" screen reads Settings only.
local novel_entry_now = mock_store["reading_history"]["novel:docln:truyen-1"]
assert(novel_entry_now.title == "Test Novel", "novel entry records the series title")
local comic_entry_now = mock_store["reading_history"]["comic:truyenqq:comic-1"]
assert(comic_entry_now.title == "Test Comic", "comic entry records the series title")

local listed = ReadingState.listHistory()
assert(#listed == 2, "listHistory returns both series, got " .. tostring(#listed))
assert(listed[1].key == "comic:truyenqq:comic-1", "most recently read first")
assert(listed[1].kind == "comic" and listed[1].source_id == "truyenqq" and listed[1].series_id == "comic-1",
    "list entry carries its identity")
assert(listed[2].key == "novel:docln:truyen-1", "novel second")
assert(listed[2].title == "Test Novel", "title survives the copy into the list")

assert(ReadingState.historyPath(listed[2]) == "test-output/novels/docln/truyen-1/chapter-1.html",
    "novel resume path")
assert(ReadingState.historyPath(listed[1]) == "test-output/comics/truyenqq/comic-1/tap-1.cbz",
    "comic resume path")

-- A stored entry must never escape its series folder.
assert(ReadingState.historyPath{ kind = "novel", source_id = "docln", series_id = "truyen-1",
    last_read_file = "../../evil.html" } == nil, "traversal filename rejected")
assert(ReadingState.historyPath{ kind = "novel", source_id = "docln", series_id = "../x",
    last_read_file = "chapter-1.html" } == nil, "traversal series id rejected")
assert(ReadingState.historyPath{ kind = "novel", source_id = "docln", series_id = "..",
    last_read_file = "chapter-1.html" } == nil, "dot-dot series id rejected")
assert(ReadingState.historyPath{ kind = "novel", source_id = "..", series_id = "truyen-1",
    last_read_file = "chapter-1.html" } == nil, "dot-dot source id rejected")
assert(ReadingState.historyPath{ kind = "novel", source_id = ".hidden", series_id = "truyen-1",
    last_read_file = "chapter-1.html" } == nil, "hidden source id rejected")
assert(ReadingState.historyPath{ kind = "novel", source_id = "docln", series_id = ".hidden",
    last_read_file = "chapter-1.html" } == nil, "hidden series id rejected")
assert(ReadingState.historyPath{ kind = "other", source_id = "docln", series_id = "truyen-1",
    last_read_file = "chapter-1.html" } == nil, "unknown kind rejected")
assert(ReadingState.historyPath{ kind = "novel", source_id = "docln", series_id = "truyen-1" } == nil,
    "missing file name rejected")
assert(ReadingState.historyPath("novel:docln:truyen-1") == nil, "non-table entry rejected")

-- Legacy entry without a stamp sinks to the bottom; the cap holds at 30.
local synthetic = {}
for n = 1, 40 do
    synthetic["novel:docln:s" .. n] = { status = "reading", read_percent = n,
        last_read_file = "chapter-1.html", last_read_time = n }
end
synthetic["novel:docln:legacy"] = { status = "reading", read_percent = 5, last_read_file = "chapter-1.html" }
mock_store["reading_history"] = synthetic
local capped = ReadingState.listHistory()
assert(#capped == ReadingState.MAX_HISTORY, "listHistory caps at MAX_HISTORY, got " .. tostring(#capped))
assert(capped[1].series_id == "s40", "newest first")
local all = ReadingState.listHistory(100)
assert(#all == 41, "limit above the entry count returns everything, got " .. tostring(#all))
assert(all[#all].series_id == "legacy", "no-stamp entry sorts last")
assert(all[#all].last_read_time == 0, "no-stamp entry reports 0 instead of now()")
assert(all[#all].title == "legacy", "no-title entry falls back to the series id")
assert(#ReadingState.listHistory(0) == 0, "limit 0 returns nothing")
mock_store["reading_history"] = nil
assert(#ReadingState.listHistory() == 0, "missing history returns an empty list")

-- 8. Storage stays bounded: the history is keyed by series, so it grows with every
-- series ever opened. A save must drop the oldest entries past the storage cap, and
-- must keep the entry it just wrote.
local bulk = {}
for n = 1, ReadingState.MAX_STORED + 50 do
    bulk["novel:docln:b" .. n] = { status = "reading", read_percent = 1,
        last_read_file = "ch-1.html", last_read_time = n }
end
mock_store["reading_history"] = bulk
ReadingState.markReading("novel", "docln", "newest", "test-output/novels/docln/newest")
local stored = mock_store["reading_history"]
local stored_count = 0
for _key in pairs(stored) do stored_count = stored_count + 1 end
assert(stored_count == ReadingState.MAX_STORED,
    "history pruned on write, got " .. tostring(stored_count))
assert(stored["novel:docln:b1"] == nil, "oldest entry dropped")
assert(stored["novel:docln:b51"] == nil, "exactly the oldest entries are dropped")
assert(stored["novel:docln:b52"] ~= nil, "the first kept entry survives")
assert(stored["novel:docln:b" .. (ReadingState.MAX_STORED + 50)] ~= nil, "newest bulk entry survives")
assert(stored["novel:docln:newest"] ~= nil, "the entry just written survives")
assert(#ReadingState.listHistory() == ReadingState.MAX_HISTORY, "the pruned store still fills the list")

-- Cleanup
os.remove(novel_dir .. "/index.json")
Html.writeFile, io.open = orig_html_write, orig_io_open
Settings.get = orig_get
Settings.set = orig_set
Settings.downloadDir = orig_dl

print("ReadingState checks passed: two-tier persistence and status tracking verified")
