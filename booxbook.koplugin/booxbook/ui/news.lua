local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = require("booxbook.ui.catalog")
local Network = require("booxbook.network")
local Publishers = require("booxbook.sources.feeds")
local Rss = require("booxbook.sources.rss")
local function CoverGrid()
    return require("booxbook.ui.cover-grid")
end

local Settings = require("booxbook.store.settings")
local Opml = require("booxbook.opml")

local News = {}

local function notify(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function customFeeds()
    local feeds = {}
    for index, url in ipairs(Settings.get("custom_rss_feeds") or {}) do
        feeds[#feeds + 1] = {
            id = "custom-" .. index,
            title = url,
            lang = "",
            url = url,
            full_article = false,
        }
    end
    return feeds
end

function News.setLimit()
    Catalog.promptText{
        title = _("Số bài mỗi danh mục"),
        input = tostring(Settings.get("news_limit") or 10),
        on_submit = function(value)
            local limit = tonumber(value)
            if not limit or limit < 1 or limit > 20 or limit % 1 ~= 0 then
                notify(_("Nhập số nguyên từ 1 đến 20."))
                return
            end
            Settings.set("news_limit", limit)
        end,
    }
end

function News.addCustomFeed()
    Catalog.promptText{
        title = _("Thêm RSS tùy chỉnh"),
        hint = "https://example.com/feed.xml",
        on_submit = function(url)
            url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if not url:match("^https?://") then
                notify(_("URL phải bắt đầu bằng http:// hoặc https://"))
                return
            end
            local feeds = Settings.get("custom_rss_feeds") or {}
            feeds[#feeds + 1] = url
            Settings.set("custom_rss_feeds", feeds)
            notify(_("Đã thêm nguồn RSS."))
        end,
    }
end

local function openFile(path)
    local file, err = io.open(path, "rb")
    if not file then return nil, err end
    local data = file:read("*a")
    file:close()
    return data
end

local function writeFile(path, data)
    local file, err = io.open(path, "wb")
    if not file then return false, err end
    local ok, write_err = file:write(data)
    file:close()
    if not ok then return false, write_err end
    return true
end

local function lfsModule()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok then return lfs end
    ok, lfs = pcall(require, "lfs")
    if ok then return lfs end
    return nil
end

local function trimPath(path)
    return tostring(path or ""):gsub("[/\\]+$", "")
end

local function listOpmlFiles()
    local lfs = lfsModule()
    if not lfs then return nil, _("Không đọc được thư mục OPML.") end

    local base = trimPath(Settings.downloadDir())
    local roots = {
        { label = "received", path = base .. "/received" },
        { label = "backup", path = base .. "/backup" },
    }
    local items = {}
    for _, root in ipairs(roots) do
        if lfs.attributes(root.path, "mode") == "directory" then
            for name in lfs.dir(root.path) do
                local lower = name:lower()
                if name ~= "." and name ~= ".." and (lower:match("%.opml$") or lower:match("%.xml$")) then
                    local path = root.path .. "/" .. name
                    if lfs.attributes(path, "mode") == "file" then
                        items[#items + 1] = {
                            text = root.label .. "/" .. name,
                            path = path,
                        }
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b) return a.text:lower() < b.text:lower() end)
    return items
end

local function currentFeedSet()
    local feeds = Settings.get("custom_rss_feeds") or {}
    local seen = {}
    for _, url in ipairs(feeds) do
        if type(url) == "string" then seen[url] = true end
    end
    return feeds, seen
end

local function importOpmlPath(path)
    local data, err = openFile(path)
    if not data then
        notify(_("Không đọc được file OPML: ") .. tostring(err))
        return
    end

    local imported = Opml.parse(data)
    local feeds, seen = currentFeedSet()
    local added = 0
    for _, feed in ipairs(imported) do
        local url = tostring(feed.xmlUrl or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if url:match("^https?://") and not seen[url] then
            seen[url] = true
            feeds[#feeds + 1] = url
            added = added + 1
        end
    end
    if added > 0 then
        Settings.set("custom_rss_feeds", feeds)
    end
    notify(string.format(_("Đã nhập %d nguồn RSS từ OPML."), added))
end

function News.importOpml()
    local files, err = listOpmlFiles()
    if not files then
        notify(err)
        return
    end
    if #files == 0 then
        notify(_("Không tìm thấy file OPML trong received hoặc backup."))
        return
    end

    local items = {}
    for _, file in ipairs(files) do
        local current = file
        items[#items + 1] = {
            text = current.text,
            keep_menu_open = true,
            callback = function()
                UIManager:nextTick(function() importOpmlPath(current.path) end)
            end,
        }
    end
    Catalog.show{ title = _("Nhập file OPML"), items = items }
end

function News.exportOpml()
    local base = trimPath(Settings.downloadDir())
    local backup_dir = base .. "/backup"
    if not Settings.ensureDir(backup_dir) then
        notify(_("Không tạo được thư mục backup."))
        return
    end

    local path = backup_dir .. "/booxbook-feeds.opml"
    local xml = Opml.generate(Settings.get("custom_rss_feeds") or {}, "BooxBook RSS Feeds")
    local ok, err = writeFile(path, xml)
    if not ok then
        notify(_("Không xuất được file OPML: ") .. tostring(err))
        return
    end
    notify(_("Đã xuất file OPML: ") .. path)
end
local function feedSourceId(feed)
    local value = tostring(feed and (feed.id or feed.title or feed.url) or "rss")
    value = value:gsub("[^%w%._%-]+", "-"):gsub("^-+", ""):gsub("-+$", "")
    if value == "" then value = "rss" end
    return "rss-" .. value
end

local function articlePageCount(total)
    local page_size = CoverGrid().PAGE_SIZE
    local count = math.ceil((tonumber(total) or 0) / page_size)
    return math.max(1, count)
end


local function onlineAction(message, action, on_success)
    -- Let the selecting menu finish updating before showing progress or another screen.
    UIManager:nextTick(function()
        Network.whenOnline(function()
            Trapper:wrap(function()
                Trapper:info(message)
                local ok, result, err = pcall(action)
                Trapper:clear()
                if not ok or not result then
                    notify(_("Không tải được tin: ") .. tostring(ok and err or result))
                    return
                end
                UIManager:nextTick(function() on_success(result) end)
            end)
        end)
    end)
end

function News.openArticle(feed, item)
    onlineAction(_("Đang mở bài: ") .. item.title, function()
        return Rss.loadArticle(feed, item)
    end, function(path)
        Catalog.clearStack()
        ReaderUI:showReader(path)
    end)
end

function News.showFeed(feed)
    onlineAction(_("Đang lấy danh sách: ") .. feed.title, function()
        return Rss.list(feed, Settings.get("news_limit") or 10)
    end, function(articles)
        local grid
        local offset = 1
        local page_size = CoverGrid().PAGE_SIZE
        local page_count = articlePageCount(#articles)

        local function payload()
            return {
                title = feed.title,
                items = articles,
                has_more = false,
                site_page = 1,
                page_count = page_count,
                offset = offset,
            }
        end

        local function refresh()
            if grid and not grid._closed then
                grid:setPage(payload())
            end
        end

        local function nextPage()
            if grid and grid._closed then return end
            if offset + page_size <= #articles then
                offset = offset + page_size
                refresh()
                return
            end
            notify(_("Hết danh sách."))
        end

        local function prevPage()
            if grid and grid._closed then return end
            if offset > 1 then
                offset = math.max(1, offset - page_size)
                refresh()
                return
            end
            notify(_("Đang ở trang đầu."))
        end

        local opts = payload()
        opts.source_id = feedSourceId(feed)
        opts.base_url = feed.url
        opts.cover_referer = feed.url
        opts.on_select = function(item) News.openArticle(feed, item) end
        opts.on_next = nextPage
        opts.on_prev = prevPage
        opts.on_close = function() grid = nil end
        grid = CoverGrid().show(opts)
    end)
end

function News.showCategories(publisher)
    local items = {}
    for _, feed in ipairs(publisher.publishers or publisher.categories) do
        local current = feed
        items[#items + 1] = {
            text = current.category or current.title,
            keep_menu_open = true,
            callback = function()
                if current.categories then
                    UIManager:nextTick(function() News.showCategories(current) end)
                else
                    News.showFeed(current)
                end
            end,
        }
    end
    Catalog.show{ title = publisher.title, items = items }
end

function News.showArticles()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        notify(_("Không đọc được thư mục tin."))
        return
    end
    local root = Settings.downloadDir() .. "/news"
    local items = {}
    if lfs.attributes(root, "mode") == "directory" then
        for feed_dir in lfs.dir(root) do
            local dir = root .. "/" .. feed_dir
            if feed_dir ~= "." and feed_dir ~= ".." and lfs.attributes(dir, "mode") == "directory" then
                for name in lfs.dir(dir) do
                    if name:match("%.html$") then
                        local path = dir .. "/" .. name
                        local article_path = path
                        items[#items + 1] = {
                            text = name:gsub("%.html$", ""),
                            keep_menu_open = true,
                            callback = function()
                                UIManager:nextTick(function()
                                    Catalog.clearStack()
                                    ReaderUI:showReader(article_path)
                                end)
                            end,
                        }
                    end
                end
            end
        end
    end
    table.sort(items, function(a, b)
        return a.text > b.text
    end)
    Catalog.show{ title = _("Tin đã tải"), items = items }
end

function News.menu()
    local groups = {
        { title = _("Báo Việt"), publishers = {} },
        { title = _("Báo Nước Ngoài"), publishers = {} },
    }
    for _, publisher in ipairs(Publishers) do
        local group = groups[publisher.region == "vietnam" and 1 or 2].publishers
        group[#group + 1] = publisher
    end
    local custom = customFeeds()
    if #custom > 0 then
        groups[#groups + 1] = { title = _("RSS tùy chỉnh"), categories = custom }
    end
    local items = {}
    for _, publisher in ipairs(groups) do
        local current = publisher
        items[#items + 1] = {
            text = current.title,
            keep_menu_open = true,
            callback = function()
                UIManager:nextTick(function() News.showCategories(current) end)
            end,
        }
    end
    items[#items + 1] = { text = _("Tin đã tải"), keep_menu_open = true, callback = function()
        UIManager:nextTick(News.showArticles)
    end }
    items[#items + 1] = { text = _("Số bài mỗi danh mục"), keep_menu_open = true, callback = News.setLimit }
    items[#items + 1] = { text = _("Thêm RSS tùy chỉnh"), keep_menu_open = true, callback = News.addCustomFeed }
    items[#items + 1] = { text = _("Nhập file OPML"), keep_menu_open = true, callback = News.importOpml }
    items[#items + 1] = { text = _("Xuất file OPML"), keep_menu_open = true, callback = News.exportOpml }
    return items
end

return News
