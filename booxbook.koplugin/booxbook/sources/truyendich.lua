local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(s) return s end
local T = { id = "truyendich", name = "Truyendich", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
-- The site has moved twice (.ai -> .fit -> .space). Refs copied from an older
-- domain must still resolve, so both the fetch base and parseRef know them.
local SITE = "https://truyendich.space"
local HOSTS = {
    ["truyendich.space"] = true, ["www.truyendich.space"] = true,
    ["truyendich.ai"] = true, ["www.truyendich.ai"] = true,
    ["truyendich.fit"] = true, ["www.truyendich.fit"] = true,
}
-- The table of contents comes from the site's own JSON endpoint at 200 chapters
-- a page; the reader must not be able to walk that forever.
local MAX_TOC_PAGES = 60
local TOC_PAGE_SIZE = 200
local SEARCH_PAGE_SIZE = 20
-- A list page renders ~24 cards on the last page of the catalogue; fewer than
-- this means we are at the end and the grid must not offer a next page.
local LIST_MIN_ITEMS = 20
local CHANGED = _("Không đọc được Truyendich; trang có thể đã đổi hoặc yêu cầu xác minh.")

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://truyendich.space/doc-truyen/ten-truyen",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Truyện hot", kind = "popular" },
        { text = "Truyện full", kind = "full" },
    },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/doc%-truyen/") ~= nil
    end,
}

function T.locate(series)
    local id, chapter = T.parseRef(series.url)
    if not id or chapter then return id, nil end
    return id, id
end

-- Chapter identity used when saving: (series_slug, chapter_number).
function T.chapterRef(chapter)
    local series_id, chapter_id, path = T.parseRef(chapter)
    if chapter.series_id ~= series_id or not path then series_id = nil end
    return series_id, chapter_id
end

local function slug(value)
    if type(value) ~= "string" or #value < 1 or #value > 180 then return nil end
    return value:match("^[%w%-]+$") and value or nil
end

local function seriesSlug(value)
    if type(value) ~= "string" then return nil end
    return slug(value:match("^/doc%-truyen/([^/?#]+)/?$"))
end

-- Series: /doc-truyen/{slug}; chapter: /doc-truyen/{slug}/chuong-{n}, with the
-- optional "cv" (convert) edition prefix the site's own chapter links carry.
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
    -- The site's own "convert" edition link is /doc-truyen/cv/{slug}/chuong-{n}.
    local edition, base, chapter = ref:match("^/doc%-truyen/(cv/)([%w%-]+)/chuong%-(%d+)/?$")
    if not base then
        base, chapter = ref:match("^/doc%-truyen/([%w%-]+)/chuong%-(%d+)/?$")
    end
    if base and chapter and #base <= 180 and #chapter <= 12 and tonumber(chapter) > 0 then
        return base, chapter, "/doc-truyen/" .. (edition or "") .. base .. "/chuong-" .. chapter
    end
end

local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end

local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end

local function absolute(url)
    if type(url) ~= "string" or url == "" then return nil end
    if url:match("^https?://") then return url end
    if url:match("^//") then return "https:" .. url end
    if url:match("^/") then return SITE .. url end
end

local function json()
    local loaded, Json = pcall(require, "json")
    if not loaded then return nil, _("Không có thư viện JSON của KOReader.") end
    return Json
end

local function request(path, referer, accept_json)
    local options = { referer = referer or (SITE .. "/"),
        delay_ms = math.max(1600, Settings.delayMs()) }
    if accept_json then options.headers = { Accept = "application/json" } end
    local ok, code, body = Http.get(SITE .. path, options)
    if not ok then
        return nil, string.format(_("Không tải được Truyendich (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end

local function requestJson(path, referer)
    local body, err, code = request(path, referer, true)
    if not body then return nil, err, code end
    local Json, json_err = json()
    if not Json then return nil, json_err end
    local decoded, data = pcall(Json.decode, body)
    if not decoded or type(data) ~= "table" then return nil, CHANGED end
    return data
end

local function hasLock(html)
    return html:find("overlay%-lock") ~= nil or html:find("Mở khóa", 1, true) ~= nil
end

local function lockedChapter(status)
    return status == "LOCKED" or status == "VIP" or status == "PAYWALL"
end

local function chapterTitle(number, name)
    name = type(name) == "string" and text(name) or ""
    if name == "" then return string.format(_("Chương %s"), number) end
    if name:match("^Chương%s") then return name end
    return string.format(_("Chương %s: %s"), number, name)
end

-- Cards are <a href="/doc-truyen/{slug}"> around the cover; a second anchor with
-- the same href carries the <h3> title on list pages. One pass keeps the first
-- (cover) anchor, whose alt text is the title on those pages.
local function parseItems(html)
    -- Featured sections above the grid repeat on every page, so only the grid
    -- that its own heading marks is paged through.
    local marker = html:find('id="list%-heading"') or html:find('id="list%-cat%-heading"')
    if marker then html = html:sub(marker) end
    local items, seen = {}, {}
    for attrs, inner in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local book, chapter = T.parseRef(Html.decode(Html.attr(attrs, "href") or ""))
        if book and not chapter and not seen[book] then
            local image = inner:match("<img[^>]*>")
            local cover = image and absolute(Html.attr(image, "src"))
            local title = text(Html.select(inner, "h3"))
            if title == "" then title = text(Html.attr(attrs, "title") or "") end
            if title == "" and image then title = text(Html.attr(image, "alt") or "") end
            title = title:gsub("^Ảnh bìa truyện%s*", "")
            if title ~= "" then
                seen[book] = true
                items[#items + 1] = { ref = "/doc-truyen/" .. book .. "/",
                    url = SITE .. "/doc-truyen/" .. book, title = title, name = title, cover = cover }
            end
        end
    end
    return items
end

local BROWSE = {
    latest = "/danh-sach/truyen-moi",
    popular = "/danh-sach/truyen-hot",
    full = "/danh-sach/truyen-full",
}
local GENRES = {}
local function genre(key, name, adult)
    local entry = { key = key, name = name, adult = adult or nil }
    GENRES[key] = entry
    return entry
end

-- Key = the site's /the-loai/ slug, so browse() needs no extra mapping. The site
-- has no adult section, so no entry is flagged and no reader gate is needed.
T.genres = {
    genre("tien-hiep", "Tiên Hiệp"),
    genre("kiem-hiep", "Kiếm Hiệp"),
    genre("ngon-tinh", "Ngôn Tình"),
    genre("do-thi", "Đô Thị"),
    genre("huyen-huyen", "Huyền Huyễn"),
    genre("vong-du", "Võng Du"),
    genre("khoa-huyen", "Khoa Huyễn"),
    genre("he-thong", "Hệ Thống"),
    genre("di-gioi", "Dị Giới"),
    genre("lich-su", "Lịch Sử"),
    genre("quan-su", "Quân Sự"),
    genre("trinh-tham", "Trinh Thám"),
    genre("tham-hiem", "Thám Hiểm"),
    genre("linh-di", "Linh Dị"),
    genre("mat-the", "Mạt Thế"),
    genre("xuyen-nhanh", "Xuyên Nhanh"),
    genre("nu-cuong", "Nữ Cường"),
    genre("cung-dau", "Cung Đấu"),
    genre("dam-my", "Đam Mỹ"),
    genre("bach-hop", "Bách Hợp"),
}

local function listPath(kind)
    local selected = GENRES[kind]
    if selected then
        if selected.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
        return "/the-loai/" .. selected.key
    end
    local path = BROWSE[kind or "latest"]
    if not path then return nil, _("Kiểu danh sách không hợp lệ.") end
    return path
end

function T.browse(kind, page)
    local path, invalid = listPath(kind)
    if not path then return nil, invalid end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request(page > 1 and (path .. "?page=" .. page) or path)
    if not html then return nil, err end
    local items = parseItems(html)
    if #items == 0 and page == 1 then return nil, CHANGED end
    return { items = items, has_more = #items >= LIST_MIN_ITEMS }
end

function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local data, err = requestJson("/api/novels/search?q=" .. encode(query) .. "&page=" .. page
        .. "&size=" .. SEARCH_PAGE_SIZE, SITE .. "/tim-kiem")
    if not data then return nil, err end
    local items = {}
    for _, book in ipairs(type(data.items) == "table" and data.items or {}) do
        local slug_id = slug(book.slug)
        if not slug_id or type(book.title) ~= "string" then return nil, CHANGED end
        items[#items + 1] = { ref = "/doc-truyen/" .. slug_id .. "/", title = book.title,
            name = book.title, url = SITE .. "/doc-truyen/" .. slug_id,
            cover = absolute(book.image_url) }
    end
    return { items = items, has_more = (tonumber(data.total) or 0) > page * SEARCH_PAGE_SIZE }
end

-- Fallback for the table of contents when the JSON endpoint is unreachable: the
-- page renders its first 50 chapters and the newest ones, so the list is short
-- but never empty, and it is marked truncated for the caller.
local function htmlChapters(html, series_id)
    local base = series_id:gsub("%-%d+$", "")
    local chapters, seen = {}, {}
    for attrs, inner in html:gmatch("<a([^>]*)>([%s%S]-)</a>") do
        local book, number, path = T.parseRef(Html.decode(Html.attr(attrs, "href") or ""))
        if book == base and number and not seen[number] then
            seen[number] = true
            local title = text(inner):gsub("^%d+%s*", "")
            chapters[#chapters + 1] = { id = number, series_id = series_id, url = SITE .. path,
                title = title ~= "" and title or string.format(_("Chương %s"), number) }
        end
    end
    return chapters
end

local function seriesInfo(html, slug_id)
    local series = { id = slug_id, source_id = T.id, url = SITE .. "/doc-truyen/" .. slug_id, chapters = {} }
    series.title = text(Html.select(html, "h1"))
    if series.title == "" then
        series.title = text(html:match('<meta property="og:title" content="([^"]*)"') or "")
    end
    local author = html:match("Tác giả</span></div><p[^>]*>([^<]*)</p>")
    if author then series.author = text(author) end
    local description = text(Html.select(html, ".prose"))
    if description == "" then
        description = text(html:match('<meta property="og:description" content="([^"]*)"') or "")
    end
    if description ~= "" then series.description = description end
    local image = html:match("<img[^>]*src=\"([^\"]*/anh%-bia/[^\"]*)\"")
    if image then series.cover = absolute(image) end
    local tags, seen_tags = {}, {}
    for key, name in html:gmatch('<a[^>]*href="/the%-loai/([%w%-]+)"[^>]*>([^<]*)</a>') do
        local entry = GENRES[key]
        if entry and (not entry.adult or Settings.adultContent()) and not seen_tags[key] then
            seen_tags[key] = true
            tags[#tags + 1] = text(name)
        end
    end
    if #tags > 0 then series.tags = tags end
    return series
end

function T.getSeries(ref)
    local slug_id, chapter = T.parseRef(ref)
    if not slug_id or chapter then return nil, _("URL truyện Truyendich không hợp lệ.") end
    local path = "/doc-truyen/" .. slug_id
    local html, err = request(path)
    if not html then return nil, err end
    local series = seriesInfo(html, slug_id)
    if series.title == "" then return nil, CHANGED end
    local chapters, seen, page = {}, {}, 1
    while true do
        local data, api_err = requestJson("/api/novels/" .. slug_id .. "/chapters?page=" .. page
            .. "&size=" .. TOC_PAGE_SIZE, SITE .. path)
        if not data then
            if page > 1 then
                -- Keep what was read: a partial table of contents still downloads.
                series.truncated = true
                break
            end
            chapters = htmlChapters(html, slug_id)
            if #chapters == 0 then return nil, api_err or CHANGED end
            series.truncated = true
            break
        end
        if type(data.items) ~= "table" then return nil, CHANGED end
        local added = 0
        for _, item in ipairs(data.items) do
            local number = item.chapter_number
            local cid = (type(number) == "number" and number > 0 and number % 1 == 0) and tostring(number) or nil
            if not cid or #cid > 12 then return nil, CHANGED end
            if not seen[cid] then
                seen[cid], added = true, added + 1
                chapters[#chapters + 1] = { id = cid, series_id = slug_id,
                    url = SITE .. path .. "/chuong-" .. cid,
                    title = chapterTitle(cid, item.title), locked = lockedChapter(item.status) }
            end
        end
        local total = tonumber(data.total)
        if #data.items == 0 or (total and page * TOC_PAGE_SIZE >= total) then break end
        if added == 0 then return nil, CHANGED end
        if page >= MAX_TOC_PAGES or Http.expired() then
            series.truncated = true
            break
        end
        page = page + 1
    end
    if #chapters == 0 then return nil, CHANGED end
    table.sort(chapters, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    for i, item in ipairs(chapters) do item.index = i end
    series.chapters = chapters
    series.volumes = { { title = _("Chương"), chapters = chapters } }
    return series
end

function T.getChapter(ref)
    local slug_id, number, path = T.parseRef(ref)
    if not slug_id or not number or not path or type(ref) ~= "table" or ref.series_id ~= slug_id then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local html, err, code = request(path, SITE .. "/doc-truyen/" .. slug_id)
    if not html then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local content = Html.select(html, "#original-content-tab") or Html.select(html, ".prose-novel")
    if not content or text(content) == "" then
        if hasLock(html) then return { skipped = _("Chương đã khóa.") } end
        return { skipped = _("Chương trống hoặc chưa được dịch.") }
    end
    content = content:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[Pp]>", "\n")
    local paragraphs = {}
    for line in content:gmatch("[^\r\n]+") do
        line = text(line)
        if line ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    return { title = ref.title, html = table.concat(paragraphs, "\n") }
end

return T
