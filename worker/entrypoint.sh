#!/bin/sh
set -eu
# Fail closed: if definitions cannot be refreshed or clamd cannot answer,
# the worker does not start and media stays quarantined.
chown -R clamav:clamav /var/lib/clamav /run/clamav
mkdir -p /tmp/clamav
chown clamav:clamav /tmp/clamav
chmod 0750 /tmp/clamav
freshclam --stdout || exit 1

# Compose mounts the root filesystem read-only. Generate ClamAV's runtime
# configuration under /run, which is an explicitly writable, size-limited tmpfs.
cat > /run/clamav/clamd.conf <<'CLAMD_CONFIG'
DatabaseDirectory /var/lib/clamav
PidFile /dev/null
User clamav
TCPSocket 3310
TCPAddr 127.0.0.1
StreamMaxLength 110M
MaxFileSize 110M
MaxScanSize 200M
MaxThreads 1
MaxQueue 2
ReadTimeout 120
CLAMD_CONFIG
chown clamav:clamav /run/clamav/clamd.conf
chmod 0640 /run/clamav/clamd.conf

clamd --config-file=/run/clamav/clamd.conf
i=0
until python -c "import socket; s=socket.create_connection(('127.0.0.1',3310),2); s.close()" 2>/dev/null; do
  i=$((i+1)); [ "$i" -lt 30 ] || exit 1; sleep 2
done
exec gosu playam-worker:playam-worker python /app/worker.py
