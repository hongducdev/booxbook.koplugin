# Kiến trúc hệ thống

Plugin KOReader `booxbook.koplugin` cho Onyx Boox và thiết bị khác: RSS/Atom lưu HTML cục bộ; adapter truyện DocLN, Wattpad, Sangtacviet, MeTruyenCV, TVTruyen, Truyện Full. Thư viện mở thư mục tải bằng trình quản lý file KOReader.

Trình đọc cá nhân. Không vượt VIP / paywall / captcha.

## Nhận sách từ mạng nội bộ

`main.lua → ui/wifi-transfer.lua → wifi-transfer-server.lua → wifi-upload.lua`.
Màn hình riêng dùng Catalog; server LuaSocket bind địa chỉ IPv4 của interface
Wi-Fi, chỉ fallback bảng định tuyến khi không đọc được interface. Poll nonblocking mỗi 50 ms, tối đa
4 kết nối, 1 MiB/kết nối/tick; idle timeout 30 giây, request timeout 30 phút.
Trang `wifi-transfer-page.lua` không có tài nguyên ngoài: XMLHttpRequest gửi raw
File lần lượt, báo tiến độ và lỗi. Đây là HTTP **nhận vào**, độc lập HTTP client
`booxbook.http` vốn chỉ tải nội dung nguồn.

POST `/upload` kiểm Host/Origin, mã phiên 6 chữ số từ `/dev/urandom` (rejection
sampling, giữ số 0 đầu), khóa riêng IP nguồn sau 5 lần sai đến khi mở lại phiên, Content-Length
và tên/đuôi sách; chặn traversal, file ẩn/reserved, header trùng/chunked và file
quá 512 MiB. Mã QR chứa token trong fragment, trang xóa fragment sau khi đọc;
token không nhúng trong HTML được phục vụ. Server không cung cấp API đọc/xóa file.
Ghi stream vào `received/.upload-<session>-<id>.part`, đóng file thành công mới
rename; giữ file đích đã có. Disconnect/timeout/stop xóa file tạm thuộc request.
Nếu tiến trình bị kill cứng, file `.part` có thể còn lại, không xuất hiện như sách.
Callback bật Wi-Fi mang generation ID nên không mở server sau khi người dùng đã rời.
Sau rename thành công, callback UI hiện tên sách trong 3 giây.
Suspend/Exit/CloseWidget/NetworkDisconnected và đóng Catalog dừng server, hủy timer,
trả standby counter; không tự bật lại. Thiết bị tự ngủ vẫn kết thúc phiên.

API đối chiếu: [KOReader HTTP Inspector lifecycle](https://github.com/koreader/koreader/blob/master/plugins/httpinspector.koplugin/main.lua),
[QRMessage](https://github.com/koreader/koreader/blob/master/frontend/ui/widget/qrmessage.lua).
Tests dùng LuaJIT, file tạm thật và socket double tiêm partial I/O/lỗi; TCP desktop
8 MiB chạy qua lớp transport Python tương thích LuaSocket, chưa thay thế test
LuaSocket native/QR/Wi-Fi trên Boox. Không tự mở firewall Kindle.

## Tải sách từ OneDrive

`main.lua → ui/onedrive.lua → onedrive.lua → booxbook.http → received/`.
OneDrive dùng Microsoft Device Code Flow với public client ID của ứng dụng BooxBook
(người dùng vẫn có thể thay thế trong cài đặt),
scope tối thiểu `Files.Read offline_access`; không có client secret. UI không poll nền:
hiện verification URL + user code/QR, rồi người dùng chủ động kiểm tra sau khi đăng nhập.
Access token tự refresh và Graph request chỉ retry một lần sau 401.
Mọi request OAuth/Graph của OneDrive bật xác minh chuỗi chứng chỉ bằng CA bundle
đóng gói trong KOReader và kiểm tra hostname từ Subject Alternative Name; redirect
về HTTP bị từ chối. Luồng đăng nhập không dùng chế độ TLS `verify = none` của các
nguồn nội dung công khai hiện có.

Graph listing duyệt từng thư mục qua `/me/drive/root/children` và
`/me/drive/items/{id}/children`, theo `@odata.nextLink` tối đa 20 trang và chỉ chấp
nhận nextLink HTTPS cùng `graph.microsoft.com/v1.0`. Chỉ các định dạng sách trong
allowlist Wi-Fi xuất hiện; không quét đệ quy, upload, sync hay thao tác file cloud.
Download `/content` được stream vào file `.part` dưới `received/`; HTTP chung bỏ
Authorization khi redirect sang URL preauthenticated khác host. Size 1–512 MiB phải
khớp metadata, file đích không được tồn tại, rename thành công mới báo hoàn tất.

Token nằm trong `settings/booxbook.lua`, không được log. Đây là storage plaintext,
không phải keychain; scope read-only và hành động đăng xuất/xóa token là ranh giới
bảo vệ thực tế trên các filesystem KOReader hỗ trợ.

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
- HTTPS đi qua DoH Cloudflare với bootstrap `1.1.1.1`, giữ hostname gốc cho Host/SNI, cache A record theo TTL và fallback DNS hệ thống nếu DoH không dùng được.
- Sangtacviet tắt (`stv_enabled = false`) đến khi xác nhận cảnh báo. 18+ tắt; ảnh bật (`adult_content`, `include_images`).
- Truyện: **một HTML mỗi chương**. Range kiểm tra entry + file trước request, trả `existing` để mở/báo bỏ qua; entry mất file được tải lại. Index ghi từng chương qua file tạm, giữ `index.json.bak` hợp lệ gần nhất và chỉ fallback khi schema/id đúng. Bật `novel_epub` để tự tạo EPUB theo khoảng; action thủ công đóng gói các HTML đã tải với `keep_html=true`. Bộ ghi mở lại archive trước rename; nếu FAT từ chối đè file đích thì replace an toàn.

## DocLN

`novel-export.lua` xử lý đóng gói và giữ/xóa HTML. `packageSaved` chọn HTML
theo số mục lục từ index, bỏ qua file thiếu/entry EPUB và không gọi adapter.
Khi `novel_keep_html=false`,
ghi tham chiếu EPUB vào index trước khi xóa HTML; lỗi xóa dừng ngay và trả
những HTML còn lại vào index. Đóng gói sau khi hủy tải (`keep_html=true` /
`packagePartial`) luôn giữ HTML để resume. ConfirmBox hủy tải hiện trước
list/toast (`cancel_callback`) để không bị fullscreen menu che. Offline deduplicate theo path; tên file chỉ nhận
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
Hủy giữa chừng hỏi Đóng gói / Giữ ảnh trước list/toast; cancel dùng sentinel
`booxbook:cancelled` (không khớp chuỗi UI).

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

## TruyenQQ CBZ

Cùng pipeline `comic-download`/`comic-cbz` như Truyện Tuổi Thơ nhưng qua adapter riêng
`truyenqqko.com`: series `/truyen-tranh/<slug>-<id>`, chapter `/truyen-tranh/<slug>-chap-<n>`.
Parser custom (không phải Madara), chỉ nhận ảnh từ `truyenqqko.com` (+ `m.`/`st.`)
và CDN `hinhhinh.com` / `truyenvua.com`; HTTP 429 báo thử lại sau, không retry dồn dập. Lưu dưới
`comics/truyenqq/<series>/<chapter>.cbz`. Giới hạn 600 trang/tập như trên.

## Đọc tiếp nối (EndOfBook)

`main.lua:onEndOfBook` ủy quyền cho `booxbook/continuation.lua`; `return true`
(nuốt dialog KOReader) khi đã hiện hộp của mình, khi guard `prompted_path` còn hiệu
lực (chống hỏi lặp trong cùng một lần mở), hoặc khi đã kích hoạt `bootstrapOnline`
dị bộ (hộp hiện sau khi fetch xong). Còn lại `return nil` để dialog mặc định hiện.
`onCloseDocument` gọi `Continuation.reset()` xóa guard.

Comic: `resolveComicNext` đọc sidecar `<tập>.cbz.meta.json` (giới hạn 64 KiB), fallback
`buildMetaFromPath` từ `manifest.json` (giới hạn 512 KiB) + ghi bù sidecar. `next_url`
phải qua `adapterFor` cùng `source_id` và cùng series, ngược lại fail-closed. Thiếu meta
→ `bootstrapOnline` fetch `getSeries` → `writeManifest` → resolve lại; lỗi thì hộp
**Thử lại?**. `Download.chapter` không ghi sidecar khi auto-meta thiếu `next_url`
(`shouldWriteMeta`) để lần sau vẫn dò được mục lục mới; riêng `resolveComicNext` vẫn
cache sidecar khi `manifest.json` đã có (kể cả tập cuối → báo hết bộ luôn).

Novel: `resolveNovelNext` đọc `novels/<nguồn>/<id>/index.json`, nhận
`chapters-<từ>-<đến>.epub` / `chapter-<n>.html` / `book.epub`; `next_entry.file` tồn tại
mới là đã tải. Chưa tải → `Novels.downloadChapter` (validate nguồn/id/số chương, báo
hết truyện khi vượt số chương mục lục mới).

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
