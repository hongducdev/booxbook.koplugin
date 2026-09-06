local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Glyphs = require("booxbook.sources.sangtacviet-glyphs")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end

local Sangtacviet = {
    id = "sangtacviet",
    name = "Sangtacviet",
    kind = "novel",
    capabilities = { search = true, browse = true, adult = false, login = false },
}

local DOMAINS = {
    "https://sangtacviet.com",
    "https://sangtacviet.app",
    "https://sangtacviet.xyz",
    "https://sangtacviet.pro",
}
local CHANGED = _("API Sangtacviet đổi — nhập URL /truyen/… hoặc thử lại sau.")
local UNREACHABLE = _("Không kết nối được Sangtacviet (DNS/mạng). Thử VPN hoặc tên miền khác.")
local DELAY_MS = 2000
local HOST_OK = { fanqie = true, qidian = true, sangtac = true, dich = true,
    uukanshu = true, faloo = true, sfacg = true, ciweimao = true }

local session = { home = nil, cookies = nil, primed = false }

function Sangtacviet.enabled(settings)
    if settings and settings.sangtacvietEnabled then
        return settings.sangtacvietEnabled() == true
    end
    return Settings.sangtacvietEnabled()
end

local function delay()
    return math.max(DELAY_MS, Settings.delayMs())
end

local function encodeQuery(value)
    return tostring(value or ""):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", c:byte())
    end)
end

local function parseLooseJson(text)
    if type(text) ~= "string" or text == "" then return nil end
    local loaded, Json = pcall(require, "json")
    if not loaded then return nil end
    local ok, data = pcall(Json.decode, text)
    if ok and type(data) == "table" then return data end
    local start = text:find("{", 1, true)
    if not start then return nil end
    ok, data = pcall(Json.decode, text:sub(start))
    if ok and type(data) == "table" then return data end
    return nil
end

local function extractInlineCookies(html)
    local cookies = {}
    if type(html) ~= "string" then return cookies end
    for assignment in html:gmatch("[Dd]ocument%.cookie%s*=%s*[\"']([^\"';]+)") do
        local name, value = assignment:match("^%s*([^=]+)%s*=%s*(.*)$")
        if name and value and name ~= "" then
            -- Keep token only; drop "; path=/" (same rule as Http.parseSetCookie).
            cookies[name] = (value:match("^([^;]*)") or ""):match("^%s*(.-)%s*$")
        end
    end
    return cookies
end

local function mergeJar(base, extra)
    return Http.mergeCookies(base or {}, extra or {})
end

local function stvHeaders(referer)
    return {
        ["x-stv-transport"] = "app",
        ["x-requested-with"] = "com.sangtacviet.mobilereader",
        referer = referer,
    }
end

local function isNetworkFail(code)
    if type(code) ~= "string" then return false end
    local lower = code:lower()
    return lower:find("timeout", 1, true) or lower:find("closed", 1, true)
        or lower:find("refused", 1, true) or lower:find("host", 1, true)
        or lower:find("dns", 1, true) or lower:find("connect", 1, true)
end

local function home()
    if session.home and session.home:match("^https://sangtacviet%.") then
        return session.home
    end
    local cached = Settings.get("stv_home")
    if type(cached) == "string" and cached:match("^https://sangtacviet%.") then
        return cached:gsub("/+$", "")
    end
    return DOMAINS[1]
end

local function useHome(url)
    url = (url or ""):gsub("/+$", "")
    if session.home ~= url then
        session.home, session.cookies, session.primed = url, nil, false
    end
end

local function rememberHome(url)
    url = (url or ""):gsub("/+$", "")
    if url ~= "" then Settings.set("stv_home", url) end
    useHome(url)
end

local function withHome(fn)
    local order = {}
    local preferred = home()
    order[#order + 1] = preferred
    for _, domain in ipairs(DOMAINS) do
        if domain ~= preferred then order[#order + 1] = domain end
    end
    local last_err
    for _, domain in ipairs(order) do
        useHome(domain)
        local ok, result, err = fn(domain)
        if ok then
            rememberHome(domain)
            return result
        end
        last_err = err or result
        if not isNetworkFail(err) and type(err) == "string" and not err:find("HTTP", 1, true) then
            -- Non-network application errors should not rotate domains forever.
            if not tostring(err):find("Không tải", 1, true) then
                return nil, last_err
            end
        end
        session.primed, session.cookies = false, nil
    end
    if isNetworkFail(last_err) then return nil, UNREACHABLE end
    return nil, last_err or UNREACHABLE
end

local function request(method, url, opts)
    opts = opts or {}
    local headers = {}
    for k, v in pairs(opts.headers or {}) do headers[k] = v end
    local cookies = mergeJar({
        transmode = "name",
        foreignlang = "vi",
    }, opts.cookies or session.cookies)
    local user = Settings.cookie("sangtacviet")
    if user ~= "" then cookies = mergeJar(cookies, user) end
    local req = {
        url = url,
        method = method,
        headers = headers,
        cookies = cookies,
        referer = opts.referer or headers.referer,
        body = opts.body,
        delay_ms = delay(),
    }
    local ok, code, body, response_headers, jar
    if method == "POST" then
        ok, code, body, response_headers, jar = Http.post(url, opts.body or "", req)
    else
        ok, code, body, response_headers, jar = Http.get(url, req)
    end
    if jar then session.cookies = mergeJar(session.cookies, jar) end
    return ok, code, body, response_headers, jar
end

function Sangtacviet.parseRef(ref)
    if type(ref) == "table" then
        if ref.host and ref.bookid then
            return {
                host = ref.host,
                sty = tostring(ref.sty or "1"),
                bookid = tostring(ref.bookid),
                chapter_id = ref.chapter_id and tostring(ref.chapter_id) or nil,
            }
        end
        ref = ref.url or ref.ref or ref.id or ref.path
    end
    if type(ref) ~= "string" then return nil end
    ref = ref:match("^%s*(.-)%s*$")
    if ref == "" then return nil end
    if ref:match("^https?://") then
        local host, path = ref:match("^https?://([^/]+)(/.*)$")
        if not host or not host:lower():find("sangtacviet", 1, true) then return nil end
        ref = path
    end
    local host, sty, bookid, chapter = ref:match("^/truyen/([%w_%-]+)/([%w_%-]+)/([%w_%-]+)/([%w_%-]+)/?$")
    if host and bookid then
        return { host = host, sty = sty, bookid = bookid, chapter_id = chapter }
    end
    host, sty, bookid = ref:match("^/truyen/([%w_%-]+)/([%w_%-]+)/([%w_%-]+)/?$")
    if host and bookid then
        return { host = host, sty = sty, bookid = bookid }
    end
    host, bookid = ref:match("^([%w_%-]+)%-([%w_%-]+)$")
    if host and bookid and HOST_OK[host] then
        return { host = host, sty = "1", bookid = bookid }
    end
    return nil
end

function Sangtacviet.seriesId(parts)
    if not parts then return nil end
    return parts.host .. "-" .. parts.bookid
end

local function seriesUrl(parts, base)
    base = (base or home()):gsub("/+$", "")
    local path = string.format("/truyen/%s/%s/%s/", parts.host, parts.sty or "1", parts.bookid)
    if parts.chapter_id then
        path = path .. parts.chapter_id .. "/"
    end
    return base .. path, path
end

local function parseSearchHtml(html, base)
    local items = {}
    if type(html) ~= "string" then return items end
    for block in html:gmatch("<a%s+[^>]*class%s*=%s*[\"'][^\"']*booksearch[^\"']*[\"'][^>]*>.-</a>") do
        local href = block:match("[Hh][Rr][Ee][Ff]%s*=%s*[\"']([^\"']+)[\"']")
        local title = block:match("[Cc]lass%s*=%s*[\"'][^\"']*searchbooktitle[^\"']*[\"'][^>]*>(.-)<")
            or block:match("searchbooktitle[^>]*>(.-)<")
        local cover = block:match("<[Ii][Mm][Gg][^>]*[Ss][Rr][Cc]%s*=%s*[\"']([^\"']+)[\"']")
        if href and title then
            title = Html.decode(title:gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
            local parts = Sangtacviet.parseRef(href)
            if parts and title ~= "" then
                local url = seriesUrl(parts, base)
                if cover and not cover:match("^https?://") then
                    cover = base .. (cover:sub(1, 1) == "/" and cover or "/" .. cover)
                end
                items[#items + 1] = {
                    name = title,
                    title = title,
                    ref = Sangtacviet.seriesId(parts),
                    url = url,
                    cover = cover,
                    host = parts.host,
                    bookid = parts.bookid,
                    sty = parts.sty,
                }
            end
        end
    end
    return items
end

-- Live 2026-09-06: with Accept preferring JSON, searchBooks returns
-- {"code":100,"list":[{host,id,tname,thumb,...}]}; HTML a.booksearch when Accept is text/html.
local function parseSearchJson(body, base)
    local data = parseLooseJson(body)
    if not data or tonumber(data.code) ~= 100 or type(data.list) ~= "table" then
        return nil
    end
    local items = {}
    for _, book in ipairs(data.list) do
        if type(book) == "table" then
            local host = type(book.host) == "string" and book.host:match("^[%w_%-]+$")
            local bookid = book.id ~= nil and tostring(book.id):match("^[%w_%-]+$")
            local title = book.tname or book.hname or book.name
            if type(title) == "string" then
                title = Html.decode(title:gsub("%s+", " "):match("^%s*(.-)%s*$") or "")
            else
                title = nil
            end
            if host and bookid and title and title ~= "" then
                local parts = { host = host, sty = "1", bookid = bookid }
                local cover = book.thumb
                if type(cover) == "string" and cover ~= "" and not cover:match("^https?://") then
                    cover = base .. (cover:sub(1, 1) == "/" and cover or "/" .. cover)
                elseif type(cover) ~= "string" or cover == "" then
                    cover = nil
                end
                items[#items + 1] = {
                    name = title,
                    title = title,
                    ref = Sangtacviet.seriesId(parts),
                    url = seriesUrl(parts, base),
                    cover = cover,
                    host = host,
                    bookid = bookid,
                    sty = "1",
                }
            end
        end
    end
    return items
end

local function parseSearchResults(body, base)
    if type(body) ~= "string" or body == "" then return {} end
    local trimmed = body:match("^%s*(.-)%s*$") or body
    if trimmed:sub(1, 1) == "{" or trimmed:sub(1, 3) == "\239\187\191" then
        local items = parseSearchJson(body, base)
        if items then return items end
    end
    return parseSearchHtml(body, base)
end

local function listBooks(sort, query, page)
    page = tonumber(page or 1)
    if not page or page < 1 or page >= 100000 or page % 1 ~= 0 then
        return nil, _("Trang không hợp lệ.")
    end
    return withHome(function(base)
        local path = "/io/searchtp/searchBooks?find="
            .. encodeQuery(query or "")
            .. "&findinname=" .. encodeQuery(query or "")
            .. "&minc=0&sort=" .. encodeQuery(sort or "")
            .. "&tag=&p=" .. tostring(page)
        local headers = stvHeaders(base .. "/")
        -- Prefer HTML like the browser UI; still parse JSON if the CDN returns it.
        headers["Accept"] = "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8"
        local ok, code, body = request("GET", base .. path, {
            headers = headers,
            referer = base .. "/",
        })
        if not ok then
            return false, nil, isNetworkFail(code) and code
                or string.format(_("Không tải được Sangtacviet (HTTP %s)."), tostring(code or "?"))
        end
        local items = parseSearchResults(body, base)
        return true, { items = items, has_more = #items >= 24 }
    end)
end

function Sangtacviet.search(query, page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 then return nil, _("Từ khóa không hợp lệ.") end
    local parts = Sangtacviet.parseRef(query)
    if parts then
        return { items = { {
            name = Sangtacviet.seriesId(parts),
            title = Sangtacviet.seriesId(parts),
            ref = Sangtacviet.seriesId(parts),
            url = seriesUrl(parts),
            host = parts.host,
            bookid = parts.bookid,
            sty = parts.sty,
        } }, has_more = false }
    end
    return listBooks("", query, page)
end

function Sangtacviet.browse(kind, page)
    kind = kind or "update"
    local sort = "update"
    if kind == "view" or kind == "popular" then sort = "view"
    elseif kind == "update" or kind == "latest" or kind == "new" then sort = "update"
    else return nil, _("Kiểu danh sách không hợp lệ.") end
    return listBooks(sort, "", page)
end

local function primeSession(parts)
    local base = home()
    local chapter_url = seriesUrl({
        host = parts.host,
        sty = parts.sty or "1",
        bookid = parts.bookid,
        chapter_id = parts.chapter_id or "1",
    }, base)
    session.cookies = mergeJar({
        transmode = "name",
        foreignlang = "vi",
    }, {})
    local ok, code, body = request("GET", chapter_url, {
        referer = base .. "/",
        cookies = session.cookies,
    })
    if not ok then
        return nil, isNetworkFail(code) and UNREACHABLE
            or string.format(_("Không tải được trang chương (HTTP %s)."), tostring(code or "?"))
    end
    session.cookies = mergeJar(session.cookies, extractInlineCookies(body))
    local ac = session.cookies and session.cookies._ac or ""
    local api = string.format(
        "%s/index.php?bookid=%s&h=%s&c=%s&ngmar=readc&sajax=readchapter&sty=1&exts=",
        base, encodeQuery(parts.bookid), encodeQuery(parts.host),
        encodeQuery(parts.chapter_id or "1"))
    ok, code, body = request("POST", api, {
        referer = chapter_url,
        body = ac,
        cookies = session.cookies,
        headers = { ["x-requested-with"] = "XmlHttpRequest" },
    })
    if not ok then
        if isNetworkFail(code) then return nil, UNREACHABLE end
        return nil, string.format(_("Không khởi tạo phiên Sangtacviet (HTTP %s)."), tostring(code or "?"))
    end
    local token = session.cookies and session.cookies._ac or ""
    if token == "" then
        return nil, _("Không lấy được cookie phiên Sangtacviet.")
    end
    session.primed = true
    return true
end

local function ensureSession(parts)
    if session.primed and session.home == home() and session.cookies and session.cookies._ac then
        return true
    end
    return primeSession(parts)
end

function Sangtacviet.getSeries(ref)
    local parts = Sangtacviet.parseRef(ref)
    if not parts then return nil, _("URL truyện Sangtacviet không hợp lệ.") end
    return withHome(function(base)
        local page_url = seriesUrl(parts, base)
        local headers = stvHeaders(page_url)
        local info_url = string.format("%s/mobile/bookinfo.php?host=%s&hid=%s",
            base, encodeQuery(parts.host), encodeQuery(parts.bookid))
        local ok, code, body = request("GET", info_url, { headers = headers, referer = page_url })
        if not ok then
            return false, nil, isNetworkFail(code) and code
                or string.format(_("Không tải được thông tin truyện (HTTP %s)."), tostring(code or "?"))
        end
        local info = parseLooseJson(body)
        if not info or tonumber(info.code) ~= 100 or type(info.book) ~= "table" then
            return false, nil, CHANGED
        end
        local book = info.book
        local title = tostring(book.tname or book.name or ""):match("^%s*(.-)%s*$")
        if not title or title == "" then return false, nil, CHANGED end
        local list_url = string.format(
            "%s/index.php?ngmar=chapterlist&h=%s&bookid=%s&sajax=getchapterlist&force=true",
            base, encodeQuery(parts.host), encodeQuery(parts.bookid))
        ok, code, body = request("GET", list_url, { headers = headers, referer = page_url })
        if not ok then
            return false, nil, isNetworkFail(code) and code
                or string.format(_("Không tải được mục lục (HTTP %s)."), tostring(code or "?"))
        end
        local list = parseLooseJson(body)
        if not list then return false, nil, CHANGED end
        if tonumber(list.code) == 2 then
            return false, nil, _("Truyện đã bị xóa hoặc không có nội dung.")
        end
        if tonumber(list.code) ~= 1 or type(list.data) ~= "string" then
            return false, nil, CHANGED
        end
        local chapters, seen = {}, {}
        for row in (list.data .. "-//-"):gmatch("(.-)%-//%-") do
            row = row:match("^%s*(.-)%s*$")
            if row ~= "" then
                local cols = {}
                for col in (row .. "-/-"):gmatch("(.-)%-/%-") do
                    cols[#cols + 1] = col
                end
                if #cols >= 3 then
                    local sty, chapter_id, name = cols[1], cols[2], cols[3]
                    chapter_id = chapter_id and chapter_id:match("^%s*(.-)%s*$")
                    name = name and Html.decode(name:match("^%s*(.-)%s*$") or "")
                    local vip = cols[4] and cols[4]:match("^%s*(.-)%s*$") or nil
                    if chapter_id and chapter_id ~= "" and name and name ~= "" then
                        local key = chapter_id .. "|" .. name
                        if not seen[key] then
                            seen[key] = true
                            local locked = vip and vip ~= "" and vip ~= "unvip"
                            local chapter_parts = {
                                host = parts.host,
                                sty = sty,
                                bookid = parts.bookid,
                                chapter_id = chapter_id,
                            }
                            chapters[#chapters + 1] = {
                                id = chapter_id,
                                url = seriesUrl(chapter_parts, base),
                                series_id = Sangtacviet.seriesId(parts),
                                title = locked and ("[VIP] " .. name) or name,
                                index = #chapters + 1,
                                locked = locked and true or false,
                                host = parts.host,
                                sty = sty,
                                bookid = parts.bookid,
                                chapter_id = chapter_id,
                            }
                        end
                    end
                end
            end
        end
        if parts.host == "uukanshu" then
            local reversed = {}
            for i = #chapters, 1, -1 do
                reversed[#reversed + 1] = chapters[i]
                reversed[#reversed].index = #reversed
            end
            chapters = reversed
        end
        local cover = book.thumb
        if type(cover) == "string" and cover ~= "" and not cover:match("^https?://") then
            cover = base .. (cover:sub(1, 1) == "/" and cover or "/" .. cover)
        end
        local id = Sangtacviet.seriesId(parts)
        return true, {
            id = id,
            source_id = "sangtacviet",
            title = title,
            url = page_url,
            author = type(book.hauthor) == "string" and book.hauthor or nil,
            cover = type(cover) == "string" and cover or nil,
            host = parts.host,
            bookid = parts.bookid,
            sty = parts.sty,
            chapters = chapters,
            volumes = { { title = _("Chương"), chapters = chapters } },
        }
    end)
end

local SKIP_CODES = { ["1"] = true, ["12"] = true, ["13"] = true }
local STOP_CODES = {
    ["5"] = true, ["7"] = true, ["15"] = true, ["18"] = true,
    ["19"] = true, ["21"] = true, ["101"] = true,
}

local function chapterMessage(code)
    code = tostring(code or "")
    if code == "1" then return _("Chương trống hoặc không tồn tại.") end
    if code == "7" then return _("Sangtacviet giới hạn tốc độ. Dừng tải.") end
    if code == "12" then return _("Chương chưa mua.") end
    if code == "13" then return _("Chưa đăng nhập Sangtacviet.") end
    if code == "21" then return _("Sangtacviet yêu cầu captcha. Dừng tải.") end
    if code == "101" then return _("Nguồn này không phải tiểu thuyết chữ.") end
    if STOP_CODES[code] then return _("Sangtacviet trả lỗi " .. code .. ". Dừng tải.") end
    return CHANGED
end

local function normalizeBody(host, raw)
    raw = tostring(raw or "")
    raw = raw:gsub("%[img[=%d,]*%].-%[/img%]", "")
    if host == "sangtac" or host == "dich" then
        raw = Glyphs.decode(raw)
    end
    raw = Html.stripDangerous(raw)
    raw = raw:gsub("<%s*[Bb][Rr]%s*/?%s*>", "\n")
    raw = raw:gsub("<%s*/%s*[PpDdHhLl][^>]*>", "\n")
    raw = raw:gsub("<%s*[Ii][^>]*>", ""):gsub("<%s*/%s*[Ii]%s*>", "")
    raw = raw:gsub("<[^>]+>", "")
    raw = Html.decode(raw)
    local paragraphs = {}
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("[%s\t]+", " "):match("^%s*(.-)%s*$") or ""
        if line ~= "" then
            paragraphs[#paragraphs + 1] = "<p>" .. Html.escape(line) .. "</p>"
        end
    end
    return table.concat(paragraphs, "\n")
end

function Sangtacviet.getChapter(ref)
    local parts = Sangtacviet.parseRef(ref)
    if not parts or not parts.chapter_id then
        return nil, _("URL chương Sangtacviet không hợp lệ.")
    end
    if type(ref) == "table" and ref.locked then
        return { skipped = _("Chương VIP — bỏ qua.") }
    end
    local primed, prime_err = ensureSession(parts)
    if not primed then return nil, prime_err end
    local base = home()
    local chapter_url = seriesUrl(parts, base)
    local api = string.format(
        "%s/index.php?bookid=%s&h=%s&c=%s&ngmar=readc&sajax=readchapter&sty=1&exts=",
        base, encodeQuery(parts.bookid), encodeQuery(parts.host), encodeQuery(parts.chapter_id))
    local function postChapter()
        local ac = session.cookies and session.cookies._ac or ""
        return request("POST", api, {
            referer = chapter_url,
            body = ac,
            cookies = session.cookies,
        })
    end
    local ok, code, body = postChapter()
    if not ok then
        if code == 403 or code == 429 then
            return nil, string.format(_("Sangtacviet chặn tải (HTTP %s). Dừng tải."), tostring(code))
        end
        if isNetworkFail(code) then return nil, UNREACHABLE end
        return nil, string.format(_("Không tải được chương (HTTP %s)."), tostring(code or "?"))
    end
    -- Plan: empty-after-retry stops the queue (first empty may be a blip).
    if type(body) ~= "string" or body == "" then
        ok, code, body = postChapter()
        if not ok or type(body) ~= "string" or body == "" then
            return nil, _("Sangtacviet trả chương trống. Dừng tải.")
        end
    end
    local data = parseLooseJson(body)
    if not data then return nil, CHANGED end
    local status = tostring(data.code or "")
    if status == "0" and type(data.data) == "string" and data.data ~= "" then
        local host = tostring(data.bookhost or parts.host):lower()
        local html = normalizeBody(host, data.data)
        if html == "" then return { skipped = _("Chương trống hoặc không tồn tại.") } end
        return {
            title = type(data.chaptername) == "string" and data.chaptername or ref.title,
            html = html,
        }
    end
    if status == "0" then
        return { skipped = _("Chương trống hoặc không tồn tại.") }
    end
    if SKIP_CODES[status] then
        return { skipped = chapterMessage(status) }
    end
    if STOP_CODES[status] or status == "7" or status == "21" then
        return nil, chapterMessage(status)
    end
    return nil, chapterMessage(status)
end

-- Test hook: expose empty-body/no-referer failure shape without network.
function Sangtacviet._normalizeBody(host, raw)
    return normalizeBody(host, raw)
end

function Sangtacviet._parseLooseJson(text)
    return parseLooseJson(text)
end

function Sangtacviet._resetSession()
    session.home, session.cookies, session.primed = nil, nil, false
end

return Sangtacviet
