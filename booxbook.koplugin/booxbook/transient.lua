-- Reading a chapter without keeping it.
--
-- KOReader can only read a document from a file, so "không lưu" cannot mean
-- holding the pages in memory: it means the CBZ written for this session is
-- deleted as soon as its document closes. Only files this session downloaded are
-- ever marked, so turning the setting on can never delete something the reader
-- already had in the library.
local Transient = {}

local marked = {}

function Transient.enabled()
    local ok, Settings = pcall(require, "booxbook.store.settings")
    return ok and type(Settings.transientComics) == "function" and Settings.transientComics() == true
end

-- Called right after a fresh download, never for a file that already existed.
function Transient.mark(path)
    if type(path) ~= "string" or path == "" then return end
    marked[path] = true
end

function Transient.isMarked(path)
    return path ~= nil and marked[path] == true
end

-- Delete a marked chapter and its sidecar once its document is closed.
-- Returns true when something was removed.
function Transient.cleanup(path)
    if not Transient.isMarked(path) then return false end
    marked[path] = nil
    os.remove(path)
    os.remove(path .. ".meta.json")
    return true
end

function Transient.reset()
    marked = {}
end

-- A partial chapter must never take the canonical path: savedPath() would then
-- treat a truncated chapter as complete. The hidden name keeps it in the same
-- folder, invisible to the file browser, and it goes away with the document.
function Transient.hiddenName(path)
    if type(path) ~= "string" or path == "" then return nil end
    local hidden = path:gsub("([^/]+)%.cbz$", ".%1-first.cbz")
    if hidden == path then return nil end
    return hidden
end

return Transient
