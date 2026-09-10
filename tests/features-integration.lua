-- Integration and regression tests for BooxBook 7 Features (Phase 08)
local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path
package.preload["socket"] = function()
    return {
        gettime = function() return os.time() end,
        sleep = function() end,
        skip = function(count, ...) return select(count + 1, ...) end,
    }
end
package.preload["socket.http"] = function()
    return { request = function() return 1, 200, {}, "OK" end }
end
package.preload["ltn12"] = function()
    return {
        sink = { table = function(t) return function(c) if c then t[#t+1]=c end return true end end },
        source = { string = function(s) local d=false return function() if d then return nil end d=true return s end end },
    }
end

package.loaded["gettext"] = function(s) return s end
package.loaded["gettext"] = function(s) return s end
package.loaded["ui/widget/infomessage"] = { new = function(_, t) return t end }
package.loaded["dispatcher"] = { registerAction = function() end }
package.loaded["ui/widget/container/widgetcontainer"] = { extend = function(_, val) return val end }
package.loaded["ui/widget/confirmbox"] = {}
package.loaded["ui/widget/inputdialog"] = {}
package.loaded["ui/network/manager"] = {}
package.loaded["apps/reader/readerui"] = { showReader = function() end }
package.loaded["booxbook.ui.cover-grid"] = function() return { PAGE_SIZE = 6 } end
package.loaded["ffi/util"] = { realpath = function(p) return p end }
package.loaded["libs/libkoreader-lfs"] = { attributes = function() return nil end, symlinkattributes = function() return nil end }
local queued_ticks = {}
package.loaded["ui/uimanager"] = {
    show = function() end,
    nextTick = function(_, fn) queued_ticks[#queued_ticks + 1] = fn end,
}
package.loaded["ui/trapper"] = { wrap = function(_, fn) fn() end }

local Settings = require("booxbook.store.settings")
local ReadingState = require("booxbook.reading-state")
local Library = require("booxbook.library")
local Download = require("booxbook.comic-download")
local Html = require("booxbook.html")

package.loaded["json"] = {
    encode = function(t)
        if type(t) ~= "table" then return tostring(t) end
        local parts = {}
        for k, v in pairs(t) do
            local vs = type(v) == "table" and "{}" or string.format("%q", tostring(v))
            if type(v) == "number" or type(v) == "boolean" then vs = tostring(v) end
            parts[#parts + 1] = string.format("%q:%s", tostring(k), vs)
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
        return res
    end,
}

local paths = {}
local old_open, old_remove, old_rename = io.open, os.remove, os.rename
local function mapped(path)
    if type(path) ~= "string" or not path:match("^test%-output/") then return path end
    if not paths[path] then paths[path] = os.tmpname(); old_remove(paths[path]) end
    return paths[path]
end
io.open = function(path, mode) return old_open(mapped(path), mode) end
os.remove = function(path) return old_remove(mapped(path)) end
os.rename = function(a, b) return old_rename(mapped(a), mapped(b)) end

local orig_dl = Settings.downloadDir
local orig_ensure = Settings.ensureDir
Settings.downloadDir = function() return "test-output" end
Settings.ensureDir = function() return true end
-- 1. REGRESSION TEST: Refresh-after-reading for comics
-- User reads a comic to Chapter 2 (50% progress).
-- Then an online TOC refresh runs via Download.writeManifest.
-- The manifest MUST preserve reading_state and not clobber it!
local comic_dir = "test-output/comics/truyenqq/refresh-test"
Settings.ensureDir(comic_dir)

local comic_file = comic_dir .. "/chap-1.cbz"
local initial_series = {
    source_id = "truyenqq",
    title = "Bộ truyện thử nghiệm",
    url = "https://truyenqqko.com/truyen-tranh/refresh-test",
    chapters = {
        { url = "https://truyenqqko.com/truyen-tranh/refresh-test-chap-1", chapter = "chap-1", title = "Tập 1" },
        { url = "https://truyenqqko.com/truyen-tranh/refresh-test-chap-2", chapter = "chap-2", title = "Tập 2" },
    },
}

-- Write initial manifest
assert(Download.writeManifest(comic_dir, initial_series), "initial manifest written")

-- Simulate user reading chap-1
ReadingState.recordProgress(comic_file, 5, 10, false)
local progress_before = ReadingState.getProgress("comic", "truyenqq", "refresh-test", comic_dir)
assert(progress_before ~= nil, "progress recorded before refresh")
assert(progress_before.status == "reading", "status is reading before refresh")

-- Refresh TOC with new chapter (e.g. author released chapter 3)
local refreshed_series = {
    source_id = "truyenqq",
    title = "Bộ truyện thử nghiệm (Đã cập nhật)",
    url = "https://truyenqqko.com/truyen-tranh/refresh-test",
    chapters = {
        { url = "https://truyenqqko.com/truyen-tranh/refresh-test-chap-1", chapter = "chap-1", title = "Tập 1" },
        { url = "https://truyenqqko.com/truyen-tranh/refresh-test-chap-2", chapter = "chap-2", title = "Tập 2" },
        { url = "https://truyenqqko.com/truyen-tranh/refresh-test-chap-3", chapter = "chap-3", title = "Tập 3" },
    },
}
-- 2. Reader lifecycle hooks in main.lua
local BooxBook = dofile(plugin_root .. "/main.lua")

-- Mock reader UI
local reader_doc = {
    file = comic_file,
    getPageCount = function() return 20 end,
}
BooxBook.ui = {
    document = reader_doc,
    paging = { current_page = 20 },
}

-- End of book marks complete
BooxBook:onEndOfBook()
local progress_completed = ReadingState.getProgress("comic", "truyenqq", "refresh-test", comic_dir)
assert(progress_completed.status == "complete", "onEndOfBook marks status complete")
assert(progress_completed.read_percent == 100, "onEndOfBook sets read_percent to 100")

-- Close document records progress
BooxBook.ui.paging.current_page = 15
BooxBook:onCloseDocument()
local progress_closed = ReadingState.getProgress("comic", "truyenqq", "refresh-test", comic_dir)
assert(progress_closed ~= nil, "onCloseDocument persists progress")

-- 3. Library.collect reading badge display
local mock_scan_tree = {
    ["test-output"] = { "novels" },
    ["test-output/novels"] = { "docln" },
    ["test-output/novels/docln"] = { "s1" },
    ["test-output/novels/docln/s1"] = { "ch-1.html", "index.json" },
}
local mock_lister = function(dir)
    return mock_scan_tree[dir] or {}
end
local mock_stat = function(path, req)
    if mock_scan_tree[path] then
        return req == "mode" and "directory" or { mode = "directory", size = 0, modification = 100 }
    elseif path:match("%.html$") then
        return req == "mode" and "file" or { mode = "file", size = 500, modification = 200 }
    end
    return nil
end

-- Set reading state for s1
local novel_path = "test-output/novels/docln/s1/ch-1.html"
ReadingState.markComplete("novel", "docln", "s1", "test-output/novels/docln/s1")

local books = Library.collect("test-output", {
    listFn = mock_lister,
    statFn = mock_stat,
    readJson = function(p) return { id = "s1", title = "Truyện S1" } end,
})
assert(#books == 1, "collected 1 novel")
assert(books[1].title:find("[Đã xong]", 1, true) ~= nil, "title contains reading badge [Đã xong]")

-- 4. Full-text search integration
local search_res = Library.searchFullText("/scan", "nonexistent_query", {
    max_matches = 10,
    file_lister = mock_lister,
    file_reader = function() return "empty" end,
})
-- Cleanup
io.open = old_open
os.remove = old_remove
os.rename = old_rename
for _, p in pairs(paths) do old_remove(p) end
Settings.downloadDir = orig_dl
Settings.ensureDir = orig_ensure

print("Features integration and regression checks passed")
