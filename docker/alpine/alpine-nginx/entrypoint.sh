#!/bin/sh
set -e

nginx -g "daemon off;" &
nginx_pid=$!

trap 'kill -TERM "$nginx_pid" 2>/dev/null' TERM INT

latest_mtime() {
  find /etc/nginx -type f -exec stat -c '%Y' {} + 2>/dev/null | sort -n | tail -1
}

last=$(latest_mtime)

while kill -0 "$nginx_pid" 2>/dev/null; do
  sleep "${NGINX_RELOAD_INTERVAL:-5}"
  current=$(latest_mtime)
  if [ "$current" != "$last" ]; then
    if nginx -t 2>&1; then
      nginx -s reload
    fi
    last="$current"
  fi
done

wait "$nginx_pid"
