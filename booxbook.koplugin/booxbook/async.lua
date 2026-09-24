-- Resumable work for the network paths that used to block the UI thread.
--
-- Android declares KOReader unresponsive when the main thread does not answer
-- input for ~5 seconds, and a table of contents is dozens of requests. Here the
-- work runs in a coroutine and the transport hands the main thread back between
-- requests, so KOReader keeps repainting and answering taps while it loads.
--
-- Only code running through Async.run yields: every other caller (background
-- sync, tests, cloud helpers) keeps today's plain synchronous behaviour.
local Async = {}

-- One resumable action at a time, and the parked one is never abandoned: a second
-- caller waits in `waiting` for the current coroutine to die. `Async.step` matches
-- the running coroutine by identity, so overwriting `running` would strand the
-- parked action without anything left to resume it.
local running = nil
local waiting = {}

local start

local function startNext()
    local queued = table.remove(waiting, 1)
    if not queued then return end
    local UIManager = require("ui/uimanager")
    -- `start`, not `Async.run`: taking the queue head must not queue it again.
    UIManager:nextTick(function() start(queued.fn, queued.done) end)
end

-- Called by the transport before each blocking step.
-- Yielding is not possible on every stack: LuaSocket's http.request calls our DoH
-- connector from inside a C function, and LuaJIT then raises "attempt to yield
-- across C-call boundary". Failing to yield is not fatal — that request simply
-- blocks a little longer — so the attempt is contained here instead of breaking
-- the whole fetch.
function Async.step()
    if running and coroutine.running() == running then
        pcall(coroutine.yield)
    end
end

function Async.active()
    return running ~= nil
end

-- Run `fn` in a coroutine, resuming it from the UI event loop whenever it yields
-- a step. `done(ok, ...)` receives the coroutine's return values, or (false, err)
-- when it raised. Yield across pcall is a LuaJIT feature, so a caller may wrap
-- network calls in pcall/Http.withBudget as usual.
-- Internal entry point: callers go through `Async.run`, which serialises them.
start = function(fn, done)
    local UIManager = require("ui/uimanager")
    local co = coroutine.create(fn)
    running = co

    local function step(...)
        if coroutine.status(co) == "dead" then return end
        running = co
        local ok, a, b, c = coroutine.resume(co, ...)
        if not ok then
            running = nil
            if done then done(false, a) end
            startNext()
            return
        end
        if coroutine.status(co) == "dead" then
            running = nil
            if done then done(true, a, b, c) end
            startNext()
            return
        end
        -- Yielded at a network step: let the UI thread breathe, then continue.
        UIManager:nextTick(step)
    end

    step()
end

function Async.run(fn, done)
    -- The queue is the gate as well as the running coroutine: a caller arriving in
    -- the tick between one action dying and the queued one starting must not jump
    -- ahead of it.
    if running or #waiting > 0 then
        waiting[#waiting + 1] = { fn = fn, done = done }
        return
    end
    start(fn, done)
end

-- Number of actions queued behind the running one (tests and diagnostics).
function Async.waiting()
    return #waiting
end

return Async
