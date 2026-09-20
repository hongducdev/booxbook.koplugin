package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path

package.loaded["libs/libkoreader-lfs"] = package.loaded["libs/libkoreader-lfs"]
    or { symlinkattributes = function() return nil end, attributes = function() return nil end }
package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end
package.loaded["json"] = package.loaded["json"] or { decode = function() return nil end, encode = function() return "" end }

local D = require("booxbook.sources.dualeo")
local Http = require("booxbook.http")

assert(D.id == "dualeo" and D.kind == "comic", "dualeo adapter identity")
assert(D.name == "Dưa Leo Truyện", "dualeo keeps its Vietnamese name")
assert(D.capabilities.search and D.capabilities.browse and not D.capabilities.login, "dualeo capabilities")
assert(D.MAX_PAGES == 600, "dualeo page cap is 600")
assert(D.seriesUrl("be-con-ngoai-y-muon") == "https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon",
    "seriesUrl is canonical")

-- parseSeriesRef: canonical host, the mirror the site redirects to, and rejects.
local series = assert(D.parseSeriesRef("https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon"))
assert(series.id == "be-con-ngoai-y-muon", "series slug kept")
assert(series.url == "https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon", "series url normalized")
assert(D.parseSeriesRef("https://dualeotruyenvt.com/truyen-tranh/be-con-ngoai-y-muon/") ~= nil,
    "redirect mirror accepted")
assert(D.parseSeriesRef("https://evil.test/truyen-tranh/be-con-ngoai-y-muon") == nil, "foreign host rejected")
assert(D.parseSeriesRef("https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon/chapter-14") == nil,
    "chapter url is not a series url")
assert(D.parseSeriesRef("https://dualeotruyenhn.com/truyen-tranh/") == nil, "series without slug rejected")
assert(D.parseSeriesRef("not a url") == nil, "garbage rejected")
assert(D.parseSeriesRef(nil) == nil, "nil rejected")

-- parseRef: path chapter numbers, dashed decimals and host rejection.
local chapter = assert(D.parseRef("https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon/chapter-14"))
assert(chapter.series == "be-con-ngoai-y-muon" and chapter.number == 14, "chapter splits series and number")
assert(chapter.chapter == "chapter-14", "chapter file slug keeps the chapter prefix")
assert(chapter.url == "https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon/chapter-14",
    "chapter url normalized")
local decimal = assert(D.parseRef("https://dualeotruyenhn.com/truyen-tranh/x/chapter-12-5"))
assert(decimal.number == 12.5 and decimal.chapter == "chapter-12-5", "dashed decimal chapter number")
local side = assert(D.parseRef("https://dualeotruyenvt.com/truyen-tranh/x/chapter-0-134/"))
assert(side.number == 0.134, "side chapter number")
assert(D.parseRef("https://dualeotruyenhn.com/truyen-tranh/x") == nil, "series url is not a chapter")
assert(D.parseRef("https://evil.test/truyen-tranh/x/chapter-1") == nil, "foreign chapter host rejected")
assert(D.parseRef("https://dualeotruyenhn.com/truyen-tranh/x/chapter-") == nil, "chapter without number rejected")
assert(D.parseRef("https://dualeotruyenhn.com/truyen-tranh/x/chapter-1-") == nil, "trailing dash rejected")
assert(D.parseRef({ url = "https://dualeotruyenhn.com/truyen-tranh/x/chapter-7" }).number == 7,
    "parseRef accepts a chapter table")

local list_html = [[
<div class="box_list">
<div class="li_truyen">
	<a href="/truyen-tranh/trai-co-lon">
		<div class="img"><img data-src="https://cover.imgdualeo1.com/biatruyen/1773765502482-455306176.webp" alt="Trai Có Lồn" src="/images/prod_loading.gif" class="lazyload"></div>
		<div class="name">Trai Có Lồn</div>
	</a>
	<a href="/truyen-tranh/trai-co-lon/chapter-159"><div class="update"><div class="chap_name">Chapter 159</div></div></a>
</div>
<div class="li_truyen">
	<a href="/truyen-tranh/trai-co-lon"><div class="name">Trai Có Lồn</div></a>
</div>
<div class="li_truyen">
	<a href="https://dualeotruyenhn.com/truyen-tranh/bi-kip-cua-do-crush/">
		<div class="img"><img data-src="https://img.imgdualeo1.com/story/bi-kip-1758708973.webp" alt="Bí Kíp Của Đồ Crush"></div>
	</a>
</div>
<div class="li_truyen">
	<a href="/truyen-tranh/khong-co-bia"><div class="img"><img src="/images/no-images.jpg"></div></a>
</div>
<nav class="pagination"><a href="/truyen-moi-cap-nhat?page=2">2</a><a href="/truyen-moi-cap-nhat?page=5">5</a></nav>
</div>]]

local listed = assert(D.parseList(list_html, 1))
assert(#listed.items == 3 and listed.has_more == true, "list dedupes and detects the next page")
assert(listed.items[1].id == "trai-co-lon" and listed.items[1].title == "Trai Có Lồn",
    "list keeps the series title, not the latest chapter title")
assert(listed.items[1].cover == "https://cover.imgdualeo1.com/biatruyen/1773765502482-455306176.webp",
    "list keeps the cover")
assert(listed.items[2].title == "Bí Kíp Của Đồ Crush", "absolute series link accepted")
assert(listed.items[3].title == "khong co bia", "title falls back to the slug")
assert(listed.items[3].cover == nil, "placeholder cover is not a cover")
local listed_last = assert(D.parseList(list_html, 5))
assert(listed_last.has_more == false, "last page has no next page")
assert(D.parseList("<html><body>changed</body></html>", 1) == nil, "unrecognized list fails closed")

local series_html = [[
<meta property="og:image" content="https://cover.imgdualeo1.com/biatruyen/1782830860471-624684718.webp">
<h1>Bé Con Ngoài Ý Muốn</h1>
<ul class="story-detail-menu">
	<li><a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-1">Đọc từ đầu</a></li>
	<li><a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-14">Đọc tập mới</a></li>
</ul>
<ul class="list-tag-story"><li><a href="/the-loai/manhwa">Manhwa</a></li><li><a href="/the-loai/18-">18+</a></li></ul>
<div class="txt">
	<p class="info-item">Nhóm dịch: MeowTime Team</p>
	<p class="info-item">Tình trang: Đang cập nhật</p>
	<p class="info-item">Lượt xem: 3,895,753</p>
</div>
<div class="story-detail-info"><p>Bé Con Ngoài Ý Muốn là bộ truyện tranh được nhiều độc giả yêu thích.</p></div>
<div class="list-chapters">
	<div class="chapter-item row">
		<div class="chap_name"><a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-14" title="Bé Con Ngoài Ý Muốn Chapter 14">Chapter 14 H+++++</a></div>
		<a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-14" title="Bé Con Ngoài Ý Muốn Chapter 14"><div class="chap_update"> 18 giờ trước </div></a>
	</div>
	<div class="chapter-item row">
		<div class="chap_name"><a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-2" title="Bé Con Ngoài Ý Muốn Chapter 2">Chapter 2</a></div>
	</div>
	<div class="chapter-item row">
		<div class="chap_name"><a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-12-5">Chapter 12.5</a></div>
	</div>
	<div class="chapter-item row">
		<div class="chap_name"><a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-1" title="Bé Con Ngoài Ý Muốn Chapter 1">Chapter 1</a></div>
	</div>
	<div class="chapter-item row">
		<div class="chap_name"><a href="/truyen-tranh/khac-9/chapter-1">Chapter 1</a></div>
	</div>
	<div class="chapter-item row">
		<div class="chap_name"><a href="/truyen-tranh/be-con-ngoai-y-muon/chapter-3"></a></div>
	</div>
</div>]]

local parsed = assert(D.parseSeries(series_html, "https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon"))
assert(parsed.source_id == "dualeo", "series carries the source id")
assert(parsed.title == "Bé Con Ngoài Ý Muốn", "series title from h1")
assert(parsed.author == "MeowTime Team" and parsed.status == "Đang cập nhật", "series info block parsed")
assert(parsed.description:find("nhiều độc giả", 1, true), "series description parsed")
assert(parsed.cover == "https://cover.imgdualeo1.com/biatruyen/1782830860471-624684718.webp", "og:image cover")
assert(#parsed.genres == 2, "series genres parsed")
assert(#parsed.chapters == 5, "toc dedupes, filters other series and keeps chapterless rows")
assert(parsed.chapters[1].number == 1 and parsed.chapters[1].index == 1, "toc sorts oldest first")
assert(parsed.chapters[1].title == "Chapter 1", "toc keeps the real chapter title, not the shortcut")
assert(parsed.chapters[2].number == 2, "chapter 2 second")
assert(parsed.chapters[3].title == "Chương 3", "chapter without a label falls back to its number")
assert(parsed.chapters[4].number == 12.5, "dashed decimal sorted between 3 and 14")
assert(parsed.chapters[5].number == 14 and parsed.chapters[5].title == "Chapter 14 H+++++", "newest chapter last")
assert(#parsed.volumes == 1 and parsed.volumes[1].chapters == parsed.chapters, "volumes mirror the chapter list")
assert(D.parseSeries("<h1></h1>", "https://dualeotruyenhn.com/truyen-tranh/x") == nil,
    "series without a title fails closed")
assert(D.parseSeries("<h1>X</h1>", "https://evil.test/truyen-tranh/x") == nil,
    "series on a foreign host fails closed")

-- Reader block: plain src, obfuscated data-img (real value from the live site),
-- a data: placeholder, a chapter banner, a comment avatar and the page banner.
local chapter_html = [[
<div class="content_view_chap">
	<img src="https://img.imgdualeo1.com/upbia/10031288211667576604.webp" alt="Đọc truyện Bé Con Ngoài Ý Muốn - Chapter 14" loading="eager">
	<img src="https://cdn7.imgdualeo1.com/uploads/2026-09-20/1789844282461-927930028.webp" alt="page 1">
	<img src="https://cdn7.imgdualeo1.com/uploads/2026-09-20/1789844282467-489934545-part2.webp" alt="page 2">
	<img src="https://cdn7.imgdualeo1.com/uploads/2026-09-20/1789844282467-489934545-part3.webp" data-img="https://cdn7.imgdualeo1.com/uploads/2026-09-20/VUJZVV1ba0FZXkBpBR0GDV1MUlhQW2peEQ0GKwE.webp" alt="page 3">
	<img src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==" data-img="https://cdn7.imgdualeo1.com/uploads/2026-09-19/VUJZVV1caUdZWERqBB0EAl1BUVpTWmY.webp" alt="page 4">
	<img src="https://cover.imgdualeo1.com/avata/1784858179179-198657596.webp" alt="comment avatar">
	<img src="/banner/banner00320x50.gif" alt="banner">
</div>
<h1>Bé Con Ngoài Ý Muốn - Chapter 14 H+++++</h1>]]

local clean = assert(D.parseChapter(chapter_html, "https://dualeotruyenhn.com/truyen-tranh/be-con-ngoai-y-muon/chapter-14"))
assert(#clean.pages == 4, "only real pages survive (banner, avatar and chapter banner are skipped)")
assert(clean.pages[1]:find("1789844282461-927930028", 1, true), "plain src page kept in order")
assert(clean.pages[3] == "https://cdn7.imgdualeo1.com/uploads/2026-09-20/1789844282467-489934545-part3.webp",
    "obfuscated data-img decoded to its real filename")
assert(clean.pages[4]:find("1789836484056-679406659", 1, true), "data: placeholder falls back to data-img")
assert(clean.title:find("Chapter 14", 1, true), "chapter title from h1")

local foreign_html = [[
<div class="content_view_chap">
	<img src="https://cdn7.imgdualeo1.com/uploads/2026-09-20/1.webp">
	<img src="https://evil.test/2.webp">
</div>]]
assert(D.parseChapter(foreign_html, "https://dualeotruyenhn.com/truyen-tranh/x/chapter-1") == nil,
    "foreign image host fails the chapter")
assert(D.parseChapter("<div></div>", "https://dualeotruyenhn.com/truyen-tranh/x/chapter-1") == nil,
    "chapter without a reader fails closed")
assert(D.parseChapter(chapter_html, "https://evil.test/truyen-tranh/x/chapter-1") == nil,
    "chapter url on a foreign host is refused before parsing")

assert(D.imageUrl("https://dualeotruyenhn.com/", "https://cdn7.imgdualeo1.com/uploads/a/b.webp")
    == "https://cdn7.imgdualeo1.com/uploads/a/b.webp", "cdn page image allowed")
assert(D.imageUrl("https://dualeotruyenhn.com/", "https://dualeotruyenhn.com/uploads/a/b.jpg") ~= nil,
    "site-host page image allowed")
assert(D.imageUrl("https://dualeotruyenhn.com/", "https://evil.test/a.jpg") == nil, "foreign image rejected")
assert(D.imageUrl("https://dualeotruyenhn.com/", "http://cdn7.imgdualeo1.com/a.webp") == nil, "plain http rejected")
assert(D.imageUrl("https://dualeotruyenhn.com/", "//cdn7.imgdualeo1.com/a.webp") ~= nil,
    "protocol-relative image resolved to https")
assert(D.imageUrl("https://dualeotruyenhn.com/", "https://cdn7.imgdualeo1.com/a b.webp") == nil,
    "image url with a space rejected")
assert(D.imageUrl("https://dualeotruyenhn.com/", "https://cdn7.imgdualeo1.com/a\\b.webp") == nil,
    "image url with a backslash rejected")
assert(D.imageUrl("https://dualeotruyenhn.com/", "https://img.imgdualeo1.com/upbia/1.webp") == nil,
    "chapter banner rejected")
assert(D.imageUrl("https://dualeotruyenhn.com/", "https://cover.imgdualeo1.com/avata/1.webp") == nil,
    "comment avatar rejected")
assert(D.imageUrl("https://dualeotruyenhn.com/", "https://cdn7.imgdualeo1.com/a.avif") == nil,
    "avif page image rejected (unreadable on KOReader)")

-- 600-page cap, exactly like truyenqq.
local exact = { '<div class="content_view_chap">' }
for i = 1, D.MAX_PAGES do
    exact[#exact + 1] = '<img src="https://cdn7.imgdualeo1.com/uploads/2026-09-20/' .. i .. '.webp">'
end
exact[#exact + 1] = "</div>"
local full = assert(D.parseChapter(table.concat(exact), "https://dualeotruyenhn.com/truyen-tranh/x/chapter-1"))
assert(#full.pages == D.MAX_PAGES, "exactly 600 pages accepted")

exact[#exact] = '<img src="https://cdn7.imgdualeo1.com/uploads/2026-09-20/601.webp">'
exact[#exact + 1] = "</div>"
local capped, cap_err = D.parseChapter(table.concat(exact), "https://dualeotruyenhn.com/truyen-tranh/x/chapter-1")
assert(capped == nil and cap_err:find("600", 1, true), "601 pages stop with a readable cap message")

local bad_kind = select(2, D.browse("popular", 1))
assert(type(bad_kind) == "string", "unknown browse kind explains itself")
assert(type(select(2, D.browse("latest", 0))) == "string", "invalid page rejected")
assert(type(select(2, D.search("   ", 1))) == "string", "blank query rejected")

-- Every request carries the pacing delay and a referer; endpoints stay canonical.
local calls, old_get = {}, Http.get
Http.get = function(url, opts)
    calls[#calls + 1] = { url = url, opts = opts }
    return true, 200, list_html
end
assert(D.browse("latest", 1), "latest list loads")
assert(calls[1].url == "https://dualeotruyenhn.com/truyen-moi-cap-nhat", "latest uses the canonical endpoint")
assert(D.browse("latest", 3), "latest page 3 loads")
assert(calls[2].url == "https://dualeotruyenhn.com/truyen-moi-cap-nhat?page=3", "latest paginates with ?page=")
assert(D.browse("completed", 1), "completed list loads")
assert(calls[3].url == "https://dualeotruyenhn.com/truyen-hoan-thanh", "completed endpoint")
assert(D.search("bé con", 1), "search loads")
assert(calls[4].url == "https://dualeotruyenhn.com/tim-kiem?key=b%C3%A9%20con", "search encodes the query")
assert(D.search("bé con", 2), "search page 2 loads")
assert(calls[5].url == "https://dualeotruyenhn.com/tim-kiem.html?key=b%C3%A9%20con&page=2",
    "search paginates on the .html endpoint")
for _i, call in ipairs(calls) do
    assert(type(call.opts) == "table" and call.opts.referer == "https://dualeotruyenhn.com/",
        "request carries a referer")
    assert((call.opts.delay_ms or 0) >= 1600, "request respects the 1600ms floor")
    assert(type(call.opts.allow_url) == "function", "request restricts redirects")
    assert(call.opts.allow_url("https://dualeotruyenhn.com/x"), "own host allowed on redirect")
    assert(not call.opts.allow_url("https://evil.test/x"), "foreign redirect blocked")
end
Http.get = function()
    return false, 429, nil
end
assert(select(2, D.browse("latest", 1)):find("429", 1, true), "429 is reported as a rate limit")
Http.get = old_get

print("Dưa Leo Truyện dualeo adapter checks passed")
