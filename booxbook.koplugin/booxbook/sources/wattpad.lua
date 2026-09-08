local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Gzip = require("booxbook.gzip")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local Wattpad = { id = "wattpad", name = "Wattpad", kind = "novel",
    capabilities = { search = true, browse = true, adult = true, login = false } }
local SITE = "https://www.wattpad.com"
local CHANGED = _("API Wattpad đổi — nhập URL truyện hoặc thử lại sau.")

function Wattpad.refId(ref, story)
    if type(ref) == "table" then ref = ref.url or ref.ref or ref.id end
    if type(ref) == "number" then ref = tostring(ref) end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if host ~= "www.wattpad.com" and host ~= "wattpad.com" then return nil end
        ref = path
    end
    local id = ref:match("^(%d+)$")
    if not id then
        local prefix = story and "^/story/" or "^/"
        id = ref:match(prefix .. "(%d+)$") or ref:match(prefix .. "(%d+)[%-?#]")
    end
    return id and #id <= 12 and tonumber(id) > 0 and id or nil
end

local function request(path, json)
    local ok, code, body = Http.get(SITE .. path, { referer = SITE .. "/",
        cookies = Settings.cookie("wattpad"), delay_ms = math.max(1600, Settings.delayMs()) })
    if not ok then
        return nil, string.format(_("Không tải được Wattpad (HTTP %s). Thử lại sau."),
            type(code) == "number" and tostring(code) or "?"), code
    end
    if type(body) ~= "string" then return nil, CHANGED end
    if body:sub(1, 2) == "\031\139" then
        body = Gzip.decode(body, Http.MAX_BODY or 2 * 1024 * 1024)
        if not body then return nil, _("Không giải nén được nội dung Wattpad.") end
    end
    if not json then return body end
    local loaded, Json = pcall(require, "json")
    if not loaded then return nil, _("Không có thư viện JSON của KOReader.") end
    local decoded, data = pcall(Json.decode, body)
    if not decoded or type(data) ~= "table" then return nil, CHANGED end
    return data
end

local function adult(story)
    return story.mature ~= false -- Unknown metadata stays hidden with the default setting.
end

local function list(path, page)
    page = tonumber(page or 1)
    if not page or page < 1 or page >= 100000 or page % 1 ~= 0 then return nil, _("Trang không hợp lệ.") end
    local data, err = request(path .. "&limit=20&offset=" .. (page - 1) * 20, true)
    if not data then return nil, CHANGED .. " " .. err end
    if type(data.stories) ~= "table" then return nil, CHANGED end
    local items = {}
    -- Live 2026-09-08: v3 lists and v4 search both return stories[], id, title, cover, mature.
    for _, story in ipairs(data.stories) do
        if type(story) ~= "table" then return nil, CHANGED end
        local id = Wattpad.refId(story.id, true)
        if not id or type(story.title) ~= "string" then return nil, CHANGED end
        if Settings.adultContent() or not adult(story) then
            items[#items + 1] = { name = story.title, title = story.title, ref = id,
                url = SITE .. "/story/" .. id, cover = type(story.cover) == "string" and story.cover or nil }
        end
    end
    return { items = items, has_more = #data.stories == 20 }
end

function Wattpad.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    local encoded = query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
    -- /api/v3/stories?query= without language=19 returns English tag-similar stories, not title hits.
    return list("/v4/search/stories?query=" .. encoded .. "&language=19", page)
end

function Wattpad.browse(kind, page)
    kind = kind or "hot"
    if kind ~= "hot" and kind ~= "featured" and kind ~= "new" then return nil, _("Kiểu danh sách không hợp lệ.") end
    return list("/api/v3/stories?filter=" .. kind .. "&language=19", page)
end

function Wattpad.getSeries(ref)
    local id = Wattpad.refId(ref, true)
    if not id then return nil, _("URL truyện Wattpad không hợp lệ.") end
    local data, err = request("/api/v3/stories/" .. id, true)
    if not data then return nil, err end
    if Wattpad.refId(data.id, true) ~= id or type(data.title) ~= "string" or type(data.parts) ~= "table" then
        return nil, CHANGED
    end
    if adult(data) and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt hoặc chưa rõ phân loại.") end
    local chapters, seen = {}, {}
    for _, part in ipairs(data.parts) do
        if type(part) ~= "table" then return nil, CHANGED end
        local part_id = Wattpad.refId(part.id, false)
        if not part_id or type(part.title) ~= "string" then return nil, CHANGED end
        if not part.draft and not part.deleted and not seen[part_id] then
            seen[part_id] = true
            chapters[#chapters + 1] = { id = part_id, url = SITE .. "/" .. part_id,
                series_id = id, title = part.title, index = #chapters + 1, adult = adult(data),
                locked = part.locked == true or part.paid == true or part.isPaid == true }
        end
    end
    return { id = id, source_id = "wattpad", title = data.title, url = SITE .. "/story/" .. id,
        adult = adult(data), author = type(data.user) == "table" and data.user.name or nil,
        cover = type(data.cover) == "string" and data.cover or nil,
        description = type(data.description) == "string" and data.description or nil,
        tags = type(data.tags) == "table" and data.tags or nil,
        chapters = chapters, volumes = { { title = _("Chương"), chapters = chapters } } }
end

function Wattpad.getChapter(ref)
    local id = Wattpad.refId(ref, false)
    if not id then return nil, _("URL chương Wattpad không hợp lệ.") end
    if type(ref) ~= "table" or ref.adult == nil then
        return nil, _("Mở mục lục truyện trước khi tải chương.")
    end
    if ref.adult and not Settings.adultContent() then return { skipped = _("Nội dung 18+ đang tắt.") } end
    if ref.locked then return { skipped = _("Chương đã khóa.") } end
    local body, err, code = request("/apiv2/storytext?id=" .. id)
    if not body then
        if code == 401 or code == 404 or code == 410 then return { skipped = err } end
        return nil, err -- 403/429 stop the queue; do not retry each remaining part.
    end
    local lower = body:lower()
    if lower:find("paywall", 1, true) or lower:find("paid%-story") or lower:find("unlock%-part")
        then return { skipped = _("Chương đã khóa.") } end
    if lower:find("<html", 1, true) or lower:find("<form", 1, true)
        or lower:find("^%s*[{%[]") then return nil, CHANGED end
    local paragraphs = {}
    for _, paragraph in ipairs(Html.selectAllInner(Html.stripDangerous(body), "p")) do
        local text = Html.decode(paragraph:gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("<[^>]+>", ""))
        if text:find("%S") then paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(text) .. "</p>" end
    end
    if #paragraphs == 0 then return { skipped = _("Chương trống hoặc đã khóa.") } end
    return { title = ref.title, html = table.concat(paragraphs, "\n") }
end

return Wattpad
