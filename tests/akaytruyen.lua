-- AkayTruyen adapter: reference parsing, the three homepage lists, search,
-- table of contents (fragment endpoint + full-page fallback) and chapter text.
package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path
local T = require("booxbook.sources.akaytruyen")
local Parser = require("booxbook.sources.akaytruyen-parser")
local H = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local original_get, original_json = H.get, package.loaded.json

assert(T.id == "akaytruyen" and T.kind == "novel" and T.capabilities.login == false)
assert(T.view.base_url == "https://akaytruyen.com" and T.view.cover_referer == "https://akaytruyen.com/")
assert(T.view.is_ref("https://akaytruyen.com/truyen/a/") and not T.view.is_ref("hai chu"))

-- ---- parseRef: accept, reject, chapter-vs-series -------------------------
assert(T.parseRef("https://akaytruyen.com/truyen/chung-cuc-truyen-ky/") == "chung-cuc-truyen-ky")
assert(T.parseRef("https://akaytruyen.com/truyen/chung-cuc-truyen-ky") == "chung-cuc-truyen-ky")
assert(T.parseRef("/truyen/chung-cuc-truyen-ky") == "chung-cuc-truyen-ky")
local book, cid, cpath = T.parseRef("https://akaytruyen.com/chung-cuc-truyen-ky/chuong-380-thuan-tien")
assert(book == "chung-cuc-truyen-ky" and cid == "chuong-380-thuan-tien")
assert(cpath == "/chung-cuc-truyen-ky/chuong-380-thuan-tien")
-- A series reference must not be mistaken for a chapter.
local only_book, no_chapter = T.parseRef("/truyen/chung-cuc-truyen-ky/")
assert(only_book == "chung-cuc-truyen-ky" and no_chapter == nil)
-- Foreign host, malformed paths and traversal must all be refused.
assert(not T.parseRef("https://evil.test/truyen/chung-cuc-truyen-ky/"))
assert(not T.parseRef("https://akaytruyen.evil.test/truyen/x/"))
assert(not T.parseRef("https://akaytruyen.com/truyen/"))
assert(not T.parseRef("https://akaytruyen.com/truyen/%2f/x"))
assert(not T.parseRef("/../x/") and not T.parseRef("/truyen/../x"))
assert(not T.parseRef(nil) and not T.parseRef({}))
local calls, body = 0, ""
H.get = function(url, opts)
    calls = calls + 1
    assert(opts.delay_ms >= 1600, "delay_ms must stay bounded")
    assert(type(opts.referer) == "string", "referer required")
    return true, 200, body
end
assert(not T.getSeries("https://evil.test/truyen/x/") and calls == 0)
assert(not T.getSeries("/truyen/x/chuong-1") and calls == 0)

-- ---- browse: the three homepage lists, one fetch ------------------------
local HOT = '<div class="section-stories-hot mb-3"><div class="container">'
    .. '<a href="https://akaytruyen.com/truyen/truyen-mot" class="d-block text-decoration-none">'
    .. '<img src="https://cdn.test/mot.jpg?v=1" alt="Truyện Một" class="story-cover">'
    .. '<h3 class="story-item__name text-one-row story-name">Truyện Một</h3>'
    .. '<span class="story-item__badge">Hot</span></a>'
    .. '<a href="https://akaytruyen.com/truyen/truyen-hai" class="d-block">'
    .. '<img src="https://cdn.test/hai.jpg" alt="Truyện Hai (Full)"></a>'
    .. '</div></div>'
local ONGOING = '<div class="section-stories-new"><div class="container">'
    .. '<a href="https://akaytruyen.com/truyen/truyen-mot" class="d-block">Truyện Một</a>'
    .. '<a href="https://akaytruyen.com/truyen/truyen-ba" class="d-block">Truyện Ba</a>'
    .. '</div></div>'
local COMPLETED = '<div class="section-stories-full"><div class="container">'
    .. '<a href="https://akaytruyen.com/truyen/truyen-ba" class="d-block">'
    .. '<img src="https://cdn.test/ba.jpg" alt="Truyện Ba"></a>'
    .. '</div></div><div id="id_feedback_button"></div>'
local HOMEPAGE = HOT .. ONGOING .. COMPLETED

-- A site that stopped publishing one of the lists must fail closed.
body = '<html><div class="section-stories-hot">chrome</div></html>'
assert(not T.browse("latest"), "missing sections must not return a partial list")
body = HOMEPAGE .. '<a href="/the-loai/tien-hiep">Tiên Hiệp</a>'
local latest = assert(T.browse("latest"))
assert(#latest.items == 2 and latest.has_more == false)
assert(latest.items[1].ref == "/truyen/truyen-mot/")
assert(latest.items[1].url == "https://akaytruyen.com/truyen/truyen-mot")
assert(latest.items[1].title == "Truyện Một" and latest.items[1].name == "Truyện Một")
assert(latest.items[1].cover == "https://cdn.test/mot.jpg?v=1")
assert(latest.items[2].title == "Truyện Hai", "trailing (Full) marker is stripped")
local ongoing = assert(T.browse("ongoing"))
assert(#ongoing.items == 2 and ongoing.items[1].cover == "https://cdn.test/mot.jpg?v=1",
    "cover is joined from the other homepage sections")
assert(ongoing.items[2].cover == "https://cdn.test/ba.jpg")
local completed = assert(T.browse("completed"))
assert(#completed.items == 1 and completed.items[1].title == "Truyện Ba")
assert(not T.browse("khong-co-kind") and not T.browse("latest", 0))

-- ---- genres: site slugs, no gating needed -------------------------------
local keys, names = {}, {}
for _, genre in ipairs(T.genres) do
    assert(not keys[genre.key], "duplicate genre key: " .. genre.key)
    assert(not names[genre.name], "duplicate genre name: " .. genre.name)
    assert(genre.key:match("^[a-z0-9%-]+$"), "genre key must be URL-safe: " .. genre.key)
    assert(genre.adult ~= true, "AkayTruyen publishes no 18+ topic: " .. genre.key)
    keys[genre.key], names[genre.name] = true, true
end
assert(#T.genres == 23 and keys["tien-hiep"] and keys["xuyen-khong"])
local genre_url
H.get = function(url, opts)
    genre_url = url
    assert(opts.delay_ms >= 1600 and type(opts.referer) == "string")
    return true, 200, HOT
end
local genre_list = assert(T.browse("tien-hiep", 2))
assert(#genre_list.items == 2)
assert(genre_url == "https://akaytruyen.com/the-loai/tien-hiep?page=2", "genre browse URL")
assert(T.browse("tien-hiep", 1) and genre_url == "https://akaytruyen.com/the-loai/tien-hiep")
assert(not T.browse("tien-hiep", 0))

-- ---- search: real form field, item extraction, pagination ----------------
local SEARCH = '<div class="list-story-in-category"><div class="story-item">'
    .. '<a href="https://akaytruyen.com/truyen/chung-cuc-truyen-ky" class="d-block">'
    .. '<img src="https://cdn.test/cuc.jpg" alt="Chung Cực Truyền Kỳ">'
    .. '<h3 class="story-name">Chung Cực Truyền Kỳ</h3></a></div></div>'
    .. '<a href="https://akaytruyen.com/tim-kiem?key_word=chung&amp;page=2">2</a>'
local search_url
H.get = function(url, opts)
    search_url = url
    assert(opts.delay_ms >= 1600 and type(opts.referer) == "string")
    return true, 200, SEARCH
end
local found = assert(T.search("chung cực"))
assert(#found.items == 1 and found.has_more == true)
assert(found.items[1].title == "Chung Cực Truyền Kỳ" and found.items[1].cover == "https://cdn.test/cuc.jpg")
assert(search_url == "https://akaytruyen.com/tim-kiem?key_word=chung%20c%E1%BB%B1c", search_url)
assert(T.search("chung", 2) and search_url:find("&page=2", 1, true))
assert(not T.search("") and not T.search(("x"):rep(301)) and not T.search("chung", 0))

-- ---- getSeries: fragment endpoint, fallback, order, dedup ---------------
local STORY = '<div class="col-12 col-lg-9">'
    .. '<h3 class="text-center story-name fw-bold">Chung Cực Truyền Kỳ</h3>'
    .. '<div class="story-detail__top--desc px-3"><p>Mô tả &amp; tóm tắt</p></div>'
    .. '<meta property="og:book:author" content="Ak&#9733;y">'
    .. '<meta property="og:image" content="https://cdn.test/cuc.jpg">'
    .. '<input type="number" class="jump-input input-paginate" placeholder="Trang" min="1" max="2">'
    .. '<div class="chapter-grid-mobile">'
    .. '<a href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-3-ba" class="chapter-link-mobile">'
    .. '<div class="chapter-number">Chương 3</div><div class="chapter-title">BA</div></a>'
    .. '<a href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-3-ba" class="chapter-link-desktop">'
    .. '<div class="chapter-number">Chương 3</div><div class="chapter-title">BA</div></a>'
    .. '<a href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-2-hai" class="chapter-link-mobile">'
    .. '<div class="chapter-number">Chương 2</div><div class="chapter-title">HAI</div></a>'
    .. '<a href="https://akaytruyen.com/truyen/chung-cuc-truyen-ky" class="d-block">Truyện</a>'
    .. '</div></div>'
local TOC2_FALLBACK = '<div class="chapter-grid-mobile">'
    .. '<a href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-1-mot" class="chapter-link-mobile">'
    .. '<div class="chapter-number">Chương 1</div><div class="chapter-title">MỘT</div></a>'
    .. '<a href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-2-hai" class="chapter-link-mobile">'
    .. '<div class="chapter-number">Chương 2</div><div class="chapter-title">HAI</div></a>'
    .. '</div>'
local FRAGMENT_422 = '{"message":"validation.required","errors":{"search":["validation.required"]}}'

-- Router for the fallback path: the fragment endpoint refuses an empty search,
-- so the table of contents must come from the paginated story pages.
local function serveFallback()
    local hits = {}
    H.get = function(url, opts)
        hits[#hits + 1] = url
        assert(opts.delay_ms >= 1600 and type(opts.referer) == "string")
        if url == "https://akaytruyen.com/truyen/chung-cuc-truyen-ky" then return true, 200, STORY end
        if url:find("search%-chapters") then return false, 422, FRAGMENT_422 end
        if url:find("%?page=2", 1) then return true, 200, TOC2_FALLBACK end
        return false, 404, ""
    end
    return hits
end

local toc_urls = serveFallback()
local series = assert(T.getSeries("https://akaytruyen.com/truyen/chung-cuc-truyen-ky/"))
assert(series.id == "chung-cuc-truyen-ky" and series.source_id == "akaytruyen")
assert(series.title == "Chung Cực Truyền Kỳ")
assert(series.description == "Mô tả & tóm tắt", "description entities decoded")
assert(series.author == "Ak★y", "author from og:book:author, numeric entity decoded")
assert(series.cover == "https://cdn.test/cuc.jpg")
assert(#series.chapters == 3, "mobile+desktop duplicate collapsed: " .. #series.chapters)
assert(series.chapters[1].id == "chuong-1-mot" and series.chapters[1].index == 1)
assert(series.chapters[3].id == "chuong-3-ba" and series.chapters[3].index == 3)
assert(series.chapters[1].title == "Chương 1: MỘT" and series.chapters[2].series_id == "chung-cuc-truyen-ky")
assert(series.chapters[1].url == "https://akaytruyen.com/chung-cuc-truyen-ky/chuong-1-mot")
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters)
assert(toc_urls[2]:find("search%-chapters"), "fragment endpoint is tried first: " .. tostring(toc_urls[2]))
assert(toc_urls[3] == "https://akaytruyen.com/truyen/chung-cuc-truyen-ky?page=2",
    "unusable fragment falls back to the full story page: " .. tostring(toc_urls[3]))
assert(not T.getSeries("/truyen/chung-cuc-truyen-ky/chuong-1-mot"), "chapter ref is not a series")

-- When the fragment endpoint does answer, its chapters are used and no full
-- page is fetched for that page.
package.loaded.json = { decode = function(payload)
    local html = payload:match('"html"%s*:%s*"(.-)"%s*,%s*"search_type"')
    if not html then return {} end
    html = html:gsub("\\/", "/"):gsub('\\"', '"'):gsub("\\n", "\n")
    return { html = html, has_more = payload:match('"has_more"%s*:%s*(%a+)') == "true" }
end }
local fragment_toc = '<a href="https://akaytruyen.com/chung-cuc-truyen-ky/chuong-1-mot" class="chapter-link-mobile">'
    .. '<div class="chapter-number">Chương 1</div><div class="chapter-title">MỘT</div></a>'
local FRAGMENT_OK = '{"html":"' .. fragment_toc:gsub("/", "\\/") .. '","search_type":"text","has_more":false}'
local fragment_hits = {}
H.get = function(url, opts)
    fragment_hits[#fragment_hits + 1] = url
    assert(opts.delay_ms >= 1600 and type(opts.referer) == "string")
    if url == "https://akaytruyen.com/truyen/chung-cuc-truyen-ky" then return true, 200, STORY end
    if url:find("search%-chapters") then return true, 200, FRAGMENT_OK end
    return false, 404, ""
end
local fragment_series = assert(T.getSeries("/truyen/chung-cuc-truyen-ky/"))
assert(#fragment_series.chapters == 3)
for _, url in ipairs(fragment_hits) do
    assert(not url:find("%?page=2", 1, true), "fragment page 2 avoids a full-page fetch")
end
package.loaded.json = original_json

-- ---- getChapter: content, entities, script stripping, locks -------------
serveFallback()
local chapter = assert(T.getSeries("/truyen/chung-cuc-truyen-ky/")).chapters[1]
assert(chapter.locked == nil and chapter.series_id == "chung-cuc-truyen-ky")
H.get = function(url, opts)
    assert(opts.delay_ms >= 1600 and type(opts.referer) == "string")
    return true, 200, body
end
body = '<h1 class="text-center custom-text"><b>Chương 1: MỘT</b></h1>'
    .. '<div id="chapter-content" class="chapter-content mb-4"><p>Tiếng Việt &amp; chữ</p>'
    .. '<script>bad()</script><style>.x{}</style><p>&#7871; Đồng</p></div>'
    .. '<div class="chapter-nav">next</div>'
local content = assert(T.getChapter(chapter))
assert(content.title == "Chương 1: MỘT")
assert(content.html:find("<p>Tiếng Việt &amp; chữ</p>", 1, true))
assert(content.html:find("<p>ế Đồng</p>", 1, true), "numeric entities decoded")
assert(not content.html:find("bad", 1, true), "script body stripped")
assert(not content.html:find("chapter%-nav"), "trailing chrome is not part of the chapter")

Settings.set("akaytruyen_cookie", "akay_sess=abc")
local seen_cookie
H.get = function(url, opts)
    seen_cookie = opts.cookies
    return true, 200, body
end
assert(T.getChapter(chapter).html)
assert(seen_cookie == "akay_sess=abc", "stored session cookie is sent when present")
Settings.set("akaytruyen_cookie", "")

H.get = function() return true, 200, body end
body = '<h1>Chương VIP</h1><div class="access-denied-container">Chương này dành cho tài khoản VIP</div>'
assert(T.getChapter(chapter).skipped == "Chương cần đăng nhập.")
body = '<h1>Chương VIP</h1><div id="chapter-content">Teaser</div><p>Chương này dành cho tài khoản VIP</p>'
assert(T.getChapter(chapter).skipped == "Chương cần đăng nhập.", "VIP wall is skipped, not fatal")
body = '<h1>Chương 1</h1><div id="chapter-content">   </div>'
assert(T.getChapter(chapter).skipped, "blank chapter skips instead of aborting the range")
body = '<html>captcha only</html>'
assert(T.getChapter(chapter).skipped, "unparseable chapter body is skipped")

H.get = function() return false, 404, "" end
assert(T.getChapter(chapter).skipped, "removed chapter is skipped")
H.get = function() return false, 429, "" end
assert(not T.getChapter(chapter), "rate limit is reported, not swallowed")
local wrong = { id = chapter.id, series_id = "other", url = chapter.url }
assert(not T.getChapter(wrong), "chapter from another series is refused")
local locked_chapter = { id = chapter.id, series_id = chapter.series_id, url = chapter.url, locked = true }
assert(T.getChapter(locked_chapter).skipped == "Chương đã khóa.")
assert(not T.getChapter({ id = chapter.id, url = chapter.url }), "chapter without a TOC is refused")

H.get = original_get
print("AkayTruyen refs, homepage lists, genres, search, TOC fallback and chapter locks passed")
