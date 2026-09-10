-- Morning automated follow checking & digest generation.
-- Non-blocking tick-scheduled state machine: runs one check per tick (Network.ifOnline).
-- Rotating cursor ensures entries > 20 are never starved across successive runs.
local MorningSync = {
    CHECK_INTERVAL = 24 * 3600,
    BATCH_SIZE = 20,
}

function MorningSync.shouldSync(last, now)
    last = tonumber(last) or 0
    now = tonumber(now) or os.time()
    if last <= 0 then return true end
    if (now - last) >= MorningSync.CHECK_INTERVAL then return true end
    local last_day = os.date("%Y%m%d", last)
    local now_day = os.date("%Y%m%d", now)
    return last_day ~= now_day
end

function MorningSync.lastSync(deps)
    local Settings = deps and deps.Settings
    if not Settings then
        local ok, s = pcall(require, "booxbook.store.settings")
        if ok then Settings = s end
    end
    if not Settings or not Settings.get then return 0 end
    return tonumber(Settings.get("morning_sync_last_time")) or 0
end

function MorningSync.noteSynced(now, deps)
    local Settings = deps and deps.Settings
    if not Settings then
        local ok, s = pcall(require, "booxbook.store.settings")
        if ok then Settings = s end
    end
    if not Settings or not Settings.set then return end
    Settings.set("morning_sync_last_time", tonumber(now) or os.time())
end

function MorningSync.scheduleTick(deps, fn)
    local UIManager = deps and deps.UIManager
    if not UIManager then
        local ok, u = pcall(require, "ui/uimanager")
        if ok then UIManager = u end
    end
    if UIManager and type(UIManager.nextTick) == "function" then
        UIManager:nextTick(fn)
    else
        fn()
    end
end

-- Pick a fair window of entries using a rotating cursor to prevent starvation.
function MorningSync.pickBatch(list, cursor, batch_size)
    list = list or {}
    batch_size = math.max(1, tonumber(batch_size) or MorningSync.BATCH_SIZE)
    local total = #list
    if total == 0 then return {}, 1 end

    cursor = tonumber(cursor) or 1
    if cursor < 1 or cursor > total then cursor = 1 end

    local picked = {}
    local count = math.min(total, batch_size)
    for i = 0, count - 1 do
        local idx = ((cursor - 1 + i) % total) + 1
        picked[#picked + 1] = list[idx]
    end

    local next_cursor = ((cursor - 1 + count) % total) + 1
    return picked, next_cursor
end

local function defaultCollectNews(news_dir, deps)
    local lfs = deps and deps.lfs
    if not lfs then
        local ok, l = pcall(require, "libs/libkoreader-lfs")
        if ok and l then lfs = l else
            local ok2, l2 = pcall(require, "lfs")
            if ok2 then lfs = l2 end
        end
    end
    local out = {}
    if not lfs or not lfs.dir or not lfs.attributes then return out end

    local function scan(dir, depth)
        if depth > 3 then return end
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok or not iter then return end
        for name in iter, state do
            if name ~= "." and name ~= ".." then
                local path = dir .. "/" .. name
                local ok_attr, mode = pcall(lfs.attributes, path, "mode")
                if ok_attr and mode == "directory" then
                    scan(path, depth + 1)
                elseif ok_attr and mode == "file" and name:match("%.html$") then
                    local ok_time, mtime = pcall(lfs.attributes, path, "modification")
                    out[#out + 1] = {
                        path = path,
                        title = name:gsub("%.html$", ""),
                        mtime = (ok_time and type(mtime) == "number") and mtime or 0,
                    }
                end
            end
        end
    end

    scan(news_dir, 1)
    table.sort(out, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
    return out
end

function MorningSync.syncDigest(deps)
    deps = deps or {}
    local Digest = deps.Digest
    if not Digest then
        local ok, d = pcall(require, "booxbook.digest")
        if ok then Digest = d end
    end
    local Settings = deps.Settings
    if not Settings then
        local ok, s = pcall(require, "booxbook.store.settings")
        if ok then Settings = s end
    end
    if not Digest or not Settings then return nil, "no_modules" end

    local download_dir = Settings.downloadDir and Settings.downloadDir() or "."
    local dest_dir = download_dir .. "/received"
    if Settings.ensureDir then Settings.ensureDir(dest_dir) end

    local filename = Digest.filename and Digest.filename() or ("digest-" .. os.date("%Y%m%d") .. ".epub")
    local dest_path = dest_dir .. "/" .. filename

    local file_exists = deps.fileExists
    if not file_exists then
        file_exists = function(path)
            local f = io.open(path, "rb")
            if f then f:close(); return true end
            return false
        end
    end

    if file_exists(dest_path) then
        return dest_path, "already_exists"
    end

    local collectFn = deps.collectNews or defaultCollectNews
    local files = collectFn(download_dir .. "/news", deps)
    if #files == 0 then
        return nil, "no_news"
    end

    local cursor_mtime = tonumber(Settings.get and Settings.get("digest_cursor_mtime")) or 0
    local cursor_path = tostring(Settings.get and Settings.get("digest_cursor_path") or "")

    local fresh_files = {}
    for _, file in ipairs(files) do
        local path = type(file) == "table" and file.path or file
        local mtime = type(file) == "table" and tonumber(file.mtime) or 0
        local is_newer = false
        if mtime > cursor_mtime then
            is_newer = true
        elseif mtime == cursor_mtime and tostring(path) > cursor_path then
            is_newer = true
        end
        if is_newer then
            local title = type(file) == "table" and (file.title or file.name) or path
            fresh_files[#fresh_files + 1] = { path = path, title = title, mtime = mtime }
        end
    end

    if #fresh_files == 0 then
        return nil, "no_new_articles"
    end

    -- Sort oldest-first so 21+ files are never skipped or starved
    table.sort(fresh_files, function(a, b)
        if a.mtime ~= b.mtime then return a.mtime < b.mtime end
        return tostring(a.path) < tostring(b.path)
    end)

    local picked = Digest.pick(fresh_files, Digest.MAX_FILES or 20)
    if #picked == 0 then
        return nil, "no_news"
    end

    local result, err = Digest.build(dest_path, picked, deps)
    if not result then
        return nil, err or "build_failed"
    end

    -- Advance cursor deterministically to the last picked file (read from fresh_files which preserves mtime)
    local last_item = fresh_files[#picked]
    if Settings.set and last_item then
        Settings.set("digest_cursor_mtime", last_item.mtime)
        Settings.set("digest_cursor_path", last_item.path)
    end
    return dest_path, "created"
end

function MorningSync.runIfDue(deps, on_progress, on_done)
    deps = deps or {}
    local Settings = deps.Settings
    if not Settings then
        local ok, s = pcall(require, "booxbook.store.settings")
        if ok then Settings = s end
    end
    local Network = deps.Network
    if not Network then
        local ok, n = pcall(require, "booxbook.network")
        if ok then Network = n end
    end
    local Follow = deps.Follow
    if not Follow then
        local ok, f = pcall(require, "booxbook.follow")
        if ok then Follow = f end
    end
    local Source = deps.Source
    if not Source then
        local ok, src = pcall(require, "booxbook.source")
        if ok then Source = src end
    end

    if Settings and Settings.get and Settings.get("auto_morning_sync") == false then
        if on_done then on_done({ status = "disabled" }) end
        return false, "disabled"
    end

    local last = MorningSync.lastSync(deps)
    local now = deps.now or os.time()
    if not MorningSync.shouldSync(last, now) then
        if on_done then on_done({ status = "not_due" }) end
        return false, "not_due"
    end

    if not Network or not Network.ifOnline then
        if on_done then on_done({ status = "no_network_module" }) end
        return false, "no_network_module"
    end

    -- Passive gate: runs only when Wi-Fi is already active
    local triggered = Network.ifOnline(function()
        local saved_followed = Settings and Settings.get and Settings.get("followed_series") or {}
        local list = Follow and Follow.list(saved_followed) or {}
        local cursor = Settings and Settings.get and tonumber(Settings.get("morning_sync_cursor")) or 1
        local batch, next_cursor = MorningSync.pickBatch(list, cursor, MorningSync.BATCH_SIZE)

        if Settings and Settings.set then
            Settings.set("morning_sync_cursor", next_cursor)
        end

        local series_count = 0
        local total_new_ch = 0
        local Trapper = deps.Trapper
        if not Trapper then
            local ok, t = pcall(require, "ui/trapper")
            if ok then Trapper = t end
        end

        -- Tick-scheduled state machine: process one series per tick
        local function checkStep(step_idx)
            if step_idx <= #batch then
                local entry = batch[step_idx]
                local adapter = Source and Source.get(entry.source_id)
                if adapter and adapter.getSeries then
                    local ref = (entry.url and entry.url ~= "") and entry.url or entry.id
                    if ref and ref ~= "" then
                        local run_query = function()
                            local ok, series = pcall(adapter.getSeries, ref)
                            if ok and type(series) == "table" then
                                local live = type(series.chapters) == "table" and #series.chapters or 0
                                local new_count = Follow.checkUpdate(entry, live)
                                Follow.noteChecked(saved_followed, entry.source_id, entry.id, live)
                                if new_count > 0 then
                                    series_count = series_count + 1
                                    total_new_ch = total_new_ch + new_count
                                end
                            end
                        end
                        if Trapper and type(Trapper.wrap) == "function" then
                            Trapper:wrap(run_query)
                        else
                            run_query()
                        end
                    end
                end
                if on_progress then
                    on_progress(step_idx, #batch, entry)
                end
                -- Schedule next entry on next tick
                MorningSync.scheduleTick(deps, function()
                    checkStep(step_idx + 1)
                end)
            else
                -- Follow checking complete: save state, then run digest on next tick
                if Settings and Settings.set and saved_followed then
                    Settings.set("followed_series", saved_followed)
                end

                MorningSync.scheduleTick(deps, function()
                    local digest_path, digest_status
                    local run_digest = function()
                        digest_path, digest_status = MorningSync.syncDigest(deps)
                    end
                    if Trapper and type(Trapper.wrap) == "function" then
                        Trapper:wrap(run_digest)
                    else
                        run_digest()
                    end
                    MorningSync.noteSynced(now, deps)

                    local result = {
                        status = "synced",
                        series_updated = series_count,
                        new_chapters = total_new_ch,
                        digest_path = digest_path,
                        digest_status = digest_status,
                        batch_size = #batch,
                        next_cursor = next_cursor,
                    }
                    if on_done then on_done(result) end
                end)
            end
        end

        -- Defer the very first step via scheduleTick so menu open handler returns immediately
        MorningSync.scheduleTick(deps, function()
            checkStep(1)
        end)
    end)

    if not triggered then
        if on_done then on_done({ status = "offline" }) end
        return false, "offline"
    end

    return true, "running"
end

return MorningSync
