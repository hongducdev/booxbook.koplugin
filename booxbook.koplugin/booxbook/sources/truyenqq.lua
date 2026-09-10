-- TruyenQQ comic adapter (https://truyenqqko.com, custom layout, not Madara).
-- Series: /truyen-tranh/<slug>-<id> — chapter: /truyen-tranh/<slug>-chap-<n>.
-- Public pages only; no VIP/paywall bypass.
local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local Source = { MAX_PAGES = 600, id = "truyenqq", name = "TruyenQQ", kind = "comic",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://truyenqqko.com"
local hosts = { ["truyenqqko.com"] = true, ["m.truyenqqko.com"] = true }

local function text(html)
    return Html.decode((html or ""):gsub("<[^>]+>", " ")):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

function Source.parseSeriesRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$")
    local host, slug = url:match("^https?://([^/]+)/truyen%-tranh/([%w%-]+)/?$")
    if not hosts[host] or not slug or #slug > 128 or slug:find("%-chap%-%d+$") then return nil end
    return { id = slug, url = "https://" .. host .. "/truyen-tranh/" .. slug }
end

function Source.parseRef(url)
    if type(url) == "table" then url = url.url or url.ref end
    if type(url) ~= "string" then return nil end
    url = url:match("^%s*(.-)%s*$")
    local host, series, chapter = url:match("^https?://([^/]+)/truyen%-tranh/([%w%-]+)%-chap%-(%d+)/?$")
    if not hosts[host] or not series or #series > 128 or not chapter or #chapter > 6 then return nil end
    local series_url = "https://" .. host .. "/truyen-tranh/" .. series
    if not Source.parseSeriesRef(series_url) then return nil end
    return { url = series_url .. "-chap-" .. chapter,
        series = series, chapter = "chap-" .. chapter, number = tonumber(chapter) }
end

local function request(url)
    local opts = { referer = SITE .. "/", delay_ms = math.max(1600, Settings.delayMs()),
        allow_url = function(next_url) return hosts[next_url:match("^https?://([^/]+)/")] == true end }
    local ok, code, body = Http.get(url, opts)
    if code == 429 then return nil, _("TruyenQQ giới hạn lượt tải (429). Thử lại sau.") end
    if not ok then return nil, _("Không tải được TruyenQQ. HTTP: ") .. tostring(code) end
    if type(body) ~= "string" then return nil, _("Phản hồi truyện không hợp lệ.") end
    return Html.stripDangerous(body)
end

local function coverUrl(html, url)
    -- `html` may already be the avatar block itself (list rows) or a full page.
    for _, block in ipairs({ html or "", Html.select(html, ".book_avatar") or "",
            Html.select(html, ".book_info") or "" }) do
        for _, img in ipairs(Html.elements(block, "img")) do
            local attrs = {}
            for key, _q, value in img.attrs:gmatch("([%w_-]+)%s*=%s*([\"'])(.-)%2") do
                attrs[key:lower()] = value
            end
            local cover = Source.imageUrl(url, attrs["data-original"] or attrs.src)
            if cover then return cover end
        end
    end
end

local function itemTitle(row, href)
    for _, img in ipairs(Html.elements(row, "img")) do
        local alt = Html.decode(Html.attr(img.attrs, "alt") or "")
        if alt:match("%S") then return text(alt) end
    end
    local heading = Html.select(row, "h3") or Html.select(row, "h2") or ""
    if text(heading) ~= "" then return text(heading) end
    return text(href:match("/truyen%-tranh/([%w%-]+)/?$") or ""):gsub("%-", " ")
end

function Source.parseList(html, page)
    html = Html.stripDangerous(html or "")
    local rows = Html.elements(html, ".book_avatar")
    if #rows == 0 then
        if Html.select(html, ".no-results") or text(html) == "" then
            return { items = {}, has_more = false }
        end
        return nil, _("Không đọc được danh sách; trang có thể đã đổi hoặc yêu cầu xác minh.")
    end
    local items, seen, more = {}, {}, false
    for _, row in ipairs(rows) do
        for _, a in ipairs(Html.elements(row.inner, "a")) do
            local ref = Source.parseSeriesRef(Http.resolveUrl(SITE, Html.decode(Html.attr(a.attrs, "href") or "")))
            if ref and not seen[ref.id] then
                seen[ref.id] = true
                ref.title, ref.name = itemTitle(row.inner, ref.url), itemTitle(row.inner, ref.url)
                ref.cover = coverUrl(row.inner, SITE)
                items[#items + 1] = ref
            end
        end
    end
    if #items == 0 then return nil, _("Không đọc được liên kết bộ truyện.") end
    local current = tonumber(page) or 1
    for _, a in ipairs(Html.elements(html, "a")) do
        local href = Html.decode(Html.attr(a.attrs, "href") or "")
        local n = tonumber(href:match("/trang%-(%d+)") or href:match("[?&]page=(%d+)"))
        if n and n > current then more = true end
    end
    return { items = items, has_more = more }
end

local function list(query, page)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local path
    if query then
        query = query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
        if page > 1 then
            path = "/tim-kiem/" .. query .. "/trang-" .. page
        else
            path = "/tim-kiem/" .. query
        end
    else
        if page > 1 then
            path = "/truyen-moi-cap-nhat/trang-" .. page
        else
            path = "/doc-truyen"
        end
    end
    local html, err = request(SITE .. path)
    if not html then return nil, err end
    return Source.parseList(html, page)
end

function Source.browse(kind, page)
    if kind ~= nil and kind ~= "latest" then
        return nil, _("TruyenQQ hiện chỉ hỗ trợ Mới cập nhật.")
    end
    return list(nil, page)
end

function Source.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    return list(query, page)
end

function Source.parseSeries(html, url)
    local ref = Source.parseSeriesRef(url)
    if not ref then return nil, _("URL bộ truyện không hợp lệ.") end
    html = Html.stripDangerous(html or "")
    ref.title = text(Html.select(html, "h1"))
    if ref.title == "" then return nil, _("Không đọc được thông tin bộ truyện.") end
    ref.source_id = Source.id
    ref.author = text(Html.select(html, ".author") or "")
    ref.description = text(Html.select(html, ".story-detail-info") or "")
    ref.cover = coverUrl(html, url)
    local toc = Html.select(html, ".works-chapter-list") or Html.select(html, ".list_chapter") or html
    local chapters, seen = {}, {}
    -- NOTE: never `for _, a` here; `_` would shadow gettext `_()` below.
    for _index, a in ipairs(Html.elements(toc, "a")) do
        local ch = Source.parseRef(Http.resolveUrl(url, Html.decode(Html.attr(a.attrs, "href") or "")))
        if ch and ch.series == ref.id and ch.number and not seen[ch.number] then
            seen[ch.number] = true
            ch.title = text(a.inner)
            if ch.title == "" then ch.title = _("Chương ") .. ch.number end
            chapters[#chapters + 1] = ch
        end
    end
    if #chapters == 0 then return nil, _("Không đọc được mục lục công khai của bộ truyện.") end
    table.sort(chapters, function(a, b) return a.number < b.number end)
    ref.chapters = {}
    for _, ch in ipairs(chapters) do
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

function Source.imageUrl(base, value)
    if not value then return nil end
    value = Html.decode(value):match("^%s*(.-)%s*$")
    if value:find("[%c%s\\]") then return nil end
    local url = Http.resolveUrl(base, value)
    local host = url and url:match("^https://([^/]+)/")
    if not host then return nil end
    if hosts[host] or host == "st.truyenqqko.com" or host:match("%.hinhhinh%.com$")
        or host:match("%.truyenvua%.com$") then
        return url
    end
end

function Source.parseChapter(html, url)
    local ref = Source.parseRef(url)
    if not ref then return nil, _("Nhập URL một tập: https://truyenqqko.com/truyen-tranh/ten-truyen-chap-1") end
    local stripped = Html.stripDangerous(html or "")
    local content = Html.select(stripped, ".chapter_content")
        or Html.select(stripped, ".chapter_content_div")
        or Html.select(stripped, ".chapter_new_load")
    if not content then return nil, _("Không tìm thấy vùng ảnh truyện công khai.") end
    local pages = {}
    local page_elems = Html.elements(content, ".page-chapter")
    local img_elems = {}
    if #page_elems > 0 then
        for _page_index, elem in ipairs(page_elems) do
            local img = Html.elements(elem.inner, "img", true)[1]
            if not img then return nil, _("Có trang ảnh không hợp lệ hoặc máy chủ ảnh chưa hỗ trợ.") end
            img_elems[#img_elems + 1] = img
        end
    else
        img_elems = Html.elements(content, "img")
    end
    -- NOTE: never `for _, img` here; `_` would shadow gettext `_()` below.
    for _index, img in ipairs(img_elems) do
        local attrs = {}
        for key, _q, value in img.attrs:gmatch("([%w_-]+)%s*=%s*([\"'])(.-)%2") do
            attrs[key:lower()] = value
        end
        local src = attrs["data-original"] or attrs["data-src"] or attrs.src
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
    local ok, code, html = Http.get(ref.url, { delay_ms = 1600, referer = SITE .. "/",
        allow_url = function(next_url)
            local next_ref = Source.parseRef(next_url)
            return next_ref and next_ref.series == ref.series
        end })
    if not ok then
        if code == 429 then return nil, _("TruyenQQ giới hạn lượt tải (429). Thử lại sau.") end
        return nil, _("Không tải được tập truyện. HTTP: ") .. tostring(code)
    end
    return Source.parseChapter(html, ref.url)
end

return Source
