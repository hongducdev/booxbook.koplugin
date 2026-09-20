-- Đọc xong không lưu: only a chapter downloaded in this session may be dropped,
-- and only once its document closes.
local Transient = require("booxbook.transient")

local dir = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp"
local path = dir .. "/booxbook-transient-test.cbz"
local meta = path .. ".meta.json"

local function write(file, text)
    local f = assert(io.open(file, "wb"))
    f:write(text)
    f:close()
end
local function exists(file)
    local f = io.open(file, "rb")
    if f then f:close(); return true end
    return false
end

write(path, "CBZ")
write(meta, "{}")

assert(Transient.enabled() == false, "off by default")
assert(Transient.cleanup(path) == false, "an unmarked file is never deleted")
assert(exists(path) and exists(meta), "unmarked chapter and sidecar survive")

-- The setting is re-checked at close time: a reader who switched the feature off
-- keeps the file.
Transient.mark(path)
assert(Transient.isMarked(path), "a fresh download is marked")
assert(Transient.cleanup(path) == false, "switched off means nothing is deleted")
assert(exists(path) and exists(meta), "the chapter survives a switched-off cleanup")
assert(Transient.isMarked(path) == false, "the mark is dropped either way")

local Settings = require("booxbook.store.settings")
Settings.set("transient_comics", true)
Transient.mark(path)
assert(Transient.cleanup(path) == true, "a marked chapter is dropped on close")
assert(not exists(path) and not exists(meta), "cbz and sidecar are gone")
assert(Transient.cleanup(path) == false, "cleanup is idempotent")
assert(Transient.isMarked(path) == false, "a cleaned path is forgotten")
Settings.set("transient_comics", false)

Transient.mark(nil)
Transient.mark("")
assert(Transient.isMarked(nil) == false and Transient.isMarked("") == false, "nothing odd is marked")
Transient.reset()
assert(Transient.isMarked(path) == false, "reset forgets the session")

-- A deleted chapter must not leave KOReader's doc-settings directory behind:
-- "<book>.sdr/" still holds metadata.cbz.lua, so the read would leave a trace and
-- a later re-download would inherit stale progress. Only the sidecar derived from
-- the chapter itself may be touched, and only when the chapter really goes.
local saved_storage = package.loaded["booxbook.store.storage"]
local emptied = {}
package.loaded["booxbook.store.storage"] = {
    emptyDir = function(target) emptied[#emptied + 1] = target; return true end,
}

Settings.set("transient_comics", true)
write(path, "CBZ")
write(meta, "{}")
Transient.mark(path)
assert(Transient.cleanup(path) == true, "marked chapter is dropped")
assert(emptied[1] == dir .. "/booxbook-transient-test.sdr",
    "the doc-settings directory goes with the chapter: " .. tostring(emptied[1]))
assert(#emptied == 1, "exactly one doc-settings directory is touched")

-- The hidden name used for a long chapter has its own doc-settings directory.
local hidden_cbz = dir .. "/.booxbook-first.cbz"
local hidden_meta = hidden_cbz .. ".meta.json"
write(hidden_cbz, "CBZ")
write(hidden_meta, "{}")
Transient.mark(hidden_cbz)
assert(Transient.cleanup(hidden_cbz) == true, "hidden chapter is dropped")
assert(emptied[2] == dir .. "/.booxbook-first.sdr",
    "the hidden chapter's own doc-settings directory: " .. tostring(emptied[2]))
assert(not exists(hidden_cbz) and not exists(hidden_meta), "hidden chapter and sidecar are gone")

-- A refused cleanup (feature off, or a file this session never downloaded) must
-- leave the doc-settings directory alone.
write(path, "CBZ")
Transient.mark(path)
Settings.set("transient_comics", false)
assert(Transient.cleanup(path) == false, "cleanup refuses while the feature is off")
Settings.set("transient_comics", true)
assert(Transient.cleanup(path) == false, "cleanup refuses an unmarked path")
assert(#emptied == 2, "a refused cleanup never touches the doc-settings directory")
assert(exists(path), "the refused chapter is still there")
package.loaded["booxbook.store.storage"] = saved_storage

-- A partial chapter goes to a hidden name so savedPath() never mistakes it for a
-- finished download.
assert(Transient.hiddenName("/comics/truyenqq/series/chap-3.cbz") == "/comics/truyenqq/series/.chap-3-first.cbz")
assert(Transient.hiddenName("chap-3.cbz") == ".chap-3-first.cbz")
assert(Transient.hiddenName("/a/b/not-a-cbz.txt") == nil, "only .cbz names are rewritten")
assert(Transient.hiddenName(nil) == nil and Transient.hiddenName("") == nil, "nothing odd is renamed")

os.remove(path)
os.remove(meta)
print("Transient chapter checks passed")
