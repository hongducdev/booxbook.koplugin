-- Cbunu comic adapter.
--
-- The site answers on two hostnames — `cbunu.com` and `cucbongunu.com` — but
-- every link, cover and page image it emits is absolute on `cucbongunu.com`, so
-- that is the canonical base. Refs pasted on either host are accepted.
--
-- Series:  /truyen-tranh/<slug>-<id>
-- Chapter: /truyen-tranh/<slug>-<id>-chap-<n>.html      (n may be fractional, e.g. 19.5)
--
-- A page can answer 403 (or the site's login page) when it sits behind the
-- site-wide `access_pass` gate. On request this adapter keeps the upstream
-- Z-Truyenviet behaviour of answering that gate with the site's shared access
-- passwords and reusing the session cookie it gets back. It is a fallback only:
-- public pages never reach it, and a chapter that still cannot be read is
-- reported as locked instead of failing the whole download range.
-- The recorded exception to the "never bypass a paywall" convention lives in
-- docs/development-roadmap.md.
local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end

local Source = { MAX_PAGES = 600, id = "cbunu", name = "Cbunu", kind = "comic",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://cucbongunu.com"
local hosts = { ["cucbongunu.com"] = true, ["www.cucbongunu.com"] = true,
    ["cbunu.com"] = true, ["www.cbunu.com"] = true }
-- Covers and page images are served by the site itself; nothing else is accepted.
local IMAGE_HOSTS = { ["cucbongunu.com"] = true, ["www.cucbongunu.com"] = true,
    ["cbunu.com"] = true, ["www.cbunu.com"] = true }

-- Shared access passwords, tried in the same order as the upstream source.
local ACCESS_PASSWORDS = { "2026", "12345" }
local SESSION_TTL = 30 * 60

local CHANGED = _("Không đọc được trang Cbunu; trang có thể đã đổi hoặc yêu cầu xác minh.")
local GATED = _("Chương cần mật khẩu truy cập của Cbunu.")

Source.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Tên truyện, URL bộ truyện hoặc URL một tập",
    loading = "Đang tải tập %s…",
    last_url_key = "cbunu_last_url",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Truyện hay", kind = "hay" },
        { text = "Hoàn thành", kind = "completed" },
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

local function allowedUrl(next_url)
    return type(next_url) == "string" and hosts[next_url:match("^https?://([^/]+)/")] == true
end

local function imageUrl(base, value)
    if not value then return nil end
    value = Html.decode(value):match("^%s*(.-)%s*$")
    -- A URL with control characters, whitespace or a backslash is not one.
    if value == "" or value:find("[%c%s\\]") then return nil end
    local url = Http.resolveUrl(base, value)
    local host = url and url:match("^https://([^/]+)/")
    if not host or not IMAGE_HOSTS[host] then return nil end
    return url
end

function Source.parseSeriesRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$")
    local host, slug = url:match("^https?://([^/]+)/truyen%-tranh/([%w%-%.]+)/?$")
    if not hosts[host] or not slug or #slug < 2 or #slug > 160 then return nil end
    -- A chapter URL also ends in /truyen-tranh/<slug>-chap-<n>; it is not a series.
    if slug:find("%-chap%-%d") then return nil end
    return { id = slug, url = SITE .. "/truyen-tranh/" .. slug }
end

function Source.parseRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$")
    local host, series, chapter = url:match("^https?://([^/]+)/truyen%-tranh/([%w%-%.]-)%-chap%-([%d%.]+)%.html/?$")
    if not host then
        host, series, chapter = url:match("^https?://([^/]+)/truyen%-tranh/([%w%-%.]-)%-chap%-([%d%.]+)/?$")
    end
    if not hosts[host] or not series or #series < 2 or #series > 160 then return nil end
    local number = tonumber(chapter)
    if not number or number <= 0 then return nil end
    if not Source.parseSeriesRef(SITE .. "/truyen-tranh/" .. series) then return nil end
    return { url = SITE .. "/truyen-tranh/" .. series .. "-chap-" .. chapter .. ".html",
        series = series, chapter = "chap-" .. chapter, number = number }
end

-- Session cookie obtained by answering the access gate, plus when it was
-- refreshed. Module state, so it lives for the reader session only.
local session = { cookies = nil, at = 0 }

local function sessionCookies()
    if session.cookies and (os.time() - session.at) <= SESSION_TTL then
        return session.cookies
    end
    return nil
end

local function mergeJar(jar)
    if type(jar) ~= "table" or next(jar) == nil then return end
    session.cookies = Http.mergeCookies(session.cookies or {}, jar)
    session.at = os.time()
end

local function isLoginPage(body)
    return type(body) == "string" and body:find("<title>Đăng nhập</title>", 1, true) ~= nil
end

local function requestCookies()
    local cookies = Http.mergeCookies(Settings.cookie(Source.id), sessionCookies())
    if next(cookies) == nil then return nil end
    return cookies
end

-- One GET. Never answers the gate: `unlock` retries through this, so a single
-- request cannot trigger two rounds of password attempts.
local function rawGet(url)
    local ok, code, body, _headers, jar = Http.get(url, {
        referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()),
        cookies = requestCookies(),
        allow_url = allowedUrl,
    })
    mergeJar(jar)
    return ok, code, body
end

-- Answer the site-wide access gate. `max_hops = 0` keeps the 302 from being
-- followed so the Set-Cookie that comes with it is still readable.
local function unlock(url)
    for _index, password in ipairs(ACCESS_PASSWORDS) do
        local _ok, code, body, _headers, jar = Http.post(url, "access_pass=" .. password, {
            referer = SITE .. "/",
            delay_ms = math.max(1600, Settings.delayMs()),
            cookies = requestCookies(),
            max_hops = 0,
            allow_url = allowedUrl,
        })
        mergeJar(jar)
        local html
        if code == 200 and type(body) == "string" and body ~= "" then
            html = body
        elseif code == 200 or code == 302 or code == 303 then
            local retry_ok, retry_code, retry_body = rawGet(url)
            if retry_ok and retry_code == 200 then html = retry_body end
        end
        if html and not isLoginPage(html) then return html end
    end
end

local function get(url)
    local ok, code, body = rawGet(url)
    if ok and type(body) == "string" and not isLoginPage(body) then return body end
    if code == 429 then return nil, _("Cbunu giới hạn lượt tải (429). Thử lại sau.") end
    if code == 404 or code == 410 then return nil, _("Tập truyện không còn tồn tại.") end
    if code == 403 or isLoginPage(body) then
        local html = unlock(url)
        if html then return html end
        return nil, GATED
    end
    return nil, CHANGED
end

local function itemTitle(row, fallback)
    local heading = Html.select(row, ".title-book")
    local title = text(heading)
    if title ~= "" then return title end
    for _index, img in ipairs(Html.elements(row, "img")) do
        title = text(Html.attr(img.attrs, "alt") or "")
        if title ~= "" then return title end
    end
    return text(fallback)
end

function Source.parseList(html, page, allow_empty)
    html = Html.stripDangerous(html or "")
    local rows = Html.elements(html, ".story-item")
    if #rows == 0 then
        if allow_empty or text(html) == "" then return { items = {}, has_more = false } end
        return nil, CHANGED
    end
    local items, seen, more = {}, {}, false
    for _index, row in ipairs(rows) do
        local ref, title
        for _anchor_index, a in ipairs(Html.elements(row.inner, "a")) do
            local candidate = Source.parseSeriesRef(Http.resolveUrl(SITE, Html.decode(Html.attr(a.attrs, "href") or "")))
            if candidate then
                ref = candidate
                title = itemTitle(row.inner, Html.attr(a.attrs, "title") or a.inner)
                break
            end
        end
        if ref and not seen[ref.id] then
            seen[ref.id] = true
            ref.title, ref.name = title, title
            for _img_index, img in ipairs(Html.elements(row.inner, "img")) do
                local cover = imageUrl(SITE, Html.attr(img.attrs, "src") or Html.attr(img.attrs, "data-original"))
                if cover then
                    ref.cover = cover
                    break
                end
            end
            items[#items + 1] = ref
        end
    end
    if #items == 0 and (tonumber(page) or 1) == 1 and not allow_empty then return nil, CHANGED end
    local current = tonumber(page) or 1
    for _index, a in ipairs(Html.elements(html, "a")) do
        local href = Html.decode(Html.attr(a.attrs, "href") or "")
        local number = tonumber(href:match("/trang%-(%d+)%.html"))
        if number and number > current then more = true end
    end
    return { items = items, has_more = more }
end

local function listPath(kind, page)
    if kind == nil or kind == "latest" then
        return page == 1 and "/" or ("/trang-" .. page .. ".html")
    end
    if kind == "hay" then
        return page == 1 and "/truyen-tranh-hay.html" or ("/truyen-tranh-hay/trang-" .. page .. ".html")
    end
    if kind == "completed" then
        return page == 1 and "/truyen-hoan-thanh.html" or ("/truyen-hoan-thanh/trang-" .. page .. ".html")
    end
end

function Source.browse(kind, page)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local path = listPath(kind, page)
    if not path then return nil, _("Cbunu không hỗ trợ danh sách này.") end
    local html, err = get(SITE .. path)
    if not html then return nil, err end
    return Source.parseList(html, page, page > 1)
end

function Source.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1) or 1
    -- The site's search page is not paginated.
    if page > 1 then return { items = {}, has_more = false } end
    local encoded = query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
    local html, err = get(SITE .. "/tim-kiem.html?q=" .. encoded)
    if not html then return nil, err end
    return Source.parseList(html, 1, true)
end

function Source.parseSeries(html, url)
    local ref = Source.parseSeriesRef(url)
    if not ref then return nil, _("URL bộ truyện không hợp lệ.") end
    html = Html.stripDangerous(html or "")
    ref.title = text(Html.select(html, "h1"))
    if ref.title == "" then return nil, _("Không đọc được thông tin bộ truyện.") end
    ref.source_id = Source.id
    -- This layout has no summary block; the meta description is all it publishes.
    ref.description = text(Html.select(html, ".story-detail-info.detail-content") or "")
    if ref.description == "" then
        ref.description = text(html:match('<meta[^>]-name="description"[^>]-content="([^"]*)"') or "")
    end
    for _index, el in ipairs(Html.elements(html, ".info-item")) do
        local author = text(el.inner):match("^Tác giả:%s*(.-)%s*$")
        if author and author ~= "" then
            ref.author = author
            break
        end
    end
    for _index, img in ipairs(Html.elements(Html.select(html, ".block01") or "", "img")) do
        local cover = imageUrl(SITE, Html.attr(img.attrs, "src") or Html.attr(img.attrs, "data-original"))
        if cover then
            ref.cover = cover
            break
        end
    end
    local toc = Html.select(html, ".works-chapter-list") or html
    local chapters, seen = {}, {}
    -- NOTE: never `for _, a` here; `_` would shadow gettext `_()` below.
    for _index, a in ipairs(Html.elements(toc, "a")) do
        local ch = Source.parseRef(Http.resolveUrl(SITE, Html.decode(Html.attr(a.attrs, "href") or "")))
        if ch and ch.series == ref.id and not seen[ch.number] then
            seen[ch.number] = true
            ch.title = text(a.inner)
            if ch.title == "" then ch.title = _("Chương ") .. tostring(ch.number) end
            chapters[#chapters + 1] = ch
        end
    end
    if #chapters == 0 then return nil, _("Không đọc được mục lục công khai của bộ truyện.") end
    -- The page lists chapters newest-first; the reader wants reading order.
    table.sort(chapters, function(a, b) return a.number < b.number end)
    ref.chapters = {}
    for _index, ch in ipairs(chapters) do
        ch.index = #ref.chapters + 1
        ref.chapters[ch.index] = ch
    end
    ref.volumes = { { title = _("Danh sách tập"), chapters = ref.chapters } }
    return ref
end

function Source.getSeries(url)
    local ref = Source.parseSeriesRef(url)
    if not ref then return nil, _("URL bộ truyện không hợp lệ.") end
    local html, err = get(ref.url)
    if not html then return nil, err end
    return Source.parseSeries(html, ref.url)
end

function Source.parseChapter(html, url)
    local ref = Source.parseRef(url)
    if not ref then return nil, _("Nhập URL một tập: https://cucbongunu.com/truyen-tranh/ten-truyen-123-chap-1.html") end
    local stripped = Html.stripDangerous(html or "")
    local content = Html.select(stripped, ".story-see-content")
    if not content then return nil, _("Không tìm thấy vùng ảnh truyện công khai.") end
    local pages = {}
    -- NOTE: never `for _, img` here; `_` would shadow gettext `_()` below.
    for _index, img in ipairs(Html.elements(content, "img")) do
        local attrs = {}
        for key, _quote, value in img.attrs:gmatch("([%w_-]+)%s*=%s*([\"'])(.-)%2") do
            attrs[key:lower()] = value
        end
        local value = attrs["data-original"] or attrs["data-src"] or attrs["data-cdn"] or attrs["data-fb"] or attrs.src
        local image = imageUrl(ref.url, value)
        -- The chapter body also carries a site notice image; only lazy-loaded
        -- page scans (or the site's /chap/ path) are real pages.
        if image and ((attrs["class"] or ""):find("lazy", 1, true) or image:find("/chap/", 1, true)) then
            pages[#pages + 1] = image
            if #pages > Source.MAX_PAGES then return nil, _("Hỗ trợ tối đa 600 trang mỗi tập.") end
        end
    end
    if #pages == 0 then return nil, _("Tập này không có ảnh đọc được.") end
    ref.pages = pages
    ref.title = text(Html.select(stripped, "h1") or ref.chapter)
    return ref
end

function Source.getChapter(url)
    local ref = Source.parseRef(url)
    if not ref then return nil, _("URL một tập không hợp lệ.") end
    local html, err = get(ref.url)
    if not html then return nil, err end
    return Source.parseChapter(html, ref.url)
end

return Source
