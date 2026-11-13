#!/bin/sh
set -eu
# Fail closed: if definitions cannot be refreshed or clamd cannot answer,
# the worker does not start and media stays quarantined.
chown -R clamav:clamav /var/lib/clamav /run/clamav
freshclam --stdout || exit 1
grep -q '^TCPSocket ' /etc/clamav/clamd.conf || printf '\nTCPSocket 3310\n' >> /etc/clamav/clamd.conf
grep -q '^TCPAddr ' /etc/clamav/clamd.conf || printf 'TCPAddr 127.0.0.1\n' >> /etc/clamav/clamd.conf
sed -i '/^StreamMaxLength /d; /^MaxFileSize /d; /^MaxScanSize /d' /etc/clamav/clamd.conf
printf 'StreamMaxLength 110M\nMaxFileSize 110M\nMaxScanSize 200M\n' >> /etc/clamav/clamd.conf
clamd
i=0
until python -c "import socket; s=socket.create_connection(('127.0.0.1',3310),2); s.close()" 2>/dev/null; do
  i=$((i+1)); [ "$i" -lt 30 ] || exit 1; sleep 2
done
exec python /app/worker.py
