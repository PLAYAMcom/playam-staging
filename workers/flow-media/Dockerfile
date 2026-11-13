FROM node:22-bookworm-slim
ENV NODE_ENV=production
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg clamav clamav-freshclam ca-certificates tini gosu && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY worker.js entrypoint.sh ./
RUN chmod 755 /app/entrypoint.sh && mkdir -p /work /var/lib/clamav && chown -R node:node /work /app
ENTRYPOINT ["tini","--","/app/entrypoint.sh"]