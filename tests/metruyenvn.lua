package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path
local M = require("booxbook.sources.metruyenvn")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local original = { Http.get, Http.post, package.loaded.json }
local body, code, calls, last_url, post_body, post_url = "", 200, 0, nil, nil, nil
local json_response = nil
local function stubGet(url, opts)
    calls = calls + 1
    assert(opts.delay_ms >= 1600, "pacing floor")
    assert(opts.referer == "https://metruyenvn.org/", "referer")
    last_url = url
    return code == 200, code, body
end
Http.get = stubGet
Http.post = function(url, request_body, opts)
    calls = calls + 1
    post_url, post_body = url, request_body
    assert(opts.delay_ms >= 1600 and opts.referer == "https://metruyenvn.org/")
    assert(opts.headers["X-Requested-With"] == "XMLHttpRequest")
    return code == 200, code, body
end
package.loaded.json = {
    decode = function(value) if json_response == nil then error("no json") end return json_response end,
    encode = function() return "{}" end,
}

assert(M.kind == "novel" and M.capabilities.search and M.capabilities.browse)
assert(M.view.base_url == "https://metruyenvn.org")
assert(M.view.is_ref("https://metruyenvn.org/truyen/truyen-a/") and M.view.is_ref("/truyen/truyen-a/"))
assert(not M.view.is_ref("truyện a"))
assert(#M.view.browse == 2 and M.view.browse[1].kind == "latest" and M.view.browse[2].kind == "completed")

assert(M.parseRef("https://metruyenvn.org/truyen/truyen-a/") == "truyen-a")
assert(M.parseRef("/truyen/truyen-a/?utm=1#x") == "truyen-a")
assert(M.parseRef("https://metruyenvn.org/truyen/truyen-a") == "truyen-a")
local series_ref, chapter_ref = M.parseRef("https://metruyenvn.org/chuong-28-62/")
assert(series_ref == nil and chapter_ref == "28-62", "chapter URL carries no series slug")
assert(M.parseRef("/chuong-12/") == nil)
assert(not M.parseRef("https://evil.test/truyen/truyen-a/"), "foreign host rejected")
assert(not M.parseRef("/truyen/") and not M.parseRef("truyện a") and not M.parseRef(nil))
local located, located_path = M.locate{ url = "https://metruyenvn.org/truyen/truyen-a/" }
assert(located == "truyen-a" and located_path == "truyen-a")

local cards = '<div class="comic-item-box">'
    .. '<div class="comic-img"><a href="https://metruyenvn.org/truyen/truyen-a/" title="Truyện A">'
    .. '<img class="img-thumbnail" src="https://img.test/a.webp"></a></div>'
    .. '<div class="comic-title-link"><a href="https://metruyenvn.org/truyen/truyen-a/" title="Truyện A">'
    .. '<h3 class="comic-title">Truyện A</h3></a></div></div>'
    .. '<div class="comic-item-box"><div class="comic-img">'
    .. '<a href="https://metruyenvn.org/truyen/truyen-b/" title="Truyện B"><img src="https://img.test/b.webp"></a>'
    .. '</div></div>'
    .. '<a href="/page/2/">2</a>'
body = cards
local listed = assert(M.browse("latest", 1))
assert(#listed.items == 2 and listed.has_more, "home page links to the next page")
assert(last_url == "https://metruyenvn.org/")
assert(listed.items[1].url == "https://metruyenvn.org/truyen/truyen-a/" and listed.items[1].cover == "https://img.test/a.webp")
body = cards:gsub('href="/page/2/"', 'href="/page/3/"')
local second = assert(M.browse("latest", 2))
assert(second.has_more and last_url == "https://metruyenvn.org/page/2/")
body = '<html>chrome only</html>'
assert(not M.browse("latest"), "empty listing page fails closed")
assert(not M.browse("bad") and not M.browse("latest", 0) and not M.browse("latest", 1001) and not M.browse("latest", "x"))
code = 500; assert(not M.browse("latest")); code = 200

body = '<ul class="most-views single-list-comic text-left hidden">'
    .. '<li class="position-relative"><img class="img-circle" src="https://img.test/c.webp">'
    .. '<p class="super-title"><a href="https://metruyenvn.org/truyen/truyen-c/">Truyện C</a></p></li></ul>'
local completed = assert(M.browse("completed", 1))
assert(#completed.items == 1 and completed.items[1].title == "Truyện C" and not completed.has_more)
assert(last_url == "https://metruyenvn.org/tron-bo/", "completed uses the tron-bo archive")

assert(type(M.genres) == "table" and #M.genres > 0, "genres are declared")
local seen_keys, seen_names, adult_key = {}, {}, nil
for _, genre in ipairs(M.genres) do
    assert(not seen_keys[genre.key], "duplicate genre key: " .. genre.key)
    assert(not seen_names[genre.name], "duplicate genre name: " .. genre.name)
    assert(genre.key:match("^[a-z0-9%-]+$"), "genre key must be URL-safe: " .. genre.key)
    assert(genre.name ~= "", "genre needs a label")
    seen_keys[genre.key], seen_names[genre.name] = true, true
    if genre.adult and not adult_key then adult_key = genre.key end
end
assert(adult_key, "at least one adult genre for the gating test")
body = cards
assert(#assert(M.browse("dam-my", 1)).items == 2)
assert(last_url == "https://metruyenvn.org/the-loai/dam-my/", "genre URL is the path segment")
assert(not M.browse("khong-co-the-loai"), "unknown genre rejected")
Settings.set("adult_content", false)
assert(not M.browse(adult_key), "adult genre blocked while 18+ is off")
Settings.set("adult_content", true)
body = cards
assert(#assert(M.browse(adult_key, 1)).items == 2, "adult genre allowed when 18+ is on")
Settings.set("adult_content", false)

json_response = { success = true, data = {
    { title = "Truyện A", img = "https://img.test/a.webp", link = "https://metruyenvn.org/truyen/truyen-a/" },
    { title = "Bỏ", img = "", link = "https://evil.test/truyen/x/" },
} }
local found = assert(M.search("truyện a"))
assert(#found.items == 1 and not found.has_more, "foreign search result dropped")
assert(post_url == "https://metruyenvn.org/wp-admin/admin-ajax.php")
assert(post_body == "action=searchtax&keyword=truy%E1%BB%87n%20a", "AJAX body: " .. tostring(post_body))
json_response = nil
body = cards
local fallback = assert(M.search("xuyen"), "AJAX failure falls back to /?s=")
assert(#fallback.items == 2 and not fallback.has_more)
assert(last_url == "https://metruyenvn.org/?s=xuyen")
assert(not M.search("") and not M.search(string.rep("x", 301)) and not M.search("a", 0) and not M.search("a", 1001))
json_response = { success = true, data = {} }
code = 500
assert(not M.search("x"), "both search paths down is an error")
code = 200

body = '<html><head><meta property="og:title" content="Truyện A - Mê Truyện - Đọc Truyện Đam Mỹ Hoàn"/>'
    .. '<meta property="og:image" content="https://img.test/a.webp"/></head><body>'
    .. '<h2 class="info-title">Truyện A</h2>'
    .. '<p class="comic-intro-text"><strong>Tác giả:</strong> <span> Tác Giả A </span><br><strong>Thể loại:</strong></p>'
    .. '<div class="desc-text">Tóm tắt A</div>'
    .. '<div class="tags margin-bottom-15px"><a href="https://metruyenvn.org/the-loai/dam-my/">dammy</a></div>'
    .. '<div class="table-wrapper chapter-table"><table><tbody>'
    .. '<tr><td><a class="text-capitalize" href="https://metruyenvn.org/chuong-2-99/">'
    .. '<span class="hidden-sm hidden-xs">Truyện A – Chương 2</span>'
    .. '<span class="hidden-lg hidden-md">Chương 2</span></a></td></tr>'
    .. '<tr><td><a class="text-capitalize" href="https://metruyenvn.org/chuong-1-90/">'
    .. '<span class="hidden-sm hidden-xs">Truyện A – Chương 1</span></a></td></tr>'
    .. '<tr><td><a class="text-capitalize" href="https://metruyenvn.org/chuong-1-90/">'
    .. '<span class="hidden-sm hidden-xs">Bản trùng</span></a></td></tr>'
    .. '</tbody></table></div></body></html>'
local series = assert(M.getSeries("https://metruyenvn.org/truyen/truyen-a/"))
assert(series.id == "truyen-a" and series.title == "Truyện A")
assert(series.author == "Tác Giả A" and series.description == "Tóm tắt A")
assert(series.cover == "https://img.test/a.webp" and series.tags[1] == "dammy")
assert(#series.chapters == 2, "duplicate chapter URL deduplicated")
assert(series.chapters[1].id == "1-90" and series.chapters[2].id == "2-99", "sorted by chapter number")
assert(series.chapters[1].title == "Truyện A – Chương 1" and series.chapters[2].index == 2)
assert(series.chapters[1].url == "https://metruyenvn.org/chuong-1-90/")
assert(series.chapters[1].series_id == "truyen-a")
assert(#series.volumes == 1 and #series.volumes[1].chapters == 2)
local chapter_series, chapter_id, max_id_len = M.chapterRef(series.chapters[1])
assert(chapter_series == "truyen-a" and chapter_id == "1-90" and max_id_len >= #chapter_id)
body = '<html>no chapter table</html>'
assert(not M.getSeries("/truyen/truyen-a/"))
assert(not M.getSeries("https://evil.test/truyen/truyen-a/"))

local chapter = series.chapters[1]
local head = '<a id="post-category-link" href="https://metruyenvn.org/truyen/truyen-a/"><span>Truyện A</span></a>'
body = head .. '<div class="none-shadow container"><div id="view-chapter" class="view-chapter">'
    .. '<p data-p-id="1">Tiếng Việt &amp; chữ</p><script>bad()</script><p>Dòng hai</p></div></div>'
local content = assert(M.getChapter(chapter))
assert(content.html:find("Tiếng Việt &amp; chữ", 1, true), "entities decoded then re-escaped")
assert(not content.html:find("bad", 1, true), "scripts stripped")
assert(content.html:find("Dòng hai", 1, true))
assert(content.title == chapter.title)
body = head .. '<div id="view-chapter" class="view-chapter">   </div>'
assert(M.getChapter(chapter).skipped, "empty chapter skips without aborting the range")
body = head .. '<div id="view-chapter" class="view-chapter"><form class="post-password-form"></form></div>'
assert(M.getChapter(chapter).skipped, "password protected chapter skips")
body = head .. '<div id="view-chapter" class="view-chapter"><p>   </p></div>'
assert(M.getChapter(chapter).skipped, "tag-only chapter skips")
code = 404; assert(M.getChapter(chapter).skipped, "404 skips")
code = 429; assert(not M.getChapter(chapter), "429 is an error, not a skip")
code = 200
body = '<a id="post-category-link" href="https://metruyenvn.org/truyen/truyen-b/"></a>'
    .. '<div id="view-chapter" class="view-chapter"><p>x</p></div>'
assert(not M.getChapter(chapter), "chapter served for another series is rejected")
body = '<div id="view-chapter" class="view-chapter"><p>x</p></div>'
assert(not M.getChapter(chapter), "missing series backlink is rejected")
assert(not M.getChapter("/chuong-1-90/"), "plain URL is not a chapter table")
assert(not M.getChapter({ url = "https://evil.test/chuong-1-90/", series_id = "truyen-a" }))
local locked = { url = chapter.url, series_id = "truyen-a", locked = true }
local before = calls
assert(M.getChapter(locked).skipped and calls == before, "locked flag skips before any request")
assert(not M.getChapter({ url = chapter.url }), "missing series_id is rejected")

Http.get, Http.post = original[1], original[2]
package.loaded.json = original[3]
Settings.set("adult_content", false)
