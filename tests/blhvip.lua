package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end

-- The API hands the adapter JSON bodies; each body is a fixture key so the decode
-- stub below never has to parse anything (KOReader ships json, a bare LuaJIT does not).
local original_json = package.loaded["json"]
local FIXTURES = {
    search = { success = true, total = 3, total_page = 2, error_message = "", data = {
        { name = "Vô Địch Kiếm Vực", slug = "vo-dich-kiem-vuc", img_url = "https://cdn.blhvip.vn/vo-dich.jpg" },
        { name = "Kiếm Đạo Độc Thần", slug = "kiem-dao-doc-than" },
    } },
    search_last = { success = true, total = 3, total_page = 2, error_message = "", data = {
        { name = "Bạt Kiếm", slug = "bat-kiem" },
    } },
    chapters = { success = true, total_page = 2, error_message = "", data = {
        { ord = "1", name = "Chương 1: Gã quét rác.", is_vip = false,
            url = "/truyen/vo-dich-kiem-vuc/chuong-1" },
        { ord = "2", name = "Chương 2: Đánh cho đến chết.", is_vip = true,
            url = "/truyen/vo-dich-kiem-vuc/chuong-2" },
    } },
    -- The second page repeats chapter 2: it must be dropped, not duplicated.
    chapters_last = { success = true, total_page = 2, error_message = "", data = {
        { ord = "2", name = "Chương 2: Đánh cho đến chết.", is_vip = true,
            url = "/truyen/vo-dich-kiem-vuc/chuong-2" },
        { ord = "3", name = "Chương 3: Vòng xoáy đan điền.", is_vip = false,
            url = "/truyen/vo-dich-kiem-vuc/chuong-3" },
    } },
    repeat_page = { success = true, total_page = 5, error_message = "", data = {
        { ord = "1", name = "Chương 1", is_vip = false, url = "/truyen/vo-dich-kiem-vuc/chuong-1" } } },
}
package.loaded["json"] = {
    decode = function(body)
        if body == "not-json" then error("invalid JSON") end
        local endless = body:match("^endless:(%d+)$")
        if endless then
            return { success = true, total_page = 9999, error_message = "", data = {
                { ord = endless, name = "Chương " .. endless, is_vip = false,
                    url = "/truyen/vo-dich-kiem-vuc/chuong-" .. endless } } }
        end
        assert(FIXTURES[body], "unexpected JSON body: " .. tostring(body))
        return FIXTURES[body]
    end,
    encode = function() return "{}" end,
}

local B = require("booxbook.sources.blhvip")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Html = require("booxbook.html")
local Download = require("booxbook.novel-download")
local Source = require("booxbook.source")
-- source.lua is wired by the orchestrator; register here (and undo it at the end)
-- so Download.range is reachable without leaking a source into later tests.
local saved_adapter = Source.adapters[B.id]
Source.register(B)

assert(B.id == "blhvip" and B.name == "Bàn Long VIP" and B.kind == "novel", "adapter identity")
assert(B.capabilities.search and B.capabilities.browse and not B.capabilities.login, "capabilities")
assert(B.capabilities.adult == nil, "Bàn Long VIP lists no 18+ genre")

local original_get = Http.get
local calls, last_url, status = 0, nil, 200
local respond = function() return "" end
Http.get = function(url, opts)
    calls, last_url = calls + 1, url
    assert(opts.delay_ms >= 1600, "delay floor")
    assert(opts.referer == "https://blhvip.vn/", "referer is the site root")
    assert(opts.allow_url, "host allow list")
    assert(opts.allow_url("https://blhvip.vn/truyen/x"), "site host allowed")
    assert(opts.allow_url("https://api.blhvip.vn/v1/search?q=a"), "API host allowed")
    assert(not opts.allow_url("https://evil.test/truyen/x"), "foreign host blocked")
    if url:match("^https://api%.blhvip%.vn/") then
        assert(opts.headers.Accept == "application/json", "API asks for JSON")
    end
    return status == 200, status, respond(url)
end

-- parseRef: both hosts accepted, chapter and series told apart, junk refused.
assert(B.parseRef("https://blhvip.vn/truyen/vo-dich-kiem-vuc") == "vo-dich-kiem-vuc")
assert(B.parseRef("https://www.blhvip.vn/truyen/vo-dich-kiem-vuc?page=2") == "vo-dich-kiem-vuc")
assert(B.parseRef("/truyen/vo-dich-kiem-vuc/") == "vo-dich-kiem-vuc")
local slug, chapter_id = B.parseRef("https://api.blhvip.vn/truyen/vo-dich-kiem-vuc/chuong-1128#top")
assert(slug == "vo-dich-kiem-vuc" and chapter_id == "1128", "API host chapter ref")
assert(B.parseRef("https://evil.test/truyen/vo-dich-kiem-vuc") == nil, "foreign host rejected")
assert(B.parseRef("https://blhvip.evil.test/truyen/vo-dich-kiem-vuc") == nil, "lookalike host rejected")
assert(B.parseRef("/truyen/vo-dich-kiem-vuc/chuong-0") == nil, "chapter 0 rejected")
assert(B.parseRef("/truyen/vo-dich-kiem-vuc/chuong-abc") == nil, "non numeric chapter rejected")
assert(B.parseRef("/khac/vo-dich-kiem-vuc") == nil and B.parseRef("") == nil and B.parseRef(nil) == nil)
assert(not B.getSeries("https://evil.test/truyen/vo-dich-kiem-vuc") and calls == 0, "no request for foreign ref")
assert(not B.getSeries("https://blhvip.vn/truyen/vo-dich-kiem-vuc/chuong-1") and calls == 0,
    "a chapter URL is not a series ref")

local located, path = B.locate({ url = "https://blhvip.vn/truyen/vo-dich-kiem-vuc" })
assert(located == "vo-dich-kiem-vuc" and path == "vo-dich-kiem-vuc", "locate maps series to its folder")
located, path = B.locate({ url = "https://blhvip.vn/truyen/vo-dich-kiem-vuc/chuong-1" })
assert(located == "vo-dich-kiem-vuc" and path == nil, "a chapter ref has no series path")
local ref = { url = "https://blhvip.vn/truyen/vo-dich-kiem-vuc/chuong-3", series_id = "vo-dich-kiem-vuc" }
local ref_series, ref_id = B.chapterRef(ref)
assert(ref_series == "vo-dich-kiem-vuc" and ref_id == "3", "chapterRef pairs series and chapter")
ref.series_id = "khac"
assert(B.chapterRef(ref) == nil, "chapterRef refuses a chapter from another series")

-- search: percent-encoded query, cover, and has_more from the API's total_page.
respond = function() return "search" end
local found = assert(B.search("kiếm", 1))
assert(#found.items == 2 and found.items[1].ref == "/truyen/vo-dich-kiem-vuc", "search maps slugs to refs")
assert(found.items[1].title == "Vô Địch Kiếm Vực" and found.items[1].name == "Vô Địch Kiếm Vực")
assert(found.items[1].url == "https://blhvip.vn/truyen/vo-dich-kiem-vuc", "search builds the site URL")
assert(found.items[1].cover == "https://cdn.blhvip.vn/vo-dich.jpg", "search keeps the cover")
assert(found.has_more, "first search page has a next page")
assert(last_url == "https://api.blhvip.vn/v1/search?q=ki%E1%BA%BFm&page=1", "encoded query: " .. last_url)
respond = function() return "search_last" end
assert(not B.search("kiếm", 2).has_more, "last search page stops")
assert(not B.search("") and not B.search("   ") and not B.search(string.rep("a", 301)), "bad queries rejected")
assert(not B.search("kiếm", 0), "bad page rejected")
assert(calls == 2, "rejected input never reaches the network, calls=" .. calls)
respond = function() return "not-json" end
local items, err = B.search("kiếm", 1)
assert(not items and type(err) == "string" and err:find("Bàn Long VIP", 1, true), "malformed JSON is readable")

-- browse: cards, cover, pagination and the genre→/the-loai/<slug> mapping.
local CARD = '<div class="novel-item h-full p-4 bg-white">'
    .. '<a href="truyen/vo-dich-kiem-vuc" title="truyen/vo-dich-kiem-vuc" class="img shrink-0">'
    .. '<picture><img loading="lazy" src="https://cdn.blhvip.vn/vo-dich.jpg" '
    .. 'data-src="https://cdn.blhvip.vn/vo-dich.jpg" alt="Vô Địch"></picture></a>'
    .. '<div class="flex-1 content"><h3><a href="truyen/vo-dich-kiem-vuc" title="Vô Địch Kiếm Vực" '
    .. 'class="title font-bold line-clamp-1">Vô Địch &amp; Kiếm Vực</a></h3>'
    .. '<a href="truyen/vo-dich-kiem-vuc" class="author">Thanh Phong Loan</a></div></div>'
local NEXT_PAGE = '<a href="https://blhvip.vn/truyen-moi-nhat?page=2">2</a>'
respond = function() return CARD .. NEXT_PAGE end
local listed = assert(B.browse("latest", 1))
assert(#listed.items == 1 and listed.items[1].title == "Vô Địch Kiếm Vực", "card title comes from the link")
assert(listed.items[1].cover == "https://cdn.blhvip.vn/vo-dich.jpg", "card cover comes from data-src")
assert(listed.items[1].ref == "/truyen/vo-dich-kiem-vuc" and listed.has_more, "next page detected")
assert(last_url == "https://blhvip.vn/truyen-moi-nhat", "first page has no page parameter")
assert(not B.browse("latest", 3).has_more, "a page without its own next link stops")
assert(not B.browse("khong-co-danh-muc") and not B.browse("latest", 0), "bad browse input rejected")
respond = function() return "<html><body>chrome only</body></html>" end
assert(not B.browse("popular"), "unrecognized page 1 fails closed")
local genre_url
respond = function(url) genre_url = url; return CARD end
local genre_list = assert(B.browse("tien-hiep", 2))
assert(#genre_list.items == 1, "genre browse returns the cards")
assert(genre_url == "https://blhvip.vn/the-loai/tien-hiep?page=2", "genre key is the site slug: " .. genre_url)
genre_list = assert(B.browse("completed", 1))
assert(genre_url == "https://blhvip.vn/truyen-hoan-thanh", "completed list maps to its own path")
local seen_keys, seen_names = {}, {}
for _, entry in ipairs(B.genres) do
    assert(not seen_keys[entry.key], "duplicate genre key: " .. entry.key)
    assert(not seen_names[entry.name], "duplicate genre name: " .. entry.name)
    assert(entry.key:match("^[a-z0-9%-]+$"), "genre key must be URL-safe: " .. entry.key)
    assert(not entry.adult, "blhvip lists no 18+ genre: " .. entry.key)
    seen_keys[entry.key], seen_names[entry.name] = true, true
end
assert(seen_keys["tien-hiep"] and #B.genres > 40, "the site's genre list is wired")

-- getSeries: HTML metadata plus the paginated REST chapter list.
local STORY = [[<html><head>
<meta property="og:title" content="Vô Địch Kiếm Vực">
<meta property="og:image" content="https://blhvip.vn/uploads/cover/vo-dich-kiem-vuc.jpg">
</head><body>
<h1 class="name-story font-bold"><span class="prefix" style="color:#0000ff">[Dịch]</span> Vô Địch Kiếm Vực</h1>
<p class="text-info">Tác giả: <a href="tac-gia/thanh-phong-loan" title="Thanh Phong Loan">Thanh Phong Loan</a></p>
<ul class="tag my-2">
<li><a href="the-loai/huyen-huyen" title="Huyền Huyễn" class="block">Huyền Huyễn</a></li>
<li><a href="the-loai/kiem-hiep" title="Kiếm Hiệp" class="block">Kiếm Hiệp</a></li>
</ul>
<ul class="tag my-2"></ul>
<div class="tabcontent p-4 active" data-target="tab-info" id="tab-info-1">
<div class="s-content"><p>Dương Diệp &amp; Kiếm Tông ở Nam Vực.</p></div>
</div>
<ul class="tag"><li><a href="the-loai/huyen-huyen" title="Huyền Huyễn">Huyền Huyễn</a></li></ul>
</body></html>]]
respond = function(url)
    if url:match("^https://api%.blhvip%.vn/") then
        return url:find("page=2", 1, true) and "chapters_last" or "chapters"
    end
    return STORY
end
local series = assert(B.getSeries("/truyen/vo-dich-kiem-vuc"))
assert(series.id == "vo-dich-kiem-vuc" and series.source_id == "blhvip", "series identity")
assert(series.title == "Vô Địch Kiếm Vực", "title comes from og:title, not the [Dịch] heading")
assert(series.author == "Thanh Phong Loan", "author link")
assert(series.description == "Dương Diệp & Kiếm Tông ở Nam Vực.", "description decoded")
assert(series.cover:find("vo-dich-kiem-vuc.jpg", 1, true), "cover from og:image")
assert(#series.tags == 2 and series.tags[1] == "Huyền Huyễn", "tags come from ul.tag only")
assert(series.url == "https://blhvip.vn/truyen/vo-dich-kiem-vuc")
assert(#series.chapters == 3, "both pages read, duplicate dropped: " .. #series.chapters)
assert(series.chapters[1].id == "1" and series.chapters[2].id == "2" and series.chapters[3].id == "3")
assert(series.chapters[1].title == "Chương 1: Gã quét rác.", "chapter title from the API")
assert(series.chapters[2].locked and not series.chapters[3].locked, "is_vip marks a locked chapter")
assert(series.chapters[1].series_id == "vo-dich-kiem-vuc", "chapters carry their series")
assert(series.chapters[3].url == "https://blhvip.vn/truyen/vo-dich-kiem-vuc/chuong-3", "chapter URL")
assert(series.chapters[1].index == 1 and series.chapters[3].index == 3, "index is sequential")
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters, "one volume holds them all")
assert(not series.truncated, "a two page table of contents is complete")

-- A response that repeats the same page must fail instead of looping or lying.
respond = function(url) return url:match("^https://api%.blhvip%.vn/") and "repeat_page" or STORY end
assert(not B.getSeries("/truyen/vo-dich-kiem-vuc"), "a repeated page is refused")

-- A site that always claims another page stops at the page cap and keeps what it read.
local toc_calls = 0
respond = function(url)
    if url:match("^https://api%.blhvip%.vn/") then
        toc_calls = toc_calls + 1
        return "endless:" .. (tonumber(url:match("page=(%d+)")) or 1)
    end
    return STORY
end
local capped = assert(B.getSeries("/truyen/vo-dich-kiem-vuc"))
assert(capped.truncated, "endless table of contents is truncated, not spun forever")
assert(toc_calls <= 110, "table of contents stops at the page cap, calls=" .. toc_calls)
assert(#capped.chapters == toc_calls and #capped.chapters > 1, "the chapters already read are kept")
assert(not B.getSeries("https://blhvip.vn/truyen/vo-dich-kiem-vuc/chuong-1"), "series ref required")

-- getChapter: free text, VIP teaser and empty pages.
local FREE = '<div class="container chapter-content-container chapter-page-apply">'
    .. '<div class="s-content text-justify mt-4  published-content">'
    .. '<p>Kiếm tông, Huyền Không sơn.</p><script>bad()</script><p>Hai<br>Ba &amp; bốn</p>'
    .. '<style>.ads{}</style><iframe src="//x"></iframe></div></div>'
    .. '<div class="container chapter-page-apply"></div>'
respond = function() return FREE end
local content = assert(B.getChapter(series.chapters[1]))
assert(content.title == "Chương 1: Gã quét rác.", "chapter keeps the table of contents title")
assert(content.html:find("<p>Kiếm tông, Huyền Không sơn.</p>", 1, true), "paragraphs are rebuilt")
assert(content.html:find("Hai", 1, true) and content.html:find("Ba &amp; bốn", 1, true), "entities re-escaped")
assert(not content.html:find("bad", 1, true) and not content.html:find("ads", 1, true)
    and not content.html:find("iframe", 1, true), "script, style and iframe stripped")
assert(last_url == "https://blhvip.vn/truyen/vo-dich-kiem-vuc/chuong-1", "chapter fetched from the site")

local before = calls
assert(B.getChapter(series.chapters[2]).skipped, "a chapter flagged is_vip is skipped")
assert(calls == before, "a flagged chapter is skipped without a request")

local LOCKED = '<div class="s-content text-justify mt-4 content-lock published-content">Bầu trời Nguyên Môn.'
    .. '</div><div class="container chapter-page-apply"><div class="box-buy-chapter">'
    .. '<p>Cần 1.50 Linh Thạch để mở khóa chương này</p></div></div>'
respond = function() return LOCKED end
local locked = assert(B.getChapter(series.chapters[3]))
assert(locked.skipped and not locked.html, "a locked page is never saved as a teaser")
assert(locked.skipped:find("VIP", 1, true), "the skip reason is user readable: " .. tostring(locked.skipped))
respond = function() return '<div class="s-content  published-content">   </div>' end
assert(B.getChapter(series.chapters[3]).skipped, "empty chapter skips instead of aborting the range")
respond = function() return '<html><body>Captcha</body></html>' end
assert(B.getChapter(series.chapters[3]).skipped, "unparseable chapter page is skipped, not fatal")
status = 404
assert(B.getChapter(series.chapters[3]).skipped, "a missing chapter skips the range step")
status = 429
assert(not B.getChapter(series.chapters[3]), "429 is an error, not a skip")
status = 200
assert(not B.getChapter("/truyen/vo-dich-kiem-vuc/chuong-1"), "open the table of contents first")
assert(not B.getChapter({ url = "https://blhvip.vn/truyen/khac/chuong-1", series_id = "vo-dich-kiem-vuc" }),
    "a chapter from another series is refused")

-- Download: a locked chapter in the middle must not abort the range.
respond = function(url)
    if url:match("^https://api%.blhvip%.vn/") then
        return url:find("page=2", 1, true) and "chapters_last" or "chapters"
    end
    return url:find("/chuong-", 1, true) and FREE or STORY
end
local full = assert(B.getSeries("/truyen/vo-dich-kiem-vuc"))
local saved_html = Html.writeFile
local saved_dir, saved_ensure, saved_open = Settings.downloadDir, Settings.ensureDir, io.open
local writes = {}
Settings.downloadDir = function() return "test-output" end
Settings.ensureDir = function() return true end
Html.writeFile = function(target, body) writes[target] = body; return true end
io.open = function() return nil end
local result = assert(Download.range(full, 1, 3))
assert(not result.error and #result.saved == 2 and #result.skipped == 1, "locked chapter skipped, others saved")
assert(writes["test-output/novels/blhvip/vo-dich-kiem-vuc/ch-000000000001.html"], "chapter file written")
assert(writes["test-output/novels/blhvip/vo-dich-kiem-vuc/ch-000000000003.html"], "third chapter written")
assert(writes["test-output/novels/blhvip/vo-dich-kiem-vuc/index.json"], "index written")
Settings.downloadDir, Settings.ensureDir, Html.writeFile, io.open = saved_dir, saved_ensure, saved_html, saved_open
Source.adapters[B.id] = saved_adapter
Http.get, package.loaded["json"] = original_get, original_json
