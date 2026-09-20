-- Truyendich adapter: reference parsing, the HTML list pages, the JSON search and
-- table of contents endpoints, the HTML table of contents fallback and chapters.
package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path
local T = require("booxbook.sources.truyendich")
local H = require("booxbook.http")
local original_get, original_json, original_expired = H.get, package.loaded.json, H.expired

assert(T.id == "truyendich" and T.kind == "novel" and T.capabilities.login == false)
assert(T.capabilities.search and T.capabilities.browse)
assert(T.view.base_url == "https://truyendich.space" and T.view.cover_referer == "https://truyendich.space/")
assert(T.view.cover_delay_ms == 1600)
assert(T.view.is_ref("https://truyendich.space/doc-truyen/tang-than-quan"))
assert(T.view.is_ref("/doc-truyen/tang-than-quan"))
assert(not T.view.is_ref("táng thần quan"))
assert(#T.view.browse == 3, "three catalogue lists")
assert(not T.capabilities.adult, "the site publishes no adult section")

-- ---- parseRef: accept, reject, chapter-vs-series -------------------------
assert(T.parseRef("https://truyendich.space/doc-truyen/tang-than-quan") == "tang-than-quan")
assert(T.parseRef("https://truyendich.space/doc-truyen/tang-than-quan/") == "tang-than-quan")
assert(T.parseRef("/doc-truyen/tang-than-quan?page=2") == "tang-than-quan")
assert(T.parseRef("https://www.truyendich.ai/doc-truyen/tang-than-quan#x") == "tang-than-quan",
    "an older domain still resolves")
local book, cid, cpath = T.parseRef("https://truyendich.space/doc-truyen/tang-than-quan/chuong-12")
assert(book == "tang-than-quan" and cid == "12" and cpath == "/doc-truyen/tang-than-quan/chuong-12")
local cv_book, cv_id, cv_path = T.parseRef("https://truyendich.space/doc-truyen/cv/tang-than-quan/chuong-7")
assert(cv_book == "tang-than-quan" and cv_id == "7")
assert(cv_path == "/doc-truyen/cv/tang-than-quan/chuong-7", "the convert edition path is kept")
local series_only, no_chapter = T.parseRef("/doc-truyen/tang-than-quan/")
assert(series_only == "tang-than-quan" and no_chapter == nil)
assert(not T.parseRef("https://evil.test/doc-truyen/tang-than-quan"))
assert(not T.parseRef("https://truyendich.space.evil.test/doc-truyen/x"))
assert(not T.parseRef("/doc-truyen/tang-than-quan/chuong-0"), "chapter 0 is refused")
assert(not T.parseRef("/doc-truyen/tang-than-quan/chuong-x"))
assert(not T.parseRef("/doc-truyen/"))
assert(not T.parseRef("/../doc-truyen/x"))
assert(not T.parseRef(nil) and not T.parseRef(12) and not T.parseRef({}))
assert(T.locate{ url = "https://truyendich.space/doc-truyen/tang-than-quan" } == "tang-than-quan")
local loc_id, loc_path = T.locate{ url = "https://truyendich.space/doc-truyen/tang-than-quan/chuong-3" }
assert(loc_id == "tang-than-quan" and loc_path == nil, "a chapter ref has no series path")

-- ---- stubs ---------------------------------------------------------------
-- Newest rule first: a later serve() overrides an earlier one, so each scenario
-- only has to state what it changes.
local calls, last_url, rules, json_bodies, json_id = 0, nil, {}, {}, 0
local function jsonOf(data)
    json_id = json_id + 1
    local key = "json:" .. json_id
    json_bodies[key] = data
    return key
end
local function serve(rule)
    table.insert(rules, 1, rule)
end
H.get = function(url, opts)
    calls, last_url = calls + 1, url
    assert(opts.delay_ms >= 1600, "delay_ms must stay bounded")
    assert(type(opts.referer) == "string", "referer required")
    for _, rule in ipairs(rules) do
        if url:find(rule.match, 1, true) then
            local body = rule.dynamic and rule.dynamic(url) or rule.data
            if body then return true, 200, jsonOf(body) end
            if rule.code and rule.code >= 400 then return false, rule.code, rule.body end
            return true, 200, rule.body
        end
    end
    return false, 404, nil
end
package.loaded.json = { decode = function(body) return json_bodies[body] end }

local function item(slug, title, cover)
    return '<div class="group flex gap-4"><a class="shrink-0" href="/doc-truyen/' .. slug .. '">'
        .. '<img alt="' .. title .. '" src="' .. cover .. '"/></a>'
        .. '<a class="block" href="/doc-truyen/' .. slug .. '"><h3>' .. title .. '</h3></a></div>'
end
local function grid(count)
    local parts = { '<h2 id="new-updated-heading">Mới Cập Nhật</h2>'
        .. item("hot-one", "Truyện Nổi", "/anh-bia/hot.webp"),
        '<h2 id="list-heading">Tất cả truyện mới</h2>' }
    for index = 1, count do
        parts[#parts + 1] = item("truyen-" .. index, "Truyện " .. index, "/anh-bia/truyen-" .. index .. ".webp?v=1")
    end
    parts[#parts + 1] = '<a href="/doc-truyen/truyen-1/chuong-3">Đọc truyện</a>'
    return table.concat(parts)
end

-- A card whose href is absolute (the home grid style) must still be listed.
local ABSOLUTE_CARD = '<a class="group flex flex-col" href="https://truyendich.space/doc-truyen/absolute-one">'
    .. '<img alt="Ảnh bìa truyện Truyện Tuyệt Đối" src="/anh-bia/absolute.webp"/>'
    .. '<h3><span>Truyện Tuyệt Đối</span></h3></a>'
assert(not T.getSeries("https://evil.test/doc-truyen/x") and calls == 0, "rejected refs cost no request")

-- ---- browse: HTML lists, grid marker, pagination -------------------------
serve{ match = "/danh-sach/truyen-moi", body = grid(20) }
serve{ match = "/danh-sach/truyen-hot", body = grid(2) }
serve{ match = "/danh-sach/truyen-full", body = grid(2) .. ABSOLUTE_CARD }
serve{ match = "/the-loai/tien-hiep", body = grid(2) }
local latest = assert(T.browse("latest", 1))
assert(last_url == "https://truyendich.space/danh-sach/truyen-moi", "page 1 has no ?page=")
assert(#latest.items == 20 and latest.has_more, "a full grid offers the next page")
assert(latest.items[1].title == "Truyện 1" and latest.items[1].name == "Truyện 1")
assert(latest.items[1].url == "https://truyendich.space/doc-truyen/truyen-1")
assert(latest.items[1].ref == "/doc-truyen/truyen-1/")
assert(latest.items[1].cover == "https://truyendich.space/anh-bia/truyen-1.webp?v=1")
for _, listed in ipairs(latest.items) do
    assert(listed.title ~= "Truyện Nổi", "the featured section above the grid is not listed")
end
local popular = assert(T.browse("popular", 1))
assert(last_url == "https://truyendich.space/danh-sach/truyen-hot" and #popular.items == 2)
assert(not popular.has_more, "a short grid is the last page")
local full = assert(T.browse("full", 1))
assert(#full.items == 3 and full.items[3].title == "Truyện Tuyệt Đối", "an absolute href is still listed")
assert(full.items[3].url == "https://truyendich.space/doc-truyen/absolute-one")
assert(full.items[3].cover == "https://truyendich.space/anh-bia/absolute.webp")
assert(last_url == "https://truyendich.space/danh-sach/truyen-full")
assert(#assert(T.browse("tien-hiep", 3)).items == 2)
assert(last_url == "https://truyendich.space/the-loai/tien-hiep?page=3", "genre pages paginate")
assert(not T.browse("khong-co"), "unknown kind is rejected")
assert(not T.browse("latest", 0) and not T.browse("latest", 10001) and not T.browse("latest", 1.5))
serve{ match = "/danh-sach/truyen-moi", body = '<html>chrome only</html>' }
local empty = assert(T.browse("latest", 2))
assert(#empty.items == 0 and not empty.has_more, "an empty later page is not an error")
assert(not T.browse("latest", 1), "an empty first page fails closed")

-- ---- search: JSON endpoint ----------------------------------------------
serve{ match = "/api/novels/search?q=Tang%20Than", data = { total = 42, page = 1, size = 20, items = {
    { slug = "tang-than-quan", title = "Táng Thần Quan", image_url = "/anh-bia/tang-than-quan-12490.webp?v=9" },
    { slug = "tang-than-quan-2", title = "Táng Thần Quan 2", image_url = nil },
} } }
local found = assert(T.search("Tang Than", 1))
assert(#found.items == 2 and found.has_more, "42 hits over a 20 item page means more")
assert(found.items[1].ref == "/doc-truyen/tang-than-quan/" and found.items[1].name == "Táng Thần Quan")
assert(found.items[1].url == "https://truyendich.space/doc-truyen/tang-than-quan")
assert(found.items[1].cover == "https://truyendich.space/anh-bia/tang-than-quan-12490.webp?v=9")
assert(found.items[2].cover == nil, "a missing cover stays missing")
assert(last_url:find("/api/novels/search?q=Tang%20Than&page=1&size=20", 1, true), last_url)
assert(not T.search("") and not T.search(("x"):rep(301)) and not T.search("x", 0))
serve{ match = "/api/novels/search?q=broken", data = { total = 1, items = { { slug = "%2f", title = "Bad" } } } }
assert(not T.search("broken"), "a malformed hit fails closed")
serve{ match = "/api/novels/search?q=html", body = "<html>not json</html>" }
assert(not T.search("html"), "a non-JSON body is reported, not parsed")

-- ---- getSeries: metadata, JSON table of contents -------------------------
local STORY = '<h1 class="text-3xl">Táng Thần Quan</h1>'
    .. '<span>Tác giả</span></div><p class="font-bold truncate">Phù Sinh Nhất Nặc</p>'
    .. '<div class="prose prose-gray">Tóm tắt &amp; mở đầu &lt;hay&gt;</div>'
    .. '<a href="/the-loai/huyen-huyen">Huyền Huyễn</a><a href="/the-loai/huyen-huyen">Huyền Huyễn</a>'
    .. '<img alt="Táng Thần Quan" src="/anh-bia/tang-than-quan-12490.webp?v=1"/>'
    .. '<a href="/doc-truyen/tang-than-quan/chuong-9" title="Chương 9: Chín">Chương 9: Chín</a>'
serve{ match = "/doc-truyen/tang-than-quan", body = STORY }
serve{ match = "/chapters?page=1", data = { total = 3, page = 1, size = 200, items = {
    { chapter_number = 3, title = "Ba", status = "COMPLETED" },
    { chapter_number = 1, title = "Chương 1: Một", status = "COMPLETED" },
    { chapter_number = 2, title = "Hai", status = "LOCKED" },
    { chapter_number = 2, title = "Hai lần nữa", status = "COMPLETED" },
} } }
local series = assert(T.getSeries("/doc-truyen/tang-than-quan"))
assert(series.id == "tang-than-quan" and series.source_id == "truyendich")
assert(series.title == "Táng Thần Quan" and series.url == "https://truyendich.space/doc-truyen/tang-than-quan")
assert(series.author == "Phù Sinh Nhất Nặc")
assert(series.description == "Tóm tắt & mở đầu <hay>", "entities are decoded")
assert(series.cover == "https://truyendich.space/anh-bia/tang-than-quan-12490.webp?v=1")
assert(#series.tags == 1 and series.tags[1] == "Huyền Huyễn", "tags are deduplicated")
assert(#series.chapters == 3, "duplicate chapter numbers are collapsed")
assert(series.chapters[1].id == "1" and series.chapters[3].id == "3", "chapters are ordered")
assert(series.chapters[1].index == 1 and series.chapters[3].index == 3)
assert(series.chapters[1].url == "https://truyendich.space/doc-truyen/tang-than-quan/chuong-1")
assert(series.chapters[1].title == "Chương 1: Một", "an existing prefix is not repeated")
assert(series.chapters[2].title == "Chương 2: Hai")
assert(series.chapters[3].title == "Chương 3: Ba")
assert(series.chapters[2].locked, "a locked status is carried to the chapter")
assert(not series.truncated)
assert(#series.volumes == 1 and series.volumes[1].title == "Chương")
assert(#series.volumes[1].chapters == 3)
local sid, chapter_id = T.chapterRef(series.chapters[1])
assert(sid == "tang-than-quan" and chapter_id == "1")
local wrong_series = { url = series.chapters[1].url, series_id = "other", title = "x" }
assert(not T.chapterRef(wrong_series), "a chapter from another series is refused")

-- A long table of contents is walked page by page, bounded by the site total.
serve{ match = "/chapters?page=2", data = { total = 201, page = 2, size = 200, items = {
    { chapter_number = 201, title = "Cuối", status = "COMPLETED" },
} } }
serve{ match = "/chapters?page=1", data = { total = 201, page = 1, size = 200, items = {
    { chapter_number = 1, title = "Một", status = "COMPLETED" },
} } }
local paged = assert(T.getSeries("/doc-truyen/tang-than-quan"))
assert(#paged.chapters == 2 and paged.chapters[2].id == "201", "the second page is followed")
assert(last_url:find("page=2", 1, true), "the loop advances")

-- An endpoint that never reports a total must not be walked forever.
serve{ match = "/doc-truyen/endless", body = STORY }
serve{ match = "/api/novels/endless/chapters", dynamic = function(url)
    local page = tonumber(url:match("page=(%d+)")) or 1
    return { page = page, size = 200, items = {
        { chapter_number = page, title = "Chương " .. page, status = "COMPLETED" },
    } }
end }
local endless = assert(T.getSeries("/doc-truyen/endless"))
assert(endless.truncated, "a runaway table of contents stops and keeps what it read")
assert(#endless.chapters == 60, "the walk is capped at MAX_TOC_PAGES, got " .. #endless.chapters)

-- The reader's time budget ends the walk too.
serve{ match = "/api/novels/tang-than-quan/chapters", dynamic = function()
    return { total = 100000, page = 1, size = 200, items = {
        { chapter_number = 1, title = "Một", status = "COMPLETED" },
    } }
end }
H.expired = function() return true end
local budgeted = assert(T.getSeries("/doc-truyen/tang-than-quan"))
assert(budgeted.truncated and #budgeted.chapters == 1, "an expired budget truncates instead of hanging")
H.expired = original_expired

-- Without the JSON endpoint the page's own chapter links are used, truncated.
serve{ match = "/chapters?", code = 404, body = "gone" }
local fallback = assert(T.getSeries("/doc-truyen/tang-than-quan"))
assert(fallback.truncated, "the HTML fallback is marked partial")
assert(#fallback.chapters == 1)
assert(fallback.chapters[1].url == "https://truyendich.space/doc-truyen/tang-than-quan/chuong-9")
assert(fallback.chapters[1].title == "Chương 9: Chín")
serve{ match = "/doc-truyen/tang-than-quan", body = '<html>Link truyện không tìm thấy</html>' }
assert(not T.getSeries("/doc-truyen/tang-than-quan"), "a missing story fails closed")

-- ---- getChapter ----------------------------------------------------------
local chapter = { url = "https://truyendich.space/doc-truyen/tang-than-quan/chuong-1",
    series_id = "tang-than-quan", title = "Chương 1: Một" }
local CHAPTER = '<h1 itemProp="name">Trường An</h1><section class="prose-novel" itemProp="text">'
    .. '<div id="original-content-tab" style="display:block"><p><content></p>'
    .. '<p>Đoạn một &amp; hai</p><script>bad()</script><style>.ad{}</style><p>Đoạn hai</p></div></section>'
serve{ match = "/doc-truyen/tang-than-quan/chuong-1", body = CHAPTER }
local content = assert(T.getChapter(chapter))
assert(content.title == "Chương 1: Một")
assert(content.html:find("<p>Đoạn một &amp; hai</p>", 1, true), "text is kept and re-escaped")
assert(content.html:find("<p>Đoạn hai</p>", 1, true))
assert(not content.html:find("bad", 1, true), "scripts are stripped")
assert(not content.html:find("ad{", 1, true), "styles are stripped")
assert(not content.html:find("<content>", 1, true), "stray tags are stripped")
serve{ match = "/chuong-2", body = '<section class="prose-novel"><div id="original-content-tab">   </div></section>' }
assert(T.getChapter{ url = "https://truyendich.space/doc-truyen/tang-than-quan/chuong-2",
    series_id = "tang-than-quan", title = "x" }.skipped, "an empty chapter skips")
serve{ match = "/chuong-3", body = '<html><div class="overlay-lock">Khóa</div></html>' }
assert(T.getChapter{ url = "https://truyendich.space/doc-truyen/tang-than-quan/chuong-3",
    series_id = "tang-than-quan", title = "x" }.skipped, "a lock overlay skips")
serve{ match = "/chuong-4", code = 404, body = "" }
assert(T.getChapter{ url = "https://truyendich.space/doc-truyen/tang-than-quan/chuong-4",
    series_id = "tang-than-quan", title = "x" }.skipped, "a removed chapter skips")
serve{ match = "/chuong-5", code = 429, body = "" }
assert(not T.getChapter{ url = "https://truyendich.space/doc-truyen/tang-than-quan/chuong-5",
    series_id = "tang-than-quan", title = "x" }, "a rate limit is reported, not swallowed")
assert(not T.getChapter{ url = chapter.url, title = "x" }, "a chapter without a TOC is refused")
assert(not T.getChapter(wrong_series))
assert(T.getChapter{ url = chapter.url, series_id = "tang-than-quan", title = "x", locked = true }
    .skipped == "Chương đã khóa.")
assert(not T.getChapter("https://truyendich.space/doc-truyen/tang-than-quan/chuong-1"))

H.get, package.loaded.json, H.expired = original_get, original_json, original_expired
print("Truyendich references, HTML lists, JSON search/TOC, TOC fallback and chapters passed")
