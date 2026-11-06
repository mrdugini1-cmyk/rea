#!/system/bin/sh
set -eu
umask 077
D=${0%/*}
P=/data/z9x-ru-persistent
[ "$(id -u)" = 0 ] || exit 80
[ "$(getprop ro.build.fingerprint)" = 'XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys' ] || exit 81
[ ! -e "$P" ] && [ ! -L "$P" ] || { echo 'Persistent directory already exists; inspect or uninstall first'; exit 82; }
# Wait until the host has observed restoration of the temporary bootstrap params.
N=0
while [ ! -f "$D/host.ready" ]; do
 N=$((N+1)); [ "$N" -lt 60 ] || exit 83; sleep 1
done
[ ! -L /data/ssh/params ] && [ "$(stat -c '%u:%a:%s' /data/ssh/params)" = 0:600:0 ] || exit 84
[ "$(sha256sum "$D/upload.apk" | awk '{print $1}')" = "$(cat "$D/candidate.sha256")" ] || exit 85
[ "$(sha256sum /system/priv-app/release_838_newsettings/release_838_newsettings.apk | awk '{print $1}')" = "$(cat "$D/before.sha256")" ] || exit 86
mkdir "$P"
chmod 755 "$P"
for NAME in before.sha256 candidate.sha256 upload.apk persistent-worker.sh persistent-entry.sh; do
 cp "$D/$NAME" "$P/$NAME"
 chown 0:0 "$P/$NAME"
 chmod 600 "$P/$NAME"
done
chmod 700 "$P/persistent-entry.sh" "$P/persistent-worker.sh"
printf '%s\n' "$D" > "$P/control.path"
cp -p /data/ssh/params "$P/params.before"
printf '%s\n' "-oProxyCommand=$P/persistent-entry.sh -oStrictHostKeyChecking=yes -oUserKnownHostsFile=/dev/null -oGlobalKnownHostsFile=/dev/null -oBatchMode=yes -oConnectTimeout=0 127.0.0.1" > "$P/params.owned"
cp "$P/params.owned" "$P/params.next"
chmod 600 "$P/params.next"
: > "$P/session.log"
chmod 644 "$P/session.log"
[ ! -L /data/ssh/params ] && cmp -s /data/ssh/params "$P/params.before" || exit 87
mv "$P/params.next" /data/ssh/params
# Match the normal SSH directory ownership; no SSH keys are modified.
chown 0:0 "$P"
exec /system/bin/sh "$P/persistent-worker.sh" >> "$P/session.log" 2>&1
