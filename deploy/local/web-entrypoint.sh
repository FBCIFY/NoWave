#!/bin/sh
set -eu
envsubst '$NOWAVE_WEB_HTTPS_PORT' < /etc/nginx/local.conf.template > /tmp/nginx-local.conf
exec nginx -c /tmp/nginx-local.conf -g 'daemon off;'
