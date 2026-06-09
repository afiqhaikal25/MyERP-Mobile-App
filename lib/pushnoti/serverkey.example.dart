/// Copy this file to `serverkey.dart` and set your Firebase Cloud Messaging server key.
/// `serverkey.dart` is gitignored.
class ServerKey {
  static const String serverKey = 'YOUR_FCM_SERVER_KEY_HERE';

  Future<String> server_token() async => serverKey;
}
