# Kiến trúc hệ thống

Plugin KOReader `booxbook.koplugin` cho Onyx Boox và thiết bị khác: RSS/Atom lưu HTML cục bộ; adapter truyện DocLN, Wattpad, Sangtacviet. Thư viện mở thư mục tải bằng trình quản lý file KOReader.

Trình đọc cá nhân. Không vượt VIP / paywall / captcha.

## Luồng

```
main.lua  →  booxbook.ui (Báo + Truyện / Thư viện file / Cài đặt / Cập nhật)
              ↓
         booxbook.http + cookie + booxbook.rate_limit
              ↓
         booxbook.html → HTML bài/chương (mặc định) / booxbook.epub (tùy chọn)
              ↓
         booxbook.source → rss / docln / wattpad / sangtacviet
```

Điểm vào mạng bọc `Network.whenOnline`. Selftest GET `https://example.com` kèm Referer, ghi `_selftest.html` (`Tiếng Việt`) và `_selftest.epub` dưới `koreader/booxbook/`.

Cây file: [development.md](development.md). Catalog RSS: [news-categories.md](news-categories.md).

## HTTP, cookie, Referer

Mọi request đi qua `booxbook.http`. Caller không gọi `socket.http` trực tiếp. Module nội bộ là `require("booxbook.*")` để không đụng tên generic của KOReader.

| Quy tắc | Hành vi |
|------|----------|
| Header | UA desktop Chrome/142 (không phải Android); override không phân biệt hoa thường; `referer` tùy chọn |
| VnExpress | Cookie trình bày `device_env=4; device_env_real=4` chỉ trên vnexpress.net |
| Log | `Cookie`, `Authorization`, `Set-Cookie` ghi `[redacted]` |
| Redirect | `redirect = false`; theo Location tối đa 5 hop; 303 → GET |
| Credential khi đổi host | Bỏ cookie tùy chọn và header Cookie/Authorization khi Location khác host |
| Retry | 3 lần khi timeout; 403: một backoff rồi dừng; 429: dừng ngay |
| Rate limit | `rate_limit.wait(host)` trước mỗi lần thử; `delay_ms` mặc định 1200ms |
| Body | tối đa 2 MiB, cắt khi stream |

Khóa cookie trong settings: `docln_cookie`, `wattpad_cookie`, `stv_cookie`. Dán từ trình duyệt. UI không hiện lại giá trị sau khi lưu.

UA desktop theo [Nekori c63f848](https://github.com/Yuneko-dev/Nekori-plugins/commit/c63f848156dcc7f1ff3b72cac010c310d0dc6201). Không xoay UA, không vượt rate limit hay nội dung trả phí.

## Adapter contract (`booxbook.source`)

Registry: `Source.register`, `Source.get`, `Source.list`, `Source.enabledList(settings)`. `register` cần `adapter.id`. `enabledList` gồm adapter không có `enabled`, hoặc `adapter.enabled(settings)` đúng.

Mỗi adapter trả:

```lua
{
  id = "docln",
  name = "DocLN",
  kind = "novel", -- hoặc "news"
  capabilities = { search = true, browse = true, login = false, adult = true },
  enabled = function(settings) end, -- tùy chọn
  search = function(query, page) end,   -- → { items, has_more }
  browse = function(kind, page) end,    -- latest|popular
  getSeries = function(ref) end,        -- series + volumes + chapters
  getChapter = function(ref) end,       -- { title, html } hoặc { skipped = "locked" }
}
```

`getChapter` không vượt paywall/VIP. Chương khóa trả `{ skipped = "locked" }`.

## UI và mặc định

- Chuỗi giao diện: tiếng Việt, `_()` (`gettext`).
- Báo: 17 đầu báo (9 Việt / 8 quốc tế), 633 kênh nonempty ngày 04/09/2026, 1–20 bài/danh mục, ảnh bật mặc định, fallback tóm tắt. `feeds.lua` gắn `region` (`vietnam`/`world`) tường minh. Đã bỏ công tắc nguồn.
- HTML bài có h1 đã escape. Ảnh: lazy/srcset/URL tương đối; chỉ HTTP(S) JPEG/PNG/GIF/WebP; tối đa 20 request, 2 MiB/ảnh, 10 MiB/bài. URL trùng dùng chung file. Lỗi ảnh vẫn đọc được chữ.
- Online: **Báo → Báo Việt / Báo Nước Ngoài → đầu báo → danh mục → bài**. Menu vùng/đầu báo không HTTP. Chọn danh mục gọi `Rss.list` (chỉ XML). Chọn tiêu đề gọi `Rss.loadArticle` cho đúng bài đó. RSS tùy chỉnh chỉ tóm tắt. **Tin đã tải** giữ file cũ.
- Mọi màn hình fullscreen dùng chung TitleBar X và chân **Quay lại / Trước / trang / Sau**. Không dùng Menu chevron của KOReader.
- Hành động online hoãn sau khi chọn menu, có Wi-Fi và Trapper. Ghi HTML qua file tạm rồi rename.
- Cổng mạng (`booxbook.network.whenOnline`): nếu đã online/connected thì chạy ngay; chỉ gọi `beforeWifiAction` khi cả hai false.
- Sangtacviet tắt (`stv_enabled = false`) đến khi xác nhận cảnh báo. 18+ tắt; ảnh bật (`adult_content`, `include_images`).
- Truyện: **một HTML mỗi chương**. Bật `novel_epub` để tạo thêm EPUB theo khoảng chương sau lượt tải thành công. Bộ ghi đọc từng HTML, giữ thứ tự/mục lục, kiểm tra lỗi ghi, mở lại archive trước khi rename; nếu rename fail vì file đích đã có thì xóa đích rồi thử lại.

## DocLN

`novel-export.lua` xử lý đóng gói và giữ/xóa HTML. Khi `novel_keep_html=false`,
ghi tham chiếu EPUB vào index trước khi xóa HTML; lỗi xóa dừng ngay và trả
những HTML còn lại vào index. Offline deduplicate theo path; tên file chỉ nhận
`tên.ext`, từ chối `.` / `..` / `../`.
`news-cleanup.lua` nhận CloseDocument từ plugin, đợi tick sau mới gọi native
FileManager:deleteFile. Chỉ nhận HTML dưới news sau kiểm tra realpath; yêu cầu
`news_delete_finished=true` và (`summary.status=complete` hoặc EndOfBook mà
`percent_finished` vẫn ≥ 0.99).

Thư viện dùng `FileManager.instance.file_chooser:changeToPath` hoặc
`FileManager:showFiles` sau khi đóng Catalog và ReaderUI đang mở. Không sao chép
logic xóa/đổi tên/di chuyển hay trạng thái đọc vào plugin. Tham chiếu API:
[FileManager](https://github.com/koreader/koreader/blob/master/frontend/apps/filemanager/filemanager.lua),
[ReaderUI](https://github.com/koreader/koreader/blob/master/frontend/apps/reader/readerui.lua),
[archiver](https://github.com/koreader/koreader-base/blob/master/ffi/archiver.lua).
Lưu ý: `archiver.Writer:close()` hiện không trả mã lỗi native;
plugin kiểm tra lỗi ghi, mở lại archive bằng Reader trước khi rename, và
thử replace khi FAT từ chối đè file đích.

`Truyện → DocLN → grid 2×3 (Mới cập nhật) → tập/chương → khoảng → HTML → ReaderUI`.

Browse theo LNHako `/tim-kiem-nang-cao`. Tối đa `Docln.LIST_LIMIT` (6) item/trang. Payload `#chapter-c-protected` decode `xor_shuffle` / `base64_reverse` khi đã có trên trang; không lấy key hay chạy JS. File `ch-<id>.html` dưới `novels/docln/<kind-id>/`. `index.json` cập nhật từng chương, giữ mục cũ khi lỗi dở. Giãn cách ≥ 1,5 giây; 429 dừng, không đổi domain.

Catalog `push` giữ widget cha dưới widget con. `pop` chỉ đóng widget đang rời. `clearStack` đóng hết khi sang ReaderUI.

## Wattpad

`ui/wattpad.lua` duyệt/tìm/URL. `sources/wattpad.lua` cô lập JSON v3 và apiv2 storytext. `ui/novels.showSeries` dùng chung TOC. Lưu dưới `novels/wattpad/<id>/`. `gzip.lua` giải nén zlib có chặn kích thước/CRC. 403/429 dừng hàng đợi. Chỉ giữ chữ đã escape.

## Sangtacviet

`ui/sangtacviet.lua` giống Wattpad (Mới cập nhật / Lượt xem + URL/tìm). Tải tắt đến ConfirmBox lần đầu. Probe `.com` → `.app` → `.xyz` → `.pro`, nhớ `stv_home`, prime `_ac`/`_gac`, đọc `sajax=readchapter` kèm Referer. VIP bỏ qua không request. Giãn cách sàn 2000ms. Glyph PUA chỉ host `sangtac`/`dich`. Đường lưu `{host}-{bookid}`; id chương dài giữ chuỗi.

## Liên kết

- [Quy ước phát triển](development.md)
- [Hướng dẫn dùng](usage.md)
- [README](../README.md)
