local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = {}
local CatalogMenu = Menu:extend{}

function CatalogMenu:onMenuSelect(item)
    if item.sub_item_table == nil and item.keep_menu_open then
        if item.select_enabled == false then
            return true
        end
        if item.select_enabled_func and not item.select_enabled_func() then
            return true
        end
        self:onMenuChoice(item)
        -- Navigation may close/hide this widget. Do not rebuild it after the callback.
        return true
    end
    return Menu.onMenuSelect(self, item)
end


-- Stack of open full-screen menus; back closes top and restores previous
Catalog._stack = {}

function Catalog.clearStack()
    for i = #Catalog._stack, 1, -1 do
        UIManager:close(Catalog._stack[i])
        Catalog._stack[i] = nil
    end
end

local function pushOnStack(widget)
    local prev = Catalog._stack[#Catalog._stack]
    if prev then
        UIManager:close(prev)
    end
    Catalog._stack[#Catalog._stack + 1] = widget
    UIManager:show(widget)
    return widget
end

function Catalog.pop(widget)
    if not widget then return end
    -- Avoid re-entrant close/show when TitleBar X and UIManager both unwind the same widget.
    if widget._booxbook_popping then return end
    widget._booxbook_popping = true
    UIManager:close(widget)
    if Catalog._stack[#Catalog._stack] == widget then
        table.remove(Catalog._stack)
    else
        for i = #Catalog._stack, 1, -1 do
            if Catalog._stack[i] == widget then
                table.remove(Catalog._stack, i)
                break
            end
        end
    end
    local prev = Catalog._stack[#Catalog._stack]
    if prev then
        UIManager:show(prev)
    end
end

-- Register any fullscreen widget (e.g. novel cover grid) on the same parent stack.
function Catalog.push(widget)
    return pushOnStack(widget)
end

function Catalog.show(opts)
    opts = opts or {}
    local menu
    menu = CatalogMenu:new{
        title = opts.title or _("Danh sách"),
        subtitle = opts.subtitle,
        item_table = opts.items or {},
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        close_callback = function()
            Catalog.pop(menu)
            if opts.on_close then
                opts.on_close()
            end
        end,
    }
    return pushOnStack(menu)
end

function Catalog.promptText(opts)
    opts = opts or {}
    local dialog
    dialog = InputDialog:new{
        title = opts.title or _("Nhập"),
        input = opts.input or "",
        input_hint = opts.hint,
        buttons = {
            {
                {
                    text = _("Hủy"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = opts.ok_text or _("OK"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText()
                        UIManager:close(dialog)
                        if opts.on_submit then
                            opts.on_submit(text)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return dialog
end

function Catalog.confirm(text, on_ok)
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Đồng ý"),
        cancel_text = _("Hủy"),
        ok_callback = on_ok,
    })
end

return Catalog
