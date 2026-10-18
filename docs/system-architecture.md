# Kiến trúc hệ thống

Plugin KOReader `booxbook.koplugin` cho Onyx Boox và thiết bị khác: RSS/Atom lưu HTML cục bộ; adapter truyện DocLN, Wattpad, Sangtacviet, MeTruyenCV, TVTruyen, Truyện Full và truyện tranh Truyện Tuổi Thơ, TruyenQQ, Cbunu. Thư viện mở thư mục tải bằng trình quản lý file KOReader.

Trình đọc cá nhân. Không vượt VIP / paywall / captcha.

## Nhận sách từ mạng nội bộ

`main.lua → ui/wifi-transfer.lua → wifi-transfer-server.lua → wifi-upload.lua`.
Trên Kindle, UI mở quy tắc iptables INPUT/OUTPUT cho đúng cổng đã bind, theo
HTTP Inspector của KOReader. Chỉ giữ quy tắc trong phiên nhận; `Transfer.stop`
gỡ khi đóng/suspend/lỗi poll, và hoàn tác nếu thiết lập chỉ thành công một phần.
Không hiện URL khi mở tường lửa thất bại; Android/Kobo bỏ qua bước này.
Màn hình riêng dùng Catalog; server LuaSocket listen `0.0.0.0` trên cổng trống đầu tiên
trong 8080–8088 (hiển thị cổng thật), hiển thị địa chỉ LAN tốt nhất — interface VPN/cellular
(`tun*`, `utun*`, `wg*`, `tailscale*`, `rmnet*`, `ccmni*`, `wwan*`, …) xếp cuối, địa chỉ
routable trước link-local, cuối cùng mới tới địa chỉ lấy từ bảng định tuyến — kèm danh sách
địa chỉ dự phòng để người dùng đổi khi địa chỉ đầu không tới được. Poll nonblocking mỗi 50 ms,
tối đa 4 kết nối, 1 MiB/kết nối/tick; idle timeout 30 giây, request timeout 30 phút.
Trang `wifi-transfer-page.lua` không có tài nguyên ngoài: XMLHttpRequest gửi raw
File lần lượt, báo tiến độ và lỗi. Đây là HTTP **nhận vào**, độc lập HTTP client
`booxbook.http` vốn chỉ tải nội dung nguồn.

POST `/upload` kiểm Host/Origin (mọi địa chỉ IPv4 hoặc `localhost` đúng cổng; từ chối tên miền và
Origin HTTPS; `Sec-Fetch-Site: cross-site` chỉ bị chặn ở request ghi nên bấm link từ ứng dụng khác
vẫn mở được trang), từ chối ngay khi accept mọi kết nối có địa chỉ nguồn ngoài mạng nội bộ
(private/link-local/loopback/CGNAT, hoặc cùng hai octet đầu với một địa chỉ của máy nên LAN cấp IP
public vẫn dùng được), mã phiên 6 chữ số từ
`/dev/urandom` (rejection sampling, giữ số 0 đầu), khóa riêng IP nguồn sau 5 lần sai đến khi mở
lại phiên, Content-Length và tên/đuôi sách; chặn traversal, file ẩn/reserved, header trùng/chunked
và file quá 512 MiB. Mã QR chứa token trong fragment, trang xóa fragment sau khi đọc; token không
nhúng trong HTML được phục vụ. Server không cung cấp API đọc/xóa file. Bộ đếm kết nối/yêu cầu/bị
từ chối, địa chỉ Host gần nhất và số lần bắt gặp TLS handshake trên cổng HTTP được hiển thị ở mục
**Kiểm tra kết nối và kết quả** để phân biệt lỗi mạng với lỗi địa chỉ.
Ghi stream vào `received/.upload-<session>-<id>.part`, đóng file thành công mới
rename; giữ file đích đã có. Disconnect/timeout/stop xóa file tạm thuộc request.
Nếu tiến trình bị kill cứng, file `.part` có thể còn lại, không xuất hiện như sách.
POST `/clip` nhận liên kết bài báo từ trang web Wi-Fi, kiểm tra token phiên, kiểm tra an toàn URL (chặn SSRF vào private LAN và loopback), bóc tách nội dung bài viết chính qua `booxbook.web-clipper`, chuẩn hóa đường dẫn ảnh, gói thành HTML chuẩn và lưu vào `news/web-clipper/`.
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
scope `Files.ReadWrite offline_access` (hỗ trợ upload sao lưu); không có client secret. UI không poll nền:
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
         booxbook.source → 25 nguồn: rss (báo), 19 nguồn truyện chữ, 5 nguồn truyện tranh CBZ
                           + DTV eBook (kind `ebook`: tải file EPUB/PDF/MOBI/AZW3, không có chương)
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
| Redirect | `redirect = false`; theo Location tối đa `opts.max_hops` hop (mặc định 5); 303 → GET; chạm trần thì trả luôn `Set-Cookie` của chính phản hồi redirect |
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

### Metadata + hook tùy chọn

Mỗi adapter tự khai báo cách hiển thị và cách ánh xạ tham chiếu, nên
`ui/source-page.lua` (truyện chữ) và `ui/comic-page.lua` (truyện tranh) render
mọi nguồn mà không cần file UI riêng: `ui/<id>.lua` chỉ còn một dòng shim.

```lua
view = {                        -- cách hiển thị
  base_url = "https://…",       -- hoặc function() khi domain đổi lúc chạy (Sangtacviet)
  cover_referer = "https://…/",
  cover_delay_ms = 1600,
  search_hint = "…",            -- gợi ý trong ô nhập
  error_hint = "…",             -- tùy chọn, thay câu "Thử nhập URL truyện."
  title_with_kind = true,       -- tùy chọn: tiêu đề kèm tên mục đang xem
  browse = { { text = "…", kind = "latest" } },
  is_ref = function(text) end,  -- nhập URL/tham chiếu hay từ khóa
}
locate = function(series) end,       -- → id, path (path = nil khi URL là chương)
chapterRef = function(chapter) end,  -- → series_id, chapter_id, max_id_len
seriesUrl = function(series_id) end, -- tùy chọn (chỉ comic): URL bộ truyện
```

Nguồn không có `genres` thì không dựng menu **Thể loại** và không hỏi tên thể loại.

Registry: `Source.ofKind(kind)` lọc adapter theo `kind`; `Source.findRef(kind, ref)`
chọn adapter đầu tiên nhận `parseRef(ref)`; `Source.locate(adapter, series)` gọi
`adapter.locate`. `novel-download`, `comic-download` và `continuation` đều đi qua
các hàm này — không còn chuỗi `if source_id == …`.

## Giới hạn thời gian & thông báo lỗi

Không thao tác nào được phép chạy vô hạn trên main thread: KOReader bị Android coi là
không phản hồi (ANR) chỉ sau ~5 giây, nên mọi đường mạng đều có trần.

- **Ngân sách theo hành động** (`booxbook/http.lua`): `Http.beginOperation(giây)` /
  `Http.endOperation()` / `Http.remaining()` / `Http.expired()`. Mặc định `OP_TIMEOUT = 20`
  cho một hành động (mở nguồn, lưới, mục lục, mở chương); `BULK_TIMEOUT = 300` cho việc tải
  dung lượng lớn (CBZ/EPUB/bài báo/cloud) vốn có thanh tiến trình và nút hủy.
- Ngân sách **chỉ nới ra khi lồng nhau**, không thu hẹp: tải một khoảng chương (BULK) mà
  bên trong có lấy mục lục (OP) thì vẫn giữ ngân sách dài.
- `Http.check` trước **mỗi** request và **mỗi** lần chờ rate-limit; hết ngân sách thì trả
  `false, "operation-timeout"` ngay chứ không thử lại.
- Timeout một request: `DEFAULT_TIMEOUT = 10s`, `DEFAULT_MAXTIME = 20s` (nới lại ở `ec5d2c0` vì
  4s quá sát với mạng thật); timeout được **cắt** theo thời gian còn lại để request cuối không vượt
  quá ngân sách. Tải file giữ 60s/180s. Hệ quả: một request **không** nằm trong ngân sách có thể
  chặn tới 20s, nên mọi đường mạng đồng bộ đều phải mở ngân sách bằng `Http.beginOperation` —
  trông cậy vào timeout nhỏ là không đủ.
- `RateLimit.wait(host, delay_ms, max_ms)` trả `false` khi phải ngủ quá `max_ms`, để caller
  dừng trước khi gửi request sớm.
- DoH (`booxbook/doh.lua`): query 8s, handshake TLS 10s, tối đa 3 địa chỉ mỗi host (nới cùng
  `ec5d2c0`); mỗi lần thử địa chỉ đều gọi `Async.step()` nên chỉ chặn trong một bước DNS.
  Lỗi được `error(reason, 0)` nên không còn tiền tố `file.lua:dòng:`.
- Mục lục dài: `MAX_TOC_PAGES = 60` cho Truyện Full và TVTruyen; hết trần hoặc hết ngân sách
  thì dừng và giữ phần đã đọc, đặt `series.truncated = true`; UI báo
  "Mục lục quá dài, chỉ lấy được N chương đầu."
- **Thông báo lỗi** (`booxbook/fault.lua`): mọi điểm hiện thông báo đi qua `Fault.notify`.
  `Fault.message(text, chủ_ngữ)` chỉ viết lại khi chuỗi chứa chi tiết mã nguồn
  (`file.lua:dòng`, `stack traceback`, `attempt to …`, `bad argument`, `nil value`); mọi câu
  đã đọc được thì giữ nguyên. Bảng map: refused → "Không kết nối được tới máy chủ.",
  timeout/wantread → "Máy chủ phản hồi quá chậm.", TLS/certificate → "Lỗi bảo mật kết nối
  (TLS).", network → "Lỗi kết nối mạng.", download failed → "Tải không thành công.",
  403/404/429/5xx → câu tương ứng, `operation-timeout` → "Việc tải mất quá nhiều thời gian
  nên đã dừng lại.", còn lại → "Không tải được nội dung. Kiểm tra Wi-Fi rồi thử lại."
  `Fault.clean(text)` chỉ bỏ tiền tố vị trí, dùng ở tầng HTTP/DoH.
- **Mọi thông báo phải có `timeout`**: mặc định của KOReader là `InfoMessage.timeout = nil` =
  "nằm đến khi chạm", mà InfoMessage còn là `modal = true` — hộp không timeout sẽ nuốt cú chạm kế
  tiếp, và nhiều hộp thì xếp lớp lên nhau nên rất giống máy đang treo. `Fault.notify`
  (`Fault.NOTIFY_TIMEOUT = 6`) và `Update.NOTIFY_TIMEOUT = 6` luôn truyền `timeout`; chỗ gọi trực
  tiếp `InfoMessage` cũng phải truyền (`ui/series.lua` 5s; `ui/wifi-transfer.lua` 8s cho lỗi, 20s
  cho địa chỉ/mã phiên để còn kịp đọc và gõ từ điện thoại). Hộp tiến trình dài hạn thì tự đóng:
  `Update.installAsync` giữ widget và `UIManager:close` khi công việc trả về.
- Không nhánh nào im lặng: guard `busy` cũng hiện "Đang tải, vui lòng chờ."

Ghi chú: khi KOReader đang ở silent mode (suspend/screensaver), `UIManager:show` thoát sớm với
widget có `honor_silent_mode = true` (InfoMessage là một trong số đó). Thông báo lúc đó **mất
im lặng** chứ không treo máy — đừng dựa vào thông báo để biết một tác vụ nền đã xong.

**Chặn UI — ai đã nhường sẵn:** `Trapper` của KOReader cũng chạy trên coroutine và `Trapper:info`
gọi `coroutine.yield()` (0,1s, để xử lý chạm huỷ) khi widget hiện hành là InfoMessage — mà hộp
"Đang tải…" của plugin đúng là InfoMessage. Đường **tải** gọi `Trapper:info` sau mỗi ảnh nên **đã
nhường UI từ trước**; đường **load** (mục lục/danh sách) không gọi gì giữa các request nên bị chặn —
đó chính là chỗ `Async` vá. Đơn vị chặn lớn nhất còn lại ở đường mạng là **một request**
(`DEFAULT_TIMEOUT = 10s`, `DEFAULT_MAXTIME = 20s`) — vẫn trên ngưỡng watchdog ~5s của Android, nên
cách bảo vệ thật sự là: đường nào không yield thì phải có **ngân sách hành động** (hoặc trần riêng
nhỏ hơn) chứ không thể trông vào timeout từng request.

**Resumable (Phase 2, đã làm cho các đường "load")** — `booxbook/async.lua`: một coroutine
nhỏ, `Async.step()` được `Http.request` và vòng thử địa chỉ của DoH gọi trước mỗi bước mạng.
Trong `Async.run` nó `coroutine.yield()`, scheduler nhường `UIManager:nextTick` rồi resume — nên
mỗi request chỉ chặn main thread trong thời gian của chính nó (≤ 5s), giữa các request UI vẫn vẽ
và nhận chạm (hết ANR khi mục lục dài). Ngoài `Async.run` thì `Async.step()` là no-op, nên
morning-sync, cloud, test và mọi caller cũ giữ nguyên hành vi đồng bộ.
Yield qua `pcall` là tính năng của LuaJIT nên `withBudget`/`runWithBudget` vẫn dùng được.
**Một coroutine tại một thời điểm**: `Async.run` chỉ giữ một `running`; nếu có hành động thứ hai
bắt đầu khi hành động trước đang parked thì nó vào hàng đợi `waiting` và chỉ chạy khi coroutine kia
chết. Ghi đè `running` sẽ làm coroutine đang parked mất chỗ resume (`Async.step` so khớp danh tính)
và bỏ rơi nó vĩnh viễn — trước đây `ui/novels.lua` và `ui/comic-page.lua` là hai đường duy nhất,
giờ thêm update-check/self-test nên rủi ro chồng lấn tăng lên. `Async.waiting()` để test/đo.

**Ngân sách của bước kiểm tra cập nhật không áp cho phần tải**: `Update.CHECK_TIMEOUT = 15s` chỉ
bọc `fetchLatest` (3 lần thử + hop redirect). `Update.installAsync` cố ý **không** đặt ngân sách —
mỗi request tải vẫn 60s/180s (`Http.downloadToFile`) vì zip 30 MiB không thể xong trong vài giây;
cái làm nó không đơ UI là coroutine + sink nhường UI, không phải trần thời gian.

Áp dụng cho các đường load: danh sách/tìm kiếm/phân trang của DocLN và các nguồn chữ
(`onlineResumable` trong `ui/novels.lua`), danh sách và mục lục truyện tranh (`ui/comic-page.lua`),
**kiểm tra cập nhật lúc mở menu và khi bấm Cập nhật** (`main.lua:maybeCheckUpdate` →
`Async.run` + `Http.withBudget(Update.CHECK_TIMEOUT = 15)`), **self-test** (`main.lua:performSelfTest`,
ngân sách 10s) và **tải/cài bản cập nhật** (`Update.installAsync`). Đường **tải** (CBZ, khoảng
chương, EPUB) vẫn dùng `Trapper:wrap` đồng bộ vì cần dòng tiến trình và chạm-để-huỷ; chúng chỉ được
giới hạn bởi `BULK_TIMEOUT` và timeout từng request.

Trong `Async.run`, thân phản hồi cũng nhường UI: sink của `http.lua` gọi `Async.step()` mỗi 256 KiB,
nên một zip 30 MiB chỉ chặn main thread từng đoạn ngắn thay vì suốt cả lần stream. Đây cũng là lý do
`Update.installAsync` đặt `Update.install` trong coroutine — ngoài `Async.run` (Trapper, cloud, test)
thì `Async.step()` vẫn là no-op.

Mốc "đã kiểm tra cập nhật" (`update_last_check`) được ghi **trước** request: nếu chỉ ghi khi thành
công thì một mạng chặn GitHub sẽ khiến mỗi lần mở menu chạy lại toàn bộ lượt kiểm tra (3 request) +
thêm một thông báo.

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
- Truyện: **một HTML mỗi chương**. Range kiểm tra entry + file trước request, trả `existing` để mở/báo bỏ qua; entry mất file được tải lại. Index ghi từng chương qua file tạm, giữ `index.json.bak` hợp lệ gần nhất và chỉ fallback khi schema/id đúng. Bật `novel_epub` để tự tạo EPUB theo khoảng; tạo EPUB thành công sẽ tự động xóa HTML và ảnh sidecar. Đóng gói sau khi hủy tải (`keep_html=true` / `packagePartial`) luôn giữ lại HTML để resume.

## DocLN

`novel-export.lua` xử lý đóng gói và xóa HTML. `packageSaved` chọn HTML
theo số mục lục từ index, bỏ qua file thiếu/entry EPUB và không gọi adapter.
Khi tạo EPUB thành công, ghi tham chiếu EPUB vào index trước khi xóa HTML; lỗi xóa dừng ngay và trả
những HTML còn lại vào index. Đóng gói sau khi hủy tải (`keep_html=true` /
`packagePartial`) luôn giữ HTML để resume. ConfirmBox hủy tải hiện trước
list/toast (`cancel_callback`) để không bị fullscreen menu che. Offline deduplicate theo path; tên file chỉ nhận
`tên.ext`, từ chối `.` / `..` / `../`.
`BooxBook.purgeImageCache()` dọn dẹp ảnh bìa cache, quét toàn bộ thư mục ảnh sidecar mồ côi dưới `news/` và `novels/`, quét xóa file HTML thừa đã được đóng gói vào EPUB qua `Download.sweepOrphanHtml`, xóa thư mục rỗng trong `news/`, và quét bản nháp comic quá 7 ngày qua `Download.sweepStale(7)`.
`news-cleanup.lua` nhận CloseDocument từ plugin, đợi tick sau mới gọi native
FileManager:deleteFile. Chỉ nhận HTML dưới news sau kiểm tra realpath; yêu cầu
`news_delete_finished=true` và (`summary.status=complete` hoặc đọc đến cuối bài
với progress ≥ 0.99 / live `getLastPercent()` ≥ 99%).


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

## Nguồn truyện bổ sung từ Z-Truyenviet

17 nguồn truyện chữ và 4 nguồn truyện tranh được port từ `magicxlll/Z-Truyenviet.koplugin` (MIT).
Mỗi nguồn là một adapter `booxbook/sources/<id>.lua` cộng shim 1 dòng `ui/<id>.lua`, mục menu
trong `main.lua` và `tests/<id>.lua`; không có file UI riêng, không có nhánh `if source_id == …`.

Điểm khác thường đã gặp khi port (giữ lại trong code kèm chú thích):

- **AkayTruyen** (`akaytruyen.lua` + `akaytruyen-parser.lua`): một lần GET trang chủ phục vụ cả ba
danh sách Hot / Đang ra / Hoàn thành, cover được ghép theo URL; mục lục lấy từ endpoint
`search-chapters` (trả 422 khi `search=` rỗng nên có fallback phân trang toàn bộ) và site xếp
**mới nhất trước** nên adapter đảo về thứ tự đọc.
- **Bàn Long VIP**: API ở host khác (`api.blhvip.vn`), 50 chương/trang, thứ tự chương lấy từ
trường `ord` chứ không suy từ số trang; `/v1/story/<slug>` trả 403 nên metadata lấy từ HTML;
chương VIP phát hiện qua `content-lock` và báo khoá thay vì lưu đoạn teaser.
- **XTruyen**: nội dung chương không nằm trong HTML — trang gửi `const data_x = "…"` và trình duyệt
giải nén bằng pako. Adapter tái hiện pipeline: bảng chữ base64 tự chế → base64 chuẩn → zlib
(`ffi.loadlib("z", 1)`, cùng cách `gzip.lua` dùng).
- **Truyendich**: đã đổi tên miền hai lần (`.ai` → `.fit` → `.space`); `parseRef` nhận cả ba host
nhưng `base_url` là `truyendich.space`, và mục lục lấy từ API JSON của chính site (HTML chỉ kèm
50 chương đầu).
- **DualeoTruyenFull**: site chèn thẻ `<a>` SEO **không đóng**, làm `Html.elements` theo anchor sai;
listing được cắt theo mốc card thay vì quét anchor.
- **TruyenC**: không có tìm kiếm phía server (`capabilities.search = false`, `search()` trả câu giải
thích); 7 thể loại 18+ ẩn đến khi bật `adult_content`.
- **Mê Truyện Chữ VN**: `/danh-sach/truyen-moi` trả 404 nên `browse("latest")` fallback về trang chủ;
mục lục lấy từ `/get/listchap/<id>?page=N` (JSON escape).
- **Cbunu**: xem mục "Cbunu CBZ" ở trên.

Ba nguồn của Z-Truyenviet đã bị loại vì kiểm tra thật cho thấy không dùng được, không đưa vào menu:

- **Mizzya**: `mizzya.wordpress.com` trả 403 JS challenge cho mọi client không-JS, kể cả khi gửi
  đủ header như bản gốc.
- **Gia Tộc Vượng Tài**: cả `giatocvuongtai.com` lẫn `/api/public/*` trả 401 `"Bạn cần đăng nhập"`.
- **Hắc Ám Chi Các**: chương gửi `InitMangaEncryptedChapter` (PBKDF2-HMAC-SHA512 999 vòng +
AES-256-CBC). Z giải mã bằng `ffi.load` hàng chục tên `libcrypto.so*`, trái quy ước trong
[development.md](development.md); không có phần giải mã thì nguồn chỉ duyệt được chứ không tải
được ảnh, nên đã bỏ thay vì để một mục menu luôn báo lỗi.

## TruyenQQ CBZ

Cùng pipeline `comic-download`/`comic-cbz` như Truyện Tuổi Thơ nhưng qua adapter riêng
`truyenqqko.com`: series `/truyen-tranh/<slug>-<id>`, chapter `/truyen-tranh/<slug>-chap-<n>`.
Parser custom (không phải Madara), chỉ nhận ảnh từ `truyenqqko.com` (+ `m.`/`st.`)
và CDN `hinhhinh.com` / `truyenvua.com`; HTTP 429 báo thử lại sau, không retry dồn dập. Lưu dưới
`comics/truyenqq/<series>/<chapter>.cbz`. Giới hạn 600 trang/tập như trên.

## Cbunu CBZ

Cùng pipeline `comic-download`/`comic-cbz`. Site trả lời trên hai tên miền — `cbunu.com` và
`cucbongunu.com` — nhưng mọi liên kết, bìa và ảnh trang đều tuyệt đối trên `cucbongunu.com`,
nên đó là `base_url`; `parseSeriesRef`/`parseRef` nhận cả hai host. Series
`/truyen-tranh/<slug>-<id>`, chapter `/truyen-tranh/<slug>-<id>-chap-<n>.html` (n có thể lẻ,
ví dụ `19.5`). Mục lục nằm ngay trong `.works-chapter-list` của trang bộ, xếp mới-nhất-trước nên
adapter sắp lại theo thứ tự đọc và loại trùng theo số chương. Chỉ nhận ảnh từ chính host của site
(cả ảnh "thông báo chương" trong `.story-see-content` đều bị loại vì không có class `lazy` và
không nằm dưới `/chap/`).

Khi một trang trả 403 hoặc trang đăng nhập, adapter **giữ cơ chế unlock của nguồn gốc
Z-Truyenviet** (theo yêu cầu người dùng): POST `access_pass` với mật khẩu chung của site và
dùng lại session cookie nhận được, rồi GET lại trang. Việc này cần `Http.post(..., { max_hops = 0 })`
để không đi theo redirect và mất `Set-Cookie` trên chính phản hồi 302. Đây là ngoại lệ đã ghi nhận
với quy ước "không vượt paywall" trong [development.md](development.md); chương vẫn không đọc được
thì báo khoá chứ không làm hỏng cả khoảng tải. Cookie phiên chỉ nằm trong bộ nhớ module, TTL 30 phút.

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

## Đang đọc dở (reading history)

`reading-state.lua` ghi tiến độ vào `settings/booxbook.lua` khóa `reading_history`
(`kind:source_id:series_id` → `{status, read_percent, title, last_read_chapter,
last_read_file, last_read_time}`) và soi bản sao vào `index.json`/`manifest.json`.
`ui/reading-history.lua` (hàng đầu menu chính) đọc **chỉ** Settings qua
`ReadingState.listHistory`: sắp xếp mới-nhất-trước, cắt trần 30 mục, **không** kiểm tra
tồn tại file và **không** đọc `index.json` — menu chính không được phép sinh I/O.
`ReadingState.historyPath` dựng đường dẫn tuyệt đối từ `kind`/`source_id`/`series_id`
+ `last_read_file`, từ chối `/`, `\` và tên bắt đầu bằng `.`; việc kiểm tra file nằm ở
lúc chạm (file đã bị dọn → `Fault.notify`, không mở trình đọc).
`title` được lấy từ `index.json`/`manifest.json` **đã nằm trong bộ nhớ** của
`resolveNovel`/`resolveComic` — không thêm lượt đọc file nào; `markComplete`/`markReading`
phải giữ lại trường này nếu không muốn xoá tên vừa ghi. Entry cũ thiếu `title` → hiện
`series_id`; thiếu mốc thời gian → xuống cuối danh sách (không được gán `now()`).
`saveSettingsProgress` cắt lịch sử **khi ghi** (`MAX_STORED = 200`, bỏ entry cũ nhất) vì
khóa là bộ truyện nên bảng lớn lên theo số bộ đã từng mở; entry bị bỏ tự quay lại từ bản
sao trong `index.json`/`manifest.json` ở lần đọc sau. Trần hiển thị (`MAX_HISTORY = 30`) và
trần lưu là hai con số tách nhau có chủ ý.
Test: `tests/reading-state.lua` (fixture `index.json` trong bộ nhớ vì `mkdir` không có
trong LuaJIT thuần) và `tests/reading-history-ui.lua`.

## Tự động hóa & Tính năng nâng cao (0.0.12)

- **Morning Sync** (`morning-sync.lua`): Tự động kiểm tra chương mới và tạo digest ngày mới vào mỗi buổi sáng. Chạy thụ động qua `Network.ifOnline` (không bao giờ hiện hộp thoại bật Wi-Fi); chia tick qua `UIManager:nextTick` và bọc tác vụ mạng bằng `Trapper:wrap`. Dùng rotating cursor tránh bỏ sót các truyện theo dõi phía sau và con trỏ `(mtime, path)` bảo đảm không bỏ sót bài báo nào.
- **OPML RSS** (`opml.lua`): Phân tích XML OPML 2.0 dạng phẳng/lồng nhau, trích xuất `xmlUrl`, giải mã entities và tạo file xuất chuẩn. Tích hợp menu nhập/xuất trong Báo.
- **Lịch sử & Tiến độ đọc** (`reading-state.lua`): Lưu trữ bền vững hai lớp (lớp 1 trong `Settings` theo key `<kind>:<source>:<id>`, lớp 2 phản chiếu vào `index.json` và `manifest.json`). `comic-download.lua` bảo toàn trạng thái đọc khi làm mới mục lục. Thư viện hiển thị nhãn `[Đang đọc %]` và `[Đã xong]`.
- **Tìm kiếm toàn văn** (`fulltext-search.lua`): Quét nội dung HTML/txt cục bộ, áp dụng accent-folding tiếng Việt, giới hạn trần bộ nhớ/kết quả (mặc định tối đa 30 kết quả, đọc 256KB/file), trích xuất snippet nổi bật hiển thị trên UI thư viện.
- **Hạn ngạch & Dọn dẹp** (`storage.lua`): Quản lý quota độc lập từng danh mục (`news`: 300MB, `received`: 500MB, `novels`/`comics`: mặc định không giới hạn). Tự động dọn FIFO cho báo/file nhận khi vượt trần nhưng bảo vệ truyện trừ khi bật opt-in. Quét sạch digest > 30 ngày và `.part` mồ côi > 24 giờ.
- **Cloud Upload** (`onedrive.lua`, `gdrive.lua`, `http.lua`): Bổ sung `Http.put` và multipart POST. Upload thủ công bản sao lưu cài đặt và danh sách theo dõi lên OneDrive và Google Drive. Nhận diện token cũ thiếu quyền và nhắc nhở đăng nhập lại.
- **OPDS Toàn thư viện** (`opds.lua`, `wifi-upload.lua`): Mở rộng máy chủ Wi-Fi cấp danh mục Atom OPDS 1.2 cho toàn bộ thư viện sách với MIME type chuẩn (`.epub`, `.cbz`, `.html`, `.pdf`). `/opds` và `/opds/file/…` yêu cầu mã phiên (header `X-BooxBook-Token` hoặc `?token=`), link trong catalog tự kèm mã. `Upload.safeRelativePath` chặn triệt để tấn công directory traversal; nâng trần stream file lên 512MB.

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

## DTV eBook (kind `ebook`)

Nguồn đầu tiên không có chương: `dtv-ebook.com.vn` chỉ cho **tải file** (EPUB/PDF/AZW3/MOBI qua
Google Drive), không đọc online. Port từ plugin `DTVEbook` của `Yuneko-dev/Nekori-plugins`; khác bản
gốc ở chỗ file được lưu thẳng vào máy rồi mở bằng ReaderUI, thay vì một "chương" chứa nút tải.

- `sources/dtvebook.lua` (`kind = "ebook"`): `browse` (`/<thể-loại-id>/<trang>.html`, 48 sách/trang,
  `has_more` theo mũi tên `&raquo;` của phân trang), `search` (`/tim-kiem.html?keyword=…&type=&page=`),
  `getSeries` → `{ title, author, tags, status, description, cover, files = {{format, id, url}} }`.
  Site chỉ khớp từ khoá **không dấu** nên `stripDiacritics` bỏ dấu (kể cả `đ`) trước khi gửi. Mỗi sách
  render hai lần (khối desktop + mobile) trong cùng `<li class="itemtruyen">`; ảnh bìa có thể lặp tiền
  tố domain (`https://x/https://x/a.jpg`) nên lấy từ lần `http` cuối. Trang không có link Drive
  (bài review) trả lỗi "không có link tải" thay vì màn hình rỗng.
- `ui/source-page.lua` dùng lại nguyên cho danh mục/tìm kiếm; `Novels.showSeries` chuyển sang
  `ui/ebook-detail.lua` khi `adapter.kind == "ebook"`: dòng **Giới thiệu** (tác giả, tình trạng, thể
  loại, mô tả) và một dòng mỗi định dạng (EPUB, AZW3, MOBI, PDF — định dạng reflow lên trước). Chạm
  → tải → hỏi **Mở sách ngay?**; định dạng đã tải thì mở luôn. Chạy trong `Async.run` để tải vài chục
  MiB không treo luồng UI.
- `ebook-download.lua`: lưu `<download_dir>/books/dtvebook/<Tiêu đề> [<id>].<đuôi>` qua `.part` rồi
  rename. Link `docs.google.com/uc?export=download&id=…` chuyển hướng 303 sang
  `drive.usercontent.google.com`; file lớn (đã thử PDF 98 MB) được Drive trả **trang HTML "Virus scan
  warning"** thay cho file. Module nhận ra trang đó (sniff byte đầu: `PK` epub, `%PDF`, `BOOKMOBI` ở
  offset 60 mobi/azw3, `<html` là trang), đọc `#download-form` (`id`, `export`, `confirm`, `uuid`) và gọi
  lại đúng URL của nút "Download anyway", tối đa 2 lần. Mọi bước chuyển hướng/form chỉ được tới host
  Google (`allow_url`); file không phải sách bị xoá; trần 200 MiB; hạn mức Drive ("Too many users…")
  báo bằng câu rõ ràng, không thử lại vòng. Đuôi file theo nội dung thực, không theo nhãn nút; AZW3 lưu
  đuôi `.azw` vì KOReader không liệt kê/mở `.azw3`. Không gửi `Referer` của site cho Google: với referer
  đó Drive trả lại trang xác nhận mãi. Bước xác nhận mất khoảng 30 giây mới có byte đầu tiên (Drive chuẩn bị file).
- Chưa làm (YAGNI): tiến trình theo phần trăm, tải tiếp khi đứt, sách nhiều tập, theo dõi sách.
- Đã kiểm với site thật (18/10/2026): danh mục, tìm kiếm, trang chi tiết, EPUB 10 MB, trang virus-scan
  và PDF 98 MB tải đủ byte. Đã chạy thật trên KOReader Android (Samsung SM-S721B): danh mục, thể loại,
  phân trang, tìm kiếm, tải EPUB/PDF/MOBI/AZW và PDF 98 MB qua trang xác nhận. Chưa chạy trên thiết bị
  Boox/Kindle/Kobo.
