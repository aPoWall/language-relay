#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
port="${LANGUAGE_RELAY_PREVIEW_PORT:-4177}"

if ! /usr/sbin/lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  /usr/bin/python3 -m http.server "$port" --bind 0.0.0.0 --directory "$project_dir/docs" \
    >"/tmp/language-relay-preview.log" 2>&1 &
fi

/usr/bin/open "http://localhost:$port"
