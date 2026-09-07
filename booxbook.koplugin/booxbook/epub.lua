local Html = require("booxbook.html")
local Metadata = require("booxbook.epub-metadata")

local Epub = {}

local CONTAINER_XML = [[<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
]]

local function chapterXHTML(title, body)
    return Html.wrapDocument(title, Html.sanitize(body or ""))
end

local function buildOpf(title, chapters, uid, book, cover)
    local items = {}
    local spines = {}
    if cover then
        items[#items + 1] = '<item id="cover-image" href="' .. cover.name .. '" media-type="' .. cover.mime .. '"/>'
        items[#items + 1] = '<item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/>'
        spines[#spines + 1] = '<itemref idref="cover-page" linear="no"/>'
    end
    for i = 1, #chapters do
        local id = string.format("chap-%03d", i)
        local href = string.format("chapter-%03d.xhtml", i)
        items[#items + 1] = string.format(
            '<item id="%s" href="%s" media-type="application/xhtml+xml"/>',
            id, href)
        spines[#spines + 1] = string.format('<itemref idref="%s"/>', id)
    end
    return string.format([[<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>%s</dc:title>
    <dc:language>%s</dc:language>
    <dc:identifier id="BookId">%s</dc:identifier>
    %s
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    %s
  </manifest>
  <spine toc="ncx">
    %s
  </spine>
  %s
</package>
]], Html.escape(title), Html.escape(book.language or "vi"), Html.escape(uid), Metadata.xml(book),
        table.concat(items, "\n    "), table.concat(spines, "\n    "),
        cover and '<guide><reference type="cover" title="Cover" href="cover.xhtml"/></guide>' or "")
end

local function buildNcx(title, chapters, uid)
    local points = {}
    for i = 1, #chapters do
        points[#points + 1] = string.format([[
    <navPoint id="nav-%03d" playOrder="%d">
      <navLabel><text>%s</text></navLabel>
      <content src="chapter-%03d.xhtml"/>
    </navPoint>]], i, i, Html.escape(chapters[i].title or ("Chương " .. i)), i)
    end
    return string.format([[<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="%s"/>
  </head>
  <docTitle><text>%s</text></docTitle>
  <navMap>
%s
  </navMap>
</ncx>
]], Html.escape(uid), Html.escape(title), table.concat(points, "\n"))
end

local function openWriter(path)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok or not Archiver or not Archiver.Writer then
        return nil, "no archiver"
    end
    local epub = Archiver.Writer:new{}
    if not epub:open(path, "epub") then
        return nil, epub.err or "open failed"
    end
    return epub
end

-- Writer:close() always returns nil and clears err; reopen to catch a truncated zip.
local function verifyArchive(path, expected)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not ok or not Archiver or not Archiver.Reader then
        return false, "no archive reader"
    end
    local reader = Archiver.Reader:new{}
    if not reader:open(path) then
        return false, reader.err or "archive verify open failed"
    end
    local count = 0
    local walked, walk_err = pcall(function()
        for _ in reader:iterate() do
            count = count + 1
        end
    end)
    pcall(function() reader:close() end)
    if not walked then
        return false, walk_err or "archive verify failed"
    end
    if count < expected then
        return false, "archive incomplete"
    end
    return true
end

--- chapters = { { title=, html= or path= }, ... }; paths contain downloaded HTML.
function Epub.write(path, book)
    book = book or {}
    local title = book.title or "BooxBook"
    local chapters = book.chapters or {}
    if #chapters == 0 then
        return false, "no chapters"
    end

    local cover, cover_err
    if book.cover_path then
        cover, cover_err = Metadata.cover(book.cover_path)
        if not cover then return false, cover_err end
    end
    -- Metadata must describe only resources actually embedded in this archive.
    local metadata = {}
    for key, value in pairs(book) do metadata[key] = value end
    metadata.cover_data = cover ~= nil

    local tmp = path .. ".tmp"
    local opened, epub, err = pcall(openWriter, tmp)
    if not opened or not epub then
        os.remove(tmp)
        return false, opened and err or epub
    end

    local mtime, uid = os.time(), book.identifier or ("booxbook-" .. title)
    local ok, write_err = pcall(function()
        local function check(success)
            if not success then error(epub.err or "archive write failed", 0) end
        end
        local function add(name, content)
            check(epub:addFileFromMemory(name, content, mtime))
        end
        check(epub:setZipCompression("store"))
        add("mimetype", "application/epub+zip")
        check(epub:setZipCompression("deflate"))
        add("META-INF/container.xml", CONTAINER_XML)
        add("OEBPS/content.opf", buildOpf(title, chapters, uid, metadata, cover))
        add("OEBPS/toc.ncx", buildNcx(title, chapters, uid))
        if cover then
            add("OEBPS/" .. cover.name, cover.data)
            add("OEBPS/cover.xhtml", Html.wrapDocument(title,
                '<div><img src="' .. cover.name .. '" alt="' .. Html.escape(title) .. '"/></div>'))
        end
        for i, chapter in ipairs(chapters) do
            local body = chapter.html
            if chapter.path then
                local file, read_err = io.open(chapter.path, "rb")
                if not file then error(read_err, 0) end
                local document, document_err = file:read("*a")
                file:close()
                if not document then error(document_err or "chapter read failed", 0) end
                body = document:match("<body[^>]*>(.-)</body>")
                if not body then error("chapter body missing", 0) end
            end
            add(string.format("OEBPS/chapter-%03d.xhtml", i), chapterXHTML(chapter.title or title, body))
        end
    end)
    -- KOReader's close returns nil on success; preserve any exposed error/exception.
    local closed, close_result = pcall(epub.close, epub)
    if not ok or not closed or close_result == false or epub.err then
        os.remove(tmp)
        return false, not ok and write_err or epub.err or close_result or "archive close failed"
    end

    local verified, verify_err = verifyArchive(tmp, 4 + #chapters + (cover and 2 or 0))
    if not verified then
        os.remove(tmp)
        return false, verify_err
    end

    local renamed, rename_err = os.rename(tmp, path)
    if not renamed then
        -- POSIX rename replaces; FAT/exFAT often fails with EEXIST.
        local leftover = io.open(tmp, "rb")
        if leftover then
            leftover:close()
            os.remove(path)
            renamed, rename_err = os.rename(tmp, path)
        end
    end
    if not renamed then
        os.remove(tmp)
        return false, rename_err or "rename failed"
    end
    return true
end

return Epub
