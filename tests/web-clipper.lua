local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local Clipper = require("booxbook.web-clipper")
local Upload = require("booxbook.wifi-upload")
local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(b), tostring(a)), 2)
    end
end

local function assert_true(cond, msg)
    if not cond then error(msg or "expected true", 2) end
end

-- 1. Test URL validation & SSRF protection
local ok, clean = Clipper.isSafeUrl("https://vnexpress.net/thoi-su/bai-viet-123.html")
assert_true(ok, "public HTTPS URL is safe")
assert_eq(clean, "https://vnexpress.net/thoi-su/bai-viet-123.html", "URL preserved")

ok = Clipper.isSafeUrl("http://example.com/post")
assert_true(ok, "public HTTP URL is safe")

assert_true(not Clipper.isSafeUrl(""), "empty URL rejected")
assert_true(not Clipper.isSafeUrl("ftp://example.com/file"), "non-HTTP URL rejected")
assert_true(not Clipper.isSafeUrl("http://localhost/admin"), "localhost rejected")
assert_true(not Clipper.isSafeUrl("http://127.0.0.1:8080/token"), "127.0.0.1 rejected")
assert_true(not Clipper.isSafeUrl("http://0.0.0.0/"), "0.0.0.0 rejected")
assert_true(not Clipper.isSafeUrl("http://192.168.1.100/"), "192.168.* rejected")
assert_true(not Clipper.isSafeUrl("http://10.0.1.5/api"), "10.* rejected")
assert_true(not Clipper.isSafeUrl("http://172.16.0.1/"), "172.16.* rejected")
assert_true(not Clipper.isSafeUrl("http://169.254.169.254/latest/meta-data"), "link-local / AWS metadata IP rejected")

-- 2. Test title extraction
local sample_og = '<html><head><meta property="og:title" content="Ti&#xEA;u &#x111;&#x1EC1; b&#xE0;i b&#xE1;o"/></head><body></body></html>'
assert_eq(Clipper.extractTitle(sample_og), "Tiêu đề bài báo", "extracts and decodes og:title")

local sample_tw = '<html><head><meta name="twitter:title" content="Twitter Title"/></head><body></body></html>'
assert_eq(Clipper.extractTitle(sample_tw), "Twitter Title", "extracts twitter:title")

local sample_title = '<html><head><title>Bản tin kinh tế buổi sáng - VnExpress</title></head><body></body></html>'
assert_eq(Clipper.extractTitle(sample_title), "Bản tin kinh tế buổi sáng", "cleans site suffix from title")

local sample_h1 = '<html><body><h1>Tiêu đề từ H1</h1></body></html>'
assert_eq(Clipper.extractTitle(sample_h1), "Tiêu đề từ H1", "falls back to h1")

-- 3. Test content extraction and script stripping
local sample_html = [[
<!doctype html>
<html>
<head>
    <meta property="og:title" content="Công nghệ mới trên E-ink" />
    <meta property="og:site_name" content="Tech Daily" />
    <meta name="author" content="Nguyễn Văn A" />
</head>
<body>
    <header><nav><a href="/">Trang chủ</a></nav></header>
    <script>alert("malicious script");</script>
    <style>.ad { display: block; }</style>
    <article class="main-article">
        <p>Màn hình E-ink Carta 1200 đem lại độ tương phản cao hơn 30% so với thế hệ trước.</p>
        <p>Tốc độ làm mới trang cũng được cải thiện đáng kể, giúp trải nghiệm lật trang mượt mà hơn.</p>
        <img src="/images/eink-chart.png" alt="Biểu đồ" />
        <p>Thời lượng pin trên các dòng máy đọc sách thế hệ mới có thể kéo dài nhiều tuần liên tục.</p>
    </article>
    <footer>Bản quyền 2026</footer>
</body>
</html>
]]

local article = Clipper.extractArticle(sample_html, "https://techdaily.vn/post/123")
assert_eq(article.title, "Công nghệ mới trên E-ink", "extracted title")
assert_eq(article.author, "Nguyễn Văn A", "extracted author")
assert_eq(article.site, "Tech Daily", "extracted site name")
assert_true(article.body:find("Carta 1200") ~= nil, "contains article text")
assert_true(article.body:find("alert") == nil, "scripts stripped")
assert_true(article.body:find("https://techdaily.vn/images/eink%-chart%.png") ~= nil, "relative image normalized to absolute")

-- 4. Test fallback to paragraphs when no container matches
local sample_fallback = [[
<html>
<head><title>Bài viết đơn giản</title></head>
<body>
    <div>
        <p>Đoạn văn thứ nhất có nội dung đủ dài để kiểm tra bộ lọc fallback của Web Clipper.</p>
        <p>Đoạn văn thứ hai tiếp tục bổ sung thông tin chi tiết về chủ đề đang được đề cập.</p>
    </div>
</body>
</html>
]]
local fallback_art = Clipper.extractArticle(sample_fallback, "https://example.com/simple")
assert_eq(fallback_art.title, "Bài viết đơn giản", "fallback extracted title")
assert_true(fallback_art.body:find("Đoạn văn thứ nhất") ~= nil, "fallback collected paragraphs")

-- 5. Test Clipper.clip
local orig_get = Http.get
Http.get = function(url)
    assert_eq(url, "https://techdaily.vn/post/123", "Http.get called with target url")
    return true, 200, sample_html, {}
end

local orig_write = Html.writeFile
local written_target, written_doc
Html.writeFile = function(target, doc)
    written_target = target
    written_doc = doc
    return true
end

local orig_ensure = Settings.ensureDir
Settings.ensureDir = function() return true end

local res, err = Clipper.clip("https://techdaily.vn/post/123", "/tmp/news/web-clipper")
assert_true(res ~= nil, "Clipper.clip succeeded: " .. tostring(err))
assert_eq(res.title, "Công nghệ mới trên E-ink", "res.title matches")
assert_true(res.path:find("/tmp/news/web%-clipper/%d+%-%d+%-cong%-nghe%-moi%-tren%-eink%.html") ~= nil, "filename generated with date and slug")
assert_true(written_doc:lower():find("<!doctype html>", 1, true) ~= nil, "wrapped document written")

Settings.ensureDir = orig_ensure

Http.get = orig_get
Html.writeFile = orig_write

-- 6. Test Wi-Fi upload route /clip in Upload.headers
local raw_req = "POST /clip HTTP/1.1\r\nHost: 192.168.1.50:8080\r\nX-BooxBook-Token: 123456\r\nContent-Length: 30\r\n\r\n"
local req, code, msg = Upload.headers(raw_req, "192.168.1.50:8080", "123456")
assert_true(req ~= nil, "Upload.headers accepted /clip with valid token")
assert_true(req.clip == true, "req.clip is true")
assert_eq(req.remaining, 30, "remaining is 30 bytes")

local bad_token_req = "POST /clip HTTP/1.1\r\nHost: 192.168.1.50:8080\r\nX-BooxBook-Token: 000000\r\nContent-Length: 30\r\n\r\n"
req, code, msg = Upload.headers(bad_token_req, "192.168.1.50:8080", "123456")
assert_true(req == nil and code == 401, "Upload.headers rejects /clip with wrong token")

print("Web clipper checks passed: safe URL guards, metadata extraction, image resolution, HTML generation and Wi-Fi route verified")
