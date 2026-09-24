-- Regression: the update check and every notification used to hold the UI thread
-- and leave modal boxes behind.
--
-- On device (Boox/Android) opening the BooxBook menu ran the GitHub lookup
-- synchronously: three transport attempts with a 10s stall / 20s ceiling each,
-- stamped "checked" only on success, so a blocked network repeated the whole
-- thing on every menu open. Every message created on that path (and every
-- Fault.notify) had no timeout either, and KOReader's InfoMessage defaults to
-- `timeout = nil` = "stay until tapped" while being modal.
local plugin_root = "booxbook.koplugin"

local names = {
    "socket.http",
    "gettext",
    "dispatcher",
    "ui/uimanager",
    "ui/widget/infomessage",
    "ui/widget/container/widgetcontainer",
    "booxbook.ui.catalog",
    "booxbook.store.settings",
    "booxbook.network",
    "booxbook.http",
    "booxbook.update",
    "booxbook.fault",
}
local saved = {}
for _, name in ipairs(names) do saved[name] = package.loaded[name] end

-- A transport that never answers, and records who is asking.
-- http.lua captures the socket.http table at load, so tests below mutate this
-- table instead of replacing it in package.loaded.
local transport = { attempts = 0, threads = {}, budgets = {} }
local transport_stub = {
    request = function(request)
        transport.attempts = transport.attempts + 1
        transport.threads[#transport.threads + 1] = coroutine.running() and "coroutine" or "MAIN"
        local Http = package.loaded["booxbook.http"]
        transport.budgets[#transport.budgets + 1] = Http and Http.remaining()
        if transport.body then
            request.sink(transport.body)
            return 1, 200, {}, "OK"
        end
        return nil, "timeout"
    end,
}
package.loaded["socket.http"] = transport_stub

local shown, closed = {}, {}
local function reset()
    shown, closed = {}, {}
    transport.attempts, transport.threads, transport.budgets = 0, {}, {}
    transport.body, transport.install_thread = nil, nil
end

package.loaded.gettext = function(value) return value end
-- Mirrors KOReader: InfoMessage keeps whatever the caller passed, and its own
-- default for `timeout` is nil.
package.loaded["ui/widget/infomessage"] = { new = function(_, value) return value end }
package.loaded["ui/uimanager"] = {
    show = function(_, widget) shown[#shown + 1] = widget end,
    close = function(_, widget) closed[#closed + 1] = widget end,
    -- Runs immediately: Async's scheduler resumes through this.
    nextTick = function(_, fn) fn() end,
    scheduleIn = function() end,
}
package.loaded["dispatcher"] = { registerAction = function() end }
package.loaded["ui/widget/container/widgetcontainer"] = { extend = function(_, value) return value end }
package.loaded["booxbook.ui.catalog"] = {
    show = function() end,
    clearStack = function() end,
    promptText = function() end,
    confirm = function(text) shown[#shown + 1] = { confirm_text = text } end,
}
local memory = {}
package.loaded["booxbook.store.settings"] = {
    get = function(key) return memory[key] end,
    set = function(key, value) memory[key] = value end,
    downloadDir = function() return "." end,
    ensureDir = function() return true end,
}
package.loaded["booxbook.network"] = {
    ifOnline = function(callback) callback(); return true end,
    whenOnline = function(callback) callback() end,
    statusLine = function() return "" end,
}
package.loaded["booxbook.http"] = nil
package.loaded["booxbook.update"] = nil
local Http = require("booxbook.http")
local Update = require("booxbook.update")
local Fault = require("booxbook.fault")
local saved_install = Update.install
assert(type(Http) == "table" and type(Fault) == "table")

local function assert_number(value, message)
    assert(type(value) == "number" and value > 0,
        message .. " (got " .. tostring(value) .. ")")
end

-- 1. A plain failure notification must close itself.
reset()
Fault.notify("Không tải được truyện.")
assert(#shown == 1, "one notification is shown")
assert_number(shown[1].timeout, "Fault.notify must set an InfoMessage timeout")

-- 2. The lookup runs off the UI thread, under a budget, and its messages close.
reset()
Update._checkOnline()
assert(transport.attempts == 3, "a stalled host gets three attempts, got " .. transport.attempts)
for _, thread in ipairs(transport.threads) do
    assert(thread == "coroutine", "the update lookup must not run on the UI thread")
end
assert_number(transport.budgets[1], "the lookup must run under an operation budget")
assert(transport.budgets[1] <= Update.CHECK_TIMEOUT,
    "the whole lookup is capped by CHECK_TIMEOUT, got " .. tostring(transport.budgets[1]))
assert(#shown >= 2, "progress and result are both reported")
for index, widget in ipairs(shown) do
    assert_number(widget.timeout, "update message " .. index .. " must set a timeout")
end

-- 3. The daily check is stamped before the request, so a failure does not repeat.
reset()
memory["update_last_check"] = 0
local BooxBook = dofile(plugin_root .. "/main.lua")
BooxBook:maybeCheckUpdate()
assert(transport.attempts == 3, "the first menu open checks once, got " .. transport.attempts)
assert(transport.threads[1] == "coroutine", "the menu check must not run on the UI thread")
assert((tonumber(memory["update_last_check"]) or 0) > 0,
    "a failed lookup must still count as today's check")
assert(#shown == 1, "a failed check reports exactly once")
assert_number(shown[1].timeout, "the menu check message must set a timeout")
local second = transport.attempts
BooxBook:maybeCheckUpdate()
assert(transport.attempts == second, "the second menu open must not repeat the lookup")
assert(#shown == 1, "the second menu open stays quiet")

-- 4. A successful lookup still reports the new version, off the UI thread.
reset()
memory["update_last_check"] = 0
transport.body = '{"tag_name":"v99.0.0","assets":[{"name":"booxbook.koplugin.zip",'
    .. '"browser_download_url":"https://github.com/hongducdev/booxbook.koplugin/releases/download/x/booxbook.koplugin.zip"}]}'
Update._jsonDecode = function(body)
    return { tag_name = body:match('"tag_name":"([^"]+)"'),
        assets = { { name = "booxbook.koplugin.zip",
            browser_download_url = body:match('"browser_download_url":"([^"]+)"') } } }
end
local real_install = Update.install
BooxBook:maybeCheckUpdate()
assert(real_install == Update.install, "the check never installs anything")
assert(transport.threads[1] == "coroutine", "a successful lookup also runs off the UI thread")
assert(memory["update_available"] == "99.0.0", "the new version is recorded for the home footer")
assert(#shown == 1 and tostring(shown[1].text):find("99.0.0", 1, true),
    "the reader is told which version is available")

-- 5. The install path does not block either, and closes its own progress box.
reset()
Update.install = function()
    transport.install_thread = coroutine.running() and "coroutine" or "MAIN"
    return true
end
Update.installAsync({ version = "99.0.0" })
assert(transport.install_thread == "coroutine", "install must not run on the UI thread")
assert(#shown >= 1, "install reports progress")
assert_number(shown[1].timeout, "the install progress box must set a timeout")
assert(closed[1] == shown[1], "install closes its own progress box when it finishes")

-- 6. A large body hands the UI thread back while it streams. The pre-request step
-- alone is not enough: the 30 MiB update zip used to block for the whole transfer.
reset()
local ticks = 0
package.loaded["ui/uimanager"].nextTick = function(_, fn) ticks = ticks + 1; fn() end
local ticks_at_chunk = {}
transport_stub.request = function(request)
    -- 8 x 64 KiB = 512 KiB, i.e. two 256 KiB yield points.
    for index = 1, 8 do
        ticks_at_chunk[index] = ticks
        request.sink(string.rep("x", 64 * 1024))
    end
    return 1, 200, {}, "OK"
end
local body, fetched
require("booxbook.async").run(function()
    local ok, _, payload = Http.get("https://example.com/big", { delay_ms = 0 })
    fetched, body = ok, payload
end, function() end)
assert(fetched == true, "the large body is fetched")
assert(#body == 8 * 64 * 1024, "the whole body arrives, got " .. tostring(#body))
assert(ticks_at_chunk[#ticks_at_chunk] > ticks_at_chunk[1],
    "a large body must yield the UI thread while streaming")

-- 7. Silent mode: UIManager:show drops the widget there (InfoMessage honors it), so no
-- progress box is created and closing one is never attempted.
reset()
package.loaded["ui/uimanager"].isInSilentMode = function() return true end
local ok_silent, err_silent = pcall(Update.installAsync, { version = "99.0.0" })
assert(ok_silent, "installAsync must survive silent mode: " .. tostring(err_silent))
assert(#closed == 0, "nothing is closed when nothing was shown")
package.loaded["ui/uimanager"].isInSilentMode = nil

Update.install = saved_install
Update._jsonDecode = nil

-- 7b. Pins the premise the fix relies on (not a pre-fix regression check): a budget is
-- a wall, not a suggestion. Once the stalled attempt has eaten it, the next attempt is
-- refused instead of getting another DEFAULT_MAXTIME (20s) — that is what turns the
-- old 3 x 20s hold on the UI thread into CHECK_TIMEOUT (15s).
reset()
local rate = require("booxbook.rate_limit")
rate.reset()
local socket_table = require("socket")
local real_gettime = socket_table.gettime
local clock = 2000000000
socket_table.gettime = function() return clock end
transport_stub.request = function()
    transport.attempts = transport.attempts + 1
    clock = clock + 60            -- the stalled socket burned a whole minute
    return nil, "timeout"
end
local budget_err, budget_code
require("booxbook.async").run(function()
    return Http.withBudget(Update.CHECK_TIMEOUT, Update.fetchLatest)
end, function(_, _, err, extra) budget_err, budget_code = err, extra end)
assert(transport.attempts == 1,
    "the attempt that used up the budget must be the last one, got " .. transport.attempts)
assert(budget_code == "operation-timeout",
    "budget expiry must reach the caller, got " .. tostring(budget_code) .. " (err=" .. tostring(budget_err) .. ")")
socket_table.gettime = real_gettime
rate.reset()

-- 8. Two overlapping resumable actions are serialised the parked one keeps its
-- resume handle. Capturing them and driving the ticks by hand also proves the
-- scheduler does not depend on re-entrant nextTick.
reset()
local queued_ticks = {}
package.loaded["ui/uimanager"].nextTick = function(_, fn) queued_ticks[#queued_ticks + 1] = fn end
local function drain(limit)
    local steps = 0
    while #queued_ticks > 0 and steps < (limit or 200) do
        steps = steps + 1
        local fn = table.remove(queued_ticks, 1)
        fn()
    end
end
local Async = require("booxbook.async")
local order = {}
local function runnable(name)
    return function()
        order[#order + 1] = name .. ":start"
        Async.step()              -- first yield, like a network step would
        order[#order + 1] = name .. ":end"
    end
end
Async.run(runnable("A"), function() order[#order + 1] = "A:done" end)
Async.run(runnable("B"), function() order[#order + 1] = "B:done" end)
assert(Async.waiting() == 1, "the second action queues behind the parked one")
drain()
assert(table.concat(order, ",") == "A:start,A:end,A:done,B:start,B:end,B:done",
    "the queued action runs after the parked one finishes, got: " .. table.concat(order, ","))
assert(Async.waiting() == 0, "the queue drains, waiting=" .. Async.waiting())
package.loaded["ui/uimanager"].nextTick = function(_, fn) fn() end

-- 9. Prevention gate: the modules that build an InfoMessage themselves must pass a
-- timeout (everything else goes through Fault.notify / Update.NOTIFY_TIMEOUT).
-- Scanning the source catches a new call site, which a runtime stub cannot.
-- Brace-matched on purpose: a constructor with a nested table must not end the span
-- at the inner brace (strings in these calls contain no braces).
local function constructor_spans(source, marker)
    local spans, position = {}, 1
    while true do
        local start = source:find(marker, position, true)
        if not start then return spans end
        local open = source:find("{", start, true)
        if not open then return spans end
        local depth, index = 0, open
        while index <= #source do
            local char = source:sub(index, index)
            if char == "{" then
                depth = depth + 1
            elseif char == "}" then
                depth = depth - 1
                if depth == 0 then break end
            end
            index = index + 1
        end
        spans[#spans + 1] = source:sub(open, index)
        position = index + 1
    end
end

for _, module in ipairs({ "booxbook/ui/series", "booxbook/ui/wifi-transfer" }) do
    local path = plugin_root .. "/" .. module .. ".lua"
    local file = assert(io.open(path, "rb"), "missing source " .. path)
    local source = file:read("*a")
    file:close()
    local spans = constructor_spans(source, "InfoMessage:new")
    assert(#spans > 0, module .. " is expected to create InfoMessages")
    for _, span in ipairs(spans) do
        assert(span:find("timeout", 1, true),
            module .. " must set a timeout on every InfoMessage: " .. span:gsub("%s+", " "))
    end
end

for _, name in ipairs(names) do
    package.loaded[name] = saved[name]
end

print("Update menu: off-thread lookup, daily stamp and notification timeouts verified")
