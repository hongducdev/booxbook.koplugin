package.path = "booxbook.koplugin/?.lua;booxbook.koplugin/?/init.lua;" .. package.path

local names = { "json", "libs/libkoreader-lfs", "gettext", "booxbook.http",
    "booxbook.store.settings", "booxbook.wifi-upload", "booxbook.onedrive",
    "booxbook.gdrive" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

package.loaded["libs/libkoreader-lfs"] = { attributes = function() return nil end, symlinkattributes = function() return nil end }
package.loaded.gettext = function(text) return text end
package.loaded["booxbook.wifi-upload"] = {
    MAX_BYTES = 512 * 1024 * 1024,
    safeFilename = function(name)
        if type(name) == "string" and name:match("%.epub$") then return name end
    end,
}

local fixtures = {
    od_device = { device_code = "od-device", user_code = "OD-CODE",
        verification_uri = "https://microsoft.com/devicelogin", expires_in = 900 },
    od_token = { access_token = "od-access", refresh_token = "od-refresh", expires_in = 3600 },
    od_list = { value = { { id = "od-book", name = "Book.epub", size = 7, file = {} } } },
    od_upload = { id = "od-upload", name = "backup.json" },
    od_forbidden = { error = { message = "Access token lacks Files.ReadWrite" } },
    gd_device = { device_code = "gd-device", user_code = "GD-CODE",
        verification_url = "https://accounts.google.com/device", expires_in = 900 },
    gd_token = { access_token = "gd-access", refresh_token = "gd-refresh", expires_in = 3600 },
    gd_list = { files = { { id = "gd-book", name = "Book.epub", size = "9", mimeType = "application/epub+zip" } } },
    gd_upload = { id = "gd-upload", name = "backup.json" },
    gd_forbidden = { error = { message = "Request had insufficient authentication scopes." } },
}
package.loaded.json = {
    decode = function(body)
        assert(fixtures[body], "unexpected JSON fixture: " .. tostring(body))
        return fixtures[body]
    end,
    encode = function(value)
        if type(value) == "table" and value.name then
            return '{"name":"' .. value.name .. '"}'
        end
        return "{}"
    end,
}

local values = {
    onedrive_client_id = "00001111-aaaa-2222-bbbb-3333cccc4444",
    onedrive_access_expires = 0,
    onedrive_device_expires = 0,
    gdrive_client_id = "abc.apps.googleusercontent.com",
    gdrive_access_expires = 0,
    gdrive_device_expires = 0,
}
package.loaded["booxbook.store.settings"] = {
    get = function(key) return values[key] end,
    set = function(key, value) values[key] = value end,
    downloadDir = function() return "@cloud" end,
    ensureDir = function() return true end,
}

local calls = { post = {}, get = {}, put = {} }
local od_put_mode, gd_post_mode = "ok", "ok"
package.loaded["booxbook.http"] = {
    post = function(url, body, opts)
        assert(opts.verify_tls == true, "cloud requests verify TLS")
        calls.post[#calls.post + 1] = { url = url, body = body, opts = opts }
        if url:match("devicecode$") then return true, 200, "od_device" end
        if url == "https://oauth2.googleapis.com/device/code" then return true, 200, "gd_device" end
        if url == "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart" then
            if gd_post_mode == "forbidden" then return false, 403, "gd_forbidden" end
            return true, 200, "gd_upload"
        end
        if url:match("token$") or url == "https://oauth2.googleapis.com/token" then
            if body:find("od%-device", 1, false) then return true, 200, "od_token" end
            return true, 200, "gd_token"
        end
        error("unexpected POST " .. tostring(url))
    end,
    get = function(url, opts)
        assert(opts.verify_tls == true, "list requests verify TLS")
        calls.get[#calls.get + 1] = { url = url, opts = opts }
        if url:sub(1, #"https://graph.microsoft.com/v1.0/") == "https://graph.microsoft.com/v1.0/" then
            return true, 200, "od_list"
        end
        if url:sub(1, #"https://www.googleapis.com/drive/v3/") == "https://www.googleapis.com/drive/v3/" then
            return true, 200, "gd_list"
        end
        error("unexpected GET " .. tostring(url))
    end,
    put = function(url, body, opts)
        assert(opts.verify_tls == true, "upload requests verify TLS")
        calls.put[#calls.put + 1] = { url = url, body = body, opts = opts }
        if od_put_mode == "forbidden" then return false, 403, "od_forbidden" end
        return true, 201, "od_upload"
    end,
}

package.loaded["booxbook.onedrive"] = nil
local OneDrive = require("booxbook.onedrive")
local od_info = assert(OneDrive.startLogin())
assert(od_info.user_code == "OD-CODE" and values.onedrive_device_code == "od-device", "OneDrive device login starts")
assert(calls.post[1].body:find("Files.ReadWrite", 1, true), "OneDrive requests Files.ReadWrite scope")
assert(calls.post[1].body:find("offline_access", 1, true), "OneDrive preserves offline_access scope")
assert(OneDrive.finishLogin() == "od-access", "OneDrive device login finishes")
local od_items = assert(OneDrive.list())
assert(#od_items == 1 and od_items[1].name == "Book.epub", "OneDrive listing still works")
local od_upload = assert(OneDrive.uploadFile("backup.json", "OD-BODY", "application/json"))
assert(od_upload.id == "od-upload", "OneDrive upload parses response")
assert(calls.put[#calls.put].url == "https://graph.microsoft.com/v1.0/me/drive/root:/BooxBook/backup.json:/content",
    "OneDrive uploads with Graph PUT by path")
assert(calls.put[#calls.put].body == "OD-BODY" and calls.put[#calls.put].opts.headers["content-type"] == "application/json",
    "OneDrive PUT sends raw backup body and MIME")
values.onedrive_access_token, values.onedrive_refresh_token = "readonly", "old-refresh"
values.onedrive_access_expires = os.time() + 3600
od_put_mode = "forbidden"
local od_ok, od_err = OneDrive.uploadFile("backup.json", "OD-BODY", "application/json")
assert(not od_ok and od_err:find("đăng nhập lại", 1, true), "OneDrive 403 asks user to re-login")
assert(values.onedrive_access_token == "" and values.onedrive_refresh_token == "", "OneDrive 403 clears stale readonly auth")
od_put_mode = "ok"

package.loaded["booxbook.gdrive"] = nil
local GDrive = require("booxbook.gdrive")
local gd_info = assert(GDrive.startLogin())
assert(gd_info.user_code == "GD-CODE" and values.gdrive_device_code == "gd-device", "Google Drive device login starts")
local gd_scope_body = calls.post[#calls.post].body
assert(gd_scope_body:find("drive.readonly", 1, true), "Google Drive preserves drive.readonly scope")
assert(gd_scope_body:find("drive.file", 1, true), "Google Drive requests drive.file upload scope")
assert(GDrive.finishLogin() == "gd-access", "Google Drive device login finishes")
local gd_items = assert(GDrive.list())
assert(#gd_items == 1 and gd_items[1].name == "Book.epub", "Google Drive listing still works")
local gd_upload = assert(GDrive.uploadFile("backup.json", "GD-BODY", "application/json"))
assert(gd_upload.id == "gd-upload", "Google Drive upload parses response")
local multipart = calls.post[#calls.post]
assert(multipart.url == "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart",
    "Google Drive uses Drive v3 multipart upload endpoint")
assert(multipart.opts.headers["content-type"]:find("multipart/related; boundary=", 1, true),
    "Google Drive upload declares multipart body")
assert(multipart.body:find("Content-Type: application/json; charset=UTF-8", 1, true), "multipart includes metadata part")
assert(multipart.body:find('{"name":"backup.json"}', 1, true), "multipart metadata names backup")
assert(multipart.body:find("Content-Type: application/json", 1, true) and multipart.body:find("GD-BODY", 1, true),
    "multipart includes backup content")
values.gdrive_access_token, values.gdrive_refresh_token = "readonly", "old-refresh"
values.gdrive_access_expires = os.time() + 3600
gd_post_mode = "forbidden"
local gd_ok, gd_err = GDrive.uploadFile("backup.json", "GD-BODY", "application/json")
assert(not gd_ok and gd_err:find("đăng nhập lại", 1, true), "Google Drive 403 asks user to re-login")
assert(values.gdrive_access_token == "" and values.gdrive_refresh_token == "", "Google Drive 403 clears stale readonly auth")

for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Cloud upload: scopes, listing, OneDrive PUT, Google multipart and 403 reauth passed")
