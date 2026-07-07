# MyERP Mobile App

A cross-platform **Flutter** mobile app for the MyERP (Odoo-based) enterprise system — bringing helpdesk, expenses, inventory, preventive maintenance, projects, and HR workflows to iOS & Android.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-3DDC84)
![Backend](https://img.shields.io/badge/Backend-Odoo%20JSON--RPC-714B67)

> Mobile client that connects to an Odoo ERP backend over JSON-RPC, with Firebase Cloud Messaging for real-time push notifications.

---

## Overview

MyERP Mobile lets field staff and office users work on the go: raise and resolve helpdesk tickets (with GPS check-in), submit expense claims, browse inventory, track preventive maintenance visits, manage projects and tasks, and apply for time off — all synced with the Odoo ERP backend.

## Key features

| Module | Highlights |
|--------|-----------|
| **Helpdesk** | Ticket list & details, GPS check-in / check-out, feedback & ratings, resolution tracking |
| **Expenses** | Create expense claims, attach receipts, expense reports, submit for approval |
| **Inventory** | Product catalogue from Odoo with price & on-hand quantity |
| **Preventive Maintenance** | PM schedules, maintenance requests, collection & UAT flows |
| **Projects & Tasks** | Projects, tasks, subtasks, OKRs |
| **Time Off** | Leave requests & approvals |
| **Notifications** | Firebase Cloud Messaging push for tickets, tasks, and approvals |

## Tech stack

- **Framework:** Flutter (Dart)
- **Backend:** Odoo ERP via JSON-RPC (`/jsonrpc`)
- **Auth/session:** email + password, session stored in `SharedPreferences`
- **Push:** Firebase Cloud Messaging + local notifications
- **Location:** Geolocator / Geocoding (GPS check-in)
- **Files:** file_picker, image_picker, PDF viewing

## Project structure

```
lib/
├─ main.dart                 # App entry, Firebase & startup wiring
├─ home.dart                 # Dashboard & navigation
├─ config/odoo_config.dart   # Odoo URL / database (prod & local dev)
├─ odoo_service.dart         # Odoo JSON-RPC client & API layer
├─ helpdesk ticket/          # Tickets, check-in, feedback
├─ expenses.dart             # HR expenses & reports
├─ inventory.dart            # Product list from Odoo
├─ PM/                       # Preventive maintenance
├─ project app/              # Projects, tasks, OKRs
├─ time off app/             # Leave requests
└─ pushnoti/                 # FCM & notification services
```

## Getting started

```bash
git clone https://github.com/afiqhaikal25/MyERP-Mobile-App.git
cd MyERP-Mobile-App
flutter pub get
flutter run
```

### Configuration (kept out of version control)

Secrets are **not** committed. Copy the example files and fill in your own values:

| Needed file | From template | Notes |
|-------------|---------------|-------|
| `lib/config/secrets.dart` | `secrets.example.dart` | Google Maps API key |
| `lib/firebase_options.dart` | `firebase_options.example.dart` | or run `flutterfire configure` |
| `lib/pushnoti/serverkey.dart` | `serverkey.example.dart` | FCM server key |
| `android/app/google-services.json` | Firebase console | Android push config |

You can also override the maps key at build time:

```bash
flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key_here
```

### Build a release APK

```bash
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

## Quality & testing notes

- Configuration is environment-driven (`OdooConfig`) so the same build targets **production** or a **local Odoo** instance without code changes.
- Secrets are isolated in gitignored files with committed `*.example.dart` templates — safe for public repos.
- API failures degrade gracefully (empty states, retry actions, guarded `mounted` checks) rather than crashing.
- Manual test flows and local Odoo setup are documented in [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md).

## Screenshots

_Add screenshots here (e.g. `docs/screens/*.png`) to showcase the UI._

## Author

**Afiq Haikal** — [github.com/afiqhaikal25](https://github.com/afiqhaikal25)

## License

Private project — shared for portfolio / demonstration purposes.
