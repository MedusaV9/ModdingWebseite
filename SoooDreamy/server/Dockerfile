# SoooDreamy server — tiny self-hosted couple server.
#   docker build -t sooodreamy-server .
#   docker run -d --name sooodreamy -p 4321:4321 -v sooodreamy-data:/app/data sooodreamy-server
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
ENV PORT=4321 HOST=0.0.0.0 DATA_DIR=/app/data
EXPOSE 4321
VOLUME ["/app/data"]
# Restart-on-hang for docker-compose/orchestrators (`restart: unless-stopped`).
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://127.0.0.1:4321/api/health || exit 1
CMD ["node", "src/server.js"]
