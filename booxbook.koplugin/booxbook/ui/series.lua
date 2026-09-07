local Catalog = require("booxbook.ui.catalog")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local SeriesUI = {}

local function chapterItems(volume, on_chapter)
    local items = {}
    for i, chapter in ipairs(volume.chapters or {}) do
        items[#items + 1] = {
            text = chapter.title or (_("Chương") .. " " .. i),
            mandatory = tostring(chapter.index or i),
            keep_menu_open = true,
            callback = function()
                if on_chapter then
                    on_chapter(chapter, i)
                end
            end,
        }
    end
    return items
end

function SeriesUI.show(series, opts)
    opts = opts or {}
    series = series or {}
    local unit = opts.unit or _("chương")
    local Unit = opts.Unit or _("Chương")
    local items = {}
    if opts.on_info then
        items[#items + 1] = { text = _("Thông tin truyện"), keep_menu_open = true, callback = opts.on_info }
    end
    if opts.on_go and #(series.chapters or {}) > 0 then
        items[#items + 1] = { text = _("Mở ") .. unit .. _(" bất kỳ"), keep_menu_open = true, callback = function()
            Catalog.promptText{
                title = _("Số thứ tự trong mục lục (1–") .. #series.chapters .. ")",
                input = "1",
                on_submit = function(value)
                    local number = tonumber(value)
                    if not number or number % 1 ~= 0 or number < 1 or number > #series.chapters then
                        UIManager:show(InfoMessage:new{ text = _("Số chương không hợp lệ.") }); return
                    end
                    opts.on_go(number)
                end,
            }
        end }
    end
    if series.author and series.author ~= "" then
        items[#items + 1] = {
            text = _("Tác giả") .. ": " .. series.author,
            select_enabled = false,
        }
    end
    if opts.on_offline and #(series.chapters or {}) > 0 then
        items[#items + 1] = { text = Unit .. _(" đã tải (offline)"), keep_menu_open = true, callback = opts.on_offline }
    end
    for position, volume in ipairs(series.volumes or {}) do
        items[#items + 1] = {
            text = volume.title or _("Tập"),
            sub_item_table = chapterItems(volume, opts.on_chapter),
        }
    end
    if #items == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Không có chương."),
        })
        return
    end
    local on_left_icon
    if #(series.chapters or {}) > 0 and (opts.on_range or opts.on_download_all) then
        on_left_icon = function()
            local actions = {}
            if opts.on_range then
                actions[#actions + 1] = {
                    text = _("Tải khoảng ") .. unit,
                    keep_menu_open = true,
                    callback = opts.on_range,
                }
            end
            if opts.on_download_all then
                actions[#actions + 1] = {
                    text = _("Tải toàn bộ ") .. unit,
                    keep_menu_open = true,
                    callback = opts.on_download_all,
                }
            end
            Catalog.show({
                title = _("Tải ") .. unit,
                items = actions,
            })
        end
    end
    Catalog.show({
        title = series.title or _("Truyện"),
        items = items,
        left_icon = on_left_icon and "appbar.menu" or nil,
        on_left_icon = on_left_icon,
    })
end

function SeriesUI.askRange(max_chapter, on_submit)
    max_chapter = tonumber(max_chapter) or 0
    if max_chapter < 1 then return end
    Catalog.promptText({
        title = _("Tải từ chương (1–") .. tostring(max_chapter) .. ")",
        input = "1",
        on_submit = function(from_text)
            local from = tonumber(from_text)
            if not from or from % 1 ~= 0 or from < 1 or from > max_chapter then
                UIManager:show(InfoMessage:new{ text = _("Số chương không hợp lệ.") }); return
            end
            Catalog.promptText({
                title = _("Đến chương"),
                input = tostring(math.min(from + 19, max_chapter)),
                on_submit = function(to_text)
                    local to = tonumber(to_text)
                    if not to or to % 1 ~= 0 or to < from or to > max_chapter then
                        UIManager:show(InfoMessage:new{ text = _("Số chương không hợp lệ.") }); return
                    end
                    if on_submit then
                        on_submit(from, to)
                    end
                end,
            })
        end,
    })
end

return SeriesUI
