-- Every failure must reach the reader as a sentence, never as code internals.
local Fault = require("booxbook.fault")

-- The exact string the reader saw on device.
local device = "Không tải được Truyện Tuổi Thơ. HTTP: ...d/0/koreader/plugins/"
    .. "booxbook.koplugin/booxbook/doh.lua:102: ...d/0/koreader/plugins/booxbook.koplugin/"
    .. "booxbook/doh.lua:41: connection refused"
local friendly = assert(Fault.message(device))
assert(not friendly:find("%.lua:"), "no file path survives: " .. friendly)
assert(not friendly:find("doh.lua", 1, true), "no module name survives: " .. friendly)
assert(friendly:find("Truyện Tuổi Thơ", 1, true), "the subject is kept: " .. friendly)
assert(friendly:find("máy chủ", 1, true), "the cause is explained: " .. friendly)

-- Messages that are already readable are never rewritten: per-source wording and
-- bare codes we know how to explain.
for _, text in ipairs({ "API changed", "write failed", "Chưa có chương đã tải.",
    "Không tìm thấy truyện phù hợp.", "Hết danh sách." }) do
    assert(Fault.message(text) == text, "must pass through unchanged: " .. text)
end
assert(Fault.message("timeout") == "Máy chủ phản hồi quá chậm.")
assert(Fault.message("network failure") == "Lỗi kết nối mạng.")
assert(Fault.message("download failed") == "Tải không thành công.")

-- Substring patterns must never touch a sentence the reader is meant to see:
-- "500 chương đầu" used to match the 5xx pattern, and "dns"/"tls" are inside
-- ordinary words.
for _, text in ipairs({
    "Mục lục quá dài, chỉ lấy được 500 chương đầu.",
    "Đã hủy tải; đã giữ 403 ảnh để tải tiếp.",
    "Có 404 chương mới (tổng 500).",
    "Máy chủ đang lỗi, thử lại sau.",
    "Đang tải, vui lòng chờ.",
    "Không tìm thấy nguồn truyện: tlssdns",
}) do
    assert(Fault.message(text) == text, "readable text must survive: " .. text)
end

-- Raised errors (Lua adds file:line) are explained, not printed.
assert(Fault.message("x.lua:1: HTTP 429") == "Trang đang giới hạn truy cập, thử lại sau ít phút (429).")
assert(Fault.message("x.lua:7: HTTP 500") == "Máy chủ đang lỗi, thử lại sau.")
assert(Fault.message("tests/x.lua:9: bad argument #1 to 'match'"):find("Wi%-Fi"))

-- A subject is used when the message alone says nothing.
assert(Fault.message(nil, "mục lục") == "Không tải được mục lục.")
assert(Fault.message("", "mục lục") == "Không tải được mục lục.")
assert(Fault.message(nil) == "Đã xảy ra lỗi.")

-- Anything technical is normalised, and normalising twice changes nothing.
local cases = {
    device,
    "tests/x.lua:12: attempt to call field 'get' (a nil value)",
    "stack traceback: some/file.lua:3: boom",
    "HTTP: a/b/doh.lua:41: connection refused",
    "a/doh.lua:102: a/doh.lua:41: TLS handshake failed",
    "x.lua:1: HTTP 429",
    "x.lua:1: HTTP 503",
    "x.lua:5: cannot write",
}
for _, raw in ipairs(cases) do
    local message = assert(Fault.message(raw))
    assert(message == Fault.message(message), "idempotent for: " .. raw)
    assert(not message:find("%.lua"), "no .lua reference for: " .. raw)
    assert(not message:find("traceback", 1, true), "no traceback for: " .. raw)
    assert(#message <= 200, "short enough to read: " .. raw)
end

-- clean() is what the transport uses so logs and callers never see a position.
assert(Fault.clean("a/b/doh.lua:41: connection refused") == "connection refused")
assert(Fault.clean("HTTP:  a/b/x.lua:9:  body too large ") == "body too large")
assert(Fault.clean("plain text") == "plain text")

assert(Fault.isTechnical(device))
assert(not Fault.isTechnical("Chưa có chương đã tải."))

print("Fault message mapping checks passed")
