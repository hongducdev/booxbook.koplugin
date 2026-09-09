local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Library = require("booxbook.library")
local Settings = require("booxbook.store.settings")

local UI = {}

local function lfsModule()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs then return lfs end
    ok, lfs = pcall(require, "lfs")
    if ok then return lfs end
end

local function collect(root, out)
    out = out or {}
    local lfs = lfsModule()
    if not lfs or not lfs.dir or not lfs.attributes then return out end
    local function scan(dir, depth)
        if depth > 3 then return end
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok or not iter then return end
        for name in iter, state do
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local ok_attr, mode = pcall(lfs.attributes, path, "mode")
                if ok_attr and mode == "directory" then
                    scan(path, depth + 1)
                elseif ok_attr and mode == "file"
                    and name:match("%.(html|epub|pdf|cbz|cbr|fb2|mobi|azw3?|djv|djvu|txt)$") then
                    local ok_size, size = pcall(lfs.attributes, path, "size")
                    local ok_time, mtime = pcall(lfs.attributes, path, "modification")
                    out[#out + 1] = { name = name, path = path,
                        size = (ok_size and type(size) == "number") and size or 0,
                        mtime = (ok_time and type(mtime) == "number") and mtime or 0 }
                end
            end
        end
    end
    scan(root, 1)
    return out
end

function UI.open(query)
    local root = Settings.downloadDir()
    local files = collect(root)
    local filtered = Library.filter(files, query)
    local summary = Library.summarize(files)
    local quota = _("Tổng: ") .. summary.count .. _(" file · ") .. Library.formatBytes(summary.bytes)
    table.sort(filtered, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
    local items = {
        { text = quota, select_enabled = false },
        { text = _("Tìm sách offline"), keep_menu_open = true, callback = function()
            Catalog.promptText{ title = _("Từ khóa"), input = query or "",
                on_submit = function(value) UI.open(value) end }
        end },
    }
    for i = 1, math.min(50, #filtered) do
        local current = filtered[i]
        items[#items + 1] = { text = current.name, keep_menu_open = true, callback = function()
            UIManager:nextTick(function()
                Catalog.clearStack()
                ReaderUI:showReader(current.path)
            end)
        end }
    end
    if #filtered == 0 then
        items[#items + 1] = { text = _("Không tìm thấy sách phù hợp."), select_enabled = false }
    end
    Catalog.show{ title = _("Tìm sách offline"), items = items }
end

return UI
