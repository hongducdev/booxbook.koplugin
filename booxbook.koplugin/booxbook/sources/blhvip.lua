local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
-- KOReader always bundles booxbook.http; the fallback keeps this adapter (and its
-- test file) loadable under a bare LuaJIT that has no luasocket.
local http_ok, Http = pcall(require, "booxbook.http")
if not http_ok then
    Http = { expired = function() return true end,
        get = function() return false, _("Không có thư viện mạng của KOReader.") end }
end
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local M = { id = "blhvip", name = "Bàn Long VIP", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE, API = "https://blhvip.vn", "https://api.blhvip.vn/v1/"
-- The REST API is served by api.blhvip.vn while story and chapter pages come
-- from blhvip.vn, so parseRef() and allow_url() must accept both hosts.
local HOSTS = { ["blhvip.vn"] = true, ["www.blhvip.vn"] = true, ["api.blhvip.vn"] = true }
-- chapter_list() is fixed at 50 items per page (109 pages for the longest story),
-- so the table of contents is read page by page and stops at this cap or when the
-- action's time budget is gone.
local MAX_TOC_PAGES = 110
local CHANGED = _("API Bàn Long VIP thay đổi hoặc dữ liệu không hợp lệ.")

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
M.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://blhvip.vn/truyen/ten-truyen",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Truyện hot", kind = "popular" },
        { text = "Hoàn thành", kind = "completed" },
    },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/truyen/") ~= nil
    end,
}

function M.locate(series)
    local id, chapter = M.parseRef(series.url)
    if not id or chapter then return id, nil end
    return id, id
end

-- Chapter identity used when saving: (series_id, chapter_id).
function M.chapterRef(chapter)
    local series_id, chapter_id = M.parseRef(chapter)
    if chapter.series_id ~= series_id then series_id = nil end
    return series_id, chapter_id
end

local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end

local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end

local function classHas(attrs, name)
    for token in (Html.attr(attrs, "class") or ""):gmatch("%S+") do
        if token == name then return true end
    end
end

local function hostAllowed(url)
    return HOSTS[(url or ""):match("^https?://([^/?#]+)")] == true
end

function M.parseRef(ref)
    if type(ref) == "table" then ref = ref.url or ref.ref end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if not path or not HOSTS[host] then return nil end
        ref = path
    end
    ref = ref:match("^[^?#]+") or ""
    local book, chapter = ref:match("^/truyen/([%w%-]+)/chuong%-(%d+)/?$")
    if book and #book <= 180 and #chapter <= 12 and tonumber(chapter) > 0 then
        return book, chapter, "/truyen/" .. book .. "/chuong-" .. chapter
    end
    local slug = ref:match("^/truyen/([%w%-]+)/?$")
    if slug and #slug <= 180 then return slug end
end

local function siteRequest(path)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()), allow_url = hostAllowed })
    if not ok then return nil, string.format(_("Không tải được Bàn Long VIP (HTTP %s)."), tostring(code)), code end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end

local function apiGet(path)
    local ok, code, body = Http.get(API .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()), allow_url = hostAllowed,
        headers = { Accept = "application/json" } })
    if not ok then return nil, string.format(_("Không tải được Bàn Long VIP (HTTP %s)."), tostring(code)), code end
    local loaded, Json = pcall(require, "json")
    if not loaded then return nil, _("Không có thư viện JSON của KOReader.") end
    local decoded, data = pcall(Json.decode, body)
    if not decoded or type(data) ~= "table" or data.success ~= true or type(data.data) ~= "table" then
        return nil, CHANGED
    end
    return data
end

local function hasMore(html, page)
    local want = tostring(page + 1)
    for n in html:gmatch("[?&]page=(%d+)") do
        if n == want then return true end
    end
end

-- Covers are lazy-loaded <img> tags; match attribute names as tokens (src must
-- not select data-src), the way the comic adapters do.
local function imageUrl(card)
    local img = card:match("<[Ii][Mm][Gg]([^>]*)>")
    if not img then return nil end
    local attrs = {}
    for key, _, value in img:gmatch("([%w_-]+)%s*=%s*([\"'])(.-)%2") do attrs[key:lower()] = value end
    return attrs["data-src"] or attrs["src"]
end

-- Each result is a .novel-item card: the cover <img> first, then the title link.
local function list(path, page)
    local html, err = siteRequest(path .. (page > 1 and ("?page=" .. page) or ""))
    if not html then return nil, err end
    local items, seen = {}, {}
    for _, card in ipairs(Html.elements(html, ".novel-item")) do
        local cover = imageUrl(card.inner)
        for _, a in ipairs(Html.elements(card.inner, "a")) do
            local href = Html.decode(Html.attr(a.attrs, "href") or "")
            local slug, chapter = M.parseRef("/" .. href)
            if classHas(a.attrs, "title") and slug and not chapter and not seen[slug] then
                seen[slug] = true
                items[#items + 1] = { ref = "/truyen/" .. slug, url = SITE .. "/truyen/" .. slug,
                    title = text(Html.attr(a.attrs, "title") or a.inner), name = text(a.inner),
                    cover = cover }
            end
        end
    end
    if #items == 0 and page == 1 then return nil, CHANGED end
    return { items = items, has_more = hasMore(html, page) == true }
end

local CATEGORIES = { latest = "/truyen-moi-nhat", popular = "/truyen-hot", completed = "/truyen-hoan-thanh" }
local GENRES = {}

-- Key = the site's /the-loai/<key> slug, so browse() needs no extra mapping.
-- Bàn Long VIP lists no 18+ genre, so no entry carries the adult flag.
local function genre(key, name)
    local entry = { key = key, name = name }
    GENRES[key] = entry
    return entry
end

M.genres = {
    genre("am-thuc", "Ẩm Thực"),
    genre("can-dai", "Cận Đại"),
    genre("canh-ky", "Cạnh Kỹ"),
    genre("da-su", "Dã Sử"),
    genre("di-gioi", "Dị Giới"),
    genre("di-nang", "Dị Năng"),
    genre("do-thi", "Đô Thị"),
    genre("dong-nhan", "Đồng Nhân"),
    genre("hai-huoc", "Hài Hước"),
    genre("hao-mon", "Hào Môn"),
    genre("he-thong", "Hệ Thống"),
    genre("hien-dai", "Hiện Đại"),
    genre("trinh-tham", "Trinh Thám"),
    genre("co-dai", "Cổ Đại"),
    genre("dien-van", "Điền Văn"),
    genre("hau-cung-harem", "Hậu Cung - Harem"),
    genre("hac-am-luu", "Hắc Ám Lưu"),
    genre("hong-hoang", "Hồng Hoang"),
    genre("huyen-ao", "Huyền Ảo"),
    genre("dao-mo", "Đạo Mộ - Khảo Cổ"),
    genre("huyen-huyen", "Huyền Huyễn"),
    genre("huyen-su", "Huyền Sử"),
    genre("khoa-huyen", "Khoa Huyễn"),
    genre("kiem-hiep", "Kiếm Hiệp"),
    genre("kinh-di", "Kinh Dị"),
    genre("kinh-te", "Kinh Tế"),
    genre("ky-huyen", "Kỳ Huyễn"),
    genre("lich-su", "Lịch Sử"),
    genre("linh-di", "Linh Dị"),
    genre("ma-phap", "Ma Pháp"),
    genre("mat-the", "Mạt Thế"),
    genre("ngon-tinh", "Ngôn Tình"),
    genre("nhe-nhang", "Nhẹ Nhàng"),
    genre("nu-hiep", "Nữ Hiệp"),
    genre("phan-phai", "Phản Phái"),
    genre("phong-thuy-tam-linh", "Phong Thủy - Tâm Linh"),
    genre("quan-su", "Quân Sự"),
    genre("quan-truong", "Quan Trường"),
    genre("thuong-nghiep", "Thương Nghiệp"),
    genre("tien-hiep", "Tiên Hiệp"),
    genre("tinh-cam", "Tình Cảm"),
    genre("trieu-hoan-ngu-thu", "Triệu Hoán - Ngự Thú"),
    genre("trung-sinh", "Trùng Sinh"),
    genre("tu-chan", "Tu Chân"),
    genre("sang-van", "Sảng Văn"),
    genre("phieu-luu", "Phiêu Lưu"),
    genre("tu-tien-do-thi", "Tu Tiên Đô Thị"),
    genre("vo-dich", "Vô Địch"),
    genre("vo-han-luu", "Vô Hạn Lưu"),
    genre("vo-hiep", "Võ Hiệp"),
    genre("vo-thuat", "Võ Thuật"),
    genre("vong-du", "Võng Du"),
    genre("xuyen-khong", "Xuyên Không"),
    genre("nu-phu", "Nữ Chủ"),
    genre("vo-si", "Vô Sỉ"),
    genre("y-thuat", "Y Thuật"),
    genre("tam-quoc", "Tam Quốc"),
}

function M.browse(kind, page)
    kind = kind or "latest"
    local selected = GENRES[kind]
    if not selected and not CATEGORIES[kind] then return nil, _("Kiểu danh sách không hợp lệ.") end
    if selected and selected.adult and not Settings.adultContent() then
        return nil, _("Nội dung 18+ đang tắt.")
    end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    return list(selected and ("/the-loai/" .. selected.key) or CATEGORIES[kind], page)
end

function M.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 1000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local data, err = apiGet("search?q=" .. encode(query) .. "&page=" .. page)
    if not data then return nil, err end
    local items = {}
    for _, story in ipairs(data.data) do
        local slug = type(story.slug) == "string" and M.parseRef("/truyen/" .. story.slug)
        if not slug or type(story.name) ~= "string" then return nil, CHANGED end
        items[#items + 1] = { ref = "/truyen/" .. slug, url = SITE .. "/truyen/" .. slug,
            title = story.name, name = story.name, cover = story.img_url }
    end
    return { items = items, has_more = page < (tonumber(data.total_page) or page) }
end

-- Story metadata only exists in the HTML page; the API's /story/<slug> is closed.
local function metadata(html, series)
    for attrs in html:gmatch("<meta([^>]+)>") do
        local property, content = Html.attr(attrs, "property"), Html.attr(attrs, "content")
        if property == "og:title" then series.title = text(content) end
        if property == "og:image" then series.cover = content end
    end
    if not series.title or series.title == "" then series.title = text(Html.select(html, ".name-story") or "") end
    local description = Html.select(Html.select(html, "#tab-info-1") or "", ".s-content")
    if description then series.description = text(description) end
    for _, a in ipairs(Html.elements(html, "a")) do
        local href = Html.attr(a.attrs, "href") or ""
        if not series.author and href:match("^tac%-gia/") then
            series.author = text(Html.attr(a.attrs, "title") or a.inner)
        end
    end
    series.tags = {}
    local seen_tags = {}
    for _, ul in ipairs(Html.elements(html, "ul")) do
        if classHas(ul.attrs, "tag") then
            for _, a in ipairs(Html.elements(ul.inner, "a")) do
                local slug = (Html.attr(a.attrs, "href") or ""):match("^the%-loai/([%w%-]+)")
                if slug and not seen_tags[slug] then
                    seen_tags[slug] = true
                    series.tags[#series.tags + 1] = text(Html.attr(a.attrs, "title") or a.inner)
                end
            end
        end
    end
end

function M.getSeries(ref)
    local slug, chapter = M.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện Bàn Long VIP không hợp lệ.") end
    local path = "/truyen/" .. slug
    local html, err = siteRequest(path)
    if not html then return nil, err end
    local series = { id = slug, source_id = M.id, url = SITE .. path, chapters = {} }
    metadata(html, series)
    if not series.title or series.title == "" then return nil, CHANGED end
    local seen, page = {}, 1
    while true do
        local data, api_err = apiGet("story/" .. slug .. "/chapter_list?page=" .. page .. "&new=0")
        if not data then return nil, api_err end
        local added = 0
        for _, item in ipairs(data.data) do
            local book, cid
            if type(item.url) == "string" then
                book, cid = item.url:match("^/truyen/([%w%-]+)/chuong%-(%d+)$")
            end
            if type(item.name) ~= "string" or item.name == "" or book ~= slug then return nil, CHANGED end
            if not seen[cid] then
                seen[cid], added = true, added + 1
                series.chapters[#series.chapters + 1] = { id = cid, series_id = slug,
                    url = SITE .. path .. "/chuong-" .. cid, title = item.name,
                    order = tonumber(item.ord) or tonumber(cid), locked = item.is_vip == true }
            end
        end
        if page >= (tonumber(data.total_page) or 1) then break end
        if added == 0 then return nil, CHANGED end
        if page >= MAX_TOC_PAGES or Http.expired() then
            -- Keep what we already have; the reader can still download it.
            series.truncated = true
            break
        end
        page = page + 1
    end
    if #series.chapters == 0 then return nil, CHANGED end
    table.sort(series.chapters, function(a, b)
        if a.order == b.order then return tonumber(a.id) < tonumber(b.id) end
        return a.order < b.order
    end)
    for i, ch in ipairs(series.chapters) do ch.index = i end
    series.volumes = { { title = _("Chương"), chapters = series.chapters } }
    return series
end

local LOCKED = _("Chương VIP bị khóa.")

function M.getChapter(ref)
    local slug, cid, path = M.parseRef(ref)
    if not cid or type(ref) ~= "table" or ref.series_id ~= slug then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = LOCKED } end
    local html, err, code = siteRequest(path)
    if not html then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local found = Html.elements(html, ".published-content", true)[1]
    if not found then found = Html.elements(html, "#chapter-content", true)[1] end
    local content
    if found then
        if classHas(found.attrs, "content-lock") then return { skipped = LOCKED } end
        content = found.inner
    end
    if not content or text(content) == "" then
        -- A locked page keeps the first lines visible above the buy box: never
        -- save that teaser as the chapter.
        if html:find("content%-lock") or html:find("box%-buy%-chapter") then return { skipped = LOCKED } end
        return { skipped = _("Chương trống.") }
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

return M
