param([string]$SessionPath, [switch]$Rollback)
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
function ReadPhase { AdbText @('shell', 'if [ -f /data/z9x-ru-persistent/phase ]; then cat /data/z9x-ru-persistent/phase; fi') }
function ShowLog { Write-Host (AdbText @('shell', 'if [ -f /data/z9x-ru-persistent/session.log ]; then tail -n 100 /data/z9x-ru-persistent/session.log; fi')) }
if ((AdbText @('get-state')) -cne 'device') { throw 'One authorized ADB device is required' }
if ((AdbText @('shell','getprop','ro.build.fingerprint')) -cne 'XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys') { throw 'Different projector firmware' }
$receiptPath = Join-Path $SessionPath 'persistent.json'
if ($Rollback) {
    $receipt = Get-Content -Raw -Encoding UTF8 -LiteralPath $receiptPath | ConvertFrom-Json
    $remote = [string]$receipt.remote_stage
    if ($remote -notmatch '^/data/ssh/z9x-ru-preview-[0-9a-f]{32}$') { throw 'Invalid saved control path' }
    if ((ReadPhase) -ne 'ROLLED_BACK') {
        [void](AdbText @('shell', ('printf ROLLBACK > {0}/rollback.request' -f $remote)))
        for ($i=0; $i -lt 90; $i++) {
            $phase = ReadPhase
            if ($phase -eq 'ROLLED_BACK') { break }
            if ($phase -like '*FAILED*' -or $phase -like '*REFUSED*' -or $phase -like '*CHANGED*' -or $phase -like '*UNCONFIRMED*') { ShowLog; throw ('Rollback needs inspection: ' + $phase) }
            Start-Sleep -Seconds 1
        }
    }
    if ((ReadPhase) -ne 'ROLLED_BACK') { ShowLog; throw 'Rollback not confirmed; keep the recovery files' }
    $sha = ((AdbText @('shell','sha256sum','/system/priv-app/release_838_newsettings/release_838_newsettings.apk')) -split '\s+')[0]
    if ($sha -cne $meta.before_sha256) { throw 'Original APK not confirmed' }
    $params = AdbText @('shell','stat','-c','%u:%a:%s','/data/ssh/params')
    if ($params -cne '0:600:0') { throw 'Original SSH params not confirmed' }
    [void](AdbText @('shell','setprop','ctl.restart','xgimi_ssh'))
    ShowLog
    Write-Host 'ROLLED_BACK: previous APK and empty original SSH params restored; boot hook removed. Recovery files retained.'
    exit 0
}
if ([IO.File]::Exists($receiptPath)) { throw 'Persistent attempt already recorded; do not overwrite it. Send the log or use -Rollback.' }
foreach ($pair in @(@($meta.before_apk,$meta.before_sha256), @($meta.candidate_apk,$meta.candidate_sha256))) {
    if ($pair[1] -notmatch '^[0-9a-f]{64}$' -or (Get-FileHash -Algorithm SHA256 -LiteralPath $pair[0]).Hash.ToLowerInvariant() -cne $pair[1]) { throw 'Local APK differs from saved hashes' }
}
$current = ((AdbText @('shell','sha256sum','/system/priv-app/release_838_newsettings/release_838_newsettings.apk')) -split '\s+')[0]
if ($current -cne $meta.before_sha256) { throw 'Wait for the old preview to roll back; live APK is not the saved baseline' }
if ((AdbText @('shell','getprop','xgimi.remoteDebug.on')) -cne 'true') { throw 'XGIMI remote debug must already be enabled' }
if ((AdbText @('shell','stat','-c','%u:%a:%s','/data/ssh/params')) -cne '0:600:0') { throw 'SSH params not empty baseline; refusing to replace them' }
if ((AdbText @('shell','test','!','-e','/data/z9x-ru-persistent')) -ne '') { throw 'Unexpected persistent directory probe' }
# The vendor script itself restores /data/ssh mode 777 on restart; do not chmod keys.
[void](AdbText @('shell','setprop','ctl.restart','xgimi_ssh'))
Start-Sleep -Seconds 2
$remote = '/data/ssh/z9x-ru-preview-' + [Guid]::NewGuid().ToString('N')
[void](AdbText @('shell', ('mkdir {0} && chmod 700 {0}' -f $remote)))
$bootId = AdbText @('shell','cat','/proc/sys/kernel/random/boot_id')
if ($bootId -notmatch '^[0-9a-f-]{36}$') { throw 'Invalid device boot ID' }
$receipt = [ordered]@{installed_boot_id=$bootId; remote_stage=$remote; before_sha256=$meta.before_sha256; candidate_sha256=$meta.candidate_sha256; persistent=$true; boot_verified=$false}
[IO.File]::WriteAllText($receiptPath, ($receipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
foreach ($pair in @(@('runtime-entry.sh','runtime-entry.sh'), @('persistent-install.sh','runtime-body.sh'), @('persistent-worker.sh','persistent-worker.sh'), @('persistent-entry.sh','persistent-entry.sh'))) {
    [void](AdbText @('push',(Join-Path $PSScriptRoot $pair[0]),($remote + '/' + $pair[1])))
}
[void](AdbText @('push',[string]$meta.candidate_apk,($remote+'/upload.apk')))
foreach ($pair in @(@('before.sha256',$meta.before_sha256), @('candidate.sha256',$meta.candidate_sha256))) {
    $path = Join-Path $SessionPath $pair[0]
    [IO.File]::WriteAllText($path, ($pair[1]+"`n"), [Text.Encoding]::ASCII)
    [void](AdbText @('push',$path,($remote+'/'+$pair[0])))
}
[void](AdbText @('shell','input','keyevent','3'))
$arm = @'
set -eu
umask 077
D='%REMOTE%'
[ "$(getprop init.svc.xgimi_ssh)" = running ] || exit 10
[ "$(getprop xgimi.remoteDebug.on)" = true ] || exit 11
[ ! -L /data/ssh/params ] && [ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ] || exit 12
chmod 700 "$D/runtime-entry.sh" "$D/runtime-body.sh"
printf '%s\n' "-oProxyCommand=$D/runtime-entry.sh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null -oBatchMode=yes -oConnectTimeout=0 127.0.0.1" > "$D/request.params"
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
$armPath = Join-Path $SessionPath 'arm-persistent.sh'
[IO.File]::WriteAllText($armPath, $arm, [Text.Encoding]::ASCII)
[void](AdbText @('push',$armPath,($remote+'/arm.sh')))
Write-Host ('REMOTE_STAGE: '+$remote)
Write-Host ('RECOVERY_IF_ARM_INTERRUPTED: adb shell mv '+$remote+'/original.params /data/ssh/params')
Write-Host (AdbText @('shell',('/system/bin/sh '+$remote+'/arm.sh')))
[void](AdbText @('shell',('touch '+$remote+'/host.ready')))
for ($i=0; $i -lt 210; $i++) {
    $ended = AdbText @('shell', ('if [ -f {0}/exit-code ]; then cat {0}/exit-code; fi' -f $remote))
    if ($ended -ne '') { Write-Host (AdbText @('shell',('cat '+$remote+'/session.log'))); ShowLog; throw ('Root worker ended: '+$ended) }
    $phase = ReadPhase
    if ($phase -ne $previousPhase) { Write-Host ('PHASE: '+$phase); $previousPhase=$phase }
    if ($phase -eq 'PERSISTENT_ACTIVE') { ShowLog; Write-Host 'ACTIVE_WITHOUT_TIMEOUT: menu patch running; reboot persistence still needs verification.'; exit 0 }
    if ($phase -eq 'ROLLED_BACK' -or $phase -like '*FAILED*' -or $phase -like '*REFUSED*' -or $phase -like '*CHANGED*' -or $phase -like '*UNCONFIRMED*') { ShowLog; throw ('Installation needs inspection: '+$phase) }
    Start-Sleep -Seconds 1
}
ShowLog
throw 'No confirmed persistent apply yet. Keep the receipt; send the output before restarting the SSH service.'
