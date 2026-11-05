#!/system/bin/sh
# One-shot root entry. Restore SSH params before beginning any APK work.
set -eu
umask 077
D=${0%/*}
[ "$(id -u)" = 0 ] || exit 20
mkdir "$D/once" 2>/dev/null || exit 0
[ -f "$D/original.params" ] && [ ! -L "$D/original.params" ] || exit 21
cmp -s /data/ssh/params "$D/request.params" || exit 22
mv "$D/original.params" /data/ssh/params
[ "$(stat -c '%u:%a:%s' /data/ssh/params)" = '0:600:0' ] || exit 23
# Keep the SSH proxy pipe open while writing diagnostic output to a file.
exec 3>&1
: > "$D/session.log"
chmod 644 "$D/session.log"
exec >> "$D/session.log" 2>&1
set +e
/system/bin/sh "$D/runtime-body.sh"
RC=$?
printf '%s\n' "$RC" > "$D/exit-code"
chmod 644 "$D/exit-code"
exit "$RC"
