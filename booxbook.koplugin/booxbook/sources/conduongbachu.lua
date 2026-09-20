local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local Library = require("booxbook.library")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local T = { id = "conduongbachu", name = "Con Đường Bá Chủ", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://conduongbachu.com"
local AUTHOR = "Akay Hau"
-- Bounded on purpose: the WordPress REST index hands out one page per request and
-- the site has thousands of chapters, so stop at the page cap or when the action's
-- time budget is gone instead of holding the reader.
local MAX_TOC_PAGES = 60
local REST_PAGE_SIZE = 100
local CHANGED = _("Không đọc được dữ liệu Con Đường Bá Chủ; trang có thể đã đổi.")
local HOSTS = { ["conduongbachu.com"] = true, ["www.conduongbachu.com"] = true }
local SPINOFF_COVER = SITE .. "/wp-content/uploads/2025/04/conduongbachu-ngoai-truyen-268x400.jpg"

-- One WordPress install publishes the main story plus three spin-offs. Each one
-- paginates its own chapter category through the REST API, and every chapter link
-- is a plain top-level post slug (/chuong-…), so a chapter URL alone says nothing
-- about which story it belongs to.
local STORIES = {
    { id = "chapter-truyen", category = 3, title = "Con Đường Bá Chủ (Chính Truyện)",
        path = "/", main = true, aliases = { "/chapter-truyen/" } },
    { id = "ngoai-truyen", category = 12, title = "Ngoại Truyện: Bất Hủ Thần Chiến",
        path = "/ngoai-truyen/", cover = SPINOFF_COVER },
    { id = "ngoai-truyen-van-dao-than-chu", category = 14, title = "Ngoại Truyện: Vạn Đạo Thần Chủ",
        path = "/ngoai-truyen-van-dao-than-chu/", cover = SPINOFF_COVER },
    { id = "ngoai-truyen-chua-te-chi-lo", category = 15, title = "Ngoại Truyện: Chúa Tể Chi Lộ",
        path = "/ngoai-truyen-chua-te-chi-lo/", cover = SPINOFF_COVER },
}
local BY_ID, BY_PATH = {}, {}
local function normalizePath(value)
    return (value or ""):gsub("/+$", "")
end
for _, story in ipairs(STORIES) do
    BY_ID[story.id] = story
    BY_PATH[normalizePath(story.path)] = story
    for _, alias in ipairs(story.aliases or {}) do BY_PATH[normalizePath(alias)] = story end
end

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://conduongbachu.com/chuong-1-…",
    browse = { { text = "Truyện & Ngoại truyện", kind = "latest" } },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/[%w%-]*/?$") ~= nil
    end,
}

function T.locate(series)
    local id, chapter = T.parseRef(series and series.url or series)
    if not id or chapter then return id, nil end
    return id, id
end

-- Chapter identity used when saving: (series_id, chapter_id). The chapter object
-- carries the story it was listed under; parseRef can only recover the main one,
-- because every chapter lives on a top-level slug.
function T.chapterRef(chapter)
    local story_id, chapter_id = T.parseRef(chapter)
    if type(chapter) == "table" and BY_ID[chapter.series_id] then story_id = chapter.series_id end
    return story_id, chapter_id
end

local function text(html)
    return Html.decode((html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$") or ""
end
-- Non-breaking spaces are invisible but not whitespace to Lua, and the theme uses
-- them as filler lines.
local function lineText(html)
    return (text(html):gsub("&nbsp;", " "):gsub("\194\160", " ")):match("^%s*(.-)%s*$") or ""
end
local function header(headers, name)
    if type(headers) ~= "table" then return nil end
    local want = name:lower()
    for key, value in pairs(headers) do
        if tostring(key):lower() == want then
            if type(value) == "table" then return value[1] end
            return value
        end
    end
end
local function hasLock(body)
    return body and (body:find("Mở khóa", 1, true) or body:find("mở khóa", 1, true)
        or body:find("Vui lòng đăng nhập", 1, true))
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
    ref = ref:match("^[^?#]+") or ""
    if ref == "" or ref == "/" then return "chapter-truyen" end -- the site root is the main story
    local clean = ref:gsub("/+$", "")
    local story = BY_PATH[clean]
    if story then return story.id end
    -- Chapter posts: /chuong-12-ten-chuong/ and the legacy /3399-vo-de/ shape.
    local slug = clean:match("^/([%w%-]+)$")
    if slug and #slug >= 3 and #slug <= 180
        and (slug:match("^chuong%-%d[%w%-]*$") or slug:match("^%d+%-%a[%w%-]*$")) then
        return "chapter-truyen", slug, "/" .. slug .. "/"
    end
end

local function request(path)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được Con Đường Bá Chủ (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end

local function item(story)
    return { ref = story.path, url = SITE .. story.path, title = story.title,
        name = story.title, cover = story.cover }
end

local GENRES = {}
T.genres = {}
for _, story in ipairs(STORIES) do
    local entry = { key = story.id, name = story.title }
    GENRES[story.id] = entry
    T.genres[#T.genres + 1] = entry
end

function T.browse(kind, page)
    if kind ~= nil and kind ~= "latest" and not GENRES[kind] then
        return nil, _("Kiểu danh sách không hợp lệ.")
    end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 100 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    -- Four series on one shelf: there is no second page to fetch.
    if page > 1 then return { items = {}, has_more = false } end
    local items = {}
    if GENRES[kind] then
        items[1] = item(BY_ID[kind])
    else
        for _, story in ipairs(STORIES) do items[#items + 1] = item(story) end
    end
    return { items = items, has_more = false }
end

-- The whole catalogue is these four series, so the query is matched locally with
-- accent folding (the site search page only ever re-lists the same posts).
local ALIASES = { "con duong ba chu", "ba chu", "ngoai truyen" }
function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 100 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local wanted = Library.fold(query)
    local items = {}
    if page == 1 then
        for _, story in ipairs(STORIES) do
            local matches = Library.fold(story.title):find(wanted, 1, true) ~= nil
            for _, alias in ipairs(ALIASES) do
                if wanted:find(alias, 1, true) then matches = true end
            end
            if matches then items[#items + 1] = item(story) end
        end
    end
    return { items = items, has_more = false }
end

-- WordPress REST index: _fields keeps the body small, the total page count arrives
-- in the headers. The endpoint answers JSON, so the body is sanitized like any other
-- fetch and the decoded value is type-checked as well: an HTML error page fails both.
local function restPage(config, page)
    local url = SITE .. "/wp-json/wp/v2/posts?categories=" .. config.category
        .. "&per_page=" .. REST_PAGE_SIZE .. "&_fields=link,title&page=" .. page
        .. "&order=asc&orderby=date"
    local ok, code, body, headers = Http.get(url, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được mục lục Con Đường Bá Chủ (HTTP %s)."), tostring(code))
    end
    if type(body) ~= "string" then return nil, CHANGED end
    local loaded, Json = pcall(require, "json")
    if not loaded or type(Json) ~= "table" or type(Json.decode) ~= "function" then
        return nil, _("Không có thư viện JSON của KOReader.")
    end
    local decoded, posts = pcall(Json.decode, Html.stripDangerous(body))
    if not decoded or type(posts) ~= "table" then return nil, CHANGED end
    return { posts = posts, total = tonumber(header(headers, "x-wp-total")),
        pages = tonumber(header(headers, "x-wp-totalpages")) }
end

local function chapterOf(post, story_id)
    if type(post) ~= "table" or type(post.link) ~= "string" then return nil end
    local rendered = type(post.title) == "table" and post.title.rendered or nil
    local title = text(rendered)
    if title == "" then return nil end
    local link = post.link:match("^[^?#]+") or post.link
    local slug = link:gsub("/+$", ""):match("([^/]+)$")
    if not slug or #slug > 180 then return nil end
    -- Skip non-chapter posts such as "Bầu chọn ngoại truyện", while keeping legacy
    -- numeric slugs like /3399-vo-de/ titled "3399: VÔ ĐỀ.".
    if not (title:find("Chương", 1, true) or title:find("CHƯƠNG", 1, true)
        or link:find("/chuong-", 1, true) or title:match("^%s*%d+%s*[:%-%.]")) then
        return nil
    end
    local number = tonumber(title:match("Chương%s*(%d+)")) or tonumber(title:match("CHƯƠNG%s*(%d+)"))
        or tonumber(link:match("/chuong%-(%d+)")) or tonumber(title:match("^%s*(%d+)"))
    return { id = slug, series_id = story_id, url = SITE .. "/" .. slug .. "/",
        title = title, number = number }
end

function T.getSeries(ref)
    local story_id, chapter = T.parseRef(ref)
    if not story_id or chapter or not BY_ID[story_id] then
        return nil, _("URL truyện Con Đường Bá Chủ không hợp lệ.")
    end
    local config = BY_ID[story_id]
    local html, err = request(config.path)
    if not html then return nil, err end
    local description = text(html:match('<meta[^>]+name=["\']description["\'][^>]+content=["\']([^"\']*)') or "")
    local author = description:match("[Tt]ác giả%s+([^%.|,]+)")
    local series = { id = config.id, source_id = T.id, title = config.title,
        url = SITE .. config.path, cover = config.cover, author = author or AUTHOR,
        description = description ~= "" and description
            or string.format(_("Bộ truyện %s."), config.title), chapters = {} }
    local page, seen, chapters, raw, total, pages = 1, {}, {}, 0, nil, nil
    while true do
        local data, page_err = restPage(config, page)
        if not data then
            -- One broken page must not throw away the chapters already read.
            if #chapters == 0 then return nil, page_err end
            series.truncated = true
            break
        end
        total, pages = total or data.total, data.pages or pages
        for _, post in ipairs(data.posts) do
            raw = raw + 1
            local entry = chapterOf(post, config.id)
            if entry and not seen[entry.id] then
                seen[entry.id] = true
                chapters[#chapters + 1] = entry
            end
        end
        if pages and page >= pages then break end
        if not pages and #data.posts < REST_PAGE_SIZE then break end
        if page >= MAX_TOC_PAGES or Http.expired() then
            series.truncated = true
            break
        end
        page = page + 1
    end
    if not series.truncated and total and raw ~= total then
        return nil, string.format(_("Mục lục chưa đủ: nhận %d/%d bài viết."), raw, total)
    end
    if not series.truncated and config.main and total and #chapters ~= total then
        return nil, string.format(_("Mục lục chính truyện thiếu: nhận %d/%d chương."), #chapters, total)
    end
    if #chapters == 0 then return nil, CHANGED end
    table.sort(chapters, function(a, b)
        if (a.number or math.huge) == (b.number or math.huge) then return a.id < b.id end
        return (a.number or math.huge) < (b.number or math.huge)
    end)
    for index, entry in ipairs(chapters) do entry.index = index end
    series.chapters = chapters
    series.volumes = { { title = _("Chương"), chapters = chapters } }
    return series
end

function T.getChapter(ref)
    local story_id, chapter_id = T.parseRef(ref)
    if not chapter_id or type(ref) ~= "table" or not BY_ID[ref.series_id or story_id] then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local html, err, code = request("/" .. chapter_id .. "/")
    if not html then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local title = text(html:match('<h1[^>]-class=["\'][^"\']*entry%-title[^"\']*["\'][^>]*>([%s%S]-)</h1>')
        or html:match("<h1[^>]*>([%s%S]-)</h1>") or ref.title or "")
    if title == "" then title = ref.title or chapter_id end
    local region = Html.select(html, ".entry-content")
    -- A named lock control inside the body means the teaser is not the chapter, even
    -- when a paragraph or two came along with it.
    if region and hasLock(region) and (region:find("<button", 1, true) or region:find("<form", 1, true)) then
        return { skipped = _("Chương đã khóa.") }
    end
    local paragraphs = {}
    if region then
        for attrs, raw in region:gmatch("<p%f[%W]([^>]*)>([%s%S]-)</p>") do
            local line = lineText(raw)
            -- post-tts is the text-to-speech widget; the other two are the site's
            -- own invitation and promo line inside the article body.
            local noise = attrs:find("post-tts", 1, true)
                or line:find("Nếu muốn tìm chương khác", 1, true)
                or line:find("conduongbachu.com", 1, true)
            if not noise and #line > 1 then
                paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>"
            end
        end
    end
    if #paragraphs == 0 then
        if hasLock(html) then return { skipped = _("Chương đã khóa.") } end
        return { skipped = _("Chương trống.") }
    end
    return { title = title, html = table.concat(paragraphs, "\n") }
end
return T
