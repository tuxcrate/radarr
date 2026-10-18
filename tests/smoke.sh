#!/bin/sh
set -eu

: "${1:?Expected application version is required}"
test "$(id -u)" -ne 0
test ! -w /opt/radarr
test -s /opt/radarr/LICENSE
test -s /usr/share/doc/radarr/SOURCE
/opt/radarr/ffprobe -version

scratch="$(mktemp -d)"
server_pid=
finish() {
    if [ -n "$server_pid" ]; then
        kill -TERM "$server_pid" 2>/dev/null || true
        wait "$server_pid" || true
    fi
    rm -rf "$scratch"
}
trap finish EXIT
trap 'exit 1' INT TERM

/opt/radarr/Radarr -nobrowser "-data=$scratch" > "$scratch/server.log" 2>&1 &
server_pid=$!
for attempt in $(seq 1 120); do
    if grep -q 'Now listening on:' "$scratch/server.log"; then
        grep -F "Version $1" "$scratch/server.log"
        test -s "$scratch/radarr.db"
        test -s "$scratch/config.xml"
        kill -TERM "$server_pid"
        wait "$server_pid"
        server_pid=
        exit 0
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        break
    fi
    sleep 1
done

cat "$scratch/server.log"
exit 1
