#Requires -Version 5.1
# Preview website locally with the real plugin version injected
# (same placeholders the Pages workflow fills in).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$meta = Join-Path $root "booxbook.koplugin/_meta.lua"
$ver = (Select-String -Path $meta -Pattern 'version\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
$url = "https://github.com/hongducdev/booxbook.koplugin/releases/tag/v$ver"
$tmp = Join-Path ([IO.Path]::GetTempPath()) "booxbook-website"
if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
Copy-Item (Join-Path $root "website/*") $tmp -Recurse -Force
$html = Join-Path $tmp "index.html"
(Get-Content -LiteralPath $html -Raw).Replace("{{BOOXBOOK_VERSION}}", $ver).Replace("{{BOOXBOOK_RELEASE_URL}}", $url).Replace("{{BOOXBOOK_STARS}}", "—").Replace("{{BOOXBOOK_DOWNLOADS}}", "—") | Set-Content -LiteralPath $html -NoNewline
Write-Output "Preview v$ver at http://localhost:8000/ (Ctrl+C to stop)"
python -m http.server 8000 --directory $tmp
