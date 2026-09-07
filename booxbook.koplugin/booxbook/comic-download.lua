local Source = require("booxbook.sources.truyentuoitho")
local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Images = require("booxbook.article-images")
local Settings = require("booxbook.store.settings")
local Cbz = require("booxbook.comic-cbz")
local _ = require("gettext")
local Download = { MAX_IMAGE = 8 * 1024 * 1024, MAX_TOTAL = 512 * 1024 * 1024 }

local function inspect(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local head = file:read(12) or ""
    local size = file:seek("end")
    file:close()
    local ext = Images.extension(head)
    if not ext or not size or size < 12 or size > Download.MAX_IMAGE then return nil end
    if ext == "webp" then
        local a, b, c, d = head:byte(5, 8)
        if a + b * 256 + c * 65536 + d * 16777216 + 8 ~= size then return nil end
    end
    return ext, size
end

function Download.path(url)
    local ref = Source.parseRef(url)
    if not ref then return nil, _("URL tập Truyện Tuổi Thơ không hợp lệ.") end
    return Settings.downloadDir() .. "/comics/truyentuoitho/" .. ref.series .. "/" .. ref.chapter .. ".cbz"
end

function Download.savedPath(url)
    local path, err = Download.path(url)
    if not path then return nil, err end
    local existing = io.open(path, "rb")
    if existing then
        existing:close()
        local valid, err = Cbz.verify(path)
        if valid then return path end
        return nil, _("CBZ cũ bị lỗi; hãy di chuyển hoặc xóa trong Thư viện trước khi tải lại. ") .. tostring(err)
    end
end

function Download.chapter(url, progress)
    local path, path_err = Download.path(url)
    if not path then return nil, path_err end
    local existing, existing_err = Download.savedPath(url)
    if existing or existing_err then return existing, existing_err end
    local ref = Source.parseRef(url)
    local dir = path:match("^(.*)/[^/]+$")
    local chapter, err = Source.getChapter(ref.url)
    if not chapter then return nil, err end
    local staging = dir .. "/." .. ref.chapter .. "-pages"
    if not Settings.ensureDir(staging) then return nil, _("Không tạo được thư mục tải ảnh.") end
    local pages, total = {}, 0
    for i, image_url in ipairs(chapter.pages) do
        if progress and progress(i, #chapter.pages, false) == false then return nil, _("Đã dừng tải; chọn lại tập hoặc khoảng tập để tiếp tục.") end
        local target = staging .. "/" .. string.format("%04d", i)
        local receipt = io.open(target .. ".url", "rb")
        local saved = receipt and receipt:read(8192)
        if receipt then receipt:close() end
        local ext, size = inspect(target)
        if not ext or saved ~= image_url .. "\n" .. tostring(size) then
            if total >= Download.MAX_TOTAL then return nil, _("Tập vượt giới hạn 512 MiB của bản thử.") end
            local pending = target .. ".part"
            local ok, code, body, headers = Http.downloadToFile(image_url, pending, {
                referer = chapter.url, delay_ms = 1600, max_body = math.min(Download.MAX_IMAGE, Download.MAX_TOTAL - total),
                timeout = 15, maxtime = 60, headers = { accept = "image/*" },
                allow_url = function(next_url) return Source.imageUrl(chapter.url, next_url) ~= nil end,
            })
            if not ok then return nil, _("Không tải được trang ") .. i .. ": " .. tostring(code) end
            ext, size = inspect(pending)
            local declared
            for key, value in pairs(headers or {}) do
                if key:lower() == "content-length" then declared = tonumber(value) end
            end
            if not ext or (declared and declared ~= size) then
                os.remove(pending)
                return nil, _("Ảnh không hợp lệ hoặc thiếu dữ liệu ở trang ") .. i
            end
            -- Only disposable staging pages are replaced, never the published CBZ.
            os.remove(target .. ".url")
            os.remove(target)
            local renamed, rename_err = os.rename(pending, target)
            if not renamed then return nil, rename_err end
            local written, write_err = Html.writeFile(target .. ".url", image_url .. "\n" .. size)
            if not written then return nil, write_err end
        end
        total = total + size
        if total > Download.MAX_TOTAL then return nil, _("Tập vượt giới hạn 512 MiB của bản thử.") end
        pages[i] = { path = target, size = size, name = string.format("%04d.%s", i, ext) }
    end
    local result, pack_err = Cbz.write(path, pages, progress)
    if not result then return nil, pack_err end
    for _, page in ipairs(pages) do
        os.remove(page.path .. ".url")
        os.remove(page.path)
    end
    return result
end

function Download.range(series, first, last, progress)
    local count = type(series) == "table" and #(series.chapters or {}) or 0
    if type(first) ~= "number" or type(last) ~= "number" or first % 1 ~= 0 or last % 1 ~= 0
        or first < 1 or last < first or last > count then return nil, _("Khoảng tập không hợp lệ.") end
    local result = { saved = {} }
    for n = first, last do
        local chapter = series.chapters[n]
        if not Source.parseRef(chapter) or Source.parseRef(chapter).series ~= series.id then
            result.error = _("Tập không thuộc bộ truyện."); break
        end
        if progress and progress(n - first + 1, last - first + 1, chapter, 0, 0, false) == false then
            result.error = _("Đã dừng tải; chọn lại khoảng tập để tiếp tục."); break
        end
        local ok, path, err = pcall(Download.chapter, chapter.url, function(i, total, packing)
            if progress then return progress(n - first + 1, last - first + 1, chapter, i, total, packing) end
        end)
        if not ok or not path then result.error = ok and err or path; break end
        result.saved[#result.saved + 1] = { title = chapter.title, path = path, number = n }
    end
    return result
end

return Download
