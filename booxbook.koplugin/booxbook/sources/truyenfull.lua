local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local ok_gettext, gettext = pcall(require, "gettext")
local _ = ok_gettext and gettext or function(s) return s end
local T = { id = "truyenfull", name = "Truyện Full", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE = "https://truyenfull.live"
local CHANGED = _("Không đọc được HTML Truyện Full; trang có thể đã đổi hoặc yêu cầu xác minh.")
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
local function hasLock(s)
    return s and (s:find("Mở khóa", 1, true) or s:find("mở khóa", 1, true))
end
function T.parseRef(ref)
    if type(ref) == "table" then ref = ref.url or ref.ref end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if host ~= "truyenfull.live" then return nil end
        ref = path
    end
    ref = ref:match("^[^?#]+") or ""
    local slug = ref:match("^/([%w%-]+)/?$")
    if slug and #slug <= 180 then return slug end
    local book, chapter = ref:match("^/([%w%-]+)/chuong%-(%d+)/?$")
    if book and #book <= 180 and #chapter <= 12 and tonumber(chapter) > 0 then return book, chapter, ref end
end
local function request(path)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then return nil, string.format(_("Không tải được Truyện Full (HTTP %s)."), tostring(code)), code end
    if type(body) ~= "string" then return nil, CHANGED end
    return Html.stripDangerous(body)
end
local function hasMore(html, page)
    local want = tostring(page + 1)
    for n in html:gmatch("/trang%-(%d+)/") do
        if n == want then return true end
    end
    for n in html:gmatch("[?&]page=(%d+)") do
        if n == want then return true end
    end
end
local function list(path, page, allow_empty)
    page = tonumber(page or 1)
    if not page or page < 1 or page > 10000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local html, err = request(path)
    if not html then return nil, err end
    local items, seen = {}, {}
    local lists = Html.elements(html, ".list-truyen")
    if #lists == 0 then lists = { { inner = html } } end
    for _, list_el in ipairs(lists) do
        for _, row in ipairs(Html.elements(list_el.inner, ".row")) do
            local name = Html.select(row.inner, ".truyen-title") or ""
            for _, a in ipairs(Html.elements(name, "a")) do
                local slug, chapter = T.parseRef(Html.decode(Html.attr(a.attrs, "href") or ""))
                if slug and not chapter and not seen[slug] then
                    seen[slug] = true
                    items[#items + 1] = { ref = "/" .. slug .. "/", url = SITE .. "/" .. slug .. "/",
                        title = text(a.inner), name = text(a.inner),
                        cover = row.inner:match('data%-image="([^"]+)"') }
                end
            end
        end
    end
    if #items == 0 and page == 1 and not allow_empty then return nil, CHANGED end
    return { items = items, has_more = hasMore(html, page) }
end
function T.browse(kind, page)
    if kind ~= nil and kind ~= "latest" and kind ~= "popular" then return nil, _("Kiểu danh sách không hợp lệ.") end
    local folder = kind == "popular" and "truyen-hot" or "truyen-moi"
    page = tonumber(page or 1) or 1
    return list("/danh-sach/" .. folder .. "/trang-" .. page .. "/", page)
end
function T.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    page = tonumber(page or 1) or 1
    return list("/tim-kiem?tukhoa=" .. encode(query) .. "&page=" .. page, page, true)
end
function T.getSeries(ref)
    local slug, chapter = T.parseRef(ref)
    if not slug or chapter then return nil, _("URL truyện Truyện Full không hợp lệ.") end
    local path = "/" .. slug .. "/"
    local html, err = request(path)
    if not html then return nil, err end
    local book = Html.select(html, ".book") or ""
    local img = book:match("<img([^>]+)>") or ""
    local title = text(Html.attr(img, "alt") or "")
    if title == "" then title = text(Html.select(html, ".truyen-title") or "") end
    if title == "" then return nil, CHANGED end
    local series = { id = slug, source_id = T.id, title = title, url = SITE .. path,
        description = text(Html.select(html, ".desc-text")), chapters = {} }
    local cover = Html.attr(img, "src")
    if cover and not cover:lower():match("%.webp") then series.cover = cover end
    for _, a in ipairs(Html.elements(html, "a")) do
        if Html.attr(a.attrs, "itemprop") == "author" then series.author = text(a.inner); break end
    end
    local seen, page = {}, 1
    while true do
        local toc = Html.select(html, "#list-chapter")
        if not toc then
            local parts = {}
            for _, el in ipairs(Html.elements(html, ".list-chapter")) do parts[#parts + 1] = el.inner end
            toc = #parts > 0 and table.concat(parts, "\n") or nil
        end
        if not toc then return nil, CHANGED end
        local added = 0
        for _, a in ipairs(Html.elements(toc, "a")) do
            local book_id, cid, chapter_path = T.parseRef(Html.decode(Html.attr(a.attrs, "href") or ""))
            if book_id == slug and cid and not seen[cid] then
                seen[cid], added = true, added + 1
                series.chapters[#series.chapters + 1] = { id = cid, series_id = slug,
                    url = SITE .. chapter_path, title = text(a.inner),
                    locked = classHas(a.attrs, "locked") }
            end
        end
        if not hasMore(html, page) then break end
        if added == 0 or page >= 1000 then return nil, CHANGED end
        page = page + 1
        html, err = request(path .. "trang-" .. page .. "/")
        if not html then return nil, err end
    end
    if #series.chapters == 0 then return nil, CHANGED end
    table.sort(series.chapters, function(a, b) return tonumber(a.id) < tonumber(b.id) end)
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
    local content = Html.select(html, "#chapter-c")
    if not content or text(content) == "" then
        if hasLock(html) then return { skipped = _("Chương đã khóa.") } end
        return { skipped = _("Chương trống.") }
    end
    if hasLock(content) and (content:find("<form") or content:find("<button")) then
        return { skipped = _("Chương đã khóa.") }
    end
    content = content:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</p>", "\n")
    local paragraphs = {}
    for line in content:gmatch("[^\r\n]+") do
        line = text(line)
        if line ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    return { title = ref.title, html = table.concat(paragraphs, "\n") }
end
return T
