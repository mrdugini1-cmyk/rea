param([string]$Serial)
$ErrorActionPreference = 'Stop'
$adbPath = [IO.Path]::GetFullPath((Join-Path (Get-Location).Path 'adb.exe'))
if (-not [IO.File]::Exists($adbPath)) { throw 'Run this script from your platform-tools directory containing adb.exe' }
$selectArgs = @()
if ($Serial) { $selectArgs = @('-s', $Serial) }
$state = (& $adbPath @selectArgs get-state | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $state -ne 'device') { throw 'One authorized ADB device is required; use -Serial if more than one is connected' }
$fingerprint = (& $adbPath @selectArgs shell getprop ro.build.fingerprint | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $fingerprint -cne 'XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys') { throw 'Device firmware differs from the reviewed projector' }
$session = Join-Path $PSScriptRoot ('preview-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
[void][IO.Directory]::CreateDirectory($session)
$original = Join-Path $session 'before.apk'
$candidate = Join-Path $session 'candidate.UNSIGNED.apk'
& $adbPath @selectArgs pull /system/priv-app/release_838_newsettings/release_838_newsettings.apk $original
if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($original)) { throw 'Could not save the current complete APK; no device changes made' }
& (Join-Path $PSScriptRoot 'build-candidate.ps1') -SourceApk $original -OutputApk $candidate
$meta = Get-Content -Raw -LiteralPath ($candidate + '.json') | ConvertFrom-Json
$info = [ordered]@{ fingerprint=$fingerprint; adb=$adbPath; serial=$Serial; before_apk=$original; before_sha256=$meta.source_apk_sha256; candidate_apk=$candidate; candidate_sha256=$meta.candidate_sha256; installed=$false }
[IO.File]::WriteAllText((Join-Path $session 'session.json'), ($info | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host ('SESSION: ' + $session)
Write-Host ('BEFORE_SHA256: ' + $meta.source_apk_sha256)
Write-Host ('CANDIDATE_SHA256: ' + $meta.candidate_sha256)
Write-Host 'PREPARED_ONLY: backup saved, full candidate verified and aligned; nothing installed on the projector.'
