return [=[<!doctype html>
<html lang="vi"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gửi sách · BooxBook</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f4f2eb;color:#20251f;font:17px/1.6 system-ui,sans-serif}
main{max-width:640px;margin:8vh auto;padding:28px}small{letter-spacing:.14em;color:#506449}
h1{font-size:clamp(30px,7vw,44px);line-height:1.15;margin:14px 0}p{color:#51574f}
form{background:white;padding:24px;border:1px solid #d4d8cf;border-radius:14px;margin:28px 0}
label{display:block;font-weight:650;margin-bottom:8px}input{font:inherit;max-width:100%;margin-bottom:22px}
input[type=text]{width:100%;padding:10px;border:1px solid #757e70;border-radius:6px}
button{font:inherit;font-weight:650;background:#294c34;color:white;border:0;border-radius:8px;padding:13px 22px;width:100%;cursor:pointer}
button:disabled{opacity:.5;cursor:wait}progress{width:100%;accent-color:#294c34}li{overflow-wrap:anywhere;margin:12px 0}
:focus-visible{outline:3px solid #b27920;outline-offset:4px}footer{font-size:14px;color:#51574f}
</style><main><small>BOOXBOOK · CÙNG MẠNG WI-FI</small>
<h1>Gửi sách tới<br>máy đọc của bạn.</h1>
<p>Chọn sách từ điện thoại hoặc máy tính. Sách được chuyển trực tiếp tới máy đọc sách.</p>
<form id="form"><label for="token">Mã phiên 6 số trên máy đọc sách</label>
<input id="token" type="text" inputmode="numeric" pattern="[0-9]{6}" minlength="6" maxlength="6" required autocomplete="off" spellcheck="false" autocapitalize="off">
<label for="files">Chọn sách (có thể chọn nhiều file)</label>
<input id="files" type="file" multiple required accept=".epub,.pdf,.cbz,.cbr,.fb2,.mobi,.azw,.azw3,.djvu,.djv,.txt,.rtf,.doc,.chm">
<p>Mỗi file tối đa 512 MiB. File trùng tên cần đổi tên trước khi gửi.</p>
<button id="send">Gửi sách</button></form>
<label for="progress">Tiến độ file hiện tại</label><progress id="progress" max="100" value="0"></progress>
<p id="status" role="status" aria-live="polite">Sẵn sàng nhận sách.</p><ul id="results"></ul>
<footer>Giữ màn hình “Gửi sách qua Wi-Fi” mở trên máy đọc. Tìm sách tại Thư viện → received.
Chỉ dùng trong mạng tin cậy; đóng màn hình nhận sách khi xong.</footer></main>
<script>
'use strict';
const form=document.getElementById('form'),button=document.getElementById('send');
const files=document.getElementById('files'),token=document.getElementById('token');
const progress=document.getElementById('progress'),status=document.getElementById('status');
const results=document.getElementById('results');
// The fragment stays in the browser, never in HTTP requests or referrers.
if(location.hash){token.value=location.hash.slice(1);history.replaceState(null,'',location.pathname)}
function upload(file){return new Promise(resolve=>{
 const xhr=new XMLHttpRequest();xhr.open('POST','/upload');xhr.timeout=30*60*1000;
 xhr.setRequestHeader('Content-Type','application/octet-stream');
 xhr.setRequestHeader('X-BooxBook-Token',token.value.trim());xhr.setRequestHeader('X-File-Name',encodeURIComponent(file.name));
 xhr.upload.onprogress=e=>{if(e.lengthComputable)progress.value=e.loaded/e.total*100};
 xhr.onload=()=>resolve(xhr.status===201?'Đã lưu vào thư viện.':xhr.responseText||'Gửi thất bại.');
 xhr.onerror=()=>resolve('Mất kết nối. Kiểm tra Wi-Fi và màn hình nhận sách.');
 xhr.ontimeout=()=>resolve('Hết thời gian gửi. Hãy thử lại.');xhr.onabort=()=>resolve('Đã hủy.');
 xhr.send(file);
})}
form.addEventListener('submit',async e=>{
 e.preventDefault();button.disabled=files.disabled=token.disabled=true;results.textContent='';
 try{for(const file of Array.from(files.files)){
  progress.value=0;status.textContent='Đang gửi: '+file.name;
  const message=file.size<1||file.size>512*1024*1024?'File phải từ 1 byte đến 512 MiB.':await upload(file);
  const li=document.createElement('li');li.textContent=file.name+' — '+message;results.appendChild(li);
 }status.textContent='Đã xử lý xong. Xem kết quả từng file bên dưới.'}
 catch(error){status.textContent='Không gửi được sách. Hãy thử lại.'}
 finally{button.disabled=files.disabled=token.disabled=false}
});
</script></html>]=]
