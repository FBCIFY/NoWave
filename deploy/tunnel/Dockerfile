FROM --platform=$BUILDPLATFORM golang:1.26.6-alpine@sha256:3889b425f035be855a72fb4755265311293b6d414521f0a519d819df32222d83 AS builder
ARG CLOUDFLARED_COMMIT=96d39adbc812dc7363834bda908970c1a2560a72
WORKDIR /src
RUN apk upgrade --no-cache && apk add --no-cache git
RUN git init && git remote add origin https://github.com/cloudflare/cloudflared.git \
    && git fetch --depth=1 origin "$CLOUDFLARED_COMMIT" && git checkout --detach "$CLOUDFLARED_COMMIT" \
    && test "$(git rev-parse HEAD)" = "$CLOUDFLARED_COMMIT"
ENV GOFLAGS=-mod=mod
RUN go get golang.org/x/crypto@v0.56.0 && go mod tidy \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go list -deps ./cmd/cloudflared > /tmp/dependencies \
    && if grep -E '^golang.org/x/crypto/openpgp(/|$)' /tmp/dependencies; then exit 1; fi \
    && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
       -ldflags='-s -w -X main.Version=2026.9.3-nowave.1 -X main.BuildTime=2026-09-27T00:00:00Z' \
       -o /cloudflared ./cmd/cloudflared

FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b
ARG NOWAVE_VERSION=development
LABEL org.opencontainers.image.source="https://github.com/FBCIFY/NoWave" org.opencontainers.image.revision="$NOWAVE_VERSION"
RUN apk upgrade --no-cache && apk add --no-cache ca-certificates
COPY --from=builder /cloudflared /usr/local/bin/cloudflared
USER 65532:65532
HEALTHCHECK --interval=20s --timeout=5s --start-period=30s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:2000/ready || exit 1
ENTRYPOINT ["cloudflared"]
