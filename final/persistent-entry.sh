#!/system/bin/sh
set -eu
[ "$(id -u)" = 0 ] || exit 80
P=/data/z9x-ru-persistent
[ ! -L "$P" ] && [ "$(stat -c '%u:%a' "$P")" = 0:755 ] || exit 81
cmp -s /data/ssh/params "$P/params.owned" || exit 82
[ "$(getprop ro.build.fingerprint)" = 'XGIMI/Product_dapengfhm/goat_elegant:13/TP1A.220624.021.A1/v6.17.12:user/dev-keys' ] || exit 83
# Keep the vendor SSH ProxyCommand connection alive while this foreground worker runs.
exec 3>&1
exec /system/bin/sh "$P/persistent-worker.sh" >> "$P/session.log" 2>&1
