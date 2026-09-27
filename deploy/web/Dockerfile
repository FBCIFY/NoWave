FROM node:24-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS build
WORKDIR /web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

FROM nginx:stable-alpine@sha256:0985e772fb9f729e6fa0980da05fca5d9c468e870eed43071545afa9d2e27d94
ARG NOWAVE_VERSION=development
LABEL org.opencontainers.image.source="https://github.com/FBCIFY/NoWave" org.opencontainers.image.revision="$NOWAVE_VERSION"
RUN apk upgrade --no-cache
COPY deploy/web/nginx.conf /etc/nginx/nginx.conf
COPY --from=build /web/dist/ /usr/share/nginx/html/
RUN printf '{"service":"nowave-web","version":"%s"}\n' "$NOWAVE_VERSION" > /usr/share/nginx/html/version.json
USER 101:101
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
ENTRYPOINT ["nginx", "-g", "daemon off;"]
