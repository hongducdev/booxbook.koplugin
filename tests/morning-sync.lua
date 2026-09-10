-- Unit tests for MorningSync (Phase 01)
local plugin_root = "booxbook.koplugin"
package.path = plugin_root .. "/?.lua;" .. plugin_root .. "/?/init.lua;" .. package.path

local MorningSync = require("booxbook.morning-sync")

-- 1. shouldSync timing logic
assert(MorningSync.shouldSync(0, 1000) == true, "0 last sync should sync")
assert(MorningSync.shouldSync(nil, 1000) == true, "nil last sync should sync")
assert(MorningSync.shouldSync(-10, 1000) == true, "negative last sync should sync")

-- Same day, less than 24h:
-- 2026-09-10 08:00:00 vs 2026-09-10 10:00:00
local t_0800 = os.time({ year = 2026, month = 9, day = 10, hour = 8, min = 0, sec = 0 })
local t_1000 = os.time({ year = 2026, month = 9, day = 10, hour = 10, min = 0, sec = 0 })
assert(MorningSync.shouldSync(t_0800, t_1000) == false, "same day under 24h should not sync")

-- Next day, early morning:
local t_next_day = os.time({ year = 2026, month = 9, day = 11, hour = 6, min = 0, sec = 0 })
assert(MorningSync.shouldSync(t_0800, t_next_day) == true, "next calendar day should sync")

-- 2. Rotating cursor / Starvation prevention across >20 entries
local long_list = {}
for i = 1, 45 do
    long_list[i] = { id = "series-" .. i, title = "Truyện " .. i }
end

local batch1, cursor1 = MorningSync.pickBatch(long_list, 1, 20)
assert(#batch1 == 20, "batch 1 has 20 items")
assert(batch1[1].id == "series-1", "batch 1 starts at 1")
assert(batch1[20].id == "series-20", "batch 1 ends at 20")
assert(cursor1 == 21, "cursor 1 advances to 21")

local batch2, cursor2 = MorningSync.pickBatch(long_list, cursor1, 20)
assert(#batch2 == 20, "batch 2 has 20 items")
assert(batch2[1].id == "series-21", "batch 2 starts at 21 (no starvation of 21+)")
assert(batch2[20].id == "series-40", "batch 2 ends at 40")
assert(cursor2 == 41, "cursor 2 advances to 41")

local batch3, cursor3 = MorningSync.pickBatch(long_list, cursor2, 20)
assert(#batch3 == 20, "batch 3 has 20 items with wrap-around")
assert(batch3[1].id == "series-41", "batch 3 starts at 41")
assert(batch3[5].id == "series-45", "batch 3 includes 45")
assert(batch3[6].id == "series-1", "batch 3 wraps around to 1")
assert(cursor3 == 16, "cursor 3 wraps to 16")

-- Verify all 45 items were touched across the 3 runs:
local visited = {}
for _, b in ipairs({ batch1, batch2, batch3 }) do
    for _, item in ipairs(b) do
        visited[item.id] = true
    end
end
for i = 1, 45 do
    assert(visited["series-" .. i] == true, "item " .. i .. " was visited")
end

-- 3. Mock Settings & lastSync/noteSynced
local mock_store = {}
local mock_settings = {
    get = function(k) return mock_store[k] end,
    set = function(k, v) mock_store[k] = v end,
    downloadDir = function() return "/mock_dl" end,
    ensureDir = function() return true end,
}

assert(MorningSync.lastSync({ Settings = mock_settings }) == 0, "initial lastSync is 0")
MorningSync.noteSynced(123456, { Settings = mock_settings })
assert(MorningSync.lastSync({ Settings = mock_settings }) == 123456, "noteSynced updates timestamp")

-- 4. syncDigest
local built_dest, built_files
local mock_digest = {
    filename = function() return "digest-20260910.epub" end,
    pick = function(files, max) return files end,
    build = function(dest, files)
        built_dest = dest
        built_files = files
        return dest
    end,
    MAX_FILES = 20,
}

-- Case: already exists
local dest, status = MorningSync.syncDigest({
    Digest = mock_digest,
    Settings = mock_settings,
    fileExists = function() return true end,
})
assert(status == "already_exists", "skips if digest file already exists")

-- Case: no news
dest, status = MorningSync.syncDigest({
    Digest = mock_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return {} end,
})
assert(status == "no_news", "returns no_news when empty")

-- Case: build new digest
mock_store["digest_cursor_mtime"] = nil
mock_store["digest_cursor_path"] = nil
dest, status = MorningSync.syncDigest({
    Digest = mock_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return { { path = "a.html", title = "Tin 1", mtime = 100 } } end,
})
assert(status == "created", "builds new digest")
assert(built_dest == "/mock_dl/received/digest-20260910.epub", "correct destination path")
assert(#built_files == 1, "passed picked news files")
assert(mock_store["digest_cursor_mtime"] == 100, "digest cursor records mtime")
assert(mock_store["digest_cursor_path"] == "a.html", "digest cursor records path")

-- Case: 25 fresh files (oldest-first consumption without starvation)
mock_store["digest_cursor_mtime"] = nil
mock_store["digest_cursor_path"] = nil
local files_25 = {}
for i = 1, 25 do
    files_25[i] = { path = string.format("article-%02d.html", i), title = "Bài " .. i, mtime = 1000 + i }
end

local digest_calls = 0
local captured_files = {}
local batch_digest = {
    filename = function() return "digest-batch-" .. digest_calls .. ".epub" end,
    pick = function(files, max)
        local out = {}
        for i = 1, math.min(#files, max or 20) do out[i] = files[i] end
        return out
    end,
    build = function(dest, files)
        digest_calls = digest_calls + 1
        captured_files[digest_calls] = files
        return dest
    end,
    MAX_FILES = 20,
}

-- Batch 1: should pick oldest 20 (articles 1 to 20)
local d1, s1 = MorningSync.syncDigest({
    Digest = batch_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return files_25 end,
})
assert(s1 == "created", "first run consumes first 20")
assert(#captured_files[1] == 20, "captured 20 files")
assert(captured_files[1][1].path == "article-01.html", "starts with oldest article-01")
assert(captured_files[1][20].path == "article-20.html", "ends with article-20")
assert(mock_store["digest_cursor_mtime"] == 1020, "cursor mtime at 1020")
assert(mock_store["digest_cursor_path"] == "article-20.html", "cursor path at article-20")

-- Batch 2: next day/run picks the remaining 5 (articles 21 to 25) without dropping any!
local d2, s2 = MorningSync.syncDigest({
    Digest = batch_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return files_25 end,
})
assert(s2 == "created", "second run consumes remaining 5 without dropping")
assert(#captured_files[2] == 5, "captured remaining 5 files")
assert(captured_files[2][1].path == "article-21.html", "resumes with article-21")
assert(captured_files[2][5].path == "article-25.html", "ends with article-25")
assert(mock_store["digest_cursor_mtime"] == 1025, "cursor mtime advances to 1025")

-- Batch 3: no new articles -> reports no_new_articles cleanly
local d3, s3 = MorningSync.syncDigest({
    Digest = batch_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return files_25 end,
})
assert(s3 == "no_new_articles", "third run detects all 25 consumed, does not rebuild")

-- Case: Equal mtimes handled deterministically by path tie-breaker
mock_store["digest_cursor_mtime"] = nil
mock_store["digest_cursor_path"] = nil
local equal_mtime_files = {
    { path = "z_equal.html", title = "Z", mtime = 500 },
    { path = "a_equal.html", title = "A", mtime = 500 },
    { path = "m_equal.html", title = "M", mtime = 500 },
}
local eq_captured
local eq_digest = {
    filename = function() return "digest-eq.epub" end,
    pick = function(files, max)
        local out = {}
        for i = 1, math.min(#files, 2) do out[i] = files[i] end -- pick only 2 of 3
        return out
    end,
    build = function(dest, files)
        eq_captured = files
        return dest
    end,
    MAX_FILES = 2,
}
local deq1, seq1 = MorningSync.syncDigest({
    Digest = eq_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return equal_mtime_files end,
})
assert(seq1 == "created", "first run with equal mtime created")
assert(#eq_captured == 2, "picked 2 of 3")
assert(eq_captured[1].path == "a_equal.html", "a sorted before m")
assert(eq_captured[2].path == "m_equal.html", "m sorted before z")
assert(mock_store["digest_cursor_mtime"] == 500, "cursor mtime 500")
assert(mock_store["digest_cursor_path"] == "m_equal.html", "cursor path at m_equal.html")

local deq2, seq2 = MorningSync.syncDigest({
    Digest = eq_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return equal_mtime_files end,
})
assert(seq2 == "created", "second run with equal mtime created")
assert(#eq_captured == 1, "picked remaining 1")
assert(eq_captured[1].path == "z_equal.html", "z picked without collision or skip")
-- Case: failed digest build must not advance cutoff
mock_store["digest_cursor_mtime"] = nil
local failing_digest = {
    filename = function() return "digest-20260912.epub" end,
    pick = function(files, max) return files end,
    build = function(dest, files)
        return nil, "build_failed"
    end,
    MAX_FILES = 20,
}
dest, status = MorningSync.syncDigest({
    Digest = failing_digest,
    Settings = mock_settings,
    fileExists = function() return false end,
    collectNews = function() return { { path = "failed.html", title = "Failed", mtime = 300 } } end,
})
assert(status == "build_failed", "failed digest reports build error")
assert(mock_store["digest_cursor_mtime"] == nil, "failed digest leaves cursor unchanged")

-- 5. runIfDue with tick-scheduled state machine & UIManager:nextTick
local when_online_called = false
local if_online_called = false
local mock_network = {
    ifOnline = function(cb)
        if_online_called = true
        cb()
        return true
    end,
    whenOnline = function()
        when_online_called = true
    end,
}

local ticks = 0
local mock_uimanager = {
    nextTick = function(self, fn)
        ticks = ticks + 1
        fn() -- run inline in test
    end,
}

local mock_followed = {
    ["source-a/series-1"] = {
        source_id = "source-a",
        id = "series-1",
        title = "Truyện A",
        last_count = 10,
    },
    ["source-a/series-2"] = {
        source_id = "source-a",
        id = "series-2",
        title = "Truyện B",
        last_count = 5,
    },
}
local mock_source = {
    get = function(id)
        if id == "source-a" then
            return {
                getSeries = function(ref)
                    if ref == "series-1" then
                        return { chapters = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } } -- +2
                    elseif ref == "series-2" then
                        return { chapters = { 1, 2, 3, 4, 5, 6 } } -- +1
                    end
                end,
            }
        end
    end,
}

mock_store["auto_morning_sync"] = true
mock_store["morning_sync_last_time"] = 0
mock_store["followed_series"] = mock_followed

local progress_reports = {}
local callback_result = nil
local trapper_wraps = 0
local mock_trapper = {
    wrap = function(self, fn)
        trapper_wraps = trapper_wraps + 1
        fn()
    end,
}

local ok, run_status = MorningSync.runIfDue({
    Settings = mock_settings,
    Network = mock_network,
    Source = mock_source,
    Digest = mock_digest,
    UIManager = mock_uimanager,
    Trapper = mock_trapper,
    Follow = require("booxbook.follow"),
    fileExists = function() return false end,
    collectNews = function() return { { path = "b.html", title = "Tin 2", mtime = 400 } } end,
    now = t_1000,
}, function(cur, total, entry)
    progress_reports[#progress_reports + 1] = { cur = cur, total = total, id = entry.id }
end, function(res)
    callback_result = res
end)

assert(ok == true, "runIfDue triggered")
assert(run_status == "running", "run status running")
assert(if_online_called == true, "Network.ifOnline passive check used")
assert(when_online_called == false, "Network.whenOnline NEVER called for morning sync")
assert(ticks >= 4, "tick scheduled: 1 initial tick + 1 tick per series + 1 for digest")
assert(trapper_wraps >= 3, "Trapper:wrap used for blocking queries & digest")
assert(#progress_reports == 2, "progress reported for both series")
assert(callback_result ~= nil, "callback called")
assert(callback_result.status == "synced", "sync status reported")
assert(callback_result.series_updated == 2, "2 series updated")
assert(callback_result.new_chapters == 3, "total 3 new chapters")
assert(mock_store["morning_sync_last_time"] == t_1000, "timestamp recorded")
assert(mock_followed["source-a/series-1"].last_count == 12, "series-1 last_count updated")
assert(mock_followed["source-a/series-2"].last_count == 6, "series-2 last_count updated")

-- Test offline behavior: ifOnline returns false
local mock_network_offline = {
    ifOnline = function(cb) return false end,
}
mock_store["morning_sync_last_time"] = 0
local off_ok, off_status = MorningSync.runIfDue({
    Settings = mock_settings,
    Network = mock_network_offline,
})
assert(off_ok == false, "runIfDue does not run when offline")
assert(off_status == "offline", "offline status reported without prompt")

print("MorningSync checks passed: non-blocking ticks and starvation-free rotation verified")
