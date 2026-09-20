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

Transient.mark(path)
assert(Transient.isMarked(path), "a fresh download is marked")
assert(Transient.cleanup(path) == true, "a marked chapter is dropped on close")
assert(not exists(path) and not exists(meta), "cbz and sidecar are gone")
assert(Transient.cleanup(path) == false, "cleanup is idempotent")
assert(Transient.isMarked(path) == false, "a cleaned path is forgotten")

Transient.mark(nil)
Transient.mark("")
assert(Transient.isMarked(nil) == false and Transient.isMarked("") == false, "nothing odd is marked")
Transient.reset()
assert(Transient.isMarked(path) == false, "reset forgets the session")

-- A partial chapter goes to a hidden name so savedPath() never mistakes it for a
-- finished download.
assert(Transient.hiddenName("/comics/truyenqq/series/chap-3.cbz") == "/comics/truyenqq/series/.chap-3-first.cbz")
assert(Transient.hiddenName("chap-3.cbz") == ".chap-3-first.cbz")
assert(Transient.hiddenName("/a/b/not-a-cbz.txt") == nil, "only .cbz names are rewritten")
assert(Transient.hiddenName(nil) == nil and Transient.hiddenName("") == nil, "nothing odd is renamed")

os.remove(path)
os.remove(meta)
print("Transient chapter checks passed")
