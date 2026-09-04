local Rss = require("booxbook.sources.rss")
local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local original = { Http.get, Html.writeFile, Settings.downloadDir, Settings.ensureDir }
local previous_images = Settings.includeImages()
Settings.set("include_images", true)
local feed = { id = "images", url = "https://example.com/rss", full_article = true }
local item = { title = 'Tiêu đề <&> "báo"', date = "", link = "https://example.com/news/article",
    summary = '<p>Tóm tắt</p><img src="/summary.png" alt="Summary"/>' }
local full = [[<article><h1>Publisher heading</h1><p>Nội dung</p>
<img src="data:image/gif;base64,placeholder" data-src="//cdn.example.com/photo?a=1&amp;b=2" alt="Ảnh &quot;đẹp&quot;"/>
<img src="//cdn.example.com/photo?a=1&amp;b=2"/>
<img data-srcset="/small.png 640w, /large.png 1200w"/>
<img src="missing.png" alt="Ảnh thiếu"/>
<img src="file:///private"/><img src="javascript:bad"/><img src="/not-image"/>
<script><img src="/tracking"/></script></article>]]
local calls, writes = {}, {}
-- Real 1x1 GIF bytes, not an HTML response disguised as an image.
local gif = "GIF89a\1\0\1\0\128\0\0\0\0\0\255\255\255!\249\4\1\0\0\0\0,\0\0\0\0\1\0\1\0\0\2\2D\1\0;"
Http.get = function(url, opts)
    calls[#calls + 1] = url
    if url == item.link then return true, 200, full end
    assert(opts.referer == item.link, "images use article referer")
    if url:find("missing", 1, true) then return false, 404 end
    if url:find("not-image", 1, true) then return true, 200, "<html>blocked</html>" end
    return true, 200, gif
end
Settings.downloadDir = function() return "tests/image-output" end
Settings.ensureDir = function() return true end
Html.writeFile = function(path, body) writes[#writes + 1] = { path = path, body = body }; return true end
local rendered = Rss.renderArticle(item, full, feed)
assert(#calls == 0, "pure rendering must not download")
assert(rendered:find('<h1>Tiêu đề &lt;&amp;&gt; &quot;báo&quot;</h1>', 1, true))
assert(not rendered:find("Publisher heading", 1, true), "one visible article heading")
local path = assert(Rss.loadArticle(feed, item))
assert(#calls == 5, "one article plus four distinct valid image requests")
assert(calls[2] == "https://cdn.example.com/photo?a=1&b=2", "lazy src + protocol-relative + entities")
assert(calls[3] == "https://example.com/small.png", "srcset fallback")
assert(calls[4] == "https://example.com/news/missing.png", "relative image URL")
assert(#writes == 3 and writes[1].body == gif and writes[2].body == gif)
local saved = writes[3].body
assert(writes[3].path == path and saved:find(".html.images/1.gif", 1, true), "HTML references local image")
assert(saved:find("Ảnh thiếu", 1, true) and not saved:find("src=\"https://", 1, true))
assert(not saved:find("file:///", 1, true) and not saved:find("javascript:", 1, true))
assert(saved:find("Ảnh &quot;đẹp&quot;", 1, true), "alt escaped safely")
calls, writes = {}, {}
Settings.set("include_images", false)
assert(Rss.loadArticle(feed, item))
assert(#calls == 1 and #writes == 1 and not writes[1].body:find("<img", 1, true), "opt out skips requests")
Settings.set("include_images", true)
Html.writeFile = function(file, body)
    if file:match("%.gif$") then return false, "disk full" end
    assert(not body:find("<img", 1, true), "failed writes leave no broken image references")
    return true
end
assert(Rss.loadArticle(feed, item), "image save failure retains article text")
Http.get = function(url)
    if url == item.link then return false, 503 end
    error("network unavailable")
end
assert(Rss.loadArticle(feed, item), "image request exceptions retain summary")
Http.get = function() return true, 200, gif end
Html.writeFile = function(file, body) writes[#writes + 1] = { path = file, body = body }; return true end
local many = "<article>" .. string.rep('<img src="/same.gif"/>', 25) .. "</article>"
writes = {}
Rss.renderArticle(item, many, feed, "tests/image-output/article.html")
assert(#writes == 1, "duplicate images downloaded/written once")
local tags = {}
for i = 1, 25 do tags[i] = '<img src="/' .. i .. '.gif"/>' end
writes = {}
Rss.renderArticle(item, "<article>" .. table.concat(tags) .. "</article>", feed, "tests/image-output/article.html")
assert(#writes == 20, "image download cap")
Http.get, Html.writeFile, Settings.downloadDir, Settings.ensureDir = unpack(original)
Settings.set("include_images", previous_images)
-- Exercise the production streaming cap at the transport boundary.
local transport = require("socket.http")
local original_request = transport.request
transport.request = function(request)
    assert(request.sink("GIF89a"))
    local ok, err = request.sink(string.rep("x", Http.MAX_BODY))
    assert(not ok and err == "body too large", "cap enforced while streaming")
    return nil, err
end
local ok, err = Http.get("https://example.com/oversized", { delay_ms = 0 })
assert(not ok and err == "body too large")
transport.request = original_request
-- Binary persistence uses the real atomic writer, not the boundary double.
local temporary = os.tmpname()
os.remove(temporary)
assert(Html.writeFile(temporary, gif))
local file = assert(io.open(temporary, "rb"))
assert(file:read("*a") == gif, "binary image bytes preserved on disk")
file:close()
os.remove(temporary)
print("Article heading and image checks passed")
