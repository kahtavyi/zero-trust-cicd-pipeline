#!/usr/bin/env bash
# docker-check.sh
# Quick verification script for local Docker Compose dev stack.
# Usage: ./scripts/docker-check.sh

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

echo "==> Bringing down any existing compose run (no-op if none)"
docker compose --profile dev down || true

echo "==> Starting compose (build & recreate)"
docker compose --profile dev up --build --force-recreate -d

echo "\n==> docker compose ps"
docker compose --profile dev ps

echo "\n==> last 200 lines: vault-init, vault, postgres, app"
docker compose --profile dev logs --tail=200 vault-init vault postgres app || true

# Try to extract root token from vault logs (dev mode prints it)
ROOT_TOKEN=$(docker compose --profile dev logs vault 2>/dev/null | sed -n "s/^.*Root Token: //p" | head -n1 || true)
if [ -n "$ROOT_TOKEN" ]; then
  echo "\n==> Vault root token found in logs (dev): ${ROOT_TOKEN}"
  echo "==> vault status (using extracted root token)"
  docker compose --profile dev exec vault sh -c "export VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='$ROOT_TOKEN' && vault status" || true
  echo "==> list AppRole roles (if any)"
  docker compose --profile dev exec vault sh -c "export VAULT_ADDR='http://127.0.0.1:8200' VAULT_TOKEN='$ROOT_TOKEN' && vault list auth/approle/role || true" || true
else
  echo "\n==> No root token found in vault logs; skipping vault CLI checks"
fi

echo "\n==> Check /bootstrap presence and app-approle.env in containers"
for svc in vault app postgres; do
  echo "--- $svc ---"
  docker compose --profile dev exec "$svc" sh -c "ls -l /bootstrap 2>/dev/null || echo '/bootstrap not found in container $svc'" || true
  docker compose --profile dev exec "$svc" sh -c "cat /bootstrap/app-approle.env 2>/dev/null || echo 'no app-approle.env in $svc'" || true
done

echo "\n==> Docker volumes (first 10)"
docker volume ls
docker volume ls -q | head -n 10 | xargs -I{} sh -c "echo '--- {} ---'; docker volume inspect {} | sed -n '1,6p'" || true

echo "\n==> Postgres health and list DBs/users"
docker compose --profile dev exec postgres sh -c 'pg_isready -U "$POSTGRES_USER" || true'
docker compose --profile dev exec postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\\l" || echo "psql failed"'

echo "\n==> HTTP health checks"
echo "- from host:"
curl -fsS http://127.0.0.1:8000/health || echo "host curl failed"
echo "- from inside app container:"
docker compose --profile dev exec app sh -c "curl -fsS http://127.0.0.1:8000/health || echo 'internal curl failed'" || true

echo "\n==> Running pytest inside app container (if pytest present)"
docker compose --profile dev exec app sh -c "pytest -q || echo 'pytest in container failed or not installed'" || true

cat <<'EOF'

==> Finished docker-check script.
Notes:
- vault-init may be a one-shot container that exits after writing bootstrap files to a volume. That's normal.
- If /bootstrap files are not found, consider removing named volumes and re-running the script.
EOF
