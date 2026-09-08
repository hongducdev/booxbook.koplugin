local Source = require("booxbook.sources.truyentuoitho")
local Http = require("booxbook.http")
local Html = require("booxbook.html")
local Images = require("booxbook.article-images")
local Settings = require("booxbook.store.settings")
local Storage = require("booxbook.store.storage")
local Cbz = require("booxbook.comic-cbz")
local _ = require("gettext")
local Download = { MAX_IMAGE = 8 * 1024 * 1024, MAX_TOTAL = 512 * 1024 * 1024 }
Download.CANCELLED = "booxbook:cancelled"

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

local function isCancelErr(err)
    return err == Download.CANCELLED
end

function Download.isCancelErr(err) return isCancelErr(err) end

local function cancelPartial(url, staging, downloaded, total)
    return nil, Download.CANCELLED, {
        cancelled = true, downloaded = downloaded, total = total, staging = staging, url = url,
    }
end

-- Collect already-downloaded staging pages for a chapter URL.
-- Returns pages list (for Cbz.write) + staging dir, or nil + err.
function Download.stagingPages(url)
    local path, path_err = Download.path(url)
    if not path then return nil, path_err end
    local ref = Source.parseRef(url)
    if not ref then return nil, _("URL tập Truyện Tuổi Thơ không hợp lệ.") end
    local dir = path:match("^(.*)/[^/]+$")
    local staging = dir .. "/." .. ref.chapter .. "-pages"
    local pages = {}
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or not lfs then ok, lfs = pcall(require, "lfs") end
    if ok and lfs and lfs.dir and lfs.attributes then
        local ok_dir, iter, state = pcall(lfs.dir, staging)
        if not (ok_dir and iter) then return nil, _("Chưa có ảnh nào được tải.") end
        local by_index = {}
        for name in iter, state do
            local n = name:match("^(%d%d%d%d)$")
            if n then
                local target = staging .. "/" .. name
                local ext, size = inspect(target)
                if ext then by_index[tonumber(n)] = { path = target, size = size, name = string.format("%04d.%s", tonumber(n), ext) } end
            end
        end
        local max_n = 0
        for n in pairs(by_index) do max_n = math.max(max_n, n) end
        for i = 1, max_n do
            if not by_index[i] then return nil, _("Ảnh tải dở còn thiếu trang ") .. i end
            pages[i] = by_index[i]
        end
    else
        for i = 1, 600 do
            local target = staging .. "/" .. string.format("%04d", i)
            local probe = io.open(target, "rb")
            if not probe then break end
            probe:close()
            local ext, size = inspect(target)
            if not ext then break end
            pages[i] = { path = target, size = size, name = string.format("%04d.%s", i, ext) }
        end
    end
    if #pages == 0 then return nil, _("Chưa có ảnh nào được tải.") end
    return pages, staging
end

-- Package a partial CBZ from staging pages after user confirms.
-- Keeps staging on failure so the user can resume; cleans it on success.
function Download.packageStaging(url, progress)
    local pages, staging = Download.stagingPages(url)
    if not pages then return nil, staging end
    local path, path_err = Download.path(url)
    if not path then return nil, path_err end
    local result, pack_err = Cbz.write(path, pages, progress)
    if not result then
        if pack_err == Cbz.CANCELLED then
            return nil, _("Đã hủy đóng gói; đã giữ ảnh để tải tiếp.")
        end
        return nil, pack_err
    end
    for _, page in ipairs(pages) do
        os.remove(page.path .. ".url")
        os.remove(page.path)
    end
    pcall(Storage.emptyDir, staging)
    return result
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
        if progress and progress(i, #chapter.pages, false) == false then
            return cancelPartial(url, staging, i - 1, #chapter.pages)
        end
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
    if not result then
        if pack_err == Cbz.CANCELLED then
            return cancelPartial(url, staging, #pages, #chapter.pages)
        end
        return nil, pack_err
    end
    for _, page in ipairs(pages) do
        os.remove(page.path .. ".url")
        os.remove(page.path)
    end
    pcall(Storage.emptyDir, staging)
    return result
end

-- Remove abandoned staging (`.-pages/` dirs + `.part` files) older than
-- max_age_days whose CBZ was never published. Best-effort, never touches CBZ.
-- Returns the number of staging dirs/files removed.
function Download.sweepStale(max_age_days)
    max_age_days = tonumber(max_age_days) or 7
    if max_age_days < 0 then return 0 end
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or not lfs then
        ok, lfs = pcall(require, "lfs")
    end
    if not ok or not lfs or not lfs.dir or not lfs.attributes then return 0 end
    local root = Settings.downloadDir() .. "/comics/truyentuoitho"
    local now = os.time()
    local swept = 0
    local function dirMtime(dir)
        local newest = nil
        local ok_dir, iter, state = pcall(lfs.dir, dir)
        if not (ok_dir and iter) then return nil end
        for name in iter, state do
            if name ~= "." and name ~= ".." then
                local ok_t, mtime = pcall(lfs.attributes, dir .. "/" .. name, "modification")
                if ok_t and type(mtime) == "number" and (not newest or mtime > newest) then
                    newest = mtime
                end
            end
        end
        return newest
    end
    local ok_root, root_iter, root_state = pcall(lfs.dir, root)
    if not (ok_root and root_iter) then return 0 end
    for series in root_iter, root_state do
        if series ~= "." and series ~= ".." then
            local series_dir = root .. "/" .. series
            local ok_attr, mode = pcall(lfs.attributes, series_dir, "mode")
            if ok_attr and mode == "directory" then
                local ok_s, s_iter, s_state = pcall(lfs.dir, series_dir)
                if ok_s and s_iter then
                    for name in s_iter, s_state do
                        local path = series_dir .. "/" .. name
                        if name:match("^%.") and name:match("%-pages$") then
                            local mtime = dirMtime(path)
                            -- Empty leftover dirs (pages already packed or never written)
                            -- have no file mtime; reclaim them. Aged dirs with files too.
                            if not mtime or (now - mtime) > max_age_days * 86400 then
                                if Storage.emptyDir(path) then swept = swept + 1 end
                            end
                        elseif name:match("%.part$") then
                            local ok_t, mtime = pcall(lfs.attributes, path, "modification")
                            if ok_t and type(mtime) == "number"
                                and (now - mtime) > max_age_days * 86400 then
                                if os.remove(path) then swept = swept + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    return swept
end

function Download.range(series, first, last, progress)
    local count = type(series) == "table" and #(series.chapters or {}) or 0
    if type(first) ~= "number" or type(last) ~= "number" or first % 1 ~= 0 or last % 1 ~= 0
        or first < 1 or last < first or last > count then return nil, _("Khoảng tập không hợp lệ.") end
    local result = { saved = {}, cancelled = false }
    for n = first, last do
        local chapter = series.chapters[n]
        if not Source.parseRef(chapter) or Source.parseRef(chapter).series ~= series.id then
            result.error = _("Tập không thuộc bộ truyện."); break
        end
        if progress and progress(n - first + 1, last - first + 1, chapter, 0, 0, false) == false then
            result.cancelled = true
            result.cancelled_at = n
            result.error = _("Đã hủy tải; chọn đóng gói để giữ CBZ partial hoặc giữ ảnh để tải tiếp.")
            break
        end
        local ok, path, err, partial = pcall(Download.chapter, chapter.url, function(i, total, packing)
            if progress then return progress(n - first + 1, last - first + 1, chapter, i, total, packing) end
        end)
        if not ok or not path then
            result.error = ok and err or path
            if ok and (err == Download.CANCELLED or partial) then
                result.cancelled = true
                result.cancelled_at = n
                result.partial_url = chapter.url
                result.partial = partial
                result.error = _("Đã hủy tải; chọn đóng gói để giữ CBZ partial hoặc giữ ảnh để tải tiếp.")
            end
            break
        end
        result.saved[#result.saved + 1] = { title = chapter.title, path = path, number = n }
    end
    return result
end

return Download
