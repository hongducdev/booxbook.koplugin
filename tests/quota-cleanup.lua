local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local saved_lfs_koreader = package.loaded["libs/libkoreader-lfs"]
local saved_lfs = package.loaded["lfs"]
local saved_os_remove = os.remove
local saved_os_time = os.time

local Settings = require("booxbook.store.settings")
assert(Settings.get("quota_news_mb") == 300, "news quota default")
assert(Settings.get("quota_received_mb") == 500, "received quota default")
assert(Settings.get("quota_novels_mb") == 0, "novels quota disabled by default")
assert(Settings.get("quota_comics_mb") == 0, "comics quota disabled by default")
assert(Settings.get("quota_novels_evict") == false, "novel eviction opt-in default")
assert(Settings.get("quota_comics_evict") == false, "comic eviction opt-in default")

local dirs, files = {}, {}

local function basename(path)
    return path:match("[^/]+$")
end

local function ensureDir(path)
    if not path or path == "" or dirs[path] then return end
    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= "" then ensureDir(parent) end
    dirs[path] = {}
    if parent and parent ~= "" and dirs[parent] then
        dirs[parent][basename(path)] = true
    end
end

local function addFile(path, size, mtime)
    local parent = path:match("^(.*)/[^/]+$")
    ensureDir(parent)
    files[path] = { size = size or 1, mtime = mtime or 0 }
    dirs[parent][basename(path)] = true
end

local fake_lfs = {
    dir = function(path)
        if not dirs[path] then error("no such dir") end
        local names = {}
        for name in pairs(dirs[path]) do names[#names + 1] = name end
        table.sort(names)
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
    mkdir = function(path)
        ensureDir(path)
        return true
    end,
    rmdir = function(path)
        if dirs[path] and not next(dirs[path]) then
            local parent = path:match("^(.*)/[^/]+$")
            dirs[path] = nil
            if parent and parent ~= "" and dirs[parent] then
                dirs[parent][basename(path)] = nil
            end
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
        if parent and dirs[parent] then dirs[parent][basename(path)] = nil end
        return true
    end
    if dirs[path] and not next(dirs[path]) then
        return true
    end
    return nil
end

local now = 2000000000
os.time = function() return now end

package.loaded["booxbook.store.storage"] = nil
local Storage = require("booxbook.store.storage")

addFile("/size/news/feed/a.html", 10, 300)
addFile("/size/news/feed/a.html.images/1.jpg", 5, 301)
local bytes, count = Storage.categorySize("/size/news")
assert(bytes == 15 and count == 2, "category size sums nested files")

addFile("/fifo/news/old.html", 60, 100)
addFile("/fifo/news/mid.html", 60, 200)
addFile("/fifo/news/new.html", 60, 300)
local freed, remaining = Storage.trimCategoryFifo("/fifo/news", 100, true)
assert(freed == 120 and remaining == 60, "news FIFO trims oldest files first")
assert(files["/fifo/news/old.html"] == nil, "news oldest deleted")
assert(files["/fifo/news/mid.html"] == nil, "news second-oldest deleted")
assert(files["/fifo/news/new.html"] ~= nil, "news newest retained")

addFile("/fifo/received/old.epub", 80, 100)
addFile("/fifo/received/newer.epub", 80, 200)
addFile("/fifo/received/newest.epub", 80, 300)
freed, remaining = Storage.trimCategoryFifo("/fifo/received", 160, true)
assert(freed == 80 and remaining == 160, "received FIFO trims only enough to fit")
assert(files["/fifo/received/old.epub"] == nil, "received oldest deleted")
assert(files["/fifo/received/newer.epub"] ~= nil, "received newer retained")
assert(files["/fifo/received/newest.epub"] ~= nil, "received newest retained")

addFile("/safe/novels/old.epub", 200, 100)
addFile("/safe/novels/new.epub", 200, 200)
freed, remaining = Storage.trimCategoryFifo("/safe/novels", 1, false)
assert(freed == 0 and remaining == 400, "novel eviction disabled returns current size")
assert(files["/safe/novels/old.epub"] ~= nil and files["/safe/novels/new.epub"] ~= nil,
    "novel files never deleted without opt-in")

addFile("/safe/comics/source/series/old.cbz", 200, 100)
addFile("/safe/comics/source/series/new.cbz", 200, 200)
freed, remaining = Storage.trimCategoryFifo("/safe/comics", 1, false)
assert(freed == 0 and remaining == 400, "comic eviction disabled returns current size")
assert(files["/safe/comics/source/series/old.cbz"] ~= nil
    and files["/safe/comics/source/series/new.cbz"] ~= nil,
    "comic files never deleted without opt-in")

local two_mb = 2 * 1024 * 1024
addFile("/maint/news/old.html", two_mb, 100)
addFile("/maint/news/new.html", two_mb, 200)
addFile("/maint/received/old.epub", two_mb, 100)
addFile("/maint/received/new.epub", two_mb, 200)
addFile("/maint/novels/old.epub", two_mb, 100)
addFile("/maint/comics/source/series/old.cbz", two_mb, 100)
local settings = {
    quota_news_mb = 3,
    quota_received_mb = 3,
    quota_novels_mb = 1,
    quota_comics_mb = 1,
    quota_novels_evict = false,
    quota_comics_evict = false,
}
local stats = Storage.runGlobalMaintenance("/maint", function(key) return settings[key] end)
assert(stats.quotas.news.freed == two_mb and files["/maint/news/old.html"] == nil
    and files["/maint/news/new.html"] ~= nil, "maintenance enforces news quota FIFO")
assert(stats.quotas.received.freed == two_mb and files["/maint/received/old.epub"] == nil
    and files["/maint/received/new.epub"] ~= nil, "maintenance enforces received quota FIFO")
assert(files["/maint/novels/old.epub"] ~= nil, "maintenance does not evict novels without opt-in")
assert(files["/maint/comics/source/series/old.cbz"] ~= nil, "maintenance does not evict comics without opt-in")

addFile("/digests/received/digest-old.epub", 1, now - 31 * 86400)
addFile("/digests/received/digest-new.epub", 1, now - 10 * 86400)
addFile("/digests/received/article.epub", 1, now - 90 * 86400)
local swept = Storage.sweepStaleDigests("/digests/received", 30)
assert(swept == 1, "only stale digest epub is swept")
assert(files["/digests/received/digest-old.epub"] == nil, "old digest deleted")
assert(files["/digests/received/digest-new.epub"] ~= nil, "fresh digest kept")
assert(files["/digests/received/article.epub"] ~= nil, "non-digest epub kept")

addFile("/parts/news/orphan.part", 1, now - 90000)
addFile("/parts/news/active.part", 1, now - 100)
addFile("/parts/news/old.tmp", 1, now - 90000)
addFile("/parts/received/deep/stale.part", 1, now - 90000)
swept = Storage.sweepOrphanParts("/parts")
assert(swept == 2, "stale .part files swept recursively")
assert(files["/parts/news/orphan.part"] == nil, "old .part deleted")
assert(files["/parts/received/deep/stale.part"] == nil, "nested old .part deleted")
assert(files["/parts/news/active.part"] ~= nil, "active .part kept for resumption")
assert(files["/parts/news/old.tmp"] ~= nil, "non-part file kept")

os.remove = saved_os_remove
os.time = saved_os_time
package.loaded["libs/libkoreader-lfs"] = saved_lfs_koreader
package.loaded["lfs"] = saved_lfs
package.loaded["booxbook.store.storage"] = nil

print("Quota cleanup tests passed")
