-- Daily update-check helpers (pure + Settings timestamp).
local Check = { CHECK_INTERVAL = 24 * 3600 }

function Check.shouldCheck(last, now)
    last = tonumber(last) or 0
    now = tonumber(now) or os.time()
    if last <= 0 then return true end
    return (now - last) >= Check.CHECK_INTERVAL
end

function Check.lastCheck()
    local ok, Settings = pcall(require, "booxbook.store.settings")
    if not ok or not Settings then return 0 end
    return tonumber(Settings.get("update_last_check")) or 0
end

function Check.noteChecked(now)
    local ok, Settings = pcall(require, "booxbook.store.settings")
    if not ok or not Settings then return end
    Settings.set("update_last_check", tonumber(now) or os.time())
end

return Check
