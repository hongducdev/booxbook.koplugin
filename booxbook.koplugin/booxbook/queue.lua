-- Wi-Fi URL queue: POST /queue appends to received/queue.txt, this module
-- reads it back so the user can download or discard each entry by hand.
-- No background fetching (e-ink battery); every action is explicit.
local Opds = require("booxbook.opds")

local Queue = {}

function Queue.path(dir)
    if type(dir) ~= "string" or dir == "" then return nil end
    return dir:gsub("[/\\]$", "") .. "/queue.txt"
end

function Queue.read(path)
    local out, seen = {}, {}
    if type(path) ~= "string" then return out end
    local file = io.open(path, "rb")
    if not file then return out end
    local body = file:read("*a") or ""
    file:close()
    for line in (body .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        local ok, url = pcall(Opds.normalizeQueueUrl, line)
        if ok and url and not seen[url] then
            seen[url] = true
            out[#out + 1] = url
        end
    end
    return out
end

function Queue.append(path, url)
    local ok, clean = pcall(Opds.normalizeQueueUrl, url)
    if not ok or not clean then return nil, "url" end
    for _, existing in ipairs(Queue.read(path)) do
        if existing == clean then return false, "duplicate" end
    end
    local file = io.open(path, "ab")
    if not file then return nil, "write" end
    file:write(clean .. "\n")
    file:close()
    return true
end

function Queue.remove(path, url)
    local kept, found = {}, false
    for _, existing in ipairs(Queue.read(path)) do
        if existing == url then
            found = true
        else
            kept[#kept + 1] = existing
        end
    end
    if not found then return false end
    if #kept == 0 then
        os.remove(path)
        return true
    end
    local file = io.open(path, "wb")
    if not file then return false end
    for _, entry in ipairs(kept) do file:write(entry .. "\n") end
    file:close()
    return true
end

function Queue.clear(path)
    os.remove(path)
    return true
end

return Queue
