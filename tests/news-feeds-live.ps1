# Optional live check; -All audits every catalog entry, otherwise ten new publishers.
# -PassThru returns records for a report without asserting all feeds are populated.
param([switch]$All, [switch]$PassThru)
$ErrorActionPreference = 'Stop'
$catalog = @'
package.path = 'booxbook.koplugin/?.lua;' .. package.path
local old = {vnexpress=true,tuoitre=true,thanhnien=true,dantri=true,bbc=true,guardian=true,dw=true}
for _, p in ipairs(require('booxbook.sources.feeds')) do
    for i, feed in ipairs(p.categories) do
        if os.getenv('BOOXBOOK_AUDIT_ALL') == '1' or (not old[p.id] and i == 1) then
            print(p.id .. '|' .. feed.id .. '|' .. feed.url)
        end
    end
end
'@
$parse = @'
package.path = 'booxbook.koplugin/?.lua;' .. package.path
-- Parsing only: do not initialize KOReader/LuaSocket transport on the host.
package.loaded['booxbook.http'] = {}
local items = require('booxbook.sources.rss').parse(io.read('*a'))
print(#items)
'@
$oldFlag = $env:BOOXBOOK_AUDIT_ALL
try {
    $env:BOOXBOOK_AUDIT_ALL = if ($All) { '1' } else { '0' }
    $lines = @(& luajit -e $catalog)
    if ($LASTEXITCODE -ne 0 -or !$lines.Count) { throw 'Catalog export failed' }
} finally { $env:BOOXBOOK_AUDIT_ALL = $oldFlag }
$feeds = @($lines | ForEach-Object {
    $paper, $id, $url = $_ -split '\|', 3
    [pscustomobject]@{ paper = $paper; id = $id; url = $url; host = ([uri]$url).DnsSafeHost }
})
# Use the production UA constant; no UA rotation or proxies.
$http = Get-Content -Raw 'booxbook.koplugin/booxbook/http.lua'
$agent = [regex]::Match($http, 'USER_AGENT\s*=\s*"([^"]+)"').Groups[1].Value
if (!$agent) { throw 'Missing production user agent' }
$root = (Get-Location).Path.Replace('\', '/')
$parse = $parse.Replace('booxbook.koplugin/?.lua', "$root/booxbook.koplugin/?.lua")
$results = @($feeds | Group-Object host | ForEach-Object -Parallel {
    $parseCode = $using:parse
    $session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
    $session.UserAgent = $using:agent
    $blocked = $null
    foreach ($row in $_.Group) {
        $record = [ordered]@{ paper=$row.paper; id=$row.id; url=$row.url; count=0; status='error'; detail=''; checked=[DateTime]::UtcNow.ToString('o') }
        if ($blocked) { $record.detail=$blocked; [pscustomobject]$record; continue }
        # One request at a time per host, at least 1.2 s apart. Recheck empty/errors once.
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            Start-Sleep -Milliseconds 1200
            try {
                if ($row.host -eq 'vnexpress.net' -or $row.host.EndsWith('.vnexpress.net')) {
                    foreach ($name in @('device_env', 'device_env_real')) {
                        $session.Cookies.Add([System.Net.Cookie]::new($name, '4', '/', '.vnexpress.net'))
                    }
                }
                $response = Invoke-WebRequest -Uri $row.url -WebSession $session -Headers @{ Referer=$row.url } -UseBasicParsing -TimeoutSec 15
                if ($response.RawContentLength -gt 2097152) { throw 'exceeds plugin 2 MiB body cap' }
                $countText = $response.Content | & luajit -e $parseCode
                if ($LASTEXITCODE -ne 0 -or "$countText" -notmatch '^\d+$') { throw 'RSS parser failed' }
                $record.count = [int]$countText
                $record.status = if ($record.count -gt 0) { 'ok' } else { 'empty' }
                $record.detail = "HTTP $($response.StatusCode)"
                if ($record.count -gt 0) { break }
            } catch {
                $record.status = 'error'
                $record.detail = $_.Exception.Message -replace '[\r\n|]+', ' '
                $code = [int]$_.Exception.Response.StatusCode
                if ($code -eq 429) { $blocked='Skipped after host returned HTTP 429; recheck later' }
                # Do not keep probing a host that explicitly limits/denies this request.
                if ($code -eq 429 -or $code -eq 403) { break }
            }
        }
        [pscustomobject]$record
    }
    Write-Host "Checked host: $($_.Name)"
} -ThrottleLimit 4 | Sort-Object paper, id)
if ($PassThru) { return $results }
foreach ($row in $results) { Write-Output "$($row.paper) : $($row.count) articles : $($row.status) : $($row.url)" }
$failed = @($results | Where-Object status -ne 'ok')
if ($failed.Count) { throw "$($failed.Count)/$($results.Count) feeds empty or unavailable" }
Write-Output "All $($results.Count) checked feeds have articles"
