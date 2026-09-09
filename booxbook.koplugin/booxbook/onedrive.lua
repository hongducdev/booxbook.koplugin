local Json = require("json")
local lfs = require("libs/libkoreader-lfs")

local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")
local Upload = require("booxbook.wifi-upload")

local OneDrive = { MAX_BYTES = Upload.MAX_BYTES, MAX_PAGES = 20 }
local LOGIN = "https://login.microsoftonline.com/common/oauth2/v2.0/"
local GRAPH = "https://graph.microsoft.com/v1.0/"
local SCOPE = "Files.Read offline_access"

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
    if type(data.error) == "table" then return data.error.message or fallback end
    return data.error_description or data.error or fallback
end

local function clearPending()
    for _, key in ipairs({ "onedrive_device_code", "onedrive_user_code",
            "onedrive_verification_uri", "onedrive_device_expires" }) do
        Settings.set(key, key:match("expires$") and 0 or "")
    end
end

local function saveToken(data)
    Settings.set("onedrive_access_token", data.access_token)
    Settings.set("onedrive_access_expires", os.time() + (tonumber(data.expires_in) or 3600))
    if trim(data.refresh_token) ~= "" then
        Settings.set("onedrive_refresh_token", data.refresh_token)
    end
    clearPending()
    return data.access_token
end

local function tokenRequest(fields)
    local ok, code, body = Http.post(LOGIN .. "token", form(fields), { delay_ms = 0, verify_tls = true })
    local data = decode(body)
    if ok and data and trim(data.access_token) ~= "" then return saveToken(data) end
    return nil, message(data, "Microsoft OAuth failed (" .. tostring(code) .. ")."), data
end

function OneDrive.clientId()
    return trim(Settings.get("onedrive_client_id"))
end

local function clientId()
    local value = OneDrive.clientId()
    if not value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
        return nil, "Microsoft client ID phải là UUID hợp lệ."
    end
    return value
end

function OneDrive.hasAuth()
    return trim(Settings.get("onedrive_access_token")) ~= ""
        or trim(Settings.get("onedrive_refresh_token")) ~= ""
end

function OneDrive.clearAuth()
    clearPending()
    Settings.set("onedrive_access_token", "")
    Settings.set("onedrive_refresh_token", "")
    Settings.set("onedrive_access_expires", 0)
end

function OneDrive.loginInfo()
    if (tonumber(Settings.get("onedrive_device_expires")) or 0) <= os.time() then return nil end
    local code = trim(Settings.get("onedrive_user_code"))
    local uri = trim(Settings.get("onedrive_verification_uri"))
    if code == "" or uri == "" then return nil end
    return { user_code = code, verification_uri = uri }
end

function OneDrive.startLogin()
    local client_id, client_err = clientId()
    if not client_id then return nil, client_err end
    clearPending()
    local ok, code, body = Http.post(LOGIN .. "devicecode", form({
        { "client_id", client_id }, { "scope", SCOPE },
    }), { delay_ms = 0, verify_tls = true })
    local data = decode(body)
    if not ok or not data or trim(data.device_code) == "" or trim(data.user_code) == ""
        or trim(data.verification_uri) == "" then
        return nil, message(data, "Không bắt đầu được đăng nhập Microsoft (" .. tostring(code) .. ").")
    end
    Settings.set("onedrive_device_code", data.device_code)
    Settings.set("onedrive_user_code", data.user_code)
    Settings.set("onedrive_verification_uri", data.verification_uri)
    Settings.set("onedrive_device_expires", os.time() + (tonumber(data.expires_in) or 900))
    return { user_code = data.user_code, verification_uri = data.verification_uri }
end

function OneDrive.finishLogin()
    local client_id, client_err = clientId()
    local device_code = trim(Settings.get("onedrive_device_code"))
    if not client_id then return nil, client_err end
    if device_code == "" then return nil, "Chưa bắt đầu đăng nhập OneDrive." end
    if (tonumber(Settings.get("onedrive_device_expires")) or 0) <= os.time() then
        clearPending()
        return nil, "Mã đăng nhập đã hết hạn. Hãy tạo mã mới."
    end
    local token, err, data = tokenRequest({
        { "client_id", client_id },
        { "grant_type", "urn:ietf:params:oauth:grant-type:device_code" },
        { "device_code", device_code },
    })
    if not token and data and data.error == "authorization_pending" then
        return nil, "Bạn chưa hoàn tất đăng nhập trên trình duyệt."
    end
    if not token and data and (data.error == "expired_token" or data.error == "authorization_declined") then
        clearPending()
    end
    return token, err
end

function OneDrive.refreshAccess()
    local client_id, client_err = clientId()
    if not client_id then return nil, client_err end
    local refresh = trim(Settings.get("onedrive_refresh_token"))
    if refresh == "" then return nil, "OneDrive chưa đăng nhập." end
    local token, err, data = tokenRequest({ { "client_id", client_id },
        { "grant_type", "refresh_token" }, { "refresh_token", refresh }, { "scope", SCOPE } })
    if not token and data and data.error == "invalid_grant" then OneDrive.clearAuth() end
    return token, err
end

function OneDrive.accessToken()
    local token = trim(Settings.get("onedrive_access_token"))
    if token ~= "" and (tonumber(Settings.get("onedrive_access_expires")) or 0) > os.time() + 60 then return token end
    return OneDrive.refreshAccess()
end

function OneDrive.graph(url, retry)
    if type(url) ~= "string" or url:sub(1, #GRAPH) ~= GRAPH then return nil, "Microsoft Graph URL không hợp lệ." end
    local token, err = OneDrive.accessToken()
    if not token then return nil, err end
    local ok, code, body = Http.get(url,
        { headers = { authorization = "Bearer " .. token }, delay_ms = 0, verify_tls = true })
    if not ok and code == 401 and retry ~= false then
        Settings.set("onedrive_access_token", "")
        local refreshed, refresh_err = OneDrive.refreshAccess()
        if not refreshed then return nil, refresh_err end
        return OneDrive.graph(url, false)
    end
    local data = decode(body)
    if not ok or not data then return nil, message(data, "Microsoft Graph lỗi (" .. tostring(code) .. ").") end
    return data
end

function OneDrive.list(folder_id)
    local url = folder_id and (GRAPH .. "me/drive/items/" .. encode(folder_id) .. "/children")
        or (GRAPH .. "me/drive/root/children")
    local items = {}
    for _ = 1, OneDrive.MAX_PAGES do
        local data, err = OneDrive.graph(url)
        if not data then return nil, err end
        if type(data.value) ~= "table" then return nil, "Danh sách OneDrive không hợp lệ." end
        for _, item in ipairs(data.value) do
            if type(item) == "table" and trim(item.id) ~= "" and trim(item.name) ~= "" then
                if type(item.folder) == "table" then
                    items[#items + 1] = { id = item.id, name = item.name, folder = true }
                elseif Upload.safeFilename(item.name) then
                    items[#items + 1] = { id = item.id, name = item.name, size = tonumber(item.size) }
                end
            end
        end
        url = data["@odata.nextLink"]
        if not url then break end
        if type(url) ~= "string" or url:sub(1, #GRAPH) ~= GRAPH then return nil, "Trang kế tiếp OneDrive không hợp lệ." end
    end
    if url then return nil, "Thư mục OneDrive có quá nhiều trang." end
    table.sort(items, function(a, b)
        if a.folder ~= b.folder then return a.folder == true end
        return a.name:lower() < b.name:lower()
    end)
    return items
end

function OneDrive.download(item)
    local name = item and Upload.safeFilename(item.name)
    local size = item and tonumber(item.size)
    if not name or not item.id or not size or size < 1 or size > OneDrive.MAX_BYTES then
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
    local token, err = OneDrive.accessToken()
    if not token then return nil, err end
    local url = GRAPH .. "me/drive/items/" .. encode(item.id) .. "/content"
    local function fetch(current)
        return Http.downloadToFile(url, pending,
            { headers = { authorization = "Bearer " .. current }, max_body = OneDrive.MAX_BYTES,
                delay_ms = 0, verify_tls = true })
    end
    local ok, code = fetch(token)
    if not ok and code == 401 then
        token, err = OneDrive.refreshAccess()
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

return OneDrive
