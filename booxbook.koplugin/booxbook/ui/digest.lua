local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Digest = require("booxbook.digest")
local Settings = require("booxbook.store.settings")

local UI = {}

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function lfsModule()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs then return lfs end
    ok, lfs = pcall(require, "lfs")
    if ok then return lfs end
end

local function collectNews()
    local out = {}
    local lfs = lfsModule()
    if not lfs or not lfs.dir or not lfs.attributes then return out end
    local root = Settings.downloadDir() .. "/news"
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
                elseif ok_attr and mode == "file" and name:match("%.html$") then
                    local ok_time, mtime = pcall(lfs.attributes, path, "modification")
                    out[#out + 1] = { path = path, title = name:gsub("%.html$", ""),
                        mtime = (ok_time and type(mtime) == "number") and mtime or 0 }
                end
            end
        end
    end
    scan(root, 1)
    table.sort(out, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
    return out
end

function UI.open()
    local files = collectNews()
    if #files == 0 then
        notify(_("Chưa có bài báo đã tải để tạo digest."))
        return
    end
    local picked = Digest.pick(files, Digest.MAX_FILES)
    local items = {
        { text = string.format(_("Tạo EPUB từ %d bài mới nhất?"), #picked), select_enabled = false },
        { text = _("Tạo digest EPUB"), keep_menu_open = true, callback = function()
            UIManager:nextTick(function()
                Trapper:wrap(function()
                    Trapper:info(_("Đang tạo digest..."))
                    local dir = Settings.downloadDir() .. "/received"
                    if not Settings.ensureDir(dir) then
                        Trapper:clear()
                        notify(_("Không mở được thư mục tải."))
                        return
                    end
                    local dest = dir .. "/" .. Digest.filename()
                    local result, err = Digest.build(dest, picked)
                    Trapper:clear()
                    if not result then
                        notify(_("Không tạo được digest: ") .. tostring(err))
                        return
                    end
                    Catalog.clearStack()
                    notify(_("Đã tạo digest: ") .. "\n" .. result)
                end)
            end)
        end },
    }
    for i = 1, math.min(10, #picked) do
        items[#items + 1] = { text = picked[i].title or picked[i].path, select_enabled = false }
    end
    Catalog.show{ title = _("Digest báo ngày"), items = items }
end

return UI
