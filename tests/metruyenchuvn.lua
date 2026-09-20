package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path

local T = require("booxbook.sources.metruyenchuvn")
local Http = require("booxbook.http")
local original = { Http.get, Http.expired }
local calls, urls, responses = 0, {}, {}

Http.get = function(url, opts)
    calls = calls + 1
    urls[#urls + 1] = url
    assert(type(opts) == "table" and opts.delay_ms >= 1600, "delay_ms floor on every request")
    assert(opts.referer == "https://metruyenchuvn.org/", "referer on every request")
    local entry = responses[url]
    if not entry then return false, 404, "no fixture for " .. url end
    local code = entry.code or 200
    return code == 200, code, entry.body or ""
end

-- The site lists chapters as JSON with escaped HTML inside, so chapters are built
-- the same way the endpoint returns them.
local function listchap(slug, ...)
    local items = {}
    for _, entry in ipairs({ ... }) do
        items[#items + 1] = string.format("<li><a href='/%s/%s'>%s</a></li>", slug, entry[1], entry[2])
    end
    local raw = "<div class='clearfix'><ul>" .. table.concat(items) .. "</ul></div>"
    raw = raw:gsub("&", "&amp;"):gsub("<", "\\u003c"):gsub(">", "\\u003e")
        :gsub("'", "\\u0027"):gsub('"', "\\u0022"):gsub("/", "\\/")
    return '{"data":"' .. raw .. '"}'
end
local function card(slug, title, cover)
    return table.concat({
        '<div class="item">',
        '<a href="/' .. slug .. '" title="' .. title .. '" class="cover"><img src="' .. cover .. '" alt="' .. title .. '"></a>',
        '<h3><a href="/' .. slug .. '" title="' .. title .. '">' .. title .. '</a></h3>',
        '<p class="line"><span>Thể loại :</span> <a href="/the-loai/tien-hiep">Tiên Hiệp</a></p>',
        '</div>',
    })
end
local function listing(...)
    return '<div class="truyen-list bg-wrap">' .. table.concat({ ... }) .. "</div>"
end
local function pager(page)
    return string.format('<div class="phan-trang"><a class="btn-page" href="/danh-sach/truyen-hot?page=%d">%d</a></div>', page, page)
end
local function chapterPage(title, body)
    return '<h2 class="current-chapter"> <a href="javascript:;" style="color:red">' .. title .. "</a></h2>"
        .. '<div class="truyen">' .. body .. '</div><footer>chân trang</footer>'
end
local story_html = table.concat({
    '<meta property="og:title" content="Quy Khư Tiên Quốc - Đọc Truyện | MeTruyenChu" />',
    '<meta property="og:url" content="https://metruyenchuvn.org/quy-khu-tien-quoc" />',
    '<meta property="og:image" content="https://metruyenchuvn.org/media/book/quy-khu.webp" />',
    '<meta property="og:description" content="Truyện Quy Khư Tiên Quốc của tác giả: Cô Độc Phiêu Lưu" />',
    '<h1 itemprop="name">Quy Khư Ti&#234;n Quốc</h1>',
    '<a href="/tac-gia/co-doc-phieu-luu" itemprop="author">C&#244; Độc Phi&#234;u Lưu</a>',
    '<img src="/media/book/quy-khu-tien-quoc.jpg" alt="Quy Khư" itemprop="image">',
    '<div class="showmore"><div class="scrolltext"><p class="intro">MeTruyenChu vừa cập nhật bộ truyện mới.</p>',
    '<h3>Giới thiệu nội dung: </h3>',
    '<div itemprop="description"><p>Quy khư là chư thiên vạn giới<br><br>tất cả sinh mệnh quy tụ.</p></div></div></div>',
    '<form><input type="hidden" name="bid" value="111806" /></form>',
    "<script>var rid = '111806';</script>",
    "<div class='paging'><a href='javascript:void(0)' onclick='page(111806,2);'>2</a></div>",
}, "")
local story_url = "https://metruyenchuvn.org/quy-khu-tien-quoc"

-- Adapter identity and contract surface.
assert(T.id == "metruyenchuvn" and T.kind == "novel", "adapter identity")
assert(T.name == "Mê Truyện Chữ VN", "display name stays distinct from MeTruyenCV")
assert(T.capabilities.search and T.capabilities.browse and not T.capabilities.login, "capabilities")
assert(T.view.base_url == "https://metruyenchuvn.org" and T.view.is_ref("https://metruyenchuvn.org/a-truyen"), "view")
assert(#T.view.browse == 3 and T.view.browse[1].kind == "latest", "three browse entries")
assert(type(T.locate) == "function" and type(T.chapterRef) == "function" and type(T.getSeries) == "function")

-- parseRef: one path level holds stories, categories, chapters and site pages, so
-- the guard does the telling apart.
assert(T.parseRef("https://metruyenchuvn.org/quy-khu-tien-quoc") == "quy-khu-tien-quoc", "series url")
assert(T.parseRef("http://www.metruyenchuvn.org/quy-khu-tien-quoc/?utm=1#x") == "quy-khu-tien-quoc",
    "mobile host, trailing slash, query and fragment")
assert(T.parseRef("/quy-khu-tien-quoc") == "quy-khu-tien-quoc", "root relative story")
assert(T.parseRef("quy-khu-tien-quoc") == "quy-khu-tien-quoc", "bare id from a followed series")
assert(T.parseRef({ url = "https://metruyenchuvn.org/quy-khu-tien-quoc" }) == "quy-khu-tien-quoc", "table ref")
local slug, chapter_id, chapter_path = T.parseRef("https://metruyenchuvn.org/quy-khu-tien-quoc/chuong-1-SODJRjw6TKZc")
assert(slug == "quy-khu-tien-quoc" and chapter_id == "chuong-1-SODJRjw6TKZc", "chapter split")
assert(chapter_path == "/quy-khu-tien-quoc/chuong-1-SODJRjw6TKZc", "chapter path rebuilt")
local _tiep_slug, tiep = T.parseRef("/can-nuot-troi-cao/chuong-tiep-CR2c3Vq86!Ie")
assert(tiep == "chuong-tiep-CR2c3Vq86!Ie", "chapter tokens may carry ! and _")
assert(select(2, T.parseRef("/quy-khu-tien-quoc/chuong-4-!K6dooRlAdLx")) == "chuong-4-!K6dooRlAdLx", "leading ! token")
assert(T.parseRef("/ab") == "ab", "the source's guard allows a two-letter story slug")
for _, ref in ipairs({ "https://evil.test/quy-khu-tien-quoc", "https://metruyenchuvn.org.evil.test/x",
    "/danh-sach/truyen-hot", "/danh-sach-foo", "/the-loai/tien-hiep", "/tac-gia/linh-linh", "/chuong-1",
    "/chuong-1-ab", "/search?q=x", "/tim-kiem?q=x", "/login", "/register", "/user/profile", "/history/1",
    "/theme/css/style.min.css", "/images/logo.png", "/tos", "/favicon.ico?v=2", "/", "/a",
    "/quy-khu-tien-quoc/chuong-1-x/extra" }) do
    assert(T.parseRef(ref) == nil, "rejected: " .. ref)
end
-- A bare word is a saved id (follow ups and continuation open a series by id), so it
-- is accepted here and fails closed when the story page turns out not to exist.
assert(T.parseRef("khong-phai-url") == "khong-phai-url", "bare id")
assert(not T.getSeries("khong-phai-url"), "an unknown bare id fails closed")
local locate_id, locate_path = T.locate({ url = story_url, id = "quy-khu-tien-quoc" })
assert(locate_id == "quy-khu-tien-quoc" and locate_path == "quy-khu-tien-quoc", "locate returns the folder id and ref")
assert(T.locate({ url = story_url .. "/chuong-1-SODJRjw6TKZc" }) == "quy-khu-tien-quoc", "locate on a chapter")
local ref_series, ref_chapter = T.chapterRef({ id = chapter_id, series_id = "quy-khu-tien-quoc",
    url = story_url .. "/" .. chapter_id })
assert(ref_series == "quy-khu-tien-quoc" and ref_chapter == chapter_id, "chapterRef for saving")
assert(T.chapterRef({ id = "x", series_id = "khac", url = "https://evil.test/a/chuong-1-b" }) == nil,
    "chapterRef refuses a foreign chapter")

-- A foreign or malformed ref never reaches the network.
local before = calls
assert(not T.getSeries("https://evil.test/quy-khu-tien-quoc") and calls == before, "foreign host never fetched")
assert(not T.getSeries("/danh-sach/truyen-hot") and calls == before, "category path is not a series")
assert(not T.getChapter({ url = "https://evil.test/a/chuong-1-b" }) and calls == before, "foreign chapter never fetched")

-- Browse: cards with covers, the 404 listing falls back to the homepage, and the
-- next page is detected from the pagination links.
responses = {
    ["https://metruyenchuvn.org/danh-sach/truyen-hot?page=1"] = { body = listing(
        card("nguoi-tinh-cua-ly-tong", "Người Tình Của Lý Tổng", "/media/book/nguoi-tinh.jpg"),
        card("chang-re-bac-si", "Chàng Rể Bác Sĩ", "/media/book/chang-re-bac-si.jpg"),
        card("nguoi-tinh-cua-ly-tong", "Người Tình Của Lý Tổng", "/media/book/nguoi-tinh.jpg")) .. pager(2) },
    ["https://metruyenchuvn.org/danh-sach/truyen-hot?page=2"] = { body = listing(
        card("vo-phu", "Vô Phụ", "/media/book/vo-phu.jpg")) },
    ["https://metruyenchuvn.org/danh-sach/truyen-full?page=1"] = { body = listing(
        card("dan-du-vang-trang", "Dẫn Dụ Vầng Trăng", "/media/book/dan-du-vang-trang.jpg")) },
    ["https://metruyenchuvn.org/the-loai/tien-hiep?page=1"] = { body = listing(
        card("tu-tam-quoc", "Từ Tam Quốc Bắt Đầu Tu Tiên", "/media/book/tu-tam-quoc.jpg")) .. pager(2) },
    ["https://metruyenchuvn.org/"] = { body = listing(
        card("mat-troi-nho-cua-anh", "Mặt Trời Nhỏ Của Anh", "/media/book/mat-troi.jpg"),
        card("tieu-phu-quan", "Tiểu Phu Quân", "/media/book/tieu-phu-quan.jpg")) },
}
local popular = assert(T.browse("popular", 1))
assert(#popular.items == 2, "cards are de-duplicated by story, got " .. #popular.items)
assert(popular.has_more == true, "page 2 link is detected")
assert(popular.items[1].ref == "/nguoi-tinh-cua-ly-tong", "item ref")
assert(popular.items[1].url == "https://metruyenchuvn.org/nguoi-tinh-cua-ly-tong", "item url")
assert(popular.items[1].title == "Người Tình Của Lý Tổng" and popular.items[1].name == popular.items[1].title, "item title")
assert(popular.items[1].cover == "/media/book/nguoi-tinh.jpg", "item cover from the card")
assert(T.browse("popular", 2).has_more == false, "last page has no next page")
local latest = assert(T.browse("latest", 1))
assert(#latest.items == 2 and latest.has_more == false, "listing 404 falls back to the homepage")
local full = assert(T.browse("full", 1))
assert(full.items[1].ref == "/dan-du-vang-trang", "full listing")
local genre = assert(T.browse("tien-hiep", 1))
assert(genre.items[1].ref == "/tu-tam-quoc" and genre.has_more == true, "genre listing")
assert(urls[#urls] == "https://metruyenchuvn.org/the-loai/tien-hiep?page=1", "genre browse url")
assert(T.browse(nil, 1).items[1].ref == "/mat-troi-nho-cua-anh", "no kind means latest")
assert(type(select(2, T.browse("khong-co-the-loai"))) == "string", "unknown list kind rejected")
assert(type(select(2, T.browse("popular", 0))) == "string", "invalid page rejected")
responses["https://metruyenchuvn.org/danh-sach/truyen-hot?page=1"] = { body = "<html>đổi giao diện</html>" }
assert(T.browse("popular", 1) == nil, "an unrecognised first page fails closed")
assert(T.browse("latest", 2) == nil, "the homepage fallback only applies to page 1")

-- A page whose links are not story-shaped must yield nothing rather than junk.
responses["https://metruyenchuvn.org/danh-sach/truyen-full?page=1"] = { body = listing(
    '<a href="/the-loai/kiem-hiep">Kiếm Hiệp</a>', '<a href="/tac-gia/x">Tác giả</a>',
    '<a href="/quy-khu-tien-quoc/chuong-1-SODJRjw6TKZc">Chương 1</a>') }
assert(T.browse("full", 1) == nil, "category, author and chapter links are never stories")
assert(T.search("kiếm", 1) ~= nil, "search keeps working after a bad listing")

-- Search: same cards, no pagination, and the homepage when the search page is
-- missing or empty.
responses["https://metruyenchuvn.org/search?q=ki%E1%BA%BFm"] = { body = listing(
    card("kiem-ban-thi-ma", "Kiếm Bàn Thị Ma", "/media/book/kiem-ban.jpg"),
    card("mot-kiem-binh-sinh", "Một Kiếm Bình Sinh", "/media/book/mot-kiem.jpg"),
    card("ta-khong-lam-kiem-chu", "Ta Không Làm Kiếm Chủ", "/media/book/ta-khong-lam-kiem-chu.jpg")) }
local hits = assert(T.search("kiếm", 1))
assert(#hits.items == 3 and hits.items[1].ref == "/kiem-ban-thi-ma", "search items")
assert(hits.items[2].cover == "/media/book/mot-kiem.jpg", "search item cover")
assert(hits.has_more == false, "search never paginates")
assert(urls[#urls] == "https://metruyenchuvn.org/search?q=ki%E1%BA%BFm", "query is percent encoded")
responses["https://metruyenchuvn.org/search?q=khong%20co"] = { body = "<html></html>" }
assert(T.search("khong co", 1).items[1].ref == "/mat-troi-nho-cua-anh", "empty search page falls back to the homepage")
assert(T.search("khong co", 1).has_more == false, "homepage fallback has no next page")
assert(T.search("mat khac", 1).items[1].ref == "/mat-troi-nho-cua-anh", "failed search request falls back too")
assert(type(select(2, T.search("   "))) == "string", "blank query rejected")
assert(type(select(2, T.search("x", 0))) == "string", "invalid search page rejected")
assert(type(select(2, T.search(string.rep("x", 301)))) == "string", "over-long query rejected")

local seen_keys, seen_names = {}, {}
for _, genre in ipairs(T.genres) do
    assert(not seen_keys[genre.key], "duplicate genre key: " .. genre.key)
    assert(not seen_names[genre.name], "duplicate genre name: " .. genre.name)
    assert(genre.key:match("^[a-z0-9%-]+$"), "genre key must be a URL-safe slug: " .. genre.key)
    assert(not genre.adult, "this site publishes no adult shelf")
    seen_keys[genre.key], seen_names[genre.name] = true, true
end
assert(#T.genres == 36, "genre list: " .. #T.genres)

-- getSeries: story header, then the ajax chapter list page by page.
responses = {
    [story_url] = { body = story_html },
    ["https://metruyenchuvn.org/get/listchap/111806?page=1"] = { body = listchap("quy-khu-tien-quoc",
        { "chuong-1-SODJRjw6TKZc", "Chương 1: Côn Luân Mâm Ngọc" },
        { "chuong-2-noDc2QDpxQAN", "Chương 2: Thiên Khanh" },
        { "chuong-2-noDc2QDpxQAN", "Chương 2: Thiên Khanh" },
        { "chien-huu-x", "Chương linh tinh của truyện khác" },
        { "chuong-tiep-aBc!", "Chương tiếp" }) },
    -- Past the last page the live endpoint serves page 1 again.
    ["https://metruyenchuvn.org/get/listchap/111806?page=2"] = { body = listchap("quy-khu-tien-quoc",
        { "chuong-1-SODJRjw6TKZc", "Chương 1: Côn Luân Mâm Ngọc" },
        { "chuong-2-noDc2QDpxQAN", "Chương 2: Thiên Khanh" }) },
}
calls = 0
local series = assert(T.getSeries(story_url))
assert(series.id == "quy-khu-tien-quoc" and series.source_id == "metruyenchuvn", "series identity")
assert(series.title == "Quy Khư Tiên Quốc", "title decoded from the h1")
assert(series.author == "Cô Độc Phiêu Lưu", "author from itemprop")
assert(series.cover == "https://metruyenchuvn.org/media/book/quy-khu-tien-quoc.jpg", "cover from the book image")
assert(series.url == story_url, "series url")
assert(series.description:find("Quy khư là chư thiên vạn giới", 1, true) ~= nil, "synopsis from the description block")
assert(#series.chapters == 3, "three unique chapters of this story, got " .. #series.chapters)
assert(series.chapters[1].id == "chuong-1-SODJRjw6TKZc" and series.chapters[1].index == 1, "first chapter")
assert(series.chapters[2].id == "chuong-2-noDc2QDpxQAN" and series.chapters[2].number == 2, "second chapter")
assert(series.chapters[3].id == "chuong-tiep-aBc!", "unnumbered chapter kept in list order")
assert(series.chapters[1].series_id == "quy-khu-tien-quoc", "chapters carry their series")
assert(series.chapters[1].url == story_url .. "/chuong-1-SODJRjw6TKZc", "chapter url")
assert(series.chapters[1].title == "Chương 1: Côn Luân Mâm Ngọc", "chapter title from the link text")
assert(series.truncated == nil, "a chapter list that ends is not flagged")
assert(calls == 3, "story page plus two chapter pages, got " .. calls)
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters, "single volume")

-- Numbered lists are sorted; a "chuong-tiep" entry keeps the position the site gave it.
responses["https://metruyenchuvn.org/get/listchap/111806?page=1"] = { body = listchap("quy-khu-tien-quoc",
    { "chuong-1-a", "Chương 1: A" }, { "chuong-3-c", "Chương 3: C" }, { "chuong-2-b", "Chương 2: B" }) }
responses["https://metruyenchuvn.org/get/listchap/111806?page=2"] = { body = listchap("quy-khu-tien-quoc",
    { "chuong-1-a", "Chương 1: A" }) }
local sorted = assert(T.getSeries(story_url))
assert(#sorted.chapters == 3 and sorted.chapters[1].id == "chuong-1-a" and sorted.chapters[3].id == "chuong-3-c",
    "numbered chapters are sorted by number")

-- When the ajax endpoint is down the story page still carries its first page.
responses["https://metruyenchuvn.org/get/listchap/111806?page=1"] = { code = 500, body = "lỗi máy chủ" }
responses[story_url] = { body = story_html:gsub("<form>", table.concat({
    "<div id='chapter-list'><ul>",
    "<li><a href='/quy-khu-tien-quoc/chuong-1-SODJRjw6TKZc'>Chương 1: Côn Luân Mâm Ngọc</a></li>",
    "<li><a href='/quy-khu-tien-quoc/chuong-2-noDc2QDpxQAN'>Chương 2: Thiên Khanh</a></li>",
    "<li><a href='/the-loai/tien-hiep'>Tiên Hiệp</a></li>",
    "</ul></div><form>",
})) }
local fallback = assert(T.getSeries(story_url))
assert(#fallback.chapters == 2, "story page fallback lists its own chapters only, got " .. #fallback.chapters)
assert(fallback.truncated == nil, "the fallback is not a truncated index")

-- A story page that does not carry its own marker (a redirect to the homepage, for
-- instance) must fail closed instead of becoming a bogus series.
responses[story_url] = { body = '<h1>MeTruyenChu</h1><div class="truyen-list">x</div>' }
local ghost, ghost_err = T.getSeries("truyen-khong-ton-tai")
assert(not ghost and ghost_err, "story page without its own marker fails closed")
assert(not T.getSeries(story_url .. "/chuong-1-SODJRjw6TKZc"), "a chapter url is not a series")
assert(not T.getSeries("https://evil.test/quy-khu-tien-quoc"), "foreign host still refused")

-- A chapter list that keeps handing out chapters must stop at the cap.
responses[story_url] = { body = story_html }
calls = 0
for page = 1, 3 do responses["https://metruyenchuvn.org/get/listchap/111806?page=" .. page] = { body = nil } end
local endless_page = 0
local original_get = Http.get
Http.get = function(url, opts)
    calls = calls + 1
    assert(opts.delay_ms >= 1600 and opts.referer == "https://metruyenchuvn.org/", "request options")
    if url == story_url then return true, 200, story_html end
    endless_page = endless_page + 1
    return true, 200, listchap("quy-khu-tien-quoc",
        { "chuong-" .. endless_page .. "-x", "Chương " .. endless_page .. ": X" })
end
local endless = assert(T.getSeries(story_url))
assert(endless.truncated, "endless chapter list is truncated, not spun forever")
assert(calls <= 61 and endless_page <= 60, "chapter paging stops at the cap, calls=" .. calls)
assert(#endless.chapters >= 1, "chapters already read are kept")
Http.expired = function() return true end
calls = 0
local budgeted = assert(T.getSeries(story_url))
assert(budgeted.truncated and calls <= 2, "expired action budget stops paging")
Http.expired = original[2]
Http.get = original_get

-- getChapter: chapter text, gates and refusals.
responses = {}
local chapter_ref = { id = "chuong-1-SODJRjw6TKZc", series_id = "quy-khu-tien-quoc",
    url = story_url .. "/chuong-1-SODJRjw6TKZc", title = "tên cũ" }
responses[chapter_ref.url] = { body = chapterPage("Chương 1: Côn Lu&#226;n M&#226;m Ngọc", table.concat({
    "&#13; Đoạn một &amp; chữ.&#13; &#13; ",
    "Đoạn hai <script>bad()</script><style>.x{}</style>còn lại.<br>",
    "Đoạn ba &lt;thẻ&gt; giữ nguyên dấu.&#13;",
    "&nbsp;",
    '<div id="formcode"><img src="/img/loading.gif" alt=""></div>',
})) }
local chapter = assert(T.getChapter(chapter_ref))
assert(chapter.title == "Chương 1: Côn Luân Mâm Ngọc", "chapter title decoded: " .. chapter.title)
local paragraphs = 0
for _ in chapter.html:gmatch("<p>") do paragraphs = paragraphs + 1 end
assert(paragraphs == 3, "one paragraph per line, got " .. paragraphs)
assert(chapter.html:find("Đoạn một &amp; chữ.", 1, true) ~= nil, "entities decoded then escaped")
assert(chapter.html:find("Đoạn hai còn lại.", 1, true) ~= nil, "inline tags dropped from the paragraph")
assert(chapter.html:find("Đoạn ba &lt;thẻ&gt; giữ nguyên dấu.", 1, true) ~= nil, "angle brackets escaped")
assert(not chapter.html:find("bad()", 1, true), "script body never reaches the reader")
assert(not chapter.html:find("&#13;", 1, true) and not chapter.html:find("\194\160", 1, true),
    "carriage-return entities and filler spaces never reach the reader")
assert(not chapter.html:find("formcode", 1, true), "the gate block is not part of the text")
assert(not chapter.html:find("<footer", 1, true), "page chrome stays outside the chapter")

responses[chapter_ref.url] = { body = chapterPage("Chương 1: Côn Luân Mâm Ngọc", "Ngắn.") }
assert(T.getChapter(chapter_ref).skipped ~= nil, "a chapter under the source length floor skips")
responses[chapter_ref.url] = { body = chapterPage("Chương 1: Côn Luân Mâm Ngọc", "") }
assert(T.getChapter(chapter_ref).skipped ~= nil, "empty chapter body skips")
responses[chapter_ref.url] = { body = chapterPage("Chương 1: Côn Luân Mâm Ngọc",
    '<div id="formcode"><img src="/theme/img/loading.gif"></div>') }
assert(T.getChapter(chapter_ref).skipped ~= nil, "ad-gated chapter skips instead of bypassing the gate")
responses[chapter_ref.url] = { body = "<html>Không có nội dung chương</html>" }
assert(T.getChapter(chapter_ref).skipped ~= nil, "unparseable chapter body skips")
responses[chapter_ref.url] = { code = 404, body = "gone" }
assert(T.getChapter(chapter_ref).skipped ~= nil, "missing chapter skips instead of aborting the range")
responses[chapter_ref.url] = { code = 429, body = "" }
assert(T.getChapter(chapter_ref) == nil, "rate limit is an error, not a skip")
responses[chapter_ref.url] = { code = 500, body = "" }
assert(T.getChapter(chapter_ref) == nil, "server error is an error, not a skip")
local no_title = { id = chapter_ref.id, series_id = "quy-khu-tien-quoc", url = chapter_ref.url, title = "tên từ mục lục" }
responses[chapter_ref.url] = { body = '<div class="truyen">Một đoạn văn dài hơn năm mươi ký tự để chắc chắn được giữ lại nguyên vẹn.</div>' }
assert(T.getChapter(no_title).title == "tên từ mục lục", "chapter title falls back to the table of contents")
calls = 0
assert(T.getChapter({ id = chapter_ref.id, series_id = "quy-khu-tien-quoc", url = chapter_ref.url,
    locked = true }).skipped ~= nil and calls == 0, "a locked chapter is never fetched")
assert(T.getChapter({ id = chapter_ref.id, series_id = "khac", url = chapter_ref.url }) == nil,
    "chapter from another series refused")
assert(T.getChapter(chapter_ref.id) == nil, "a bare string is not a chapter ref")

Http.get, Http.expired = original[1], original[2]
print("MeTruyenChuVN adapter: URL guard, listings, ajax chapter list and chapter gates passed")
