local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local Upload = { MAX_BYTES = 512 * 1024 * 1024 }
local formats = { epub=true, pdf=true, cbz=true, cbr=true, fb2=true, mobi=true,
    azw=true, azw3=true, djvu=true, djv=true, txt=true, rtf=true, doc=true, chm=true }

function Upload.safeFilename(name)
    if type(name) ~= "string" then return end
    if #name == 0 or #name > 220 or name:find('[%z\1-\31\127/\\:*?"<>|]')
        or name:match("^[%. ]") or name:match("[%. ]$") then return end
    local stem = name:match("^([^%.]+)"):upper()
    if stem == "CON" or stem == "PRN" or stem == "AUX" or stem == "NUL"
        or stem:match("^COM%d$") or stem:match("^LPT%d$") then return end
    if not formats[(name:match("%.([^.]+)$") or ""):lower()] then return end
    return name
end

function Upload.filename(encoded)
    if type(encoded) ~= "string" or encoded:gsub("%%(%x%x)", ""):find("%%") then return end
    return Upload.safeFilename(encoded:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local function urldecode(encoded)
    if type(encoded) ~= "string" or encoded:gsub("%%(%x%x)", ""):find("%%") then return end
    return encoded:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
end

function Upload.safeRelativePath(encoded_path)
    if type(encoded_path) ~= "string" or #encoded_path > 1024 then return end
    -- Reject encoded directory separators and encoded null bytes before decoding
    if encoded_path:find("%%2[Ff]") or encoded_path:find("%%5[Cc]") or encoded_path:find("%%00") then return end
    local path = urldecode(encoded_path)
    if not path or path == "" then return end
    if path:find("\0", 1, true) or path:find("\\", 1, true) then return end
    if path:sub(1, 1) == "/" or path:match("^%a:") then return end
    local parts = {}
    for segment in path:gmatch("[^/]+") do
        if segment == "." or segment == ".." or segment == "" then return end
        parts[#parts + 1] = segment
    end
    if #parts == 0 or table.concat(parts, "/") ~= path then return end
    return path
end


local function isPrivateIPv4(address)
    local first, second = address:match("^(%d+)%.(%d+)%.")
    first, second = tonumber(first), tonumber(second)
    if not first then return false end
    return first == 10 or first == 127
        or (first == 172 and second >= 16 and second <= 31)
        or (first == 192 and second == 168)
        or (first == 100 and second >= 64 and second <= 127) -- carrier NAT / mesh overlay
        or (first == 169 and second == 254) -- link local
end

-- true/false once the value is a usable address; nil when it cannot be classified.
-- Callers treat nil as "unknown" rather than "remote".
function Upload.isLanAddress(value)
    if type(value) ~= "string" then return nil end
    local address = value:match("^(%d+%.%d+%.%d+%.%d+):%d+$") or value:match("^(%d+%.%d+%.%d+%.%d+)$")
    if address then return isPrivateIPv4(address) end
    if value == "::1" or value == "localhost" or value:match("^%[::1%]") then return true end
    if value:match("^f[cd]%x%x:") or value:match("^fe80:") then return true end
end

-- A phone on the same Wi-Fi normally shares our subnet. Globally routable sources are
-- accepted only when they share our two leading octets, which keeps a corporate LAN
-- with public addresses working while internet scanners stay refused.
function Upload.isLocalPeer(peer, addresses)
    local lan = Upload.isLanAddress(peer)
    if lan ~= false then return true end
    local address = peer:match("^(%d+%.%d+%.%d+%.%d+)")
    local prefix = address and address:match("^(%d+%.%d+%.)")
    if not prefix then return true end
    for _, local_address in ipairs(addresses or {}) do
        if type(local_address) == "string" and local_address:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function authorityPort(authority)
    if type(authority) ~= "string" then return end
    return tonumber(authority:match(":(%d+)$"))
end

-- Accept any address literal the user may type (plus localhost) on the server's own
-- port: the phone must work through every interface of the device. Domain names stay
-- rejected, so a page that rebinds its host to this address is never served.
local function hostAllowed(host, authority, port)
    if type(host) ~= "string" then return false end
    if host == authority then return true end
    if not port then return false end
    local name, host_port = host:match("^(.-):(%d+)$")
    if not name or tonumber(host_port) ~= port then return false end
    return name == "localhost" or name == "[::1]" or name:match("^%d+%.%d+%.%d+%.%d+$") ~= nil
end

local function originAllowed(origin, authority, port)
    if origin == nil then return true end
    if type(origin) ~= "string" then return false end
    local host = origin:match("^http://(.+)$")
    return host ~= nil and hostAllowed(host, authority, port)
end

local function route(fields, headers)
    fields.host = headers.host
    fields.origin = headers.origin
    return fields
end

function Upload.headers(raw, authority, token)
    local first, rest = raw:match("^([^\r\n]+)\r\n(.*)$")
    if not first then return nil, 400, _("Yêu cầu không hợp lệ.") end
    local method, path = first:match("^(%u+) ([^ ]+) HTTP/1%.[01]$")
    if not method or rest:gsub("[^\r\n]+\r\n", "") ~= "\r\n" then
        return nil, 400, _("Header không hợp lệ.")
    end
    local headers = {}
    for line in rest:gmatch("([^\r\n]+)\r\n") do
        local key, value = line:match("^([%w-]+):[ \t]*(.-)[ \t]*$")
        if not key or headers[key:lower()] then return nil, 400, _("Header không hợp lệ.") end
        headers[key:lower()] = value
    end
    local port = authorityPort(authority)
    -- A cross-site navigation (a link tapped in a chat app) carries no Origin and must
    -- still reach the page, so only state-changing requests treat it as an attack.
    local cross_site_write = method == "POST" and headers["sec-fetch-site"] == "cross-site"
    if not hostAllowed(headers.host, authority, port)
        or not originAllowed(headers.origin, authority, port)
        or cross_site_write then
        return nil, 403, _("Hãy mở đúng địa chỉ:") .. " http://" .. tostring(authority) .. "/"
    end
    if headers["transfer-encoding"] or headers.expect then
        return nil, 400, _("Kiểu truyền không được hỗ trợ.")
    end
    if method == "GET" and path == "/" then return route({ page = true }, headers) end
    if method == "GET" and path == "/opds" then return route({ opds = true }, headers) end
    if method == "GET" then
        local encoded = path:match("^/opds/file/(.+)$")
        if encoded then
            local relpath = Upload.safeRelativePath(encoded)
            if not relpath then return nil, 404, _("Không tìm thấy.") end
            return route({ opds_file = relpath }, headers)
        end
    end
    if method == "POST" and path == "/queue" then
        if headers["x-booxbook-token"] ~= token then return nil, 401, _("Mã phiên không đúng. Xem lại máy đọc sách.") end
        local length = tonumber(headers["content-length"] or "")
        if not length or length < 1 or length > 2048 then return nil, 413, _("URL quá dài.") end
        return route({ queue = true, remaining = length }, headers)
    end
    if method ~= "POST" or path ~= "/upload" then return nil, 404, _("Không tìm thấy.") end
    if headers["x-booxbook-token"] ~= token then return nil, 401, _("Mã phiên không đúng. Xem lại máy đọc sách.") end
    local length = headers["content-length"] or ""
    if not length:match("^%d+$") then return nil, 411, _("Thiếu kích thước file.") end
    length = tonumber(length)
    if length < 1 or length > Upload.MAX_BYTES then return nil, 413, _("File phải từ 1 byte đến 512 MiB.") end
    local name = Upload.filename(headers["x-file-name"])
    if not name then return nil, 400, _("Tên hoặc định dạng sách không hợp lệ.") end
    return route({ name = name, remaining = length }, headers)
end

function Upload.begin(request, dir, suffix)
    request.path = dir .. "/" .. request.name
    request.temp = dir .. "/.upload-" .. suffix .. ".part"
    if lfs.symlinkattributes(request.path) then return nil, 409, _("Sách trùng tên. Hãy đổi tên rồi gửi lại.") end
    if lfs.symlinkattributes(request.temp) then return nil, 409, _("File tạm đã tồn tại. Hãy mở lại phiên nhận.") end
    request.file = io.open(request.temp, "wb")
    if not request.file then return nil, 500, _("Không tạo được file. Kiểm tra bộ nhớ/quyền ghi.") end
    request.owns_temp = true
    return true
end

function Upload.abort(request)
    if request.file then request.file:close(); request.file = nil end
    if request.owns_temp then os.remove(request.temp); request.owns_temp = nil end
end

function Upload.write(request, chunk)
    if #chunk > request.remaining then return nil, _("Kích thước file không khớp.") end
    if not request.file:write(chunk) then return nil, _("Ghi file thất bại. Kiểm tra dung lượng trống.") end
    request.remaining = request.remaining - #chunk
    if request.remaining > 0 then return true end
    local closed = request.file:close()
    request.file = nil
    if not closed then return nil, _("Không hoàn tất được file.") end
    if lfs.symlinkattributes(request.path) then return nil, _("Sách trùng tên. File cũ được giữ nguyên.") end
    if not os.rename(request.temp, request.path) then return nil, _("Không lưu được sách vào thư viện.") end
    request.owns_temp = nil
    return true, "complete"
end

return Upload
