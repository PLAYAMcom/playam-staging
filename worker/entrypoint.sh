#!/bin/sh
set -eu
# Fail closed: if definitions cannot be refreshed or clamd cannot answer,
# the worker does not start and media stays quarantined.
freshclam --stdout || exit 1
sed -i 's/^#TCPSocket 3310/TCPSocket 3310/' /etc/clamav/clamd.conf
sed -i 's/^#TCPAddr 127.0.0.1/TCPAddr 127.0.0.1/' /etc/clamav/clamd.conf
clamav-daemon
i=0
until python -c "import socket; s=socket.create_connection(('127.0.0.1',3310),2); s.close()" 2>/dev/null; do
  i=$((i+1)); [ "$i" -lt 30 ] || exit 1; sleep 2
done
exec python /app/worker.py
