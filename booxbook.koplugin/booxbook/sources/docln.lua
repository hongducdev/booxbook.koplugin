local Html = require("booxbook.html")
local Http = require("booxbook.http")
local Parser = require("booxbook.sources.docln-parser")
local RateLimit = require("booxbook.rate_limit")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local Docln = { id = "docln", name = "DocLN", kind = "novel",
    capabilities = { search = true, browse = true, login = false, adult = true },
    -- One grid screen; larger pages + sync covers were OOMing on device after search.
    LIST_LIMIT = 6 }

local function request(path, valid)
    local homes, saved = {}, Settings.get("docln_home")
    for position, home in ipairs(Parser.homes) do if home == saved then homes[1] = home end end
    for position, home in ipairs(Parser.homes) do if home ~= saved then homes[#homes + 1] = home end end
    for position, home in ipairs(homes) do
        -- One source-wide clock also spaces failover requests to different hosts.
        local delay = math.max(1500, Settings.delayMs())
        RateLimit.wait("docln", delay)
        local ok, code, html = Http.get(home .. path, { delay_ms = delay, cookies = Settings.cookie("docln") })
        html = html or ""
        local recognized = valid(html)
        -- Cloudflare also injects challenge-platform scripts into normal readable pages.
        local challenge = not recognized and (html:find("cf%-chl%-") or html:find("Just a moment", 1, true)
            or html:find("challenge-platform", 1, true))
        if code == 429 then return nil, _("DocLN giới hạn lượt tải (429). Thử lại sau."), code end
        if code == 404 or code == 410 then return nil, _("Chương/truyện không còn tồn tại."), code end
        if not challenge and (code == 401 or code == 403) then return nil, _("Trang yêu cầu đăng nhập hoặc đã khóa."), code end
        if ok and not challenge and not Html.select(html, ".error-page") and recognized then
            Settings.set("docln_home", home)
            return html
        end
    end
    return nil, _("Không đọc được DocLN. Bật Wi-Fi / thử tên miền khác / thử lại sau.")
end

local function pageNumber(page)
    page = tonumber(page or 1)
    return page and page >= 1 and page < 100000 and page % 1 == 0 and page
end

local function listPage(path, page)
    local html, err = request(path, function(body)
        return Html.select(body, ".sect-body") ~= nil or Html.select(body, Parser.selectors.results) ~= nil
    end)
    if not html then return nil, err end
    local result = Parser.search(html, page, Settings.adultContent())
    if #result.items > Docln.LIST_LIMIT then
        local items = {}
        for i = 1, Docln.LIST_LIMIT do
            items[i] = result.items[i]
        end
        result.items = items
        result.has_more = true
    end
    return result
end

function Docln.search(query, page)
    page = pageNumber(page)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" or #query > 300 or not page then return nil, _("Từ khóa hoặc trang không hợp lệ.") end
    local escaped = query:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end)
    return listPage("/tim-kiem?keywords=" .. escaped .. "&page=" .. page, page)
end

-- Browse mirrors Nekori LNHako popularNovels (/tim-kiem-nang-cao); kind: latest|popular.
function Docln.browse(kind, page)
    page = pageNumber(page)
    if not page then return nil, _("Trang không hợp lệ.") end
    local sort = "capnhat"
    if kind == "popular" then
        sort = "top"
    elseif kind ~= nil and kind ~= "latest" then
        return nil, _("Kiểu danh sách không hợp lệ.")
    end
    -- Keep the same filter keys LNHako sends so the advanced-search form stays stable.
    local path = "/tim-kiem-nang-cao?author=&illustrator=&title=&status=0&sapxep="
        .. sort .. "&seriestype=0&page=" .. page
    return listPage(path, page)
end

function Docln.getSeries(ref)
    local path = Parser.path(ref)
    if not path or path:match("/c%d+") then return nil, _("Đường dẫn truyện không hợp lệ.") end
    local html, err = request(path, function(body) return Html.select(body, Parser.selectors.name) ~= nil end)
    if not html then return nil, err end
    local series = Parser.series(html, path)
    if not series then return nil, _("Không đọc được thông tin truyện.") end
    if series.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
    return series
end

function Docln.getChapter(ref)
    local path = Parser.path(ref)
    if not path or not path:match("/c%d+") then return nil, _("Đường dẫn chương không hợp lệ.") end
    if type(ref) == "table" then
        if ref.adult and not Settings.adultContent() then return { skipped = _("Nội dung 18+ đang tắt.") } end
        if ref.locked then return { skipped = _("Chương đã khóa.") } end
    end
    local html, err, code = request(path, function(body)
        return Html.select(body, Parser.selectors.content) ~= nil or body:find("đăng nhập", 1, true) ~= nil
    end)
    if not html then
        if code == 404 or code == 410 or code == 401 or code == 403 then return { skipped = err } end
        return nil, err
    end
    local body, reason = Parser.chapter(html)
    if not body then
        local messages = { locked = _("Chương đã khóa hoặc cần đăng nhập."),
            encoded = _("Định dạng nội dung chương chưa được hỗ trợ."), empty = _("Chương không có nội dung chữ."),
            changed = _("Trang chương đã thay đổi hoặc cần đăng nhập.") }
        return { skipped = messages[reason] }
    end
    return { title = type(ref) == "table" and ref.title or Parser.text(Html.select(html, "h4")), html = body }
end

return Docln
