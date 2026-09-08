# BooxBook

Plugin [KOReader](https://github.com/koreader/koreader) để đọc báo RSS và truyện chữ trên máy đọc sách (Onyx Boox và thiết bị khác). Tải HTML về máy, đọc offline trong KOReader.

**Phiên bản:** 0.0.5 (`hongducdev/booxbook.koplugin`) · giấy phép [AGPL-3.0-or-later](./LICENSE)

Dùng như trình đọc RSS / thư viện cá nhân. Không phát tán nội dung đã tải. Không vượt VIP, paywall hay captcha.

## Tính năng

| Mục | Nguồn | Ghi chú |
|---|---|---|
| **Báo** | 17 tờ, 633 kênh RSS | 9 báo Việt, 8 nguồn nước ngoài; thêm RSS tùy chỉnh |
| **Truyện** | DocLN, Wattpad, Sangtacviet, MeTruyenCV, TVTruyen, Truyện Full | Tìm / duyệt, tải chương, đọc lại offline |
| **Truyện tranh** | Truyện Tuổi Thơ | Duyệt/tìm, mục lục, tải một/khoảng/toàn bộ tập, tải tiếp, đọc CBZ offline |
| **Thư viện** | File đã tải | Mở thư mục tải bằng trình quản lý file KOReader; nhấn giữ để thao tác |

Cách dùng chi tiết: [hướng dẫn](docs/usage.md). Phạm vi RSS: [danh mục báo](docs/news-categories.md).

## Cài trên Boox (Android)

1. Copy thư mục `booxbook.koplugin` vào `/sdcard/koreader/plugins/booxbook.koplugin/`. Trong đó phải có `main.lua`, `_meta.lua` và thư mục `booxbook/`.
2. Restart KOReader.
3. Bật plugin: **Tools → More tools → Plugin management → BooxBook**.
4. Mở: **Tools → BooxBook**.

Cập nhật khi có [Release](https://github.com/hongducdev/booxbook.koplugin/releases) kèm `booxbook.koplugin.zip`: icon thông tin trên màn hình chính, mục **Cập nhật**, hoặc **Cài đặt → Cập nhật từ GitHub** (cần Wi-Fi). Dữ liệu trong `koreader/booxbook/` và cookie không bị xóa. Restart KOReader sau khi cài.

## Cài đặt trong plugin

- Cookie từng nguồn: dán session từ trình duyệt. Cookie không được in ra log.
- Sangtacviet tắt mặc định; lần đầu mở sẽ hỏi xác nhận. Có thể tắt lại trong Cài đặt.
- Nội dung 18+: tắt mặc định. **Tải ảnh minh họa**: bật mặc định.
- **Lưu truyện thành EPUB**: tắt mặc định. Mỗi khoảng chương tải xong có EPUB với mục lục; áp dụng cả sáu nguồn.
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
```

Ghi chú bên thứ ba (MIT, Nekori): [THIRD-PARTY-NOTICES.md](booxbook.koplugin/THIRD-PARTY-NOTICES.md).
