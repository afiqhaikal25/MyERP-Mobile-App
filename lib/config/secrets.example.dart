/// Template for local secrets.
/// Copy this file to `secrets.dart` and fill in your real values.
/// `secrets.dart` is gitignored so keys are never committed.
///
/// You can also override at build time:
///   flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key_here
class Secrets {
  /// Google Maps Geocoding / Directions API key.
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'YOUR_GOOGLE_MAPS_API_KEY',
  );
}
