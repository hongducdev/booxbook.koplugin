local M = require("booxbook.sources.metruyencv")
local C = require("booxbook.sources.metruyencv-crypto")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Html = require("booxbook.html")
local Download = require("booxbook.novel-download")
local original = { Http.get, package.loaded.json, C.signature, C.hash, C.decrypt,
    Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open }
local code, response, calls, last_url = 200, {}, 0
package.loaded.json = { decode = function(body)
    if body == "bad" then error("JSON") end
    return response
end, encode = function() return "{}" end }
-- Transport doubles exercise API contracts; real OpenSSL vectors are tested separately.
C.signature = function(path) assert(path:match("^books") or path:match("^chapters")); return "signature" end
C.hash = function() return "0123456789abcdef" end
C.decrypt = function(content, hash)
    assert(content == "encrypted" and hash == "0123456789abcdef")
    return "Tiếng Việt <&>\nDòng hai"
end
local responder
Http.get = function(url, opts)
    calls, last_url = calls + 1, url
    assert(opts.delay_ms >= 1600 and opts.headers["X-App"] == "MeTruyenChu")
    assert(opts.headers["X-Signature"] == "signature" and opts.referer == "https://metruyencv.com/")
    if responder then response = responder(url) end
    return code == 200, code, "json"
end
assert(M.refId("https://metruyencv.com/truyen/123", true) == "123")
assert(M.refId("https://metruyencv.com/truyen/123?utm=1", true) == "123")
assert(M.refId("https://metruyencv.com/truyen/chuong/11#frag") == "11")
for _, ref in ipairs({ "../1", "0", "1e3", "https://evil.test/truyen/1", "//evil/1" }) do
    assert(not M.getSeries(ref) and calls == 0)
end
assert(not M.search("") and not M.browse("bad") and not M.browse("latest", 0))
response = { success = true, data = { { id = 1, name = "Truyện" } }, pagination = { last = 2 } }
assert(M.search("tiếng Việt", 1).has_more and last_url:find("%20", 1, true))
assert(not M.browse("popular", 2).has_more and last_url:find("sort=-view_count", 1, true))
for i = 2, 20 do response.data[i] = { id = i, name = "Truyện" } end
assert(not M.browse("latest", 2).has_more, "full final page must stop")
response = { success = true, data = { false } }; assert(not M.browse())
local book = { id = 1, name = "Truyện", author = { name = "Tác giả" }, synopsis = "Tóm tắt",
    poster = { ["600"] = "https://example.com/cover.jpg" }, genres = { { name = "Tiên Hiệp" } } }
responder = function(url)
    if url:find("books/1", 1, true) then return { success = true, data = book } end
    if url:find("chapters?", 1, true) then
        local second = url:find("page=2", 1, true)
        return { success = true, pagination = { last = 2 }, data = second
            and { { id = 11, name = "Một", index = 1 } }
            or { { id = 12, name = "Hai", index = 2, is_vip = 1 } } }
    end
    return { success = true, data = { id = 11, book_id = 1, content = "encrypted" } }
end
local series = assert(M.getSeries("1"))
assert(#series.chapters == 2 and series.chapters[1].id == "11" and series.chapters[2].index == 2)
assert(series.author == "Tác giả" and series.tags[1] == "Tiên Hiệp" and series.description == "Tóm tắt")
local before = calls
assert(M.getChapter(series.chapters[2]).skipped and calls == before)
assert(M.getChapter(series.chapters[1]).html:find("&lt;&amp;&gt;", 1, true))
code = 401; assert(not M.getChapter(series.chapters[1]), "401 is signature failure, not skip")
code = 429; assert(not M.getChapter(series.chapters[1])); code = 200
local decrypt = C.decrypt; C.decrypt = function() error("padding") end
assert(not M.getChapter(series.chapters[1])); C.decrypt = decrypt
local writes = {}
Settings.downloadDir = function() return "test-output" end
Settings.ensureDir = function() return true end
Html.writeFile = function(path, body) writes[path] = body; return true end
io.open = function() return nil end
local result = assert(Download.range(series, 1, 2))
assert(#result.saved == 1 and #result.skipped == 1 and not result.error)
assert(writes["test-output/novels/metruyencv/1/ch-000000000011.html"])
assert(writes["test-output/novels/metruyencv/1/index.json"])
series.chapters[1].series_id = "2"
assert(Download.range(series, 1, 1).error)
-- A server repeating the same page must fail instead of looping or returning a partial TOC.
responder = function(url)
    if url:find("books/1", 1, true) then return { success = true, data = book } end
    return { success = true, pagination = { last = 3 }, data = { { id = 11, name = "Một", index = 1 } } }
end
assert(not M.getSeries("1"))
responder = nil
response = { success = true, data = { id = 11, book_id = 999, content = "encrypted" } }
series.chapters[1].series_id = "1"
assert(not M.getChapter(series.chapters[1]), "reject wrong book response")
response = { success = true, data = { id = 11, content = "encrypted" } }
assert(not M.getChapter(series.chapters[1]), "missing book_id is CHANGED")
code = 401
local failed = assert(Download.range(series, 1, 1))
assert(failed.error and #failed.saved == 0 and #failed.skipped == 0, "401 stops the download range")
code = 200
Http.get, package.loaded.json, C.signature, C.hash, C.decrypt = unpack(original, 1, 5)
Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open = unpack(original, 6, 9)
print("MeTruyenCV API, pagination, locked/error and download checks passed")
