local names = { "ui/uimanager", "ffi/util", "libs/libkoreader-lfs",
    "apps/reader/readerui", "apps/filemanager/filemanager", "booxbook.news-cleanup" }
local previous = {}
for _, name in ipairs(names) do previous[name] = package.loaded[name] end
local Settings = require("booxbook.store.settings")
local old_dir = Settings.downloadDir
Settings.downloadDir = function() return "/downloads" end
local pending, deleted, refreshed = nil, nil, false
local reader = {}
local aliases = {}
package.loaded["ui/uimanager"] = { nextTick = function(_, callback) pending = callback end }
package.loaded["ffi/util"] = { realpath = function(path) return aliases[path] or path end }
package.loaded["libs/libkoreader-lfs"] = { attributes = function() return "file" end }
package.loaded["apps/reader/readerui"] = reader
package.loaded["apps/filemanager/filemanager"] = {
    deleteFile = function(_, path, is_file)
        assert(is_file, "never delete directories recursively")
        deleted = path
        return true
    end,
    instance = { onRefresh = function() refreshed = true end },
}
package.loaded["booxbook.news-cleanup"] = nil
local Cleanup = require("booxbook.news-cleanup")
local status, percent = "reading", 1
local ui = { document = { file = "/downloads/news/feed/article.html" },
    doc_settings = { readSetting = function(_, key)
        if key == "percent_finished" then return percent end
        return { status = status }
    end } }
local path = ui.document.file
local function reset() pending, deleted, refreshed = nil, nil, false end
Settings.set("news_delete_finished", false)
Cleanup.afterClose(ui, path)
assert(not pending, "disabled option keeps finished news")
Settings.set("news_delete_finished", true)
Cleanup.afterClose(ui)
assert(not pending, "unfinished news retained")
percent = 0.2
Cleanup.afterClose(ui, path)
assert(not pending, "EndOfBook then leave last page keeps article")
percent = 1
Cleanup.afterClose(ui, path)
assert(pending and not deleted, "deletion waits for reader close")
pending()
assert(deleted == path and refreshed, "finished article deleted through native file manager")
reset()
status = "complete"
Cleanup.afterClose(ui)
assert(pending, "explicit finished status works without EndOfBook")
Settings.set("news_delete_finished", false)
pending()
assert(not deleted, "recheck option before deletion")
Settings.set("news_delete_finished", true)
for _, other in ipairs({ "/downloads/novels/book.html", "/downloads/news-other/feed/book.html",
    "/downloads/news/feed/book.epub", "/downloads/news/feed/book.html.images/1.html" }) do
    reset(); ui.document.file = other
    Cleanup.afterClose(ui, other)
    assert(not pending, "cleanup must be restricted to news HTML")
end
ui.document.file = path
aliases[path] = "/outside/article.html"
reset(); Cleanup.afterClose(ui, path)
assert(not pending, "symlink escaping news root rejected")
aliases[path] = nil
reset(); Cleanup.afterClose(ui, path)
aliases[path] = "/outside/article.html"
pending()
assert(not deleted, "recheck canonical path before deleting")
aliases[path] = nil
reset(); Cleanup.afterClose(ui, path)
reader.instance = ui
pending()
assert(not deleted, "do not delete reopened document")
reader.instance = nil
-- /sdcard and /storage/emulated/0 may identify the same news file on Android.
reset(); aliases[path] = "/storage/news/feed/article.html"
aliases["/downloads/news"] = "/storage/news"
Cleanup.afterClose(ui, path); assert(pending); pending()
assert(deleted == "/storage/news/feed/article.html")
Settings.set("news_delete_finished", false)
Settings.downloadDir = old_dir
for _, name in ipairs(names) do package.loaded[name] = previous[name] end

-- Sidecar removal is gated on FileManager:deleteFile succeeding.
local sidecar_calls = {}
package.loaded["booxbook.store.storage"] = {
    removeSidecar = function(html) sidecar_calls[#sidecar_calls + 1] = html end,
}
package.loaded["booxbook.news-cleanup"] = nil
package.loaded["ui/uimanager"] = { nextTick = function(_, callback) pending = callback end }
package.loaded["ffi/util"] = { realpath = function(p) return p end }
package.loaded["libs/libkoreader-lfs"] = { attributes = function() return "file" end }
package.loaded["apps/reader/readerui"] = { instance = nil }
local delete_ok = true
package.loaded["apps/filemanager/filemanager"] = {
    deleteFile = function(_, p)
        deleted = p
        return delete_ok
    end,
    instance = { onRefresh = function() end },
}
Settings.downloadDir = function() return "/downloads" end
Settings.set("news_delete_finished", true)
local CleanupSidecar = require("booxbook.news-cleanup")
ui.document.file = path
pending, deleted, sidecar_calls = nil, nil, {}
CleanupSidecar.afterClose(ui, path)
assert(pending); pending()
assert(deleted == path and #sidecar_calls == 1, "sidecar removed after HTML delete")
delete_ok = false
pending, deleted, sidecar_calls = nil, nil, {}
CleanupSidecar.afterClose(ui, path)
assert(pending); pending()
assert(deleted == path and #sidecar_calls == 0, "failed HTML delete keeps sidecar")
Settings.set("news_delete_finished", false)
Settings.downloadDir = old_dir
package.loaded["booxbook.store.storage"] = nil
package.loaded["booxbook.news-cleanup"] = nil
for _, name in ipairs(names) do package.loaded[name] = previous[name] end
print("Finished news cleanup, deferred deletion and canonical path checks passed")
