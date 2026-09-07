local names = { "gettext", "ffi/archiver", "booxbook.comic-download", "booxbook.comic-cbz" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
package.loaded.gettext = function(s) return s end
package.loaded["booxbook.comic-download"], package.loaded["booxbook.comic-cbz"] = nil, nil
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local old_get, old_download, old_dir, old_ensure = Http.get, Http.downloadToFile, Settings.downloadDir, Settings.ensureDir
local old_open, old_remove, old_rename = io.open, os.remove, os.rename
-- Use real temporary files; map the test's virtual directory for portable LuaJIT tests.
local paths = {}
local function mapped(path)
    if path:sub(1, 7) ~= "@comic/" then return path end
    if not paths[path] then paths[path] = os.tmpname(); old_remove(paths[path]) end
    return paths[path]
end
io.open = function(path, mode) return old_open(mapped(path), mode) end
os.remove = function(path) return old_remove(mapped(path)) end
os.rename = function(a, b) return old_rename(mapped(a), mapped(b)) end
Settings.downloadDir = function() return "@comic" end
Settings.ensureDir = function() return true end
local entries, fail_pack, fail_verify = {}, false, false
-- Archive boundary double permits deterministic disk/CRC failure injection.
package.loaded["ffi/archiver"] = {
    Writer = { new = function() return {
        open = function(self, path, format)
            assert(format == "zip"); entries = {}; self.file = assert(io.open(path, "wb")); return true
        end,
        setZipCompression = function(self, mode) assert(mode == "store"); return true end,
        addFileFromMemory = function(self, name, data)
            if fail_pack then self.err = "disk full"; return nil end
            entries[#entries + 1] = { path = name, size = #data, mode = "file", data = data }
            assert(self.file:write(data)); return true
        end,
        close = function(self)
            if self.file then self.file:write("PK\5\6" .. string.rep("\0", 18)); self.file:close(); self.file = nil end
            self.err = nil
        end,
    } end },
    Reader = { new = function() return {
        open = function() return true end,
        iterate = function() local i = 0; return function() i = i + 1; return entries[i] end end,
        extractToMemory = function(self, name)
            if fail_verify then self.err = "CRC error"; return nil end
            for _, entry in ipairs(entries) do if entry.path == name then return entry.data end end
        end,
        close = function() end,
    } end },
}
local Download = require("booxbook.comic-download")
local url = "https://truyentuoitho.com/manga/test/tap-1/"
local image = "RIFF" .. string.char(8, 0, 0, 0) .. "WEBP" .. "data"
local request_count, fail_page, response = 0, 2, image
Http.get = function() return true, 200,
    '<div class="reading-content"><img src="/1.webp"><img src="/2.webp"></div>' end
Http.downloadToFile = function(u, path, opts)
    request_count = request_count + 1
    assert(opts.referer == url and opts.max_body <= Download.MAX_IMAGE)
    assert(opts.allow_url(u) and not opts.allow_url("http://127.0.0.1/a"))
    if fail_page and u:find("/" .. fail_page .. ".webp", 1, true) then return false, 429 end
    local file = assert(io.open(path, "wb")); assert(file:write(response)); assert(file:close())
    return true, 200, "", { ["Content-Length"] = tostring(#response) }
end
local path, err = Download.chapter(url)
assert(not path and err:find("429") and request_count == 2)
local staging = "@comic/comics/truyentuoitho/test/.tap-1-pages/"
local page1 = assert(io.open(staging .. "0001", "rb")); assert(page1:read("*a") == image); page1:close()
assert(not io.open("@comic/comics/truyentuoitho/test/tap-1.cbz", "rb"), "partial chapter never published")
fail_page, request_count = nil, 0
path = assert(Download.chapter(url))
assert(request_count == 1 and #entries == 2, "resume only missing pages")
assert(entries[1].path == "0001.webp" and entries[2].path == "0002.webp", "stable page ordering")
assert(not io.open(staging .. "0001", "rb"), "staging removed after success")
assert(Download.chapter(url) == path and request_count == 1, "existing book reused without image requests")
os.remove(path)
request_count = 0
assert(not Download.chapter(url, function() return false end) and request_count == 0, "cancel before first image")
response = "<html>not an image</html>"
assert(not Download.chapter(url), "HTTP 200 HTML is not an image")
response = image:sub(1, -2)
assert(not Download.chapter(url), "truncated WebP rejected")
response, fail_pack = image, true
assert(not Download.chapter(url), "packing failure propagates")
assert(not io.open(path, "rb") and io.open(staging .. "0001", "rb"):close(), "packing failure preserves pages")
fail_pack, fail_verify = false, true
assert(not Download.chapter(url), "CRC failure prevents publish")
fail_verify, request_count = false, 0
assert(Download.chapter(url) == path and request_count == 0, "retry packaging uses complete pages")
os.remove(path)
local original_limit = Download.MAX_TOTAL
Download.MAX_TOTAL = #image
assert(not Download.chapter(url), "chapter byte budget enforced")
Download.MAX_TOTAL = original_limit
local series = { id = "test", chapters = {
    { url = url, title = "Tập 1" },
    { url = "https://truyentuoitho.com/manga/test/tap-2/", title = "Tập 2" },
} }
local result = assert(Download.range(series, 1, 2, function(n) return n == 1 end))
assert(#result.saved == 1 and result.error, "cancel range preserves completed CBZ")
local before = request_count
result = assert(Download.range(series, 1, 1))
assert(#result.saved == 1 and request_count == before, "range skips cached CBZ")
assert(Download.savedPath(url) == path, "offline lookup verifies existing archive")
assert(not Download.range(series, 0, 1) and not Download.range(series, 1, 3))
series.chapters[2].url = "https://truyentuoitho.com/manga/other/tap-2/"
result = Download.range(series, 1, 2)
assert(#result.saved == 1 and result.error, "foreign chapter rejected before HTTP")
for _, actual in pairs(paths) do old_remove(actual) end
io.open, os.remove, os.rename = old_open, old_remove, old_rename
Http.get, Http.downloadToFile = old_get, old_download
Settings.downloadDir, Settings.ensureDir = old_dir, old_ensure
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Comic download: real file staging, resume, cancel, invalid images, archive errors and limits passed")
