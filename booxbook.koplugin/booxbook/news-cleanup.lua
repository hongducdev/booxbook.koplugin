local Settings = require("booxbook.store.settings")
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

local function stillAtEnd(percent)
    if type(percent) ~= "number" then return false end
    if percent > 1 then return percent >= 99 end
    return percent >= 0.99
end

function Cleanup.afterClose(ui, finished_path)
    if Settings.get("news_delete_finished") ~= true then return end
    local path = ui.document and ui.document.file
    local settings = ui.doc_settings
    local summary = settings and settings:readSetting("summary") or {}
    local percent = settings and settings:readSetting("percent_finished")
    -- EndOfBook alone is not enough: "Go to beginning" must not delete on a later close.
    local marked = summary.status == "complete"
    local left_at_end = finished_path == path and stillAtEnd(percent)
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
        if FileManager:deleteFile(target, true) and FileManager.instance then
            FileManager.instance:onRefresh()
        end
    end)
end

return Cleanup
