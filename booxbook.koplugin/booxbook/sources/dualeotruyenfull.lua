local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end

local T = { id = "dualeotruyenfull", name = "DualeoTruyenFull", kind = "novel",
    -- The site's own description is "truyện 18+"; explicit tags are gated below.
    capabilities = { search = true, browse = true, login = false, adult = true } }
local SITE = "https://dualeotruyenfull.net"
-- Bounded on purpose: a site that keeps handing out "next page" links must not
-- hold the reader here, and the action's time budget is checked every round.
local MAX_TOC_PAGES = 60
local CHANGED = _("Không đọc được HTML DualeoTruyenFull; trang có thể đã đổi hoặc yêu cầu xác minh.")

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://dualeotruyenfull.net/doc-truyen/ten-truyen/",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Xếp hạng", kind = "popular" },
        { text = "Đã hoàn thành", kind = "completed" },
    },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/doc%-truyen/[%w_%-]+/?$") ~= nil
    end,
}

function T.locate(series)
    local id, chapter = T.parseRef(series.url)
    if not id or chapter then return id, nil end
    return id, id
end

-- Chapter identity used when saving: (series_id, chapter_id).
function T.chapterRef(chapter)
    local series_id, chapter_id = T.parseRef(chapter)
    if chapter.series_id ~= series_id then series_id = nil end
    return series_id, chapter_id
end

function T.parseRef(ref)
    if type(ref) == "table" then ref = ref.url or ref.ref end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if host ~= "dualeotruyenfull.net" and host ~= "www.dualeotruyenfull.net" then return nil end
        ref = path
    end
    ref = ref:match("^[^?#]+") or ""
    local slug = ref:match("^/doc%-truyen/([%w_%-]+)/?$")
    if slug and #slug <= 180 then return slug end
    local book, chapter = ref:match("^/doc%-truyen/([%w_%-]+)/chuong%-(%d+)/?$")
    if book and #book <= 180 and #chapter <= 12 and tonumber(chapter) > 0 then return book, chapter, ref end
end

local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end
local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end
-- The same 20-story widgets repeat in <aside id="im-sidebar">. Removing that
-- block (search pages put it above the results, listings below) keeps a listing to
-- the cards the page really shows.
local function mainHtml(html)
    local start = html:find('<aside id="im-sidebar"', 1, true)
    if not start then return html end
    local close = html:find("</aside>", start, true)
    if not close then return html:sub(1, start - 1) end
    return html:sub(1, start - 1) .. html:sub(close + 8)
end
local function request(path)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then return nil, string.format(_("Không tải được DualeoTruyenFull (HTTP %s)."), tostring(code)), code end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end
-- WordPress pagination: the last page still renders a disabled "Trang sau", so
-- only a real link to the next page counts.
local function hasMore(html, page)
    return html:find("/page/" .. (page + 1) .. "/", 1, true) ~= nil
end

-- The site injects hidden SEO <a> tags that are never closed, so extracting
-- elements over anchors swallows the rest of the page. Cards are sliced on their
-- own start markers and read with flat patterns instead.
local CARD_MARKERS = { '<div class="manga-item-grid', '<div class="manga-item-details',
    '<article class="uk-grid-small', '<div class="story-cover-wrap' }

local function slices(html, markers)
    local marks = {}
    for _, marker in ipairs(markers) do
        local pos = 1
        while true do
            local at = html:find(marker, pos, true)
            if not at then break end
            marks[#marks + 1] = at
            pos = at + #marker
        end
    end
    table.sort(marks)
    local blocks = {}
    for i, at in ipairs(marks) do
        blocks[#blocks + 1] = html:sub(at, (marks[i + 1] or (#html + 1)) - 1)
    end
    return blocks
end

local function seriesRef(block)
    for href in block:gmatch('href="([^"]+)"') do
        local slug, chapter = T.parseRef(Html.decode(href))
        if slug and not chapter then return slug, "/doc-truyen/" .. slug .. "/" end
    end
end

local function cardTitle(block)
    -- Slider cards keep the title in <strong> and a genre list in a sibling <p>;
    -- the heading wins so the genre list never leaks into the name.
    local raw = block:match('<a class="uk%-link%-heading"[^>]*>(.-)</a>')
        or block:match("<h[1-6][^>]*>(.-)</h[1-6]>")
        or block:match("<strong[^>]*>(.-)</strong>")
    return text(raw)
end

local function parseItems(html)
    local items, seen = {}, {}
    for _, block in ipairs(slices(html, CARD_MARKERS)) do
        local slug, ref = seriesRef(block)
        if slug and not seen[slug] then
            local title = cardTitle(block)
            if title ~= "" then
                seen[slug] = true
                local img = block:match("<img([^>]+)>")
                items[#items + 1] = { ref = ref, url = SITE .. ref, title = title, name = title,
                    cover = img and Html.attr(img, "src") or nil }
            end
        end
    end
    return items
end

local function list(makePath, page, allow_empty)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request(makePath(page))
    if not html then return nil, err end
    local body = mainHtml(html)
    local items = parseItems(body)
    if #items == 0 and page == 1 and not allow_empty then return nil, CHANGED end
    return { items = items, has_more = hasMore(body, page) }
end

local GENRES = {}

-- Key = the site's bo-loc-nang-cao filter slug, so browse() needs no extra
-- mapping. Adult tags stay hidden until Settings.adultContent() is on
-- (browse() checks again for stale menus).
local function genre(key, name, adult)
    local entry = { key = key, name = name, adult = adult or nil }
    GENRES[key] = entry
    return entry
end

T.genres = {
    genre("dammy", "Dammy (18+)", true),
    genre("caoh", "Cao H (18+)", true),
    genre("dam-my", "Đam Mỹ (18+)", true),
    genre("hiendai", "Hiện Đại"),
    genre("songtinh", "Song Tính (18+)", true),
    genre("sung", "Sủng"),
    genre("danmei", "Danmei (18+)", true),
    genre("hvan", "H Văn (18+)", true),
    genre("do-thi", "Đô Thị"),
    genre("1x1", "1x1"),
}

local LISTS = {
    latest = "moi-cap-nhat",
    popular = "bang-xep-hang-truyen",
    completed = "truyen-da-hoan-thanh",
}

function T.browse(kind, page)
    kind = kind or "latest"
    page = tonumber(page or 1) or 1
    local selected = GENRES[kind]
    if selected then
        if selected.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
        local filter = "/?genre%5B0%5D=" .. selected.key .. "&sort=updated"
        return list(function(p)
            return p <= 1 and "/bo-loc-nang-cao" .. filter or "/bo-loc-nang-cao/page/" .. p .. filter
        end, page)
    end
    local folder = LISTS[kind]
    if not folder then return nil, _("Kiểu danh sách không hợp lệ.") end
    return list(function(p)
        return p <= 1 and "/" .. folder .. "/" or "/" .. folder .. "/page/" .. p .. "/"
    end, page)
end

function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1) or 1
    local encoded = encode(query)
    return list(function(p)
        return p <= 1 and "/?s=" .. encoded or "/page/" .. p .. "/?s=" .. encoded
    end, page, true)
end

local function lockedRow(block)
    local class = block:match('<a[^>]-class="([^"]*)"') or ""
    for token in class:gmatch("%S+") do
        if token == "locked" or token == "vip" then return true end
    end
end

function T.getSeries(ref)
    local slug, chapter = T.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện DualeoTruyenFull không hợp lệ.") end
    local path = "/doc-truyen/" .. slug .. "/"
    local html, err = request(path)
    if not html then return nil, err end
    -- Sidebar widgets repeat story links (and their own pagination) on every page;
    -- only the main column belongs to this series.
    html = mainHtml(html)
    local title = text(Html.select(html, "#manga-title"))
    if title == "" then title = text(html:match("<h1[^>]*>(.-)</h1>") or "") end
    if title == "" then return nil, CHANGED end
    local series = { id = slug, source_id = T.id, title = title, url = SITE .. path, chapters = {} }
    local description = text(Html.select(html, "#manga-description"))
    if description ~= "" then series.description = description end
    local author = html:match("Tác giả:%s*<a[^>]*>(.-)</a>")
    if author then
        author = text(author)
        if author ~= "" then series.author = author end
    end
    -- EPUB cover writing only takes JPEG/PNG/GIF; this site serves WebP, so the
    -- cover stays in the grid (item covers) instead of the book.
    local cover = html:match('property="og:image"%s*content="([^"]+)"')
        or html:match('content="([^"]+)"%s*property="og:image"')
    if cover and not cover:lower():match("%.webp") then series.cover = cover end
    local seen, chapters, page = {}, {}, 1
    local CHAPTER_MARKER = { '<div class="chapter-item' }
    while true do
        local added = 0
        for _, row in ipairs(slices(html, CHAPTER_MARKER)) do
            local cid, chapter_path
            for href in row:gmatch('href="([^"]+)"') do
                local book, chapter, path = T.parseRef(Html.decode(href))
                if book == slug and chapter then
                    cid, chapter_path = chapter, path
                    break
                end
            end
            if cid and not seen[cid] then
                seen[cid], added = true, added + 1
                local label = text(row:match("<h3[^>]*>(.-)</h3>"))
                chapters[#chapters + 1] = { id = cid, series_id = slug, url = SITE .. chapter_path,
                    title = label ~= "" and label or (_("Chương ") .. cid),
                    locked = lockedRow(row) }
            end
        end
        if not hasMore(html, page) then break end
        if added == 0 then return nil, CHANGED end
        if page >= MAX_TOC_PAGES or Http.expired() then
            -- Keep what is already read; the reader can still download it.
            series.truncated = true
            break
        end
        page = page + 1
        html, err = request(path .. "chuong/page/" .. page .. "/")
        if not html then return nil, err end
        html = mainHtml(html)
    end
    if #chapters == 0 then return nil, CHANGED end
    -- Every chapter page lists newest-first; sorting by chapter number gives the
    -- reading order without trusting the site's page order.
    table.sort(chapters, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
    for i, ch in ipairs(chapters) do ch.index = i end
    series.chapters = chapters
    series.volumes = { { title = _("Chương"), chapters = chapters } }
    return series
end

local function hasLock(html)
    return html and (html:find("Mở khóa", 1, true) or html:find("mở khóa", 1, true))
end

function T.getChapter(ref)
    local slug, cid, path = T.parseRef(ref)
    if not cid or type(ref) ~= "table" or ref.series_id ~= slug then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local html, err, code = request(path)
    if not html then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local content = Html.select(html, "#chapter-content")
    if not content or text(content) == "" then
        -- Never fetch a key or run a script: a body without text is locked or empty.
        return { skipped = _("Chương trống hoặc đã khóa.") }
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
    local title = text(html:match("<h1[^>]*>(.-)</h1>") or "")
    return { title = title ~= "" and title or ref.title, html = table.concat(paragraphs, "\n") }
end

return T
