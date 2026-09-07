local old_gettext = package.loaded["gettext"]
package.loaded["gettext"] = function(s) return s end
local Source = require("booxbook.sources.truyentuoitho")
local Http = require("booxbook.http")
local url = "https://truyentuoitho.com/manga/test/tap-1/"
local series_url = "https://truyentuoitho.com/manga/test/"
assert(Source.parseSeriesRef({ url = series_url }).id == "test")
assert(not Source.parseSeriesRef(url) and not Source.parseSeriesRef("https://evil.test/manga/test/"))
local listing = [[<div class="page-item-detail"><div class="item-thumb"><img src="/cover.webp"></div>
<div class="post-title"><h3><a href="/manga/test/">Test &amp; title</a></h3></div></div>
<div class="wp-pagenavi"><span class="current">1</span><a href="/manga/page/2/?m_orderby=latest">2</a></div>]]
local listed = assert(Source.parseList(listing, 1))
assert(#listed.items == 1 and listed.items[1].title == "Test & title" and listed.has_more)
assert(listed.items[1].cover == "https://truyentuoitho.com/cover.webp")
assert(not Source.parseList(listing, 2).has_more)
assert(#Source.parseList('<div class="no-results">No results</div>', 1).items == 0)
assert(not Source.parseList('<html>challenge</html>', 1))
local toc = [[<li class="wp-manga-chapter"><a href="/manga/test/tap-10/">Tập 10</a></li>
<li class="wp-manga-chapter"><a href="/manga/test/tap-2/">Tập 2</a></li>
<li class="wp-manga-chapter"><a href="/manga/test/tap-2/">duplicate</a></li>
<li class="wp-manga-chapter"><a href="/manga/other/tap-1/">other book</a></li>]]
local meta = '<div class="post-title"><h1>Test</h1></div><div class="author-content">Writer</div>'
local book = assert(Source.parseSeries(meta, series_url, toc))
assert(#book.chapters == 2 and book.chapters[1].chapter == "tap-2" and book.chapters[2].index == 2)
assert(book.author == "Writer" and book.source_id == "truyentuoitho")
assert(not Source.parseSeries(meta, series_url, ""))
local original_get, original_post = Http.get, Http.post
local requests = 0
Http.get = function(u, opts)
    requests = requests + 1
    assert(opts.allow_url(u) and not opts.allow_url("https://evil.test/"))
    if u == series_url then return true, 200, meta .. '<div id="manga-chapters-holder"></div>' end
    assert(u:find("s=a%%20%%26%%20b") and u:find("paged=2", 1, true)); return true, 200, listing
end
Http.post = function(u) assert(u == series_url .. "ajax/chapters/"); return true, 200, toc end
assert(#Source.getSeries(series_url).chapters == 2)
assert(Source.search("a & b", 2))
assert(not Source.search("", 1) and not Source.browse("bad", 1) and not Source.browse("latest", 1.5))
assert(requests == 2, "invalid inputs never issue a request")
Http.post = function() return false, 503 end
local failed, error_text = Source.getSeries(series_url)
assert(not failed and error_text:find("503"))
Http.get, Http.post = original_get, original_post
assert(Source.parseRef(url).chapter == "tap-1")
for _, bad in ipairs({ "https://evil.test/manga/test/tap-1/", "https://truyentuoitho.com/manga/test/",
    "https://truyentuoitho.com/manga/../tap-1/", "https://truyentuoitho.com@m.evil/manga/a/b/",
    "https://truyentuoitho.com/manga/a/b/?x=1", "http://truyentuoitho.com/manga/a/b/" }) do
    assert(not Source.parseRef(bad), bad)
end
local markup = [[<h1>Test &amp; title</h1><img src="https://ads.test/ad.jpg">
<div class="reading-content"><div><img src="/one.webp"></div>
<img src="placeholder" data-src="https://img.resourcehub.shop/two.webp">
<noscript><img src="/one.webp"></noscript></div>]]
local parsed = assert(Source.parseChapter(markup, url))
assert(parsed.title == "Test & title" and #parsed.pages == 2)
assert(parsed.pages[1] == "https://truyentuoitho.com/one.webp")
assert(parsed.pages[2] == "https://img.resourcehub.shop/two.webp")
assert(not Source.parseChapter('<div class="reading-content"><img src="https://localhost/a"></div>', url))
assert(not Source.parseChapter('<div class="reading-content"></div>', url))
assert(not Source.parseChapter('<div class="reading-content">'
    .. string.rep('<img src="/one.webp">', 601) .. '</div>', url))
local transport = require("socket.http")
local original = transport.request
local calls = 0
transport.request = function()
    calls = calls + 1
    return 1, 302, { location = "http://127.0.0.1/private" }, "Found"
end
local ok, code = Http.get(url, { allow_url = function(u) return Source.parseRef(u) ~= nil end })
assert(not ok and code == "URL not allowed" and calls == 1, "redirect rejected before request")
transport.request = original
local old_open, old_remove = io.open, os.remove
local removed = false
io.open = function() return { write = function() return true end,
    close = function() return nil, "disk full on close" end } end
os.remove = function() removed = true; return true end
transport.request = function(req) assert(req.sink("data")); return 1, 200, {}, "OK" end
ok, code = Http.downloadToFile(url, "unused-test-file")
io.open, os.remove, transport.request = old_open, old_remove, original
assert(not ok and code == "disk full on close" and removed, "failed flush cannot mark download complete")
package.loaded["gettext"] = old_gettext
print("Comic source: URL boundaries, scoped ordered pages, limits and redirects passed")
