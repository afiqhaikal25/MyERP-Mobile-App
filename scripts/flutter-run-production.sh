#!/usr/bin/env bash
# Mobile app → production Odoo 15 (myerp.com.my). Use this on Mac until local Odoo 15 runs on Linux.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
exec flutter run --dart-define=USE_LOCAL_ODOO=false "$@"
