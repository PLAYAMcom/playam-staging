FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg clamav clamav-daemon ca-certificates gosu && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --create-home --shell /usr/sbin/nologin playam-worker
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py entrypoint.sh ./
RUN chmod 755 /app/entrypoint.sh && mkdir -p /var/lib/clamav /run/clamav /tmp/playam-worker \
 && chown -R clamav:clamav /var/lib/clamav /run/clamav \
 && chown -R playam-worker:playam-worker /app /tmp/playam-worker
ENV CLAMD_HOST=127.0.0.1 CLAMD_PORT=3310
ENTRYPOINT ["/app/entrypoint.sh"]