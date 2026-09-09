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

print("Library checks passed")
