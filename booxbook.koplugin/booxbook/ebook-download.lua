local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(s) return s end

-- Saves one ebook file (EPUB/PDF/MOBI/AZW3) from a Google Drive link to
-- <download_dir>/books/<source_id>/ and returns its path, ready for ReaderUI.
-- Drive answers large files with an HTML "virus scan" page instead of the file;
-- that page's own form is followed once (the same request the "Download anyway"
-- button makes), so big PDFs work without a browser.
local Download = {}

Download.MAX_BYTES = 200 * 1024 * 1024
Download.BUDGET_SECONDS = 1800
local SNIFF_BYTES = 512
local MAX_PAGE_BYTES = 256 * 1024
local MAX_CONFIRMS = 2
local MAX_NAME_BYTES = 100

local function allowedHost(url)
    local host = url:match("^https://([^/:?#]+)")
    host = host and host:lower()
    return host == "docs.google.com" or host == "drive.google.com"
        or host == "drive.usercontent.google.com" or (host ~= nil and host:match("%.googleusercontent%.com$") ~= nil)
end

-- What the first bytes say the file is. "html" means Drive sent a page instead.
function Download.sniff(head)
    if type(head) ~= "string" or head == "" then return nil end
    if head:sub(1, 4) == "PK\3\4" then return "epub" end
    if head:sub(1, 4) == "%PDF" then return "pdf" end
    if head:sub(61, 68) == "BOOKMOBI" then return "mobi" end
    local start = head:match("^%s*(.-)$"):sub(1, 15):lower()
    if start:sub(1, 1) == "<" and (start:find("<!doctype", 1, true) or start:find("<html", 1, true)) then
        return "html"
    end
end

local function cutUtf8(value, limit)
    if #value <= limit then return value end
    local stop = limit
    -- Never end on half a UTF-8 sequence: step back to the start of the character.
    while stop > 0 do
        local byte = value:byte(stop + 1)
        if not byte or byte < 0x80 or byte >= 0xC0 then break end
        stop = stop - 1
    end
    return value:sub(1, stop)
end

-- "<title> [<id>]" keeps two editions with the same title apart.
function Download.stem(series)
    local title = tostring(series.title or ""):gsub('[\\/:*?"<>|%c]', " "):gsub("%s+", " ")
    title = cutUtf8(title:match("^[%s%.]*(.-)[%s%.]*$"), MAX_NAME_BYTES)
    local number = tostring(series.id or ""):match("(%d+)$")
    if title == "" then title = tostring(series.id or "ebook") end
    return number and (title .. " [" .. number .. "]") or title
end

function Download.dir(series)
    return Settings.downloadDir() .. "/books/" .. tostring(series.source_id)
end

local function exists(path)
    local handle = io.open(path, "rb")
    if not handle then return false end
    handle:close()
    return true
end

-- KOReader lists and opens ".azw" but rejects ".azw3", although both hold the same
-- MOBI/KF8 container, so AZW3 files are saved as ".azw".
local function savedExt(format)
    local ext = tostring(format):lower()
    return ext == "azw3" and "azw" or ext
end

-- Path of an already saved copy of this format, or nil.
function Download.existing(series, file)
    local path = Download.dir(series) .. "/" .. Download.stem(series) .. "." .. savedExt(file.format)
    if exists(path) then return path end
end

local function encode(value)
    return (value:gsub("([^%w%-_%.~])", function(c) return string.format("%%%02X", c:byte()) end))
end

local function readFile(path, limit)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local data = handle:read(limit)
    handle:close()
    return data
end

-- The "Download anyway" request of Drive's virus-scan page, or nil + why.
function Download.confirmUrl(page)
    if type(page) ~= "string" then return nil, _("Google Drive không trả về file.") end
    if page:find("Quota exceeded", 1, true) or page:find("Too many users", 1, true)
        or page:find("download quota", 1, true) then
        return nil, _("File này đã vượt hạn mức tải của Google Drive; thử lại sau.")
    end
    local form = page:match('<form[^>]-id="download%-form"[^>]->')
    local action = form and Html.decode(Html.attr(form, "action") or "")
    if not action or not allowedHost(action) then
        return nil, _("Google Drive không trả về file (cần đăng nhập hoặc file đã bị chặn).")
    end
    local pairs_out, has_id = {}, false
    for tag in page:gmatch("<input[^>]*>") do
        local name, value = Html.attr(tag, "name"), Html.attr(tag, "value")
        if name and value and name:match("^[%w_]+$") and (Html.attr(tag, "type") or "") == "hidden" then
            pairs_out[#pairs_out + 1] = encode(name) .. "=" .. encode(Html.decode(value))
            has_id = has_id or name == "id"
        end
    end
    if not has_id then return nil, _("Google Drive không trả về file.") end
    return action .. "?" .. table.concat(pairs_out, "&")
end

local function httpError(code)
    if code == "body too large" then
        return string.format(_("File lớn hơn %d MB, không tải."), math.floor(Download.MAX_BYTES / (1024 * 1024)))
    elseif code == "operation-timeout" then
        return _("Hết thời gian tải; thử lại khi mạng ổn định.")
    elseif code == 404 then
        return _("Link tải không còn tồn tại.")
    elseif code == 403 or code == 429 then
        return _("Google Drive đang giới hạn lượt tải; thử lại sau.")
    end
    return string.format(_("Tải không thành công (%s)."), tostring(code))
end

-- Returns (path, ext) on success, nil + message on failure. Run under a budget
-- (Http.runWithBudget(Download.BUDGET_SECONDS, ...)); a book can take minutes.
function Download.fetch(series, file)
    if type(series) ~= "table" or type(file) ~= "table" or type(file.url) ~= "string"
        or not file.url:match("^https://docs%.google%.com/") or not file.format then
        return nil, _("Link tải không hợp lệ.")
    end
    local dir = Download.dir(series)
    if not Settings.ensureDir(dir) then return nil, _("Không tạo được thư mục sách.") end
    local base = dir .. "/" .. Download.stem(series)
    local part = base .. "." .. tostring(file.format):lower() .. ".part"
    local url = file.url
    for _attempt = 1, MAX_CONFIRMS + 1 do
        -- No Referer on purpose: with the book site as referer, Drive answers the
        -- "Download anyway" request with the scan page again, so big files never arrive.
        local ok, code = Http.downloadToFile(url, part, {
            max_body = Download.MAX_BYTES,
            timeout = 60,
            maxtime = Download.BUDGET_SECONDS,
            allow_url = allowedHost,
        })
        if not ok then
            os.remove(part)
            return nil, httpError(code)
        end
        local kind = Download.sniff(readFile(part, SNIFF_BYTES))
        if kind and kind ~= "html" then
            local ext = kind
            if kind == "mobi" and savedExt(file.format) == "azw" then ext = "azw" end
            local final = base .. "." .. ext
            os.remove(final)
            if not os.rename(part, final) then
                os.remove(part)
                return nil, _("Không lưu được file sách.")
            end
            return final, ext
        end
        if not kind then
            os.remove(part)
            return nil, _("File tải về không đúng định dạng sách.")
        end
        local page = readFile(part, MAX_PAGE_BYTES)
        os.remove(part)
        local next_url, why = Download.confirmUrl(page)
        if not next_url then return nil, why end
        url = next_url
    end
    return nil, _("Google Drive liên tục yêu cầu xác nhận.")
end

return Download
