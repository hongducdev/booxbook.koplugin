local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local M = { id = "metruyenvn", name = "Mê Truyện VN", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://metruyenvn.org"
-- Search is rendered by the theme's own AJAX call on the live site, so the
-- adapter uses that endpoint first and only falls back to the server-rendered
-- /?s= page (which the theme leaves empty without JS).
local SEARCH_URL = SITE .. "/wp-admin/admin-ajax.php"
-- Every list here is one server page; pagination is bounded so a broken site
-- cannot make the reader walk an endless /page/N/ series.
local MAX_PAGE = 1000
local CHANGED = _("Không đọc được HTML Mê Truyện VN; trang có thể đã đổi hoặc yêu cầu xác minh.")

-- Presentation for booxbook.ui.source-page; series→folder mapping for
-- booxbook.novel-download. Both keep this source out of UI and dispatch code.
M.view = {
    base_url = SITE,
    cover_referer = SITE .. "/",
    cover_delay_ms = 1600,
    search_hint = "Từ khóa hoặc https://metruyenvn.org/truyen/…",
    browse = {
        { text = "Mới cập nhật", kind = "latest" },
        { text = "Trọn bộ", kind = "completed" },
    },
    is_ref = function(text)
        return text:match("^https?://") ~= nil or text:match("^/truyen/") ~= nil
    end,
}

local function text(html)
    return Html.decode(Html.stripDangerous(html or ""):gsub("<[^>]+>", "")):match("^%s*(.-)%s*$")
end

local function encode(query)
    return query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
end

function M.parseRef(ref)
    if type(ref) == "table" then ref = ref.url or ref.ref end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if host ~= "metruyenvn.org" and host ~= "www.metruyenvn.org" then return nil end
        ref = path
    end
    ref = ref:match("^[^?#]+") or ""
    local slug = ref:match("^/truyen/([%w%%%-]+)/?$")
    if slug and #slug <= 200 then return slug end
    -- Chapter URLs are global (/chuong-<n>-<post id>/), so the series is not
    -- part of the reference; the caller supplies series_id from the table of contents.
    local cid = ref:match("^/chuong%-([%w%%%-]+)/?$")
    if cid and #cid <= 40 then return nil, cid, ref end
end

function M.locate(series)
    local id = M.parseRef(series or {})
    if not id then return nil, nil end
    return id, id
end

-- Chapter identity used when saving: (series_id, chapter_id). The full segment
-- ("28-62") is kept so two branches with the same chapter number cannot collide.
function M.chapterRef(chapter)
    local ref = type(chapter) == "table" and (chapter.url or chapter.ref) or chapter
    local ignored, cid = M.parseRef(ref)
    local series_id = type(chapter) == "table" and chapter.series_id or nil
    return series_id, cid, 40
end
local GENRES = {}

-- Key = the site's /the-loai/<key>/ path segment, so browse() needs no mapping.
-- Adult tags stay hidden until Settings.adultContent() is on (browse() checks
-- again for a stale menu). Only the site's real, verified slugs are listed.
local function genre(key, name, adult)
    local entry = { key = key, name = name, adult = adult or nil }
    GENRES[key] = entry
    return entry
end

M.genres = {
    genre("tien-hiep", "Tiên Hiệp"), genre("kiem-hiep", "Kiếm Hiệp"),
    genre("ngon-tinh", "Ngôn Tình"), genre("dam-my", "Đam Mỹ"),
    genre("bach-hop", "Bách Hợp"), genre("huyen-huyen", "Huyền Huyễn"),
    genre("di-gioi", "Dị Giới"), genre("do-thi", "Đô Thị"),
    genre("he-thong", "Hệ Thống"), genre("trong-sinh", "Trọng Sinh"),
    genre("hien-dai", "Hiện Đại"), genre("co-dai", "Cổ Đại"),
    genre("cung-dau", "Cung Đấu"), genre("dien-van", "Điền Văn"),
    genre("doan-van", "Đoản Văn"), genre("truyen-ngan", "Truyện Ngắn"),
    genre("kinh-di", "Kinh Dị"), genre("linh-di", "Linh Dị"),
    genre("mat-the", "Mạt Thế"), genre("quan-truong", "Quan Trường"),
    genre("trinh-tham", "Trinh Thám"), genre("vong-du", "Võng Du"),
    genre("hai-huoc", "Hài Hước"), genre("nguoc", "Ngược"),
    genre("sung", "Sủng"), genre("nu-cuong", "Nữ Cường"),
    genre("chucong", "Chủ Công"), genre("chuthu", "Chủ Thụ"),
    genre("cuongcong", "Cường Công"), genre("cuongthu", "Cường Thụ"),
    genre("abo", "ABO"), genre("hocduong", "Học Đường"),
    genre("thanhxuan", "Thanh Xuân"), genre("truyen-hot", "Truyện Hot"),
    genre("ngot", "Ngọt"), genre("ngotsung", "Ngọt Sủng"),
    genre("hieulam", "Hiểu Lầm"), genre("hoanthanh", "Hoàn Thành"),
    genre("happyend", "Happy End"), genre("vohanluu", "Vô Hạn Lưu"),
    genre("trungsinh", "Trùng Sinh"), genre("songtinh", "Song Tính"),
    genre("tongcong", "Tổng Công"), genre("tongthu", "Tổng Thụ"),
    genre("tracong", "Tra Công"), genre("mycong", "Mỹ Công"),
    genre("mythu", "Mỹ Thụ"), genre("cauhuyet", "Cẩu Huyết"),
    genre("nguoctam", "Ngược Tâm"), genre("nguocthan", "Ngược Thân"),
    genre("nguoctra", "Ngược Tra"), genre("diemvan", "Điềm Văn"),
    genre("hacbang", "Hắc Bang"), genre("cotrang", "Cổ Trang"),
    genre("cungdinh", "Cung Đình"), genre("1v1", "1v1"),
    genre("3p", "3P"), genre("np", "NP"),
    genre("sac", "Sắc (18+)", true), genre("cao-h", "Cao H (18+)", true),
    genre("h-tuc", "H Tục (18+)", true), genre("18", "18+", true),
    genre("18plus", "18Plus (18+)", true), genre("bdsm", "BDSM (18+)", true),
    genre("sm", "SM (18+)", true), genre("hentai", "Hentai (18+)", true),
    genre("gaysex", "Gay Sex (18+)", true), genre("chatsex", "Chat Sex (18+)", true),
}

local function request(path)
    if Http.expired() then return nil, _("Việc tải mất quá nhiều thời gian nên đã dừng lại.") end
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được Mê Truyện VN (HTTP %s)."), tostring(code)), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end

local function hasMore(html, page)
    local want = tostring(page + 1)
    for n in html:gmatch("/page/(%d+)/") do
        if n == want then return true end
    end
    return false
end

-- Covers both listing layouts: .comic-item-box cards (home) and the
-- .single-list-comic list rows (completed / genre archives).
local function parseItems(html)
    local items, seen = {}, {}
    local function add(href, title, cover)
        local slug, cid = M.parseRef(href)
        if not slug or cid or not title or title == "" or seen[slug] then return end
        seen[slug] = true
        items[#items + 1] = { ref = "/truyen/" .. slug .. "/", url = SITE .. "/truyen/" .. slug .. "/",
            title = title, name = title, cover = cover }
    end
    for _, card in ipairs(Html.elements(html, ".comic-item-box")) do
        local anchor
        for _, a in ipairs(Html.elements(card.inner, "a")) do
            local href = Html.decode(Html.attr(a.attrs, "href") or "")
            local slug, cid = M.parseRef(href)
            if slug and not cid then anchor = a; break end
        end
        if anchor then
            local href = Html.decode(Html.attr(anchor.attrs, "href") or "")
            local title = Html.attr(anchor.attrs, "title")
            if not title then title = text(Html.select(anchor.inner, ".comic-title") or anchor.inner) end
            local img = Html.elements(card.inner, "img")[1]
            add(href, text(title), img and Html.attr(img.attrs, "src"))
        end
    end
    local list = Html.select(html, ".single-list-comic")
    if list then
        for _, row in ipairs(Html.elements(list, "li")) do
            local a = Html.elements(row.inner, "a")[1]
            if a then
                local img = Html.elements(row.inner, "img")[1]
                add(Html.decode(Html.attr(a.attrs, "href") or ""), text(a.inner),
                    img and Html.attr(img.attrs, "src"))
            end
        end
    end
    return items
end

local function list(path, page, allow_empty)
    page = tonumber(page or 1)
    if not page or page < 1 or page > MAX_PAGE or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request(path)
    if not html then return nil, err end
    local items = parseItems(html)
    if #items == 0 and not allow_empty then return nil, CHANGED end
    return { items = items, has_more = hasMore(html, page) }
end

function M.browse(kind, page)
    kind = kind or "latest"
    if kind == "latest" then
        page = tonumber(page or 1)
        if not page or page < 1 or page > MAX_PAGE or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
        return list(page == 1 and "/" or ("/page/" .. page .. "/"), page)
    end
    if kind == "completed" then
        -- The whole completed catalogue is one server page.
        return list("/tron-bo/", 1)
    end
    local selected = GENRES[kind]
    if not selected then return nil, _("Kiểu danh sách không hợp lệ.") end
    if selected.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
    -- Genre archives ship their rows in one page and paginate client-side.
    return list("/the-loai/" .. selected.key .. "/", 1)
end

-- Live search is the theme's AJAX endpoint; returns nil so search() can fall back.
local function searchAjax(query)
    local loaded, Json = pcall(require, "json")
    if not loaded or type(Json) ~= "table" or type(Json.decode) ~= "function" then return nil end
    local ok, code, body = Http.post(SEARCH_URL, "action=searchtax&keyword=" .. encode(query), {
        referer = SITE .. "/", delay_ms = math.max(1600, Settings.delayMs()),
        headers = { ["X-Requested-With"] = "XMLHttpRequest", Accept = "application/json" } })
    if not ok or type(body) ~= "string" then return nil end
    local decoded, data = pcall(Json.decode, body)
    if not decoded or type(data) ~= "table" or data.success ~= true or type(data.data) ~= "table" then
        return nil
    end
    local items, seen = {}, {}
    for _, row in ipairs(data.data) do
        if type(row) == "table" and type(row.link) == "string" then
            local slug, cid = M.parseRef(row.link)
            if slug and not cid and not seen[slug] then
                seen[slug] = true
                local title = tostring(row.title or slug)
                items[#items + 1] = { ref = "/truyen/" .. slug .. "/", url = SITE .. "/truyen/" .. slug .. "/",
                    title = title, name = title, cover = type(row.img) == "string" and row.img or nil }
            end
        end
    end
    return items
end

function M.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1)
    if not page or page < 1 or page > MAX_PAGE or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    if page == 1 then
        local items = searchAjax(query)
        if items then return { items = items, has_more = false } end
    end
    local html, err = request("/?s=" .. encode(query))
    if not html then return nil, err end
    return { items = parseItems(html), has_more = false }
end

function M.getSeries(ref)
    local id = M.parseRef(ref)
    if not id then return nil, _("Nhập URL truyện Mê Truyện VN hoặc tìm bằng tên truyện.") end
    local path = "/truyen/" .. id .. "/"
    local html, err = request(path)
    if not html then return nil, err end
    local title = Html.decode(html:match('<meta property="og:title" content="([^"]+)%s*%-%s*Mê Truyện') or "")
    title = title:match("^%s*(.-)%s*$")
    if title == "" then title = text(Html.select(html, ".info-title")) end
    if title == "" then return nil, CHANGED end
    local series = { id = id, source_id = M.id, title = title, url = SITE .. path,
        description = text(Html.select(html, ".desc-text")), chapters = {} }
    if series.description == "" then series.description = nil end
    local image = html:match('<meta property="og:image" content="([^"]+)"')
    if image then series.cover = Html.decode(image) end
    local author = html:match("<strong>Tác giả:</strong>%s*<span>%s*(.-)%s*</span>")
    author = author and text(author) or ""
    if author ~= "" and author ~= "Đang cập nhật" then series.author = author end
    local tags = {}
    local tags_html = Html.select(html, ".tags")
    if tags_html then
        for _, a in ipairs(Html.elements(tags_html, "a")) do
            local name = text(a.inner)
            if name ~= "" then tags[#tags + 1] = name end
        end
    end
    if #tags > 0 then series.tags = tags end
    local toc = Html.select(html, ".chapter-table")
    if not toc then return nil, CHANGED end
    local seen = {}
    for _, a in ipairs(Html.elements(toc, "a")) do
        local href = Html.decode(Html.attr(a.attrs, "href") or "")
        local ignored, cid = M.parseRef(href)
        if cid and not seen[cid] then
            seen[cid] = true
            local chapter_title = a.inner:match('<span class="hidden%-sm hidden%-xs">(.-)</span>') or a.inner
            series.chapters[#series.chapters + 1] = { id = cid, series_id = id,
                url = href, title = text(chapter_title) }
        end
    end
    if #series.chapters == 0 then return nil, CHANGED end
    table.sort(series.chapters, function(a, b)
        local an, bn = tonumber(a.id:match("^(%d+)")), tonumber(b.id:match("^(%d+)"))
        if an and bn and an ~= bn then return an < bn end
        if an and not bn then return true end
        if bn and not an then return false end
        return a.id < b.id
    end)
    for i, chapter in ipairs(series.chapters) do chapter.index = i end
    series.volumes = { { title = _("Chương"), chapters = series.chapters } }
    return series
end

function M.getChapter(ref)
    local source = type(ref) == "table" and (ref.url or ref.ref) or ref
    local ignored, cid, path = M.parseRef(source)
    if not cid or not path or type(ref) ~= "table" or type(ref.series_id) ~= "string" then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local html, err, code = request(path)
    if not html then
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    -- The chapter page links back to its series: reject a chapter served for a
    -- different story instead of saving the wrong text.
    local backlink = Html.elements(html, "#post-category-link", true)[1]
    local story = backlink and Html.attr(backlink.attrs, "href")
    if not story or M.parseRef(Html.decode(story)) ~= ref.series_id then return nil, CHANGED end
    local content = Html.select(html, "#view-chapter")
    if not content or text(content) == "" then
        if html:find("post%-password%-form") then return { skipped = _("Chương đã khóa.") } end
        return { skipped = _("Chương trống.") }
    end
    if content:find("post%-password%-form") then return { skipped = _("Chương đã khóa.") } end
    content = content:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</p>", "\n")
    local paragraphs = {}
    for line in content:gmatch("[^\r\n]+") do
        line = text(line)
        if line ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    return { title = ref.title, html = table.concat(paragraphs, "\n") }
end

return M
