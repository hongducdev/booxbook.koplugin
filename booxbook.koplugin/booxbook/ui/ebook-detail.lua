-- Detail page for sources that publish whole ebook files (adapter.kind == "ebook"):
-- title, author, blurb, and one row per downloadable format. Tapping a format saves
-- the file under <download_dir>/books/<source>/ and offers to open it in the reader;
-- a format that is already saved opens straight away.
--
-- Network work runs through Async so a multi-megabyte transfer keeps the UI answering
-- taps (Android declares KOReader unresponsive after ~5 s of a blocked main thread).
local Detail = {}

-- One list fetch / transfer at a time: a second tap would only queue behind it.
local busy = false

local function notify(text, subject)
    return require("booxbook.fault").notify(text, subject)
end

-- Progress box the caller closes itself, as in booxbook.update: it carries a
-- timeout so a lost callback cannot leave a modal box behind.
local function progress(text)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local widget = InfoMessage:new{ text = text, timeout = 3600 }
    UIManager:show(widget)
    return widget
end

local function closeProgress(widget)
    if widget then require("ui/uimanager"):close(widget) end
end

local function run(message, work, done)
    local _ = require("gettext")
    require("booxbook.network").whenOnline(function()
        if busy then
            notify(_("Đang tải, vui lòng chờ."))
            return
        end
        busy = true
        local box = progress(message)
        require("booxbook.async").run(work, function(ok, first, second)
            busy = false
            closeProgress(box)
            if not ok then
                notify(tostring(first))
                return
            end
            done(first, second)
        end)
    end)
end

local function openBook(path)
    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        require("booxbook.ui.catalog").clearStack()
        require("apps/reader/readerui"):showReader(path)
    end)
end

local function formatLabel(file, path)
    local _ = require("gettext")
    return string.format(path and _("Mở %s") or _("Tải %s"), file.format)
end

function Detail.download(series, file)
    local _ = require("gettext")
    local Download = require("booxbook.ebook-download")
    local saved = Download.existing(series, file)
    if saved then
        openBook(saved)
        return
    end
    run(string.format(_("Đang tải %s…\nCó thể mất vài phút."), file.format), function()
        return require("booxbook.http").withBudget(Download.BUDGET_SECONDS, function()
            return Download.fetch(series, file)
        end)
    end, function(path, err)
        if not path then
            notify(tostring(err))
            return
        end
        require("booxbook.ui.catalog").confirm(
            string.format(_("Đã lưu: %s\n\nMở sách ngay?"), path:match("[^/\\]+$") or path),
            function() openBook(path) end, { ok_text = _("Mở") })
    end)
end

local function showBlurb(series)
    local _ = require("gettext")
    local lines = {}
    if series.author then lines[#lines + 1] = _("Tác giả") .. ": " .. series.author end
    if series.status and series.status ~= "" then lines[#lines + 1] = _("Tình trạng") .. ": " .. series.status end
    if type(series.tags) == "table" and #series.tags > 0 then
        lines[#lines + 1] = _("Thể loại") .. ": " .. table.concat(series.tags, ", ")
    end
    if series.description then lines[#lines + 1] = "\n" .. series.description end
    require("ui/uimanager"):show(require("ui/widget/textviewer"):new{
        title = series.title,
        text = table.concat(lines, "\n"),
    })
end

function Detail.showFiles(series)
    local _ = require("gettext")
    local Download = require("booxbook.ebook-download")
    local items = { {
        text = _("Giới thiệu"),
        mandatory = series.author,
        keep_menu_open = true,
        callback = function() showBlurb(series) end,
    } }
    for _index, file in ipairs(series.files or {}) do
        local current = file
        local saved = Download.existing(series, current)
        items[#items + 1] = {
            text = formatLabel(current, saved),
            mandatory = saved and _("đã tải") or nil,
            keep_menu_open = true,
            callback = function() Detail.download(series, current) end,
        }
    end
    require("booxbook.ui.catalog").show{ title = series.title, items = items }
end

function Detail.show(ref, adapter)
    local _ = require("gettext")
    run(_("Đang lấy thông tin sách…"), function()
        return require("booxbook.http").withBudget(nil, function() return adapter.getSeries(ref) end)
    end, function(series, err)
        if not series then
            notify(tostring(err))
            return
        end
        require("ui/uimanager"):nextTick(function() Detail.showFiles(series) end)
    end)
end

return Detail
