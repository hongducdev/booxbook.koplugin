-- AkayTruyen (akaytruyen.com) novel adapter.
--
-- Public browsing, search, table of contents and chapter text only. The site
-- also has a login form, but BooxBook has no login flow: when the reader has
-- pasted a session cookie into Settings the adapter simply sends it, and a
-- chapter that still cannot be read is reported as skipped instead of aborting
-- a download range.
local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Parser = require("booxbook.sources.akaytruyen-parser")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end

local A = { id = "akaytruyen", name = "AkayTruyen", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://akaytruyen.com"
local HOST = "akaytruyen.com"
local MAX_TOC_PAGES = 60
local CHANGED = _("Không đọc được HTML AkayTruyen; trang có thể đã đổi cấu trúc.")
local LOGIN_REQUIRED = _("Chương cần đăng nhập.")

A.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://akaytruyen.com/truyen/ten-truyen/",
    browse = {
        { text = "Hot", kind = "latest" },
        { text = "Đang ra", kind = "ongoing" },
        { text = "Hoàn thành", kind = "completed" },
    },
    is_ref = function(text)
        return type(text) == "string" and text:match("^https?://") ~= nil
    end,
}

-- Series folder on disk is the slug; a chapter reference carries the slug plus
-- the chapter segment so Source.findRef can never route a foreign URL here.
function A.parseRef(ref)
    if type(ref) == "table" then ref = ref.url or ref.ref end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if not host then return nil end
        host = host:lower():gsub("^www%.", ""):gsub(":%d+$", "")
        if host ~= HOST then return nil end
        ref = path
    end
    ref = (ref:match("^[^?#]+") or ""):gsub("/+$", "")
    local slug = ref:match("^/truyen/([%w%-_%.]+)$")
    if slug and #slug <= 180 and slug ~= "truyen" and not slug:find("%.%.") then return slug end
    local series, chapter = ref:match("^/([%w%-_%.]+)/([%w%-_%.]+)$")
    if series and series ~= "truyen" and not series:find("%.%.") and not chapter:find("%.%.")
            and #series <= 180 and #chapter <= 64 then
        return series, chapter, ref
    end
end

function A.locate(series)
    local id, chapter = A.parseRef(series)
    if not id or chapter then return id, nil end
    return id, id
end

-- Chapter slug is also the file name suffix; 64 is chapterFileName()'s ceiling.
function A.chapterRef(chapter)
    local series_id, chapter_id = A.parseRef(chapter)
    if type(chapter) == "table" and chapter.series_id ~= series_id then series_id = nil end
    return series_id, chapter_id, 64
end

-- Keys are the site's /the-loai/ slugs, so browse() needs no extra mapping.
local GENRES = {}
A.genres = {}
for _, entry in ipairs({
    { "co-dai", "Cổ Đại" }, { "tien-hiep", "Tiên Hiệp" }, { "huyen-huyen", "Huyền Huyễn" },
    { "goc-cam-ky-thi-hoa", "Góc cầm kỳ thi họa" }, { "gia-tuong", "Giả tưởng" },
    { "hai-huoc", "Hài Hước" }, { "tam-linh", "Tâm Linh" }, { "kinh-di", "Kinh Dị" },
    { "hien-dai", "Hiện Đại" }, { "noi-tam", "Nội Tâm" }, { "ngon-tinh", "Ngôn Tình" },
    { "hoc-duong", "Học Đường" }, { "xuyen-khong", "Xuyên Không" }, { "event", "EVENT" },
    { "nu-cuong", "Nữ Cường" }, { "trung-sinh", "Trùng Sinh" }, { "vong-du", "Võng Du" },
    { "giai-tri", "Giải Trí" }, { "khoa-huyen", "Khoa Huyễn" }, { "hac-am", "Hắc Ám" },
    { "tu-chan-sinh-hoc", "Tu Chân Sinh Học" }, { "co-tich-bien-tau", "Cổ Tích biến tấu" },
    { "di-gioi", "Dị Giới" },
}) do
    local genre = { key = entry[1], name = entry[2] }
    GENRES[genre.key] = genre
    A.genres[#A.genres + 1] = genre
end

local function cookieValue()
    local value = Settings.cookie("akaytruyen")
    if type(value) ~= "string" or value == "" then value = Settings.get("akaytruyen_cookie") end
    if type(value) == "string" and value ~= "" then return value end
end

local function absolute(path)
    return path:match("^https?://") and path or (SITE .. path)
end

-- Never log the cookie; Http redacts it. sanitize=false is only for the JSON
-- chapter-list endpoint, whose payload must be decoded before tag stripping.
local function request(path, sanitize)
    local opts = { referer = SITE .. "/", delay_ms = math.max(1600, Settings.delayMs()) }
    local cookie = cookieValue()
    if cookie then opts.cookies = cookie end
    local ok, code, body = Http.get(absolute(path), opts)
    if not ok then
        if code == 404 or code == 410 then return nil, _("Truyện/chương không còn tồn tại."), code end
        if code == 401 or code == 403 then return nil, LOGIN_REQUIRED, code end
        if code == 429 then return nil, _("AkayTruyen giới hạn lượt tải (429). Thử lại sau."), code end
        return nil, string.format(_("Không tải được AkayTruyen (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    if sanitize == false then return body end
    return Html.stripDangerous(body)
end

local function listPage(path, page, allow_empty)
    local body, err = request(path)
    if not body then return nil, err end
    local items = Parser.items(body, SITE)
    if #items == 0 and page == 1 and not allow_empty then return nil, CHANGED end
    return { items = items, has_more = Parser.hasMore(body, page) }
end

local function pageNumber(page)
    page = tonumber(page or 1)
    return page and page >= 1 and page <= 10000 and page % 1 == 0 and page
end

local HOME_TTL = 120
local home = { data = nil, at = 0 }
local SECTIONS = { latest = "hot", ongoing = "ongoing", completed = "completed" }

-- One homepage fetch serves all three browse lists; the parsed groups are
-- cached instead of the ~1 MB document.
local function homeData()
    local now = os.time()
    if home.data and (now - home.at) < HOME_TTL then return home.data end
    local body, err = request("/")
    if not body then return nil, err end
    local data = Parser.homeSections(body, SITE)
    if not data then return nil, CHANGED end
    home.data, home.at = data, now
    return data
end

function A.browse(kind, page)
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    kind = kind or "latest"
    local genre = GENRES[kind]
    if genre then
        local path = "/the-loai/" .. genre.key .. (page > 1 and ("?page=" .. page) or "")
        return listPage(path, page, true)
    end
    local section = SECTIONS[kind]
    if not section then return nil, _("Kiểu danh sách không hợp lệ.") end
    local data, err = homeData()
    if not data then return nil, err end
    if page ~= 1 then return { items = {}, has_more = false } end
    local items = {}
    for _, item in ipairs(data[section]) do
        items[#items + 1] = { ref = item.ref, url = item.url, title = item.title,
            name = item.name, cover = item.cover }
    end
    return { items = items, has_more = false }
end

function A.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    -- The header form posts `key_word`; an unknown parameter returns the plain
    -- latest list, which would silently look like a match.
    local escaped = query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
    local path = "/tim-kiem?key_word=" .. escaped
    if page > 1 then path = path .. "&page=" .. page end
    return listPage(path, page, true)
end

local function storyPath(slug) return "/truyen/" .. slug end

local function tocPath(slug, page)
    if page <= 1 then return storyPath(slug) end
    return storyPath(slug) .. "?page=" .. tostring(page)
end

local function fragmentPath(slug, page)
    return storyPath(slug) .. "/search-chapters?search=&page=" .. tostring(page)
end

function A.getSeries(ref)
    local slug, chapter = A.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện AkayTruyen không hợp lệ.") end
    -- The story page is the only place with title/author/cover, so it is fetched
    -- once and doubles as table-of-contents page 1 for the fallback path.
    local story_html, err = request(storyPath(slug))
    if not story_html then return nil, err end
    local details = Parser.details(story_html)
    if not details.title then return nil, CHANGED end

    local chapters, seen = {}, {}
    local function merge(html)
        local added = 0
        for _, item in ipairs(Parser.chapters(html, SITE, slug)) do
            if not seen[item.url] then
                seen[item.url] = true
                chapters[#chapters + 1] = { id = item.id, series_id = slug, url = item.url,
                    title = item.title, locked = item.locked }
                added = added + 1
            end
        end
        return added
    end

    merge(story_html)
    local total = Parser.pageCount(story_html)
    local page, use_fragment, truncated = 2, true, false
    while page <= total do
        local reused = false
        if use_fragment then
            -- Lightweight chapter fragment first; the endpoint currently answers
            -- 422 for an empty search, so a single failure disables it and the
            -- full story page takes over for the remaining pages.
            local raw = request(fragmentPath(slug, page), false)
            if raw then
                local fragment = Parser.decodeFragment(raw)
                if fragment then fragment = Html.stripDangerous(fragment) end
                if fragment and merge(fragment) > 0 then reused = true end
            end
            if not reused then use_fragment = false end
        end
        if not reused then
            local page_body, page_err, page_code = request(tocPath(slug, page))
            if not page_body then
                if page_code == 404 or page_code == 410 then break end
                return nil, page_err
            end
            if merge(page_body) == 0 then break end
        end
        if page >= MAX_TOC_PAGES or Http.expired() then
            truncated = true
            break
        end
        page = page + 1
    end
    if #chapters == 0 then return nil, CHANGED end

    -- The site lists newest chapter first; the reader expects oldest first.
    local ordered = {}
    for index = #chapters, 1, -1 do
        local item = chapters[index]
        item.index = #chapters - index + 1
        ordered[#ordered + 1] = item
    end
    local series = { id = slug, source_id = A.id, title = details.title,
        url = SITE .. storyPath(slug), description = details.description,
        author = details.author, cover = details.cover, chapters = ordered,
        volumes = { { title = _("Chương"), chapters = ordered } } }
    if truncated then series.truncated = true end
    return series
end

function A.getChapter(ref)
    local slug, chapter_id, path = A.parseRef(ref)
    if not chapter_id or type(ref) ~= "table" or ref.series_id ~= slug then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local html, err, code = request(type(ref.url) == "string" and ref.url or path)
    if not html then
        -- A locked/removed chapter must not abort the whole download range.
        if code == 404 or code == 410 or code == 401 or code == 403 then return { skipped = err } end
        return nil, err
    end
    if Parser.locked(html) then return { skipped = LOGIN_REQUIRED } end
    local content = Html.select(html, "#chapter-content")
    local body = content and Parser.paragraphs(content) or ""
    if body == "" then return { skipped = _("Chương trống.") } end
    local title = Parser.chapterTitle(html) or ref.title or _("Chương")
    return { title = title, html = body }
end

return A
