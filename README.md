# MyERP Mobile App (myerp.com.my)

Flutter mobile app for [myerp.com.my](https://myerp.com.my) — helpdesk, expenses, inventory, PM, projects, time off, and more.

**Repository:** [github.com/whsta/MyERP-Mobile-App---myerp.com.my](https://github.com/whsta/MyERP-Mobile-App---myerp.com.my)

## Requirements

- Flutter SDK 3.x (`flutter doctor`)
- Android Studio / Xcode (for device builds)
- Odoo account on `myerp.com.my` (employee linked to your user)
- Firebase project (push notifications — optional for local dev)

## Quick start

```bash
git clone https://github.com/whsta/MyERP-Mobile-App---myerp.com.my.git
cd MyERP-Mobile-App---myerp.com.my
flutter pub get
flutter run
```

## Odoo connection

Configured in `lib/odoo_service.dart`:

| Setting   | Value                      |
|-----------|----------------------------|
| Base URL  | `https://myerp.com.my`     |
| JSON-RPC  | `https://myerp.com.my/jsonrpc` |
| Database  | `myerp_db`                 |

Login uses email + password stored in `SharedPreferences` after successful Odoo authentication.

## Firebase (push notifications)

1. Place `android/app/google-services.json` from your Firebase console (not committed — see `.gitignore`).
2. `lib/firebase_options.dart` is generated via FlutterFire CLI.
3. FCM server key: `lib/pushnoti/serverkey.dart` (local only — copy from `serverkey.example.dart` if provided).

Without Firebase, the app still runs; push may be disabled.

## Odoo server module (optional)

`lib/helpdesk_ticket.py` adds mobile API routes (check-in, PM kanban, expense helpers, etc.). Deploy to your Odoo addons path and upgrade the module after changes.

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
| `helpdesk ticket/` | Tickets, check-in, feedback |
| `expenses.dart` | HR expenses & reports |
| `inventory.dart` | Product list from Odoo |
| `PM/` | Preventive maintenance |
| `project app/` | Projects & tasks |
| `time off app/` | Leave requests |
| `odoo_service.dart` | Odoo JSON-RPC & APIs |

## Troubleshooting

- **Login fails:** Check email/password and that `myerp_db` matches your Odoo database name.
- **Empty expense products:** Products must have **Can be expensed** in Odoo.
- **Empty inventory:** User needs Stock/Inventory read access on `product.product`.
- **PM list empty:** Deploy `helpdesk_ticket.py` mobile PM routes or grant PM groups in Odoo.

## License

Private — Sigma Rectrix / myerp.com.my.
