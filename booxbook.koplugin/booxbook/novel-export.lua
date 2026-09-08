local Epub = require("booxbook.epub")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local Covers = require("booxbook.covers")
local Http = require("booxbook.http")
local Storage = require("booxbook.store.storage")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local Export = {}

function Export.finish(series, dir, first, last, index, result, Json)
    if Settings.get("novel_epub") ~= true or result.error or #result.saved == 0 then return end
    local title = string.format(_("%s — Chương %d–%d"), series.title or series.id, first, last)
    local filename = string.format("chapters-%d-%d.epub", first, last)
    local target = dir .. "/" .. filename
    local source_id = series.source_id or "docln"
    local url = series.url
    if source_id == "docln" then url = Http.resolveUrl(Settings.get("docln_home") or "https://docln.net", url) end
    local cover_path
    if type(series.cover) == "string" and series.cover ~= "" then
        cover_path = Covers.fetch(source_id, Http.resolveUrl(url or "", series.cover), {
            referer = url, max_bytes = 2 * 1024 * 1024,
        })
        if not cover_path then
            result.error = _("Không tải được ảnh bìa; đã giữ HTML. Hãy thử tải lại.")
            return
        end
    end
    local ok, err = Epub.write(target, {
        title = series.title or series.id, author = series.author, description = series.description,
        tags = series.tags, language = series.language, publisher = series.publisher,
        date = series.date, rights = series.rights, url = url, cover_path = cover_path,
        identifier = (url or (source_id .. ":" .. tostring(series.id))) .. "#chapters-" .. first .. "-" .. last,
        chapters = result.saved,
    })
    if not ok then
        result.error = _("Không tạo được EPUB; đã giữ bản HTML: ") .. tostring(err)
        return
    end
    local html_files = result.saved
    local epub = { title = title .. " (EPUB)", path = target }
    if Settings.get("novel_keep_html") ~= false then
        table.insert(result.saved, 1, epub)
        return
    end
    -- Commit the new offline targets before deleting any HTML recovery files.
    for position, saved in ipairs(html_files) do
        local entry = index.chapters[saved.id]
        if not entry then
            table.insert(result.saved, 1, epub)
            result.error = _("Đã giữ HTML vì không cập nhật được danh sách: ") .. _("thiếu mục chương")
            return
        end
        entry.file, entry.export_title = filename, epub.title
    end
    local encoded_ok, encoded = pcall(Json.encode, index)
    if encoded_ok and type(encoded) == "string" then
        ok, err = Html.writeFile(dir .. "/index.json", encoded)
    else
        ok, err = false, _("Không ghi được danh sách chương.")
    end
    if not ok then
        table.insert(result.saved, 1, epub)
        result.error = _("Đã giữ HTML vì không cập nhật được danh sách: ") .. tostring(err)
        return
    end
    result.saved = { epub }
    for position, saved in ipairs(html_files) do
        local removed, remove_err = os.remove(saved.path)
        if not removed then
            for index_pos = position, #html_files do
                local leftover = html_files[index_pos]
                result.saved[#result.saved + 1] = leftover
                local entry = index.chapters[leftover.id]
                if entry then
                    entry.file = leftover.path:match("([^/\\]+)$")
                    entry.export_title = nil
                end
            end
            encoded_ok, encoded = pcall(Json.encode, index)
            if encoded_ok and type(encoded) == "string" then
                Html.writeFile(dir .. "/index.json", encoded)
            end
            result.error = _("Đã tạo EPUB nhưng không xóa được HTML: ") .. tostring(remove_err)
            return
        end
        -- Chapter HTML currently holds text only; drop any image sidecar anyway.
        pcall(Storage.removeSidecar, saved.path)
    end
end

return Export
