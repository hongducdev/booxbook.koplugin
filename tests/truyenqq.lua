package.loaded["libs/libkoreader-lfs"] = package.loaded["libs/libkoreader-lfs"]
    or { symlinkattributes = function() return nil end, attributes = function() return nil end }
package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end
package.loaded["json"] = package.loaded["json"] or { decode = function() return nil end, encode = function() return "" end }

local QQ = require("booxbook.sources.truyenqq")
local Http = require("booxbook.http")

assert(QQ.id == "truyenqq" and QQ.kind == "comic", "truyenqq adapter identity")
assert(QQ.capabilities.search and QQ.capabilities.browse, "truyenqq browsable and searchable")

local series = assert(QQ.parseSeriesRef("https://truyenqqko.com/truyen-tranh/yeu-than-ky-746/"))
assert(series.id == "yeu-than-ky-746", "series slug keeps numeric suffix")
assert(QQ.parseSeriesRef("http://m.truyenqqko.com/truyen-tranh/a-1") ~= nil, "mobile host accepted")
assert(QQ.parseSeriesRef("https://evil.test/truyen-tranh/a-1") == nil, "foreign host rejected")
assert(QQ.parseSeriesRef("not a url") == nil, "garbage rejected")

local chapter = assert(QQ.parseRef("https://truyenqqko.com/truyen-tranh/yeu-than-ky-746-chap-703"))
assert(chapter.series == "yeu-than-ky-746" and chapter.number == 703, "chapter splits series and number")
assert(chapter.chapter == "chap-703", "chapter file slug keeps chap prefix")
assert(QQ.parseRef("https://truyenqqko.com/truyen-tranh/yeu-than-ky-746") == nil, "series url is not a chapter")
assert(QQ.parseRef("https://truyenqq.net/manga/x/tap-1/") == nil, "old madara urls rejected")

local list_html = [[
<div class="book_avatar"><a href="/truyen-tranh/bo-a-1"><img alt="Bo A" src="https://i.hinhhinh.com/ebook/bo.jpg"></a></div>
<div class="book_avatar"><a href="/truyen-tranh/bo-a-1"><img alt="Bo A" src="https://i.hinhhinh.com/ebook/bo.jpg"></a></div>
<div class="book_avatar"><a href="https://truyenqqko.com/truyen-tranh/bo-b-2"><img src="https://st.truyenqqko.com/x.png"></a></div>
<a href="/truyen-moi-cap-nhat/trang-2">2</a>]]
local listed = assert(QQ.parseList(list_html, 1))
assert(#listed.items == 2 and listed.has_more == true, "list dedupes and detects next page")
assert(listed.items[1].title == "Bo A" and listed.items[1].cover:find("hinhhinh", 1, true),
    "list keeps title and cover")
local listed_last = assert(QQ.parseList(list_html, 2))
assert(listed_last.has_more == false, "last page has no next page")
assert(QQ.parseList("<html><body>changed</body></html>", 1) == nil, "unrecognized list fails closed")

local series_html = [[
<h1>Yeu Than Ky</h1><div class="author row">Tac gia</div>
<div class="works-chapter-list">
<a href="/truyen-tranh/yeu-than-ky-746-chap-2">Chuong 2</a>
<a href="/truyen-tranh/yeu-than-ky-746-chap-1">Chuong 1</a>
<a href="/truyen-tranh/yeu-than-ky-746-chap-2">Chuong 2</a>
<a href="/truyen-tranh/yeu-than-ky-746-chap-3"></a>
<a href="/truyen-tranh/khac-9-chap-1">Chuong 1</a>
</div>]]
local parsed = assert(QQ.parseSeries(series_html, "https://truyenqqko.com/truyen-tranh/yeu-than-ky-746"))
assert(parsed.source_id == "truyenqq" and #parsed.chapters == 3, "toc dedupes and filters series")
assert(parsed.chapters[1].number == 1 and parsed.chapters[1].index == 1, "toc sorts oldest first")
assert(parsed.chapters[2].number == 2, "newest chapter last")
assert(parsed.chapters[3].title:find("3", 1, true), "untitled chapter falls back to number")
assert(QQ.parseSeries("<h1></h1>", "https://truyenqqko.com/truyen-tranh/x-1") == nil,
    "series without title fails closed")

local chapter_html = [[
<div class="chapter_content_div">
<img class="lazy" data-original="https://i178.truyenvua.com/746/703/1.jpg">
<img src="https://i.hinhhinh.com/746/703/2.jpg">
<img src="https://evil.test/x.jpg">
</div><h1>Chuong 703</h1>]]
assert(QQ.parseChapter(chapter_html, "https://truyenqqko.com/truyen-tranh/yeu-than-ky-746-chap-703") == nil,
    "foreign image host fails the chapter")
local clean_html = chapter_html:gsub('<img src="https://evil[^>]+>', "")
local clean = assert(QQ.parseChapter(clean_html, "https://truyenqqko.com/truyen-tranh/yeu-than-ky-746-chap-703"))
assert(#clean.pages == 2 and clean.pages[1]:find("truyenvua", 1, true), "data-original preferred")
assert(QQ.parseChapter("<div></div>", "https://truyenqqko.com/truyen-tranh/a-1-chap-1") == nil,
    "chapter without reader fails closed")

local page_chapter_html = [[
<div class="chapter_content_div">
    <div class="chapter_content">
        <div class="page-chapter"><img data-original="https://i178.truyenvua.com/746/703/1.jpg"></div>
        <div class="page-chapter"><img class="lazy" data-original="https://i.hinhhinh.com/746/703/2.jpg"></div>
    </div>
    <div class="avartar-comment">
        <img class="lazy-image" src="https://st.truyenqqko.com/template/frontend/images/noavatar.png">
    </div>
    <div class="content-comment">
        <img alt="emo" class="lazy-image" data-src="https://4.bp.blogspot.com/emo.gif">
    </div>
</div><h1>Chuong 703</h1>]]
local page_chapter_parsed = assert(QQ.parseChapter(page_chapter_html, "https://truyenqqko.com/truyen-tranh/yeu-than-ky-746-chap-703"))
assert(#page_chapter_parsed.pages == 2, "page-chapter extracts only comic pages and ignores comments/avatar")
assert(page_chapter_parsed.pages[1]:find("truyenvua", 1, true) and page_chapter_parsed.pages[2]:find("hinhhinh", 1, true),
    "page-chapter preserves valid image hosts")

local evil_page_chapter_html = [[
<div class="chapter_content_div">
    <div class="chapter_content">
        <div class="page-chapter"><img data-original="https://i178.truyenvua.com/746/703/1.jpg"></div>
        <div class="page-chapter"><img data-original="https://evil.test/x.jpg"></div>
    </div>
    <div class="content-comment">
        <img alt="emo" class="lazy-image" data-src="https://4.bp.blogspot.com/emo.gif">
    </div>
</div><h1>Chuong 703</h1>]]
assert(QQ.parseChapter(evil_page_chapter_html, "https://truyenqqko.com/truyen-tranh/yeu-than-ky-746-chap-703") == nil,
    "foreign image inside page-chapter fails closed")

local empty_page_chapter_html = [[
<div class="chapter_content_div">
    <div class="chapter_content">
        <div class="page-chapter"><img data-original="https://i178.truyenvua.com/746/703/1.jpg"></div>
        <div class="page-chapter"></div>
    </div>
</div><h1>Chuong 703</h1>]]
assert(QQ.parseChapter(empty_page_chapter_html, "https://truyenqqko.com/truyen-tranh/yeu-than-ky-746-chap-703") == nil,
    "empty page-chapter container fails closed to prevent missing pages")

assert(QQ.imageUrl("https://truyenqqko.com/", "https://i178.truyenvua.com/a.jpg"):find("truyenvua", 1, true),
    "cdn image host allowed")
assert(QQ.imageUrl("https://truyenqqko.com/", "https://evil.test/a.jpg") == nil, "foreign image rejected")
assert(QQ.imageUrl("https://truyenqqko.com/", "http://i.hinhhinh.com/a.jpg") == nil, "plain http rejected")

local bad_kind = select(2, QQ.browse("popular", 1))
assert(type(bad_kind) == "string", "non-latest browse explains itself")
local bad_page = select(2, QQ.browse("latest", 0))
assert(type(bad_page) == "string", "invalid page rejected")
local bad_query = select(2, QQ.search("   ", 1))
assert(type(bad_query) == "string", "blank query rejected")

local old_get, requested_url = Http.get
Http.get = function(url)
    requested_url = url
    return true, 200, list_html
end
assert(QQ.browse("latest", 1), "latest list loads")
assert(requested_url == "https://truyenqqko.com/doc-truyen", "latest list uses canonical endpoint")
Http.get = old_get

print("TruyenQQ truyenqqko adapter checks passed")
