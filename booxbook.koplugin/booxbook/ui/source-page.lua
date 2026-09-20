-- One catalogue + cover-grid page for every novel adapter.
--
-- The adapter itself describes how it should be presented (`adapter.view`):
-- browse entries, cover referer, search hint, and how to tell a series
-- reference from a keyword. Adding a novel source therefore means touching the
-- adapter and `booxbook/source.lua` — no new UI file.
--
-- Dependencies are resolved inside create() so a page always binds the module
-- instances that are loaded at the time it is built (the test harness reloads
-- KOReader widgets per fixture).
local Page = {}

-- adapter.id -> a request is in flight; one list fetch per source at a time.
local busy = {}

-- view.base_url may be a function for sources whose domain can change at runtime.
local function resolve(value)
    if type(value) == "function" then return value() end
    return value
end

function Page.create(adapter)
    assert(type(adapter) == "table" and adapter.id, "adapter with id required")
    local Catalog = require("booxbook.ui.catalog")
    local Novels = require("booxbook.ui.novels")
    local Network = require("booxbook.network")
    local Trapper = require("ui/trapper")
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    local _ = require("gettext")

    local view = adapter.view or {}
    local source_id = adapter.id
    local name = adapter.name or adapter.id
    local UI = { adapter = adapter, view = view }

    -- Every failure reaches the reader as a sentence, never as a file:line.
    local function notify(text, subject)
        return require("booxbook.fault").notify(text, subject)
    end

    -- "Name", "Name — query", "Name — <genre>", and for sources that opt in
    -- (view.title_with_kind) "Name — <browse entry>".
    local function pageTitle(kind, query)
        if query then return name .. " — " .. query end
        -- Only sources that publish a genre list can be titled by genre.
        if type(adapter.genres) == "table" and #adapter.genres > 0 then
            local genre = Catalog.genreName(adapter, kind)
            if genre then return name .. " — " .. genre end
        end
        if view.title_with_kind then
            for _index, entry in ipairs(view.browse or {}) do
                if entry.kind == kind then return name .. " — " .. _(entry.text) end
            end
        end
        return name
    end

    function UI.showSeries(ref)
        Novels.showSeries(ref, adapter)
    end

    function UI.promptSearch()
        Catalog.promptText{
            title = string.format(_("Tìm truyện hoặc nhập URL %s"), name),
            hint = view.search_hint and _(view.search_hint),
            on_submit = function(text)
                text = (text or ""):match("^%s*(.-)%s*$")
                if text == "" then return end
                if view.is_ref and view.is_ref(text) then
                    UI.showSeries(text)
                else
                    UI.list(nil, text)
                end
            end,
        }
    end

    function UI.list(kind, query, page, grid, last_screen)
        page = page or 1
        Network.whenOnline(function()
            if busy[source_id] then
                notify(_("Đang tải, vui lòng chờ."))
                return
            end
            busy[source_id] = true
            Trapper:wrap(function()
                local ok, result, err = require("booxbook.http").runWithBudget(nil, function()
                    Trapper:info(string.format(_("Đang tải %s…"), name))
                    if query then return adapter.search(query, page) end
                    return adapter.browse(kind, page)
                end)
                busy[source_id] = false
                Trapper:clear()
                if not ok or not result then
                    notify(ok and err or string.format(_("Không đọc được %s. %s"), name,
                        view.error_hint or _("Thử nhập URL truyện.")))
                    return
                end
                UIManager:nextTick(function()
                    if grid and grid._closed then return end
                    local CoverGrid = require("booxbook.ui.cover-grid")
                    local items, size = result.items or {}, CoverGrid.PAGE_SIZE
                    local offset = last_screen and math.floor(math.max(0, #items - 1) / size) * size + 1 or 1
                    local base = resolve(view.base_url)
                    local payload = { title = pageTitle(kind, query),
                        items = items, offset = offset, site_page = page, has_more = result.has_more,
                        source_id = source_id, base_url = base,
                        cover_referer = view.cover_referer or (base .. "/"),
                        cover_delay_ms = view.cover_delay_ms,
                        on_search = UI.promptSearch, on_select = UI.showSeries }
                    if grid then grid:setPage(payload) else grid = CoverGrid.show(payload) end
                    local function turn(direction)
                        if grid._closed then return end
                        local next_offset = offset + direction * size
                        if next_offset >= 1 and next_offset <= #items then
                            offset = next_offset
                            grid:setPage{ offset = offset }
                        elseif direction > 0 and result.has_more then
                            UI.list(kind, query, page + 1, grid)
                        elseif direction < 0 and page > 1 then
                            UI.list(kind, query, page - 1, grid, true)
                        end
                    end
                    grid.on_next = function() turn(1) end
                    grid.on_prev = function() turn(-1) end
                    if #items == 0 then
                        notify(_("Không có truyện phù hợp ở trang này."))
                    end
                end)
            end)
        end)
    end

    function UI.openSource()
        -- Reopening the source menu is the escape hatch when a fetch got stuck.
        busy[source_id] = false
        local items = {}
        for _index, entry in ipairs(view.browse or {}) do
            local kind = entry.kind
            items[#items + 1] = { text = _(entry.text), callback = function() UI.list(kind) end }
        end
        local genres = {}
        if type(adapter.genres) == "table" and #adapter.genres > 0 then
            genres = Catalog.genreItems(adapter, function(key) UI.list(key) end)
        end
        if #genres > 0 then
            items[#items + 1] = { text = _("Thể loại"), sub_item_table = genres }
        end
        Catalog.show{ title = name, on_search = UI.promptSearch, items = items }
    end

    return UI
end

return Page
