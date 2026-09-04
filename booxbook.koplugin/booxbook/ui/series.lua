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
            mandatory = tostring(i),
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
    local items = {}
    if series.author and series.author ~= "" then
        items[#items + 1] = {
            text = _("Tác giả") .. ": " .. series.author,
            select_enabled = false,
        }
    end
    for _, volume in ipairs(series.volumes or {}) do
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
    Catalog.show({
        title = series.title or _("Truyện"),
        items = items,
    })
end

function SeriesUI.askRange(max_chapter, on_submit)
    max_chapter = tonumber(max_chapter) or 1
    Catalog.promptText({
        title = _("Tải từ chương (1–") .. tostring(max_chapter) .. ")",
        input = "1",
        on_submit = function(from_text)
            local from = tonumber(from_text) or 1
            Catalog.promptText({
                title = _("Đến chương"),
                input = tostring(math.min(from + 19, max_chapter)),
                on_submit = function(to_text)
                    local to = tonumber(to_text) or from
                    if from < 1 then from = 1 end
                    if to > max_chapter then to = max_chapter end
                    if to < from then to = from end
                    if on_submit then
                        on_submit(from, to)
                    end
                end,
            })
        end,
    })
end

return SeriesUI
