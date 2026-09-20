package.loaded["gettext"] = package.loaded["gettext"] or function(s) return s end

-- Every JSON body from the Storya API is a fixture key, so the decode stub below
-- never has to parse anything (KOReader ships json, a bare LuaJIT does not).
local original_json = package.loaded["json"]
local SLUG = "cau-tha-thanh-thanh-nhan-tien-quan-trieu-ta-cham-ngua"
local FIXTURES = {
    search = { data = {
        { id = 76, slug = SLUG, title = "Cẩu Thả Thành Thánh Nhân", coverUrl = "/media/covers/cau-tha.jpg" },
    }, meta = { total = 4, page = 1, limit = 20, totalPages = 2 } },
    search_last = { data = {
        { id = 929, slug = "lau-tren-lau-duoi", title = "Lầu Trên Lầu Dưới", coverUrl = "https://cdn.storya.test/x.jpg" },
    }, meta = { total = 4, page = 2, limit = 20, totalPages = 2 } },
    list = { data = {
        { id = 76, slug = SLUG, title = "Cẩu Thả Thành Thánh Nhân", coverUrl = "/media/covers/cau-tha.jpg" },
    }, meta = { total = 3522, page = 1, limit = 20, totalPages = 3 } },
    hot = { data = {
        { id = 76, slug = SLUG, title = "Cẩu Thả Thành Thánh Nhân", coverUrl = "/media/covers/cau-tha.jpg" },
    }, meta = { total = 20, page = 1, limit = 20, totalPages = 1 } },
    genre = { data = { id = 1, name = "Linh Dị", slug = "linh-di", description = "x", stories = {
        { id = 1588, slug = "sieu-cap-cung-chieu-446045", title = "Siêu Cấp Cưng Chiều" },
    } } },
    genre_adult = { data = { id = 68, name = "Sắc", slug = "sac", stories = {
        { id = 99, slug = "truyen-nguoi-lon", title = "Truyện Người Lớn" },
    } } },
    story = { data = {
        id = 76, slug = SLUG, title = "Cẩu Thả Thành Thánh Nhân, Tiên Quan Triệu Ta Chăm Ngựa",
        description = "", rewrittenDescription = "Tu tiên là gì? Là đoạt thiên địa tạo hóa.",
        coverUrl = "/media/covers/cau-tha.jpg", status = "COMPLETED", isLocked = false,
        author = { id = 8, name = "Nhâm Ngã Tiếu", slug = "nham-nga-tieu" },
        genres = { { id = 6, name = "Hệ Thống", slug = "he-thong" }, { id = 10, name = "Tiên Hiệp", slug = "tien-hiep" } },
    } },
    story_adult = { data = {
        id = 99, slug = "truyen-nguoi-lon", title = "Truyện Người Lớn", coverUrl = "/media/covers/nl.jpg",
        author = { name = "Khuyết Danh" }, genres = { { name = "Sắc", slug = "sac" } },
    } },
    chapters = { data = {
        { id = 56615, slug = "chuong-1", title = "Chương 1: Chiếm lấy tuổi thọ", order = 1 },
        -- The minimal listing does not send isLocked today; the adapter still
        -- honours it, so the fixture exercises that path.
        { id = 56616, slug = "chuong-2", title = "Chương 2: Ngàn năm tuổi thọ", order = 2, isLocked = true },
    }, meta = { total = 1115, page = 1, limit = 100, totalPages = 2 } },
    -- The second page repeats chapter 1: it must be dropped, not duplicated.
    chapters_last = { data = {
        { id = 56615, slug = "chuong-1", title = "Chương 1: Chiếm lấy tuổi thọ", order = 1 },
        { id = 57729, slug = "chuong-1131-2", title = "Chương 1131-2: Đại Chung Nguyên", order = 1131 },
    }, meta = { total = 1115, page = 2, limit = 100, totalPages = 2 } },
    chapters_repeat = { data = {
        { id = 56615, slug = "chuong-1", title = "Chương 1", order = 1 },
    }, meta = { total = 400, page = 1, limit = 100, totalPages = 4 } },
    chapter = { data = {
        id = 56615, slug = "chuong-1", title = "Chương 1: Chiếm lấy tuổi thọ", order = 1,
        content = "Dưới ánh mặt trời chói chang, bầu trời xanh ngắt.\n\nCố An lau mồ hôi trên trán &amp; mỉm cười.\n"
            .. "<script>ads()</script><style>.ads{}</style><iframe src=\"//x\"></iframe>",
    } },
    chapter_locked = { data = {
        id = 57729, slug = "chuong-1131-2", title = "Chương 1131-2", isLocked = true, content = "Đoạn mở đầu.",
    } },
    chapter_empty = { data = { id = 56615, slug = "chuong-1", title = "Chương 1", content = "" } },
    chapter_other = { data = { id = 1, slug = "chuong-9", title = "Chương khác", content = "Nội dung." } },
}
package.loaded["json"] = {
    decode = function(body)
        if body == "not-json" then error("invalid JSON") end
        local endless = body:match("^endless:(%d+)$")
        if endless then
            return { data = { { id = tonumber(endless), slug = "chuong-" .. endless,
                title = "Chương " .. endless, order = tonumber(endless) } },
                meta = { total = 999999, page = tonumber(endless), limit = 100, totalPages = 9999 } }
        end
        assert(FIXTURES[body], "unexpected JSON body: " .. tostring(body))
        return FIXTURES[body]
    end,
    encode = function() return "{}" end,
}

local B = require("booxbook.sources.storyaclick")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")

assert(B.id == "storyaclick" and B.name == "Storya" and B.kind == "novel", "adapter identity")
assert(B.capabilities.search and B.capabilities.browse and not B.capabilities.login, "capabilities")
assert(B.capabilities.adult, "Storya carries an 18+ genre")

local original_get = Http.get
local calls, last_url, status = 0, nil, 200
local respond = function() return "" end
Http.get = function(url, opts)
    calls, last_url = calls + 1, url
    assert(opts.delay_ms >= 1600, "delay floor")
    assert(opts.referer == "https://storya.click/", "referer is the site root")
    assert(opts.allow_url, "host allow list")
    assert(opts.allow_url("https://storya.click/truyen/x"), "site host allowed")
    assert(not opts.allow_url("https://evil.test/api/v1/stories"), "foreign host blocked")
    assert(opts.headers.Accept == "application/json", "API asks for JSON")
    return status == 200, status, respond(url)
end

-- parseRef: series and chapter refs, both hosts, junk refused.
assert(B.parseRef("https://storya.click/truyen/" .. SLUG) == SLUG)
assert(B.parseRef("https://www.storya.click/truyen/" .. SLUG .. "?utm=1") == SLUG)
assert(B.parseRef("/truyen/" .. SLUG .. "/") == SLUG)
local slug, chapter_id = B.parseRef("https://storya.click/truyen/" .. SLUG .. "/chuong-1131-2#top")
assert(slug == SLUG and chapter_id == "chuong-1131-2", "chapter slug is the chapter id")
assert(B.parseRef("https://evil.test/truyen/" .. SLUG) == nil, "foreign host rejected")
assert(B.parseRef("https://storya.evil.test/truyen/" .. SLUG) == nil, "lookalike host rejected")
assert(B.parseRef("/truyen/") == nil and B.parseRef("/khac/a") == nil and B.parseRef("") == nil
    and B.parseRef(nil) == nil, "garbage rejected")
assert(not B.getSeries("https://evil.test/truyen/" .. SLUG) and calls == 0, "no request for foreign ref")
assert(not B.getSeries("https://storya.click/truyen/" .. SLUG .. "/chuong-1") and calls == 0,
    "a chapter URL is not a series ref")

local located, path = B.locate({ url = "https://storya.click/truyen/" .. SLUG })
assert(located == SLUG and path == SLUG, "locate maps series to its folder")
located, path = B.locate({ url = "https://storya.click/truyen/" .. SLUG .. "/chuong-1" })
assert(located == SLUG and path == nil, "a chapter ref has no series path")
local ref = { url = "https://storya.click/truyen/" .. SLUG .. "/chuong-1131-2", series_id = SLUG }
local ref_series, ref_id, ref_max = B.chapterRef(ref)
assert(ref_series == SLUG and ref_id == "chuong-1131-2", "chapterRef pairs series and chapter")
assert(ref_max == 32, "long chapter slugs are allowed")
ref.series_id = "khac"
assert(B.chapterRef(ref) == nil, "chapterRef refuses a chapter from another series")

-- search.
respond = function() return "search" end
local found = assert(B.search("cẩu thả", 1))
assert(#found.items == 1 and found.items[1].ref == "/truyen/" .. SLUG, "search maps slugs to refs")
assert(found.items[1].title == "Cẩu Thả Thành Thánh Nhân" and found.items[1].cover ==
    "https://storya.click/media/covers/cau-tha.jpg", "relative covers are absolute-ised")
assert(found.items[1].url == "https://storya.click/truyen/" .. SLUG, "search builds the site URL")
assert(found.has_more and last_url:find("q=c%E1%BA%A9u+th%E1%BA%A3", 1, true), "spaces become +: " .. last_url)
respond = function() return "search_last" end
assert(not B.search("cẩu thả", 2).has_more, "last search page stops")
assert(not B.search("") and not B.search(string.rep("a", 301)) and not B.search("x", 0),
    "bad search input rejected")
respond = function() return "not-json" end
local items, err = B.search("cẩu", 1)
assert(not items and type(err) == "string" and err:find("Storya", 1, true), "malformed JSON is readable")

-- browse: latest, hot, genre and 18+ gating.
respond = function() return "list" end
local listed = assert(B.browse("latest", 1))
assert(#listed.items == 1 and listed.items[1].title == "Cẩu Thả Thành Thánh Nhân", "latest list")
assert(listed.has_more and last_url == "https://storya.click/api/v1/stories?page=1&limit=20", "latest URL")
respond = function() return "hot" end
local hot = assert(B.browse("popular", 1))
assert(#hot.items == 1 and not hot.has_more and last_url == "https://storya.click/api/v1/stories/hot?page=1&limit=20",
    "hot list URL")
assert(not B.browse("khong-co") and not B.browse("latest", 0), "bad browse input rejected")
local genre_url
respond = function(url) genre_url = url; return "genre" end
local genre = assert(B.browse("linh-di", 1))
assert(#genre.items == 1 and genre.items[1].ref == "/truyen/sieu-cap-cung-chieu-446045", "genre list")
assert(genre_url == "https://storya.click/api/v1/genres/slug/linh-di", "genre slug endpoint: " .. genre_url)
assert(not genre.has_more, "the genre endpoint has no pagination")
local before = calls
assert(not B.browse("linh-di", 2).items[1] and calls == before, "genre page 2 asks the site nothing")
assert(not B.browse("sac"), "adult genre blocked while 18+ is off")
Settings.set("adult_content", true)
respond = function() return "genre_adult" end
local adult = assert(B.browse("sac", 1))
assert(#adult.items == 1 and adult.items[1].title == "Truyện Người Lớn", "adult genre allowed when 18+ is on")
Settings.set("adult_content", false)
assert(not B.browse("sac"), "adult genre blocked again once 18+ is off")
local seen_keys, seen_names = {}, {}
for _, entry in ipairs(B.genres) do
    assert(not seen_keys[entry.key], "duplicate genre key: " .. entry.key)
    assert(not seen_names[entry.name], "duplicate genre name: " .. entry.name)
    assert(entry.key:match("^[a-z0-9%-]+$"), "genre key must be URL-safe: " .. entry.key)
    seen_keys[entry.key], seen_names[entry.name] = true, true
end
assert(seen_keys["sac"] and #B.genres > 60, "the site's genre list is wired")

-- getSeries: JSON metadata plus the paginated chapter list.
local story_url = "https://storya.click/api/v1/stories/" .. SLUG
respond = function(url)
    if url == story_url then return "story" end
    if url == "https://storya.click/api/v1/stories/truyen-nguoi-lon" then return "story_adult" end
    if url:find("/chapters/story/", 1, true) then
        return url:find("page=2", 1, true) and "chapters_last" or "chapters"
    end
    return "chapter"
end
local series = assert(B.getSeries("/truyen/" .. SLUG))
assert(series.id == SLUG and series.source_id == "storyaclick", "series identity")
assert(series.title == "Cẩu Thả Thành Thánh Nhân, Tiên Quan Triệu Ta Chăm Ngựa", "series title")
assert(series.author == "Nhâm Ngã Tiếu", "author comes from the nested object")
assert(series.description == "Tu tiên là gì? Là đoạt thiên địa tạo hóa.", "empty description falls back")
assert(series.cover == "https://storya.click/media/covers/cau-tha.jpg", "relative cover absolute-ised")
assert(#series.tags == 2 and series.tags[1] == "Hệ Thống", "genres become tags")
assert(not series.adult, "a story without the Sắc genre is not adult")
assert(#series.chapters == 3, "both pages read, duplicate dropped: " .. #series.chapters)
assert(series.chapters[1].id == "chuong-1" and series.chapters[3].id == "chuong-1131-2", "chapter ids are slugs")
assert(series.chapters[3].order == 1131 and series.chapters[3].index == 3, "order keeps the site numbering")
assert(series.chapters[1].series_id == SLUG and series.chapters[1].locked == false, "chapter fields")
assert(series.chapters[2].locked, "a locked chapter from the listing keeps its flag")
assert(series.chapters[3].url == "https://storya.click/truyen/" .. SLUG .. "/chuong-1131-2", "chapter URL")
assert(#series.volumes == 1 and series.volumes[1].chapters == series.chapters, "one volume holds them all")
assert(not series.truncated, "a two page table of contents is complete")
local adult_series = assert(B.getSeries("/truyen/truyen-nguoi-lon"))
assert(adult_series.adult, "a story tagged Sắc is flagged adult")

-- A response that repeats the same page must fail instead of looping or lying.
respond = function(url) return url:find("/chapters/story/", 1, true) and "chapters_repeat" or "story" end
assert(not B.getSeries("/truyen/" .. SLUG), "a repeated page is refused")

-- A site that always claims another page stops at the page cap and keeps what it read.
local toc_calls = 0
respond = function(url)
    if url:find("/chapters/story/", 1, true) then
        toc_calls = toc_calls + 1
        return "endless:" .. (tonumber(url:match("page=(%d+)")) or 1)
    end
    return "story"
end
local capped = assert(B.getSeries("/truyen/" .. SLUG))
assert(capped.truncated, "endless table of contents is truncated, not spun forever")
assert(toc_calls <= 60, "table of contents stops at the page cap, calls=" .. toc_calls)
assert(#capped.chapters == toc_calls and #capped.chapters > 1, "the chapters already read are kept")
assert(not B.getSeries("/truyen/" .. SLUG .. "/chuong-1"), "series ref required")

-- getChapter: plain text becomes paragraphs, locked and empty chapters skip.
respond = function() return "chapter" end
local content = assert(B.getChapter(series.chapters[1]))
assert(content.title == "Chương 1: Chiếm lấy tuổi thọ", "chapter keeps the site title")
assert(content.html:find("<p>Dưới ánh mặt trời chói chang, bầu trời xanh ngắt.</p>", 1, true), "paragraphs split")
assert(content.html:find("<p>Cố An lau mồ hôi trên trán &amp; mỉm cười.</p>", 1, true), "entities decoded, then escaped")
assert(not content.html:find("ads", 1, true) and not content.html:find("iframe", 1, true),
    "script, style and iframe stripped")
assert(last_url == "https://storya.click/api/v1/chapters/" .. SLUG .. "/chuong-1", "chapter fetched from the API")

local before_chapter = calls
assert(B.getChapter(series.chapters[2]).skipped, "a chapter flagged locked is skipped")
assert(calls == before_chapter, "a flagged chapter is skipped without a request")

ref = { url = "https://storya.click/truyen/" .. SLUG .. "/chuong-1131-2", series_id = SLUG, title = "Chương 1131-2" }
respond = function() return "chapter_locked" end
local locked = assert(B.getChapter(ref))
assert(locked.skipped and not locked.html, "a locked chapter is never saved")
respond = function() return "chapter_empty" end
assert(B.getChapter(series.chapters[1]).skipped, "empty chapter skips instead of aborting the range")
respond = function() return "chapter_other" end
assert(not B.getChapter(series.chapters[1]), "a chapter the API does not match is refused")
respond = function() return "not-json" end
assert(not B.getChapter(series.chapters[1]), "malformed JSON is an error, not a crash")
status = 404
assert(B.getChapter(series.chapters[1]).skipped, "a missing chapter skips the range step")
status = 429
assert(not B.getChapter(series.chapters[1]), "429 is an error, not a skip")
status = 200
assert(not B.getChapter("/truyen/" .. SLUG .. "/chuong-1"), "open the table of contents first")
assert(not B.getChapter({ url = "https://storya.click/truyen/khac/chuong-1", series_id = SLUG }),
    "a chapter from another series is refused")

Http.get, package.loaded["json"] = original_get, original_json
