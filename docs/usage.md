# Hướng dẫn sử dụng

Màn hình chính hiện phiên bản ngay dưới tiêu đề. Điều hướng dùng **Quay lại / Trước / Sau** ở chân trang.

## Gửi sách qua Wi-Fi

1. Kết nối máy đọc sách và điện thoại/máy tính vào cùng mạng Wi-Fi.
2. Trong **BooxBook → Gửi sách qua Wi-Fi**, giữ màn hình nhận sách mở.
3. Điện thoại: chọn **Quét QR để gửi từ điện thoại**, quét bằng camera để mở web
   với mã phiên điền sẵn. Máy tính: gõ địa chỉ `http://…:8080/` đang hiển thị
   vào trình duyệt, rồi nhập mã phiên 6 chữ số trên máy đọc sách (giữ số 0 đầu).
4. Chọn một hoặc nhiều sách, bấm **Gửi sách**. Xem tiến độ và kết quả từng file.
5. Bấm **Dừng nhận sách**, rồi mở **Thư viện → received** để đọc.

Hỗ trợ EPUB, PDF, CBZ, CBR, FB2, MOBI, AZW/AZW3, DJVU/DJV, TXT, RTF, DOC, CHM;
khả năng đọc từng định dạng phụ thuộc KOReader. Mỗi file từ 1 byte đến 512 MiB.
File trùng tên bị từ chối; đổi tên trên thiết bị gửi rồi gửi lại. Không ghi đè sách cũ.
File gửi dở bị xóa khi ngắt kết nối, hết thời gian hoặc dừng phiên; gửi lại từ đầu.

Không cần Internet hay tài khoản. Chỉ dùng trong mạng tin cậy vì kết nối là HTTP.
Một thiết bị nhập sai mã 5 lần sẽ bị khóa tới khi mở lại phiên; thiết bị khác
trong cùng mạng vẫn gửi được.
Đóng màn hình nhận sách, tắt KOReader, mất mạng hoặc cho máy ngủ sẽ dừng phiên;
mở lại sẽ có mã phiên mới. Khi gửi sách lớn, tránh để máy tự ngủ.
Không vào được web: kiểm tra cùng Wi-Fi, tránh mạng khách/chặn thiết bị nội bộ,
tắt VPN nếu địa chỉ hiển thị thuộc VPN. Nếu cổng 8080 bận, dừng HTTP Inspector
hoặc ứng dụng đang dùng cổng đó rồi mở lại. Chưa xác nhận trên Boox/Kindle/Kobo thật.

Sau khi mỗi file được ghi hoàn tất, KOReader hiện thông báo **Đã nhận sách** kèm
tên file trong 3 giây. Không báo thành công cho file dở hoặc file bị từ chối.

## Báo RSS

- **Báo → Báo Việt / Báo Nước Ngoài → chọn đầu báo → chọn danh mục**: chỉ lấy danh sách tiêu đề RSS khi chọn danh mục, chưa tải nội dung các bài.
- 17 đầu báo, 633 kênh RSS có bài trong lượt kiểm tra ngày 04/09/2026. Xem [phạm vi và nguồn danh mục](news-categories.md).
- Đã bỏ **Nguồn tin** và toàn bộ công tắc bật/tắt. Thiết lập tắt nguồn từ bản cũ không còn ẩn danh mục.
- **Chạm tiêu đề bài**: lấy nội dung bài đó và mở bằng KOReader; nếu lấy toàn bài lỗi, dùng bản tóm tắt RSS/Atom.
- Trang chi tiết có tiêu đề ở đầu bài; ảnh trong nội dung/tóm tắt được lưu cục bộ chỉ khi mở bài. Ảnh lỗi không chặn đọc chữ. Hỗ trợ JPEG, PNG, GIF, WebP; tối đa 20 ảnh, 2 MiB/ảnh, 10 MiB/bài.
- **Báo → Số bài mỗi danh mục**: chọn từ 1 đến 20 tiêu đề hiển thị; không giới hạn số danh mục.
- **Báo → Tin đã tải**: đọc lại các bài đã mở/lưu, không cần tải lại. Bài cũ vẫn được giữ.
- **Báo → Thêm RSS tùy chỉnh**: thêm URL bắt đầu bằng `http://` hoặc `https://`.
- RSS bạn thêm nằm trong nhóm riêng **Báo → RSS tùy chỉnh**. Kênh rỗng/lỗi chỉ báo thông báo; không làm mất danh sách danh mục.
- Dùng User-Agent desktop; riêng VnExpress có cookie chọn giao diện desktop để tránh RSS rỗng. Vẫn giãn cách lượt tải và dừng khi máy chủ trả HTTP 429; không cam kết loại bỏ mọi rate limit.
- Chỉ bài được chọn mới lưu HTML tại `koreader/booxbook/news/<feed-id>/`. Mở từ danh sách online sẽ lấy lại nội dung bài đó.
- RSS tùy chỉnh chỉ đọc nội dung/tóm tắt trong feed, không tự lấy toàn văn website.

## DocLN

- **Truyện → DocLN**: nhập từ khóa; chọn truyện để xem các tập và chương. Có **Trang tiếp** khi còn kết quả.
- **Tải chương** (icon menu góc trái thanh tiêu đề mục lục): **Tải khoảng chương** (nhập từ–đến), **Tải toàn bộ chương** hoặc **Tạo EPUB từ chương đã tải**. **Chương đã tải (offline)** nằm trong danh sách mục lục: mở file đã lưu từ `index.json`, không cần mạng. Chạm một chương để tải hoặc mở ngay bản đã có.
- Mỗi lượt mặc định gợi ý tối đa 20 chương; hơn 50 chương cần xác nhận. Tải tuần tự, cách nhau ít nhất 1,5 giây; HTTP 429 dừng lượt tải.
- Lưu HTML từng chương và `index.json` tại `koreader/booxbook/novels/docln/<loại-truyện-id>/`. Tải lại khoảng tự bỏ qua chương còn file; mục index có file đã mất được tải lại. `index.json.bak` giữ bản hợp lệ gần nhất để fallback nếu index chính hỏng. Tên file dùng ID chương ổn định.
- Tự chuyển giữa `docln.net`, `ln.hako.vn`, `docln.sbs` khi lỗi mạng/trang; nhớ tên miền hoạt động. Dùng **Cookie DocLN** đã có trong Cài đặt nếu cần.
- Ẩn kết quả được đánh dấu 18+ khi thiết lập tắt; kiểm tra lại trên trang truyện. Chương khóa/404/không có chữ hiển thị lý do bỏ qua; lỗi mạng hoặc ghi file giữ lại các chương đã lưu.
- Hỗ trợ nội dung công khai được đóng gói trong HTML theo cách của [Nekori LNHako](https://github.com/Yuneko-dev/Nekori-plugins/tree/c29b05de71bf71e5321d6488014d027d7b2f68cb/plugins/vietnamese/LNHako). [Thông báo MIT](../booxbook.koplugin/THIRD-PARTY-NOTICES.md). EPUB tùy chọn trong Cài đặt; tải ảnh chương để bước sau.

## Wattpad

- Danh sách duyệt và kết quả tìm kiếm hiển thị grid 2×3 bìa/tên truyện như DocLN. Nút Trước/Sau chuyển màn hình rồi lấy trang API tiếp theo; bìa chỉ tải khi xuất hiện trên màn hình, lỗi ảnh vẫn đọc được tên truyện.
- **Truyện → Wattpad**: duyệt Nổi bật / Đề cử / Mới (tiếng Việt). Chạm kính lúp trên thanh tiêu đề để tìm kiếm hoặc nhập URL `/story/<id>`; nút này cũng có ở danh sách kết quả, giống DocLN. Khi API danh sách lỗi vẫn có thể nhập URL; Đề cử có thể rỗng.
- Mục lục dùng chung DocLN: icon menu góc trái → khoảng / toàn bộ; **Chương đã tải (offline)** trong danh sách. Lưu HTML + `index.json` tại `koreader/booxbook/novels/wattpad/<id>/`.
- Dùng **Cookie Wattpad** đã lưu; không đăng nhập bằng mật khẩu hay mở khóa chương trả phí. Ẩn truyện 18+ hoặc chưa rõ phân loại khi thiết lập 18+ tắt. Bỏ qua bản nháp, chương xóa/khóa/trống; HTTP 403/429 dừng lượt tải.
- Giãn cách ít nhất 1,6 giây; tự giải nén gzip bằng zlib của KOReader. Chỉ lưu chữ; EPUB tùy chọn trong Cài đặt, ảnh để bước sau.

## MeTruyenCV

- **Truyện → MeTruyenCV**: Mới cập nhật / Lượt xem, grid bìa 2×3; kính lúp để tìm tên truyện hoặc nhập ID số / URL `https://metruyencv.com/truyen/<id>`.
- URL dạng tên (slug) chưa hỗ trợ; tìm theo tên truyện để chọn kết quả tương ứng.
- Mục lục và tải khoảng/toàn bộ dùng chung các nguồn khác. Lưu HTML, `index.json` và EPUB tùy chọn tại `koreader/booxbook/novels/metruyencv/<id>/`.
- Giãn cách tối thiểu 1,6 giây. Bỏ qua chương được đánh dấu khóa/VIP hoặc không có nội dung; lỗi HTTP 403/429 hoặc giải mã dừng lượt tải và giữ file đã lưu.
- Không cần cookie. Dùng thư viện OpenSSL có sẵn trong KOReader; đồng hồ thiết bị cần đúng để ký request API. API tham khảo không cung cấp phân loại 18+, nên nguồn này chưa lọc theo độ tuổi.

## Sangtacviet

- **Truyện → Sangtacviet** luôn hiện trong menu. Lần đầu chạm sẽ hỏi xác nhận (cảnh báo dịch máy); sau đó mở grid. Tắt lại bằng **Cài đặt → Bật Sangtacviet**.
- Duyệt **Mới cập nhật** / **Lượt xem** dạng grid bìa; kính lúp nhận từ khóa hoặc URL `/truyen/{host}/{sty}/{bookid}/`.
- Tải chương qua AJAX (`sajax=readchapter`) kèm Referer + cookie phiên; giãn cách ≥ 2 giây. Bỏ qua VIP; captcha / rate-limit / chương trống sau lỗi dừng cả lượt tải.
- ID truyện là `{host}-{bookid}` (cùng bookid có thể trùng giữa nguồn gốc). Lưu HTML tại `koreader/booxbook/novels/sangtacviet/{host}-{bookid}/`. Chương id dài (fanqie) giữ dạng chuỗi, không `tonumber`. Icon menu trên mục lục mở **Tải khoảng / toàn bộ** như DocLN; tải toàn bộ có thể chậm vì giãn cách ≥ 2 giây và dừng khi captcha/rate-limit.
- Chỉ dùng cá nhân; nhiều bản dịch máy. Không vượt captcha/VIP. Bảng glyph PUA (sangtac/dich) theo [Nekori SangTacViet](https://github.com/Yuneko-dev/Nekori-plugins/tree/master/plugins/vietnamese/SangTacViet) — [MIT](../booxbook.koplugin/THIRD-PARTY-NOTICES.md).

## EPUB và Thư viện

EPUB mới giữ tên truyện gốc và metadata nguồn có cung cấp (tác giả, mô tả,
thể loại/thẻ, URL nguồn). Ảnh bìa JPEG/PNG/GIF tối đa 2 MiB được nhúng vào file,
có trang bìa để xem offline. Nguồn không có bìa thì không tạo bìa giả; tải bìa
lỗi hoặc định dạng chưa hỗ trợ thì giữ HTML và báo lỗi. EPUB đã tải trước đây
cần tải lại để nhận metadata và bìa mới.

- Bật **Cài đặt → Lưu truyện thành EPUB**. Mặc định vẫn là HTML.
- Không cần bật công tắc để đóng gói thủ công: trong menu mục lục chọn **Tạo EPUB từ chương đã tải**, nhập khoảng. Plugin chỉ dùng HTML đang có, báo số chương thiếu và luôn giữ HTML/index.
- Áp dụng DocLN, Wattpad, Sangtacviet, MeTruyenCV, TVTruyen và Truyện Full: mỗi khoảng tải xong có file
  `chapters-<từ>-<đến>.epub` trong thư mục truyện, chứa các chương tải được theo
  thứ tự và mục lục. Tải toàn bộ tạo một EPUB cho khoảng đó. Chương khóa bị bỏ qua.
- Chọn dòng **(EPUB)** ở đầu kết quả để đọc. **Giữ bản HTML khi lưu EPUB** bật
  mặc định: mục **Chương đã tải (offline)** tiếp tục mở từng HTML. Tắt công tắc
  này để xóa HTML của lượt tải sau khi EPUB và `index.json` đã ghi thành công;
  danh sách offline khi đó mở EPUB, mỗi file chỉ hiện một lần. Công tắc chỉ áp
  dụng khi EPUB bật; không quét xóa các HTML đã tải từ trước.
- Nếu lượt tải bị gián đoạn, chưa tạo EPUB; các HTML đã ghi vẫn dùng được. Nếu
  xuất EPUB lỗi, thông báo lỗi và giữ HTML cùng EPUB cũ. Tải lại cùng khoảng thành
  công sẽ thay EPUB của khoảng đó; các khoảng khác có file riêng.
- **Thư viện** ở màn hình chính mở thư mục `koreader/booxbook/` bằng trình quản lý
  file KOReader, không cần mạng. Vào `news/` để tìm báo, `novels/<nguồn>/<id>/`
  để tìm truyện. Danh sách phản ánh file thực trên máy, kể cả tải từ trước.
- Chạm file để đọc; nhấn giữ để đổi tên, xóa, sao chép, di chuyển, xem thông tin,
  thêm bộ sưu tập hoặc đổi trạng thái đọc theo KOReader. Khi mở từ sách đang đọc,
  KOReader đóng sách và lưu trạng thái trước khi chuyển sang Thư viện.
- Đổi tên/di chuyển/xóa HTML bằng KOReader không sửa `index.json` của truyện;
  khi đó mở file ở vị trí mới qua Thư viện thay vì danh sách chương offline cũ.

## Tự xóa báo đã đọc

- Bật **Cài đặt → Tự xóa HTML báo sau khi đọc xong** (mặc định tắt).
- Khi đóng bài: xóa nếu đã đánh dấu **Đã đọc**, hoặc nếu vừa tới cuối bài
  và vẫn đang ở cuối (không xóa nếu lật tới cuối rồi chọn về đầu / đọc tiếp).
- Áp dụng cả khi mở bài từ Báo, Tin đã tải hoặc Thư viện. Chỉ xóa HTML trong
  `booxbook/news/<nguồn>/`, không xóa truyện hay file ngoài thư mục này.
- KOReader cập nhật lịch sử, bộ sưu tập và metadata khi xóa. Ảnh tải kèm vẫn giữ.
- Không quét xóa báo cũ hàng loạt. Có thể tải lại bài từ danh sách online.

## Truyện Tuổi Thơ — CBZ

1. Vào **Truyện → Truyện Tuổi Thơ**. Chọn **Mới cập nhật**, **Lượt xem**, **Truyện mới** hoặc **Thịnh hành** để duyệt grid bìa, lật trang bằng mũi tên.
2. **Tìm truyện / nhập URL** nhận tên truyện, URL bộ hoặc URL một tập, ví dụ `https://truyentuoitho.com/manga/tieu-hoa-thuong/tap-28/`.
3. Chọn bộ để xem thông tin và **Danh sách tập**. Chọn tập hoặc **Mở tập bất kỳ** (số thứ tự mục lục) để tải/mở CBZ.
4. Icon menu bên trái mục lục có **Tải khoảng tập**, **Tải toàn bộ tập**. Mỗi tập là một CBZ riêng. Xác nhận số tập trước khi tải nhiều tập.
5. **Truyện đã tải (offline)** mở thư mục CBZ ngay cả khi mất mạng. Trong mục lục đã mở, **Tập đã tải (offline)** liệt kê tập có sẵn của bộ đó.

Lần đầu mở mỗi CBZ của nguồn này (kể cả tập tải trước bản sửa), plugin chọn
**hiển thị từng trang + vừa toàn trang** để một trang truyện không bị chia qua
nhiều lần lật màn hình. Bạn vẫn có thể đổi zoom/chế độ cuộn sau đó; plugin chỉ
đặt mặc định một lần, không đổi thiết lập toàn cục.

Chạm thông báo tiến độ để tạm dừng, rồi chọn hủy hoặc tiếp tục. Hủy có hiệu lực
giữa các lượt tải ảnh/đóng gói; một request đang chạy có thể mất tới 60 giây.
Chọn lại tập hoặc khoảng tập để tải tiếp các trang còn thiếu; tập đã xong không tải lại. CBZ có sẵn được kiểm tra và
mở lại; đọc offline qua **Thư viện → comics → truyentuoitho → tên bộ → tập.cbz**.

Chỉ nhận URL bộ/tập HTTPS trên `truyentuoitho.com` / `truyentuoitho.online`.
Lỗi/hủy dừng khoảng tải và giữ các tập đã hoàn tất. Không dùng liên kết tải kho
Google Drive trả phí. Ảnh chỉ từ hai domain nguồn và `img.resourcehub.shop`.
Giới hạn 600 trang/tập, 8 MiB/ảnh, 512 MiB/tập; cần chỗ trống cho cả ảnh tạm và
CBZ (khoảng hai lần dung lượng ảnh). Ảnh tạm nằm trong thư mục ẩn `.<tập>-pages`,
chỉ dọn các trang dùng trong CBZ sau khi thành công. Đổi nguồn ảnh có thể cần tải lại.
Không phụ thuộc công tắc ảnh minh họa hay EPUB của truyện chữ.
Chưa xác minh giao diện và CBZ WebP trên Boox thật.

## Dữ liệu trên máy

| Loại | Đường dẫn |
|---|---|
| Bài báo đã mở | `koreader/booxbook/news/<feed-id>/` |
| Chương truyện | `koreader/booxbook/novels/<nguồn>/<id>/` |
| Tập truyện tranh CBZ | `koreader/booxbook/comics/truyentuoitho/<bộ>/<tập>.cbz` |
| Cài đặt + cookie | `koreader/settings/booxbook.lua` |

## TVTruyen

**Truyện → TVTruyen**: danh sách mới / lượt xem, tìm tên hoặc nhập URL
`https://www.tvtruyen.live/ten-truyen.html`. Đọc HTML trực tiếp; không cần mã hóa,
JavaScript hoặc cookie. Mục lục tải lần lượt các trang nên truyện dài có thể chờ
vài phút. Tải khoảng/toàn bộ, HTML/EPUB và offline dùng cùng menu các nguồn khác.
Lưu dưới `novels/tvtruyen/<ten-truyen>/`. Chương khóa/trống bỏ qua; lỗi mạng dừng.
và giữ file đã tải. Nguồn này chưa có bộ lọc độ tuổi. Bìa WebP chỉ hiện ở grid; EPUB bỏ bìa WebP vì bộ ghi hiện tại chỉ nhận JPEG/PNG/GIF.

## Truyện Full

**Truyện → Truyện Full**: danh sách mới / lượt xem, tìm tên hoặc nhập URL
`https://truyenfull.live/ten-truyen/`. Đọc HTML trực tiếp (`#chapter-c`); không
cần mã hóa hay cookie. Mục lục lấy từng trang `/trang-N/` (khoảng 50 chương/trang)
nên truyện dài có thể chờ vài phút. Tải khoảng/toàn bộ, HTML/EPUB và offline
dùng cùng menu các nguồn khác. Lưu dưới `novels/truyenfull/<ten-truyen>/`.
Chương trống hoặc khóa bỏ qua; lỗi mạng dừng và giữ file đã tải. Nguồn này
chưa có bộ lọc độ tuổi.

## Mở nhanh một chương

Trong mục lục truyện, chọn **Mở chương bất kỳ**, nhập số thứ tự 1…N đang hiển thị
bên cạnh chương. Plugin tải riêng chương đó và mở ngay HTML hoặc EPUB theo cài đặt.
Áp dụng cả sáu nguồn, thứ tự tính xuyên các tập. Đây là số thứ tự mục lục, không
phải ID hoặc số nằm trong tiêu đề (các số này có thể bị khuyết/lặp).
Chương khóa hoặc tải lỗi hiện lý do; không tự mở file lỗi.
