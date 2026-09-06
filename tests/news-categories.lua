local Publishers = require("booxbook.sources.feeds")
local expected = { vnexpress = 22, tuoitre = 19, thanhnien = 166, dantri = 33,
    bbc = 26, guardian = 54, dw = 10,
    tienphong = 100, vietnamplus = 58, baotintuc = 23, nhandan = 36, sggp = 58,
    skynews = 9, independent = 16, aljazeera = 1, france24 = 1, abcau = 1 }
local vietnam = { vnexpress = true, tuoitre = true, thanhnien = true, dantri = true,
    tienphong = true, vietnamplus = true, baotintuc = true, nhandan = true, sggp = true }
assert(#Publishers == 17, "retain seven publishers and add five per region")
local ids, urls, by_url, publisher_ids = {}, {}, {}, {}
local regions = { vietnam = 0, world = 0 }
local total = 0
local audited = {}
for line in io.lines("tests/fixtures/feeds-audit.md") do
    local id, count, status, url = line:match("^| [^|]+ | ([^|]+) | (%d+) | ([^|]+) | ([^|]+) |")
    if id then audited[url] = { id = id, count = tonumber(count), status = status } end
end
for _, publisher in ipairs(Publishers) do
    assert(not publisher_ids[publisher.id], "duplicate publisher ID")
    publisher_ids[publisher.id] = true
    assert(publisher.region == (vietnam[publisher.id] and "vietnam" or "world"), "wrong publisher group")
    regions[publisher.region] = regions[publisher.region] + 1
    assert(#publisher.categories == expected[publisher.id], "incomplete catalog for " .. publisher.id)
    local labels = {}
    for _, category in ipairs(publisher.categories) do
        assert(category.url:match("^https://"), "catalog must use HTTPS")
        assert(category.title:find(publisher.title, 1, true), "reader retains publisher attribution")
        assert(category.category ~= "" and not labels[category.category], "ambiguous category name")
        assert(not ids[category.id], "duplicate article storage ID")
        assert(not urls[category.url], "duplicate RSS URL")
        local check = audited[category.url]
        assert(check and check.id == category.id and check.status == "ok" and check.count > 0,
            "category must have parseable articles in the live audit: " .. category.url)
        labels[category.category], ids[category.id], urls[category.url] = true, true, true
        by_url[category.url] = category
        total = total + 1
    end
end
assert(total == 633, "expected nonempty RSS catalog size")
assert(regions.vietnam == 9 and regions.world == 8, "five additions per group")
assert(by_url["https://thanhnien.vn/rss/thoi-su/phap-luat.rss"].category == "Thời sự / Pháp luật")
assert(by_url["https://thanhnien.vn/rss/video/thoi-su.rss"].category == "Video / Thời sự")
assert(by_url["https://dantri.com.vn/rss/noi-vu.rss"], "newly published category retained")
assert(by_url["https://vnexpress.net/rss/khoa-hoc-cong-nghe.rss"], "current science URL retained")
assert(by_url["https://tuoitre.vn/nhip-song-so.rss"].category == "Công nghệ", "use actual RSS URL, not title slug")
assert(not by_url["https://feeds.bbci.co.uk/news/video_and_audio/world/rss.xml"], "known 404 excluded")
assert(by_url["https://vnexpress.net/rss/thoi-su.rss"].id == "vnexpress-thoi-su", "old storage IDs unchanged")
assert(not by_url["https://vnexpress.net/rss/startup.rss"], "confirmed empty feed excluded")
assert(not by_url["https://www.independent.co.uk/travel/uk/rss"], "empty foreign feed excluded")
print("Publisher catalog checks passed: 17 publishers, 633 populated categories (9 Vietnam / 8 world)")
