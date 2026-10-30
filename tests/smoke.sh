#!/bin/sh
set -eu

: "${1:?Expected application version is required}"
grep -Ex 'Branch=(master|develop)' /opt/package_info
test "$(id -u)" -ne 0
test ! -w /opt/radarr
test -s /opt/radarr/LICENSE
test -s /usr/share/doc/radarr/SOURCE
/opt/radarr/ffprobe -version

scratch="$(mktemp -d)"
server_pid=
phase='starting Radarr'
finish() {
    status=$?
    if [ -n "$server_pid" ]; then
        kill -TERM "$server_pid" 2>/dev/null || true
        wait "$server_pid" || true
    fi
    if [ "$status" -ne 0 ]; then
        printf 'Radarr smoke test failed while %s (exit status %s).\n' "$phase" "$status" >&2
        ls -la "$scratch" >&2 || true
        if [ -f "$scratch/server.log" ]; then
            cat "$scratch/server.log" >&2 || true
        fi
    fi
    rm -rf "$scratch"
    exit "$status"
}
trap finish EXIT
trap 'exit 1' INT TERM

/opt/radarr/Radarr -nobrowser "-data=$scratch" > "$scratch/server.log" 2>&1 &
server_pid=$!
phase='waiting for Radarr to listen and create nonempty radarr.db and config.xml'
attempt=0
while :; do
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo 'Radarr exited before becoming ready.' >&2
        exit 1
    fi
    if grep -q 'Now listening on:' "$scratch/server.log" \
        && test -s "$scratch/radarr.db" \
        && test -s "$scratch/config.xml"; then
        break
    fi
    if [ "$attempt" -ge 120 ]; then
        echo 'Timed out waiting for Radarr readiness.' >&2
        exit 1
    fi
    attempt=$((attempt + 1))
    sleep 1
done

phase='checking the installed version'
grep -F "Version $1" "$scratch/server.log"
phase='stopping Radarr'
kill -TERM "$server_pid"
if wait "$server_pid"; then
    server_pid=
else
    status=$?
    server_pid=
    printf 'Radarr shutdown returned exit status %s.\n' "$status" >&2
    exit "$status"
fi
