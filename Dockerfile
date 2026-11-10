FROM oven/bun:1.4.4 AS build
WORKDIR /app
COPY . .
RUN bun install --frozen-lockfile
RUN bun run web:build
RUN bun build packages/server/src/index.ts --target=bun --outfile=dist/server.js --external bun:sqlite

FROM oven/bun:1.4.4-slim
WORKDIR /app
COPY --from=build /app/dist/server.js ./server.js
COPY --from=build /app/packages/web/dist ./web
ENV PORT=4096 BADB_DB=/data/badb.sqlite BADB_WEB=/app/web
EXPOSE 4096
VOLUME ["/data"]
CMD ["bun", "server.js"]
