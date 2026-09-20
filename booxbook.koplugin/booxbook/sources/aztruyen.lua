local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local T = { id = "aztruyen", name = "AzTruyen", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://aztruyen.top"
local HOSTS = { ["aztruyen.top"] = true, ["www.aztruyen.top"] = true }
local CHANGED = _("Không đọc được HTML AzTruyen; trang có thể đã đổi hoặc yêu cầu xác minh.")

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://aztruyen.top/ten-truyen-123/",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
    },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/[^/]+/?$") ~= nil
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
    return series_id, chapter_id, 64
end
local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end
-- AzTruyen uses <br /> as its line separator inside synopsis paragraphs.
local function blockText(html)
    local lines = {}
    for line in (html or ""):gsub("<[Bb][Rr]%s*/?>", "\n"):gmatch("[^\r\n]+") do
        local clean = text(line)
        if clean ~= "" then lines[#lines + 1] = clean end
    end
    return table.concat(lines, "\n")
end
local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end
local function classHas(attrs, name)
    for token in (Html.attr(attrs, "class") or ""):gmatch("%S+") do
        if token == name then return true end
    end
end
local function pageNumber(page)
    local n = tonumber(page or 1)
    if not n or n < 1 or n > 10000 or n % 1 ~= 0 then return nil end
    return n
end
-- Html.attr takes a Lua pattern, so a hyphenated attribute name needs escaping.
local function dataSrc(attrs)
    return attrs:match("data%-src%s*=%s*\"([^\"]*)\"")
        or attrs:match("data%-src%s*=%s*'([^']*)'")
        or attrs:match("data%-src%s*=%s*([^%s>]+)")
end
local function hasLock(html)
    if not html then return false end
    return html:find("Mở khóa", 1, true) ~= nil or html:find("mở khóa", 1, true) ~= nil
        or html:find("Đăng nhập để đọc", 1, true) ~= nil
        or html:find("Vui lòng đăng nhập", 1, true) ~= nil
        or html:match("chapter%-locked") ~= nil
end

-- Story URLs are /{slug}-{id}/; a chapter adds /{chapter-slug}-{chapter-id}/.
-- The numeric tail of the second segment is the site's chapter id.
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
    local slug = ref:match("^/([^/]+%-%d+)/?$")
    if slug and #slug <= 200 then return slug end
    local book, chapter = ref:match("^/([^/]+%-%d+)/([^/]+%-%d+)/?$")
    if book and chapter and #book <= 200 and #chapter <= 200 then
        local cid = chapter:match("%-(%d+)$")
        if cid and #cid <= 12 and tonumber(cid) > 0 then return book, cid, ref end
    end
end
local function request(path)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được AzTruyen (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end
local function hasMore(html, page)
    local want = tostring(page + 1)
    for n in html:gmatch("[?&]page=(%d+)") do
        if n == want then return true end
    end
    for n in html:gmatch("trang%-(%d+)") do
        if n == want then return true end
    end
end

-- One card = <div class="… story"> with <a class="thumbnail"><img></a> and
-- <h2 class="crop-text-2"><a title=…>Name</a></h2>. Sidebar entries use
-- li.story-top, so the exact "story" token keeps them out of the grid.
local function list(path, page, allow_empty)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request(path)
    if not html then return nil, err end
    local items, seen = {}, {}
    for _, card in ipairs(Html.elements(html, ".story")) do
        local ref, inner_title, attr_title
        for _, a in ipairs(Html.elements(card.inner, "a")) do
            local slug, chapter = T.parseRef(Html.decode(Html.attr(a.attrs, "href") or ""))
            if slug and not chapter then
                ref = ref or slug
                -- The cover anchor wraps only <img>; keep its title attribute as
                -- a fallback and prefer a link that carries visible text.
                local label = text(a.inner)
                if label ~= "" then
                    inner_title = inner_title or label
                else
                    attr_title = attr_title or Html.decode(Html.attr(a.attrs, "title") or "")
                end
            end
        end
        local title = inner_title or attr_title
        if ref and not seen[ref] then
            local img = Html.elements(card.inner, "img")[1]
            local cover = img and Html.decode(dataSrc(img.attrs) or Html.attr(img.attrs, "src") or "")
            if cover == "" then cover = nil end
            seen[ref] = true
            if title == nil or title == "" then title = ref end
            items[#items + 1] = { ref = "/" .. ref .. "/", url = SITE .. "/" .. ref .. "/",
                title = title, name = title, cover = cover }
        end
    end
    if #items == 0 and page == 1 and not allow_empty then return nil, CHANGED end
    return { items = items, has_more = hasMore(html, page) }
end
local GENRES = {}

-- Key = the site's /the-loai/ slug, so browse() needs no extra mapping. The live
-- taxonomy has no 18+ entry, so no genre is flagged adult.
local function genre(key, name, adult)
    local entry = { key = key, name = name, adult = adult or nil }
    GENRES[key] = entry
    return entry
end

T.genres = {
    genre("bi-an", "Bí Ẩn"),
    genre("chicklit", "ChickLit"),
    genre("co-dien", "Cổ Điển"),
    genre("dam-my", "Đam Mỹ"),
    genre("do-thi", "Đô Thị"),
    genre("fanfiction", "Fan Fiction"),
    genre("hai-huoc", "Hài Hước"),
    genre("hanh-dong", "Hành Động"),
    genre("hu-cau", "Hư Cấu"),
    genre("kinh-di", "Kinh Dị"),
    genre("lang-man", "Lãng Mạn"),
    genre("lgbt", "LGBT"),
    genre("lich-su", "Lịch Sử"),
    genre("ma-ca-rong", "Ma Cà Rồng"),
    genre("ngau-nhien", "Ngẫu Nhiên"),
    genre("ngon-tinh", "Ngôn Tình"),
    genre("nguoi-soi", "Người Sói"),
    genre("phi-tieu-thuyet", "Phi Tiểu Thuyết"),
    genre("phieu-luu", "Phiêu Lưu"),
    genre("sieu-nhien", "Siêu Nhiên"),
    genre("tam-linh", "Tâm Linh"),
    genre("tho-ca", "Thơ Ca"),
    genre("thriller", "Thriller"),
    genre("tieu-thuyet", "Tiểu Thuyết"),
    genre("truyen-ngan", "Truyện Ngắn"),
    genre("truyen-teen", "Truyện Teen"),
    genre("vien-tuong", "Viễn Tưởng"),
    genre("xuyen-khong", "Xuyên Không"),
}

function T.browse(kind, page)
    local selected = GENRES[kind]
    if kind ~= nil and not selected and kind ~= "latest" then
        return nil, _("Kiểu danh sách không hợp lệ.")
    end
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    if selected then
        if selected.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
        local path = "/the-loai/" .. selected.key .. "/"
        if page > 1 then path = path .. "?page=" .. page end
        return list(path, page)
    end
    -- /danh-sach/hoan-thanh/ answers 200 with an error page, so "latest" is the
    -- home archive; ?page=N walks it.
    return list(page > 1 and ("/?page=" .. page) or "/", page)
end
function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    local path = "/tim-kiem/" .. encode(query)
    if page > 1 then path = path .. "?page=" .. page end
    return list(path, page, true)
end
function T.getSeries(ref)
    local slug, chapter = T.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện AzTruyen không hợp lệ.") end
    local path = "/" .. slug .. "/"
    local html, err = request(path)
    if not html then return nil, err end
    local title
    for _, h1 in ipairs(Html.elements(html, "h1")) do
        if Html.attr(h1.attrs, "itemprop") == "name" or classHas(h1.attrs, "title") then
            title = text(h1.inner)
            if title ~= "" then break end
        end
    end
    if not title or title == "" then return nil, CHANGED end
    local series = { id = slug, source_id = T.id, title = title, url = SITE .. path }
    local fallback_cover
    for _, img in ipairs(Html.elements(html, "img")) do
        local src = Html.decode(Html.attr(img.attrs, "src") or "")
        if src ~= "" then
            if Html.attr(img.attrs, "itemprop") == "image" then
                series.cover = src
                break
            elseif not fallback_cover and classHas(img.attrs, "cover") then
                fallback_cover = src
            end
        end
    end
    series.cover = series.cover or fallback_cover
    local desc = Html.elements(html, ".description")[1]
    if desc then
        local parts = {}
        for _, p in ipairs(Html.elements(desc.inner, "p")) do
            local line = blockText(p.inner)
            if line ~= "" then parts[#parts + 1] = line end
        end
        if #parts > 0 then series.description = table.concat(parts, "\n\n") end
    end
    local author = Html.elements(html, ".author")[1]
    if author then
        local name = blockText(author.inner)
        if name == "" then name = text(author.inner) end
        if name ~= "" then series.author = name end
    end
    -- The whole table of contents is rendered on the story page (verified up to
    -- 196 chapters, no ?page= pagination). Two <ul class="chapters"> exist (a
    -- short "latest" block and the full list), so score every <ul> by how many
    -- of its links are chapters of this story and keep the widest one.
    series.chapters = {}
    local best, best_count = {}, 0
    for _, ul in ipairs(Html.elements(html, "ul")) do
        local found, seen = {}, {}
        for _, li in ipairs(Html.elements(ul.inner, "li")) do
            for _, a in ipairs(Html.elements(li.inner, "a")) do
                local book, cid, cpath = T.parseRef(Html.decode(Html.attr(a.attrs, "href") or ""))
                if book == slug and cid and not seen[cid] then
                    seen[cid] = true
                    local label = text(a.inner)
                    if label == "" then label = Html.decode(Html.attr(a.attrs, "title") or "") end
                    found[#found + 1] = { id = cid, series_id = slug, url = SITE .. cpath,
                        title = label, locked = classHas(li.attrs, "vip") or classHas(li.attrs, "lock") }
                end
            end
        end
        if #found > best_count then best, best_count = found, #found end
    end
    series.chapters = best
    if #series.chapters == 0 then return nil, CHANGED end
    for i, ch in ipairs(series.chapters) do ch.index = i end
    series.volumes = { { title = _("Chương"), chapters = series.chapters } }
    return series
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
    local body = Html.elements(html, ".chapter-content")[1]
    body = body and body.inner or nil
    if not body or text(body) == "" then
        if hasLock(html) then return { skipped = _("Chương đã khóa.") } end
        return { skipped = _("Chương trống.") }
    end
    if hasLock(body) and (body:find("<form") or body:find("<button")) then
        return { skipped = _("Chương đã khóa.") }
    end
    local paragraphs = {}
    for line in body:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[Pp]>", "\n"):gmatch("[^\r\n]+") do
        local clean = text(line)
        if clean ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(clean) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    return { title = ref.title, html = table.concat(paragraphs, "\n") }
end
return T
