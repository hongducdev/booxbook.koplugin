local _ = require("gettext")
local Cbz = {}

function Cbz.verify(path, pages, progress)
    local Archiver = require("ffi/archiver")
    local reader = Archiver.Reader:new{}
    local ok, err = pcall(function()
        -- libarchive can read local entries even if close never wrote the ZIP directory.
        -- Our writer adds no ZIP comment, so the end record must occupy the final 22 bytes.
        local file = assert(io.open(path, "rb"))
        local offset = file:seek("end", -22)
        local footer = offset and file:read(22)
        file:close()
        assert(footer and footer:sub(1, 4) == "PK\5\6" and footer:sub(21) == "\0\0", "ZIP end record missing")
        assert(reader:open(path), reader.err or "archive open failed")
        local count, total = 0, 0
        for entry in reader:iterate() do
            count = count + 1
            assert(count <= 600, "too many pages")
            if progress and progress(count, #pages, true) == false then error(_("Đã dừng kiểm tra CBZ."), 0) end
            assert(entry.mode == "file" and entry.path:match("^%d+%.[a-z]+$"), "invalid page entry")
            if pages then
                assert(pages[count] and entry.path == pages[count].name
                    and tonumber(entry.size) == pages[count].size, "archive page mismatch")
            end
            -- Read each entry to detect truncated data/CRC errors, one image at a time.
            assert(tonumber(entry.size) > 0 and tonumber(entry.size) <= 8 * 1024 * 1024, "invalid page size")
            total = total + tonumber(entry.size)
            assert(total <= 512 * 1024 * 1024, "archive too large")
            assert(reader:extractToMemory(entry.path), reader.err or "archive data incomplete")
        end
        assert(not reader.err, reader.err)
        assert(count > 0 and (not pages or count == #pages), "archive incomplete")
    end)
    pcall(reader.close, reader)
    return ok, err
end

function Cbz.write(path, pages, progress)
    local Archiver = require("ffi/archiver")
    local writer, pending = Archiver.Writer:new{}, path .. ".part"
    local ok, err = pcall(function()
        assert(#pages > 0, "no pages")
        assert(writer:open(pending, "zip"), writer.err or "archive open failed")
        assert(writer:setZipCompression("store"), writer.err or "compression failed")
        for i, page in ipairs(pages) do
            if progress and progress(i, #pages, true) == false then error(_("Đã dừng đóng gói."), 0) end
            local file = assert(io.open(page.path, "rb"))
            local data = file:read(page.size + 1)
            file:close()
            assert(data and #data == page.size, "page read incomplete")
            assert(writer:addFileFromMemory(page.name, data, os.time()), writer.err or "archive write failed")
        end
    end)
    local closed, close_err = pcall(writer.close, writer)
    if not ok or not closed or close_err == false then
        os.remove(pending)
        return nil, err or close_err
    end
    local verified, verify_err = Cbz.verify(pending, pages, progress)
    if not verified then os.remove(pending); return nil, verify_err end
    -- Never delete an existing book to work around FAT rename failures.
    local existing = io.open(path, "rb")
    if existing then existing:close(); os.remove(pending); return nil, _("CBZ đã tồn tại; mở từ Thư viện.") end
    local renamed, rename_err = os.rename(pending, path)
    if not renamed then os.remove(pending); return nil, rename_err end
    return path
end

return Cbz
