local Settings = require("booxbook.store.settings")
local Storage = require("booxbook.store.storage")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

local Cleanup = {}

local function newsFile(path)
    if type(path) ~= "string" then return end
    local root = ffiUtil.realpath(Settings.downloadDir() .. "/news")
    local resolved = ffiUtil.realpath(path)
    if not root or not resolved then return end
    local prefix = root .. "/"
    if resolved:sub(1, #prefix) ~= prefix
        or not resolved:sub(#prefix + 1):match("^[^/]+/[^/]+%.html$") then return end
    if lfs.attributes(resolved, "mode") == "file" then return resolved end
end

local function readProgress(ui)
    if not ui then return nil end
    if ui.paging and type(ui.paging.getLastPercent) == "function" then
        local ok, val = pcall(ui.paging.getLastPercent, ui.paging)
        if ok and type(val) == "number" then return val end
    end
    if ui.rolling and type(ui.rolling.getLastPercent) == "function" then
        local ok, val = pcall(ui.rolling.getLastPercent, ui.rolling)
        if ok and type(val) == "number" then return val end
    end
    local settings = ui.doc_settings
    if settings and type(settings.readSetting) == "function" then
        local p = settings:readSetting("percent_finished")
        if type(p) == "number" then return p end
    end
    return nil
end

local function stillAtEnd(percent)
    if type(percent) ~= "number" then return false end
    if percent > 1 then return percent >= 99 end
    return percent >= 0.99
end

function Cleanup.afterClose(ui)
    if Settings.get("news_delete_finished") ~= true or not ui then return end
    local path = ui.document and ui.document.file
    local settings = ui.doc_settings
    local summary = settings and settings:readSetting("summary") or {}
    local percent = readProgress(ui)
    local marked = summary.status == "complete"
    local left_at_end = stillAtEnd(percent)
    if not marked and not left_at_end then return end
    local target = newsFile(path)
    if not target then return end
    -- CloseDocument runs before the reader releases the file and saves its metadata.
    UIManager:nextTick(function()
        if Settings.get("news_delete_finished") ~= true or newsFile(path) ~= target then return end
        local reader = require("apps/reader/readerui").instance
        if reader and reader.document and ffiUtil.realpath(reader.document.file) == target then return end
        local FileManager = require("apps/filemanager/filemanager")
        -- Use KOReader's deletion so history, collections and sidecar metadata stay in sync.
        if FileManager:deleteFile(target, true) then
            if FileManager.instance then
                FileManager.instance:onRefresh()
            end
            -- Image sidecars are disposable plugin data, not library files:
            -- remove them only after the HTML is gone so a failed delete
            -- cannot leave a library article with missing images.
            pcall(Storage.removeSidecar, target)
        end
    end)
end

return Cleanup
