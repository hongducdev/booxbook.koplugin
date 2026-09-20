local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local T = { id = "metruyenchuvn", name = "Mê Truyện Chữ VN", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://metruyenchuvn.org"
-- Bounded on purpose: the chapter list is an ajax endpoint that returns 100
-- chapters per page, and a broken server must not hold the reader here.
local MAX_TOC_PAGES = 60
local CHANGED = _("Không đọc được HTML Mê Truyện Chữ VN; trang có thể đã đổi.")
local HOSTS = { ["metruyenchuvn.org"] = true, ["www.metruyenchuvn.org"] = true }

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://metruyenchuvn.org/ten-truyen",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Truyện hot", kind = "popular" },
        { text = "Truyện full", kind = "full" },
    },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/[%w%-]+") ~= nil
    end,
}

function T.locate(series)
    local id, chapter = T.parseRef(series and series.url or series)
    if not id or chapter then return id, nil end
    return id, id
end

-- Chapter identity used when saving: (series_id, chapter_id). The chapter segment
-- carries an opaque token ("chuong-12-aBcD" or "chuong-tiep-aBcD"), not a number.
function T.chapterRef(chapter)
    local series_id, chapter_id = T.parseRef(chapter)
    if chapter.series_id ~= series_id then series_id = nil end
    return series_id, chapter_id
end

local function text(value)
    -- The theme pads with non-breaking spaces, both as the entity and as the decoded
    -- byte pair, and neither is whitespace to Lua.
    local decoded = Html.decode((value or ""):gsub("<[^>]+>", ""))
    return (decoded:gsub("&nbsp;", " "):gsub("\194\160", " ")):match("^%s*(.-)%s*$") or ""
end
-- The site returns chapter lists as JSON with escaped HTML inside ("\u003cdiv…"),
-- so unescape before scanning, then run the normal sanitizer over the result.
local function normalizeEscaped(body)
    return body:gsub("\\u003c", "<"):gsub("\\u003e", ">"):gsub("\\u0027", "'")
        :gsub("\\u0022", '"'):gsub('\\"', '"'):gsub("\\/", "/"):gsub("\\\\", "\\")
end
local function meta(html, attribute, value)
    for attrs in (html or ""):gmatch("<meta%s+([^>]*)>") do
        if Html.attr(attrs, attribute) == value then return Html.attr(attrs, "content") end
    end
end
local function hasLock(body)
    return body and (body:find("Mở khóa", 1, true) or body:find("NHẬP MÃ", 1, true))
end

-- Categories, chapters and every site page share one path level, so story links
-- are recognised by shape alone. This guard is what keeps category, chapter and
-- account links from being listed as stories.
local BLOCKED = { "danh-sach", "the-loai", "tac-gia", "chuong-", "search", "tim-kiem",
    "contact", "policy", "dmca", "about", "privacy", "terms", "user", "login", "register",
    "history", "images", "theme", "tos", "favicon" }
local function isValidStoryPath(path)
    if not path or #path < 3 or path == "/" then return false end
    local lower = path:lower()
    for _, prefix in ipairs(BLOCKED) do
        if lower:sub(1, #prefix + 1) == "/" .. prefix then return false end
    end
    return lower:match("^/[%w%-]+/?$") ~= nil
end

function T.parseRef(ref)
    if type(ref) == "table" then ref = ref.url or ref.ref end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if not host or not HOSTS[host:lower()] then return nil end
        ref = path
    end
    ref = (ref:match("^[^?#]+") or ""):gsub("/+$", "")
    if ref == "" then return nil end
    local slug, chapter = ref:match("^/([%w%-]+)/(chuong%-[%w!_%-]+)$")
    if slug and #slug <= 180 and isValidStoryPath("/" .. slug) then
        return slug, chapter, "/" .. slug .. "/" .. chapter
    end
    local story = ref:match("^/([%w%-]+)$") or ref:match("^([%w%-]+)$")
    if story and isValidStoryPath("/" .. story) then return story end
end

local function request(path)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được Mê Truyện Chữ VN (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(normalizeEscaped(body))
end

local function hasMore(html, page)
    local want = tostring(page + 1)
    for _, a in ipairs(Html.elements(html, "a")) do
        local href = Html.attr(a.attrs, "href") or ""
        if (href:match("[?&]page=(%d+)") or href:match("[?&]p=(%d+)")) == want then return true end
    end
end

local function storyItem(href, title, cover)
    if type(href) ~= "string" then return nil end
    -- List links are root-absolute or absolute, exactly like the source's list scan:
    -- a bare relative href on a nested listing page would resolve somewhere else.
    if not (href:match("^/") or href:match("^https?://")) then return nil end
    local slug, chapter = T.parseRef(href)
    title = text(title)
    if not slug or chapter or title == "" then return nil end
    return { ref = "/" .. slug, url = SITE .. "/" .. slug, title = title, name = title, cover = cover }
end

local function items(html)
    local found, seen = {}, {}
    local function keep(entry)
        if entry and not seen[entry.ref] then
            seen[entry.ref] = true
            found[#found + 1] = entry
        end
    end
    local list = Html.select(html, ".truyen-list") or ""
    if list ~= "" then
        for _, card in ipairs(Html.elements(list, ".item")) do
            local heading = Html.select(card.inner, "h3") or ""
            local anchor = Html.elements(heading, "a", true)[1]
            local image = card.inner:match("<img([^>]*)>")
            local cover = image and Html.attr(image, "src")
            if cover and cover:lower():match("%.webp") then cover = nil end
            if anchor then keep(storyItem(Html.attr(anchor.attrs, "href"), anchor.inner, cover)) end
        end
    end
    if #found == 0 then
        -- Same fallback the source used: any anchor whose path looks like a story.
        for _, a in ipairs(Html.elements(html, "a")) do
            keep(storyItem(Html.attr(a.attrs, "href"), a.inner))
        end
    end
    return found
end

local function list(path, page, allow_empty, fallback)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request(path .. (path:find("?", 1, true) and "&" or "?") .. "page=" .. page)
    if not html and fallback and page == 1 then html, err = request(fallback) end
    if not html then return nil, err end
    local found = items(html)
    -- A listing page with no story on page 1 means the markup changed; a search may
    -- legitimately return nothing.
    if #found == 0 and page == 1 and not allow_empty then return nil, CHANGED end
    return { items = found, has_more = hasMore(html, page) == true }
end

-- Keys are the site's /the-loai/<key> slugs (checked live), so browse() needs no
-- extra mapping.
local GENRE_KEYS = {
    { "tien-hiep", "Tiên Hiệp" }, { "kiem-hiep", "Kiếm Hiệp" }, { "ngon-tinh", "Ngôn Tình" },
    { "dam-my", "Đam Mỹ" }, { "huyen-huyen", "Huyền Huyễn" }, { "khoa-huyen", "Khoa Huyễn" },
    { "di-gioi", "Dị Giới" }, { "di-nang", "Dị Năng" }, { "do-thi", "Đô Thị" },
    { "quan-truong", "Quan Trường" }, { "quan-su", "Quân Sự" }, { "lich-su", "Lịch Sử" },
    { "vong-du", "Võng Du" }, { "he-thong", "Hệ Thống" }, { "trong-sinh", "Trọng Sinh" },
    { "xuyen-khong", "Xuyên Không" }, { "xuyen-sach", "Xuyên Sách" }, { "co-dai", "Cổ Đại" },
    { "dong-phuong", "Đông Phương" }, { "phuong-tay", "Phương Tây" }, { "mat-the", "Mạt Thế" },
    { "linh-di", "Linh Dị" }, { "trinh-tham", "Trinh Thám" }, { "hai-huoc", "Hài Hước" },
    { "nguoc", "Ngược" }, { "sung", "Sủng" }, { "cung-dau", "Cung Đấu" },
    { "gia-dau", "Gia Đấu" }, { "nu-cuong", "Nữ Cường" }, { "nu-phu", "Nữ Phụ" },
    { "dien-van", "Điền Văn" }, { "doan-van", "Đoản Văn" }, { "truyen-teen", "Truyện Teen" },
    { "light-novel", "Light Novel" }, { "viet-nam", "Việt Nam" }, { "khac", "Khác" },
}
local GENRES = {}
T.genres = {}
for _, entry in ipairs(GENRE_KEYS) do
    local genre = { key = entry[1], name = entry[2] }
    GENRES[genre.key] = genre
    T.genres[#T.genres + 1] = genre
end

function T.browse(kind, page)
    local kinds = { latest = "/danh-sach/truyen-moi", popular = "/danh-sach/truyen-hot",
        full = "/danh-sach/truyen-full" }
    local genre = GENRES[kind]
    if kind ~= nil and not genre and not kinds[kind] then return nil, _("Kiểu danh sách không hợp lệ.") end
    if genre then return list("/the-loai/" .. genre.key, page) end
    local path = kinds[kind or "latest"]
    -- The "mới cập nhật" listing 404s on the current deployment; the homepage is
    -- the same shelf, so page 1 falls back to it.
    return list(path, page, false, path == kinds.latest and "/" or nil)
end

local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end

function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request("/search?q=" .. encode(query):gsub("%%20", "+"))
    if not html then
        if page > 1 then return { items = {}, has_more = false } end
        html, err = request("/")
    elseif #html < 500 and page == 1 then
        -- Empty search page: the source falls back to the homepage shelf.
        html = request("/") or html
    end
    if not html then return nil, err end
    return { items = items(html), has_more = false }
end

local function chaptersOf(html, slug, seen, chapters)
    local added = 0
    for _, a in ipairs(Html.elements(html, "a")) do
        local href = Html.decode(Html.attr(a.attrs, "href") or "")
        local path = href:match("^https?://[^/]+(/.*)$") or href
        local owner, chapter_id = (path:match("^[^?#]+") or ""):match("^/([%w%-]+)/(chuong%-[%w!_%-]+)$")
        if owner == slug and chapter_id and not seen[chapter_id] then
            seen[chapter_id] = true
            added = added + 1
            chapters[#chapters + 1] = { id = chapter_id, series_id = slug,
                url = SITE .. "/" .. slug .. "/" .. chapter_id, title = text(a.inner),
                number = tonumber(chapter_id:match("^chuong%-(%d+)")) }
        end
    end
    return added
end

-- The chapter list endpoint wants the numeric book id, which lives in the hidden
-- "notify me" input of the story page (survives sanitizing); the pagination buttons
-- carry it too, when the theme keeps them without an event handler.
local function bookId(html)
    for attrs in html:gmatch("<input%s+([^>]*)>") do
        if Html.attr(attrs, "name") == "bid" then
            local value = Html.attr(attrs, "value")
            if value and value:match("^%d+$") then return value end
        end
    end
    return html:match("page%s*%(%s*(%d+)%s*,%s*%d+%s*%)")
end

function T.getSeries(ref)
    local slug, chapter = T.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện Mê Truyện Chữ VN không hợp lệ.") end
    local html, err = request("/" .. slug)
    if not html then return nil, err end
    -- A chapter-less URL that does not render its own story page (a redirect to the
    -- homepage, for instance) must not become a bogus series.
    local canonical = meta(html, "property", "og:url") or ""
    if not html:find("bid = '" .. slug .. "'", 1, true) and not canonical:find("/" .. slug, 1, true) then
        return nil, CHANGED
    end
    local title = text(html:match("<h1[^>]*>([%s%S]-)</h1>") or "")
    if title == "" then title = text((meta(html, "property", "og:title") or ""):match("^([^|]+)") or "") end
    if title == "" then return nil, CHANGED end
    local author
    for _, a in ipairs(Html.elements(html, "a")) do
        if Html.attr(a.attrs, "itemprop") == "author" then author = text(a.inner) end
    end
    local cover
    for attrs in html:gmatch("<img([^>]*)>") do
        if Html.attr(attrs, "itemprop") == "image" then cover = Html.attr(attrs, "src") end
    end
    if not cover then cover = meta(html, "property", "og:image") end
    if cover and (cover:lower():match("%.webp") or cover == "") then cover = nil end
    if cover and not cover:match("^https?://") then
        cover = cover:match("^//") and ("https:" .. cover) or (SITE .. "/" .. cover:gsub("^/+", ""))
    end
    -- The synopsis is the itemprop="description" div; the .intro paragraph above it
    -- is the site's own promotional blurb.
    local description = ""
    local scroll = Html.select(html, ".scrolltext")
    if scroll then
        for _, element in ipairs(Html.elements(scroll, "div")) do
            if Html.attr(element.attrs, "itemprop") == "description" then
                description = text(element.inner:gsub("<[Bb][Rr]%s*/?>", " "))
                break
            end
        end
    end
    if #description < 10 then description = text(meta(html, "property", "og:description") or "") end
    if #description < 10 then description = string.format(_("Truyện đọc tại %s."), SITE) end
    local series = { id = slug, source_id = T.id, title = title, url = SITE .. "/" .. slug,
        author = author ~= "" and author or nil, description = description, cover = cover, chapters = {} }
    -- Chapters paginate through /get/listchap/<book id>?page=N; that endpoint is the
    -- only place the whole table of contents exists.
    local book_id = bookId(html)
    local seen, chapters, page = {}, series.chapters, 1
    if book_id then
        while true do
            local body = request("/get/listchap/" .. book_id .. "?page=" .. page)
            if not body then
                if #chapters > 0 then series.truncated = true end
                break
            end
            local added = chaptersOf(body, slug, seen, chapters)
            -- The endpoint answers an out-of-range page with page 1 again, so an
            -- empty page (no new chapter) is the real end of the list.
            if added == 0 then break end
            if page >= MAX_TOC_PAGES or Http.expired() then
                series.truncated = true
                break
            end
            page = page + 1
        end
    end
    if #chapters == 0 then
        -- Fallback when the ajax endpoint is down: the story page still carries its
        -- first page of chapters.
        chaptersOf(html, slug, seen, chapters)
    end
    if #chapters == 0 then return nil, CHANGED end
    local numbered = true
    for _, entry in ipairs(chapters) do
        if not entry.number then numbered = false break end
    end
    -- The list is already in reading order; only sort when every title is numbered,
    -- so "chuong-tiep" chapters keep the position the site gave them.
    if numbered then
        table.sort(chapters, function(a, b)
            if a.number == b.number then return a.id < b.id end
            return a.number < b.number
        end)
    end
    for index, entry in ipairs(chapters) do entry.index = index end
    series.volumes = { { title = _("Chương"), chapters = chapters } }
    return series
end

function T.getChapter(ref)
    local slug, chapter_id = T.parseRef(ref)
    if not chapter_id or type(ref) ~= "table" or ref.series_id ~= slug then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local html, err, code = request("/" .. slug .. "/" .. chapter_id)
    if not html then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local title = text(Html.select(html, ".current-chapter") or ref.title or "")
    if title == "" then title = ref.title or chapter_id end
    local paragraphs = {}
    local total = 0
    local region = Html.select(html, ".truyen")
    if region then
        local plain = text(region:gsub("<[Bb][Rr]%s*/?>", "\n"))
        for line in plain:gmatch("[^\r\n]+") do
            local clean = line:match("^%s*(.-)%s*$")
            if #clean > 1 then
                paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(clean) .. "</p>"
                total = total + #clean
            end
        end
    end
    -- Below the source's own 50-character floor the page is an empty or gated
    -- chapter, not a chapter with one very short paragraph.
    if #paragraphs == 0 or total < 50 then
        -- Newest chapters are behind an ad-gated "enter the code" form: never fetch
        -- around it, report the chapter as locked and keep the download going.
        if hasLock(html) or html:find("formcode", 1, true) then
            return { skipped = _("Chương đã khóa.") }
        end
        return { skipped = _("Chương trống.") }
    end
    return { title = title, html = table.concat(paragraphs, "\n") }
end
return T
