local Catalog = require("booxbook.ui.catalog")
local Novels = require("booxbook.ui.novels")
local TVTruyen = require("booxbook.sources.tvtruyen")
local Network = require("booxbook.network")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local _ = require("gettext")
local UI = {}
local busy = false

local function showSeries(ref) Novels.showSeries(ref, TVTruyen) end

function UI.promptSearch()
    Catalog.promptText{ title = _("Tìm truyện hoặc nhập URL TVTruyen"),
        hint = _("Từ khóa hoặc https://www.tvtruyen.live/ten-truyen.html"),
        on_submit = function(text)
            text = (text or ""):match("^%s*(.-)%s*$")
            if text == "" then return end
            if text:match("^https?://") or text:match("^/[%w%-]+%.html$") then
                showSeries(text)
            else
                UI.list(nil, text)
            end
        end }
end

function UI.list(kind, query, page, grid, last_screen)
    page = page or 1
    Network.whenOnline(function()
        if busy then return end
        busy = true
        Trapper:wrap(function()
            local ok, result, err = pcall(function()
                Trapper:info(_("Đang tải TVTruyen…"))
                if query then return TVTruyen.search(query, page) end
                return TVTruyen.browse(kind, page)
            end)
            busy = false
            Trapper:clear()
            if not ok or not result then
                UIManager:show(InfoMessage:new{ text = ok and err or _("Không đọc được TVTruyen. Thử nhập URL truyện.") })
                return
            end
            UIManager:nextTick(function()
                if grid and grid._closed then return end
                local CoverGrid = require("booxbook.ui.cover-grid")
                local items, size = result.items or {}, CoverGrid.PAGE_SIZE
                local offset = last_screen and math.floor(math.max(0, #items - 1) / size) * size + 1 or 1
                local payload = { title = query and ("TVTruyen — " .. query) or "TVTruyen",
                    items = items, offset = offset, site_page = page, has_more = result.has_more,
                    source_id = "tvtruyen", base_url = "https://www.tvtruyen.live",
                    cover_referer = "https://www.tvtruyen.live/", cover_delay_ms = 1600,
                    on_search = UI.promptSearch, on_select = showSeries }
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
                    UIManager:show(InfoMessage:new{ text = _("Không có truyện phù hợp ở trang này.") })
                end
            end)
        end)
    end)
end

function UI.openSource()
    Catalog.show{ title = "TVTruyen", on_search = UI.promptSearch, items = {
        { text = _("Mới đăng"), callback = function() UI.list("latest") end },
        { text = _("Lượt xem"), callback = function() UI.list("popular") end },
    } }
end

return UI
