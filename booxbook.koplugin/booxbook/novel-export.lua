local Epub = require("booxbook.epub")
local Html = require("booxbook.html")
local Settings = require("booxbook.store.settings")
local Covers = require("booxbook.covers")
local Http = require("booxbook.http")
local Storage = require("booxbook.store.storage")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local Export = {}

function Export.splitIntoVolumes(saved, volume_size)
    if type(volume_size) ~= "number" or volume_size <= 0 or #saved <= volume_size then
        return { saved }
    end
    local chunks = {}
    local current = {}
    for _, item in ipairs(saved) do
        current[#current + 1] = item
        if #current >= volume_size then
            chunks[#chunks + 1] = current
            current = {}
        end
    end
    if #current > 0 then
        chunks[#chunks + 1] = current
    end
    return chunks
end

function Export.finish(series, dir, first, last, index, result, Json, explicit, volume_size)
    if (not explicit and Settings.get("novel_epub") ~= true) or result.error or #result.saved == 0 then return end
    volume_size = volume_size or Settings.novelVolumeSize()
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

    local chunks = Export.splitIntoVolumes(result.saved, volume_size)
    local html_files = result.saved
    local epubs = {}

    for chunk_idx, chunk in ipairs(chunks) do
        local sub_first = chunk[1].number or first
        local sub_last = chunk[#chunk].number or last
        local title, filename
        if #chunks == 1 then
            title = string.format(_("%s — Chương %d–%d"), series.title or series.id, first, last)
            filename = string.format("chapters-%d-%d.epub", first, last)
        else
            title = string.format(_("%s — Tập %d (Chương %d–%d)"), series.title or series.id, chunk_idx, sub_first, sub_last)
            filename = string.format("chapters-%d-%d.epub", sub_first, sub_last)
        end
        local target = dir .. "/" .. filename
        local epub_doc_title = #chunks == 1 and (series.title or series.id) or title
        local ok, err = Epub.write(target, {
            title = epub_doc_title, author = series.author, description = series.description,
            tags = series.tags, language = series.language, publisher = series.publisher,
            date = series.date, rights = series.rights, url = url, cover_path = cover_path,
            identifier = (url or (source_id .. ":" .. tostring(series.id))) .. "#chapters-" .. sub_first .. "-" .. sub_last,
            chapters = chunk,
        })
        if not ok then
            result.error = _("Không tạo được EPUB; đã giữ bản HTML: ") .. tostring(err)
            return
        end
        epubs[#epubs + 1] = {
            epub = { title = title .. " (EPUB)", path = target },
            filename = filename,
            chunk = chunk,
        }
    end

    -- Cancelled-run packaging always keeps HTML so the user can still resume.
    if result.keep_html == true then
        for idx = #epubs, 1, -1 do
            table.insert(result.saved, 1, epubs[idx].epub)
        end
        return
    end

    -- Commit the new offline targets before deleting any HTML recovery files.
    -- Never `for _, x` here: `_` would shadow gettext `_()` below.
    for _item_index, item in ipairs(epubs) do
        for _saved_index, saved in ipairs(item.chunk) do
            local entry = index.chapters[saved.id]
            if not entry then
                for idx = #epubs, 1, -1 do
                    table.insert(result.saved, 1, epubs[idx].epub)
                end
                result.error = _("Đã giữ HTML vì không cập nhật được danh sách: ") .. _("thiếu mục chương")
                return
            end
            entry.file, entry.export_title = item.filename, item.epub.title
        end
    end

    local encoded_ok, encoded = pcall(Json.encode, index)
    local ok, err
    if encoded_ok and type(encoded) == "string" then
        ok, err = Html.writeFile(dir .. "/index.json", encoded)
    else
        ok, err = false, _("Không ghi được danh sách chương.")
    end
    if not ok then
        for idx = #epubs, 1, -1 do
            table.insert(result.saved, 1, epubs[idx].epub)
        end
        result.error = _("Đã giữ HTML vì không cập nhật được danh sách: ") .. tostring(err)
        return
    end

    result.saved = {}
    for _, item in ipairs(epubs) do
        result.saved[#result.saved + 1] = item.epub
    end

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
