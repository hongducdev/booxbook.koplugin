local Docln = require("booxbook.sources.docln")
local Html = require("booxbook.html")
local Parser = require("booxbook.sources.docln-parser")
local Settings = require("booxbook.store.settings")
local has_gettext, gettext = pcall(require, "gettext")
local _ = has_gettext and gettext or function(text) return text end
local Download = {}

function Download.range(series, first, last, confirmed, progress)
    local path, id = Parser.path(series.url)
    if not path or id ~= series.id or type(first) ~= "number" or type(last) ~= "number"
        or first % 1 ~= 0 or last % 1 ~= 0 or first < 1 or last < first or last > #series.chapters then
        return nil, _("Khoảng chương không hợp lệ.")
    end
    if last - first + 1 > 50 and not confirmed then return nil, _("Cần xác nhận khi tải hơn 50 chương.") end
    if series.adult and not Settings.adultContent() then return nil, _("Nội dung 18+ đang tắt.") end
    local json_ok, Json = pcall(require, "json")
    if not json_ok then return nil, _("Không có thư viện JSON của KOReader.") end
    local dir = Settings.downloadDir() .. "/novels/docln/" .. id
    if not Settings.ensureDir(dir) then return nil, _("Không tạo được thư mục truyện.") end
    local index_path, index = dir .. "/index.json", { id = id, title = series.title, chapters = {} }
    local file, read_err, read_code = io.open(index_path, "rb")
    if not file and read_code and read_code ~= 2 then return nil, read_err end
    if file then
        local content = file:read("*a"); file:close()
        local ok, saved = pcall(Json.decode, content)
        if not ok or type(saved) ~= "table" or saved.id ~= id or type(saved.chapters) ~= "table" then
            return nil, _("index.json bị lỗi; giữ nguyên dữ liệu đã tải.")
        end
        index = saved
    end
    local result = { saved = {}, skipped = {} }
    for number = first, last do
        local chapter = series.chapters[number]
        if progress and progress(number - first + 1, last - first + 1, chapter) == false then
            result.error = _("Đã dừng tải."); break
        end
        local chapter_path, chapter_series = Parser.path(chapter)
        local chapter_id = chapter_path and chapter_path:match("/c(%d+)")
        if chapter_series ~= id or not chapter_id or #chapter_id > 12 then
            result.error = _("Đường dẫn chương không thuộc truyện này."); break
        end
        local content, err = Docln.getChapter(chapter)
        if not content then result.error = err; break end
        local entry = { title = chapter.title, url = chapter.url, number = number }
        if content.skipped then
            entry.skipped = content.skipped
            result.skipped[#result.skipped + 1] = { title = chapter.title, reason = content.skipped }
            -- A later locked response must not remove a previously downloaded chapter.
            if index.chapters[chapter_id] then entry = index.chapters[chapter_id] end
        else
            entry.file = string.format("ch-%012d.html", tonumber(chapter_id))
            local target = dir .. "/" .. entry.file
            local document = Html.wrapDocument(chapter.title, "<h1>" .. Html.escape(chapter.title) .. "</h1>" .. content.html)
            local ok, write_err = Html.writeFile(target, document)
            if not ok then result.error = write_err; break end
            result.saved[#result.saved + 1] = { title = chapter.title, path = target }
        end
        index.chapters[chapter_id] = entry
        local encoded_ok, encoded = pcall(Json.encode, index)
        if not encoded_ok or type(encoded) ~= "string" then result.error = _("Không ghi được danh sách chương."); break end
        local ok, write_err = Html.writeFile(index_path, encoded)
        if not ok then result.error = write_err; break end
    end
    return result
end

return Download
