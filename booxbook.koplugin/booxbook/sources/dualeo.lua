-- Dưa Leo Truyện comic adapter.
-- Series: /truyen-tranh/<slug> — chapter: /truyen-tranh/<slug>/chapter-<n>
-- (dashed decimals included: chapter-12-5 = chương 12.5).
-- Page images come from the site's own CDNs (cdn*.imgdualeo1.com); a few of them
-- carry a base64+XOR obfuscated filename that is decoded here before the URL is
-- used. Public pages only; no VIP/paywall bypass.
local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end

local Source = { MAX_PAGES = 600, id = "dualeo", name = "Dưa Leo Truyện", kind = "comic",
    capabilities = { search = true, browse = true, login = false } }

local SITE = "https://dualeotruyenhn.com"
-- dualeotruyenvt.com is the host dualeotruyenhn.com redirects to (same site), so
-- both are accepted and the redirect is followed.
local hosts = {
    ["dualeotruyenhn.com"] = true, ["www.dualeotruyenhn.com"] = true,
    ["dualeotruyenvt.com"] = true, ["www.dualeotruyenvt.com"] = true,
}

-- Page/cover images live on the site's own image CDNs (cdn7., img., cover.).
local function isCdnHost(host)
    if type(host) ~= "string" then return false end
    return host == "imgdualeo1.com" or host:match("%.imgdualeo%d*%.com$") ~= nil
end

local function isImageHost(host)
    if type(host) ~= "string" then return false end
    return hosts[host] == true or isCdnHost(host)
end

-- Non-page assets that sit inside the reader block: chapter banner (/upbia/),
-- comment avatars (/avatar/, /avata/), placeholders, theme images. Same host, so
-- they are filtered by path.
local ASSET_PATHS = { "/avatar", "/avata/", "/upbia/", "/story/", "/biatruyen/",
    "/skin/", "/icon/", "/images/", "/banner/", "/logo" }
local EXTENSIONS = { "%.jpe?g$", "%.png$", "%.webp$", "%.gif$" }

local function hasImageExtension(path)
    for _i, pattern in ipairs(EXTENSIONS) do
        if path:match(pattern) then return true end
    end
    return false
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local b64dec = {}
for i = 1, #B64 do b64dec[B64:sub(i, i)] = i - 1 end
local SALT = "dualeo_salt_2025"

-- nil on any malformed input; the caller keeps the original URL then.
local function base64Decode(str)
    local out = {}
    for i = 1, #str, 4 do
        local c1, c2 = str:sub(i, i), str:sub(i + 1, i + 1)
        local c3, c4 = str:sub(i + 2, i + 2), str:sub(i + 3, i + 3)
        local n1, n2 = b64dec[c1], b64dec[c2]
        if not n1 or not n2 then return nil end
        local n3, n4 = b64dec[c3] or 0, b64dec[c4] or 0
        local value = n1 * 262144 + n2 * 4096 + n3 * 64 + n4
        out[#out + 1] = string.char(math.floor(value / 65536) % 256)
        if c3 ~= "=" then out[#out + 1] = string.char(math.floor(value / 256) % 256) end
        if c4 ~= "=" then out[#out + 1] = string.char(value % 256) end
    end
    return table.concat(out)
end

-- Some <img data-img="..."> values hide the real filename as
-- base64(XOR(name, "dualeo_salt_2025")). Anything that does not decode to a
-- plain filename is returned untouched, so unencrypted URLs keep working.
local function decryptImage(url)
    local path, name, ext = url:match("^(.-)/([^/%.]+)%.([^/%.]+)$")
    if not name or #name < 8 or #name > 512 then return url end
    local ok_bit, bit = pcall(require, "bit")
    if not ok_bit then return url end
    local encoded = name:gsub("%-", "+"):gsub("_", "/")
    local pad = (4 - (#encoded % 4)) % 4
    local decoded = base64Decode(encoded .. string.rep("=", pad))
    if not decoded or #decoded < 4 then return url end
    local out = {}
    for i = 1, #decoded do
        out[i] = string.char(bit.bxor(decoded:byte(i), SALT:byte((i - 1) % #SALT + 1)))
    end
    local plain = table.concat(out)
    if plain:match("^[A-Za-z0-9%-]+$") then
        return path .. "/" .. plain .. "." .. ext
    end
    return url
end

-- Presentation for booxbook.ui.comic-page.
Source.view = {
    base_url = SITE,
    cover_delay_ms = 1600,
    search_hint = "Tên truyện, URL bộ truyện hoặc URL một tập",
    loading = "Đang tải tập %s…",
    last_url_key = "dualeo_last_url",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Truyện đã hoàn thành", kind = "completed" },
    },
}

-- Canonical series URL, used by booxbook.continuation when a saved CBZ has no
-- stored series URL.
function Source.seriesUrl(series_id)
    return SITE .. "/truyen-tranh/" .. series_id
end

local function text(html)
    return Html.decode((html or ""):gsub("<[^>]+>", " ")):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function attrsOf(tag)
    local attrs = {}
    for key, _quote, value in tag.attrs:gmatch("([%w_-]+)%s*=%s*([\"'])(.-)%2") do
        attrs[key:lower()] = value
    end
    return attrs
end

local function firstImage(block)
    return Html.elements(block, "img", true)[1]
end

function Source.parseSeriesRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$")
    local host, slug = url:match("^https?://([^/]+)/truyen%-tranh/([%w%-]+)/?$")
    if not hosts[host] or not slug or #slug > 200 then return nil end
    return { id = slug, url = "https://" .. host .. "/truyen-tranh/" .. slug }
end

-- "12" -> 12, "12-5" -> 12.5, "0-134" -> 0.134.
local function chapterNumber(raw)
    local major, minor = raw:match("^(%d+)%-(%d+)$")
    if major then return tonumber(major .. "." .. minor) end
    return tonumber(raw)
end

function Source.parseRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$")
    local host, series, raw = url:match("^https?://([^/]+)/truyen%-tranh/([%w%-]+)/chapter%-([%d%-]+)/?$")
    if not hosts[host] or not series or #series > 200 or not raw or #raw > 24 then return nil end
    if raw:match("%-%-") or raw:match("^%-") or raw:match("%-$") then return nil end
    local number = chapterNumber(raw)
    if not number then return nil end
    return { url = "https://" .. host .. "/truyen-tranh/" .. series .. "/chapter-" .. raw,
        series = series, chapter = "chapter-" .. raw, number = number }
end

local function request(url)
    local opts = { referer = SITE .. "/", delay_ms = math.max(1600, Settings.delayMs()),
        allow_url = function(next_url) return hosts[next_url:match("^https?://([^/]+)/")] == true end }
    local ok, code, body = Http.get(url, opts)
    if code == 429 then return nil, _("Dưa Leo Truyện giới hạn lượt tải (429). Thử lại sau.") end
    if not ok then return nil, _("Không tải được Dưa Leo Truyện. HTTP: ") .. tostring(code) end
    if type(body) ~= "string" then return nil, _("Phản hồi truyện không hợp lệ.") end
    return Html.stripDangerous(body)
end

-- Grid covers are series art; placeholders, theme images and user avatars are not.
local COVER_ASSET_PATHS = { "/images/", "/skin/", "/icon/", "/banner/", "/logo", "/avatar", "/avata/" }

-- Grid cover: the site's own image CDNs (cover./img. subdomains), same host
-- allowlist as page images but with cover-specific path filters.
local function coverUrl(base, value)
    if type(value) ~= "string" then return nil end
    value = Html.decode(value):match("^%s*(.-)%s*$")
    if value == "" or value:match("^data:") or value:find("[%c%s\\]") then return nil end
    local url = Http.resolveUrl(base, value)
    if not url or not url:match("^https://") then return nil end
    local host, path = url:match("^https://([^/]+)(/.*)$")
    if not host or not path or not isImageHost(host) or not hasImageExtension(path) then return nil end
    for _i, needle in ipairs(COVER_ASSET_PATHS) do
        if path:find(needle, 1, true) then return nil end
    end
    return url
end

-- Page image: only the site's own hosts and its image CDNs, https only, and only
-- real image files outside the known asset paths.
function Source.imageUrl(base, value)
    if type(value) ~= "string" then return nil end
    value = Html.decode(value):match("^%s*(.-)%s*$")
    if value == "" or value:match("^data:") or value:find("[%c%s\\]") then return nil end
    local url = Http.resolveUrl(base, value)
    if not url then return nil end
    url = decryptImage(url)
    if not url:match("^https://") then return nil end
    local host, path = url:match("^https://([^/]+)(/.*)$")
    if not host or not path or not isImageHost(host) then return nil end
    if path:find("%.avif") or not hasImageExtension(path) then return nil end
    for _i, needle in ipairs(ASSET_PATHS) do
        if path:find(needle, 1, true) then return nil end
    end
    return url
end

-- True when the value points at a real image file on a host we do not serve from:
-- that is a reader we cannot download, so the chapter fails loudly instead of
-- silently dropping a page.
local function isForeignImage(base, value)
    if type(value) ~= "string" then return false end
    value = Html.decode(value):match("^%s*(.-)%s*$")
    if value == "" or value:match("^data:") or value:find("[%c%s\\]") then return false end
    local url = Http.resolveUrl(base, value)
    if not url or not url:match("^https://") then return false end
    local host, path = url:match("^https://([^/]+)(/.*)$")
    if not host or not path or isImageHost(host) or not hasImageExtension(path) then return false end
    return true
end

local function itemTitle(row, fallback)
    local name = text(Html.select(row, ".name"))
    if name ~= "" then return name end
    local img = firstImage(row)
    local alt = img and text(Html.attr(img.attrs, "alt")) or ""
    if alt ~= "" then return alt end
    return fallback
end

function Source.parseList(html, page)
    html = Html.stripDangerous(html or "")
    local rows = Html.elements(html, ".li_truyen")
    if #rows == 0 then
        if Html.select(html, ".no-results") or text(html) == "" then
            return { items = {}, has_more = false }
        end
        return nil, _("Không đọc được danh sách; trang có thể đã đổi hoặc yêu cầu xác minh.")
    end
    local items, seen, more = {}, {}, false
    for _row_index, row in ipairs(rows) do
        local ref
        for _link_index, a in ipairs(Html.elements(row.inner, "a")) do
            if not ref then
                local href = Html.decode(Html.attr(a.attrs, "href") or "")
                ref = href ~= "" and Source.parseSeriesRef(Http.resolveUrl(SITE, href)) or nil
            end
        end
        if ref and not seen[ref.id] then
            seen[ref.id] = true
            local title = itemTitle(row.inner, ref.id:gsub("%-", " "))
            ref.title, ref.name = title, title
            local img = firstImage(row.inner)
            if img then
                local attrs = attrsOf(img)
                ref.cover = coverUrl(SITE, attrs["data-src"] or attrs["data-original"] or attrs.src)
            end
            items[#items + 1] = ref
        end
    end
    if #items == 0 then return nil, _("Không đọc được liên kết bộ truyện.") end
    local current = tonumber(page) or 1
    for _link_index, a in ipairs(Html.elements(html, "a")) do
        local href = Html.decode(Html.attr(a.attrs, "href") or "")
        local n = tonumber(href:match("[?&]page=(%d+)"))
        if n and n > current then more = true end
    end
    return { items = items, has_more = more }
end

local function encodeQuery(query)
    return (query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end))
end

local function list(kind, page)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local path
    if kind == "completed" then
        path = "/truyen-hoan-thanh"
    else
        path = "/truyen-moi-cap-nhat"
    end
    local html, err = request(SITE .. path .. (page > 1 and ("?page=" .. page) or ""))
    if not html then return nil, err end
    return Source.parseList(html, page)
end

function Source.browse(kind, page)
    if kind ~= nil and kind ~= "latest" and kind ~= "completed" then
        return nil, _("Dưa Leo Truyện chỉ hỗ trợ Mới cập nhật và Truyện đã hoàn thành.")
    end
    return list(kind == "completed" and "completed" or "latest", page)
end

function Source.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local encoded = encodeQuery(query)
    local url = SITE .. "/tim-kiem?key=" .. encoded
    if page > 1 then url = SITE .. "/tim-kiem.html?key=" .. encoded .. "&page=" .. page end
    local html, err = request(url)
    if not html then return nil, err end
    return Source.parseList(html, page)
end

function Source.parseSeries(html, url)
    local ref = Source.parseSeriesRef(url)
    if not ref then return nil, _("URL bộ truyện không hợp lệ.") end
    html = Html.stripDangerous(html or "")
    ref.title = text(Html.select(html, "h1"))
    if ref.title == "" then return nil, _("Không đọc được thông tin bộ truyện.") end
    ref.source_id = Source.id
    ref.description = text(Html.select(html, ".story-detail-info"))
    local info = Html.select(html, ".txt") or ""
    for _p_index, p in ipairs(Html.elements(info, "p")) do
        local line = text(p.inner)
        local value = line:match("^Nhóm dịch:%s*(.*)$")
        if value and value ~= "" then ref.author = value end
        value = line:match("^Tình tr[ạa]ng:%s*(.*)$")
        if value and value ~= "" then ref.status = value end
    end
    local cover = ""
    for _meta_index, meta in ipairs(Html.elements(html, "meta")) do
        if Html.attr(meta.attrs, "property") == "og:image" then
            cover = Html.attr(meta.attrs, "content") or ""
            break
        end
    end
    ref.cover = coverUrl(url, cover)
    local genres = {}
    for _link_index, a in ipairs(Html.elements(Html.select(html, ".list-tag-story") or "", "a")) do
        local name = text(a.inner)
        if name ~= "" then genres[#genres + 1] = name end
    end
    if #genres > 0 then ref.genres = genres end

    -- The chapter list is the only place with real chapter titles: the "Đọc từ
    -- đầu / Đọc tập mới" shortcuts earlier on the page reuse the same URLs.
    local toc = Html.select(html, ".list-chapters") or Html.select(html, ".list_chapters") or html
    local chapters, seen = {}, {}
    -- NOTE: never `for _, a` here; `_` would shadow gettext `_()` below.
    for _link_index, a in ipairs(Html.elements(toc, "a")) do
        local ch = Source.parseRef(Http.resolveUrl(ref.url, Html.decode(Html.attr(a.attrs, "href") or "")))
        if ch and ch.series == ref.id and not seen[ch.chapter] then
            seen[ch.chapter] = true
            ch.title = text(a.inner)
            if ch.title == "" then ch.title = text(Html.attr(a.attrs, "title")) end
            if ch.title == "" then ch.title = _("Chương ") .. tostring(ch.number) end
            chapters[#chapters + 1] = ch
        end
    end
    if #chapters == 0 then return nil, _("Không đọc được mục lục công khai của bộ truyện.") end
    table.sort(chapters, function(a, b) return a.number < b.number end)
    ref.chapters = {}
    for _chapter_index, ch in ipairs(chapters) do
        ch.index = #ref.chapters + 1
        ref.chapters[ch.index] = ch
    end
    ref.volumes = { { title = _("Danh sách tập"), chapters = ref.chapters } }
    return ref
end

function Source.getSeries(url)
    local ref = Source.parseSeriesRef(url)
    if not ref then return nil, _("URL bộ truyện không hợp lệ.") end
    local html, err = request(ref.url)
    if not html then return nil, err end
    return Source.parseSeries(html, ref.url)
end

function Source.parseChapter(html, url)
    local ref = Source.parseRef(url)
    if not ref then
        return nil, _("Nhập URL một tập: ") .. SITE .. "/truyen-tranh/ten-truyen/chapter-1"
    end
    local stripped = Html.stripDangerous(html or "")
    local content = Html.select(stripped, ".content_view_chap")
        or Html.select(stripped, ".chapter_view")
    if not content then return nil, _("Không tìm thấy vùng ảnh truyện công khai.") end
    local pages, foreign = {}, false
    -- NOTE: never `for _, img` here; `_` would shadow gettext `_()` below.
    for _image_index, img in ipairs(Html.elements(content, "img")) do
        local attrs = attrsOf(img)
        local image
        for _key_index, key in ipairs({ "data-img", "data-src", "data-original", "src" }) do
            local raw = attrs[key]
            if not image and type(raw) == "string" and raw ~= "" then
                image = Source.imageUrl(ref.url, raw)
                if not image and isForeignImage(ref.url, raw) then foreign = true end
            end
        end
        if image then
            pages[#pages + 1] = image
            if #pages > Source.MAX_PAGES then return nil, _("Hỗ trợ tối đa 600 trang mỗi tập.") end
        elseif foreign then
            return nil, _("Có trang ảnh không hợp lệ hoặc máy chủ ảnh chưa hỗ trợ.")
        end
    end
    if #pages == 0 then return nil, _("Tập này không có ảnh đọc được.") end
    ref.pages = pages
    local title = text(Html.select(html, "h1"))
    ref.title = title ~= "" and title or ref.chapter
    return ref
end

function Source.getChapter(url)
    local ref = Source.parseRef(url)
    if not ref then return Source.parseChapter("", url) end
    local opts = { delay_ms = math.max(1600, Settings.delayMs()), referer = SITE .. "/",
        allow_url = function(next_url)
            local next_ref = Source.parseRef(next_url)
            return next_ref ~= nil and next_ref.series == ref.series
        end }
    local ok, code, html = Http.get(ref.url, opts)
    if not ok then
        if code == 429 then return nil, _("Dưa Leo Truyện giới hạn lượt tải (429). Thử lại sau.") end
        return nil, _("Không tải được tập truyện. HTTP: ") .. tostring(code)
    end
    return Source.parseChapter(html, ref.url)
end

return Source
