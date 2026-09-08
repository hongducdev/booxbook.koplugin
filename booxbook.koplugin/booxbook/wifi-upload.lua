local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local Upload = { MAX_BYTES = 512 * 1024 * 1024 }
local formats = { epub=true, pdf=true, cbz=true, cbr=true, fb2=true, mobi=true,
    azw=true, azw3=true, djvu=true, djv=true, txt=true, rtf=true, doc=true, chm=true }

function Upload.filename(encoded)
    if type(encoded) ~= "string" or encoded:gsub("%%(%x%x)", ""):find("%%") then return end
    local name = encoded:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
    if #name == 0 or #name > 220 or name:find('[%z\1-\31\127/\\:*?"<>|]')
        or name:match("^[%. ]") or name:match("[%. ]$") then return end
    local stem = name:match("^([^%.]+)"):upper()
    if stem == "CON" or stem == "PRN" or stem == "AUX" or stem == "NUL"
        or stem:match("^COM%d$") or stem:match("^LPT%d$") then return end
    if not formats[(name:match("%.([^.]+)$") or ""):lower()] then return end
    return name
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
    if headers.host ~= authority or (headers.origin and headers.origin ~= "http://" .. authority)
        or headers["sec-fetch-site"] == "cross-site" then
        return nil, 403, _("Hãy mở đúng địa chỉ trên máy đọc sách.")
    end
    if headers["transfer-encoding"] or headers.expect then
        return nil, 400, _("Kiểu truyền không được hỗ trợ.")
    end
    if method == "GET" and path == "/" then return { page = true } end
    if method ~= "POST" or path ~= "/upload" then return nil, 404, _("Không tìm thấy.") end
    if headers["x-booxbook-token"] ~= token then return nil, 401, _("Mã phiên không đúng. Xem lại máy đọc sách.") end
    local length = headers["content-length"] or ""
    if not length:match("^%d+$") then return nil, 411, _("Thiếu kích thước file.") end
    length = tonumber(length)
    if length < 1 or length > Upload.MAX_BYTES then return nil, 413, _("File phải từ 1 byte đến 512 MiB.") end
    local name = Upload.filename(headers["x-file-name"])
    if not name then return nil, 400, _("Tên hoặc định dạng sách không hợp lệ.") end
    return { name = name, remaining = length }
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
