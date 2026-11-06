param([string]$SessionPath, [switch]$Rollback, [switch]$Diagnose)
$ErrorActionPreference = 'Stop'
if ($Rollback -and $Diagnose) { throw 'Choose either -Rollback or -Diagnose' }
if (-not $SessionPath) {
    $buildRoot = Join-Path (Get-Location).Path 'z9x-hb-build'
    if (-not (Test-Path -LiteralPath $buildRoot -PathType Container)) { throw 'Run prepare-preview.ps1 first; build directory not found' }
    $sessions = @(Get-ChildItem -LiteralPath $buildRoot -Directory -Filter 'preview-*' | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.FullName 'session.json')) -and ((-not $Rollback) -or (Test-Path -LiteralPath (Join-Path $_.FullName 'runtime.json')))
    } | Sort-Object LastWriteTime -Descending)
    if ($sessions.Count -eq 0) { throw 'No matching prepared session found' }
    $SessionPath = $sessions[0].FullName
}
$SessionPath = [IO.Path]::GetFullPath($SessionPath)
Write-Host ('USING_SESSION: ' + $SessionPath)
$meta = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $SessionPath 'session.json') | ConvertFrom-Json
$adb = $meta.adb
if (-not [IO.File]::Exists($adb)) { throw 'Saved adb.exe not found' }
$selectArgs = @()
if ($meta.serial) { $selectArgs = @('-s', [string]$meta.serial) }
function Invoke-AdbText([string[]]$Arguments) {
    # Windows PowerShell 5.1 wraps merged native stderr in ErrorRecord objects.
    # ADB progress on stderr is successful when the native exit code is zero.
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = & $adb @selectArgs @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $text = (($lines | ForEach-Object { $_.ToString() }) -join "`n").Trim()
    if ($code -ne 0) { throw ('ADB failed: ' + $text) }
    return $text
}
function Read-Phase([string]$RemotePath) {
    return Invoke-AdbText -Arguments @('shell', ('if [ -f "{0}/phase" ]; then cat "{0}/phase"; fi' -f $RemotePath))
}
function Read-Log([string]$RemotePath, [int]$Lines = 60) {
    if ($Lines -lt 1 -or $Lines -gt 200) { throw 'Invalid log line limit' }
    Write-Host (Invoke-AdbText -Arguments @('shell', ('if [ -f "{0}/session.log" ]; then tail -n {1} "{0}/session.log"; fi' -f $RemotePath, $Lines)))
}
function Clear-CachedRequest {
    $command = @'
[ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ] || exit 1
setprop ctl.restart xgimi_ssh
'@
    [void](Invoke-AdbText -Arguments @('shell', $command.Replace("`r", '')))
}
if ((Invoke-AdbText -Arguments @('get-state')) -ne 'device') { throw 'Authorized ADB device required' }
$fp = Invoke-AdbText -Arguments @('shell','getprop','ro.build.fingerprint')
if ($fp -cne 'XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys') { throw 'Projector firmware differs' }
$receiptPath = Join-Path $SessionPath 'runtime.json'
if ($Rollback) {
    $receipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptPath | ConvertFrom-Json
    $remote = [string]$receipt.remote_stage
    if ($remote -notmatch '^/data/ssh/z9x-ru-preview-[0-9a-f]{32}$') { throw 'Invalid saved preview path' }
    $phase = Read-Phase $remote
    if ($receipt.kind -eq 'diagnostic') {
        if ($phase -ne 'DIAGNOSTIC_DONE') { throw 'This is a read-only diagnostic stage; wait for it to finish. It creates no APK overlay.' }
        Clear-CachedRequest
        Write-Host 'DIAGNOSTIC_DONE: this stage created no APK overlay.'
        exit 0
    }
    if ($phase -ne 'ROLLED_BACK') {
        [void](Invoke-AdbText -Arguments @('shell', ('printf "ROLLBACK\n" > "{0}/rollback.request"' -f $remote)))
        for ($i=0; $i -lt 90; $i++) {
            $phase = Read-Phase $remote
            if ($phase -eq 'ROLLED_BACK') { break }
            if ($phase -like '*FAILED*' -or $phase -like '*REFUSED*' -or $phase -like '*CHANGED*' -or $phase -like '*UNCONFIRMED*') { Read-Log $remote; throw ('Rollback needs inspection: ' + $phase) }
            Start-Sleep -Seconds 1
        }
    }
    if ($phase -ne 'ROLLED_BACK') { Read-Log $remote; throw ('Rollback not confirmed yet: ' + $phase) }
    Clear-CachedRequest
    Read-Log $remote
    Write-Host 'ROLLED_BACK: previous APK restored and preview service state cleaned up.'
    exit 0
}
if ([IO.File]::Exists($receiptPath)) {
    $previous = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptPath | ConvertFrom-Json
    $previousRemote = [string]$previous.remote_stage
    if ($previousRemote -notmatch '^/data/ssh/z9x-ru-preview-[0-9a-f]{32}$') { throw 'Invalid previous preview path; leaving its record untouched' }
    if ($previous.before_sha256 -cne $meta.before_sha256 -or $previous.candidate_sha256 -cne $meta.candidate_sha256) { throw 'Previous runtime record belongs to different APKs' }
    $terminalStage = $false
    $previousPhase = Read-Phase $previousRemote
    $exitCode = Invoke-AdbText -Arguments @('shell', ('if [ -f "{0}/exit-code" ]; then cat "{0}/exit-code"; fi' -f $previousRemote))
    if ($Diagnose -and $previousPhase -match '^(ROLLED_BACK|ROLLBACK_[A-Z_]+|MAINTENANCE_RESTART_FAILED|PREFLIGHT_MOUNT_UNDO_FAILED)$' -and $exitCode -match '^\d+$') { $terminalStage = $true }
    if ($previousPhase -eq 'DIAGNOSTIC_DONE' -and $exitCode -eq '0') { $terminalStage = $true }
    if ($previousPhase -eq 'ROLLED_BACK' -and $exitCode -match '^\d+$') {
        $paramsState = Invoke-AdbText -Arguments @('shell', 'if [ ! -L /data/ssh/params ]; then stat -c %u:%a:%s /data/ssh/params; fi')
        if ($paramsState -cne '0:600:0') { throw 'SSH params not restored; refusing another preview' }
        $terminalStage = $true
    }
    $probe = @'
set -eu
D='%REMOTE%'
if [ -L "$D" ] || [ -e "$D/arm.sh" ] || [ -e "$D/once" ] || [ -e "$D/phase" ] || [ -e "$D/original.params" ]; then
 echo PRIOR_STAGE_MAY_HAVE_STARTED
 exit 0
fi
[ ! -L /data/ssh/params ] && [ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ] || { echo SSH_PARAMS_NOT_BASELINE; exit 0; }
echo TRANSFER_NEVER_ARMED
'@
    $probe = $probe.Replace('%REMOTE%', $previousRemote).Replace("`r", '')
    $probeResult = 'TRANSFER_NEVER_ARMED'
    if (-not $terminalStage) { $probeResult = Invoke-AdbText -Arguments @('shell', $probe) }
    if ($probeResult -cne 'TRANSFER_NEVER_ARMED') { throw ('Previous stage cannot be resumed automatically: ' + $probeResult + '. Use -Rollback or send this output.') }
    $receiptPrefix = 'runtime.failed-transfer-'
    if ($terminalStage) { $receiptPrefix = 'runtime.completed-stage-' }
    $archivedReceipt = Join-Path $SessionPath ($receiptPrefix + [Guid]::NewGuid().ToString('N') + '.json')
    Move-Item -LiteralPath $receiptPath -Destination $archivedReceipt
    if ($terminalStage) { Write-Host 'Previous stage has finished; saved its receipt.' } else { Write-Host 'Previous stage stopped before arming; saved its receipt and starting a new transfer.' }
}
foreach ($value in @($meta.before_sha256, $meta.candidate_sha256)) { if ($value -notmatch '^[0-9a-f]{64}$') { throw 'Invalid stored SHA-256' } }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $meta.before_apk).Hash.ToLowerInvariant() -cne $meta.before_sha256) { throw 'Local original APK differs' }
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $meta.candidate_apk).Hash.ToLowerInvariant() -cne $meta.candidate_sha256) { throw 'Local candidate differs' }
$live = Invoke-AdbText -Arguments @('shell','sha256sum','/system/priv-app/release_838_newsettings/release_838_newsettings.apk')
if (-not $Diagnose -and ($live -split '\s+')[0] -cne $meta.before_sha256) { throw 'Current projector APK changed after the backup; no preview started' }
if ($Diagnose) {
    Write-Host ('ADB_APK: ' + $live)
    Write-Host ('ADB_MOUNT_NS: ' + (Invoke-AdbText -Arguments @('shell','readlink','/proc/self/ns/mnt')))
}
$remote = '/data/ssh/z9x-ru-preview-' + [Guid]::NewGuid().ToString('N')
[void](Invoke-AdbText -Arguments @('shell', ('mkdir "{0}" && chmod 700 "{0}"' -f $remote)))
$receipt = [ordered]@{ kind='preview'; remote_stage=$remote; before_sha256=$meta.before_sha256; candidate_sha256=$meta.candidate_sha256; max_preview_seconds=300; persistent=$false; lifecycle='transferring' }
if ($Diagnose) { $receipt['kind'] = 'diagnostic' }
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
[void](Invoke-AdbText -Arguments @('push', (Join-Path $PSScriptRoot 'runtime-entry.sh'), ($remote + '/runtime-entry.sh')))
$bodyName = 'runtime-body.sh'
if ($Diagnose) { $bodyName = 'diagnose-body.sh' }
[void](Invoke-AdbText -Arguments @('push', (Join-Path $PSScriptRoot $bodyName), ($remote + '/runtime-body.sh')))
if (-not $Diagnose) { [void](Invoke-AdbText -Arguments @('push', [string]$meta.candidate_apk, ($remote + '/upload.apk'))) }
foreach ($pair in @(@('before.sha256', $meta.before_sha256), @('candidate.sha256', $meta.candidate_sha256))) {
    $path = Join-Path $SessionPath $pair[0]
    [IO.File]::WriteAllText($path, ($pair[1] + "`n"), [Text.Encoding]::ASCII)
    [void](Invoke-AdbText -Arguments @('push', $path, ($remote + '/' + $pair[0])))
}
# Ordinary HOME navigation closes the settings overlay before the scoped refresh.
if (-not $Diagnose) { [void](Invoke-AdbText -Arguments @('shell','input','keyevent','3')) }
$arm = @'
set -eu
umask 077
D='%REMOTE%'
[ "$(getprop init.svc.xgimi_ssh)" = running ] || exit 10
[ "$(getprop xgimi.remoteDebug.on)" = true ] || exit 11
[ ! -L /data/ssh/params ] && [ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ] || exit 12
chmod 700 "$D/runtime-entry.sh" "$D/runtime-body.sh"
printf '%s\n' "-oProxyCommand=$D/runtime-entry.sh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null -oBatchMode=yes -oConnectTimeout=600 127.0.0.1" > "$D/request.params"
cp "$D/request.params" "$D/armed.params"
chmod 600 "$D/armed.params"
restore_params() {
 if [ -f "$D/original.params" ]; then
  if [ ! -e /data/ssh/params ] || cmp -s /data/ssh/params "$D/request.params"; then
   mv "$D/original.params" /data/ssh/params
  else
   echo "REFUSED_FOREIGN_PARAMS: original retained at $D/original.params"
   return 1
  fi
 fi
}
trap restore_params EXIT
trap 'exit 130' HUP INT TERM
mv /data/ssh/params "$D/original.params"
mv "$D/armed.params" /data/ssh/params
setprop ctl.restart xgimi_ssh
N=0
while [ "$N" -lt 100 ]; do
 if [ ! -e "$D/original.params" ] && [ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ]; then echo ROOT_STAGE_STARTED; exit 0; fi
 sleep 0.2; N=$((N+1))
done
echo ROOT_START_NOT_CONFIRMED
exit 13
'@
$arm = $arm.Replace('%REMOTE%', $remote).Replace("`r", '')
$armPath = Join-Path $SessionPath 'arm-preview.sh'
[IO.File]::WriteAllText($armPath, $arm, [Text.Encoding]::ASCII)
[void](Invoke-AdbText -Arguments @('push', $armPath, ($remote + '/arm.sh')))
$receipt['lifecycle'] = 'arming'
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host ('REMOTE_STAGE: ' + $remote)
Write-Host ('RECOVERY_IF_ARM_INTERRUPTED: adb shell mv ' + $remote + '/original.params /data/ssh/params')
Write-Host (Invoke-AdbText -Arguments @('shell', ('sh "{0}/arm.sh"' -f $remote)))
$lastPhase = ''
for ($i=0; $i -lt 180; $i++) {
    $phase = Read-Phase $remote
    if ($phase -and $phase -ne $lastPhase) { Write-Host ('PHASE: ' + $phase); $lastPhase = $phase }
    if ($Diagnose -and $phase -eq 'DIAGNOSTIC_DONE') {
        # Let the root wrapper finish before clearing its cached SSH arguments.
        for ($j=0; $j -lt 5; $j++) {
            $done = Invoke-AdbText -Arguments @('shell', ('if [ -f "{0}/exit-code" ]; then cat "{0}/exit-code"; fi' -f $remote))
            if ($done -eq '0') { break }
            Start-Sleep -Seconds 1
        }
        if ($done -ne '0') { Read-Log $remote; throw 'Diagnostic exit is not confirmed; send this output before restarting SSH' }
        Clear-CachedRequest
        Read-Log $remote 200
        Write-Host 'DIAGNOSTIC_DONE: no APK replacement or mount performed.'
        exit 0
    }
    if (-not $Diagnose -and $phase -eq 'APPLIED_5_MINUTES') {
        Write-Host 'APPLIED_5_MINUTES: open projector settings with the remote and inspect the translation.'
        Write-Host ('SESSION: ' + $SessionPath)
        Write-Host 'Automatic rollback follows after five minutes. Do not restart SSH or rerun root-probe during this window.'
        Write-Host 'For earlier rollback, run this script again with the same -SessionPath and -Rollback.'
        exit 0
    }
    if ($phase -eq 'ROLLED_BACK') {
        Clear-CachedRequest
        Read-Log $remote
        throw 'Preview ended before confirmation; previous APK is restored. Send the log above.'
    }
    if ($phase -like '*FAILED*' -or $phase -like '*REFUSED*' -or $phase -like '*CHANGED*' -or $phase -like '*UNCONFIRMED*') {
        Read-Log $remote
        throw ('Preview needs inspection: ' + $phase)
    }
    Start-Sleep -Seconds 1
}
Read-Log $remote
throw 'Startup still not confirmed; use -Rollback with this session and send the output. No permanent installation was requested.'
