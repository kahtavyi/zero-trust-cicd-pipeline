#!/bin/sh
# approle-setup.sh — create AppRole(s) and write role_id/secret_id to BOOTSTRAP_DIR/app-approle.env
# Usage: BOOTSTRAP_DIR=/bootstrap APP_UID=1000 APP_GID=1000 ./approle-setup.sh

set -eu

: "${BOOTSTRAP_DIR:=/bootstrap}"
: "${VAULT_ADDR:=http://vault:8200}"
: "${APPROLE_NAME:=app-role}"
: "${CIROLE_NAME:=ci-deploy}"
: "${APP_POLICY_PATH:=/vault-config/policies/app-read.hcl}"
: "${CI_POLICY_PATH:=/vault-config/policies/ci-deploy.hcl}"
: "${APP_UID:=1000}"
: "${APP_GID:=1000}"

export VAULT_ADDR

# wait for vault to be ready
printf '==> Waiting for Vault API...'
until vault status >/dev/null 2>&1; do
  sleep 1
done
echo " reachable."

# apply policies (idempotent)
if [ -f "$APP_POLICY_PATH" ]; then
  vault policy write app-read "$APP_POLICY_PATH"
fi
if [ -f "$CI_POLICY_PATH" ]; then
  vault policy write ci-deploy "$CI_POLICY_PATH"
fi

# enable approle if not enabled
if ! vault auth list -format=json | grep -q '"approle/"'; then
  vault auth enable approle
fi

# create app AppRole
vault write auth/approle/role/$APPROLE_NAME \
  token_policies="app-read" \
  token_ttl="1h" \
  token_max_ttl="4h" \
  secret_id_ttl="24h" \
  secret_id_num_uses="0"

# create ci AppRole
vault write auth/approle/role/$CIROLE_NAME \
  token_policies="ci-deploy" \
  token_ttl="20m" \
  token_max_ttl="1h" \
  secret_id_ttl="1h" \
  secret_id_num_uses="1"

# read role_id and secret_id for app role
ROLE_ID=$(vault read -field=role_id auth/approle/role/$APPROLE_NAME/role-id)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/$APPROLE_NAME/secret-id)

# write to bootstrap dir with restrictive permissions
mkdir -p "$BOOTSTRAP_DIR"
umask 077

cat > "$BOOTSTRAP_DIR/app-approle.env" <<EOF
VAULT_ROLE_ID=${ROLE_ID}
VAULT_SECRET_ID=${SECRET_ID}
EOF

if [ -n "${APP_UID:-}" ] && [ -n "${APP_GID:-}" ]; then
  chown "${APP_UID}:${APP_GID}" "$BOOTSTRAP_DIR/app-approle.env" || true
fi

chmod 600 "$BOOTSTRAP_DIR/app-approle.env"

echo "AppRole credentials written to $BOOTSTRAP_DIR/app-approle.env"
