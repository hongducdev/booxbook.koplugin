local Http = require("booxbook.http")
local Settings = require("booxbook.store.settings")

local Update = {
    REPO = "hongducdev/booxbook.koplugin",
    ASSET_NAME = "booxbook.koplugin.zip",
    MAX_ZIP = 30 * 1024 * 1024,
    MAX_EXTRACT = 80 * 1024 * 1024,
    MAX_FILES = 2000,
    -- One release lookup: three transport attempts plus a redirect hop. Outside a
    -- coroutine this used to hold the UI thread for 3 x DEFAULT_MAXTIME (60s),
    -- which is what Android calls an unresponsive app.
    CHECK_TIMEOUT = 15,
    -- Result messages the reader only has to glance at.
    NOTIFY_TIMEOUT = 6,
}

Update.API_URL = "https://api.github.com/repos/" .. Update.REPO .. "/releases/latest"

local function gettext()
    local ok, mod = pcall(require, "gettext")
    if ok and type(mod) == "function" then
        return mod
    end
    return function(text) return text end
end

local function ui()
    local ok, UIManager = pcall(require, "ui/uimanager")
    local ok_im, InfoMessage = pcall(require, "ui/widget/infomessage")
    if not ok or not ok_im then
        return
    end
    return UIManager, InfoMessage
end

-- Every message here carries a timeout: KOReader's InfoMessage has none by
-- default, so a message without one is a modal box that stays until tapped and
-- stacks on top of the previous one.
local function notify(text, timeout)
    local UIManager, InfoMessage = ui()
    if not UIManager then
        return
    end
    UIManager:show(InfoMessage:new{
        text = text,
        timeout = tonumber(timeout) or Update.NOTIFY_TIMEOUT,
    })
end

-- Long-running box the caller closes itself when the work returns, so a slow
-- download cannot leave a message behind. Returns nil when UI stubs are absent or
-- when KOReader is in silent mode: `UIManager:show` drops such a widget instead of
-- pushing it, and we would then be closing something we never owned.
local function progress(text, timeout)
    local UIManager, InfoMessage = ui()
    if not UIManager then
        return nil
    end
    if type(UIManager.isInSilentMode) == "function" and UIManager:isInSilentMode() then
        return nil
    end
    local widget = InfoMessage:new{ text = text, timeout = tonumber(timeout) or Update.CHECK_TIMEOUT * 20 }
    UIManager:show(widget)
    return widget
end

local function closeWidget(widget)
    if not widget then
        return
    end
    local UIManager = ui()
    if not UIManager or type(UIManager.close) ~= "function" then
        return
    end
    pcall(UIManager.close, UIManager, widget)
end

local function lfsMod()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok then
        return lfs
    end
    ok, lfs = pcall(require, "lfs")
    if ok then
        return lfs
    end
end

local function normalizePath(path)
    return tostring(path or ""):gsub("\\", "/")
end

function Update.safeRelPath(entry)
    if type(entry) ~= "string" or entry == "" then
        return nil
    end
    local path = normalizePath(entry)
    if path:match("^/") or path:match("^%a:[/\\]") then
        return nil
    end
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            return nil
        end
    end
    return path
end

function Update.allowedDownloadUrl(url)
    if type(url) ~= "string" then
        return false
    end
    local host = (url:match("^https://([^/:?#]+)") or ""):lower()
    return host == "github.com" or host:match("%.githubusercontent%.com$") ~= nil
end

function Update.compare(a, b)
    local function parts(value)
        local out = {}
        for number in tostring(value or ""):gmatch("(%d+)") do
            out[#out + 1] = tonumber(number)
        end
        return out
    end
    local pa, pb = parts(a), parts(b)
    local len = math.max(#pa, #pb)
    for i = 1, len do
        local na, nb = pa[i] or 0, pb[i] or 0
        if na < nb then return -1 end
        if na > nb then return 1 end
    end
    return 0
end

function Update.needsUpdate(remote, local_ver)
    return Update.compare(remote, local_ver) > 0
end

local Check = require("booxbook.update-check")
Update.CHECK_INTERVAL = Check.CHECK_INTERVAL
Update.shouldCheck = Check.shouldCheck
Update.lastCheck = Check.lastCheck
Update.noteChecked = Check.noteChecked

function Update.pluginDir()
    if Update._plugin_dir then
        return Update._plugin_dir
    end
    local src = debug.getinfo(1, "S").source
    local file = normalizePath((src:match("^@(.*)$") or src))
    local dir = file:match("^(.*)/[^/]+$")
    if dir then
        dir = dir:match("^(.*)/[^/]+$") or dir
    end
    return dir or "."
end

function Update.currentVersion()
    local meta_path = Update.pluginDir() .. "/_meta.lua"
    if not package.loaded.gettext then
        package.loaded.gettext = gettext()
    end
    local ok, meta = pcall(dofile, meta_path)
    if ok and type(meta) == "table" and meta.version then
        return tostring(meta.version)
    end
    return "0.0.0"
end

function Update.parseRelease(data)
    if type(data) == "string" then
        local decode = Update._jsonDecode
        if not decode then
            local okj, json = pcall(require, "json")
            if not okj or type(json) ~= "table" or not json.decode then
                return nil, "parse"
            end
            decode = json.decode
        end
        local ok, parsed = pcall(decode, data)
        if not ok or type(parsed) ~= "table" then
            return nil, "parse"
        end
        data = parsed
    elseif type(data) ~= "table" then
        return nil, "parse"
    end
    local tag = data.tag_name
    if type(tag) ~= "string" or tag == "" then
        return nil, "parse"
    end
    local version = tag:gsub("^v", "")
    local zip_url
    if type(data.assets) == "table" then
        for _, asset in ipairs(data.assets) do
            if type(asset) == "table" and asset.name == Update.ASSET_NAME
                and Update.allowedDownloadUrl(asset.browser_download_url) then
                zip_url = asset.browser_download_url
                break
            end
        end
    end
    if not zip_url then
        return nil, "no_asset"
    end
    return { tag = tag, version = version, zip_url = zip_url }
end

function Update.fetchLatest()
    local version = Update.currentVersion()
    local ok, code, body = Http.get(Update.API_URL, {
        delay_ms = 0,
        headers = {
            Accept = "application/vnd.github+json",
            ["User-Agent"] = "BooxBook/" .. version,
        },
    })
    if not ok then
        return nil, "http", code
    end
    return Update.parseRelease(body)
end

function Update.zipHasPluginRoot(entries)
    local saw_root = false
    for _, entry in ipairs(entries or {}) do
        local path = Update.safeRelPath(entry)
        if path then
            if path == "booxbook.koplugin" or path:match("^booxbook%.koplugin/") then
                saw_root = true
            elseif path == "main.lua" or path:match("^booxbook/") then
                return false
            end
        end
    end
    return saw_root
end

local function fileExists(path)
    local file = io.open(path, "rb")
    if not file then
        return false
    end
    file:close()
    return true
end

local function rm_rf(path)
    path = normalizePath(path)
    if path == "" or path == "." or path == "/" then
        return false
    end
    local lfs = lfsMod()
    if not lfs then
        return os.remove(path) ~= nil
    end
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then
                rm_rf(path .. "/" .. name)
            end
        end
        return lfs.rmdir(path) == true
    end
    if mode then
        return os.remove(path) ~= nil
    end
    return true
end

function Update.unpackZip(zip_path, dest, strip)
    local ok_arc, Archiver = pcall(require, "ffi/archiver")
    if not (ok_arc and Archiver and Archiver.Reader) then
        -- Do not fall back to Device:unpackArchive: it will not reject zip-slip paths.
        return false, "no archiver"
    end
    local arc = Archiver.Reader:new()
    local function closeArc()
        if arc and arc.close then
            pcall(function() arc:close() end)
        end
    end
    if not arc:open(zip_path) then
        local err = arc.err or "open failed"
        closeArc()
        return false, err
    end
    local extracted = 0
    local files = 0
    for entry in arc:iterate() do
        local rel = normalizePath(entry.path or "")
        if not Update.safeRelPath(rel) then
            rel = ""
        elseif strip then
            local _, tail = rel:match("([^/]*)/*(.*)")
            if tail and tail ~= "" then
                rel = tail
            elseif entry.mode == "directory" then
                rel = ""
            end
        end
        local safe = rel ~= "" and Update.safeRelPath(rel) or nil
        if safe and entry.mode == "file" then
            files = files + 1
            extracted = extracted + (tonumber(entry.size) or 0)
            if files > Update.MAX_FILES or extracted > Update.MAX_EXTRACT then
                closeArc()
                return false, "too large"
            end
            if not arc:extractToPath(entry.path, dest .. "/" .. safe) then
                local err = arc.err or "extract failed"
                closeArc()
                return false, err
            end
        end
    end
    local err = arc.err
    closeArc()
    if err then
        return false, err
    end
    return true
end

local function pluginParent(live)
    live = normalizePath(live):gsub("/$", "")
    return live:match("^(.*)/[^/]+$") or "."
end

function Update.install(release)
    if type(release) ~= "table" or type(release.zip_url) ~= "string" then
        return nil, "invalid"
    end
    local live = normalizePath(Update.pluginDir()):gsub("/$", "")
    local parent = pluginParent(live)
    local staging = parent .. "/booxbook.koplugin.staging"
    local bak = parent .. "/booxbook.koplugin.bak"
    local tmp_dir = Settings.downloadDir() .. "/_update"
    Settings.ensureDir(tmp_dir)
    local zip_path = tmp_dir .. "/booxbook.koplugin.zip"

    local ok, code = Http.downloadToFile(release.zip_url, zip_path, {
        delay_ms = 0,
        max_body = Update.MAX_ZIP,
        headers = { ["User-Agent"] = "BooxBook/" .. Update.currentVersion() },
    })
    if not ok then
        os.remove(zip_path)
        return nil, "download", code
    end

    rm_rf(staging)
    Settings.ensureDir(staging)
    -- Keep the zip folder layout: wrapped releases land in staging/booxbook.koplugin/.
    local extracted, extract_err = Update.unpackZip(zip_path, staging, false)
    if not extracted then
        rm_rf(staging)
        os.remove(zip_path)
        return nil, "extract", extract_err
    end

    local staged = staging
    if not fileExists(staged .. "/main.lua") and fileExists(staged .. "/booxbook.koplugin/main.lua") then
        staged = staged .. "/booxbook.koplugin"
    end
    if not fileExists(staged .. "/main.lua") or not fileExists(staged .. "/_meta.lua") then
        rm_rf(staging)
        os.remove(zip_path)
        return nil, "invalid_zip"
    end

    rm_rf(bak)
    if not os.rename(live, bak) then
        rm_rf(staging)
        os.remove(zip_path)
        return nil, "swap"
    end
    if not os.rename(staged, live) then
        os.rename(bak, live)
        rm_rf(staging)
        os.remove(zip_path)
        return nil, "swap"
    end
    os.remove(zip_path)
    rm_rf(parent .. "/booxbook.koplugin.staging")
    return true
end

local function promptRestart(version)
    local _ = gettext()
    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    local Catalog = require("booxbook.ui.catalog")
    local text = _("Đã cập nhật lên") .. " " .. version .. ".\n\n" .. _("Khởi động lại KOReader để áp dụng.")
    Catalog.confirm(text, function()
        if ok_ui and UIManager.restartKOReader then
            UIManager:restartKOReader()
        else
            notify(_("Hãy khởi động lại KOReader."))
        end
    end, { ok_text = _("Khởi động lại"), cancel_text = _("Để sau") })
end

function Update.checkAndPrompt()
    local Network = require("booxbook.network")
    Network.whenOnline(function()
        Update._checkOnline()
    end)
end

function Update.installAsync(release)
    local _ = gettext()
    local Async = require("booxbook.async")
    -- Up to 30 MiB of zip and 80 MiB of extraction: run it in a coroutine so the
    -- transport can hand the UI thread back between chunks instead of holding the
    -- menu for the whole transfer. The box is ours to close when the work returns.
    local box = progress(_("Đang tải bản cập nhật…"))
    Async.run(function()
        return Update.install(release)
    end, function(ok, result, install_err, detail)
        closeWidget(box)
        if ok and result == true then
            promptRestart(release.version)
            return
        end
        local err = ok and install_err or result
        local suffix = detail and (" (" .. tostring(detail) .. ")") or ""
        if err == "download" then
            notify(_("Tải bản cập nhật thất bại.") .. suffix)
        elseif err == "extract" or err == "invalid_zip" then
            notify(_("Giải nén thất bại.") .. suffix)
        else
            notify(_("Cài đặt bản cập nhật thất bại.") .. suffix)
        end
    end)
end

function Update._checkOnline()
    local _ = gettext()
    notify(_("Đang kiểm tra bản cập nhật…"), Update.CHECK_TIMEOUT + 5)
    local Async = require("booxbook.async")
    local Http = require("booxbook.http")
    -- Resumable, and under a budget: the lookup may retry three times, and the
    -- reader must keep seeing the menu and answering taps while it does.
    Async.run(function()
        return Http.withBudget(Update.CHECK_TIMEOUT, Update.fetchLatest)
    end, function(ok, release, err, extra)
        if not ok then
            notify(_("Không kiểm tra được cập nhật."))
            return
        end
        if not release then
            if err == "no_asset" then
                notify(_("Chưa có gói cài đặt trên GitHub."))
            else
                local suffix = extra and (" (" .. tostring(extra) .. ")") or ""
                notify(_("Không kiểm tra được cập nhật.") .. suffix)
            end
            return
        end
        local current = Update.currentVersion()
        if not Update.needsUpdate(release.version, current) then
            notify(_("Đã là bản mới nhất") .. " (" .. current .. ").")
            return
        end
        local Catalog = require("booxbook.ui.catalog")
        Catalog.confirm(
            _("Có bản mới") .. ": " .. release.version .. "\n"
                .. _("Đang dùng") .. ": " .. current .. "\n\n"
                .. _("Tải và cài đặt?"),
            function()
                Update.installAsync(release)
            end,
            { ok_text = _("Cập nhật") }
        )
    end)
end

return Update
