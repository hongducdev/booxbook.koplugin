-- Followed novel/comic series: manual "check for new chapters".
-- No background polling (e-ink battery). Caller passes live chapter count.
local Follow = {}

function Follow.key(source_id, id)
    if type(source_id) ~= "string" or type(id) ~= "string" then return nil end
    if source_id == "" or id == "" or #id > 128 then return nil end
    if source_id:match("[^%w%-]") then return nil end
    return source_id .. "/" .. id
end

function Follow.list(saved)
    if type(saved) ~= "table" then return {} end
    local out = {}
    for _, entry in pairs(saved) do
        if type(entry) == "table" and type(entry.source_id) == "string"
            and type(entry.id) == "string" then
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.title) < tostring(b.title)
    end)
    return out
end

function Follow.isFollowed(saved, source_id, id)
    local key = Follow.key(source_id, id)
    if not key or type(saved) ~= "table" then return false end
    return type(saved[key]) == "table"
end

function Follow.follow(saved, series)
    series = series or {}
    local key = Follow.key(series.source_id, series.id)
    if not key then return nil, "missing series id" end
    saved = type(saved) == "table" and saved or {}
    local count = type(series.chapters) == "table" and #series.chapters or 0
    saved[key] = {
        source_id = series.source_id,
        id = series.id,
        title = series.title or series.id,
        url = series.url or "",
        last_count = count,
        updated_at = os.time(),
    }
    return saved, true
end

function Follow.unfollow(saved, source_id, id)
    local key = Follow.key(source_id, id)
    if not key or type(saved) ~= "table" then return saved, false end
    if saved[key] == nil then return saved, false end
    saved[key] = nil
    return saved, true
end

-- Compare stored chapter count with a freshly fetched live count.
-- Returns new_chapters (>= 0). Never negative: shrunk TOC counts as 0.
function Follow.checkUpdate(entry, live_count)
    live_count = tonumber(live_count) or 0
    local last = tonumber(entry and entry.last_count) or 0
    local diff = live_count - last
    if diff < 0 then diff = 0 end
    return diff
end

function Follow.noteChecked(saved, source_id, id, live_count)
    local key = Follow.key(source_id, id)
    if not key or type(saved) ~= "table" or not saved[key] then return false end
    saved[key].last_count = tonumber(live_count) or saved[key].last_count or 0
    saved[key].updated_at = os.time()
    return true
end

return Follow
