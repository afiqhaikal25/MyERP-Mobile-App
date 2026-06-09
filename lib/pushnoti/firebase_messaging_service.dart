import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart'; // Import NotificationService
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';



class FirebaseMessagingService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    String? token = await _firebaseMessaging.getToken();
    print("🔥 FCM Token: $token");

    if (token != null) {
      await saveTokenToFirestore(token);
      await sendTokenToOdoo(token);
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("📩 Foreground Message: ${message.notification?.title}");
      
      NotificationService().sendLocalNotification(
        title: message.notification?.title ?? "New Ticket",
        body: message.notification?.body ?? "You have a new ticket!",
      );

      NotificationService.notifyNewTicket();
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("🔔 Notification Clicked: ${message.data}");
    });
  }


  Future<void> saveTokenToFirestore(String token) async {
    // Simpan token dalam Firestore (boleh ubah mengikut keperluan)
    await FirebaseFirestore.instance.collection('users').doc('user@example.com').set({
  'deviceToken': token,
}, SetOptions(merge: true));
  }

Future<void> sendTokenToOdoo(String token) async {
  final String odooUrl = 'https://myerp.com.my/api/update_fcm_token';

  // Load session_id from SharedPreferences (you need to store it at login)
  final prefs = await SharedPreferences.getInstance();
  final sessionId = prefs.getString('session_id');  // You must store this at login

  if (sessionId == null) {
    print("❌ No session ID found. Cannot send token.");
    return;
  }

  final Map<String, dynamic> requestBody = {
    "jsonrpc": "2.0",
    "method": "call",
    "params": {"token": token}
  };

  try {
    final response = await http.post(
      Uri.parse(odooUrl),
      headers: {
        "Content-Type": "application/json",
        "Cookie": "session_id=$sessionId",  // Include session in headers
      },
      body: jsonEncode(requestBody),
    );

    if (response.statusCode == 200) {
      print("✅ FCM Token berjaya dihantar ke Odoo!");
    } else {
      print("❌ Gagal hantar token ke Odoo: ${response.body}");
    }
  } catch (e) {
    print("❌ Error: $e");
  }
}


Future<void> sendPushNotification(String token, String title, String body) async {
  // TODO: Replace with your actual Firebase Server Key from Firebase Console
  // Go to Project Settings > Cloud Messaging > Server Key
  final String firebaseServerKey = 'YOUR_FIREBASE_SERVER_KEY_HERE';

  final Uri fcmUri = Uri.parse('https://fcm.googleapis.com/fcm/send');
  final headers = {
    'Content-Type': 'application/json',
    'Authorization': 'key=$firebaseServerKey',
  };

  final payload = {
    'to': token,
    'notification': {
      'title': title,
      'body': body,
      'sound': 'default',
    },
    'priority': 'high',
    'data': {  // 🔥 Tambah "data" supaya background notification boleh muncul
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'custom_data': 'new_ticket'
    },
  };

  final response = await http.post(
    fcmUri,
    headers: headers,
    body: jsonEncode(payload),
  );

  if (response.statusCode == 200) {
    debugPrint('✅ [PUSH NOTIFICATION] Berjaya dihantar!');
  } else {
    debugPrint('❌ [PUSH NOTIFICATION] Gagal dihantar: ${response.body}');
  }
}

}
