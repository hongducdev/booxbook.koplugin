# BooxBook

[![GitHub Stars](https://img.shields.io/github/stars/hongducdev/booxbook.koplugin?style=flat-square&logo=github)](https://github.com/hongducdev/booxbook.koplugin/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/hongducdev/booxbook.koplugin?style=flat-square&logo=github)](https://github.com/hongducdev/booxbook.koplugin/forks)
[![License](https://img.shields.io/github/license/hongducdev/booxbook.koplugin?style=flat-square)](./LICENSE)
[![Release Downloads](https://img.shields.io/github/downloads/hongducdev/booxbook.koplugin/total?style=flat-square&logo=github)](https://github.com/hongducdev/booxbook.koplugin/releases)

Plugin [KOReader](https://github.com/koreader/koreader) để đọc báo RSS và truyện chữ trên máy đọc sách (Onyx Boox và thiết bị khác). Tải HTML về máy, đọc offline trong KOReader.

**Phiên bản:** 0.0.9 (`hongducdev/booxbook.koplugin`) · giấy phép [AGPL-3.0-or-later](./LICENSE)

**Website giới thiệu + hướng dẫn:** xem [`website/`](website/) (deploy tự động lên GitHub Pages qua workflow `pages.yml`). Số version và link Release trên web tự đồng bộ từ `version` trong `booxbook.koplugin/_meta.lua` lúc deploy — không sửa tay. Preview local: `pwsh -File scripts/preview-website.ps1`.

Dùng như trình đọc RSS / thư viện cá nhân. Không phát tán nội dung đã tải. Không vượt VIP, paywall hay captcha.

## Website có gì

- Giới thiệu tính năng: báo RSS 17 tờ / 633 kênh, truyện chữ 6 nguồn, truyện tranh CBZ, EPUB + thư viện, gửi sách qua Wi-Fi.
- Hướng dẫn cài 5 bước từ file Release (có ảnh minh họa từng bước), cập nhật từ Release, kiểm tra cài đặt.
- Hướng dẫn dùng theo tab: Báo / Truyện chữ / Truyện tranh / EPUB & Thư viện / Wi-Fi; bảng danh mục báo; đường dẫn dữ liệu; FAQ.
- Nguồn: [`website/`](website/) tĩnh (HTML/CSS/JS, không build). Sửa nội dung ở `website/index.html`, style ở `website/styles.css`.

## Tính năng

| Mục | Nguồn | Ghi chú |
|---|---|---|
| **Báo** | 17 tờ, 633 kênh RSS | 9 báo Việt, 8 nguồn nước ngoài; thêm RSS tùy chỉnh |
| **Truyện** | DocLN, Wattpad, Sangtacviet, MeTruyenCV, TVTruyen, Truyện Full | Tìm / duyệt, tải chương, đọc lại offline |
| **Truyện tranh** | Truyện Tuổi Thơ | Duyệt/tìm, mục lục, tải một/khoảng/toàn bộ tập, tải tiếp, đọc CBZ offline |
| **Thư viện** | File đã tải | Mở thư mục tải bằng trình quản lý file KOReader; nhấn giữ để thao tác |
| **Gửi sách qua Wi-Fi** | Điện thoại / máy tính cùng mạng | Mở web hoặc quét QR, gửi nhiều sách vào thư viện; tối đa 512 MiB/file |

Cách dùng chi tiết: [hướng dẫn](docs/usage.md). Phạm vi RSS: [danh mục báo](docs/news-categories.md).

## Cài trong KOReader

Tải file từ trang Release, không copy code lẻ từ GitHub:

1. Mở [Release mới nhất](https://github.com/hongducdev/booxbook.koplugin/releases/latest), kéo tới **Assets**, tải `booxbook.koplugin.zip`.
2. Giải nén zip được thư mục `booxbook.koplugin`. Copy nguyên thư mục vào thư mục `plugins` của KOReader (trên Android thường là `/sdcard/koreader/plugins/booxbook.koplugin/`). Trong đó phải có `main.lua`, `_meta.lua` và thư mục `booxbook/`.
3. Restart KOReader (tắt hẳn rồi mở lại).
4. Bật plugin: **Tools → More tools → Plugin management → BooxBook**.
5. Mở: **Tools → BooxBook**. Hiện phiên bản dưới tiêu đề là thành công.

Minh họa từng bước: [website #cai-dat](./website/index.html#cai-dat) (timeline số dọc).

Cập nhật: mỗi bản mới đều có `booxbook.koplugin.zip` ở [Release](https://github.com/hongducdev/booxbook.koplugin/releases) — tải zip mới đè vào thư mục cũ, chọn **Cập nhật** ở thanh dưới trang chủ, hoặc vào **Cài đặt → Hệ thống → Cập nhật từ GitHub** (cần Wi-Fi). Dữ liệu trong `koreader/booxbook/` và cookie không bị xóa. Restart KOReader sau khi cài.

## Cài đặt trong plugin

- Cookie từng nguồn: dán session từ trình duyệt. Cookie không được in ra log.
- Sangtacviet tắt mặc định; lần đầu mở sẽ hỏi xác nhận. Có thể tắt lại trong **Cài đặt → Nguồn và cookie**.
- Nội dung 18+: tắt mặc định. **Tải ảnh minh họa**: bật mặc định.
- **Lưu truyện thành EPUB**: tắt mặc định. Mỗi khoảng chương tải xong có EPUB với mục lục; áp dụng cả sáu nguồn.
- Tải lại một khoảng tự bỏ qua chương còn file trên máy. `index.json.bak` giữ danh sách hợp lệ gần nhất để fallback khi index chính hỏng.
- Trong menu tải của mục lục, **Tạo EPUB từ chương đã tải** đóng gói khoảng HTML đã có mà không tải lại nội dung; HTML luôn được giữ.
- EPUB giữ tên truyện gốc, tác giả, mô tả/thẻ nếu nguồn cung cấp, liên kết nguồn và ảnh bìa nhúng offline. Không dùng BooxBook làm tác giả.
- **Giữ bản HTML khi lưu EPUB**: bật mặc định. Tắt để chỉ giữ EPUB sau khi xuất và cập nhật danh sách thành công; lỗi vẫn giữ HTML để phục hồi.
- **Tự xóa HTML báo sau khi đọc xong**: tắt mặc định. Xóa khi đóng bài đã đánh dấu đã đọc, hoặc vừa tới cuối và vẫn ở cuối; quay lại giữa bài thì giữ. Thư mục ảnh `.images` của bài bị xóa cùng HTML (chỉ khi xóa HTML thành công); tải lại bài làm mới sạch ảnh cũ sau khi ghi HTML xong.
- **Ảnh bìa**: lưu dưới `koreader/booxbook/covers/`, trần 50MB (xóa bìa cũ nhất trước). Cài đặt hiện dung lượng ảnh và có mục **Dọn ảnh bìa và ảnh thừa** (xóa bìa, ảnh của bài đã mất, bản nháp comic quá 7 ngày).
- **Kiểm tra cài đặt** (cần Wi-Fi): gọi `example.com`, ghi `_selftest.html` (có chữ `Tiếng Việt`) và thử EPUB vào `koreader/booxbook/`.

## Phát triển

LuaJIT, không thêm native library. Xem [quy ước](docs/development.md) và [kiến trúc](docs/system-architecture.md).

```sh
luajit tests/run.lua
```

Rà RSS thật (cần mạng, mất vài phút): `pwsh -File scripts/news-feeds-live.ps1 -All`.

## Cấu trúc repo

```
booxbook.koplugin/   plugin KOReader — copy nguyên thư mục này lên máy
docs/                hướng dẫn dùng, danh mục RSS, kiến trúc
scripts/             kiểm tra RSS trên mạng
tests/               unit test LuaJIT (không cần KOReader)
website/             site tĩnh giới thiệu + hướng dẫn (deploy GitHub Pages)
```

Ghi chú bên thứ ba (MIT, Nekori): [THIRD-PARTY-NOTICES.md](booxbook.koplugin/THIRD-PARTY-NOTICES.md).
