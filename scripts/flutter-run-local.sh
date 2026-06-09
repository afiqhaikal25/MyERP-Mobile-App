#!/usr/bin/env bash
# Mobile app → local Odoo 15 on http://HOST:8070 (myerp_db).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB="${ODOO_DB:-myerp_demo}"
PORT="${ODOO_LOCAL_PORT:-8070}"

# Prefer Mac LAN IP so physical iPhones can reach Odoo (127.0.0.1 is the phone itself).
if [[ -n "${ODOO_LOCAL_HOST:-}" ]]; then
  HOST="$ODOO_LOCAL_HOST"
else
  HOST="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  HOST="${HOST:-127.0.0.1}"
fi

echo "Flutter → http://$HOST:$PORT (db: $DB)"
echo "Login: admin@sigmarectrix.com / admin123"
echo "Ensure Odoo is running: cd \"MyERP Web Odoo\" && ./run-local-odoo.sh"
echo ""

cd "$ROOT"
exec flutter run \
  --dart-define=USE_LOCAL_ODOO=true \
  --dart-define=ODOO_LOCAL_HOST="$HOST" \
  --dart-define=ODOO_LOCAL_PORT="$PORT" \
  --dart-define=ODOO_DB="$DB" \
  "$@"
