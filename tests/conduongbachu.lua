package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path

local T = require("booxbook.sources.conduongbachu")
local Http = require("booxbook.http")
local original = { Http.get, Http.expired, package.loaded.json }
local calls, urls = 0, {}
local html_body, status, rest_pages, rest_headers = "", 200, {}, {}

-- The WordPress REST index is real JSON; the stub decoder only needs the two fields
-- the adapter asks for, exactly like the whole-body fixtures below.
package.loaded.json = {
    decode = function(raw)
        if raw:find("BROKEN", 1, true) then return nil end
        if raw:match("^%s*%[%s*%]$") then return {} end
        local posts = {}
        for link, title in raw:gmatch('{"link":"([^"]*)","title":{"rendered":"([^"]*)"}}') do
            posts[#posts + 1] = { link = link, title = { rendered = title } }
        end
        return posts
    end,
    encode = function() return "{}" end,
}

local function responder(url, opts)
    calls = calls + 1
    urls[#urls + 1] = url
    assert(type(opts) == "table" and opts.delay_ms >= 1600, "delay_ms floor on every request")
    assert(opts.referer == "https://conduongbachu.com/", "referer on every request")
    local page = url:match("&page=(%d+)")
    if url:find("/wp%-json/", 1) then
        local content = rest_pages[tonumber(page)]
        if content == nil then return false, 404, "no such rest page" end
        return true, 200, content, rest_headers
    end
    return status == 200, status, html_body
end
Http.get = responder

local function rest(...)
    local parts = {}
    for _, post in ipairs({ ... }) do
        parts[#parts + 1] = string.format('{"link":"%s","title":{"rendered":"%s"}}', post[1], post[2])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end
local function chapter(slug, title)
    return { "https://conduongbachu.com/" .. slug .. "/", title }
end
local function assertContains(value, needle, message)
    assert(type(value) == "string" and value:find(needle, 1, true) ~= nil, message or ("missing: " .. needle))
end

-- Adapter identity and contract surface.
assert(T.id == "conduongbachu" and T.kind == "novel" and T.name == "Con Đường Bá Chủ", "adapter identity")
assert(T.capabilities.search and T.capabilities.browse and not T.capabilities.login, "capabilities")
assert(T.view.base_url == "https://conduongbachu.com" and T.view.is_ref("https://conduongbachu.com/"), "view")
assert(type(T.locate) == "function" and type(T.chapterRef) == "function" and type(T.getSeries) == "function")

-- parseRef: the site root is the main story, spinoffs have their own paths and every
-- chapter is a top-level post slug.
assert(T.parseRef("https://conduongbachu.com/") == "chapter-truyen", "site root is the main story")
assert(T.parseRef("https://conduongbachu.com/chapter-truyen/") == "chapter-truyen", "chapter archive is the same story")
assert(T.parseRef({ url = "https://conduongbachu.com/ngoai-truyen/" }) == "ngoai-truyen", "table ref")
assert(T.parseRef("/ngoai-truyen-van-dao-than-chu/") == "ngoai-truyen-van-dao-than-chu", "spinoff path")
assert(T.parseRef("/ngoai-truyen-chua-te-chi-lo") == "ngoai-truyen-chua-te-chi-lo", "spinoff without slash")
local book, chapter_id, chapter_path = T.parseRef("https://conduongbachu.com/chuong-1-hai-so-phan/")
assert(book == "chapter-truyen" and chapter_id == "chuong-1-hai-so-phan", "chapter of the main story")
assert(chapter_path == "/chuong-1-hai-so-phan/", "chapter path rebuilt from the slug")
local legacy, legacy_id = T.parseRef("/3399-vo-de/?utm=1#top")
assert(legacy == "chapter-truyen" and legacy_id == "3399-vo-de", "legacy numeric slug, query and fragment dropped")
local numbered_legacy, numbered_legacy_id = T.parseRef("/1-x/")
assert(numbered_legacy == "chapter-truyen" and numbered_legacy_id == "1-x", "short legacy numeric slug")
for _, ref in ipairs({ "https://evil.test/chuong-1-x/", "https://conduongbachu.com.evil.test/chuong-1-x/",
    "/gioi-thieu/", "/chuong-abc/", "/ab", "khong-phai-url" }) do
    assert(T.parseRef(ref) == nil, "rejected: " .. ref)
end
assert(T.locate({ url = "https://conduongbachu.com/" }) == "chapter-truyen", "locate series id")
assert(T.locate({ url = "https://conduongbachu.com/chuong-1-hai-so-phan/" }) == "chapter-truyen", "locate chapter id")
local locate_id, locate_path = T.locate({ url = "https://conduongbachu.com/" })
assert(locate_id == "chapter-truyen" and locate_path == "chapter-truyen", "locate returns a folder id")
local ref_series, ref_chapter = T.chapterRef({ id = chapter_id, series_id = "ngoai-truyen",
    url = "https://conduongbachu.com/" .. chapter_id .. "/" })
assert(ref_series == "ngoai-truyen" and ref_chapter == chapter_id, "chapterRef keeps the listed story")

-- A foreign ref must never reach the network.
local before = calls
assert(not T.getSeries("https://evil.test/chuong-1-x/") and calls == before, "foreign host never fetched")
assert(not T.getChapter({ url = "https://evil.test/chuong-1-x/" }) and calls == before, "foreign chapter never fetched")

-- Browse: four series on one shelf, single fixed page.
local listed = assert(T.browse("latest", 1))
assert(#listed.items == 4 and listed.has_more == false, "browse lists the four series")
assert(listed.items[1].ref == "/" and listed.items[1].url == "https://conduongbachu.com/", "main item ref/url")
assert(listed.items[1].title == "Con Đường Bá Chủ (Chính Truyện)" and listed.items[1].name == listed.items[1].title)
assert(listed.items[1].cover == nil, "no webp cover for the main story")
assertContains(listed.items[2].cover, ".jpg", "spinoff cover")
assert(#assert(T.browse("ngoai-truyen", 1)).items == 1, "genre browse narrows to one story")
assert(#assert(T.browse("latest", 2)).items == 0, "there is no second page")
assert(type(select(2, T.browse("khong-co"))) == "string", "unknown list kind rejected")
assert(type(select(2, T.browse("latest", 0))) == "string", "invalid page rejected")

-- Search matches the four titles with accent folding and never hits the network.
assert(T.search("vạn đạo").items[1].ref == "/ngoai-truyen-van-dao-than-chu/", "accented title search")
assert(#T.search("van dao").items == 1, "unaccented query still matches")
assert(#T.search("ba chu").items == 4, "the source matched 'ba chu' against every story")
assert(#T.search("BÁ CHỦ").items == 4, "case insensitive")
assert(#T.search("chính truyện").items == 1, "partial title")
assert(#T.search("khong-co-truyen-nao").items == 0, "no match returns no item")
assert(T.search("vạn đạo", 2).items[1] == nil, "search has no second page")
assert(type(select(2, T.search("   "))) == "string", "blank query rejected")
assert(calls == before, "browse and search never fetch anything")

local seen_keys, seen_names = {}, {}
for _, genre in ipairs(T.genres) do
    assert(not seen_keys[genre.key] and not seen_names[genre.name], "duplicate genre entry")
    assert(genre.key:match("^[a-z0-9%-]+$"), "genre key must be URL-safe: " .. genre.key)
    assert(not genre.adult, "this site has no adult shelf")
    seen_keys[genre.key], seen_names[genre.name] = true, true
end
assert(#T.genres == 4, "one genre entry per series")

-- getSeries over the WordPress index: pagination, the non-chapter post filter,
-- legacy slugs, de-duplication and ordering.
html_body = '<meta name="description" content="Tóm tắt con đường bá chủ của tác giả Akay Hau">'
html_body = html_body:gsub("&", "&amp;")
rest_headers = { ["X-WP-Total"] = "6", ["X-WP-TotalPages"] = "2" }
rest_pages = {
    [1] = rest(chapter("chuong-2-hai", "Chương 2: Hai"), chapter("chuong-1-mot", "Chương 1: Một"),
        chapter("chuong-1-mot-lai", "Chương 1: Một (lại)")),
    [2] = rest(chapter("3399-vo-de", "3399: VÔ ĐỀ."), chapter("chuong-3-ba", "Chương 3: Ba"),
        chapter("chuong-4-bon", "Chương 4: Bốn")),
}
calls = 0
local series = assert(T.getSeries("/chapter-truyen/"))
assert(#series.chapters == 6, "chapter count: " .. #series.chapters)
assert(calls == 3, "one story page plus two index pages, got " .. calls)
assert(series.id == "chapter-truyen" and series.source_id == "conduongbachu", "series identity")
assertContains(series.url, "https://conduongbachu.com/", "series url")
assertContains(series.description, "Tóm tắt con đường bá chủ", "description from the meta tag")
assert(series.author == "Akay Hau", "author from the description, fallback to the known author")
assert(series.chapters[1].id == "chuong-1-mot" and series.chapters[1].number == 1, "first chapter")
assert(series.chapters[2].id == "chuong-1-mot-lai" and series.chapters[2].number == 1,
    "posts sharing a rendered number stay distinct and are ordered by id")
assert(series.chapters[3].id == "chuong-2-hai" and series.chapters[4].id == "chuong-3-ba", "ascending order")
assert(series.chapters[5].id == "chuong-4-bon" and series.chapters[6].id == "3399-vo-de", "legacy slug sorts last")
assert(series.chapters[6].number == 3399 and series.chapters[6].index == 6, "legacy slug numbered and indexed")
assert(series.chapters[1].index == 1, "index assigned in order")
assert(series.chapters[1].series_id == "chapter-truyen", "chapters carry their series")
assert(series.chapters[1].url == "https://conduongbachu.com/chuong-1-mot/", "chapter url rebuilt from the slug")
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters, "single volume wraps the chapters")

-- The same shape for a spinoff: a vote post is not a chapter and a repeated link is
-- listed once, but the story is allowed to end up shorter than the post total.
rest_headers = { ["X-WP-Total"] = "4", ["X-WP-TotalPages"] = "1" }
rest_pages = { [1] = rest(chapter("bau-chon-ngoai-truyen", "Bầu chọn ngoại truyện"),
    chapter("chuong-1-lich-su", "Chương 1: LỊCH SỬ"), chapter("chuong-1-lich-su", "Chương 1: LỊCH SỬ"),
    chapter("chuong-2-tre-nho", "Chương 2: TRẺ NHỎ")) }
local spinoff = assert(T.getSeries("/ngoai-truyen/"))
assert(#spinoff.chapters == 2, "vote post dropped and duplicate link listed once: " .. #spinoff.chapters)
assert(spinoff.chapters[1].number == 1 and spinoff.chapters[2].number == 2, "spinoff order")
assert(spinoff.truncated == nil, "no truncation flag when the index was complete")

-- The main story must not report a partial index as success.
rest_headers = { ["X-WP-Total"] = "6", ["X-WP-TotalPages"] = "1" }
rest_pages = { [1] = rest(chapter("chuong-1-mot", "Chương 1: Một")) }
local partial, partial_err = T.getSeries("/chapter-truyen/")
assert(not partial and partial_err, "partial index is not success")
assertContains(partial_err, "Mục lục", "partial index error explains itself")
rest_headers = { ["X-WP-Total"] = "3", ["X-WP-TotalPages"] = "1" }
rest_pages = { [1] = rest(chapter("chuong-1-mot", "Chương 1: Một"), chapter("chuong-2-hai", "Chương 2: Hai"),
    chapter("bau-chon-ngoai-truyen", "Bầu chọn ngoại truyện")) }
local short_story, short_err = T.getSeries("/chapter-truyen/")
assert(not short_story and short_err, "main story missing a chapter fails closed")
assertContains(short_err, "chính truyện", "main story error names the story")

-- Malformed JSON and a failed first page are errors, not a truncated success.
rest_headers = {}
rest_pages = { [1] = "BROKEN" }
assert(not T.getSeries("/chapter-truyen/"), "malformed index JSON fails closed")
rest_pages = { [1] = nil }
assert(not T.getSeries("/chapter-truyen/"), "first index page failure fails closed")
local failed_err = select(2, T.getSeries("/chapter-truyen/"))
assertContains(failed_err, "HTTP 404", "http failure is reported with its code")

-- A page that keeps handing out pages must stop at the cap and keep what it read.
calls = 0
rest_headers = { ["X-WP-Total"] = "9999", ["X-WP-TotalPages"] = "99" }
Http.get = function(url, opts)
    calls = calls + 1
    assert(opts.delay_ms >= 1600 and opts.referer == "https://conduongbachu.com/", "index request options")
    local page = tonumber(url:match("&page=(%d+)"))
    if url:find("/wp%-json/", 1) then
        return true, 200, rest(chapter("chuong-" .. page .. "-x", "Chương " .. page .. ": X")), rest_headers
    end
    return true, 200, '<meta name="description" content="Tóm tắt">'
end
local endless = assert(T.getSeries("/chapter-truyen/"))
assert(endless.truncated, "endless index is truncated, not spun forever")
assert(calls <= 61, "index stops at the page cap, calls=" .. calls)
assert(#endless.chapters >= 1, "chapters already read are kept")

-- The action time budget also stops the loop.
Http.expired = function() return true end
calls = 0
local budgeted = assert(T.getSeries("/chapter-truyen/"))
assert(budgeted.truncated and calls <= 2, "expired action budget stops paging")
Http.expired = original[2]

-- getChapter: content extraction on a chapter page shaped like the live theme.
Http.get = responder
html_body = table.concat({
    '<h1 class="entry-title">Chương 5: Niềm vui &amp; nỗi buồn</h1>',
    '<div class="entry-content single-page">',
    '<select class="chapter-selector"><option value="/chuong-1-mot/">Chương 1: Một</option></select>',
    '<p>Đoạn một <strong>in đậm</strong> &amp; chữ.</p>',
    '<p class="post-tts-meta">NGHE TRUYỆN</p>',
    '<p>Truyện Con Đường Bá Chủ. Nếu muốn tìm chương khác vui lòng nhấp vào ô</p>',
    '<p>Xem truyện <a href="https://conduongbachu.com/">con đường bá chủ</a> tại conduongbachu.com</p>',
    '<svg><polyline points="15 18 9 12 15 6"/></svg>',
    '<p>Đoạn hai<script>bad()</script><style>.x{}</style> còn lại.</p>',
    '<p>?</p>',
    '</div>',
    '<nav id="nav-below"><a rel="prev" href="/chuong-4-bon/">Chương trước</a></nav>',
}, "")
local mid = { id = "chuong-5-niem-vui", series_id = "chapter-truyen",
    url = "https://conduongbachu.com/chuong-5-niem-vui/", title = "old title", index = 5 }
local content = assert(T.getChapter(mid))
assertContains(content.title, "Chương 5: Niềm vui & nỗi buồn", "chapter title decoded")
local paragraphs = 0
for _ in content.html:gmatch("<p>") do paragraphs = paragraphs + 1 end
assert(paragraphs == 2, "only real paragraphs are kept, got " .. paragraphs)
assertContains(content.html, "Đoạn một in đậm &amp; chữ.", "entities decoded then escaped, tags dropped")
assertContains(content.html, "Đoạn hai còn lại.", "script and style stripped from the paragraph")
assert(not content.html:find("bad()", 1, true), "script body never reaches the reader")
assert(not content.html:find("NGHE TRUYỆN", 1, true), "text-to-speech line dropped")
assert(not content.html:find("Nếu muốn tìm chương khác", 1, true), "source intro dropped")
assert(not content.html:find("conduongbachu.com", 1, true), "source promo line dropped")
assert(not content.html:find("<option", 1, true) and not content.html:find("Chương 1: Một", 1, true),
    "chapter selector never leaks into the text")
assert(not content.html:find("<polyline", 1, true) and not content.html:find("<svg", 1, true),
    "inline svg tags never leak into the text")
assert(not content.html:find("nav-below", 1, true), "navigation stays outside the article")

-- Locked, empty and unparseable chapters skip instead of aborting the range.
html_body = '<div class="entry-content"><p>Teaser</p><button>Mở khóa</button></div>'
assert(type(T.getChapter(mid).skipped) == "string", "lock button inside the body skips")
html_body = '<div class="entry-content">&nbsp;</div><button>Mở khóa</button>'
assertContains(T.getChapter(mid).skipped, "khóa", "lock marker skips")
html_body = '<div class="entry-content"><p>Mở khóa chương này để đọc tiếp</p><button>Mở khóa</button></div>'
assertContains(T.getChapter(mid).skipped, "khóa", "lock copy plus lock button skips")
html_body = '<div class="entry-content">   </div>'
assert(type(T.getChapter(mid).skipped) == "string", "empty chapter skips")
html_body = "<html>Captcha</html>"
assert(type(T.getChapter(mid).skipped) == "string", "unparseable chapter body skips")
status = 404
assert(type(T.getChapter(mid).skipped) == "string", "missing chapter skips rather than aborting")
status = 200
status = 429
assert(T.getChapter(mid) == nil, "rate limit is an error, not a skip")
status = 200
local locked_ref = { id = mid.id, series_id = "chapter-truyen", url = mid.url, locked = true }
assert(T.getChapter(locked_ref).skipped ~= nil, "chapter marked locked skips")
local locked_calls = calls
assert(T.getChapter(locked_ref).skipped ~= nil and calls == locked_calls, "locked chapter is never fetched")
local foreign_chapter = T.getChapter({ id = mid.id, series_id = "other", url = mid.url })
assert(foreign_chapter == nil, "a chapter flagged for another series is refused, not skipped")
assert(T.getChapter({ id = "chuong-5-niem-vui", series_id = "khac", url = mid.url }) == nil,
    "chapter from another series refused")
assert(T.getChapter(mid.id) == nil, "a bare string is not a chapter ref")

Http.get, Http.expired, package.loaded.json = original[1], original[2], original[3]
print("ConDuongBachu adapter: URL shapes, listing, WordPress index and chapter gates passed")
