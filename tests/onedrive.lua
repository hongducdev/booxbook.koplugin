local names = { "json", "libs/libkoreader-lfs", "gettext", "booxbook.http",
    "booxbook.store.settings", "booxbook.wifi-upload", "booxbook.onedrive",
    "ui/widget/infomessage", "ui/trapper", "ui/uimanager", "booxbook.ui.catalog",
    "booxbook.network", "booxbook.ui.onedrive" }
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

local real_open, real_remove, real_rename = io.open, os.remove, os.rename
local rename_fail = false
local paths = {}
local function mapped(path)
    if not tostring(path):match("^@onedrive/") then return path end
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

local values = { onedrive_client_id = "00001111-aaaa-2222-bbbb-3333cccc4444", onedrive_access_expires = 0,
    onedrive_device_expires = 0 }
package.loaded["booxbook.store.settings"] = {
    get = function(key) return values[key] end,
    set = function(key, value) values[key] = value end,
    downloadDir = function() return "@onedrive" end,
    ensureDir = function() return true end,
}

local bodies = {
    device = { device_code="device-secret", user_code="ABCD-EFGH",
        verification_uri="https://microsoft.com/devicelogin", expires_in=900 },
    token = { access_token="access-one", refresh_token="refresh-one", expires_in=3600 },
    refresh = { access_token="access-two", refresh_token="refresh-two", expires_in=3600 },
    invalid = { error="invalid_grant", error_description="refresh token expired" },
    malformed = "not a table",
    page1 = { value={
        { id="folder", name="Books", folder={ childCount=2 } },
        { id="epub", name="Book.EPUB", size=5, file={} },
        { id="video", name="Movie.mp4", size=5, file={} },
    }, ["@odata.nextLink"]="https://graph.microsoft.com/v1.0/next" },
    page2 = { value={ { id="pdf", name="Manual.pdf", size=10, file={} } } },
}
package.loaded.json = { decode = function(body)
    assert(bodies[body], "unexpected JSON fixture: " .. tostring(body))
    return bodies[body]
end }

local posted, graph_mode, graph_calls, refresh_invalid, download_mode = {}, "normal", 0, false, "normal"
package.loaded["booxbook.http"] = {
    post = function(url, body, opts)
        assert(opts.verify_tls == true)
        posted[#posted + 1] = { url=url, body=body }
        if url:match("devicecode$") then return true, 200, "device" end
        if body:find("refresh_token", 1, true) then
            if refresh_invalid then return false, 400, "invalid" end
            return true, 200, "refresh"
        end
        return true, 200, "token"
    end,
    get = function(url, opts)
        assert(opts.verify_tls == true)
        assert(opts.headers.authorization:match("^Bearer access%-"))
        graph_calls = graph_calls + 1
        if graph_mode == "retry" and graph_calls == 1 then return false, 401 end
        if graph_mode == "malformed" then return true, 200, "malformed" end
        if graph_mode == "foreign" then
            return true, 200, "page1"
        end
        return true, 200, url:match("/next$") and "page2" or "page1"
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
package.loaded["booxbook.onedrive"] = nil
local OneDrive = require("booxbook.onedrive")

local info = assert(OneDrive.startLogin())
assert(info.user_code == "ABCD-EFGH" and values.onedrive_device_code == "device-secret")
assert(posted[1].body:find("Files.ReadWrite%%20offline_access") and not posted[1].body:find("User.Read", 1, true))
assert(OneDrive.finishLogin() == "access-one")
assert(values.onedrive_refresh_token == "refresh-one" and OneDrive.hasAuth())

graph_mode, graph_calls = "retry", 0
assert(OneDrive.list() and graph_calls == 3, "Graph 401 refreshes once, then continues pagination")
values.onedrive_access_token, values.onedrive_access_expires = "access-one", os.time() + 3600
graph_mode = "normal"
local items = assert(OneDrive.list())
assert(#items == 3 and items[1].folder and items[2].name == "Book.EPUB" and items[3].name == "Manual.pdf")
local path = assert(OneDrive.download(items[2]))
local file = assert(io.open(path, "rb")); assert(file:read("*a") == "abcde"); file:close()
local duplicate = assert(OneDrive.download(items[2]))
assert(duplicate == "@onedrive/received/Book (1).EPUB", "duplicate gets a unique filename")
file = assert(io.open(path, "rb")); assert(file:read("*a") == "abcde"); file:close()

download_mode = "mismatch"
assert(not OneDrive.download({ id="mismatch", name="Mismatch.epub", size=5 }))
assert(not attributes("@onedrive/received/.Mismatch.epub.part"), "size mismatch removes partial file")
download_mode, rename_fail = "normal", true
assert(not OneDrive.download({ id="rename", name="Rename.epub", size=5 }))
assert(not attributes("@onedrive/received/.Rename.epub.part"), "rename failure removes partial file")
rename_fail, download_mode = false, "failure"
assert(not OneDrive.download({ id="failure", name="Failure.epub", size=5 }), "HTTP failure is reported")
download_mode = "normal"

bodies.page1["@odata.nextLink"] = "https://evil.example/token"
graph_mode = "malformed"
assert(not OneDrive.list(), "malformed Graph JSON fails closed")
graph_mode = "normal"
assert(not OneDrive.list(), "foreign pagination URL must fail closed")
bodies.page1["@odata.nextLink"] = "https://graph.microsoft.com/v1.0/next"
OneDrive.MAX_PAGES = 1
assert(not OneDrive.list(), "pagination cap must fail closed")

values.onedrive_access_token, values.onedrive_access_expires = "", 0
assert(OneDrive.accessToken() == "access-two" and values.onedrive_refresh_token == "refresh-two")
values.onedrive_access_token, values.onedrive_refresh_token = "", "expired"
refresh_invalid = true
assert(not OneDrive.refreshAccess() and not OneDrive.hasAuth(), "invalid refresh token clears stale auth")
assert(values.onedrive_device_code == "")

values.onedrive_access_token, values.onedrive_access_expires = "access-one", os.time() + 3600
graph_mode, graph_calls, OneDrive.MAX_PAGES = "normal", 0, 20
local queue, shown = {}, {}
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/trapper"] = { wrap = function(_, fn) fn() end, info = function() end, clear = function() end }
package.loaded["ui/uimanager"] = {
    nextTick = function(_, fn) queue[#queue + 1] = fn end,
    show = function() end,
}
package.loaded["booxbook.ui.catalog"] = { show = function(value) shown[#shown + 1] = value end }
package.loaded["booxbook.network"] = { whenOnline = function(fn) fn() end }
package.loaded["booxbook.ui.onedrive"] = nil
local OneDriveUI = require("booxbook.ui.onedrive")
OneDriveUI.showFolder(nil, "OneDrive")
while #queue > 0 do table.remove(queue, 1)() end
assert(shown[1].items[1].text == "Thư mục: Books", "folder rows keep gettext callable")

io.open, os.remove, os.rename = real_open, real_remove, real_rename
for _, path_name in pairs(paths) do real_remove(path_name) end
for _, name in ipairs(names) do package.loaded[name] = saved[name] end
print("OneDrive: device login, refresh, filtering, pagination and atomic download passed")
