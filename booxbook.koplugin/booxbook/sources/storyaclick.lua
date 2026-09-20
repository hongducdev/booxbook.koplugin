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
local M = { id = "storyaclick", name = "Storya", kind = "novel",
    capabilities = { search = true, browse = true, login = false, adult = true } }
local SITE, API = "https://storya.click", "https://storya.click/api/v1/"
-- The site is a JSON REST app: /api/v1/<endpoint> serves the data and
-- /truyen/<slug>[/<chapter>] is the reader-facing URL parseRef() must accept.
local HOSTS = { ["storya.click"] = true, ["www.storya.click"] = true }
local PAGE = 100
-- A table of contents may paginate for a long series; stop here or when the
-- action's time budget is gone instead of spinning on a broken response.
local MAX_TOC_PAGES = 60
local CHANGED = _("API Storya thay đổi hoặc dữ liệu không hợp lệ.")
local ADULT = { sac = true }

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
M.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://storya.click/truyen/ten-truyen",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Truyện hot", kind = "popular" },
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

-- Chapter identity used when saving: (series_id, chapter_id, max id length).
-- Chapter ids are slugs ("chuong-1128-2"), so they may be longer than 12 chars.
function M.chapterRef(chapter)
    local series_id, chapter_id = M.parseRef(chapter)
    if chapter.series_id ~= series_id then series_id = nil end
    return series_id, chapter_id, 32
end

local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end

local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
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
    local slug = ref:match("^/truyen/([%w%-]+)/?$")
    if slug and #slug <= 180 then return slug end
    local book, chapter = ref:match("^/truyen/([%w%-]+)/([%w%-]+)/?$")
    if book and #book <= 180 and chapter and #chapter <= 64 then
        return book, chapter, "/truyen/" .. book .. "/" .. chapter
    end
end

local function apiGet(path)
    local ok, code, body = Http.get(API .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()), allow_url = hostAllowed,
        headers = { Accept = "application/json" } })
    if not ok then return nil, string.format(_("Không tải được Storya (HTTP %s)."), tostring(code)), code end
    local loaded, Json = pcall(require, "json")
    if not loaded then return nil, _("Không có thư viện JSON của KOReader.") end
    local decoded, data = pcall(Json.decode, body)
    if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then
        return nil, CHANGED
    end
    return data
end

local function cover(url)
    if type(url) == "string" and url:sub(1, 1) == "/" then return SITE .. url end
    return url
end

local function items(stories)
    local list, seen = {}, {}
    for _, story in ipairs(stories) do
        local slug = type(story.slug) == "string" and M.parseRef("/truyen/" .. story.slug)
        if not slug or type(story.title) ~= "string" then return nil, CHANGED end
        if not seen[slug] then
            seen[slug] = true
            local title = story.title ~= "" and story.title or _("Chưa có tiêu đề")
            list[#list + 1] = { ref = "/truyen/" .. slug, url = SITE .. "/truyen/" .. slug,
                title = title, name = title, cover = cover(story.coverUrl) }
        end
    end
    return list
end

local CATEGORIES = { latest = "stories", popular = "stories/hot" }
local GENRES = {}

-- Key = the site's /api/v1/genres/slug/<key> slug. The API also returns a few
-- slugs missing their first letter (o-thi, co-ai, ...); they are kept verbatim
-- because those are the only keys the endpoint answers to. Adult entries stay
-- hidden until Settings.adultContent() is on (browse() checks again).
local function genre(key, name, adult)
    local entry = { key = key, name = name, adult = adult or nil }
    GENRES[key] = entry
    return entry
end

M.genres = {
    genre("linh-di", "Linh Dị"),
    genre("am-my", "Đam Mỹ"),
    genre("xuyen-khong", "Xuyên Không"),
    genre("huyen-huyen", "Huyền Huyễn"),
    genre("trong-sinh", "Trọng Sinh"),
    genre("he-thong", "Hệ Thống"),
    genre("khac", "Khác"),
    genre("co-ai", "Cổ Đại"),
    genre("bach-hop", "Bách Hợp"),
    genre("tien-hiep", "Tiên Hiệp"),
    genre("xuyen-qua", "Xuyên Qua"),
    genre("o-thi", "Đô Thị"),
    genre("ngon-tinh", "Ngôn Tình"),
    genre("nu-cuong", "Nữ Cường"),
    genre("khoa-huyen", "Khoa Huyễn"),
    genre("cung-au", "Cung Đấu"),
    genre("mat-the", "Mạt Thế"),
    genre("quan-truong", "Quan Trường"),
    genre("kiem-hiep", "Kiếm Hiệp"),
    genre("nhiet-huyet", "Nhiệt Huyết"),
    genre("light-novel", "Light Novel"),
    genre("hien-ai", "Hiện đại"),
    genre("ong-nhan", "Đồng Nhân"),
    genre("da-su", "Dã Sử"),
    genre("xuyen-nhanh", "Xuyên Nhanh"),
    genre("du-hi-di-gioi", "Du Hí Dị Giới"),
    genre("ong-phuong-huyen-huyen", "Đông Phương Huyền Huyễn"),
    genre("vo-si", "Vô Sỉ"),
    genre("ong-phuong", "Đông Phương"),
    genre("nguoc", "Ngược"),
    genre("sung", "Sủng"),
    genre("ien-van", "Điền Văn"),
    genre("di-nang", "Dị Năng"),
    genre("sang-van", "Sảng Văn"),
    genre("goc-nhin-nam", "Góc Nhìn Nam"),
    genre("di-gioi", "Dị Giới"),
    genre("gia-au", "Gia Đấu"),
    genre("hai-huoc", "Hài Hước"),
    genre("oan-van", "Đoản Văn"),
    genre("trinh-tham", "Trinh Thám"),
    genre("lich-su-quan-su", "Lịch Sử Quân Sự"),
    genre("trung-sinh", "Trùng sinh"),
    genre("co-tri", "Cơ Trí"),
    genre("than-thoai-tu-chan", "Thần Thoại Tu Chân"),
    genre("thiet-huyet", "Thiết Huyết"),
    genre("tu-chan-van-minh", "Tu Chân Văn Minh"),
    genre("pham-nhan", "Phàm Nhân"),
    genre("iem-am", "Điềm Đạm"),
    genre("ngoi-thu-nhat", "Ngôi Thứ Nhất"),
    genre("huyen-nghi", "Huyền Nghi"),
    genre("mat-the-nguy-co", "Mạt Thế Nguy Cơ"),
    genre("lanh-khoc", "Lãnh Khốc"),
    genre("vong-du", "Võng Du"),
    genre("quan-su", "Quân Sự"),
    genre("canh-ky", "Cạnh Kỹ"),
    genre("nu-phu", "Nữ Phụ"),
    genre("tham-hiem", "Thám Hiểm"),
    genre("fanfic", "FanFic"),
    genre("phuong-tay", "Phương Tây"),
    genre("truyen-teen", "Truyện Teen"),
    genre("tong-tai", "Tổng Tài"),
    genre("tieu-thuyet", "Tiểu Thuyết"),
    genre("truyen-audio", "Truyện Audio"),
    genre("viet-nam", "Việt Nam"),
    genre("ky-ao", "Kỳ Ảo"),
    genre("lich-su", "Lịch Sử"),
    genre("sac", "Sắc", true),
    genre("truyen-tranh", "Truyện Tranh"),
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
    if selected then
        -- The genre endpoint answers with one page of stories and no pagination.
        if page > 1 then return { items = {}, has_more = false } end
        local data, err = apiGet("genres/slug/" .. selected.key)
        if not data then return nil, err end
        local list, item_err = items(data.data.stories or {})
        if not list then return nil, item_err end
        return { items = list, has_more = false }
    end
    local data, err = apiGet(CATEGORIES[kind] .. "?page=" .. page .. "&limit=20")
    if not data then return nil, err end
    local list, item_err = items(data.data)
    if not list then return nil, item_err end
    local meta = data.meta or {}
    return { items = list, has_more = page < (tonumber(meta.totalPages) or page) }
end

function M.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local data, err = apiGet("stories/search?q=" .. encode(query):gsub("%%20", "+") .. "&page=" .. page)
    if not data then return nil, err end
    local list, item_err = items(data.data)
    if not list then return nil, item_err end
    local meta = data.meta or {}
    return { items = list, has_more = page < (tonumber(meta.totalPages) or page) }
end

function M.getSeries(ref)
    local slug, chapter = M.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện Storya không hợp lệ.") end
    local data, err = apiGet("stories/" .. slug)
    if not data then return nil, err end
    local story = data.data
    if type(story.slug) ~= "string" or story.slug ~= slug or type(story.title) ~= "string" then
        return nil, CHANGED
    end
    local description = type(story.description) == "string" and story.description or ""
    if description == "" and type(story.rewrittenDescription) == "string" then
        description = story.rewrittenDescription
    end
    local series = { id = slug, source_id = M.id, title = story.title, url = SITE .. "/truyen/" .. slug,
        description = description ~= "" and description or nil, cover = cover(story.coverUrl),
        chapters = {}, tags = {} }
    local author = type(story.author) == "table" and story.author or {}
    if type(author.name) == "string" and author.name ~= "" then series.author = author.name end
    for _, entry in ipairs(type(story.genres) == "table" and story.genres or {}) do
        if type(entry) == "table" and type(entry.name) == "string" then
            series.tags[#series.tags + 1] = entry.name
            if ADULT[entry.slug] then series.adult = true end
        end
    end
    local seen, page = {}, 1
    while true do
        local page_data, page_err = apiGet("chapters/story/" .. slug .. "?page=" .. page
            .. "&limit=" .. PAGE .. "&minimal=true")
        if not page_data then return nil, page_err end
        local added = 0
        for _, item in ipairs(page_data.data) do
            local cid = type(item.slug) == "string" and item.slug:match("^[%w%-]+$")
            local order = tonumber(item.order)
            if not cid or #cid > 64 or not order or type(item.title) ~= "string" then return nil, CHANGED end
            if not seen[cid] then
                seen[cid], added = true, added + 1
                series.chapters[#series.chapters + 1] = { id = cid, series_id = slug,
                    url = SITE .. "/truyen/" .. slug .. "/" .. cid,
                    title = item.title ~= "" and item.title or (_("Chương") .. " " .. order),
                    order = order, locked = item.isLocked == true }
            end
        end
        local meta = page_data.meta or {}
        local total = tonumber(meta.totalPages) or page
        if page >= total then break end
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
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
    for i, ch in ipairs(series.chapters) do ch.index = i end
    series.volumes = { { title = _("Chương"), chapters = series.chapters } }
    return series
end

function M.getChapter(ref)
    local slug, cid = M.parseRef(ref)
    if not cid or type(ref) ~= "table" or ref.series_id ~= slug then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local data, err, code = apiGet("chapters/" .. slug .. "/" .. cid)
    if not data then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local item = data.data
    if type(item.slug) ~= "string" or item.slug ~= cid then return nil, CHANGED end
    if item.isLocked == true then return { skipped = _("Chương đã khóa.") } end
    local content = item.content
    if type(content) ~= "string" or content == "" then content = item.rewrittenContent end
    if type(content) ~= "string" or content == "" then content = item.rawContent end
    if type(content) ~= "string" or content == "" then return { skipped = _("Chương trống.") } end
    content = Html.stripDangerous(content):gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[Pp]>", "\n")
    local paragraphs = {}
    for line in content:gmatch("[^\r\n]+") do
        line = text(line)
        if line ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    return { title = type(item.title) == "string" and item.title or ref.title,
        html = table.concat(paragraphs, "\n") }
end

return M
