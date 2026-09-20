-- TruyenC adapter: reference parsing, the story lists, the 18+ genre gate, the
-- single-page table of contents and chapter text.
package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path
local T = require("booxbook.sources.truyenc")
local H = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local original_get = H.get
local calls, body, code, last_url, last_referer = 0, "", 200, nil, nil
H.get = function(url, opts)
    calls, last_url, last_referer = calls + 1, url, opts.referer
    assert(opts.delay_ms >= 1600, "delay_ms must stay bounded")
    assert(type(opts.referer) == "string", "referer required")
    return code == 200, code, body
end

assert(T.id == "truyenc" and T.name == "TruyenC" and T.kind == "novel")
assert(T.capabilities.browse and not T.capabilities.search, "the site has no keyword search")
assert(T.capabilities.adult and not T.capabilities.login, "the 18+ sections are gated")
assert(T.view.base_url == "https://truyenc.com" and T.view.cover_referer == "https://truyenc.com/")
assert(T.view.cover_delay_ms == 1600)
assert(T.view.is_ref("https://truyenc.com/truyen/cam-tu-ky-bao-79"))
assert(T.view.is_ref("/truyen/cam-tu-ky-bao-79"))
assert(not T.view.is_ref("truyện ma"))
assert(#T.view.browse == 1 and T.view.browse[1].kind == "latest")

-- ---- parseRef: accept, reject, chapter-vs-series -------------------------
assert(T.parseRef("https://truyenc.com/truyen/cam-tu-ky-bao-79") == "cam-tu-ky-bao-79")
assert(T.parseRef("/truyen/cam-tu-ky-bao-79/") == "cam-tu-ky-bao-79")
assert(T.parseRef("https://truyenc.com/truyen/cam-tu-ky-bao-79?prev=chap-head-1") == "cam-tu-ky-bao-79")
local base, cid, cpath = T.parseRef("https://truyenc.com/truyen/cam-tu-ky-bao/chuong-1-gap-go-2440")
assert(base == "cam-tu-ky-bao" and cid == "2440")
assert(cpath == "/truyen/cam-tu-ky-bao/chuong-1-gap-go-2440")
local grouped, grouped_id = T.parseRef("https://truyenc.com/truyen/cuu-bien-lien/quyen-5-chuong-4-nguyet-2439")
assert(grouped == "cuu-bien-lien" and grouped_id == "2439", "a grouped chapter slug still ends in the id")
local series_only, no_chapter = T.parseRef("https://truyenc.com/truyen/cam-tu-ky-bao-79")
assert(series_only == "cam-tu-ky-bao-79" and no_chapter == nil)
assert(not T.parseRef("https://truyenc.com/truyen/cam-tu-ky-bao"), "the base slug is not a story URL")
assert(not T.parseRef("https://truyenc.com/tim-truyen-ma"), "a category is not a story")
assert(not T.parseRef("https://evil.test/truyen/cam-tu-ky-bao-79"))
assert(not T.parseRef("https://truyenc.com.evil.test/truyen/cam-tu-ky-bao-79"))
assert(not T.parseRef("/truyen/cam-tu-ky-bao/chuong-x"))
assert(not T.parseRef("/truyen/cam-tu-ky-bao/chuong-0"))
assert(not T.parseRef("/truyen/"))
assert(not T.parseRef(nil) and not T.parseRef(7) and not T.parseRef({}))
assert(T.locate{ url = "https://truyenc.com/truyen/cam-tu-ky-bao-79" } == "cam-tu-ky-bao-79")
local loc_id, loc_path = T.locate{ url = "https://truyenc.com/truyen/cam-tu-ky-bao/chuong-1-gap-go-2440" }
assert(loc_id == "cam-tu-ky-bao" and loc_path == nil, "a chapter ref has no series path")

-- ---- list cards and pagination (markup taken from the live site) ---------
local function card(slug, title, cover)
    return '<div class="d-flex"><div class="mr-3">'
        .. '<a href="https://truyenc.com/truyen/' .. slug .. '" title="' .. title .. '">'
        .. '<img class="fluid-img rounded-m shadow-xl story-image" src="' .. cover
        .. '" onerror="this.src=\'/static/images/thumb/2s.jpg\'" alt="' .. title .. '"/></a></div>'
        .. '<div><h6 class="color-highlight font-600 mb-1">'
        .. '<a href="https://truyenc.com/tim-truyen-ma" class="badge badge-danger" title="Truyện ma">Truyện ma</a></h6>'
        .. '<h2>Truyện ' .. title .. '</h2><p class="mt-2">Tóm tắt</p>'
        .. '<a href="https://truyenc.com/truyen/' .. slug .. '" class="btn btn-xs">Đọc truyện</a></div></div>'
end
local LIST = card("dau-thuong-den-chet-15", "Đau Thương", "https://i.truyenc.com/img/Dau thuong 15.jpg")
    .. card("cam-tu-ky-bao-79", "Cẩm Tú Kỳ Bào", "https://i.truyenc.com/img/cam-tu-ky-bao.jpg")
    .. '<div class="card card-full-left"><a href="https://truyenc.com/tim-truyen-ma">Thể loại</a></div>'
local PAGER = '<ul class="pagination justify-content-center">'
    .. '<li class="page-item"><a class="page-link" href="/tim-truyen-ma?page=4" title="Trang cuối">4</a></li>'
    .. '<li class="page-item"><a class="page-link" href="/tim-truyen-ma?page=2" title="Trang sau">»</a></li></ul>'
assert(not T.getSeries("https://evil.test/truyen/x-1") and calls == 0, "rejected refs cost no request")

body = LIST
local latest = assert(T.browse("latest", 1))
assert(last_url == "https://truyenc.com/", "the newest list is the home page")
assert(#latest.items == 2 and not latest.has_more, "no pagination markup means no next page")
assert(latest.items[1].title == "Đau Thương" and latest.items[1].name == "Đau Thương")
assert(latest.items[1].ref == "/truyen/dau-thuong-den-chet-15/")
assert(latest.items[1].url == "https://truyenc.com/truyen/dau-thuong-den-chet-15")
assert(latest.items[1].cover == "https://i.truyenc.com/img/Dau%20thuong%2015.jpg",
    "a cover file name with spaces is encoded")
assert(latest.items[2].cover == "https://i.truyenc.com/img/cam-tu-ky-bao.jpg")

body = LIST .. PAGER
local paged = assert(T.browse("tim-truyen-ma", 1))
assert(last_url == "https://truyenc.com/tim-truyen-ma", "page 1 has no ?page=")
assert(#paged.items == 2 and paged.has_more, "the pager announces page 2")
assert(#assert(T.browse("tim-truyen-ma", 3)).items == 2)
assert(last_url == "https://truyenc.com/tim-truyen-ma?page=3", "genre pages paginate")
-- On the last page the site points "Trang sau" back at itself: no page 5 exists.
body = LIST .. '<ul class="pagination"><li class="page-item"><a class="page-link" href="/tim-truyen-ma?page=4"'
    .. ' title="Trang sau">»</a></li></ul>'
assert(not assert(T.browse("tim-truyen-ma", 4)).has_more, "the last page has no next page")
assert(not T.browse("khong-co-the-loai"), "unknown list kind is rejected")
assert(not T.browse("latest", 0) and not T.browse("latest", 10001) and not T.browse("latest", 1.5))
body = '<html>Nội dung không tồn tại</html>'
assert(not T.browse("latest", 1), "an empty first page fails closed")
local empty = assert(T.browse("tim-truyen-ma", 2))
assert(#empty.items == 0 and not empty.has_more, "an empty later page is not an error")
body = '<html>Nội dung không tồn tại</html>'
assert(not T.getSeries("/truyen/cam-tu-ky-bao-79"), "a missing story fails closed")

-- ---- search: the site publishes none -------------------------------------
local search_calls = calls
local _, search_err = T.search("cẩm tú")
assert(search_err and search_err:find("không hỗ trợ", 1, true), search_err)
assert(calls == search_calls, "a disabled search costs no request")
assert(not T.search("") and not T.search(("x"):rep(301)))

-- ---- genres and the 18+ gate --------------------------------------------
local seen_keys, seen_names, adult = {}, {}, 0
for _, entry in ipairs(T.genres) do
    assert(not seen_keys[entry.key], "duplicate genre key: " .. entry.key)
    assert(not seen_names[entry.name], "duplicate genre name: " .. entry.name)
    assert(entry.key:match("^[a-z0-9%-]+$"), "genre key must be URL-safe: " .. entry.key)
    seen_keys[entry.key], seen_names[entry.name] = true, true
    if entry.adult then adult = adult + 1 end
end
assert(adult == 7, "the seven 18+ sections are flagged, got " .. adult)
assert(T.genres[1].key == "tim-truyen-ma" and not T.genres[1].adult)
local allowed = calls
assert(not T.browse("truyen-sex"), "adult genre blocked while 18+ is off")
assert(not T.browse("truyen-cuoi-18"), "every adult genre stays blocked")
assert(calls == allowed, "a blocked genre costs no request")
Settings.set("adult_content", true)
body = LIST
assert(#assert(T.browse("truyen-sex", 1)).items == 2, "adult genre allowed when 18+ is on")
assert(last_url == "https://truyenc.com/truyen-sex", "the genre path is the site's own")
Settings.set("adult_content", false)
assert(not T.browse("truyen-h"), "the gate closes again")
body = LIST

-- ---- getSeries: metadata, chapter order, volumes -------------------------
local function chapter_link(slug, id, title)
    return '<a href="https://truyenc.com/truyen/' .. slug .. '/' .. id .. '" title="' .. title
        .. '" class="story-chap-item" data-group="0" data-group-name="Mục lục">'
        .. '<span class="story-chap-name">' .. title .. '</span></a>'
end
local CHAPTER_LINKS = chapter_link("cam-tu-ky-bao", "chuong-3-ba-300", "Chương 3: Ba")
    .. chapter_link("cam-tu-ky-bao", "chuong-1-mot-100", "Chương 1: Một")
    .. chapter_link("cam-tu-ky-bao", "chuong-1-mot-100", "Chương 1: Một lần nữa")
    .. chapter_link("cam-tu-ky-bao", "chuong-2-hai-200", "Chương 2: Hai")
    .. chapter_link("cuu-bien-lien", "chuong-9-ngoai-999", "Chương của truyện khác")
    .. '<a href="https://truyenc.com/truyen/cam-tu-ky-bao/khong-phai-chuong">Linh tinh</a>'
local function story(newest_href, newest_title)
    return '<h1>Cẩm Tú Kỳ Bào</h1>'
        .. '<h3 class="h6">Tác giả: <b>Chu Nghiệp Á</b></h3>'
        .. '<p class="h6">Tình trạng: Hoàn thành</p>'
        .. '<img class="fluid-img rounded-m shadow-xl story-image" src="https://i.truyenc.com/img/cam tu ky bao.jpg"'
        .. ' alt="Cẩm Tú Kỳ Bào"/>'
        .. '<h6 class="color-highlight font-600 mb-1">'
        .. '<a href="https://truyenc.com/tim-truyen-ma" class="badge badge-danger mr-1 mb-1" title="Truyện ma">Truyện ma</a>'
        .. '<a href="https://truyenc.com/truyen-sex" class="badge badge-primary mr-1 mb-1" title="Truyện Sex">Truyện Sex</a>'
        .. '</h6>'
        .. '<meta property="og:description" content="Mô tả &amp; tóm tắt"/>'
        .. '<p class="mt-2 mb-2">Mới nhất: <a href="' .. newest_href .. '" title="' .. newest_title
        .. '">' .. newest_title .. '</a></p>'
        .. CHAPTER_LINKS
end
local STORY = story("https://truyenc.com/truyen/cam-tu-ky-bao/chuong-3-ba-300", "Chương 3: Ba")
body = STORY
local series = assert(T.getSeries("/truyen/cam-tu-ky-bao-79"))
assert(series.id == "cam-tu-ky-bao-79" and series.source_id == "truyenc")
assert(series.title == "Cẩm Tú Kỳ Bào" and series.url == "https://truyenc.com/truyen/cam-tu-ky-bao-79")
assert(series.author == "Chu Nghiệp Á")
assert(series.description == "Mô tả & tóm tắt", "entities are decoded")
assert(series.cover == "https://i.truyenc.com/img/cam%20tu%20ky%20bao.jpg")
assert(#series.chapters == 3, "duplicate ids are collapsed and other stories are ignored")
assert(series.chapters[1].id == "100" and series.chapters[2].id == "200" and series.chapters[3].id == "300")
assert(series.chapters[1].index == 1 and series.chapters[3].index == 3)
assert(series.chapters[1].series_id == "cam-tu-ky-bao-79", "chapters carry the folder id")
assert(series.chapters[1].title == "Chương 1: Một", "the anchor title is preferred over the duplicated span")
assert(series.chapters[1].url == "https://truyenc.com/truyen/cam-tu-ky-bao/chuong-1-mot-100")
assert(not series.truncated, "the newest chapter is in the table of contents")
assert(#series.tags == 1 and series.tags[1] == "Truyện ma", "an 18+ badge is not tagged while 18+ is off")
assert(#series.volumes == 1 and series.volumes[1].title == "Chương")
assert(#series.volumes[1].chapters == 3)
local sid, chapter_id = T.chapterRef(series.chapters[1])
assert(sid == "cam-tu-ky-bao-79" and chapter_id == "100")
local wrong_series = { url = series.chapters[1].url, series_id = "khac-1", title = "x" }
assert(not T.chapterRef(wrong_series), "a chapter from another series is refused")
assert(not T.chapterRef({ url = series.chapters[1].url }), "a chapter without a series is refused")

Settings.set("adult_content", true)
local with_adult = assert(T.getSeries("/truyen/cam-tu-ky-bao-79"))
assert(#with_adult.tags == 2, "the 18+ badge is tagged when 18+ is on")
Settings.set("adult_content", false)

-- A table of contents that stops before the newest chapter is marked partial.
body = story("https://truyenc.com/truyen/cam-tu-ky-bao/chuong-9-chin-900", "Chương 9: Chín")
assert(assert(T.getSeries("/truyen/cam-tu-ky-bao-79")).truncated, "a partial table of contents is flagged")
body = '<html>Truyện audio không có chương chữ</html>'
assert(not T.getSeries("/truyen/goi-quy-101"), "a story without text chapters is reported")
body = STORY

-- ---- getChapter ----------------------------------------------------------
local chapter = { url = "https://truyenc.com/truyen/cam-tu-ky-bao/chuong-1-mot-100",
    series_id = "cam-tu-ky-bao-79", title = "Chương 1: Một" }
body = '<h1><i class="color-red-dark mr-2">1</i> Chương 1: Một</h1><div class="story-content">'
    .. '<script>bad()</script><style>.ad{}</style>Dòng một &amp; hai<br/><br/>Dòng hai &lt;x&gt;<br/>Dòng ba</div>'
local content = assert(T.getChapter(chapter))
assert(content.title == "Chương 1: Một")
assert(last_url == "https://truyenc.com/truyen/cam-tu-ky-bao/chuong-1-mot-100")
assert(last_referer == "https://truyenc.com/truyen/cam-tu-ky-bao-79", "the story page is the referer")
assert(select(2, content.html:gsub("<p>", "")) == 3, "each line becomes a paragraph")
assert(content.html:find("<p>Dòng một &amp; hai</p>", 1, true), "text is kept and re-escaped")
assert(content.html:find("<p>Dòng hai &lt;x&gt;</p>", 1, true), "entities are decoded then re-escaped")
assert(not content.html:find("bad", 1, true), "scripts are stripped")
assert(not content.html:find("ad{", 1, true), "styles are stripped")
body = '<div class="story-content">   <br/>  </div>'
assert(T.getChapter(chapter).skipped, "an empty chapter skips instead of aborting the range")
body = '<div class="story-content"><p>Teaser</p><button>Mở khóa</button></div>'
assert(T.getChapter(chapter).skipped, "a lock button in the body skips")
body = '<html><div class="overlay-lock"></div></html>'
assert(T.getChapter(chapter).skipped, "a locked chapter page skips")
body = '<html>captcha only</html>'
assert(T.getChapter(chapter).skipped, "an unparseable chapter body is skipped")
code = 404
assert(T.getChapter(chapter).skipped, "a removed chapter skips")
code = 429
assert(not T.getChapter(chapter), "a rate limit is reported, not swallowed")
code = 200
body = '<div class="story-content">Nội dung</div>'
assert(not T.getChapter({ url = chapter.url, series_id = "khac-1", title = "x" }))
assert(not T.getChapter({ url = chapter.url, title = "x" }), "a chapter without a TOC is refused")
assert(not T.getChapter("https://truyenc.com/truyen/cam-tu-ky-bao/chuong-1-mot-100"))
assert(T.getChapter{ url = chapter.url, series_id = "cam-tu-ky-bao-79", title = "x", locked = true }
    .skipped == "Chương đã khóa.")
assert(not T.getChapter({ url = "https://truyenc.com/tim-truyen-ma", series_id = "tim-truyen-ma-1" }))

H.get = original_get
print("TruyenC references, lists, 18+ gate, table of contents and chapters passed")
