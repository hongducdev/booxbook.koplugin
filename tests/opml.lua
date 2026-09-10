-- Unit tests for OPML parsing, generation and news integration (Phase 02)
local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local Opml = require("booxbook.opml")

-- 1. Entity decoding
assert(Opml.decodeEntities("&amp;&lt;&gt;&quot;&apos;") == "&<>\"'", "basic entities decoded")
assert(Opml.decodeEntities("Ti&#7879;m s&#225;ch") == "Tiệm sách", "numeric entities decoded")
assert(Opml.decodeEntities("H&#x1ec7; th&#x1ed1;ng") == "Hệ thống", "hex entities decoded")
assert(Opml.decodeEntities("N&#7845;u &#x1ea5;m") == "Nấu ấm", "vietnamese code points >255 decoded to valid utf-8")
assert(Opml.decodeEntities("Surrogate &#55296; stays") == "Surrogate &#55296; stays", "invalid surrogate entity preserved, not deleted")
assert(Opml.decodeEntities("Out of range &#x110000; stays") == "Out of range &#x110000; stays", "out of range entity preserved")

-- 2. Parsing standard OPML sample
local sample_opml = [[<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>My Subscriptions</title>
  </head>
  <body>
    <outline text="Tin tức" title="Tin tức">
      <outline type="rss" text="VnExpress &amp; Tin Nhanh" title="VnExpress"
               xmlUrl="https://vnexpress.net/rss/tin-moi-nhat.rss" htmlUrl="https://vnexpress.net"/>
      <outline type="rss" text="Tuổi Trẻ"
               xmlUrl="https://tuoitre.vn/rss/tin-moi-nhat.rss" htmlUrl="https://tuoitre.vn"/>
    </outline>
    <outline type="rss" text="BBC Tiếng Việt"
             xmlUrl="https://feeds.bbci.co.uk/vietnamese/rss.xml"/>
  </body>
</opml>]]

local feeds = Opml.parse(sample_opml)
assert(#feeds == 3, "extracted 3 feeds from nested outline")
assert(feeds[1].title == "VnExpress", "title preferred over text when present")
assert(feeds[1].xmlUrl == "https://vnexpress.net/rss/tin-moi-nhat.rss", "xmlUrl extracted")
assert(feeds[1].htmlUrl == "https://vnexpress.net", "htmlUrl extracted")
assert(feeds[2].title == "Tuổi Trẻ", "second feed title extracted")
assert(feeds[3].title == "BBC Tiếng Việt", "single outline feed extracted")

-- 3. Resilient parsing: case-insensitive xmlurl/url, CDATA, missing attributes
local messy_opml = [[<opml><BODY>
  <outline text="Feed 1" XMLURL="https://example.com/feed1.xml" />
  <outline URL="http://example.com/feed2.xml" title="Feed 2" />
  <outline text="Invalid feed" xmlUrl="ftp://invalid.com/rss" />
  <outline text="Duplicate 1" xmlUrl="https://example.com/feed1.xml" />
</BODY></opml>]]

local messy_feeds = Opml.parse(messy_opml)
assert(#messy_feeds == 2, "extracted valid feeds, ignored ftp and deduplicated same URL")
assert(messy_feeds[1].xmlUrl == "https://example.com/feed1.xml", "XMLURL case-insensitive")
assert(messy_feeds[2].xmlUrl == "http://example.com/feed2.xml", "URL attribute fallback")

-- 4. Empty and corrupt inputs
assert(#Opml.parse("") == 0, "empty string returns empty table")
assert(#Opml.parse(nil) == 0, "nil returns empty table")
assert(#Opml.parse("not xml at all") == 0, "malformed text returns empty table")

-- 5. Generation and round-trip
local to_export = {
    { title = "Kênh 1 & Bạn", xmlUrl = "https://a.com/rss.xml", htmlUrl = "https://a.com" },
    { title = "Kênh 2", xmlUrl = "https://b.com/feed", htmlUrl = "" },
}

local xml_out = Opml.generate(to_export, "Danh mục xuất")
assert(xml_out:find('version="2.0"', 1, true) ~= nil, "opml 2.0 header")
assert(xml_out:find("Kênh 1 &amp; Bạn", 1, true) ~= nil, "escaped entities in xml")
assert(xml_out:find('xmlUrl="https://a.com/rss.xml"', 1, true) ~= nil, "xmlUrl in outline")

local re_parsed = Opml.parse(xml_out)
assert(#re_parsed == 2, "round-trip parsed 2 items")
assert(re_parsed[1].title == "Kênh 1 & Bạn", "decoded title matches original")
assert(re_parsed[1].xmlUrl == "https://a.com/rss.xml", "xmlUrl matches original")
assert(re_parsed[2].xmlUrl == "https://b.com/feed", "second item matches original")

-- 6. News menu integration check
package.preload["socket"] = function()
    return {
        gettime = function() return os.time() end,
        sleep = function() end,
        skip = function(count, ...) return select(count + 1, ...) end,
    }
end
package.preload["socket.http"] = function()
    return { request = function() return 1, 200, {}, "OK" end }
end
package.preload["ltn12"] = function()
    return {
        sink = { table = function(t) return function(c) if c then t[#t+1]=c end return true end end },
        source = { string = function(s) local d=false return function() if d then return nil end d=true return s end end },
    }
end

package.loaded["ui/widget/infomessage"] = { new = function(_, t) return t end }
package.loaded["ui/uimanager"] = { show = function() end, nextTick = function(self, fn) fn() end }
package.loaded["apps/reader/readerui"] = { showReader = function() end }
package.loaded["ui/trapper"] = { wrap = function(_, fn) fn() end }
package.loaded["gettext"] = function(s) return s end
package.loaded["booxbook.ui.catalog"] = { promptText = function() end, show = function() end }
package.loaded["ui/network/manager"] = {}
package.loaded["booxbook.ui.cover-grid"] = function() return { PAGE_SIZE = 6 } end

local News = require("booxbook.ui.news")
local Settings = require("booxbook.store.settings")
Settings.set("custom_rss_feeds", { "https://existing.com/feed.xml" })

local menu = News.menu()
local has_import, has_export = false, false
for _, item in ipairs(menu) do
    if item.text == "Nhập file OPML" then has_import = true end
    if item.text == "Xuất file OPML" then has_export = true end
end
assert(has_import == true, "menu has 'Nhập file OPML'")
assert(has_export == true, "menu has 'Xuất file OPML'")

-- Restore settings
Settings.set("custom_rss_feeds", initial_custom)

print("OPML checks passed")
