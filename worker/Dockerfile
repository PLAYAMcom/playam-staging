FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg clamav clamav-daemon ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY worker.py entrypoint.sh ./
RUN chmod +x /app/entrypoint.sh && mkdir -p /var/lib/clamav /run/clamav /tmp/playam-worker
ENV CLAMD_HOST=127.0.0.1 CLAMD_PORT=3310
ENTRYPOINT ["/app/entrypoint.sh"]
