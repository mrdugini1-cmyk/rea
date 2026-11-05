#!/system/bin/sh
# Read-only APK/namespace diagnostics, entered through the existing root wrapper.
set -u
D=${0%/*}
TARGET=/system/priv-app/release_838_newsettings/release_838_newsettings.apk
printf 'DIAG_START\n'
id
printf 'EXPECTED_BEFORE='; cat "$D/before.sha256"
printf 'EXPECTED_CANDIDATE='; cat "$D/candidate.sha256"
printf 'SELF_MOUNT_NS='; readlink /proc/self/ns/mnt || true
printf 'NSENTER='; command -v nsenter || true
printf 'HASH_COMMAND_TYPE_BEFORE='; type hash || true
hash() { sha256sum "$1" | awk '{print $1}'; }
printf 'HASH_COMMAND_TYPE_AFTER='; type hash || true
printf 'HASH_FUNCTION_SAMPLE='; hash "$TARGET" || true
for N in 1 2 3; do
 printf 'ROOT_APK_SAMPLE_%s=' "$N"
 sha256sum "$TARGET" || true
 sleep 0.3
done
PIDS="1 $(pidof adbd 2>/dev/null) $(pidof zygote64 2>/dev/null) $(pidof zygote 2>/dev/null) $(pidof system_server 2>/dev/null) $(pidof com.android.newsettings 2>/dev/null) $(pidof com.amnesiaos.secure.controller 2>/dev/null)"
for P in $(printf '%s\n' "$PIDS" | tr ' ' '\n' | sort -nu); do
 case "$P" in ''|*[!0-9]*) continue ;; esac
 [ -d /proc/"$P" ] || continue
 printf '\nPID=%s NAME=' "$P"
 tr '\000' ' ' < /proc/"$P"/cmdline 2>/dev/null | cut -c 1-160
 printf 'MOUNT_NS='; readlink /proc/"$P"/ns/mnt || true
 printf 'PROCESS_ROOT_APK_INODE='; stat -c '%d:%i' /proc/"$P"/root"$TARGET" || true
 if [ "$(tr '\000' ' ' < /proc/"$P"/cmdline 2>/dev/null | sed 's/ *$//')" = com.android.newsettings ]; then
  awk '/release_838_newsettings\.apk|settings-25[^ ]*\.apk|settings-ru[^ ]*\.apk|candidate\.apk/ {print "APK_MAPPING dev=" $4, "inode=" $5, "path=" $6}' /proc/"$P"/maps | sort -u | head -n 10 || true
 fi
 printf 'PROCESS_ROOT_APK='; sha256sum /proc/"$P"/root"$TARGET" || true
 if command -v nsenter >/dev/null && command -v timeout >/dev/null; then
  printf 'NSENTER_APK='
  timeout -k 2 10 nsenter -t "$P" -m -- /system/bin/sha256sum "$TARGET" || true
 fi
done
printf '\nDIAG_END\n'
printf 'DIAGNOSTIC_DONE\n' > "$D/phase.tmp"
chmod 644 "$D/phase.tmp"
mv "$D/phase.tmp" "$D/phase"
