-- Backup/restore settings + followed list as one JSON file in received/.
-- Only explicit user action reads/writes. No cloud upload here.
local Backup = { KEYS = { "novel_epub", "novel_keep_html", "news_delete_finished",
    "adult_content", "include_images", "news_limit", "followed_series" } }

function Backup.export(getFn)
    if type(getFn) ~= "function" then return nil, "no settings" end
    local ok_json, Json = pcall(require, "json")
    if not ok_json or not Json.encode then return nil, "no json" end
    local data = { app = "booxbook", version = 1, settings = {} }
    for _, key in ipairs(Backup.KEYS) do
        local ok, value = pcall(getFn, key)
        if ok then data.settings[key] = value end
    end
    local ok, encoded = pcall(Json.encode, data)
    if not ok or type(encoded) ~= "string" then return nil, "encode failed" end
    return encoded
end

function Backup.parse(body)
    local ok_json, Json = pcall(require, "json")
    if not ok_json or not Json.decode then return nil, "no json" end
    local ok, data = pcall(Json.decode, body or "")
    if not ok or type(data) ~= "table" or data.app ~= "booxbook"
        or type(data.settings) ~= "table" then
        return nil, "invalid backup"
    end
    local out = {}
    for _, key in ipairs(Backup.KEYS) do
        if data.settings[key] ~= nil then out[key] = data.settings[key] end
    end
    return out
end

function Backup.filename()
    return "booxbook-backup-" .. os.date("%Y%m%d-%H%M%S") .. ".json"
end

return Backup
