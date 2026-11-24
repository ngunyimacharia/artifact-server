#!/bin/sh
# Map Laravel Cloud's injected resource variables onto Artifact Server's own
# names, then run the given CLI subcommand. Explicit ARTIFACT_SERVER_* values
# always win, so any mapping can be overridden from the environment settings.
#
# Usage: sh deploy/laravel-cloud/run.sh migrate apply
#        sh deploy/laravel-cloud/run.sh start-external-storage

: "${ARTIFACT_SERVER_DATABASE_URL:=${DATABASE_URL:-}}"
# Laravel Serverless Postgres (Neon) requires TLS, but @effect/sql-pg only
# enables TLS when the URL carries sslmode. Append it when absent.
ssl_note="sslmode present"
case "$ARTIFACT_SERVER_DATABASE_URL" in
  *sslmode=*) ;;
  *\?*) ARTIFACT_SERVER_DATABASE_URL="${ARTIFACT_SERVER_DATABASE_URL}&sslmode=require"; ssl_note="sslmode=require appended" ;;
  ?*) ARTIFACT_SERVER_DATABASE_URL="${ARTIFACT_SERVER_DATABASE_URL}?sslmode=require"; ssl_note="sslmode=require appended" ;;
  *) ssl_note="no database url" ;;
esac
: "${ARTIFACT_SERVER_OBJECT_STORAGE_PROVIDER:=s3}"
: "${ARTIFACT_SERVER_S3_BUCKET:=${AWS_BUCKET:-}}"
: "${ARTIFACT_SERVER_S3_REGION:=${AWS_DEFAULT_REGION:-${AWS_REGION:-auto}}}"
: "${ARTIFACT_SERVER_S3_ENDPOINT:=${AWS_ENDPOINT_URL:-${AWS_ENDPOINT:-}}}"
: "${ARTIFACT_SERVER_S3_ACCESS_KEY_ID:=${AWS_ACCESS_KEY_ID:-}}"
: "${ARTIFACT_SERVER_S3_SECRET_ACCESS_KEY:=${AWS_SECRET_ACCESS_KEY:-}}"
: "${ARTIFACT_SERVER_S3_FORCE_PATH_STYLE:=${AWS_USE_PATH_STYLE_ENDPOINT:-false}}"
: "${ARTIFACT_SERVER_PORT:=${PORT:-3000}}"
: "${ARTIFACT_SERVER_HOST:=::}"

# Inside Laravel Cloud, ep-*.c-N.aws-REGION.pg.laravel.cloud resolves to Neon
# endpoints that present only *.c-N.REGION.aws.neon.tech certificates. Send the
# Neon name as SNI and verify against it (full verification stays on).
if [ -z "${ARTIFACT_SERVER_DATABASE_TLS_SERVERNAME:-}" ]; then
  db_host=$(printf %s "$ARTIFACT_SERVER_DATABASE_URL" | sed -E 's#^[a-z]+://([^@]*@)?([^:/?]+).*#\2#')
  ARTIFACT_SERVER_DATABASE_TLS_SERVERNAME=$(printf %s "$db_host" | sed -nE 's#^(ep-[^.]+)\.(c-[0-9]+)\.aws-([a-z0-9-]+)\.pg\.laravel\.cloud$#\1.\2.\3.aws.neon.tech#p')
fi
export ARTIFACT_SERVER_DATABASE_TLS_SERVERNAME
export ARTIFACT_SERVER_DATABASE_URL ARTIFACT_SERVER_OBJECT_STORAGE_PROVIDER \
  ARTIFACT_SERVER_S3_BUCKET ARTIFACT_SERVER_S3_REGION ARTIFACT_SERVER_S3_ENDPOINT \
  ARTIFACT_SERVER_S3_ACCESS_KEY_ID ARTIFACT_SERVER_S3_SECRET_ACCESS_KEY \
  ARTIFACT_SERVER_S3_FORCE_PATH_STYLE ARTIFACT_SERVER_PORT ARTIFACT_SERVER_HOST

echo "laravel-cloud/run.sh: node $(node --version), host ${ARTIFACT_SERVER_HOST}, port ${ARTIFACT_SERVER_PORT}, bucket ${ARTIFACT_SERVER_S3_BUCKET:-<unset>}, path-style ${ARTIFACT_SERVER_S3_FORCE_PATH_STYLE}, db ${ssl_note}, tls-servername ${ARTIFACT_SERVER_DATABASE_TLS_SERVERNAME:-<host>}"

if [ "$1" = "migrate" ] && [ "${ARTIFACT_SERVER_DB_PROBE:-1}" = "1" ]; then
  node "$(dirname "$0")/db-probe.mjs" || true
fi

exec node "$(dirname "$0")/../../dist/cli/main.js" "$@"
