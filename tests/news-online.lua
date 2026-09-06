-- Deterministic network/KOReader boundary doubles; exercise the real RSS and news modules.
local Rss = require("booxbook.sources.rss")
local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
assert(type(Rss.list) == "function", "RSS must list without bulk downloading")
assert(type(Rss.loadArticle) == "function", "RSS must load one selected article")
local original = { Http.get, Html.writeFile, Settings.downloadDir, Settings.ensureDir }
local requests, writes = {}, {}
local feed = { id = "online", title = "Online", url = "https://example.com/rss", full_article = true }
local function feedXml(count)
    local parts = { '<rss><channel>' }
    for i = 1, count do
        local title = ({ "First", "Second" })[i] or ("Item " .. i)
        local summary = title .. " summary"
        local cover = i == 1 and '<media:thumbnail url="https://example.com/thumb1.jpg"/>' or ""
        if i == 2 then summary = summary .. ' <img src="https://example.com/thumb2.jpg"/>' end
        parts[#parts + 1] = '<item><title>' .. title .. '</title><link>https://example.com/' .. i
            .. '</link><description>' .. summary .. '</description>' .. cover .. '</item>'
    end
    parts[#parts + 1] = '</channel></rss>'
    return table.concat(parts)
end
local xml = feedXml(2)
Http.get = function(url)
    requests[#requests + 1] = url
    if url == feed.url then return true, 200, xml end
    return true, 200, '<article><p>Selected body</p></article>'
end
Html.writeFile = function(path, body)
    writes[#writes + 1] = { path = path, body = body }
    return true
end
Settings.downloadDir = function() return "." end
Settings.ensureDir = function() return true end
local items = assert(Rss.list(feed, 20))
assert(#items == 2 and #requests == 1 and #writes == 0, "listing must only fetch feed XML")
assert(#Rss.list(feed, 1) == 1, "listing honors configured limit")
assert(items[1].cover == "https://example.com/thumb1.jpg" and items[2].cover == "https://example.com/thumb2.jpg",
    "RSS thumbnails are preserved for article grids")
local video_item = Rss.parse('<rss><item><title>Video story</title><link>https://example.com/story</link>'
    .. '<media:content medium="video" url="https://example.com/video.mp4"/>'
    .. '<description><![CDATA[<img src="https://example.com/poster.jpg"/>]]></description></item></rss>')[1]
assert(video_item.cover == "https://example.com/poster.jpg",
    "non-image media must not suppress the summary thumbnail")
requests = {}
local path = assert(Rss.loadArticle(feed, items[2]))
assert(#requests == 1 and requests[1] == items[2].link, "only selected article requested")
assert(#writes == 1 and writes[1].path == path and writes[1].body:find("Selected body", 1, true))
assert(not Rss.loadArticle(feed, { link = "file:///private" }), "non-HTTP article rejected")
assert(not Rss.list({ url = "file:///private" }), "non-HTTP feed rejected")
Http.get = function() return false, 503 end
assert(Rss.loadArticle(feed, items[2]), "failed article falls back to summary")
assert(writes[#writes].body:find("Second summary", 1, true), "selected summary preserved")
assert(not Rss.list(feed), "feed failures returned")
local atom = Rss.parse('<feed><entry><title>Atom</title><link href="https://example.com/a"/>'
    .. '<summary>Atom summary</summary></entry></feed>')
assert(atom[1].summary == "Atom summary", "Atom summary fallback preserved")
feed.full_article = false
Http.get = function() error("custom feed must not scrape article") end
assert(Rss.loadArticle(feed, items[1]))
Html.writeFile = function() return false, "disk full" end
local failed, err = Rss.loadArticle(feed, items[1])
assert(not failed and err == "disk full", "write errors must propagate")
Http.get, Html.writeFile, Settings.downloadDir, Settings.ensureDir = unpack(original)

-- Simulate menu events, but keep the production feed listing and article loading.
local names = { "ui/widget/infomessage", "ui/network/manager", "apps/reader/readerui",
    "ui/trapper", "ui/uimanager", "gettext", "booxbook.ui.catalog", "booxbook.sources.feeds",
    "booxbook.ui.cover-grid" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
package.loaded["booxbook.network"] = nil
package.loaded["booxbook.ui.news"] = nil
local shown, opened, notices, queue, grids = {}, {}, {}, {}, {}
local wifi, cleared, stack_cleared = 0, 0, false
local online = true
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/network/manager"] = {
    isOnline = function() return online end,
    isConnected = function() return online end,
    beforeWifiAction = function(_, fn) wifi = wifi + 1; fn() end,
}
package.loaded["apps/reader/readerui"] = { showReader = function(_, value)
    assert(stack_cleared, "menus must not cover the reader")
    opened[#opened + 1] = value
end }
package.loaded["ui/trapper"] = { wrap = function(_, fn) fn() end,
    info = function() end, clear = function() cleared = cleared + 1 end }
package.loaded["ui/uimanager"] = {
    show = function(_, value) notices[#notices + 1] = value end,
    nextTick = function(_, fn) queue[#queue + 1] = fn end,
}
package.loaded["gettext"] = function(value) return value end
package.loaded["booxbook.ui.catalog"] = {
    show = function(value) shown[#shown + 1] = value end,
    clearStack = function() stack_cleared = true end,
}
package.loaded["booxbook.ui.cover-grid"] = {
    PAGE_SIZE = 6,
    show = function(opts)
        local value = {
            opts = opts,
            pages = {},
            setPage = function(self, page)
                self.pages[#self.pages + 1] = page
                for key, field in pairs(page) do self.opts[key] = field end
            end,
        }
        grids[#grids + 1] = value
        return value
    end,
}
feed.full_article = true
package.loaded["booxbook.sources.feeds"] = {
    { id = "paper", title = "Test paper", region = "vietnam", categories = { feed } },
    { id = "other", title = "Other paper", region = "world", categories = { {
        id = "other-news", title = "Other news", category = "Other category", url = "https://other.example/rss",
    } } },
}
local News = dofile("booxbook.koplugin/booxbook/ui/news.lua")
local custom = Settings.get("custom_rss_feeds")
Settings.set("custom_rss_feeds", {})
Settings.set("feed_enabled_online", false) -- Retired toggles must not hide categories.
requests, writes = {}, {}
local ui_xml = feedXml(7)
Http.get = function(url)
    requests[#requests + 1] = url
    return true, 200, url == feed.url and ui_xml or '<article>Chosen article</article>'
end
Settings.downloadDir = function() return "." end
Settings.ensureDir = function() return true end
Html.writeFile = function(value, body) writes[#writes + 1] = body; return true end
local function tick()
    while #queue > 0 do table.remove(queue, 1)() end
end
local menu = News.menu()
assert(menu[1].text == "Báo Việt" and menu[2].text == "Báo Nước Ngoài", "news menu groups by region")
for _, row in ipairs(menu) do assert(row.text ~= "Nguồn tin", "source toggle menu removed") end
menu[1].callback()
tick()
assert(#requests == 0 and #shown == 1 and #shown[1].items == 1, "region browsing is local")
assert(shown[1].items[1].text == "Test paper", "Vietnam group excludes foreign publishers")
shown[1].items[1].callback()
tick()
assert(#requests == 0 and #shown[2].items == 1, "publisher opens categories without HTTP")
assert(shown[2].items[1].keep_menu_open, "category list survives navigation")
shown[2].items[1].callback()
assert(#requests == 0, "work deferred until menu selection completes")
tick()
assert(#requests == 1 and #writes == 0 and #grids == 1 and #grids[1].opts.items == 7,
    "source click lists titles in the shared grid")
assert(grids[1].opts.items[1].cover == "https://example.com/thumb1.jpg"
    and grids[1].opts.items[2].cover == "https://example.com/thumb2.jpg",
    "news grid receives RSS thumbnails")
assert(grids[1].opts.source_id == "rss-online" and grids[1].opts.cover_referer == feed.url
    and grids[1].opts.cover_cookies == nil and grids[1].opts.on_search == nil,
    "news grid uses RSS cover context without DocLN cookies or search")
local listed_requests = #requests
grids[1].opts.on_next()
assert(grids[1].opts.offset == 7 and #requests == listed_requests and grids[1].pages[#grids[1].pages].page_count == 2,
    "news next page is local and reports total pages")
grids[1].opts.on_next()
assert(notices[#notices].text == "Hết danh sách." and #requests == listed_requests,
    "news last-page boundary is local")
grids[1].opts.on_prev()
assert(grids[1].opts.offset == 1 and #requests == listed_requests, "news previous page is local")
grids[1].opts.on_prev()
assert(notices[#notices].text == "Đang ở trang đầu." and #requests == listed_requests,
    "news first-page boundary is local")
grids[1].opts.on_select(grids[1].opts.items[2])
tick()
assert(#requests == listed_requests + 1 and requests[#requests] == grids[1].opts.items[2].link
    and #writes == 1 and #opened == 1)
local notices_after_grid = #notices
assert(wifi == 0 and cleared == 2, "already-online skips Wi-Fi prompt but still clears progress")
menu[2].callback()
tick()
assert(shown[#shown].items[1].text == "Other paper" and #shown[#shown].items == 1,
    "foreign group excludes Vietnamese publishers")
assert(#requests == 2, "regional navigation does not prefetch feeds")
online = false
Http.get = function() error("network unavailable") end
News.showFeed(feed)
tick()
assert(wifi == 1 and #notices == notices_after_grid + 1 and cleared == 3, "offline path may prompt then still clear progress")
online = true
Html.writeFile = function() return false, "disk full" end
Http.get = function() return false, 503 end
News.openArticle(feed, items[1])
tick()
assert(#opened == 1 and #notices == notices_after_grid + 2, "failed write never opens the reader")
assert(News.showSources == nil and News.showOnline == nil, "legacy source picker removed")
Settings.set("custom_rss_feeds", { "https://example.com/custom" })
local custom_menu = News.menu()
assert(custom_menu[3].text == "RSS tùy chỉnh", "custom feeds have a separate group")
custom_menu[3].callback()
tick()
assert(shown[#shown].items[1].text == "https://example.com/custom", "custom feed preserved")
Http.get = function(url)
    requests[#requests + 1] = url
    return true, 200, feedXml(1)
end
shown[#shown].items[1].callback()
tick()
assert(grids[#grids].opts.source_id == "rss-custom-1"
    and grids[#grids].opts.base_url == "https://example.com/custom"
    and grids[#grids].opts.cover_cookies == nil,
    "custom RSS feeds also use the shared grid without source cookies")
Settings.set("feed_enabled_online", nil)
Settings.set("custom_rss_feeds", custom)
Http.get, Html.writeFile, Settings.downloadDir, Settings.ensureDir = unpack(original)
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
package.loaded["booxbook.network"] = nil
package.loaded["booxbook.ui.news"] = nil

-- Real local I/O plus a disk-full double: never destroy an existing article on failure.
local temp_path = os.tmpname()
os.remove(temp_path)
assert(Html.writeFile(temp_path, "original"))
local real_open = io.open
io.open = function(value, mode)
    if value == temp_path .. ".part" and mode == "wb" then
        return { write = function() return nil, "disk full" end, close = function() return true end }
    end
    return real_open(value, mode)
end
local written, write_err = Html.writeFile(temp_path, "replacement")
io.open = real_open
assert(not written and write_err == "disk full")
local file = assert(io.open(temp_path, "rb"))
assert(file:read("*a") == "original", "failed refresh preserves old article")
file:close()
os.remove(temp_path)
print("Online RSS, menu and storage checks passed")
