#!/bin/sh
# Enable Vault database secrets engine and connect it to local PostgreSQL.
# Vault will create short-lived DB users on demand instead of using static passwords.

set -eu

: "${PG_HOST:=postgres}"
: "${PG_PORT:=5432}"
: "${PG_DB:=appdb}"
: "${PG_ADMIN_USER:=vaultadmin}"
: "${PG_ADMIN_PASSWORD:=vaultadmin}"

CONNECTION_URL="postgresql://{{username}}:{{password}}@${PG_HOST}:${PG_PORT}/${PG_DB}?sslmode=disable"

echo "    Enabling database secrets engine..."
if ! vault secrets list -format=json | grep -q '"database/"'; then
  vault secrets enable database
fi

echo "    Configuring PostgreSQL connection..."
vault write database/config/postgresql \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="$CONNECTION_URL" \
  username="$PG_ADMIN_USER" \
  password="$PG_ADMIN_PASSWORD"

echo "    Creating dynamic credential role 'app-role'..."
vault write database/roles/app-role \
  db_name=postgresql \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT CONNECT ON DATABASE ${PG_DB} TO \"{{name}}\"; GRANT USAGE ON SCHEMA public TO \"{{name}}\"; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_statements="REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\"; REVOKE USAGE ON SCHEMA public FROM \"{{name}}\"; REVOKE CONNECT ON DATABASE ${PG_DB} FROM \"{{name}}\"; DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

echo "    Database secrets engine ready."
