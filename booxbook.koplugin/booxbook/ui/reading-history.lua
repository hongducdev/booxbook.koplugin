-- "Đang đọc dở": the reading_history that reading-state.lua already writes, finally
-- surfaced as a list instead of only a badge inside the file lists.
-- Building this screen is pure in-memory work (see ReadingState.listHistory), so it
-- opens instantly even with a long history; the filesystem is touched on tap only.
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local ReadingState = require("booxbook.reading-state")

local UI = {}

local function notify(text, subject)
    return require("booxbook.fault").notify(text, subject)
end

-- "Tên · chương N · [42%]". Chapter and badge are dropped when unknown, so a legacy
-- entry (no title, no chapter) still renders a row the reader can tap.
local function rowText(entry)
    local parts = { tostring(entry.title or entry.series_id or "?") }
    local chapter = entry.last_read_chapter
    if chapter ~= nil and tostring(chapter) ~= "" then
        parts[#parts + 1] = _("chương ") .. tostring(chapter)
    end
    local badge = ReadingState.formatStatusBadge(entry)
    if badge ~= "" then parts[#parts + 1] = badge end
    return table.concat(parts, " · ")
end

-- Legacy entries carry no stamp (0): return nothing rather than a fake date, and the
-- caller then leaves `mandatory` off so the title keeps the full row width.
local function whenText(entry)
    local at = tonumber(entry.last_read_time) or 0
    if at <= 0 then return nil end
    return os.date("%d/%m", at)
end

local function openEntry(entry)
    local path = ReadingState.historyPath(entry)
    if not path then
        notify(_("Không tìm thấy đường dẫn của mục này."))
        return
    end
    local file = io.open(path, "rb")
    if not file then
        -- Deleted by cleanup or by a transient comic read: say so instead of letting
        -- the reader fail on a missing file.
        notify(_("Không tìm thấy tệp. Mục này có thể đã bị xoá."))
        return
    end
    file:close()
    require("booxbook.ui.library").openBook(path)
end

function UI.open()
    local entries = ReadingState.listHistory()
    local items = {}
    -- NOTE: never name the loop index `_`; it would shadow gettext `_()`.
    for _index, entry in ipairs(entries) do
        local current = entry
        local row = {
            text = rowText(current),
            keep_menu_open = true,
            callback = function() openEntry(current) end,
        }
        local when = whenText(current)
        if when then row.mandatory = when end
        items[#items + 1] = row
    end

    local subtitle
    if #items == 0 then
        items[1] = { text = _("Chưa đọc gì gần đây."), select_enabled = false }
    else
        subtitle = string.format(_("%d mục · mới nhất trước"), #items)
    end

    Catalog.show{
        title = _("Đang đọc dở"),
        subtitle = subtitle,
        items = items,
    }
end

return UI
