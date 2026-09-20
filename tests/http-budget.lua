-- Time budgets: a slow or dead host must stop the action with a message instead
-- of freezing KOReader's UI thread (Android ANR) for minutes.
local Http = require("booxbook.http")
local RateLimit = require("booxbook.rate_limit")
local socket = require("socket")
local transport = require("socket.http")

local saved = { request = transport.request, wait = RateLimit.wait, gettime = socket.gettime }
local clock = 1000
-- Deterministic clock: no test sleeps, and the budget can be aged on demand.
socket.gettime = function() return clock end

local attempted, waits = {}, {}
transport.request = function(request)
    attempted[#attempted + 1] = request.url
    return nil, "timeout" -- dead host
end
RateLimit.wait = function(host, delay, max_ms)
    waits[#waits + 1] = { host = host, delay = delay, max_ms = max_ms }
    return true
end

-- Without a budget a request is still bounded by its own timeout.
local ok, err = Http.get("https://dead.test/a")
assert(ok == false and err == "timeout", "a lone request reports the transport error")
assert(#attempted == 3, "retries still happen without a budget: " .. #attempted)

-- Under a budget, retries stop as soon as the budget is gone.
attempted = {}
Http.beginOperation(5)
assert(Http.remaining() and Http.remaining() > 0, "a fresh budget has time left")
Http.get("https://dead.test/b")
clock = clock + 6 -- the network took longer than the budget
assert(Http.expired(), "budget expires with the clock")
local ok2, err2 = Http.get("https://dead.test/c")
assert(ok2 == false and err2 == "operation-timeout", "budget stops the request: " .. tostring(err2))
assert(#attempted == 3, "no request is fired after the budget is gone: " .. #attempted)
Http.endOperation()
assert(Http.remaining() == nil, "a lone operation leaves no deadline behind")

-- Nested budgets may extend the deadline but never shrink it.
Http.beginOperation(5)
local short = Http.remaining()
Http.beginOperation(Http.BULK_TIMEOUT)
assert(Http.remaining() > short, "a nested bulk job keeps the longer budget")
Http.endOperation()
assert(Http.remaining() == short, "the outer budget is restored")
Http.endOperation()
assert(Http.remaining() == nil)

-- runWithBudget replaces a pcall without dropping nil results.
local ok3, a, b = Http.runWithBudget(5, function() return nil, "API changed" end)
assert(ok3 == true and a == nil and b == "API changed", "nil middle results survive")
assert(Http.remaining() == nil, "runWithBudget always clears its budget")
local ok4, reason = Http.runWithBudget(5, function() error("boom") end)
assert(ok4 == false and reason:find("boom", 1, true), "runWithBudget reports failures")

-- withBudget keeps the caller's arity and re-raises for the caller's pcall.
local ok5, value = pcall(Http.withBudget, Http.BULK_TIMEOUT, function() return "chapter" end)
assert(ok5 and value == "chapter", "withBudget passes values through")
local ok6 = pcall(Http.withBudget, Http.BULK_TIMEOUT, function() error("late") end)
assert(ok6 == false, "withBudget re-raises")
assert(Http.remaining() == nil, "withBudget clears its budget even on error")

-- A rate-limit sleep may not outlive the remaining budget: the sleep is capped
-- and the caller is told, so it can abort before firing a request too early.
waits = {}
Http.beginOperation(3)
Http.get("https://dead.test/d")
assert(waits[#waits] and waits[#waits].max_ms == 3000,
    "the sleep cap is in milliseconds: " .. tostring(waits[#waits] and waits[#waits].max_ms))
Http.endOperation()

-- The real waiter refuses to sleep past its cap and reports that back.
RateLimit.wait = saved.wait
RateLimit.reset()
assert(RateLimit.wait("capped.test", 1200) == true, "first contact waits nothing")
assert(RateLimit.wait("capped.test", 1200, 100) == false, "the cap is reported to the caller")
assert(RateLimit.wait("capped.test", 0) == true, "a zero delay never caps")

transport.request = saved.request
socket.gettime = saved.gettime
RateLimit.reset()

print("Request time budget checks passed")
