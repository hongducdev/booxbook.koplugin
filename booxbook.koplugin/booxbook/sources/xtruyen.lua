local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local T = { id = "xtruyen", name = "XTruyen", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://xtruyen.vn"
-- Stories are linked on both the bare and the www host; both resolve.
local HOSTS = { ["xtruyen.vn"] = true, ["www.xtruyen.vn"] = true }
local CHANGED = _("Không đọc được HTML XTruyen; trang có thể đã đổi hoặc yêu cầu xác minh.")
-- The table of contents is rebuilt from the first/last chapter buttons, so the
-- range is ours: cap it above any real story so a broken page cannot spin.
local MAX_CHAPTERS = 20000

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
T.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://xtruyen.vn/truyen/ten-truyen/",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Truyện HOT", kind = "popular" },
        { text = "Hoàn thành", kind = "completed" },
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

-- Chapter identity used when saving: (series_id, chapter_id).
function T.chapterRef(chapter)
    local series_id, chapter_id = T.parseRef(chapter)
    if chapter.series_id ~= series_id then series_id = nil end
    return series_id, chapter_id, 64
end
local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end
local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end
local function pageNumber(page)
    local n = tonumber(page or 1)
    if not n or n < 1 or n > 10000 or n % 1 ~= 0 then return nil end
    return n
end
local function hasLock(html)
    if not html then return false end
    return html:find("Mở khóa", 1, true) ~= nil or html:find("mở khóa", 1, true) ~= nil
        or html:find("Đăng nhập để đọc", 1, true) ~= nil
        or html:find("Vui lòng đăng nhập", 1, true) ~= nil
        or html:find("Nội dung trả phí", 1, true) ~= nil
end

-- Story URLs are /truyen/{slug}/; chapters add /{chuong|phan}-{n}/ and the
-- intro page /gioi-thieu/. Anything deeper under /truyen/ is not a chapter.
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
    local slug = ref:match("^/truyen/([^/]+)/?$")
    if slug and #slug <= 200 and slug ~= "feed" then return slug end
    local book, chapter = ref:match("^/truyen/([^/]+)/([^/]+)/?$")
    if book and chapter and #book <= 200 and #chapter <= 120 then
        local number = chapter:match("^chuong%-(%d+)$") or chapter:match("^phan%-(%d+)$")
        if number and (#number > 12 or tonumber(number) < 1) then return nil end
        return book, number or chapter, ref
    end
end

-- `fetch` hands back the raw body, `request` the sanitised HTML the parsers
-- below read; chapter payloads live in a <script> that the sanitiser removes.
local function fetch(path)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được XTruyen (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    return body, nil, code
end
local function request(path)
    local body, err, code = fetch(path)
    if not body then return nil, err, code end
    return Html.stripDangerous(body)
end
local function hasMore(html, page)
    local want = tostring(page + 1)
    for _, pattern in ipairs({ "page=(%d+)", "[pP]aged=(%d+)", "/page/(%d+)" }) do
        for n in html:gmatch(pattern) do
            if n == want then return true end
        end
    end
end

-- One card = <div class="popular-item-wrap"> with <h5 class="widget-title"> and
-- <a href="…/truyen/slug/">. The grid lives in .content_archive_3; the sidebar
-- repeats the same markup, so that scope keeps "Truyện mới" widgets out.
local function list(path, page, allow_empty)
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    local html, err = request(path)
    if not html then return nil, err end
    local scope = Html.elements(html, ".content_archive_3")[1]
    local items, seen = {}, {}
    for _, card in ipairs(Html.elements(scope and scope.inner or html, ".popular-item-wrap")) do
        local ref, inner_title, attr_title
        local heading = Html.elements(card.inner, "h5")[1]
        local anchors = heading and Html.elements(heading.inner, "a") or Html.elements(card.inner, "a")
        for _, a in ipairs(anchors) do
            local slug = T.parseRef(Html.decode(Html.attr(a.attrs, "href") or ""))
            if slug then
                ref = ref or slug
                local label = text(a.inner)
                if label ~= "" then
                    inner_title = inner_title or label
                else
                    attr_title = attr_title or Html.decode(Html.attr(a.attrs, "title") or "")
                end
            end
        end
        if ref and not seen[ref] then
            local img = Html.elements(card.inner, "img")[1]
            local cover = img and Html.decode(Html.attr(img.attrs, "src") or "")
            if cover == "" then cover = nil end
            seen[ref] = true
            local title = inner_title or attr_title
            if title == nil or title == "" then title = ref end
            items[#items + 1] = { ref = "/truyen/" .. ref .. "/", url = SITE .. "/truyen/" .. ref .. "/",
                title = title, name = title, cover = cover }
        end
    end
    if #items == 0 and page == 1 and not allow_empty then return nil, CHANGED end
    return { items = items, has_more = hasMore(html, page) }
end
local GENRES = {}

-- Key = the site's /theloai/ slug (the taxonomy is case-insensitive; the
-- lower case form is used). "Sắc" is the site's 18+ shelf, hidden until 18+ is
-- on (browse() checks again for stale menus).
local function genre(key, name, adult)
    local entry = { key = key, name = name, adult = adult or nil }
    GENRES[key] = entry
    return entry
end

T.genres = {
    genre("tien-hiep", "Tiên Hiệp"), genre("kiem-hiep", "Kiếm Hiệp"), genre("ngon-tinh", "Ngôn Tình"),
    genre("tong-tai", "Tổng Tài"), genre("dam-my", "Đam Mỹ"), genre("quan-truong", "Quan Trường"),
    genre("vong-du", "Võng Du"), genre("khoa-huyen", "Khoa Huyễn"), genre("he-thong", "Hệ Thống"),
    genre("huyen-huyen", "Huyền Huyễn"), genre("di-gioi", "Dị Giới"), genre("di-nang", "Dị Năng"),
    genre("quan-su", "Quân Sự"), genre("lich-su", "Lịch Sử"), genre("xuyen-khong", "Xuyên Không"),
    genre("xuyen-nhanh", "Xuyên Nhanh"), genre("trong-sinh", "Trọng Sinh"), genre("trinh-tham", "Trinh Thám"),
    genre("tham-hiem", "Thám Hiểm"), genre("linh-di", "Linh Dị"), genre("nguoc", "Ngược"),
    genre("sung", "Sủng"), genre("cung-dau", "Cung Đấu"), genre("nu-cuong", "Nữ Cường"),
    genre("gia-dau", "Gia Đấu"), genre("dong-phuong", "Đông Phương"), genre("do-thi", "Đô Thị"),
    genre("bach-hop", "Bách Hợp"), genre("dien-van", "Điền Văn"), genre("co-dai", "Cổ Đại"),
    genre("mat-the", "Mạt Thế"), genre("truyen-teen", "Truyện Teen"), genre("phuong-tay", "Phương Tây"),
    genre("nu-phu", "Nữ Phụ"), genre("light-novel", "Light Novel"), genre("viet-nam", "Việt Nam"),
    genre("doan-van", "Đoản Văn"), genre("my-thuc", "Mỹ Thực"), genre("hien-dai", "Hiện Đại"),
    genre("hai-huoc", "Hài Hước"), genre("khac", "Khác"), genre("sac", "Sắc (18+)", true),
}

function T.browse(kind, page)
    local selected = GENRES[kind]
    if kind ~= nil and not selected and kind ~= "latest" and kind ~= "popular" and kind ~= "completed" then
        return nil, _("Kiểu danh sách không hợp lệ.")
    end
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    if selected then
        if selected.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
        local path = "/theloai/" .. selected.key .. "/"
        if page > 1 then path = path .. "?page=" .. page end
        return list(path, page)
    end
    local order = kind == "latest" and "latest" or "trending"
    local path = "/truyen/?m_orderby=" .. order
    if kind == "completed" then path = path .. "&status=end" end
    return list(path .. "&page=" .. page, page)
end
function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    local path = "/?s=" .. encode(query):gsub("%%20", "+") .. "&post_type=wp-manga"
    if page > 1 then path = path .. "&page=" .. page end
    return list(path, page, true)
end

-- The story page keeps only the "Chương đầu"/"Chương cuối" buttons and a short
-- "Mới nhất" list; the full table of contents is built by the site's JS (its
-- ajax/chapters endpoint ships empty sub-lists). Expand the range between the
-- buttons; a partial fallback would be worse than a clear failure.
local function chaptersFromButtons(html, slug)
    local links = {}
    local nav = Html.elements(html, "#init-links")[1]
    if nav then
        for _, a in ipairs(Html.elements(nav.inner, "a")) do
            local book, cid, cpath = T.parseRef(Html.decode(Html.attr(a.attrs, "href") or ""))
            if book == slug and cid and cpath then links[#links + 1] = { id = cid, path = cpath } end
        end
    end
    if #links < 2 then return nil end
    local last = links[#links]
    local last_number = tonumber(last.id)
    local prefix = last.path:match("/([^/]+)%-%d+/$")
    local chapters = {}
    if last_number and last_number > 0 and prefix and last_number <= MAX_CHAPTERS then
        local first_number = tonumber(links[1].id) or 1
        if first_number < 1 then first_number = 1 end
        for n = first_number, last_number do
            chapters[#chapters + 1] = { id = tostring(n), series_id = slug,
                url = SITE .. "/truyen/" .. slug .. "/" .. prefix .. "-" .. n .. "/",
                title = (prefix == "phan" and _("Phần ") or _("Chương ")) .. n }
        end
    end
    -- Keep the first button when it falls outside that range: an unnumbered
    -- intro page (/gioi-thieu/) or a first part not named like the last one.
    local first = links[1]
    local covered = tonumber(first.id) and prefix
        and first.path == ("/truyen/" .. slug .. "/" .. prefix .. "-" .. tostring(tonumber(first.id)) .. "/")
    if not covered then
        table.insert(chapters, 1, { id = first.id, series_id = slug, url = SITE .. first.path,
            title = first.id == "gioi-thieu" and _("Giới thiệu") or first.id })
    end
    return #chapters > 0 and chapters or nil
end

function T.getSeries(ref)
    local slug, chapter = T.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện XTruyen không hợp lệ.") end
    local path = "/truyen/" .. slug .. "/"
    local html, err = request(path)
    if not html then return nil, err end
    local title = text(Html.select(html, ".post-title") or "")
    if title == "" then
        local meta = html:match('<meta property="og:title" content="([^"]+)"')
        title = meta and Html.decode(meta) or ""
    end
    if title == "" then return nil, CHANGED end
    local series = { id = slug, source_id = T.id, title = title, url = SITE .. path }
    local image = Html.elements(html, ".summary_image")[1]
    image = image and Html.elements(image.inner, "img")[1]
    if image then
        series.cover = Html.decode(Html.attr(image.attrs, "src") or "")
        if series.cover == "" then series.cover = nil end
    end
    local desc = Html.elements(html, ".summary__content")[1] or Html.elements(html, ".description")[1]
    if desc then
        local parts = {}
        for _, p in ipairs(Html.elements(desc.inner, "p")) do
            local line = text(p.inner)
            if line ~= "" then parts[#parts + 1] = line end
        end
        if #parts > 0 then series.description = table.concat(parts, "\n\n") end
    end
    local author = Html.elements(html, ".author-content")[1]
    if author then
        local link = Html.elements(author.inner, "a")[1]
        local name = text(link and link.inner or author.inner)
        if name ~= "" then series.author = name end
    end
    local chapters, seen = {}, {}
    for _, ch in ipairs(chaptersFromButtons(html, slug) or {}) do
        if not seen[ch.id] then
            seen[ch.id] = true
            ch.index = #chapters + 1
            chapters[#chapters + 1] = ch
        end
    end
    if #chapters == 0 then return nil, CHANGED end
    series.chapters = chapters
    series.volumes = { { title = _("Chương"), chapters = chapters } }
    return series
end

-- The chapter body is not in the HTML: the page ships a custom-base64 zlib
-- blob (`const data_x = "…"`) and inflates it in the browser (pako). Reproduce
-- that pipeline: custom alphabet → base64 → zlib.
local CUSTOM_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
local STANDARD_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function translate(data)
    local out = {}
    for i = 1, #data do
        local byte = data:sub(i, i)
        local index = CUSTOM_ALPHABET:find(byte, 1, true)
        out[#out + 1] = index and STANDARD_ALPHABET:sub(index, index) or byte
    end
    return table.concat(out)
end

local function base64(data)
    local out, accumulator, bits = {}, 0, 0
    for i = 1, #data do
        local byte = data:sub(i, i)
        if byte == "=" then break end
        local index = STANDARD_ALPHABET:find(byte, 1, true)
        if index then
            accumulator = accumulator * 64 + (index - 1)
            bits = bits + 6
            while bits >= 8 do
                bits = bits - 8
                out[#out + 1] = string.char(math.floor(accumulator / 2 ^ bits) % 256)
                accumulator = accumulator % 2 ^ bits
            end
        end
    end
    return table.concat(out)
end

local zlib_ready = false

-- zlib (RFC 1950) inflate; booxbook.gzip only handles gzip framing, so the same
-- struct/API is declared here with wbits 15 (identical cdefs keep both modules
-- loadable). Exposed so the unit test can drive the pipeline without libz.
T.inflate = function(data, limit)
    local ok, out = pcall(function()
        local ffi = require("ffi")
        if not zlib_ready then
            ffi.cdef(table.concat({
                "typedef struct { const unsigned char *next_in; unsigned int avail_in; unsigned long total_in;",
                "unsigned char *next_out; unsigned int avail_out; unsigned long total_out; char *msg; void *state;",
                "void *(*zalloc)(void *, unsigned int, unsigned int); void (*zfree)(void *, void *); void *opaque;",
                "int data_type; unsigned long adler; unsigned long reserved; } booxbook_z_stream;",
                "const char *zlibVersion(void);",
                "int inflateInit2_(booxbook_z_stream *, int, const char *, int);",
                "int inflate(booxbook_z_stream *, int); int inflateEnd(booxbook_z_stream *);",
            }, "\n"))
            zlib_ready = true
        end
        local lib = ffi.loadlib("z", 1)
        local stream = ffi.new("booxbook_z_stream[1]")
        local output = ffi.new("unsigned char[?]", limit + 1)
        stream[0].next_in, stream[0].avail_in = data, #data
        stream[0].next_out, stream[0].avail_out = output, limit + 1
        assert(lib.inflateInit2_(stream, 15, lib.zlibVersion(), ffi.sizeof(stream[0])) == 0)
        local status = lib.inflate(stream, 4) -- Z_FINISH
        local size = tonumber(stream[0].total_out)
        lib.inflateEnd(stream)
        assert(status == 1 and size <= limit)
        return ffi.string(output, size)
    end)
    if ok then return out end
    return nil
end

-- Inflated chapter body from the raw (pre-sanitiser) page, or nil without one.
function T.decode(html)
    local data = tostring(html or ""):match('data_x%s*=%s*"([^"]+)"')
    if not data or data == "" then return nil end
    local raw = base64(translate(data))
    if raw == "" then return nil end
    return T.inflate(raw, 4 * 1024 * 1024)
end

function T.getChapter(ref)
    local slug, cid, path = T.parseRef(ref)
    if not cid or type(ref) ~= "table" or ref.series_id ~= slug then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    -- The payload sits inside a <script>, which the sanitiser removes, so read
    -- it from the raw body and sanitise a second copy for the HTML checks.
    local raw, err, code = fetch(path)
    if not raw then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local html = Html.stripDangerous(raw)
    local title = ref.title
    if title == nil or title == "" then
        local heading = Html.elements(html, "h2")[1]
        title = heading and text(heading.inner) or nil
    end
    local body = T.decode(raw)
    if not body or text(body) == "" then
        if hasLock(html) then return { skipped = _("Chương đã khóa.") } end
        return { skipped = _("Chương trống hoặc không giải mã được.") }
    end
    local paragraphs = {}
    body = Html.stripDangerous(body)
    for line in body:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[Pp]>", "\n"):gmatch("[^\r\n]+") do
        local clean = text(line)
        if clean ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(clean) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    return { title = title, html = table.concat(paragraphs, "\n") }
end
return T
