# Local development: Odoo + MyERP mobile app

Run **native Odoo 15** + **native PostgreSQL** on your Mac (no Docker).

## Client demo database (recommended)

**Fictional data only** — no real customer records:

| Item | Demo value |
|------|------------|
| Database | `myerp_demo` |
| Companies | Company A, Company B |
| Products | Product A, Product B |
| PM | PM DEMO - Company A / B with sample done & to-do counts |
| Login | `demo@myerp.com` / `demo123` or `admin@sigmarectrix.com` / `admin123` |

```bash
cd "MyERP Web Odoo"
./setup-native-odoo15.sh           # once: Odoo + venv
./scripts/setup-demo-database.sh   # once: empty DB + dummy data (~15 min first time)
./run-local-odoo.sh
```

Web: http://localhost:8070/web?db=myerp_demo

To use the **real backup** again: `./setup-native-postgres.sh` then `DB_NAME=myerp_db ./run-local-odoo.sh`

## One-time setup (real backup — optional)

```bash
cd "MyERP Web Odoo"
./setup-native-odoo15.sh      # Odoo 15 source + Python venv
./setup-native-postgres.sh    # Restore myerp_db into Homebrew PostgreSQL
```

Requires **Python 3.10** (`brew install python@3.10`) and **PostgreSQL** (`brew install postgresql@16`).

## Start Odoo

```bash
./scripts/start-local-odoo.sh
```

- **ERP home:** http://localhost:8070/web?db=myerp_demo  
- **Login:** `demo@myerp.com` / `demo123` (demo) or `admin@sigmarectrix.com` / `admin123`  
- **Database:** `myerp_demo` (default). Real data: `DB_NAME=myerp_db ./run-local-odoo.sh`  
- **Postgres:** Homebrew on port `5432`, user `odoo`, password `odoo123`

Do **not** open `http://localhost:8070/` alone — that is the public website and may show theme errors. Use `/web?db=myerp_db`.

## Mobile app

**Recommended** (auto-detects Mac LAN IP for physical iPhone):

```bash
./scripts/flutter-run-local.sh
```

Or manually:

```bash
flutter run --dart-define=USE_LOCAL_ODOO=true --dart-define=ODOO_LOCAL_PORT=8070
```

Physical iPhone on Wi‑Fi: **do not use `127.0.0.1`** — use your Mac’s LAN IP:

```bash
flutter run --dart-define=USE_LOCAL_ODOO=true --dart-define=ODOO_LOCAL_HOST=192.168.x.x --dart-define=ODOO_LOCAL_PORT=8070
```

After switching from production to local, **log in again** (local password: `admin123`). PM should show cards like **RELA LTU** (1047 Done / 16 To Do), not Depulze with zeros.

Check the console on startup:

```text
🔗 Odoo server: http://192.168.x.x:8070 (db: myerp_db, local: true)
🔹 PM sample: PM RELA-LTU 1 done=1047 todo=16 @ http://...
```

Production:

```bash
flutter run --dart-define=USE_LOCAL_ODOO=false
```

## Stop

Ctrl+C in the Odoo terminal. PostgreSQL can keep running (`brew services stop postgresql@16` if you want to stop it).

## Data paths

| Path | Purpose |
|------|---------|
| `postgres-data/` | Old Docker PG data (optional; native uses Homebrew PG) |
| `odoo-data/.local/share/Odoo/filestore/` | Attachments (myerp_db) |
| `extra-addons/` | Helpdesk, Preventive Maintenance, etc. |
| `demo_myerp_backup.sql` | Source for `setup-native-postgres.sh` |

## Mobile API routes (Time Off)

Time Off uses `/api/leaves/*` controllers in the **`time_custom`** addon. After pulling changes:

```bash
cd "MyERP Web Odoo"
.venv/bin/python odoo_dist/odoo-bin -d myerp_db --config odoo-config/odoo.conf \
  --addons-path "odoo_dist/addons,default-addons,extra-addons" \
  --data-dir "odoo-data/.local/share/Odoo" -u time_custom --stop-after-init
./run-local-odoo.sh
```

## Troubleshooting

| Issue | What to try |
|-------|-------------|
| Database missing | Run `./setup-native-postgres.sh` |
| 500 on login | Run `./setup-native-odoo15.sh` again; restart `./run-local-odoo.sh` |
| Style error on `/` | Use `/web?db=myerp_db` (backend), not website root |
| App cannot connect on phone | Same Wi‑Fi, correct `ODOO_LOCAL_HOST`, firewall allows 8070 |
