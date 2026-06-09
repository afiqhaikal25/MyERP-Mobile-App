#!/usr/bin/env bash
# Start native Odoo 15 (Sigma-style) — real myerp_db UI on http://localhost:8070
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ODOO_DIR="$ROOT/MyERP Web Odoo"

if [[ ! -x "$ODOO_DIR/run-local-odoo.sh" ]]; then
  echo "Missing $ODOO_DIR/run-local-odoo.sh"
  exit 1
fi

if [[ ! -x "$ODOO_DIR/.venv/bin/python" ]]; then
  echo "First-time setup (clone Odoo 15 + venv)..."
  chmod +x "$ODOO_DIR/setup-native-odoo15.sh" "$ODOO_DIR/setup-native-postgres.sh" "$ODOO_DIR/run-local-odoo.sh"
  "$ODOO_DIR/setup-native-odoo15.sh"
fi

if ! PGPASSWORD=odoo123 psql -h 127.0.0.1 -p 5432 -U odoo -d myerp_db -c "SELECT 1" >/dev/null 2>&1; then
  echo "First-time database restore (native PostgreSQL)..."
  chmod +x "$ODOO_DIR/setup-native-postgres.sh"
  "$ODOO_DIR/setup-native-postgres.sh"
fi

chmod +x "$ODOO_DIR/run-local-odoo.sh"
exec "$ODOO_DIR/run-local-odoo.sh"
