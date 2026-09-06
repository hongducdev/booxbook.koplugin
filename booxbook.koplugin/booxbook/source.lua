local Source = {
    adapters = {},
}

function Source.register(adapter)
    assert(adapter and adapter.id, "adapter.id required")
    Source.adapters[adapter.id] = adapter
    return adapter
end

function Source.get(id)
    return Source.adapters[id]
end

function Source.list()
    local list = {}
    for _, adapter in pairs(Source.adapters) do
        list[#list + 1] = adapter
    end
    table.sort(list, function(a, b)
        return tostring(a.name or a.id) < tostring(b.name or b.id)
    end)
    return list
end

function Source.enabledList(settings)
    local list = {}
    for _, adapter in ipairs(Source.list()) do
        if adapter.enabled == nil then
            list[#list + 1] = adapter
        elseif adapter.enabled(settings) then
            list[#list + 1] = adapter
        end
    end
    return list
end

Source.register(require("booxbook.sources.rss"))

Source.register(require("booxbook.sources.docln"))
Source.register(require("booxbook.sources.wattpad"))
Source.register(require("booxbook.sources.sangtacviet"))

return Source
