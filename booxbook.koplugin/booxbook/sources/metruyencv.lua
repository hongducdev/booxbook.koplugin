local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local Crypto = require("booxbook.sources.metruyencv-crypto")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local M = { id = "metruyencv", name = "MeTruyenCV", kind = "novel",
    capabilities = { search = true, browse = true, login = false } }
local SITE, API = "https://metruyencv.com", "https://backend.metruyencv.com/api/"
local CHANGED = _("API MeTruyenCV thay đổi hoặc dữ liệu không hợp lệ.")

function M.refId(ref, story)
    if type(ref) == "table" then ref = ref.ref or ref.id or ref.url end
    if type(ref) == "number" then ref = tostring(ref) end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if host ~= "metruyencv.com" and host ~= "www.metruyencv.com" then return nil end
        ref = path
    end
    ref = (ref:match("^[^?#]+") or ""):gsub("/+$", "")
    local prefix = story and "^/truyen/" or "^/truyen/chuong/"
    local id = ref:match("^(%d+)$") or ref:match(prefix .. "(%d+)$")
    return id and #id <= 12 and tonumber(id) > 0 and id or nil
end

local function request(path)
    local signed, signature = pcall(Crypto.signature, path)
    if not signed then return nil, _("Không khởi tạo được mã hóa MeTruyenCV. Kiểm tra bản KOReader.") end
    local ok, code, body = Http.get(API .. path, { referer = SITE .. "/",
        delay_ms = math.max(1600, Settings.delayMs()), headers = {
            Accept = "application/json", ["X-App"] = "MeTruyenChu", ["X-Signature"] = signature } })
    if not ok then return nil, string.format(_("Không tải được MeTruyenCV (HTTP %s)."), tostring(code)), code end
    local loaded, Json = pcall(require, "json")
    if not loaded then return nil, _("Không có thư viện JSON của KOReader.") end
    local decoded, data = pcall(Json.decode, body)
    if not decoded or type(data) ~= "table" or data.success ~= true or type(data.data) ~= "table" then
        return nil, CHANGED
    end
    return data
end

local function more(data, page)
    local pagination = data.pagination
    if type(pagination) ~= "table" then return false end
    return (tonumber(pagination.last) or page) > page
end

local function cover(book)
    local poster = type(book.poster) == "table" and book.poster or {}
    return poster["600"] or poster["300"] or poster.default
end

local function list(params, page)
    page = tonumber(page or 1)
    if not page or page < 1 or page >= 100000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local data, err = request("books?limit=20&include=creator&page=" .. page .. "&" .. params)
    if not data then return nil, err end
    local items = {}
    for _, book in ipairs(data.data) do
        if type(book) ~= "table" or not M.refId(book.id, true) or type(book.name) ~= "string" then return nil, CHANGED end
        items[#items + 1] = { ref = tostring(book.id), title = book.name, name = book.name,
            url = SITE .. "/truyen/" .. book.id, cover = cover(book) }
    end
    local has_more = #data.data == 20
    if data.pagination then has_more = more(data, page) end
    return { items = items, has_more = has_more }
end

function M.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    return list("filter[keyword]=" .. query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end), page)
end

function M.browse(kind, page)
    local sorts = { latest = "-updated_at", popular = "-view_count" }
    if not sorts[kind or "latest"] then return nil, _("Kiểu danh sách không hợp lệ.") end
    return list("filter[state]=published&sort=" .. sorts[kind or "latest"], page)
end

local function locked(ch)
    return ch.locked == true or ch.is_locked == true or ch.is_vip == true or ch.is_vip == 1
        or ch.vip == true or ch.vip == 1 or ch.is_paid == true or (tonumber(ch.price) or 0) > 0
end

function M.getSeries(ref)
    local id = M.refId(ref, true)
    if not id then return nil, _("Nhập ID truyện MeTruyenCV hoặc tìm bằng tên truyện.") end
    local data, err = request("books/" .. id)
    if not data then return nil, err end
    local book = data.data
    if M.refId(book.id, true) ~= id or type(book.name) ~= "string" then return nil, CHANGED end
    local chapters, seen, page = {}, {}, 1
    repeat
        data, err = request("chapters?filter[book_id]=" .. id .. "&filter[type]=published&page=" .. page)
        if not data then return nil, err end
        local added = 0
        for _, ch in ipairs(data.data) do
            if type(ch) ~= "table" or not M.refId(ch.id) or type(ch.name) ~= "string"
                or not tonumber(ch.index) then return nil, CHANGED end
            local cid = tostring(ch.id)
            if not seen[cid] then
                seen[cid], added = true, added + 1
                chapters[#chapters + 1] = { id = cid, title = ch.name, order = tonumber(ch.index),
                    url = SITE .. "/truyen/chuong/" .. cid, series_id = id, locked = locked(ch) }
            end
        end
        if more(data, page) and (added == 0 or page >= 1000) then return nil, CHANGED end
        page = page + 1
    until not more(data, page - 1)
    table.sort(chapters, function(a, b)
        if a.order == b.order then return tonumber(a.id) < tonumber(b.id) end
        return a.order < b.order
    end)
    for i, ch in ipairs(chapters) do ch.index = i end
    local author = type(book.author) == "table" and book.author or {}
    local author_name = author.name
    if type(author.local_name) == "string" and author.local_name ~= "" then
        author_name = (author_name or "") .. " (" .. author.local_name .. ")"
    end
    if not author_name and type(book.creator) == "table" then author_name = book.creator.name end
    local tags = {}
    for _, genre in ipairs(type(book.genres) == "table" and book.genres or {}) do
        if type(genre) == "table" and type(genre.name) == "string" then tags[#tags + 1] = genre.name end
    end
    return { id = id, source_id = M.id, title = book.name, url = SITE .. "/truyen/" .. id,
        author = author_name, description = type(book.synopsis) == "string" and book.synopsis or nil,
        cover = cover(book), tags = tags, chapters = chapters,
        volumes = { { title = _("Chương"), chapters = chapters } } }
end

function M.getChapter(ref)
    local id = M.refId(ref, false)
    if not id or type(ref) ~= "table" or not M.refId(ref.series_id, true) then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local ok, hash = pcall(Crypto.hash)
    if not ok then return nil, _("Không khởi tạo được mã hóa MeTruyenCV.") end
    local data, err, code = request("chapters/" .. id .. "?hash=" .. hash)
    if not data then
        -- login=false: 401 is a bad signature/hash, not a locked chapter.
        if code == 404 then return { skipped = err } end
        return nil, err
    end
    local ch = data.data
    if locked(ch) then return { skipped = _("Chương đã khóa.") } end
    if M.refId(ch.id) ~= id then return nil, CHANGED end
    if M.refId(ch.book_id, true) ~= ref.series_id then return nil, CHANGED end
    if type(ch.content) ~= "string" or ch.content == "" then return { skipped = _("Chương trống hoặc đã khóa.") } end
    local decoded, content = pcall(Crypto.decrypt, ch.content, hash)
    if not decoded then return nil, _("Không giải mã được chương MeTruyenCV.") end
    local paragraphs = {}
    for line in content:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống.") } end
    return { title = ref.title, html = table.concat(paragraphs, "\n") }
end

return M
