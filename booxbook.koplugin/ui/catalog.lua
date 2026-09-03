local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = {}

function Catalog.show(opts)
    opts = opts or {}
    local menu
    menu = Menu:new{
        title = opts.title or _("Danh sách"),
        item_table = opts.items or {},
        is_borderless = true,
        is_popout = false,
        close_callback = function()
            UIManager:close(menu)
            if opts.on_close then
                opts.on_close()
            end
        end,
    }
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
