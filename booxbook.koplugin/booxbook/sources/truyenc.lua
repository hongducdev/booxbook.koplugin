local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(s) return s end
local T = { id = "truyenc", name = "TruyenC", kind = "novel",
    capabilities = { search = false, browse = true, login = false, adult = true } }
local SITE = "https://truyenc.com"
local HOSTS = { ["truyenc.com"] = true, ["www.truyenc.com"] = true }
local CHANGED = _("Không đọc được HTML TruyenC; trang có thể đã đổi hoặc yêu cầu xác minh.")

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Nguồn này không có tìm kiếm: dán URL https://truyenc.com/truyen/ten-truyen-123",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
    },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/truyen/") ~= nil
    end,
}

function T.locate(series)
    local id, chapter = T.parseRef(series.url)
    if not id or chapter then return id, nil end
    return id, id
end

-- Series identity used when saving: (story slug, chapter id). A chapter URL only
-- carries the story's base slug, so the remembered series id is matched on its
-- base form instead of on the full ref.
function T.chapterRef(chapter)
    local base, chapter_id, path = T.parseRef(chapter)
    if not base or not path or type(chapter.series_id) ~= "string" then return nil end
    if chapter.series_id:gsub("%-%d+$", "") ~= base then return nil end
    return chapter.series_id, chapter_id
end

local function seriesSlug(value)
    if type(value) ~= "string" then return nil end
    local slug = value:match("^/truyen/([%w%-]+%-%d+)/?$")
    if slug and #slug <= 180 then return slug end
end

-- Series: /truyen/{slug}-{id}; chapter: /truyen/{base-slug}/{chapter-slug} where
-- the chapter slug itself ends in the chapter id (e.g. quyen-5-chuong-4-nguyet-2439).
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
    local book = seriesSlug(ref)
    if book then return book end
    local base, chapter_slug = ref:match("^/truyen/([%w%-]+)/([%w%-]+)/?$")
    if base and chapter_slug and #base <= 180 then
        local chapter_id = chapter_slug:match("%-(%d+)$")
        if chapter_id and #chapter_id <= 12 and tonumber(chapter_id) > 0 then
            return base, chapter_id, "/truyen/" .. base .. "/" .. chapter_slug
        end
    end
end

local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end

local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end

-- Covers on this site are served from i.truyenc.com with literal spaces in the
-- file name, which no HTTP client will send as-is.
local function coverUrl(value)
    if type(value) ~= "string" or value == "" then return nil end
    if value:match("^//") then value = "https:" .. value end
    if not value:match("^https?://") then return nil end
    return (value:gsub(" ", "%%20"))
end

local function request(path, referer)
    local ok, code, body = Http.get(SITE .. path, { referer = referer or (SITE .. "/"),
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then return nil, string.format(_("Không tải được TruyenC (HTTP %s)."), tostring(code)), code end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end

local function hasLock(html)
    return html:find("Mở khóa", 1, true) ~= nil or html:find("Đăng nhập để đọc", 1, true) ~= nil
        or html:find("overlay%-lock") ~= nil
end

-- List cards are <div class="d-flex"> with the cover anchor carrying
-- href/title/alt for the story; the same href is repeated on the "Đọc truyện"
-- button, so one pass per card keeps the first (cover) hit.
local function parseItems(html)
    local items, seen = {}, {}
    for _, card in ipairs(Html.elements(html, ".d-flex")) do
        local slug, title
        for attrs in card.inner:gmatch("<a([^>]*)>") do
            local book, chapter = T.parseRef(Html.decode(Html.attr(attrs, "href") or ""))
            if book and not chapter then
                slug = book
                title = text(Html.attr(attrs, "title") or "")
                break
            end
        end
        if slug and not seen[slug] then
            local image_tag = card.inner:match("<img[^>]*>")
            local image = image_tag and Html.attr(image_tag, "src")
            if not title or title == "" then title = text(Html.select(card.inner, "h2")) end
            if title == "" and image_tag then title = text(Html.attr(image_tag, "alt") or "") end
            if title ~= "" then
                seen[slug] = true
                items[#items + 1] = { ref = "/truyen/" .. slug .. "/", url = SITE .. "/truyen/" .. slug,
                    title = title, name = title, cover = coverUrl(image) }
            end
        end
    end
    return items
end

-- Pagination is "?page=N" with the last page announced by title="Trang cuối".
local function hasMore(html, page)
    local want = tostring(page + 1)
    if html:find('title="Trang ' .. want .. '"', 1, true) then return true end
    for value in html:gmatch("[?&]page=(%d+)") do
        if value == want then return true end
    end
end

local GENRES = {}
local function genre(key, name, adult)
    local entry = { key = key, name = name, adult = adult or nil }
    GENRES[key] = entry
    return entry
end

-- Key = the site's /{slug}, so browse() needs no extra mapping. The 18+ sections
-- stay hidden until Settings.adultContent() is on (checked again in browse).
T.genres = {
    genre("tim-truyen-ma", "Truyện ma"),
    genre("tim-truyen-18", "Truyện 18+", true),
    genre("tim-truyen-cuoi", "Truyện cười"),
    genre("tim-truyen-audio", "Truyện audio"),
    genre("tim-truyen-chua-phan-loai", "Chưa phân loại"),
    genre("truyen-cuoi-vova", "Truyện cười vova"),
    genre("truyen-cuoi-18", "Truyện cười 18+", true),
    genre("truyen-cuoi-tinh-yeu", "Truyện cười tình yêu"),
    genre("truyen-trang-quynh", "Truyện trạng Quỳnh"),
    genre("truyen-cuoi-dan-gian", "Truyện cười dân gian"),
    genre("truyen-cuoi-quoc-te", "Truyên cười quốc tế"),
    genre("truyen-cuoi-khac", "Truyện cười khác"),
    genre("truyen-ma-viet-nam", "Truyện ma Việt Nam"),
    genre("truyen-ma-trung-quoc", "Truyện ma Trung Quốc"),
    genre("truyen-ma-ngan", "Truyện ma ngắn"),
    genre("truyen-ma-dai-ky", "Truyện ma dài kỳ"),
    genre("truyen-ma-hay", "Truyện ma hay"),
    genre("truyen-ma-co-that", "Truyện ma có thật"),
    genre("truyen-ma-nguyen-ngoc-ngan", "Truyện ma Nguyễn Ngọc Ngạn"),
    genre("truyen-kinh-di", "Truyện kinh dị"),
    genre("truyen-ma-audio", "Truyện ma audio"),
    genre("truyen-audio-kiem-hiep", "Truyện audio kiếm hiệp"),
    genre("truyen-audio-ngon-tinh", "Truyện audio ngôn tình"),
    genre("truyen-dem-khuya", "Đọc truyện đêm khuya"),
    genre("truyen-audio-trinh-tham", "Truyện audio trinh thám"),
    genre("truyen-audio-ngan", "Truyện audio ngắn"),
    genre("truyen-sac-hiep", "Truyện sắc hiệp", true),
    genre("truyen-sex", "Truyện Sex", true),
    genre("truyen-sex-audio", "Truyện Sex Audio", true),
    genre("truyen-voz", "Truyện Voz"),
    genre("truyen-co-that", "Truyện có thật"),
    genre("truyen-dam-hiep", "Truyện dâm hiệp", true),
    genre("truyen-kiem-hiep", "Truyện kiếm hiệp"),
    genre("truyen-h", "Truyện H", true),
}

function T.browse(kind, page)
    local selected = GENRES[kind]
    local path
    if selected then
        if selected.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
        path = "/" .. selected.key
    elseif kind == nil or kind == "latest" then
        path = "/"
    else
        return nil, _("Kiểu danh sách không hợp lệ.")
    end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request(page > 1 and (path .. "?page=" .. page) or path)
    if not html then return nil, err end
    local items = parseItems(html)
    if #items == 0 and page == 1 then return nil, CHANGED end
    return { items = items, has_more = hasMore(html, page) }
end

-- The site publishes no keyword search: /tim-kiem/* answers "Nội dung tìm kiếm
-- không tồn tại" and its result list is built in the browser. Readers open a
-- story by pasting its URL instead of silently getting an empty grid.
function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    return nil, _("TruyenC không hỗ trợ tìm kiếm theo từ khóa; hãy dán URL truyện.")
end

local function seriesInfo(html, slug)
    local title = text(Html.select(html, "h1"))
    if title == "" then return nil end
    local series = { id = slug, source_id = T.id, title = title, url = SITE .. "/truyen/" .. slug,
        chapters = {} }
    local author = html:match("Tác giả:%s*<b[^>]*>([^<]*)</b>")
    if author then series.author = text(author) end
    local description = text(html:match('<meta property="og:description" content="([^"]*)"') or "")
    if description == "" then
        description = text(html:match('<div class="d%-none d%-sm%-block">([%s%S]-)<div class="divider') or "")
    end
    if description ~= "" then series.description = description end
    series.cover = coverUrl(html:match('<img[^>]*src="(https?://i%.truyenc%.com/[^"]+)"'))
    local tags = {}
    for _, anchor in ipairs(Html.elements(Html.select(html, ".color-highlight") or "", "a")) do
        local href = Html.attr(anchor.attrs, "href") or ""
        local entry = GENRES[href:match("^https?://truyenc%.com/([%w%-]+)$")]
        local classes = Html.attr(anchor.attrs, "class") or ""
        if entry and classes:find("badge") and (not entry.adult or Settings.adultContent()) then
            tags[#tags + 1] = text(anchor.inner)
        end
    end
    if #tags > 0 then series.tags = tags end
    return series
end

function T.getSeries(ref)
    local slug, chapter = T.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện TruyenC không hợp lệ.") end
    local path = "/truyen/" .. slug
    local html, err = request(path, SITE .. "/")
    if not html then return nil, err end
    local series = seriesInfo(html, slug)
    if not series then return nil, CHANGED end
    local base = slug:gsub("%-%d+$", "")
    local chapters, seen = {}, {}
    for _, anchor in ipairs(Html.elements(html, ".story-chap-item")) do
        local book, chapter_id, chapter_path = T.parseRef(Html.decode(Html.attr(anchor.attrs, "href") or ""))
        if book == base and chapter_id and not seen[chapter_id] then
            seen[chapter_id] = true
            local title = text(Html.attr(anchor.attrs, "title") or "")
            if title == "" then title = text(anchor.inner) end
            chapters[#chapters + 1] = { id = chapter_id, series_id = slug, url = SITE .. chapter_path,
                title = title ~= "" and title or string.format(_("Chương %s"), chapter_id) }
        end
    end
    if #chapters == 0 then
        return nil, _("Truyện này không có chương chữ (có thể chỉ có bản audio).")
    end
    table.sort(chapters, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    for i, item in ipairs(chapters) do item.index = i end
    series.chapters = chapters
    series.volumes = { { title = _("Chương"), chapters = chapters } }
    -- The page announces its newest chapter: when the table of contents does not
    -- reach it, the list is partial and the caller should know.
    local _, latest = T.parseRef(Html.decode(html:match('Mới nhất:%s*<a[^>]*href="([^"]+)"') or ""))
    if latest and not seen[latest] then series.truncated = true end
    return series
end

function T.getChapter(ref)
    local base, chapter_id, path = T.parseRef(ref)
    if not base or not chapter_id or not path or type(ref) ~= "table" then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    local series_id = ref.series_id
    if type(series_id) ~= "string" or series_id:gsub("%-%d+$", "") ~= base then
        return nil, _("Đường dẫn chương không thuộc truyện này.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local html, err, code = request(path, SITE .. "/truyen/" .. series_id)
    if not html then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local content = Html.select(html, ".story-content")
    if not content or text(content) == "" then
        if hasLock(html) then return { skipped = _("Chương đã khóa.") } end
        return { skipped = _("Chương trống.") }
    end
    if hasLock(content) and (content:find("<form") or content:find("<button")) then
        return { skipped = _("Chương đã khóa.") }
    end
    content = content:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[Pp]>", "\n")
    local paragraphs = {}
    for line in content:gmatch("[^\r\n]+") do
        line = text(line)
        if line ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    local title = type(ref.title) == "string" and ref.title or ""
    if title == "" then title = text(html:match("<h1[^>]*>([%s%S]-)</h1>") or "") end
    return { title = title, html = table.concat(paragraphs, "\n") }
end

return T
