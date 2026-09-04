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

function Catalog.show(opts)
    opts = opts or {}
    local menu
    menu = CatalogMenu:new{
        title = opts.title or _("Danh sách"),
        item_table = opts.items or {},
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        close_callback = function()
            UIManager:close(menu)
            -- pop this menu off stack
            if Catalog._stack[#Catalog._stack] == menu then
                table.remove(Catalog._stack)
            end
            -- restore previous menu if any
            local prev = Catalog._stack[#Catalog._stack]
            if prev then
                UIManager:show(prev)
            end
            if opts.on_close then
                opts.on_close()
            end
        end,
    }
    -- hide current top menu (don't destroy it, keep on stack)
    local prev = Catalog._stack[#Catalog._stack]
    if prev then
        UIManager:close(prev)
    end
    Catalog._stack[#Catalog._stack + 1] = menu
    UIManager:show(menu)
    return menu
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
