local Html = require("html")

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

local function buildOpf(title, chapters)
    local items = {}
    local spines = {}
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
    <dc:language>vi</dc:language>
    <dc:identifier id="BookId">booxbook-%s</dc:identifier>
    <dc:creator>BooxBook</dc:creator>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    %s
  </manifest>
  <spine toc="ncx">
    %s
  </spine>
</package>
]], Html.escape(title), tostring(os.time()), table.concat(items, "\n    "), table.concat(spines, "\n    "))
end

local function buildNcx(title, chapters)
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
    <meta name="dtb:uid" content="booxbook"/>
  </head>
  <docTitle><text>%s</text></docTitle>
  <navMap>
%s
  </navMap>
</ncx>
]], Html.escape(title), table.concat(points, "\n"))
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

--- chapters = { { title=, html= }, ... }
function Epub.write(path, book)
    book = book or {}
    local title = book.title or "BooxBook"
    local chapters = book.chapters or {}
    if #chapters == 0 then
        return false, "no chapters"
    end

    local tmp = path .. ".tmp"
    local epub, err = openWriter(tmp)
    if not epub then
        return false, err
    end

    local mtime = os.time()
    epub:setZipCompression("store")
    epub:addFileFromMemory("mimetype", "application/epub+zip", mtime)
    epub:setZipCompression("deflate")
    epub:addFileFromMemory("META-INF/container.xml", CONTAINER_XML, mtime)
    epub:addFileFromMemory("OEBPS/content.opf", buildOpf(title, chapters), mtime)
    epub:addFileFromMemory("OEBPS/toc.ncx", buildNcx(title, chapters), mtime)
    for i, chapter in ipairs(chapters) do
        local name = string.format("OEBPS/chapter-%03d.xhtml", i)
        epub:addFileFromMemory(name, chapterXHTML(chapter.title or title, chapter.html), mtime)
    end
    epub:close()

    os.remove(path)
    local renamed, rename_err = os.rename(tmp, path)
    if not renamed then
        return false, rename_err or "rename failed"
    end
    return true
end

return Epub
