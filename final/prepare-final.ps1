param([string]$PreviousSession)
$ErrorActionPreference = 'Stop'
if (-not $PreviousSession) {
    $base = Join-Path (Get-Location).Path 'z9x-hb-build'
    $PreviousSession = Get-ChildItem -LiteralPath $base -Directory | Where-Object { [IO.File]::Exists((Join-Path $_.FullName 'session.json')) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $PreviousSession) { throw 'Saved original session not found; pass -PreviousSession' }
$old = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $PreviousSession 'session.json') | ConvertFrom-Json
if ($old.before_sha256 -cne '69e51d6087f1554153ae9d23008a77aec10747476a8adb206ab2c0cc816fa411') { throw 'Saved APK is not the reviewed baseline' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $old.before_apk).Hash.ToLowerInvariant() -cne $old.before_sha256) { throw 'Saved full original APK changed' }
$session = Join-Path $PSScriptRoot ('final-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($session)
$candidate = Join-Path $session 'projector-settings-ru-v3.UNSIGNED.apk'
& (Join-Path $PSScriptRoot 'build-candidate.ps1') -SourceApk $old.before_apk -OutputApk $candidate
$built = Get-Content -Raw -Encoding UTF8 -LiteralPath ($candidate + '.json') | ConvertFrom-Json
$meta = [ordered]@{fingerprint=$old.fingerprint; adb=$old.adb; serial=$old.serial; before_apk=$old.before_apk; before_sha256=$old.before_sha256; candidate_apk=$candidate; candidate_sha256=$built.candidate_sha256; installed=$false}
[IO.File]::WriteAllText((Join-Path $session 'session.json'), ($meta | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host ('SESSION: ' + $session)
Write-Host ('CANDIDATE_SHA256: ' + $meta.candidate_sha256)
Write-Host 'BUILT_ONLY: full APK created locally from saved original; nothing installed. Do not use adb install.'
