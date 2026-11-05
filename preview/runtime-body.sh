#!/system/bin/sh
# Foreground five-minute preview; invoked by the validated vendor root channel.
set -eu
umask 077
D=${0%/*}
S=$D/private
TARGET=/system/priv-app/release_838_newsettings/release_838_newsettings.apk
PKG=com.android.newsettings
MAINT=com.amnesiaos.secure.controller/.oem.Z9xHbMaintenanceService
MOUNTED=0
SCRATCH_MOUNTED=0
STOPPED_SETTINGS=0
MAINT_STOPPED=0
CLEANED=0
OWN_MOUNT=
BEFORE_HASH=
phase() { printf '%s\n' "$1" > "$D/phase.tmp"; chmod 644 "$D/phase.tmp"; mv "$D/phase.tmp" "$D/phase"; }
hash() { sha256sum "$1" | awk '{print $1}'; }
mount_id() {
 exec 8< "$TARGET"
 awk '$1=="mnt_id:" {print $2}' /proc/self/fdinfo/8
 exec 8<&-
}
bounded() { timeout -k 2 20 "$@"; }
maintenance_running() {
 bounded dumpsys activity services "$MAINT" > "$D/maintenance-state.log" 2>&1 || return 2
 grep -q 'ServiceRecord{' "$D/maintenance-state.log"
}
start_settings() { bounded content query --user 0 --uri content://com.android.newsettings.lifecycle-process > "$D/provider.log" 2>&1 || true; }
settings_reads_file() {
 WANTED_INODE=$(stat -c '%i' "$1") || return 1
 for APID in $(pidof "$PKG" 2>/dev/null || true); do
  if [ "$(tr '\000' ' ' < /proc/"$APID"/cmdline | sed 's/ *$//')" = "$PKG" ] && awk -v inode="$WANTED_INODE" '$5==inode && /\.apk/ {found=1} END {exit !found}' /proc/"$APID"/maps; then return 0; fi
 done
 return 1
}
wait_loaded() {
 SUCCESSIVE=0; ATTEMPT=0
 while [ "$ATTEMPT" -lt 20 ]; do
  if settings_reads_file "$1"; then SUCCESSIVE=$((SUCCESSIVE+1)); else SUCCESSIVE=0; fi
  [ "$SUCCESSIVE" -lt 3 ] || return 0
  sleep 1; ATTEMPT=$((ATTEMPT+1))
 done
 return 1
}
rollback() {
 [ "$CLEANED" = 0 ] || return 0
 CLEANED=1
 phase ROLLING_BACK
 ROLLBACK_STATE=ROLLED_BACK
 if [ "$SCRATCH_MOUNTED" = 1 ]; then
  if [ "$(stat -c '%d:%i' "$S/mount-target")" = "$(stat -c '%d:%i' "$S/mount-source")" ] && umount -l "$S/mount-target"; then SCRATCH_MOUNTED=0; else ROLLBACK_STATE=PREFLIGHT_MOUNT_UNDO_FAILED; fi
 fi
 if [ "$MOUNTED" = 1 ]; then
  CURRENT=$(mount_id) || CURRENT=unknown
  # If recording failed immediately after mount, the unique private inode still anchors ownership.
  if { [ -n "$OWN_MOUNT" ] && [ "$CURRENT" != "$OWN_MOUNT" ]; } || [ "$(stat -c '%d:%i' "$TARGET")" != "$(stat -c '%d:%i' "$S/candidate.apk")" ]; then
   ROLLBACK_STATE=ROLLBACK_REFUSED_FOREIGN_MOUNT
   echo 'Visible mount changed independently; refusing to unmount it. Original snapshot retained.'
  elif bounded am force-stop --user 0 "$PKG" && umount -l "$TARGET"; then
   MOUNTED=0
  else
   ROLLBACK_STATE=ROLLBACK_UNMOUNT_FAILED
  fi
 fi
 if [ "$MOUNTED" = 0 ]; then
  if [ -n "$BEFORE_HASH" ] && [ "$(hash "$TARGET")" != "$BEFORE_HASH" ]; then
   ROLLBACK_STATE=ROLLBACK_BASELINE_CHANGED
   echo 'Underlying APK differs from the saved baseline; no further mount performed.'
  elif [ "$STOPPED_SETTINGS" = 1 ]; then
   start_settings
   STOPPED_SETTINGS=0
   if ! wait_loaded "$TARGET"; then ROLLBACK_STATE=ROLLBACK_PROCESS_UNCONFIRMED; fi
  fi
 fi
 # Always restore our own maintenance-service change, even if mount ownership was lost.
 if [ "$MAINT_STOPPED" = 1 ]; then
  if bounded am start-foreground-service --user 0 -n "$MAINT"; then MAINT_STOPPED=0; else ROLLBACK_STATE=MAINTENANCE_RESTART_FAILED; fi
 fi
 phase "$ROLLBACK_STATE"
 echo "$ROLLBACK_STATE"
 [ "$ROLLBACK_STATE" = ROLLED_BACK ]
}
main() {
 [ "$(id -u)" = 0 ] || exit 20
 [ "$(getprop ro.build.fingerprint)" = 'XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys' ] || exit 21
 [ "$(getprop sys.boot_completed)" = 1 ] || exit 22
 command -v timeout >/dev/null || { echo 'Bounded command runner unavailable'; exit 43; }
 [ "$(bounded pm path "$PKG")" = "package:$TARGET" ] || exit 23
 [ ! -L "$D" ] && [ -d "$D" ] || exit 24
 BEFORE_HASH=$(cat "$D/before.sha256")
 CANDIDATE_HASH=$(cat "$D/candidate.sha256")
 printf '%s\n' "$BEFORE_HASH" | grep -Eq '^[0-9a-f]{64}$' || exit 25
 printf '%s\n' "$CANDIDATE_HASH" | grep -Eq '^[0-9a-f]{64}$' || exit 26
 [ "$BEFORE_HASH" != "$CANDIDATE_HASH" ] || exit 27
 [ "$(hash "$TARGET")" = "$BEFORE_HASH" ] || { echo 'Current APK changed since backup'; exit 28; }
 [ "$(hash "$D/upload.apk")" = "$CANDIDATE_HASH" ] || exit 29
 mkdir "$S"
 chmod 700 "$S"
 cp "$TARGET" "$S/before.apk"
 [ "$(hash "$S/before.apk")" = "$BEFORE_HASH" ] || exit 30
 cp "$D/upload.apk" "$S/candidate.apk"
 chown 0:0 "$S/candidate.apk"
 chmod 644 "$S/candidate.apk"
 CONTEXT=$(ls -Zd "$TARGET" | awk '{print $1}')
 case "$CONTEXT" in u:object_r:*:s0) ;; *) exit 31 ;; esac
 chcon "$CONTEXT" "$S/candidate.apk"
 [ "$(hash "$S/candidate.apk")" = "$CANDIDATE_HASH" ] || exit 32
 # Verify bind and undo with private scratch files before stopping any service or replacing Settings.
 printf 'source\n' > "$S/mount-source"
 printf 'baseline\n' > "$S/mount-target"
 chcon "$CONTEXT" "$S/mount-source" "$S/mount-target"
 SCRATCH_BEFORE=$(stat -c '%d:%i' "$S/mount-target")
 mount -o bind "$S/mount-source" "$S/mount-target"
 SCRATCH_MOUNTED=1
 [ "$(stat -c '%d:%i' "$S/mount-source")" = "$(stat -c '%d:%i' "$S/mount-target")" ] || exit 45
 umount -l "$S/mount-target"
 SCRATCH_MOUNTED=0
 [ "$(stat -c '%d:%i' "$S/mount-target")" = "$SCRATCH_BEFORE" ] || exit 46
 phase PRIVATE_MOUNT_AND_UNDO_VERIFIED
 start_settings
 if ! wait_loaded "$TARGET"; then cat "$D/provider.log"; echo 'Baseline Settings process cannot be confirmed; no APK mount performed'; exit 42; fi
 phase BASELINE_SAVED
 if maintenance_running; then
  MAINT_STOPPED=1
  bounded am stopservice --user 0 -n "$MAINT"
  N=0
  while :; do
   if maintenance_running; then
    N=$((N+1)); [ "$N" -lt 15 ] || { echo 'Maintenance did not stop'; exit 33; }; sleep 1
   else
    QUERY_RC=$?
    [ "$QUERY_RC" = 1 ] || { echo 'Maintenance state is unknown'; exit 44; }
    break
   fi
  done
 else
  QUERY_RC=$?
  [ "$QUERY_RC" = 1 ] || { echo 'Initial maintenance state is unknown'; exit 44; }
 fi
 # Let an already dispatched native maintenance operation finish before mounting.
 N=0
 while pgrep -f '[Z]9xHbNativeSettings' >/dev/null 2>&1; do
  N=$((N+1)); [ "$N" -lt 20 ] || { echo 'Existing maintenance still active'; exit 34; }; sleep 1
 done
 [ "$(hash "$TARGET")" = "$BEFORE_HASH" ] || exit 35
 PREVIOUS_MOUNT=$(mount_id)
 printf '%s\n' "$PREVIOUS_MOUNT" | grep -Eq '^[0-9]+$' || exit 41
 # Refresh only this package; no reboot, no data clearing and no HOME reassignment.
 STOPPED_SETTINGS=1
 bounded am force-stop --user 0 "$PKG"
 mount -o bind "$S/candidate.apk" "$TARGET"
 MOUNTED=1
 OWN_MOUNT=$(mount_id)
 [ -n "$OWN_MOUNT" ] || exit 36
 printf '%s\n' "$OWN_MOUNT" > "$S/mount-id"
 [ "$(stat -c '%d:%i' "$TARGET")" = "$(stat -c '%d:%i' "$S/candidate.apk")" ] || exit 37
 [ "$(hash "$TARGET")" = "$CANDIDATE_HASH" ] || exit 38
 start_settings
 if ! wait_loaded "$S/candidate.apk"; then cat "$D/provider.log"; echo 'Settings did not load candidate inode; rolling back'; exit 39; fi
 phase APPLIED_5_MINUTES
 echo 'Preview active. Automatic rollback after five minutes.'
 T=0
 while [ "$T" -lt 300 ]; do
  if [ -f "$D/rollback.request" ] && [ "$(cat "$D/rollback.request")" = ROLLBACK ]; then break; fi
  [ "$(mount_id)" = "$OWN_MOUNT" ] || { echo 'Mount ownership changed during preview'; exit 40; }
  sleep 1; T=$((T+1))
 done
 rollback
}
trap 'RC=$?; if [ "$CLEANED" = 0 ]; then rollback || true; fi; exit "$RC"' EXIT
trap 'exit 130' HUP INT TERM
phase STARTING
main
