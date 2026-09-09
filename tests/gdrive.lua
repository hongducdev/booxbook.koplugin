local names = { "json", "libs/libkoreader-lfs", "gettext", "booxbook.http",
    "booxbook.store.settings", "booxbook.wifi-upload", "booxbook.gdrive",
    "ui/widget/infomessage", "ui/trapper", "ui/uimanager", "booxbook.ui.catalog",
    "booxbook.network", "booxbook.ui.gdrive" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

local real_open, real_remove, real_rename = io.open, os.remove, os.rename
local rename_fail = false
local paths = {}
local function mapped(path)
    if not tostring(path):match("^@gdrive/") then return path end
    if not paths[path] then paths[path] = os.tmpname(); real_remove(paths[path]) end
    return paths[path]
end
io.open = function(path, mode) return real_open(mapped(path), mode) end
os.remove = function(path) return real_remove(mapped(path)) end
os.rename = function(from, to)
    if rename_fail then return nil end
    return real_rename(mapped(from), mapped(to))
end

local function attributes(path, field)
    local file = real_open(mapped(path), "rb")
    if not file then return nil end
    local size = file:seek("end")
    file:close()
    if field == "size" then return size end
    if field == "mode" then return "file" end
    return { mode = "file", size = size }
end
package.loaded["libs/libkoreader-lfs"] = { attributes = attributes, symlinkattributes = attributes }
package.loaded.gettext = function(text) return text end

local values = { gdrive_client_id = "abc.apps.googleusercontent.com", gdrive_access_expires = 0,
    gdrive_device_expires = 0 }
package.loaded["booxbook.store.settings"] = {
    get = function(key) return values[key] end,
    set = function(key, value) values[key] = value end,
    downloadDir = function() return "@gdrive" end,
    ensureDir = function() return true end,
}

local bodies = {
    device = { device_code = "device-secret", user_code = "ABCD-EFGH",
        verification_url = "https://accounts.google.com/device", expires_in = 900 },
    token = { access_token = "access-one", refresh_token = "refresh-one", expires_in = 3600 },
    refresh = { access_token = "access-two", refresh_token = "refresh-two", expires_in = 3600 },
    invalid = { error = "invalid_grant", error_description = "refresh token expired" },
    malformed = "not a table",
    page1 = { files = {
        { id = "folder", name = "Books", mimeType = "application/vnd.google-apps.folder" },
        { id = "epub", name = "Book.EPUB", size = "5", mimeType = "application/epub+zip" },
        { id = "video", name = "Movie.mp4", size = "5", mimeType = "video/mp4" },
    }, nextPageToken = "tok123" },
    page2 = { files = { { id = "pdf", name = "Manual.pdf", size = "10", mimeType = "application/pdf" } } },
}
package.loaded.json = { decode = function(body)
    assert(bodies[body], "unexpected JSON fixture: " .. tostring(body))
    return bodies[body]
end }

local posted, list_calls, refresh_invalid, download_mode = {}, 0, false, "normal"
package.loaded["booxbook.http"] = {
    post = function(url, body, opts)
        assert(opts.verify_tls == true)
        posted[#posted + 1] = { url = url, body = body }
        if url:match("device/code$") then return true, 200, "device" end
        if body:find("refresh_token", 1, true) then
            if refresh_invalid then return false, 400, "invalid" end
            return true, 200, "refresh"
        end
        return true, 200, "token"
    end,
    get = function(url, opts)
        assert(opts.verify_tls == true)
        assert(opts.headers.authorization:match("^Bearer access%-"))
        assert(url:sub(1, 36) == "https://www.googleapis.com/drive/v3/",
            "drive api stays on googleapis host")
        list_calls = list_calls + 1
        if url:find("pageToken=tok123", 1, true) then return true, 200, "page2" end
        return true, 200, "page1"
    end,
    downloadToFile = function(_, path, opts)
        assert(opts.verify_tls == true)
        assert(opts.headers.authorization == "Bearer access-one")
        local file = assert(io.open(path, "wb"))
        assert(file:write(download_mode == "mismatch" and "abc" or "abcde")); assert(file:close())
        if download_mode == "failure" then os.remove(path); return false, 503 end
        return true, 200
    end,
}

package.loaded["booxbook.wifi-upload"] = nil
package.loaded["booxbook.gdrive"] = nil
local GDrive = require("booxbook.gdrive")

assert(not GDrive.validClientId("not-a-client-id"), "non-google client id rejected")
local info = assert(GDrive.startLogin())
assert(info.user_code == "ABCD-EFGH" and values.gdrive_device_code == "device-secret")
assert(posted[1].body:find("drive.readonly", 1, true), "device flow requests readonly scope")
assert(GDrive.finishLogin() == "access-one")
assert(values.gdrive_refresh_token == "refresh-one" and GDrive.hasAuth())

local items = assert(GDrive.list())
assert(#items == 3 and items[1].folder and items[2].name == "Book.EPUB" and items[3].name == "Manual.pdf")
local path = assert(GDrive.download(items[2]))
local file = assert(io.open(path, "rb")); assert(file:read("*a") == "abcde"); file:close()
local duplicate = assert(GDrive.download(items[2]))
assert(duplicate == "@gdrive/received/Book (1).EPUB", "duplicate gets a unique filename")

download_mode = "mismatch"
assert(not GDrive.download({ id = "mismatch", name = "Mismatch.epub", size = 5 }))
download_mode = "normal"

values.gdrive_access_token, values.gdrive_access_expires = "", 0
assert(GDrive.accessToken() == "access-two" and values.gdrive_refresh_token == "refresh-two")
values.gdrive_access_token, values.gdrive_refresh_token = "", "expired"
refresh_invalid = true
assert(not GDrive.refreshAccess() and not GDrive.hasAuth(), "invalid refresh token clears stale auth")

values.gdrive_access_token, values.gdrive_access_expires = "access-one", os.time() + 3600
local queue, shown = {}, {}
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/trapper"] = { wrap = function(_, fn) fn() end, info = function() end, clear = function() end }
package.loaded["ui/uimanager"] = {
    nextTick = function(_, fn) queue[#queue + 1] = fn end,
    show = function() end,
}
package.loaded["booxbook.ui.catalog"] = { show = function(value) shown[#shown + 1] = value end }
package.loaded["booxbook.network"] = { whenOnline = function(fn) fn() end }
package.loaded["booxbook.ui.gdrive"] = nil
local GDriveUI = require("booxbook.ui.gdrive")
GDriveUI.showFolder(nil, "Google Drive")
while #queue > 0 do table.remove(queue, 1)() end
assert(shown[1].items[1].text == "Thư mục: Books", "drive folder rows render")

local Digest = require("booxbook.digest")
local tmp1, tmp2 = os.tmpname() .. ".html", os.tmpname() .. ".html"
local f1 = assert(real_open(tmp1, "wb")); assert(f1:write("<html><body><p>One</p></body></html>")); f1:close()
local f2 = assert(real_open(tmp2, "wb")); assert(f2:write("<html><body><p>Two</p></body></html>")); f2:close()
local seen
local dest = assert(Digest.build("@gdrive/out.epub",
    { { path = tmp1, title = "One" }, { path = tmp2, title = "Two" } },
    { write = function(path, book)
        seen = { path = path, book = book }
        return true
    end }))
assert(dest == "@gdrive/out.epub" and #seen.book.chapters == 2
    and seen.book.chapters[1].html:find("One", 1, true), "digest bundles html chapters")
assert(not Digest.build("@gdrive/out.epub", {}, { write = function() return true end }),
    "digest rejects empty selection")
real_remove(tmp1); real_remove(tmp2)

io.open, os.remove, os.rename = real_open, real_remove, real_rename
for _, path_name in pairs(paths) do real_remove(path_name) end
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("Google Drive: device login, refresh, listing, atomic download and digest build passed")
