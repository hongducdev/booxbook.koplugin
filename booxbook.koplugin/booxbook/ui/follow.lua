local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Follow = require("booxbook.follow")
local Network = require("booxbook.network")
local Settings = require("booxbook.store.settings")
local Source = require("booxbook.source")

local UI = {}

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function saved()
    local value = Settings.get("followed_series")
    return type(value) == "table" and value or {}
end

function UI.toggle(series)
    if type(series) ~= "table" or not series.source_id or not series.id then return end
    local data = saved()
    if Follow.isFollowed(data, series.source_id, series.id) then
        Follow.unfollow(data, series.source_id, series.id)
        Settings.set("followed_series", data)
        notify(_("Đã bỏ theo dõi."))
    else
        Follow.follow(data, series)
        Settings.set("followed_series", data)
        notify(_("Đã theo dõi. Mở Truyện đang theo dõi để kiểm tra chương mới."))
    end
end

function UI.followLabel(series)
    local data = saved()
    if type(series) == "table" and Follow.isFollowed(data, series.source_id, series.id) then
        return _("Bỏ theo dõi truyện này")
    end
    return _("Theo dõi truyện này")
end

local function checkOne(entry, done)
    local adapter = Source.get(entry.source_id)
    if not adapter or not adapter.getSeries then
        done(entry, nil, _("Nguồn không hỗ trợ kiểm tra."))
        return
    end
    Network.whenOnline(function()
        Trapper:wrap(function()
            Trapper:info(_("Đang kiểm tra: ") .. (entry.title or entry.id))
            local ok, series = pcall(adapter.getSeries, entry.url ~= "" and entry.url or entry.id)
            Trapper:clear()
            if not ok or not series then
                done(entry, nil, tostring(series))
                return
            end
            local live = type(series.chapters) == "table" and #series.chapters or 0
            done(entry, Follow.checkUpdate(entry, live), nil, live)
        end)
    end)
end

function UI.open()
    local data = saved()
    local list = Follow.list(data)
    if #list == 0 then
        Catalog.show{ title = _("Truyện đang theo dõi"),
            items = { { text = _("Chưa theo dõi truyện nào. Mở một bộ truyện và chọn Theo dõi."), select_enabled = false } } }
        return
    end
    local items = {}
    for _, entry in ipairs(list) do
        local current = entry
        items[#items + 1] = {
            text = current.title or current.id,
            mandatory = tostring(current.last_count or 0) .. _(" chương"),
            keep_menu_open = true,
            callback = function()
                checkOne(current, function(check_entry, new_count, err, live)
                    if err then
                        notify(tostring(err))
                        return
                    end
                    local fresh = saved()
                    Follow.noteChecked(fresh, check_entry.source_id, check_entry.id, live)
                    Settings.set("followed_series", fresh)
                    if (new_count or 0) > 0 then
                        notify(string.format(_("Có %d chương mới (tổng %d)."), new_count, live))
                    else
                        notify(_("Chưa có chương mới."))
                    end
                end)
            end,
        }
    end
    Catalog.show{ title = _("Truyện đang theo dõi"), items = items }
end

return UI
