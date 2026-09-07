local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local Source = { MAX_PAGES = 600, id = "truyentuoitho", name = "Truyện Tuổi Thơ", kind = "comic",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://truyentuoitho.com"
local hosts = { ["truyentuoitho.com"] = true, ["truyentuoitho.online"] = true }

function Source.parseRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$")
    local host, series, chapter = url:match("^https://([^/]+)/manga/([%w%-]+)/([%w%-]+)/?$")
    if not hosts[host] or #series > 100 or #chapter > 100 then return nil end
    return { url = "https://" .. host .. "/manga/" .. series .. "/" .. chapter .. "/",
        series = series, chapter = chapter }
end

function Source.parseSeriesRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    local host, slug = url:match("^%s*https://([^/]+)/manga/([%w%-]+)/?%s*$")
    if not hosts[host] or #slug > 100 then return nil end
    return { id = slug, url = "https://" .. host .. "/manga/" .. slug .. "/" }
end

local function text(html)
    return Html.decode((html or ""):gsub("<[^>]+>", " ")):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function request(url, post)
    local opts = { referer = SITE .. "/", delay_ms = math.max(1600, Settings.delayMs()),
        allow_url = function(next_url) return hosts[next_url:match("^https://([^/]+)/")] == true end }
    local ok, code, body
    if post then ok, code, body = Http.post(url, "", opts) else ok, code, body = Http.get(url, opts) end
    if not ok then return nil, _("Không tải được Truyện Tuổi Thơ. HTTP: ") .. tostring(code) end
    if type(body) ~= "string" then return nil, _("Phản hồi truyện không hợp lệ.") end
    return Html.stripDangerous(body)
end

local function cover(html, url)
    local img = Html.elements(html, "img", true)[1]
    if not img then return nil end
    local attrs = {}
    for key, _, value in img.attrs:gmatch("([%w_-]+)%s*=%s*([\"'])(.-)%2") do attrs[key] = value end
    return Source.imageUrl(url, attrs["data-src"] or attrs["data-lazy-src"] or attrs.src)
end

function Source.parseList(html, page)
    html = Html.stripDangerous(html or "")
    local rows = Html.elements(html, ".page-item-detail")
    if #rows == 0 then rows = Html.elements(html, ".c-tabs-item__content") end
    if #rows == 0 and not Html.select(html, ".no-results") then
        return nil, _("Không đọc được danh sách; trang có thể đã đổi hoặc yêu cầu xác minh.")
    end
    local items, seen, more = {}, {}, false
    for _, row in ipairs(rows) do
        for _, a in ipairs(Html.elements(Html.select(row.inner, ".post-title"), "a")) do
            local ref = Source.parseSeriesRef(Http.resolveUrl(SITE, Html.decode(Html.attr(a.attrs, "href") or "")))
            if ref and not seen[ref.id] then
                seen[ref.id] = true
                ref.title, ref.name, ref.cover = text(a.inner), text(a.inner), cover(row.inner, SITE)
                items[#items + 1] = ref
            end
        end
    end
    if #rows > 0 and #items == 0 then return nil, _("Không đọc được liên kết bộ truyện.") end
    for _, a in ipairs(Html.elements(Html.select(html, ".wp-pagenavi"), "a")) do
        local href = Html.decode(Html.attr(a.attrs, "href") or "")
        local n = tonumber(href:match("/page/(%d+)/") or href:match("[?&]paged=(%d+)"))
        if n and n > (page or 1) then more = true end
    end
    return { items = items, has_more = more }
end

local function list(query, kind, page)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local path
    if query then
        query = query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
        path = "/?s=" .. query .. "&post_type=wp-manga&paged=" .. page
    else
        local orders = { latest = "latest", popular = "views", new = "new-manga", trending = "trending" }
        if not orders[kind or "latest"] then return nil, _("Kiểu danh sách không hợp lệ.") end
        path = "/manga/" .. (page > 1 and ("page/" .. page .. "/") or "") .. "?m_orderby=" .. orders[kind or "latest"]
    end
    local html, err = request(SITE .. path)
    if not html then return nil, err end
    return Source.parseList(html, page)
end

function Source.browse(kind, page) return list(nil, kind, page) end
function Source.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    return list(query, nil, page)
end

function Source.parseSeries(html, url, toc)
    local ref = Source.parseSeriesRef(url)
    if not ref then return nil, _("URL bộ truyện không hợp lệ.") end
    html = Html.stripDangerous(html or "")
    ref.title = text(Html.select(Html.select(html, ".post-title"), "h1"))
    if ref.title == "" then return nil, _("Không đọc được thông tin bộ truyện.") end
    ref.source_id, ref.author = Source.id, text(Html.select(html, ".author-content"))
    ref.description = text(Html.select(html, ".description-summary"))
    ref.cover = cover(Html.select(html, ".summary_image") or "", url)
    local chapters, seen = {}, {}
    for _, row in ipairs(Html.elements(Html.stripDangerous(toc or html), ".wp-manga-chapter")) do
        for _, a in ipairs(Html.elements(row.inner, "a")) do
            local ch = Source.parseRef(Http.resolveUrl(url, Html.decode(Html.attr(a.attrs, "href") or "")))
            if ch and ch.series == ref.id and not seen[ch.chapter] then
                seen[ch.chapter] = true
                ch.title = text(a.inner)
                chapters[#chapters + 1] = ch
            end
        end
    end
    if #chapters == 0 then return nil, _("Không đọc được mục lục công khai của bộ truyện.") end
    ref.chapters = {}
    -- Madara's public TOC is newest first, including chapters without numeric titles.
    for i = #chapters, 1, -1 do
        local ch = chapters[i]
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
    local toc
    if Html.select(html, "#manga-chapters-holder") then
        toc, err = request(ref.url .. "ajax/chapters/", true)
        if not toc then return nil, err end
    end
    return Source.parseSeries(html, ref.url, toc)
end

function Source.imageUrl(base, value)
    if not value then return nil end
    value = Html.decode(value):match("^%s*(.-)%s*$")
    if value:find("[%c%s\\]") then return nil end
    local url = Http.resolveUrl(base, value)
    local host = url and url:match("^https://([^/]+)/")
    if not hosts[host] and host ~= "img.resourcehub.shop" then return nil end
    return url
end

function Source.parseChapter(html, url)
    local ref = Source.parseRef(url)
    if not ref then return nil, _("Nhập URL một tập: https://truyentuoitho.com/manga/ten-truyen/tap-1/") end
    local content = Html.select(Html.stripDangerous(html or ""), ".reading-content")
    if not content then return nil, _("Không tìm thấy vùng ảnh truyện công khai.") end
    local pages = {}
    for image_index, img in ipairs(Html.elements(content, "img")) do
        -- Match attributes as tokens: src must not accidentally select data-src.
        local attrs = {}
        for key, _, value in img.attrs:gmatch("([%w_-]+)%s*=%s*([\"'])(.-)%2") do
            attrs[key:lower()] = value
        end
        local src = attrs["data-src"] or attrs["data-lazy-src"] or attrs.src
        local image = Source.imageUrl(ref.url, src)
        if not image then return nil, _("Có trang ảnh không hợp lệ hoặc máy chủ ảnh chưa hỗ trợ.") end
        pages[#pages + 1] = image
        if #pages > Source.MAX_PAGES then return nil, _("Hỗ trợ tối đa 600 trang mỗi tập.") end
    end
    if #pages == 0 then return nil, _("Tập này không có ảnh đọc được.") end
    ref.pages = pages
    ref.title = Html.decode((Html.select(html, "h1") or ref.chapter):gsub("<[^>]+>", ""))
    return ref
end

function Source.getChapter(url)
    local ref = Source.parseRef(url)
    if not ref then return Source.parseChapter("", url) end
    local ok, code, html = Http.get(ref.url, { delay_ms = 1600,
        allow_url = function(next_url)
            local next_ref = Source.parseRef(next_url)
            return next_ref and next_ref.series == ref.series and next_ref.chapter == ref.chapter
        end })
    if not ok then return nil, _("Không tải được tập truyện. HTTP: ") .. tostring(code) end
    return Source.parseChapter(html, ref.url)
end

return Source
