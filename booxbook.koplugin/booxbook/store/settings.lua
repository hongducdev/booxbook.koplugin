local Settings = {}

local DEFAULTS = {
    download_dir = nil,
    delay_ms = 1200,
    include_images = true,
    covers_max_bytes = 50 * 1024 * 1024,
    novel_epub = false,
    novel_keep_html = true,
    news_delete_finished = false,
    quota_news_mb = 300,
    quota_received_mb = 500,
    quota_novels_mb = 0,
    quota_comics_mb = 0,
    quota_novels_evict = false,
    quota_comics_evict = false,
    adult_content = false,
    wattpad_cookie = "",
    docln_cookie = "",
    stv_cookie = "",
    stv_enabled = false,
    stv_warning_accepted = false,
    stv_home = "https://sangtacviet.com",
    custom_rss_feeds = {},
    news_limit = 10,
    onedrive_client_id = "262471d2-046d-45d1-a681-ea5b025d17b7",
    onedrive_access_token = "",
    onedrive_refresh_token = "",
    onedrive_access_expires = 0,
    onedrive_device_code = "",
    onedrive_user_code = "",
    onedrive_verification_uri = "",
    onedrive_device_expires = 0,
    gdrive_client_id = "",
    gdrive_access_token = "",
    gdrive_refresh_token = "",
    gdrive_access_expires = 0,
    gdrive_device_code = "",
    gdrive_user_code = "",
    gdrive_verification_uri = "",
    gdrive_device_expires = 0,
    followed_series = {},
    update_last_check = 0,
}

local store
local memory = {}

local function memoryStore()
    return {
        readSetting = function(_, key, default)
            if memory[key] == nil then
                return default
            end
            return memory[key]
        end,
        saveSetting = function(_, key, value)
            memory[key] = value
        end,
        flush = function() end,
        has = function(_, key)
            return memory[key] ~= nil
        end,
    }
end

function Settings.bind(backend)
    store = backend
    return Settings
end

function Settings.load()
    local ok_ls, LuaSettings = pcall(require, "luasettings")
    local ok_ds, DataStorage = pcall(require, "datastorage")
    if ok_ls and ok_ds and LuaSettings.open then
        store = LuaSettings:open(DataStorage:getSettingsDir() .. "/booxbook.lua")
    else
        store = memoryStore()
    end
    return Settings
end

local function backend()
    if not store then
        Settings.load()
    end
    return store
end

function Settings.get(key)
    local value = backend():readSetting(key, DEFAULTS[key])
    if value == nil then
        return DEFAULTS[key]
    end
    return value
end

function Settings.set(key, value)
    backend():saveSetting(key, value)
    backend():flush()
end

function Settings.delayMs()
    return tonumber(Settings.get("delay_ms")) or DEFAULTS.delay_ms
end

function Settings.includeImages()
    return Settings.get("include_images") == true
end

function Settings.adultContent()
    return Settings.get("adult_content") == true
end

function Settings.cookie(source_id)
    if source_id == "wattpad" then
        return Settings.get("wattpad_cookie") or ""
    end
    if source_id == "docln" then
        return Settings.get("docln_cookie") or ""
    end
    if source_id == "sangtacviet" then
        return Settings.get("stv_cookie") or ""
    end
    return ""
end

function Settings.setCookie(source_id, value)
    if source_id == "wattpad" then
        Settings.set("wattpad_cookie", value or "")
    elseif source_id == "docln" then
        Settings.set("docln_cookie", value or "")
    elseif source_id == "sangtacviet" then
        Settings.set("stv_cookie", value or "")
    end
end

function Settings.sangtacvietEnabled()
    return Settings.get("stv_enabled") == true
end

function Settings.setSangtacvietEnabled(enabled)
    Settings.set("stv_enabled", enabled == true)
end

local function mkdir_p(path)
    local lfs_ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not lfs_ok then
        lfs_ok, lfs = pcall(require, "lfs")
    end
    if not lfs_ok then
        return false
    end
    local acc = ""
    for part in string.gmatch(path, "[^/\\]+") do
        if acc == "" and path:match("^/") then
            acc = "/" .. part
        elseif acc == "" then
            acc = part
        else
            acc = acc .. "/" .. part
        end
        pcall(lfs.mkdir, acc)
    end
    return lfs.attributes(path, "mode") == "directory"
end

function Settings.ensureDir(path)
    return mkdir_p(path)
end

function Settings.downloadDir()
    local custom = Settings.get("download_dir")
    if type(custom) == "string" and custom ~= "" then
        mkdir_p(custom)
        return custom
    end
    local ok, DataStorage = pcall(require, "datastorage")
    local base
    if ok then
        if DataStorage.getFullDataDir then
            base = DataStorage:getFullDataDir()
        else
            base = DataStorage:getDataDir()
        end
    else
        base = "."
    end
    local dir = (base:gsub("[/\\]$", "")) .. "/booxbook"
    mkdir_p(dir)
    return dir
end

return Settings
