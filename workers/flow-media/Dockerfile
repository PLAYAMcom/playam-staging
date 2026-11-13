FROM node:22-bookworm-slim
ENV NODE_ENV=production
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg clamav clamav-freshclam ca-certificates tini && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY worker.js ./
RUN mkdir -p /work && chown -R node:node /work /app
USER node
ENTRYPOINT ["tini","--"]
CMD ["node","worker.js"]