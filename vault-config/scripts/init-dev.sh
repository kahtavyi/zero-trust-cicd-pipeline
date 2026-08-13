#!/bin/sh
# Bootstrap Vault for local development.
# Runs once via the vault-init container after Vault and Postgres are healthy.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
VAULT_CONFIG_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

echo "==> Waiting for Vault API..."
until vault status >/dev/null 2>&1; do
  sleep 2
done
echo "    Vault is reachable."

echo "==> Applying Vault policies..."
vault policy write app-read "$VAULT_CONFIG_DIR/policies/app-read.hcl"
vault policy write ci-deploy "$VAULT_CONFIG_DIR/policies/ci-deploy.hcl"

echo "==> Enabling AppRole auth method..."
if ! vault auth list -format=json | grep -q '"approle/"'; then
  vault auth enable approle
fi

echo "==> Creating AppRole for FastAPI app..."
vault write auth/approle/role/app-role \
  token_policies="app-read" \
  token_ttl="1h" \
  token_max_ttl="4h" \
  secret_id_ttl="24h" \
  secret_id_num_uses="0"

echo "==> Creating AppRole for future CI deploy job..."
vault write auth/approle/role/ci-deploy \
  token_policies="ci-deploy" \
  token_ttl="20m" \
  token_max_ttl="1h" \
  secret_id_ttl="1h" \
  secret_id_num_uses="1"

APP_ROLE_ID=$(vault read -field=role_id auth/approle/role/app-role/role-id)
APP_SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/app-role/secret-id)
echo "    AppRole role_id: ${APP_ROLE_ID}"

if [ -n "${BOOTSTRAP_DIR:-}" ]; then
  mkdir -p "$BOOTSTRAP_DIR"
  umask 077
  cat > "$BOOTSTRAP_DIR/app-approle.env" <<EOF
VAULT_ROLE_ID=${APP_ROLE_ID}
VAULT_SECRET_ID=${APP_SECRET_ID}
EOF
  # App container runs as non-root; readable bootstrap is local-dev only.
  chmod 644 "$BOOTSTRAP_DIR/app-approle.env"
  echo "    AppRole credentials written to ${BOOTSTRAP_DIR}/app-approle.env"
fi

echo "==> Configuring database secrets engine..."
. "$SCRIPT_DIR/../secrets-engines/database-setup.sh"

echo "==> Vault dev bootstrap complete."
