-- Image-cache storage: sidecar lifecycle, covers budget, comic staging sweep.
-- Uses an in-memory lfs double; production KOReader always ships lfs.
local saved_lfs_koreader = package.loaded["libs/libkoreader-lfs"]
local saved_lfs = package.loaded["lfs"]
local saved_gettext = package.loaded["gettext"]
local saved_os_remove = os.remove
if package.loaded["gettext"] == nil then
    package.loaded["gettext"] = function(s) return s end
end

local dirs, files = {}, {}

local function ensureDir(path)
    if dirs[path] then return end
    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= "" then ensureDir(parent) end
    dirs[path] = {}
    if parent and dirs[parent] then dirs[parent][path:match("[^/]+$")] = true end
end

local function addFile(path, size, mtime)
    local parent = path:match("^(.*)/[^/]+$")
    ensureDir(parent)
    files[path] = { size = size or 10, mtime = mtime or 1000 }
    dirs[parent][path:match("[^/]+$")] = true
end

local fake_lfs = {
    dir = function(path)
        if not dirs[path] then error("no such dir") end
        local names = {}
        for name in pairs(dirs[path]) do names[#names + 1] = name end
        local i = 0
        return function()
            i = i + 1
            return names[i]
        end
    end,
    attributes = function(path, key)
        if files[path] then
            if key == "mode" then return "file" end
            if key == "size" then return files[path].size end
            if key == "modification" then return files[path].mtime end
            return nil
        end
        if dirs[path] then
            if key == "mode" then return "directory" end
            return nil
        end
        return nil
    end,
    mkdir = function(path) ensureDir(path); return true end,
    rmdir = function(path)
        if dirs[path] and not next(dirs[path]) then
            local parent = path:match("^(.*)/[^/]+$")
            dirs[path] = nil
            if parent and dirs[parent] then dirs[parent][path:match("[^/]+$")] = nil end
            return true
        end
        return nil
    end,
}

package.loaded["libs/libkoreader-lfs"] = fake_lfs
package.loaded["lfs"] = fake_lfs

os.remove = function(path)
    if files[path] then
        local parent = path:match("^(.*)/[^/]+$")
        files[path] = nil
        if parent and dirs[parent] then dirs[parent][path:match("[^/]+$")] = nil end
        return true
    end
    if dirs[path] then
        if not next(dirs[path]) then return true end
        return nil
    end
    return nil
end

package.loaded["booxbook.store.storage"] = nil
local Storage = require("booxbook.store.storage")

-- Sidecar removal deletes numbered assets then the dir itself.
ensureDir("/dl/news/feed/post.html.images")
addFile("/dl/news/feed/post.html.images/1.gif", 5, 100)
addFile("/dl/news/feed/post.html.images/2.jpg", 7, 101)
assert(Storage.removeSidecar("/dl/news/feed/post.html") == true)
assert(files["/dl/news/feed/post.html.images/1.gif"] == nil)
assert(dirs["/dl/news/feed/post.html.images"] == nil, "sidecar dir removed")

-- removeSidecar on absent dir is a no-op success.
assert(Storage.removeSidecar("/dl/news/feed/missing.html") == true)

-- pruneSidecar keeps referenced names, drops stale numbered files only.
ensureDir("/dl/news/feed/other.html.images")
addFile("/dl/news/feed/other.html.images/1.gif", 5, 100)
addFile("/dl/news/feed/other.html.images/9.png", 5, 100)
addFile("/dl/news/feed/other.html.images/notes.txt", 5, 100)
local pruned = Storage.pruneSidecar("/dl/news/feed/other.html.images", { ["1.gif"] = true })
assert(pruned == 1, "only unreferenced numbered files pruned")
assert(files["/dl/news/feed/other.html.images/1.gif"] ~= nil)
assert(files["/dl/news/feed/other.html.images/notes.txt"] ~= nil, "non-image files untouched")

-- Orphan sweep removes sidecars whose HTML is gone, keeps live ones.
addFile("/dl/news/feed/gone.html.images/1.gif", 5, 100)
addFile("/dl/news/feed/kept.html", 20, 100)
addFile("/dl/news/feed/kept.html.images/1.gif", 5, 100)
local swept = Storage.sweepOrphanSidecars("/dl/news")
assert(swept >= 1, "orphan sidecar swept")
assert(dirs["/dl/news/feed/gone.html.images"] == nil)
assert(files["/dl/news/feed/kept.html.images/1.gif"] ~= nil, "live sidecar kept")

-- Covers budget trims oldest first across source dirs.
ensureDir("/dl/covers/docln")
ensureDir("/dl/covers/wattpad")
addFile("/dl/covers/docln/old.jpg", 40, 100)
addFile("/dl/covers/docln/new.jpg", 40, 300)
addFile("/dl/covers/wattpad/mid.png", 40, 200)
local bytes, count = Storage.treeSize("/dl/covers")
assert(bytes == 120 and count == 3, "tree size sums nested source dirs")
local freed, remaining = Storage.trimTreeByMtime("/dl/covers", 80)
assert(freed == 40 and remaining == 80, "oldest cover trimmed to budget")
assert(files["/dl/covers/docln/old.jpg"] == nil)
assert(files["/dl/covers/docln/new.jpg"] ~= nil)
freed, remaining = Storage.trimTreeByMtime("/dl/covers", 40, nil, "/dl/covers/wattpad/mid.png")
assert(files["/dl/covers/wattpad/mid.png"] ~= nil, "just-written keep_path is not evicted")
assert(files["/dl/covers/docln/new.jpg"] == nil)

-- Covers module measures and clears through the same helpers.
local Settings = require("booxbook.store.settings")
local old_dir = Settings.downloadDir
Settings.downloadDir = function() return "/dl" end
package.loaded["booxbook.covers"] = nil
local Covers = require("booxbook.covers")
local used, n = Covers.diskUsage()
assert(used == 40 and n == 1, "covers usage reflects trim")
assert(Covers.clear() == true)
used = Covers.diskUsage()
assert(used == 0, "covers cleared")
Settings.downloadDir = old_dir

-- Comic staging sweep: old abandoned staging goes, fresh work and CBZ stay.
local old_time = os.time
os.time = function() return 2000000 end
ensureDir("/dl/comics/truyentuoitho/series/.tap-1-pages")
addFile("/dl/comics/truyentuoitho/series/.tap-1-pages/0001", 30, 1000)
addFile("/dl/comics/truyentuoitho/series/.tap-1-pages/0001.url", 5, 1000)
ensureDir("/dl/comics/truyentuoitho/series/.tap-2-pages")
addFile("/dl/comics/truyentuoitho/series/.tap-2-pages/0001", 30, 1999990)
addFile("/dl/comics/truyentuoitho/series/tap-2.cbz", 100, 1999990)
addFile("/dl/comics/truyentuoitho/series/stray.part", 10, 1000)
Settings.downloadDir = function() return "/dl" end
package.loaded["booxbook.comic-download"] = nil
local Download = require("booxbook.comic-download")
local removed = Download.sweepStale(7)
assert(removed == 2, "old staging dir and stray part swept, fresh kept")
assert(dirs["/dl/comics/truyentuoitho/series/.tap-1-pages"] == nil)
assert(files["/dl/comics/truyentuoitho/series/.tap-2-pages/0001"] ~= nil, "fresh staging kept")
assert(files["/dl/comics/truyentuoitho/series/tap-2.cbz"] ~= nil, "published CBZ never touched")
assert(files["/dl/comics/truyentuoitho/series/stray.part"] == nil)
ensureDir("/dl/comics/truyentuoitho/series/.tap-empty-pages")
assert(Download.sweepStale(7) >= 1, "empty leftover staging reclaimed")
assert(dirs["/dl/comics/truyentuoitho/series/.tap-empty-pages"] == nil)
os.time = old_time
Settings.downloadDir = old_dir

-- pruneSidecar also drops crashed Html.writeFile leftovers (`N.ext.part`).
ensureDir("/dl/news/feed/part.html.images")
addFile("/dl/news/feed/part.html.images/1.gif", 5, 100)
addFile("/dl/news/feed/part.html.images/2.gif.part", 5, 100)
assert(Storage.pruneSidecar("/dl/news/feed/part.html.images", { ["1.gif"] = true }) == 1)
assert(files["/dl/news/feed/part.html.images/2.gif.part"] == nil, "sidecar .part files pruned")
assert(files["/dl/news/feed/part.html.images/1.gif"] ~= nil)

-- Images.process must not mutate sidecars; commitSidecar runs after HTML write.
local previous_images = Settings.includeImages()
Settings.set("include_images", true)
local Http = require("booxbook.http")
local old_http = Http.get
Http.get = function() return false, 404 end
ensureDir("/dl/news/feed/live.html.images")
addFile("/dl/news/feed/live.html.images/1.gif", 5, 100)
package.loaded["booxbook.article-images"] = nil
local Images = require("booxbook.article-images")
local _, plan = Images.process(
    '<img src="https://example.com/photo.gif" alt="x"/>',
    "https://example.com/",
    "/dl/news/feed/live.html",
    function(s) return s end
)
assert(files["/dl/news/feed/live.html.images/1.gif"] ~= nil, "process does not prune")
assert(plan and plan.keep and not next(plan.keep), "failed fetches yield empty keep")
Images.commitSidecar("/dl/news/feed/live.html", plan)
assert(files["/dl/news/feed/live.html.images/1.gif"] ~= nil, "empty keep leaves sidecar")
Settings.set("include_images", false)
_, plan = Images.process(
    '<img src="https://example.com/photo.gif"/>',
    "https://example.com/",
    "/dl/news/feed/live.html",
    function(s) return s end
)
assert(plan and plan.remove, "images-off returns remove plan")
assert(files["/dl/news/feed/live.html.images/1.gif"] ~= nil, "remove waits for commit")
Images.commitSidecar("/dl/news/feed/live.html", plan)
assert(files["/dl/news/feed/live.html.images/1.gif"] == nil, "commit removes sidecar")
Http.get = old_http
Settings.set("include_images", previous_images)

os.remove = saved_os_remove
package.loaded["libs/libkoreader-lfs"] = saved_lfs_koreader
package.loaded["lfs"] = saved_lfs
package.loaded["gettext"] = saved_gettext
print("Image storage cache: sidecar lifecycle, covers budget and staging sweep passed")
