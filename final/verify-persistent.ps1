param([string]$SessionPath)
$ErrorActionPreference = 'Stop'
if (-not $SessionPath) {
    $SessionPath = Get-ChildItem -LiteralPath $PSScriptRoot -Directory -Filter 'final-*' | Where-Object { [IO.File]::Exists((Join-Path $_.FullName 'session.json')) } | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $SessionPath) { throw 'Run prepare-final.ps1 first' }
$meta = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $SessionPath 'session.json') | ConvertFrom-Json
$adb = [string]$meta.adb
$selectArgs = @(); if ($meta.serial) { $selectArgs = @('-s', [string]$meta.serial) }
function AdbText([string[]]$Arguments) {
    $savedPreference = $ErrorActionPreference
    try { $ErrorActionPreference = 'Continue'; $lines = & $adb @selectArgs @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $savedPreference }
    $text = ($lines | ForEach-Object { $_.ToString() } | Out-String).Trim()
    if ($code -ne 0) { throw ('ADB failed: ' + $text) }
    return $text
}
if ((AdbText @('shell','getprop','ro.build.fingerprint')) -cne $meta.fingerprint) { throw 'Projector firmware differs from saved session' }
$receiptPath = Join-Path $SessionPath 'persistent.json'
$receipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptPath | ConvertFrom-Json
$boot = AdbText @('shell','cat','/proc/sys/kernel/random/boot_id')
if ($boot -eq $receipt.installed_boot_id) { throw 'Same device boot as installation; reboot persistence cannot be confirmed yet' }
if ((AdbText @('shell','cat','/data/z9x-ru-persistent/phase')) -cne 'PERSISTENT_ACTIVE') { throw 'Persistent worker not active yet; wait or send its log' }
if ((AdbText @('shell','cat','/data/z9x-ru-persistent/boot.id')) -cne $boot) { throw 'Worker status belongs to a different boot' }
$sha = ((AdbText @('shell','sha256sum','/system/priv-app/release_838_newsettings/release_838_newsettings.apk')) -split '\s+')[0]
if ($sha -cne $meta.candidate_sha256) { throw 'Live APK does not match the built translation' }
$receipt.boot_verified = $true
$receipt | Add-Member -NotePropertyName verified_boot_id -NotePropertyValue $boot -Force
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host 'BOOT_PERSISTENCE_VERIFIED: new boot ID, active worker and exact candidate APK hash confirmed.'
