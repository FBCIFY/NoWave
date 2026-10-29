FROM postgis/postgis:17-3.5-alpine@sha256:894f570c0cf0664ed5576a8fd5d5bfb8fb1b19d592885b686c3a88c8bd90c41f
ARG NOWAVE_VERSION=development
LABEL org.opencontainers.image.source="https://github.com/FBCIFY/NoWave" org.opencontainers.image.revision="$NOWAVE_VERSION"
RUN apk upgrade --no-cache && rm -f /usr/local/bin/gosu
USER 70:70
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=5 CMD pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" || exit 1
