# Kiến trúc hệ thống

Plugin KOReader `booxbook.koplugin` cho Onyx Boox và thiết bị khác: RSS/Atom lưu HTML cục bộ; adapter truyện DocLN, Wattpad, Sangtacviet, MeTruyenCV, TVTruyen, Truyện Full. Thư viện mở thư mục tải bằng trình quản lý file KOReader.

Trình đọc cá nhân. Không vượt VIP / paywall / captcha.

## Luồng

```
main.lua  →  booxbook.ui (Báo + Truyện / Thư viện file / Cài đặt / Cập nhật)
              ↓
         booxbook.http + cookie + booxbook.rate_limit
              ↓
         booxbook.html → HTML bài/chương (mặc định) / booxbook.epub (tùy chọn)
              ↓
         booxbook.source → rss / docln / wattpad / sangtacviet / metruyencv / tvtruyen / truyenfull
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
- HTML bài có h1 đã escape. Ảnh: lazy/srcset/URL tương đối; chỉ HTTP(S) JPEG/PNG/GIF/WebP; tối đa 20 request, 2 MiB/ảnh, 10 MiB/bài. URL trùng dùng chung file. Lỗi ảnh vẫn đọc được chữ. Ảnh nằm trong thư mục sidecar `<bài>.html.images/`; tải lại bài cắt ảnh thừa không còn dùng, tắt ảnh rồi tải lại xóa sidecar — chỉ sau khi ghi HTML thành công (ghi fail giữ bài cũ và ảnh cũ). Fetch ảnh fail thì không prune. Xóa HTML (báo đọc xong, EPUB không giữ HTML) xóa sidecar chỉ khi xóa HTML thành công. Bìa grid dưới `covers/<nguồn>/`, trần 50MB toàn cây (FIFO theo mtime, không xóa bìa vừa ghi); staging comic `.-pages/` xóa sau khi xuất CBZ, thư mục rỗng hoặc quá 7 ngày được quét dọn.
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

## MeTruyenCV

`sources/metruyencv.lua` dùng API `backend.metruyencv.com/api`, header X-App và
X-Signature theo Nekori 1.0.6. Chữ ký dùng AES-128-CBC/PKCS7 bằng Lua trong
`metruyencv-aes.lua`; SHA1/Base64 dùng `ffi/sha2` có sẵn. Giải mã dùng
`ffi/crypto` AES-ECB rồi XOR để khôi phục CBC, kiểm tra đầy đủ PKCS7.
Không gọi trực tiếp các symbol AES-CBC/Encrypt/RAND/Base64 mà Android monolibtic
không export. Hash đọc 8 byte `/dev/urandom` trên Android/Linux (Kindle, Kobo…);
lỗi đọc dừng tải. Không thêm native library hoặc đường dẫn Android vào plugin.
Đã kiểm tra wrapper từ APK Android; các thiết bị Kindle/Kobo chưa được test thật.
JSON đi qua HTTP chung với giãn cách ≥ 1600ms; lỗi 403/429/giải mã dừng download.
Mục lục gộp trang, loại ID trùng và sắp theo index; chương khóa bỏ qua trước request.
UI grid dùng cùng mẫu Wattpad, mục lục/HTML/EPUB/offline dùng pipeline chung;
đường lưu `novels/metruyencv/<id>/`. Chưa hỗ trợ URL slug hoặc lọc độ tuổi.

## Truyện Tuổi Thơ CBZ

Adapter comic đăng ký trong registry. `ui/truyentuoitho` dùng CoverGrid và SeriesUI:
duyệt `/manga/page/N/?m_orderby=...`, tìm `/?s=...&post_type=wp-manga&paged=N`.
Parser hỗ trợ `.page-item-detail`, `.c-tabs-item__content`, `.wp-pagenavi`;
thông tin bộ trong `.post-title`/`.description-summary`. Khi có `#manga-chapters-holder`,
POST công khai `/<bộ>/ajax/chapters/`; lọc đúng bộ, loại trùng và đảo mục lục Madara về thứ tự đọc.
Tải khoảng gọi từng tập tuần tự, giữ kết quả trước lỗi/hủy và bỏ qua CBZ đã có.

`ui/truyentuoitho` nhận URL tập → `sources/truyentuoitho` lấy ảnh trong
`.reading-content` → `comic-download` dùng `Http.downloadToFile` → `comic-cbz`
ghi ZIP store bằng archiver KOReader → ReaderUI. Không đổi adapter truyện chữ.
HTTP có tùy chọn `allow_url` để kiểm tra từng redirect trước request; lỗi close
file cũng làm download thất bại. Selector HTML xử lý đúng thẻ rỗng `img`.

Trang hoàn chỉnh trong thư mục staging ẩn có receipt URL + byte count để tải tiếp.
Kiểm tra chữ ký ảnh, kích thước RIFF WebP, Content-Length nếu có; không giải mã
toàn bộ ảnh để kiểm tra pixel. Giới hạn 600 trang, 8 MiB/ảnh, 512 MiB/tập.
Đóng gói/đọc kiểm tra từng entry để chặn lỗi CRC/truncated ZIP; tên trang `%04d`.
Chỉ rename sau khi archive đủ trang; không xóa CBZ cũ khi rename thất bại.
Staging giữ khi lỗi/hủy; thành công xóa các trang đã dùng. CBZ dưới
`comics/truyentuoitho/<series>/<chapter>.cbz`, mở offline qua FileManager.
Đã xác minh ReaderUI/WebP và fit-page trên điện thoại Samsung Android; chưa xác minh Boox/Kindle/Kobo.

## Liên kết

- [Quy ước phát triển](development.md)
- [Hướng dẫn dùng](usage.md)
- [README](../README.md)

## TVTruyen HTML

`sources/tvtruyen.lua` lấy HTML qua HTTP chung (≥1600ms). Parser dùng
`Html.elements/select/attr`: `.info-mobile-card`, `#comic_name`,
`#mobile-list-chapter`, `#chapter-content`. Theo `rel=next` tuần tự, chống mục lục
lặp, giới hạn 1000 trang; sắp chương theo số URL. Tên thư mục là slug đã kiểm tra,
chương phải thuộc đúng slug. Chỉ lưu chữ đã escape, không tải script/ảnh quảng cáo.
Không phụ thuộc crypto; dùng grid và pipeline HTML/EPUB/offline hiện có.

## Truyện Full HTML

`sources/truyenfull.lua` lấy HTML qua HTTP chung (≥1600ms). Parser:
`.truyen-title`, `data-image` (grid), `.book img`, `#list-chapter`, `#chapter-c`.
Duyệt `/danh-sach/truyen-moi|truyen-hot/trang-N/`, tìm `/tim-kiem?tukhoa=`. TOC
theo `/<slug>/trang-N/`, chống lặp, giới hạn 1000 trang; sắp theo số `chuong-N`.
Chương trống/khóa bỏ qua (không dừng cả khoảng). Host chỉ `truyenfull.live`.
