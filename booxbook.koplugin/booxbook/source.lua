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

-- Adapters of one kind ("novel", "comic", "news"), in menu order.
function Source.ofKind(kind)
    local list = {}
    for _, adapter in ipairs(Source.list()) do
        if adapter.kind == kind then
            list[#list + 1] = adapter
        end
    end
    return list
end

-- First adapter of `kind` whose parseRef() accepts the reference.
function Source.findRef(kind, ref)
    for _, adapter in ipairs(kind and Source.ofKind(kind) or Source.list()) do
        if type(adapter.parseRef) == "function" and adapter.parseRef(ref) then
            return adapter
        end
    end
end

-- Series identity for the on-disk layout: (id, path). `path` is nil when the
-- reference points at a chapter rather than at the series itself.
function Source.locate(adapter, series)
    if type(adapter) ~= "table" or type(adapter.locate) ~= "function" then
        return nil, nil
    end
    return adapter.locate(series)
end

Source.register(require("booxbook.sources.rss"))

Source.register(require("booxbook.sources.docln"))
Source.register(require("booxbook.sources.wattpad"))
Source.register(require("booxbook.sources.metruyencv"))
Source.register(require("booxbook.sources.tvtruyen"))
Source.register(require("booxbook.sources.truyenfull"))
Source.register(require("booxbook.sources.truyentuoitho"))
Source.register(require("booxbook.sources.truyenqq"))
Source.register(require("booxbook.sources.sangtacviet"))

return Source
