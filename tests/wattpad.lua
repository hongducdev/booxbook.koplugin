local W = require("booxbook.sources.wattpad")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Html = require("booxbook.html")
local Download = require("booxbook.novel-download")
local original = { Http.get, package.loaded.json, Settings.adultContent(), Settings.cookie("wattpad"),
    Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open }
local data, body, code, calls, last_url = {}, nil, 200, 0
package.loaded.json = { decode = function(value)
    if value == "bad" then error("invalid JSON") end
    return data
end, encode = function() return "{}" end }
Settings.set("adult_content", false)
Settings.setCookie("wattpad", "test-session")
Http.get = function(url, opts)
    calls, last_url = calls + 1, url
    assert(opts.cookies == "test-session" and opts.delay_ms >= 1500)
    assert(opts.referer == "https://www.wattpad.com/")
    return code == 200, code, body or "json"
end
assert(W.refId("https://www.wattpad.com/story/1134042-title", true) == "1134042")
assert(W.refId("https://wattpad.com/3875397-title", false) == "3875397")
for _, ref in ipairs({ "https://evil.test/story/1", "//evil.test/story/1", "../1", "1oops", "0", "1e5" }) do
    assert(not W.refId(ref, true))
end
assert(not W.getSeries("https://evil.test/story/1") and calls == 0)
data = { stories = { { id = "1", title = "Public", mature = false },
    { id = "2", title = "Adult", mature = true }, { id = "3", title = "Unknown" } } }
assert(#assert(W.search("tiếng Việt", 2)).items == 1)
assert(last_url:find("offset=20", 1, true) and last_url:find("%20", 1, true))
assert(not W.search("", 1) and not W.browse("hot", 0))
assert(W.browse("featured") and last_url:find("filter=featured", 1, true))
assert(W.browse("new") and last_url:find("filter=new", 1, true))
data.stories = {}
for i = 1, 20 do data.stories[i] = { id = tostring(i), title = "Adult", mature = true } end
local hidden = assert(W.browse("hot")); assert(#hidden.items == 0 and hidden.has_more)
body = "bad"; assert(not W.search("x")); body = nil
data = { stories = { false } }; assert(not W.search("x"))
data = { id = "1134042", title = "Public", mature = false, parts = {
    { id = 3875397, title = "Chapter" }, { id = 2, title = "Draft", draft = true },
    { id = 3, title = "Deleted", deleted = true }, { id = 4, title = "Paid", paid = true } } }
local series = assert(W.getSeries("1134042"))
assert(#series.chapters == 2 and series.chapters[2].index == 2 and series.source_id == "wattpad")
data.mature = true; assert(not W.getSeries("1134042")); data.mature = false
local before = calls
assert(W.getChapter(series.chapters[2]).skipped and calls == before)
body = '<p>Hello &amp; Tiếng Việt <a href="javascript:bad()">text</a></p><script>bad()</script>'
local content = assert(W.getChapter(series.chapters[1]))
assert(content.html == '<p>Hello &amp; Tiếng Việt text</p>')
body = '<div class="paywall"><p>Buy coins</p></div>'; assert(W.getChapter(series.chapters[1]).skipped)
body = ''; assert(W.getChapter(series.chapters[1]).skipped)
body = '<html><p>Login</p></html>'; assert(not W.getChapter(series.chapters[1]))
code = 403; assert(not W.getChapter(series.chapters[1]))
code = 429; assert(not W.getChapter(series.chapters[1]))
code = 404; assert(W.getChapter(series.chapters[1]).skipped)
code, body = 200, '<p>Tiếng Việt</p>'
local writes = {}
Settings.downloadDir = function() return "test-output" end
Settings.ensureDir = function(path) assert(path == "test-output/novels/wattpad/1134042"); return true end
io.open = function() return nil, "not found", 2 end
Html.writeFile = function(path, text) writes[path] = text; return true end
local result = assert(Download.range(series, 1, 2))
assert(#result.saved == 1 and #result.skipped == 1)
assert(writes['test-output/novels/wattpad/1134042/ch-000003875397.html']:find('Tiếng Việt', 1, true))
assert(writes['test-output/novels/wattpad/1134042/index.json'])
series.chapters[1].series_id = "999"
assert(Download.range(series, 1, 1).error)
Http.get, package.loaded.json = original[1], original[2]
Settings.set("adult_content", original[3]); Settings.setCookie("wattpad", original[4])
Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open = original[5], original[6], original[7], original[8]
print("Wattpad adapter/download checks passed")
