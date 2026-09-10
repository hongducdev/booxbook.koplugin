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

-- Cleanup
os.remove(novel_dir .. "/index.json")
Settings.get = orig_get
Settings.set = orig_set
Settings.downloadDir = orig_dl

print("ReadingState checks passed: two-tier persistence and status tracking verified")
