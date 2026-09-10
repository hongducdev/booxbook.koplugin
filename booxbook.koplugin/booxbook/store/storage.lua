-- Central helpers for disposable image data (news sidecars, covers, comic staging).
-- Library files (HTML/CBZ/EPUB) have their own lifecycle; this module only
-- measures and removes data that can be re-downloaded.
local Storage = {}

local function lfsModule()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok and lfs then return lfs end
    ok, lfs = pcall(require, "lfs")
    if ok and lfs then return lfs end
    return nil
end

-- Directory listing is required for every mutating helper below.
-- KOReader always ships lfs; without it we do nothing (never guess).
function Storage.canList()
    local lfs = lfsModule()
    return lfs ~= nil and type(lfs.dir) == "function"
        and type(lfs.attributes) == "function"
end

-- Snapshot names before unlink: POSIX readdir+remove can skip entries.
local function listedNames(dir)
    local lfs = lfsModule()
    if not (lfs and lfs.dir) then return nil end
    local ok, iter, state = pcall(lfs.dir, dir)
    if not (ok and iter) then return nil end
    local names = {}
    for name in iter, state do
        if name ~= "." and name ~= ".." then
            names[#names + 1] = name
        end
    end
    return names
end

function Storage.sidecarDir(html_path)
    if type(html_path) ~= "string" then return nil end
    return html_path .. ".images"
end

local function isSafeSidecarFile(name)
    if type(name) ~= "string" then return false end
    return name:match("^%d+%.[A-Za-z0-9]+$") ~= nil
        or name:match("^%d+%.[A-Za-z0-9]+%.part$") ~= nil
end

-- Remove files then rmdir. True when the directory is gone (or was absent).
function Storage.emptyDir(dir)
    if type(dir) ~= "string" or not Storage.canList() then return false end
    local lfs = lfsModule()
    local ok_mode, mode = pcall(lfs.attributes, dir, "mode")
    if not (ok_mode and mode == "directory") then return true end
    local names = listedNames(dir)
    if not names then return false end
    for _, name in ipairs(names) do
        os.remove(dir .. "/" .. name)
    end
    os.remove(dir)
    pcall(function() return lfs.rmdir(dir) end)
    ok_mode, mode = pcall(lfs.attributes, dir, "mode")
    return not (ok_mode and mode == "directory")
end

-- Remove every numbered asset inside `<html>.images/` then the dir itself.
-- Returns true when nothing remains (including "was already absent").
-- Without lfs there is nothing verifiable to do; empty dirs are harmless.
function Storage.removeSidecar(html_path)
    local dir = Storage.sidecarDir(html_path)
    if not dir or not Storage.canList() then return true end
    local lfs = lfsModule()
    local ok_mode, mode = pcall(lfs.attributes, dir, "mode")
    if not (ok_mode and mode == "directory") then return true end
    local names = listedNames(dir)
    if not names then return false end
    for _, name in ipairs(names) do
        if isSafeSidecarFile(name) then
            os.remove(dir .. "/" .. name)
        end
    end
    os.remove(dir)
    pcall(function() return lfs.rmdir(dir) end)
    ok_mode, mode = pcall(lfs.attributes, dir, "mode")
    return not (ok_mode and mode == "directory")
end

-- Delete numbered sidecar files not referenced by the current render.
function Storage.pruneSidecar(dir, keep_names)
    if type(dir) ~= "string" or type(keep_names) ~= "table" then return 0 end
    local names = listedNames(dir)
    if not names then return 0 end
    local removed = 0
    for _, name in ipairs(names) do
        if isSafeSidecarFile(name) and not keep_names[name] then
            if os.remove(dir .. "/" .. name) then removed = removed + 1 end
        end
    end
    return removed
end

function Storage.dirSize(dir, max_entries)
    if type(dir) ~= "string" then return 0, 0 end
    local lfs = lfsModule()
    if not (lfs and lfs.dir and lfs.attributes) then return 0, 0 end
    local ok, iter, state = pcall(lfs.dir, dir)
    if not (ok and iter) then return 0, 0 end
    local bytes, count, seen = 0, 0, 0
    max_entries = tonumber(max_entries) or 5000
    for name in iter, state do
        if name ~= "." and name ~= ".." then
            seen = seen + 1
            if seen > max_entries then break end
            local ok_attr, mode = pcall(lfs.attributes, dir .. "/" .. name, "mode")
            if ok_attr and mode == "file" then
                local ok_size, size = pcall(lfs.attributes, dir .. "/" .. name, "size")
                if ok_size and type(size) == "number" then bytes = bytes + size end
                count = count + 1
            end
        end
    end
    return bytes, count
end

-- Walk one extra level (e.g. covers/<source>/*) and sum file sizes.
function Storage.treeSize(root, max_entries)
    if type(root) ~= "string" then return 0, 0 end
    local lfs = lfsModule()
    if not (lfs and lfs.dir and lfs.attributes) then return 0, 0 end
    local ok, iter, state = pcall(lfs.dir, root)
    if not (ok and iter) then return 0, 0 end
    local bytes, count = 0, 0
    for name in iter, state do
        if name ~= "." and name ~= ".." then
            local sub = root .. "/" .. name
            local ok_attr, mode = pcall(lfs.attributes, sub, "mode")
            if ok_attr then
                if mode == "file" then
                    local ok_size, size = pcall(lfs.attributes, sub, "size")
                    if ok_size and type(size) == "number" then bytes = bytes + size end
                    count = count + 1
                elseif mode == "directory" then
                    local b, c = Storage.dirSize(sub, max_entries)
                    bytes, count = bytes + b, count + c
                end
            end
        end
    end
    return bytes, count
end

-- Walk one extra level (e.g. covers/<source>/*). Bounds the whole tree.
-- keep_path is never deleted (the cover that just landed).
-- Missing mtime sorts last so a failed stat cannot evict a new file.
function Storage.trimTreeByMtime(root, max_bytes, max_entries, keep_path)
    max_bytes = tonumber(max_bytes) or 0
    local lfs = lfsModule()
    if not (lfs and lfs.dir and lfs.attributes) then return 0, 0 end
    local ok, iter, state = pcall(lfs.dir, root)
    if not (ok and iter) then return 0, 0 end
    local files, bytes = {}, 0
    max_entries = tonumber(max_entries) or 5000
    for name in iter, state do
        if name ~= "." and name ~= ".." then
            local sub = root .. "/" .. name
            local ok_attr, mode = pcall(lfs.attributes, sub, "mode")
            if ok_attr and mode == "directory" then
                local ok_sub, sub_iter, sub_state = pcall(lfs.dir, sub)
                if ok_sub and sub_iter then
                    for file in sub_iter, sub_state do
                        if file ~= "." and file ~= ".." and #files < max_entries then
                            local path = sub .. "/" .. file
                            local ok_f, fmode = pcall(lfs.attributes, path, "mode")
                            if ok_f and fmode == "file" then
                                local ok_size, size = pcall(lfs.attributes, path, "size")
                                local ok_time, mtime = pcall(lfs.attributes, path, "modification")
                                size = (ok_size and type(size) == "number") and size or 0
                                if not (ok_time and type(mtime) == "number") then
                                    mtime = math.huge
                                end
                                files[#files + 1] = { path = path, size = size, mtime = mtime }
                                bytes = bytes + size
                            end
                        end
                    end
                end
            end
        end
    end
    if bytes <= max_bytes then return 0, bytes end
    table.sort(files, function(a, b) return a.mtime < b.mtime end)
    local freed = 0
    for _, entry in ipairs(files) do
        if bytes <= max_bytes then break end
        if entry.path ~= keep_path and os.remove(entry.path) then
            bytes, freed = bytes - entry.size, freed + entry.size
        end
    end
    return freed, bytes
end

-- Remove every file under root (one extra level deep) and the emptied dirs.
-- Returns true when nothing remains, false when listing is impossible.
function Storage.clearTree(root)
    if type(root) ~= "string" or not Storage.canList() then return false end
    local lfs = lfsModule()
    local ok_mode, mode = pcall(lfs.attributes, root, "mode")
    if not (ok_mode and mode == "directory") then return true end
    local names = listedNames(root)
    if not names then return false end
    for _, name in ipairs(names) do
        local sub = root .. "/" .. name
        local ok_attr, submode = pcall(lfs.attributes, sub, "mode")
        if ok_attr and submode == "directory" then
            local files = listedNames(sub) or {}
            for _, file in ipairs(files) do
                os.remove(sub .. "/" .. file)
            end
            os.remove(sub)
            pcall(function() return lfs.rmdir(sub) end)
        elseif ok_attr and submode == "file" then
            os.remove(sub)
        end
    end
    names = listedNames(root)
    if not names then return false end
    return #names == 0
end

-- Remove `*.images/` dirs whose HTML no longer exists (abandoned refreshes).
function Storage.sweepOrphanSidecars(root)
    if type(root) ~= "string" then return 0 end
    local lfs = lfsModule()
    if not (lfs and lfs.dir and lfs.attributes) then return 0 end
    local swept = 0
    local function scan(dir, depth)
        if depth > 3 then return end
        local names = listedNames(dir)
        if not names then return end
        for _, name in ipairs(names) do
            local path = dir .. "/" .. name
            local ok_attr, mode = pcall(lfs.attributes, path, "mode")
            if ok_attr and mode == "directory" then
                if name:match("%.images$") then
                    local html = path:sub(1, -8)
                    local ok_html, html_mode = pcall(lfs.attributes, html, "mode")
                    if not (ok_html and html_mode == "file") then
                        if Storage.removeSidecar(html) then
                            swept = swept + 1
                        end
                    end
                else
                    scan(path, depth + 1)
                end
            end
        end
    end
    scan(root, 1)
    return swept
end
-- Remove empty subdirectories under root (e.g. empty feed folders in news).
function Storage.sweepEmptyDirs(root)
    if type(root) ~= "string" or not Storage.canList() then return 0 end
    local lfs = lfsModule()
    local ok_root, root_mode = pcall(lfs.attributes, root, "mode")
    if not (ok_root and root_mode == "directory") then return 0 end
    local swept = 0
    local names = listedNames(root) or {}
    for _, name in ipairs(names) do
        local dir = root .. "/" .. name
        local ok_dir, dmode = pcall(lfs.attributes, dir, "mode")
        if ok_dir and dmode == "directory" then
            local children = listedNames(dir) or {}
            if #children == 0 then
                if Storage.emptyDir(dir) then
                    swept = swept + 1
                end
            end
        end
    end
    return swept
end


local function collectCategoryFiles(root)
    local lfs = lfsModule()
    if type(root) ~= "string" or not (lfs and lfs.dir and lfs.attributes) then
        return {}, 0, 0
    end

    local files, bytes, count = {}, 0, 0
    local function scan(dir)
        local names = listedNames(dir)
        if not names then return end
        for _, name in ipairs(names) do
            local path = dir .. "/" .. name
            local ok_attr, mode = pcall(lfs.attributes, path, "mode")
            if ok_attr and mode == "file" then
                local filename = name:lower()
                local is_metadata = filename == "index.json" or filename == "index.json.bak"
                    or filename == "manifest.json" or filename:match("%.meta%.json$")
                local ok_size, size = pcall(lfs.attributes, path, "size")
                local ok_time, mtime = pcall(lfs.attributes, path, "modification")
                size = (ok_size and type(size) == "number") and size or 0
                if not (ok_time and type(mtime) == "number") then
                    mtime = math.huge
                end
                files[#files + 1] = { path = path, size = size, mtime = mtime, is_metadata = is_metadata }
                bytes = bytes + size
                count = count + 1
            elseif ok_attr and mode == "directory" then
                scan(path)
            end
        end
    end

    scan(root)
    return files, bytes, count
end

function Storage.categorySize(category_dir)
    local _, bytes, count = collectCategoryFiles(category_dir)
    return bytes, count
end

function Storage.trimCategoryFifo(dir, max_bytes, is_eviction_allowed)
    local current = Storage.categorySize(dir)
    if is_eviction_allowed ~= true then
        return 0, current
    end

    max_bytes = tonumber(max_bytes) or 0
    if max_bytes <= 0 then
        return 0, current
    end

    local files, bytes = collectCategoryFiles(dir)
    if bytes <= max_bytes then
        return 0, bytes
    end

    table.sort(files, function(a, b)
        if a.mtime == b.mtime then return a.path < b.path end
        return a.mtime < b.mtime
    end)

    local freed = 0
    for _, entry in ipairs(files) do
        if bytes <= max_bytes then break end
        if not entry.is_metadata and os.remove(entry.path) then
            bytes = bytes - entry.size
            freed = freed + entry.size
        end
    end
    return freed, bytes
end

function Storage.sweepStaleDigests(received_dir, max_days)
    if type(received_dir) ~= "string" then return 0 end
    local lfs = lfsModule()
    if not (lfs and lfs.dir and lfs.attributes) then return 0 end
    max_days = tonumber(max_days) or 30
    local max_age = max_days * 86400
    local now = os.time()
    local swept = 0
    local names = listedNames(received_dir)
    if not names then return 0 end
    for _, name in ipairs(names) do
        if name:match("^digest%-.*%.epub$") then
            local path = received_dir .. "/" .. name
            local ok_mode, mode = pcall(lfs.attributes, path, "mode")
            local ok_time, mtime = pcall(lfs.attributes, path, "modification")
            if ok_mode and mode == "file" and ok_time and type(mtime) == "number"
                and now - mtime > max_age and os.remove(path) then
                swept = swept + 1
            end
        end
    end
    return swept
end

function Storage.sweepOrphanParts(root_dir, max_age_seconds)
    if type(root_dir) ~= "string" then return 0 end
    local lfs = lfsModule()
    if not (lfs and lfs.dir and lfs.attributes) then return 0 end
    max_age_seconds = tonumber(max_age_seconds) or 86400
    local now = os.time()
    local swept = 0

    local function scan(dir)
        local names = listedNames(dir)
        if not names then return end
        for _, name in ipairs(names) do
            local path = dir .. "/" .. name
            local ok_attr, mode = pcall(lfs.attributes, path, "mode")
            if ok_attr and mode == "directory" then
                scan(path)
            elseif ok_attr and mode == "file" and name:match("%.part$") then
                local ok_time, mtime = pcall(lfs.attributes, path, "modification")
                if ok_time and type(mtime) == "number"
                    and now - mtime > max_age_seconds and os.remove(path) then
                    swept = swept + 1
                end
            end
        end
    end

    scan(root_dir)
    return swept
end

local function settingValue(settings_getter, key, default)
    local value
    if type(settings_getter) == "function" then
        value = settings_getter(key)
    elseif type(settings_getter) == "table" and type(settings_getter.get) == "function" then
        local ok
        ok, value = pcall(settings_getter.get, key)
        if not ok then
            ok, value = pcall(settings_getter.get, settings_getter, key)
        end
        if not ok then value = nil end
    else
        local ok_settings, Settings = pcall(require, "booxbook.store.settings")
        if ok_settings and Settings and type(Settings.get) == "function" then
            value = Settings.get(key)
        end
    end
    if value == nil then return default end
    return value
end

local function quotaBytes(settings_getter, key)
    local mb = tonumber(settingValue(settings_getter, key, 0)) or 0
    if mb <= 0 then return nil end
    return mb * 1024 * 1024
end

function Storage.runGlobalMaintenance(download_dir, settings_getter)
    local stats = {
        stale_digests = 0,
        orphan_parts = 0,
        orphan_sidecars = 0,
        quotas = {},
    }
    if type(download_dir) ~= "string" or download_dir == "" then
        return stats
    end

    stats.stale_digests = Storage.sweepStaleDigests(download_dir .. "/received", 30)
    stats.orphan_parts = Storage.sweepOrphanParts(download_dir, 86400)
    stats.orphan_sidecars = Storage.sweepOrphanSidecars(download_dir .. "/news")

    local categories = {
        { name = "news", key = "quota_news_mb", allowed = true },
        { name = "received", key = "quota_received_mb", allowed = true },
        { name = "novels", key = "quota_novels_mb", evict_key = "quota_novels_evict" },
        { name = "comics", key = "quota_comics_mb", evict_key = "quota_comics_evict" },
    }

    for _, category in ipairs(categories) do
        local dir = download_dir .. "/" .. category.name
        local max_bytes = quotaBytes(settings_getter, category.key)
        local allowed = category.allowed == true
        if category.evict_key then
            allowed = settingValue(settings_getter, category.evict_key, false) == true
        end
        if max_bytes then
            local freed, remaining = Storage.trimCategoryFifo(dir, max_bytes, allowed)
            stats.quotas[category.name] = {
                freed = freed,
                remaining = remaining,
                max_bytes = max_bytes,
                eviction_allowed = allowed,
            }
        else
            local bytes = Storage.categorySize(dir)
            stats.quotas[category.name] = {
                freed = 0,
                remaining = bytes,
                max_bytes = 0,
                eviction_allowed = allowed,
            }
        end
        Storage.sweepEmptyDirs(dir)
    end

    return stats
end

return Storage
