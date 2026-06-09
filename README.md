# MyERP Mobile App (myerp.com.my)

Flutter mobile app for [myerp.com.my](https://myerp.com.my) — helpdesk, expenses, inventory, PM, projects, time off, and more.

**Repository:** [github.com/whsta/myerp.com.my](https://github.com/whsta/myerp.com.my) (branch `dev-hanep`)

## Requirements

- Flutter SDK 3.x (`flutter doctor`)
- Android Studio / Xcode (for device builds)
- Odoo account on `myerp.com.my` (employee linked to your user)
- Firebase project (push notifications — optional for local dev)

## Quick start

```bash
git clone https://github.com/whsta/myerp.com.my.git
cd myerp.com.my
git checkout dev-hanep
flutter pub get
flutter run
```

Production run:

```bash
./scripts/flutter-run-production.sh
```

## Odoo connection

Configured in `lib/config/odoo_config.dart`:

| Setting   | Production                 | Local dev                  |
|-----------|----------------------------|----------------------------|
| Base URL  | `https://myerp.com.my`     | `http://127.0.0.1:8069`    |
| JSON-RPC  | `…/jsonrpc`                | `…/jsonrpc`                |
| Database  | `myerp_db`                 | `demo_myerp`               |

**Local Odoo + mobile app:** [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md)

Login uses email + password stored in `SharedPreferences` after successful Odoo authentication.

## Firebase (push notifications)

1. Place `android/app/google-services.json` from your Firebase console (not committed — see `.gitignore`).
2. `lib/firebase_options.dart` is generated via FlutterFire CLI.
3. FCM server key: `lib/pushnoti/serverkey.dart` (local only — copy from `serverkey.example.dart`).

Without Firebase, the app still runs; push may be disabled.

## Odoo server module (optional)

`lib/helpdesk ticket/helpdesk odoo/helpdesk_ticket.py` adds mobile API routes. Deploy to your Odoo addons path and upgrade the module after changes.

## Build release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

Rename for distribution, e.g. `myerp.com Mobile App.apk`.

## Main app modules (`lib/`)

| Path | Feature |
|------|---------|
| `home.dart` | Dashboard & navigation |
| `config/odoo_config.dart` | Odoo URL / database config |
| `helpdesk ticket/` | Tickets, check-in, feedback |
| `expenses.dart` | HR expenses & reports |
| `inventory.dart` | Product list from Odoo |
| `PM/` | Preventive maintenance |
| `project app/` | Projects & tasks |
| `time off app/` | Leave requests |
| `odoo_service.dart` | Odoo JSON-RPC & APIs |

## Troubleshooting

- **Login fails:** Check email/password and database name in `odoo_config.dart`.
- **Empty expense products:** Products must have **Can be expensed** in Odoo.
- **Empty inventory:** User needs Stock/Inventory read access on `product.product`.
- **PM list empty:** Deploy helpdesk mobile PM routes or grant PM groups in Odoo.

## License

Private — Sigma Rectrix / myerp.com.my.
