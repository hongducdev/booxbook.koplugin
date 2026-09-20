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

local running = nil

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
function Async.run(fn, done)
    local UIManager = require("ui/uimanager")
    local co = coroutine.create(fn)
    local previous = running

    local function step(...)
        if coroutine.status(co) == "dead" then return end
        running = co
        local ok, a, b, c = coroutine.resume(co, ...)
        if not ok then
            running = previous
            if done then done(false, a) end
            return
        end
        if coroutine.status(co) == "dead" then
            running = previous
            if done then done(true, a, b, c) end
            return
        end
        -- Yielded at a network step: let the UI thread breathe, then continue.
        UIManager:nextTick(step)
    end

    step()
end

return Async
