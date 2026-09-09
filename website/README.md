# Website BooxBook

Site tĩnh giới thiệu plugin + hướng dẫn cài đặt / sử dụng. Không build, không dependency.

```
website/
├── index.html   nội dung tiếng Việt, toàn bộ section
├── styles.css   theme giấy-mực e-ink (Fraunces + Be Vietnam Pro)
├── main.js      tabs hướng dẫn + accordion FAQ + scroll reveal, vanilla JS
```

Chạy local (tự điền đúng version như bản deploy):

```powershell
pwsh -File scripts/preview-website.ps1
# mở http://localhost:8000/
```

Mở trực tiếp `index.html` cũng được nhưng sẽ thấy placeholder thô `{{BOOXBOOK_VERSION}}`.

## Tự động đồng bộ dữ liệu

`index.html` dùng các placeholder được workflow điền khi deploy:

- `{{BOOXBOOK_VERSION}}` — số phiên bản (badge, mock menu, bước 5, CTA).
- `{{BOOXBOOK_RELEASE_URL}}` — link đúng tag release (`.../releases/tag/vX.Y.Z`).
- `{{BOOXBOOK_STARS}}` — số sao GitHub.
- `{{BOOXBOOK_DOWNLOADS}}` — tổng lượt tải asset của tối đa 100 Release gần nhất.

Workflow `.github/workflows/pages.yml` thay thế các placeholder trước khi deploy và fail
nếu còn placeholder sót. Đổi version chỉ cần sửa `_meta.lua` — push main là web
tự cập nhật. Đường dẫn dữ liệu (`koreader/...`, `Tools → ...`) giữ sửa tay vì
chỉ đổi khi kiến trúc plugin đổi.

Deploy: workflow `.github/workflows/pages.yml` đẩy thư mục `website/` lên GitHub Pages mỗi khi push main và chạy mỗi ngày để làm mới số sao/lượt tải. Sau khi bật Pages (Settings → Pages → Source: GitHub Actions), cập nhật URL demo trong `README.md` gốc.

## Responsive

Breakpoints trong `styles.css`: 960px (tablet), 620px (điện thoại), 480px (máy bé 360–480).
Quy ước khi sửa CSS: không dùng `overflow-x:hidden` trên body (làm hỏng sticky topbar) — đã dùng `overflow-x:clip`;
bóng thẻ giảm còn 4px ở mobile; ảnh có guard `max-width:100%`; bảng báo giữ `min-width` + cuộn ngang trong `.table-wrap`.
