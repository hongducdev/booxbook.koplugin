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
local xml = '<rss><channel><item><title>First</title><link>https://example.com/1</link>'
    .. '<description>First summary</description></item><item><title>Second</title>'
    .. '<link>https://example.com/2</link><description>Second summary</description></item></channel></rss>'
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
    "ui/trapper", "ui/uimanager", "gettext", "booxbook.ui.catalog", "booxbook.sources.feeds" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end
package.loaded["booxbook.network"] = nil
package.loaded["booxbook.ui.news"] = nil
local shown, opened, notices, queue = {}, {}, {}, {}
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
Http.get = function(url)
    requests[#requests + 1] = url
    return true, 200, url == feed.url and xml or '<article>Chosen article</article>'
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
assert(#requests == 1 and #writes == 0 and #shown[3].items == 2, "source click lists titles only")
assert(shown[3].items[2].keep_menu_open, "article selection owns menu lifecycle")
shown[3].items[2].callback()
tick()
assert(#requests == 2 and requests[2] == items[2].link and #writes == 1 and #opened == 1)
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
assert(wifi == 1 and #notices == 1 and cleared == 3, "offline path may prompt then still clear progress")
online = true
Html.writeFile = function() return false, "disk full" end
Http.get = function() return false, 503 end
News.openArticle(feed, items[1])
tick()
assert(#opened == 1 and #notices == 2, "failed write never opens the reader")
assert(News.showSources == nil and News.showOnline == nil, "legacy source picker removed")
Settings.set("custom_rss_feeds", { "https://example.com/custom" })
local custom_menu = News.menu()
assert(custom_menu[3].text == "RSS tùy chỉnh", "custom feeds have a separate group")
custom_menu[3].callback()
tick()
assert(shown[#shown].items[1].text == "https://example.com/custom", "custom feed preserved")
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
