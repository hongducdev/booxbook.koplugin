-- Turn transport and parser failures into a sentence a reader can act on.
--
-- The rule is deliberately narrow: a message is rebuilt only when it carries
-- code internals ("some/file.lua:123:", "stack traceback", "attempt to index…").
-- Anything else is passed through untouched, which keeps every per-source
-- message (and every message a test pins) exactly as it was.
local Fault = {}

-- Bare transport codes that carry no meaning for a reader.
local EXACT = {
    ["timeout"] = "Máy chủ phản hồi quá chậm.",
    ["wantread"] = "Máy chủ phản hồi quá chậm.",
    ["wantwrite"] = "Máy chủ phản hồi quá chậm.",
    ["connection refused"] = "Không kết nối được tới máy chủ.",
    ["connection failed"] = "Không kết nối được tới máy chủ.",
    ["connection reset by peer"] = "Kết nối bị ngắt giữa chừng.",
    ["broken pipe"] = "Kết nối bị ngắt giữa chừng.",
    ["body too large"] = "Trang trả về quá lớn để đọc.",
    ["request failed"] = "Yêu cầu không thành công.",
    ["operation-timeout"] = "Việc tải mất quá nhiều thời gian nên đã dừng lại.",
    -- Bare forms returned (not raised) by a source still get explained.
    ["network failure"] = "Lỗi kết nối mạng.",
    ["network unavailable"] = "Lỗi kết nối mạng.",
    ["download failed"] = "Tải không thành công.",
}

-- Substrings that identify the cause inside a longer technical string.
local CAUSES = {
    { "operation%-timeout", EXACT["operation-timeout"] },
    { "connection refused", EXACT["connection refused"] },
    { "refused", EXACT["connection refused"] },
    { "host not found", "Không tìm thấy địa chỉ máy chủ." },
    { "no address", "Không tìm thấy địa chỉ máy chủ." },
    { "dns", "Không tìm thấy địa chỉ máy chủ." },
    { "handshake", "Lỗi bảo mật kết nối (TLS)." },
    { "certificate", "Lỗi bảo mật kết nối (TLS)." },
    { "ssl", "Lỗi bảo mật kết nối (TLS)." },
    { "tls", "Lỗi bảo mật kết nối (TLS)." },
    { "timed ?out", "Máy chủ phản hồi quá chậm." },
    { "timeout", "Máy chủ phản hồi quá chậm." },
    { "wantread", "Máy chủ phản hồi quá chậm." },
    { "wantwrite", "Máy chủ phản hồi quá chậm." },
    { "reset by peer", EXACT["connection reset by peer"] },
    { "broken pipe", EXACT["broken pipe"] },
    { "body too large", EXACT["body too large"] },
    { "cloudflare", "Trang đang chặn truy cập tự động." },
    { "challenge%-error", "Trang đang chặn truy cập tự động." },
    { "just a moment", "Trang đang chặn truy cập tự động." },
    { "request failed", EXACT["request failed"] },
    { "network failure", "Lỗi kết nối mạng." },
    { "network unavailable", "Lỗi kết nối mạng." },
    { "download failed", "Tải không thành công." },
}

local STATUS = {
    { "403", "Trang chặn truy cập (403)." },
    { "404", "Không tìm thấy trang (404)." },
    { "429", "Trang đang giới hạn truy cập, thử lại sau ít phút (429)." },
    { "5%d%d", "Máy chủ đang lỗi, thử lại sau." },
}

local GENERIC = "Không tải được nội dung. Kiểm tra Wi-Fi rồi thử lại."

-- Lua/parser noise that must never reach the reader.
local function hasMarker(text)
    if text:find("%.lua:%d+") then return true end
    local lower = text:lower()
    for _, marker in ipairs({ "stack traceback", "attempt to ", "bad argument", "nil value" }) do
        if lower:find(marker, 1, true) then return true end
    end
    return false
end

-- Exposed for tests and for callers that want to log the difference.
function Fault.isTechnical(text)
    return hasMarker(tostring(text or ""))
end

function Fault.cause(text)
    local lower = tostring(text or ""):lower()
    for _, entry in ipairs(CAUSES) do
        if lower:find(entry[1]) then return entry[2] end
    end
    for _, entry in ipairs(STATUS) do
        if lower:find(entry[1]) then return entry[2] end
    end
    if EXACT[lower] then return EXACT[lower] end
end

-- "…/booxbook/doh.lua:102: …/booxbook/doh.lua:41: connection refused"
--   -> "connection refused"
function Fault.clean(text)
    local out = tostring(text == nil and "" or text)
    for _ = 1, 4 do
        out = out:gsub("[%w%._%-/\\]*%.lua:%d+:?%s*", "")
        out = out:gsub("%s*HTTP:%s*", " ")
    end
    return out:gsub("%s+", " "):match("^%s*(.-)%s*$")
end

-- A message may already start with a sentence the reader needs ("Không tải được
-- Truyện Full."); keep that part and replace only the technical tail.
local function lead(text)
    local first = text:match("^([^%.]*%.)")
    if not first or #first > 90 then return nil end
    if first:find("[%{%}\\|]") or hasMarker(first) then return nil end
    return first
end

-- `subject` is the thing being loaded ("Truyện Full", "chương 12", "mục lục").
function Fault.message(text, subject)
    local raw = tostring(text == nil and "" or text):match("^%s*(.-)%s*$")
    if not hasMarker(raw) then
        if raw == "" then
            return subject and string.format("Không tải được %s.", subject) or "Đã xảy ra lỗi."
        end
        -- Already readable (per-source wording, our own Vietnamese). Only an
        -- exact transport code is translated: substring patterns must never run
        -- on text a reader is meant to see ("…chỉ lấy được 500 chương đầu."
        -- would otherwise match the 5xx pattern). A bare HTTP status is the one
        -- case that is code-like on its own ("500" from Http.request).
        return EXACT[raw:lower()] or (raw:match("^%d%d%d$") and Fault.cause(raw)) or raw
    end

    local stripped = Fault.clean(raw)
    local cause = Fault.cause(stripped) or GENERIC
    local prefix = lead(stripped)
    if prefix then
        return prefix .. " " .. cause
    end
    if subject then
        return string.format("Không tải được %s. %s", subject, cause)
    end
    return cause
end

-- Single place where a failure becomes something the reader sees. Depends on
-- UIManager/InfoMessage at call time so widget stubs and reloads keep working.
function Fault.notify(text, subject)
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = Fault.message(text, subject) })
end

return Fault
