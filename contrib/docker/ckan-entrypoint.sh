#!/bin/sh
set -eu

# URL for the primary database, in the format expected by sqlalchemy (required
# unless linked to a container called 'db')
: ${DATABASE_URL:=}
# URL for solr (required unless linked to a container called 'solr')
: ${SOLR_URL:=}
# URL for redis (required unless linked to a container called 'redis')
: ${REDIS_URL:=}
# Email to which errors should be sent (optional, default: none)
: ${ERROR_EMAIL:=}

CONFIG="${CKAN_CONFIG}/ckan.ini"

abort () {
  echo "$@" >&2
  exit 1
}

write_config () {
  ckan-paster make-config ckan "$CONFIG"

  ckan-paster --plugin=ckan config-tool "$CONFIG" -e \
      "sqlalchemy.url = ${DATABASE_URL}" \
      "solr_url = ${SOLR_URL}" \
      "ckan.redis.url = ${REDIS_URL}" \
      "ckan.storage_path = /var/lib/ckan" \
      "email_to = disabled@example.com" \
      "error_email_from = ckan@$(hostname -f)" \
      "ckan.site_url = http://localhost:5000"

  if [ -n "$ERROR_EMAIL" ]; then
    sed -i -e "s&^#email_to.*&email_to = ${ERROR_EMAIL}&" "$CONFIG"
  fi
}

link_postgres_url () {
  local user=$DB_ENV_POSTGRES_USER
  local pass=$DB_ENV_POSTGRES_PASSWORD
  local db=$DB_ENV_POSTGRES_DB
  local host=$DB_PORT_5432_TCP_ADDR
  local port=$DB_PORT_5432_TCP_PORT
  echo "postgresql://${user}:${pass}@${host}:${port}/${db}"
}

link_solr_url () {
  local host=$SOLR_PORT_8983_TCP_ADDR
  local port=$SOLR_PORT_8983_TCP_PORT
  echo "http://${host}:${port}/solr/ckan"
}

link_redis_url () {
  local host=$REDIS_PORT_6379_TCP_ADDR
  local port=$REDIS_PORT_6379_TCP_PORT
  echo "redis://${host}:${port}/1"
}

# If we don't already have a config file, bootstrap
if [ ! -e "$CONFIG" ]; then

  if [ -z "$DATABASE_URL" ]; then
    if ! DATABASE_URL=$(link_postgres_url); then
      abort "ERROR: no DATABASE_URL specified and linked container called 'db' was not found"
    fi
  fi

  if [ -z "$SOLR_URL" ]; then
    if ! SOLR_URL=$(link_solr_url); then
      abort "ERROR: no SOLR_URL specified and linked container called 'solr' was not found"
    fi
  fi
    
  if [ -z "$REDIS_URL" ]; then
    if ! REDIS_URL=$(link_redis_url); then
      abort "ERROR: no REDIS_URL specified and linked container called 'redis' was not found"
    fi
  fi

  write_config

fi

ckan-paster --plugin=ckan db init -c "${CKAN_CONFIG}/ckan.ini"

exec "$@"
