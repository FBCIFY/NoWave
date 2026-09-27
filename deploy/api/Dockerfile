FROM python:3.12-alpine@sha256:4c47124a8391cb7a9f571164147d154777cf012a4ece5f86097130d7a4478111 AS builder
WORKDIR /build
COPY backend/requirements.lock ./
RUN apk upgrade --no-cache && pip install --no-cache-dir --require-hashes --prefix=/install -r requirements.lock

FROM python:3.12-alpine@sha256:4c47124a8391cb7a9f571164147d154777cf012a4ece5f86097130d7a4478111
ARG NOWAVE_VERSION=development
LABEL org.opencontainers.image.source="https://github.com/FBCIFY/NoWave" org.opencontainers.image.revision="$NOWAVE_VERSION"
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 NOWAVE_VERSION=$NOWAVE_VERSION
RUN apk upgrade --no-cache && apk add --no-cache libstdc++ \
    && addgroup -S -g 10001 nowave && adduser -S -D -H -u 10001 -G nowave nowave \
    && python -m pip uninstall -y pip && rm -rf /usr/local/lib/python3.12/ensurepip
COPY --from=builder /install /usr/local
WORKDIR /app
COPY backend/app ./app
COPY backend/alembic ./alembic
COPY backend/alembic.ini ./
COPY deploy/hostinger/migrate.py ./migrate.py
USER 10001:10001
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=3)" || exit 1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log", "--no-server-header", "--no-proxy-headers", "--limit-concurrency", "80", "--timeout-keep-alive", "5"]
