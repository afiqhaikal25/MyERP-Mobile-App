/// Odoo server endpoints for the mobile app.
///
/// Local dev (physical iPhone on same Wi‑Fi as your Mac):
///   flutter run --dart-define=USE_LOCAL_ODOO=true --dart-define=ODOO_LOCAL_HOST=192.168.1.10
///
/// Local dev (iOS Simulator / Android emulator on this machine):
///   flutter run --dart-define=USE_LOCAL_ODOO=true
///   (Simulator: 127.0.0.1 works. Android emulator: use 10.0.2.2)
///
/// Production:
///   flutter run
///   or: --dart-define=USE_LOCAL_ODOO=false
class OdooConfig {
  /// Set true when native Odoo 15 is running (./MyERP Web Odoo/run-local-odoo.sh).
  static const bool useLocal = bool.fromEnvironment(
    'USE_LOCAL_ODOO',
    defaultValue: false,
  );

  /// Mac LAN IP when testing on a physical phone (not localhost).
  static const String localHost = String.fromEnvironment(
    'ODOO_LOCAL_HOST',
    defaultValue: '127.0.0.1',
  );

  /// Native Odoo 15 (Sigma-style) uses 8070; Docker fallback used 8069.
  static const int localPort = int.fromEnvironment(
    'ODOO_LOCAL_PORT',
    defaultValue: 8070,
  );

  static const String database = String.fromEnvironment(
    'ODOO_DB',
    defaultValue: 'myerp_demo',
  );

  static const String productionBaseUrl = 'https://myerp.com.my';
  static const String productionDatabase = 'myerp_db';

  static String get baseUrl =>
      useLocal ? 'http://$localHost:$localPort' : productionBaseUrl;

  static String get jsonRpcUrl => '$baseUrl/jsonrpc';

  static String get activeDatabase =>
      useLocal ? database : productionDatabase;
}
