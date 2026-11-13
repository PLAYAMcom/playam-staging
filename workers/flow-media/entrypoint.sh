#!/bin/sh
set -eu
# Refresh ClamAV definitions before processing anything. Fail closed if update fails.
freshclam --stdout
# Confirm a usable signature database exists before starting the worker.
if ! clamscan --version >/dev/null 2>&1; then
  echo "ClamAV is unavailable; refusing to start" >&2
  exit 1
fi
exec gosu node:node node /app/worker.js
