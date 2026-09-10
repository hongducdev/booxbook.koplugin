-- Google Drive download-only (mirrors OneDrive pattern).
-- Device flow + Drive API v3 files.list/files.get. Network calls go
-- through booxbook.http with TLS verification; pure parsers are unit-tested.
local Json = require("json")
local lfs = require("libs/libkoreader-lfs")

local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Upload = require("booxbook.wifi-upload")

local GDrive = { MAX_BYTES = 512 * 1024 * 1024, MAX_PAGES = 20 }
local DEVICE = "https://oauth2.googleapis.com/device/code"
local TOKEN = "https://oauth2.googleapis.com/token"
local API = "https://www.googleapis.com/drive/v3/"
local SCOPE = "https://www.googleapis.com/auth/drive.readonly https://www.googleapis.com/auth/drive.file"
local FOLDER_MIME = "application/vnd.google-apps.folder"

local FORMATS = { epub = true, pdf = true, cbz = true, cbr = true, fb2 = true,
    mobi = true, azw = true, azw3 = true, djvu = true, djv = true,
    txt = true, rtf = true, doc = true, chm = true }

local function trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function encode(value)
    return (tostring(value or ""):gsub("([^%w%-%.%_%~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

local function form(fields)
    local parts = {}
    for _, field in ipairs(fields) do
        parts[#parts + 1] = encode(field[1]) .. "=" .. encode(field[2])
    end
    return table.concat(parts, "&")
end

local function decode(body)
    local ok, data = pcall(Json.decode, body or "")
    if ok and type(data) == "table" then return data end
end

local function message(data, fallback)
    if type(data) ~= "table" then return fallback end
    if type(data.error) == "table" then
        return data.error.message or data.error_description or fallback
    end
    return data.error_description or data.error or fallback
end

local function clearPending()
    for _, key in ipairs({ "gdrive_device_code", "gdrive_user_code",
            "gdrive_verification_uri", "gdrive_device_expires" }) do
        Settings.set(key, key:match("expires$") and 0 or "")
    end
end

local function saveToken(data)
    Settings.set("gdrive_access_token", data.access_token)
    Settings.set("gdrive_access_expires", os.time() + (tonumber(data.expires_in) or 3600))
    if trim(data.refresh_token) ~= "" then
        Settings.set("gdrive_refresh_token", data.refresh_token)
    end
    clearPending()
    return data.access_token
end

local function tokenRequest(fields)
    local ok, code, body = Http.post(TOKEN, form(fields), { delay_ms = 0, verify_tls = true })
    local data = decode(body)
    if ok and data and trim(data.access_token) ~= "" then return saveToken(data) end
    return nil, message(data, "Google OAuth failed (" .. tostring(code) .. ")."), data
end

function GDrive.validClientId(value)
    value = trim(value)
    if value == "" or #value > 256 then return false end
    return value:match("%.apps%.googleusercontent%.com$") ~= nil
end

function GDrive.clientId()
    return trim(Settings.get("gdrive_client_id"))
end

function GDrive.hasAuth()
    return trim(Settings.get("gdrive_access_token")) ~= ""
        or trim(Settings.get("gdrive_refresh_token")) ~= ""
end

function GDrive.clearAuth()
    clearPending()
    Settings.set("gdrive_access_token", "")
    Settings.set("gdrive_refresh_token", "")
    Settings.set("gdrive_access_expires", 0)
end

function GDrive.deviceUrl() return DEVICE end
function GDrive.tokenUrl() return TOKEN end
function GDrive.apiUrl() return API end
function GDrive.folderMime() return FOLDER_MIME end

function GDrive.loginInfo()
    if (tonumber(Settings.get("gdrive_device_expires")) or 0) <= os.time() then return nil end
    local code = trim(Settings.get("gdrive_user_code"))
    local uri = trim(Settings.get("gdrive_verification_uri"))
    if code == "" or uri == "" then return nil end
    return { user_code = code, verification_uri = uri }
end

function GDrive.startLogin()
    local client_id = GDrive.clientId()
    if not GDrive.validClientId(client_id) then
        return nil, "Google client ID phải dạng xxx.apps.googleusercontent.com."
    end
    clearPending()
    local ok, code, body = Http.post(DEVICE, form({
        { "client_id", client_id }, { "scope", SCOPE },
    }), { delay_ms = 0, verify_tls = true })
    local data = decode(body)
    if not ok or not data or trim(data.device_code) == "" or trim(data.user_code) == ""
        or trim(data.verification_url or data.verification_uri) == "" then
        return nil, message(data, "Không bắt đầu được đăng nhập Google (" .. tostring(code) .. ").")
    end
    Settings.set("gdrive_device_code", data.device_code)
    Settings.set("gdrive_user_code", data.user_code)
    Settings.set("gdrive_verification_uri", data.verification_url or data.verification_uri)
    Settings.set("gdrive_device_expires", os.time() + (tonumber(data.expires_in) or 900))
    return { user_code = data.user_code,
        verification_uri = data.verification_url or data.verification_uri }
end

function GDrive.finishLogin()
    local client_id = GDrive.clientId()
    local device_code = trim(Settings.get("gdrive_device_code"))
    if not GDrive.validClientId(client_id) then
        return nil, "Google client ID phải dạng xxx.apps.googleusercontent.com."
    end
    if device_code == "" then return nil, "Chưa bắt đầu đăng nhập Google." end
    if (tonumber(Settings.get("gdrive_device_expires")) or 0) <= os.time() then
        clearPending()
        return nil, "Mã đăng nhập đã hết hạn. Hãy tạo mã mới."
    end
    local token, err, data = tokenRequest({
        { "client_id", client_id },
        { "grant_type", "urn:ietf:params:oauth:grant-type:device_code" },
        { "device_code", device_code },
    })
    if not token and data then
        local code = data.error
        if code == "authorization_pending" or code == "slow_down" then
            return nil, "Bạn chưa hoàn tất đăng nhập trên trình duyệt."
        end
        if code == "expired_token" or code == "access_denied" then clearPending() end
    end
    return token, err
end

function GDrive.refreshAccess()
    local client_id = GDrive.clientId()
    if not GDrive.validClientId(client_id) then
        return nil, "Google client ID phải dạng xxx.apps.googleusercontent.com."
    end
    local refresh = trim(Settings.get("gdrive_refresh_token"))
    if refresh == "" then return nil, "Google Drive chưa đăng nhập." end
    local token, err, data = tokenRequest({ { "client_id", client_id },
        { "grant_type", "refresh_token" }, { "refresh_token", refresh } })
    if not token and data and data.error == "invalid_grant" then GDrive.clearAuth() end
    return token, err
end

function GDrive.accessToken()
    local token = trim(Settings.get("gdrive_access_token"))
    if token ~= "" and (tonumber(Settings.get("gdrive_access_expires")) or 0) > os.time() + 60 then
        return token
    end
    return GDrive.refreshAccess()
end

function GDrive.allowedName(name)
    if type(name) ~= "string" then return false end
    local ext = (name:match("%.([^.]+)$") or ""):lower()
    return FORMATS[ext] == true and #name <= 220 and not name:match("[/\\]")
end

-- Parse Drive files.list payload into {items, nextPage}.
-- items: {id=, name=, size=, mime=, folder=}. Skips disallowed extensions.
function GDrive.parseList(data)
    if type(data) ~= "table" or type(data.files) ~= "table" then
        return nil, "invalid response"
    end
    local items = {}
    for _, file in ipairs(data.files) do
        if type(file) == "table" and trim(file.id) ~= "" and trim(file.name) ~= "" then
            if file.mimeType == FOLDER_MIME then
                items[#items + 1] = { id = file.id, name = file.name, folder = true }
            elseif GDrive.allowedName(file.name) then
                items[#items + 1] = {
                    id = file.id,
                    name = file.name,
                    size = tonumber(file.size) or 0,
                    mime = file.mimeType or "",
                }
            end
        end
    end
    table.sort(items, function(a, b)
        if a.folder ~= b.folder then return a.folder == true end
        return a.name:lower() < b.name:lower()
    end)
    return { items = items, nextPage = data.nextPageToken }
end

local function apiGet(url, retry)
    if type(url) ~= "string" or url:sub(1, #API) ~= API then
        return nil, "Google Drive URL không hợp lệ."
    end
    local token, err = GDrive.accessToken()
    if not token then return nil, err end
    local ok, code, body = Http.get(url,
        { headers = { authorization = "Bearer " .. token }, delay_ms = 0, verify_tls = true })
    if not ok and code == 401 and retry ~= false then
        Settings.set("gdrive_access_token", "")
        local refreshed, refresh_err = GDrive.refreshAccess()
        if not refreshed then return nil, refresh_err end
        return apiGet(url, false)
    end
    local data = decode(body)
    if not ok or not data then
        return nil, message(data, "Google Drive lỗi (" .. tostring(code) .. ").")
    end
    return data
end

local function uploadReauthError()
    GDrive.clearAuth()
    return nil, "Google Drive cần đăng nhập lại để cấp quyền tải lên bản sao lưu."
end

function GDrive.uploadFile(filename, content, mime)
    local name = trim(filename)
    if name == "" or name:find("[/\\]") then return nil, "Tên bản sao lưu không hợp lệ." end
    local token, err = GDrive.accessToken()
    if not token then return nil, err end
    local boundary = "BooxBookBoundary" .. tostring(os.time())
    local metadata = Json.encode({ name = name })
    local body = "--" .. boundary .. "\r\n"
        .. "Content-Type: application/json; charset=UTF-8\r\n\r\n"
        .. metadata .. "\r\n"
        .. "--" .. boundary .. "\r\n"
        .. "Content-Type: " .. (mime or "application/octet-stream") .. "\r\n\r\n"
        .. (content or "") .. "\r\n"
        .. "--" .. boundary .. "--\r\n"
    local ok, code, response = Http.post("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart", body, {
        headers = {
            authorization = "Bearer " .. token,
            ["content-type"] = "multipart/related; boundary=" .. boundary,
        },
        delay_ms = 0,
        verify_tls = true,
    })
    local data = decode(response)
    if ok then return data or true end
    if code == 401 or code == 403 then return uploadReauthError() end
    return nil, message(data, "Không tải bản sao lưu lên Google Drive (" .. tostring(code) .. ").")
end

function GDrive.list(folder_id, page_token)
    local query = "trashed = false"
    if folder_id then
        query = "'" .. tostring(folder_id):gsub("'", "") .. "' in parents and " .. query
    end
    local url = API .. "files?q=" .. encode(query)
        .. "&fields=" .. encode("files(id,name,size,mimeType),nextPageToken")
        .. "&pageSize=100"
    if page_token then url = url .. "&pageToken=" .. encode(page_token) end
    local items = {}
    for _ = 1, GDrive.MAX_PAGES do
        local data, err = apiGet(url)
        if not data then return nil, err end
        local parsed, parse_err = GDrive.parseList(data)
        if not parsed then return nil, parse_err end
        for _, entry in ipairs(parsed.items) do items[#items + 1] = entry end
        if not parsed.nextPage then break end
        url = API .. "files?q=" .. encode(query)
            .. "&fields=" .. encode("files(id,name,size,mimeType),nextPageToken")
            .. "&pageSize=100&pageToken=" .. encode(parsed.nextPage)
    end
    if #items == 0 then return items end
    return items
end

function GDrive.download(item)
    local name = item and Upload.safeFilename(item.name)
    local size = item and tonumber(item.size)
    if not name or not item.id or not size or size < 1 or size > GDrive.MAX_BYTES then
        return nil, "Tên hoặc kích thước sách không hợp lệ."
    end
    local dir = Settings.downloadDir() .. "/received"
    if not Settings.ensureDir(dir) then return nil, "Không tạo được thư mục nhận sách." end
    local stem, extension = name:match("^(.*)(%.[^.]+)$")
    local target, pending
    for suffix = 0, 999 do
        local candidate = suffix == 0 and name or stem .. " (" .. suffix .. ")" .. extension
        target, pending = dir .. "/" .. candidate, dir .. "/." .. candidate .. ".part"
        if not lfs.symlinkattributes(target) and not lfs.symlinkattributes(pending) then break end
        target, pending = nil, nil
    end
    if not target then return nil, "Có quá nhiều sách trùng tên trong thư viện." end
    local token, err = GDrive.accessToken()
    if not token then return nil, err end
    local url = API .. "files/" .. encode(item.id) .. "?alt=media"
    local function fetch(current)
        return Http.downloadToFile(url, pending,
            { headers = { authorization = "Bearer " .. current }, max_body = GDrive.MAX_BYTES,
                delay_ms = 0, verify_tls = true })
    end
    local ok, code = fetch(token)
    if not ok and code == 401 then
        token, err = GDrive.refreshAccess()
        if not token then return nil, err end
        ok, code = fetch(token)
    end
    if not ok then return nil, "Không tải được sách (" .. tostring(code) .. ")." end
    local actual = tonumber(lfs.attributes(pending, "size"))
    if actual ~= size or lfs.symlinkattributes(target) or not os.rename(pending, target) then
        os.remove(pending)
        return nil, actual ~= size and "Kích thước sách tải về không khớp." or "Không lưu được sách vào thư viện."
    end
    return target
end

return GDrive
