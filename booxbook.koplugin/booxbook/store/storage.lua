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

return Storage
