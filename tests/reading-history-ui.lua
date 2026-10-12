-- Regression for the "Đang đọc dở" screen: rows must build without crashing, a
-- deleted file must produce a sentence instead of a reader error, and the loop
-- index must not shadow gettext `_()` (the follow-list bug of ui-open.lua).
local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local names = { "gettext", "booxbook.ui.catalog", "booxbook.reading-state",
    "booxbook.ui.library", "booxbook.fault" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

package.loaded.gettext = function(text) return text end

local shown
package.loaded["booxbook.ui.catalog"] = {
    show = function(value) shown = value end,
    clearStack = function() end,
}

local notified
package.loaded["booxbook.fault"] = {
    notify = function(text) notified = text end,
}

local opened
package.loaded["booxbook.ui.library"] = {
    openBook = function(path) opened = path end,
}

local dir = "test-output/reading-history-ui"
-- One path resolves, the other does not: that is the whole difference the screen has
-- to handle. No fixture on disk, so the check is about the branch, not about mkdir.
local orig_io_open = io.open
io.open = function(path)
    if path == dir .. "/existing.html" then return { close = function() return true end } end
    return nil
end

local entries = {
    { key = "novel:docln:truyen-1", kind = "novel", source_id = "docln", series_id = "truyen-1",
        title = "Truyện Một", status = "reading", read_percent = 42, last_read_chapter = 7,
        last_read_file = "existing.html", last_read_time = 1700000000 },
    { key = "comic:truyenqq:comic-1", kind = "comic", source_id = "truyenqq", series_id = "comic-1",
        title = "Truyện Hai", status = "reading", read_percent = 0,
        last_read_file = "gone.cbz", last_read_time = 0 },
    { key = "novel:docln:legacy", kind = "novel", source_id = "docln", series_id = "legacy",
        title = "Truyện Cũ", status = "reading", read_percent = 5, last_read_time = 0 },
}

package.loaded["booxbook.reading-state"] = {
    MAX_HISTORY = 30,
    listHistory = function() return entries end,
    formatStatusBadge = function(info)
        if info.status == "complete" then return "[Đã xong]" end
        if (tonumber(info.read_percent) or 0) > 0 then return "[" .. tostring(info.read_percent) .. "%]" end
        return ""
    end,
    historyPath = function(entry)
        if type(entry.last_read_file) ~= "string" then return nil end
        return dir .. "/" .. entry.last_read_file
    end,
}

package.loaded["booxbook.ui.reading-history"] = nil
local HistoryUI = require("booxbook.ui.reading-history")

HistoryUI.open()
assert(shown and shown.title == "Đang đọc dở", "resume list opens")
assert(#shown.items == 3, "one row per history entry, got " .. tostring(#shown.items))
assert(shown.subtitle:find("3 m", 1, true), "subtitle counts the rows")

assert(shown.items[1].text == "Truyện Một · chương 7 · [42%]", "row shows title, chapter and badge, got " .. shown.items[1].text)
assert(shown.items[1].mandatory == os.date("%d/%m", 1700000000), "row shows the read date")

-- No chapter, no badge, no stamp: the title alone, and no `mandatory` at all.
assert(shown.items[2].text == "Truyện Hai", "row degrades without chapter/percent, got " .. shown.items[2].text)
assert(shown.items[2].mandatory == nil, "no stamp leaves the row width to the title")
assert(shown.items[3].text == "Truyện Cũ · [5%]", "legacy row still renders, got " .. shown.items[3].text)

-- Tap: an existing file resumes, a deleted one reports, a broken entry reports.
shown.items[1].callback()
assert(opened == dir .. "/existing.html", "tap opens the stored file, got " .. tostring(opened))
assert(notified == nil, "successful resume does not notify")

shown.items[2].callback()
assert(opened == dir .. "/existing.html", "missing file does not open a reader")
assert(notified and notified:find("Không tìm thấy tệp", 1, true), "missing file reports, got " .. tostring(notified))

notified = nil
shown.items[3].callback()
assert(notified and notified:find("đường dẫn", 1, true), "entry without a path reports, got " .. tostring(notified))

-- Empty history: one disabled row, no subtitle, no crash.
entries = {}
HistoryUI.open()
assert(#shown.items == 1 and shown.items[1].select_enabled == false, "empty history renders a disabled row")
assert(shown.subtitle == nil, "empty history has no subtitle")

os.remove(dir .. "/existing.html")
io.open = orig_io_open
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Reading history screen builds rows and handles missing files")
