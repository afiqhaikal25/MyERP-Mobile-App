#!/usr/bin/env bash
# Create myerp_demo with fictional data for client demos.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/MyERP Web Odoo"
exec ./scripts/setup-demo-database.sh "$@"
