local ConfirmBox = require("ui/widget/confirmbox")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Catalog = {}

-- Keep parents on UIManager's stack: CloseWidget frees their rendering resources.
Catalog._stack = {}
local function removeFromStack(widget)
    if Catalog._stack[#Catalog._stack] == widget then
        table.remove(Catalog._stack)
        return
    end
    for i = #Catalog._stack, 1, -1 do
        if Catalog._stack[i] == widget then
            table.remove(Catalog._stack, i)
            return
        end
    end
end

function Catalog.clearStack()
    for i = #Catalog._stack, 1, -1 do
        UIManager:close(Catalog._stack[i])
        Catalog._stack[i] = nil
    end
end

local function pushOnStack(widget)
    -- The fullscreen child covers its parent without destroying it.
    Catalog._stack[#Catalog._stack + 1] = widget
    UIManager:show(widget)
    return widget
end

function Catalog.pop(widget)
    if not widget then return end
    -- Avoid re-entrant close when TitleBar X and UIManager unwind the same widget.
    if widget._booxbook_popping then return end
    widget._booxbook_popping = true
    UIManager:close(widget)
    removeFromStack(widget)
end

-- Register any fullscreen widget (e.g. novel cover grid) on the same parent stack.
function Catalog.push(widget)
    return pushOnStack(widget)
end

function Catalog.show(opts)
    return require("booxbook.ui.item-list").show(opts)
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

function Catalog.confirm(text, on_ok, opts)
    opts = opts or {}
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = opts.ok_text or _("Đồng ý"),
        cancel_text = opts.cancel_text or _("Hủy"),
        ok_callback = on_ok,
    })
end

return Catalog
