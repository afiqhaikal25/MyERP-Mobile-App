import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpdesk ticket/ticket.dart'; // Added import for TicketPage
import '../time off app/timeoff.dart'; // Added import for TimeOffPage

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  static final StreamController<void> _onNewTicketController = StreamController.broadcast();
  static Stream<void> get onNewTicket => _onNewTicketController.stream;

  static void notifyNewTicket() {
    print("🔔 New ticket event triggered!");
    _onNewTicketController.add(null);
  }

  late FirebaseMessaging _firebaseMessaging;
  late FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin;
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  NotificationService._internal();

  Future<void> initialize() async {
    _firebaseMessaging = FirebaseMessaging.instance;
    _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    await _requestPermission();
    await _setupLocalNotifications();
    await _registerNotificationHandlers();
    await _saveTokenToFirestore();
  }

  Future<void> _requestPermission() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 [NOTIFICATION PERMISSION] Status: ${settings.authorizationStatus}');
  }

Future<void> _setupLocalNotifications() async {
  final androidInitializationSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const DarwinInitializationSettings iosInitializationSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  final initializationSettings = InitializationSettings(
    android: androidInitializationSettings,
    iOS: iosInitializationSettings,
  );

  await _flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: onDidReceiveBackgroundNotificationResponse,
  );

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'default_channel',
  'Default Channel',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  await _flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}


  Future<void> _registerNotificationHandlers() async {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final ticketId = message.data['ticket_id']?.toString();
      final notificationType = message.data['type']?.toString();
      final leaveId = message.data['leave_id']?.toString();
      
      String title;
      String body;
      
      // Handle Time Off notifications
      if (notificationType == 'timeoff_approved') {
        title = message.notification?.title ?? "Time Off Approved";
        body = message.notification?.body ?? "Your time off request has been approved";
        
        // Trigger UI update for Time Off page
        notifyNewTicket(); // Reuse existing notification system
        
        await sendLocalNotification(
          title: title,
          body: body,
        );
        
        print("📩 Time Off notification received: $title - $body");
        return;
      }
      
      // Handle Time Off first approval notifications
      if (notificationType == 'timeoff_first_approved') {
        title = message.notification?.title ?? "Time Off First Approval";
        body = message.notification?.body ?? "Your time off request has been approved by first approver";
        
        // Trigger UI update for Time Off page
        notifyNewTicket();
        
        await sendLocalNotification(
          title: title,
          body: body,
        );
        
        print("📩 Time Off first approval notification received: $title - $body");
        return;
      }
      
      // Handle Time Off refused notifications
      if (notificationType == 'timeoff_refused') {
        title = message.notification?.title ?? "Time Off Refused";
        body = message.notification?.body ?? "Your time off request has been refused";
        
        // Trigger UI update for Time Off page
        notifyNewTicket();
        
        await sendLocalNotification(
          title: title,
          body: body,
        );
        
        print("📩 Time Off refused notification received: $title - $body");
        return;
      }
      
      // Handle Ticket notifications (existing code)
      if (ticketId != null && ticketId.isNotEmpty && ticketId != '0') {
        title = "New Ticket #$ticketId";
        await addPendingCheckInTicket(ticketId); // Add to pending list
        startCheckInReminderTimer(); // Start reminder timer
        // Set badge for new ticket
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hasNewTicket', true);
      } else {
        title = message.notification?.title ?? "New Ticket";
      }
      body = message.notification?.body ?? "You have a new ticket!";

      notifyNewTicket();
      NotificationService.notifyNewTicket();

      await sendLocalNotification(
        title: title,
        body: body,
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedAppHandler);
  }

  Future<void> _saveTokenToFirestore() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        // Save token locally only - skip Firestore to avoid permission issues
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token_${user.email}', token);
        
        // Get saved Gmail for notifications
        final String? gmailForNotifications = prefs.getString('push_notification_gmail_${user.email}');
        
        debugPrint('✅ FCM token saved locally: $token');
        debugPrint('✅ Gmail for notifications: $gmailForNotifications');
      }
    } catch (e) {
      debugPrint('❌ Failed to save FCM token: $e');
    }
  }

  // Method to get saved Gmail for notifications
  static Future<String?> getGmailForNotifications(String userEmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('push_notification_gmail_$userEmail');
    } catch (e) {
      debugPrint('❌ Error getting Gmail for notifications: $e');
      return null;
    }
  }

  // Method to update Gmail for notifications
  static Future<void> updateGmailForNotifications(String userEmail, String gmail) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('push_notification_gmail_$userEmail', gmail);
      
      // Skip Firestore to avoid permission issues
      // Firestore is only used for server-side push notifications
      // If you don't need server-side notifications, SharedPreferences is sufficient
      
      debugPrint('✅ Gmail for notifications updated (SharedPreferences only): $gmail');
    } catch (e) {
      debugPrint('❌ Error updating Gmail for notifications: $e');
    }
  }

  Future<void> _onMessageHandler(RemoteMessage message) async {
  print("📩 Foreground Notifikasi: ${message.notification?.title}");

  // Pastikan UI mendapat isyarat untuk kemas kini
  notifyNewTicket();

  // Tunjukkan notifikasi dalam aplikasi
  _showNotification(
    title: message.notification?.title ?? "New Ticket Assigned",
    body: message.notification?.body ?? "You have a new ticket!",
    payload: jsonEncode(message.data),
  );
}

static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📩 [BACKGROUND] Notifikasi diterima: ${message.notification?.title}');
  
  // Handle Time Off notifications in background
  final notificationType = message.data['type']?.toString();
  if (notificationType == 'timeoff_approved') {
    NotificationService().sendLocalNotification(
      title: message.notification?.title ?? "Time Off Approved",
      body: message.notification?.body ?? "Your time off request has been approved",
    );
    print("📩 [BACKGROUND] Time Off notification handled");
    return;
  }
  
  // Handle Ticket notifications (existing code)
  NotificationService().sendLocalNotification(
    title: "New Ticket Alert",
    body: "You have a new ticket!",
  );

  NotificationService.notifyNewTicket(); // 🚨 Trigger UI update
}






  Future<void> _onNotificationResponse(NotificationResponse response) async {
    if (response.payload != null) {
      _handleNavigation(jsonDecode(response.payload!));
    }
  }



  Future<void> _onMessageOpenedAppHandler(RemoteMessage message) async {
    final ticketId = message.data['ticket_id'];
    final notificationType = message.data['type']?.toString();
    final leaveId = message.data['leave_id'];
    
    // Handle Time Off notifications
    if (notificationType == 'timeoff_approved') {
      // Navigate to Time Off page
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const TimeOffPage(),
        ),
        (route) => false,
      );
      print("📩 Time Off notification clicked, navigating to Time Off page");
      return;
    }
    
    // Handle Ticket notifications (existing code)
    if (ticketId != null && ticketId.toString().isNotEmpty && ticketId != '0') {
      // Get email & password from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('email') ?? '';
      final password = prefs.getString('password') ?? '';
      // Set badge for new ticket (in case user opens from notification tray)
      await prefs.setBool('hasNewTicket', true);
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => TicketPage(
            email: email,
            password: password,
          ),
        ),
        (route) => false,
      );
    }
  }

  Future<void> _showNotification({
    required String title,
    required String body,
    required String payload,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'Default Channel',
      channelDescription: 'Saluran notifikasi utama',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformDetails,
      payload: payload,
    );
  }

  void _handleNavigation(Map<String, dynamic> data) {
    final String? route = data['route'];
    if (route != null && navigatorKey.currentState != null) {
      navigatorKey.currentState!.pushNamed(route, arguments: data);
    }
  }

  Future<void> sendPushNotification(String token, String title, String body) async {
    // TODO: Replace with your actual Firebase Server Key from Firebase Console
    const String firebaseServerKey = 'YOUR_FIREBASE_SERVER_KEY_HERE';

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
      'data': {
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
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

  Future<void> sendLocalNotification({required String title, required String body}) async {
  const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
    'default_channel',
    'Default Channel',
    channelDescription: 'Main notification channel',
    importance: Importance.high,
    priority: Priority.high,
  );

  const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

  await _flutterLocalNotificationsPlugin.show(
    0, // ID Notification
    title,
    body,
    platformDetails,
  );
}


  Future<void> sendCheckInReminder(String ticketId, String ticketTitle) async {
    // Check if reminder was already sent for this ticket
    final prefs = await SharedPreferences.getInstance();
    final reminderKey = 'checkin_reminder_$ticketId';
    final reminderSent = prefs.getBool(reminderKey) ?? false;

    if (!reminderSent) {
      // Send the reminder notification
      await sendLocalNotification(
        title: "Check-In Reminder",
        body: "Don't forget to check in for ticket: $ticketTitle",
      );

      // Mark reminder as sent
      await prefs.setBool(reminderKey, true);
      print("✅ Check-in reminder sent for ticket: $ticketId");
    }
  }
}

// === Pending Check-in Reminder Utilities ===
Future<void> addPendingCheckInTicket(String ticketId) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> pending = prefs.getStringList('pending_checkin_tickets') ?? [];
  if (!pending.contains(ticketId)) {
    pending.add(ticketId);
    await prefs.setStringList('pending_checkin_tickets', pending);
  }
}

Future<void> removePendingCheckInTicket(String ticketId) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> pending = prefs.getStringList('pending_checkin_tickets') ?? [];
  pending.remove(ticketId);
  await prefs.setStringList('pending_checkin_tickets', pending);
}

Future<List<String>> getPendingCheckInTickets() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList('pending_checkin_tickets') ?? [];
}

Timer? _reminderTimer;

void startCheckInReminderTimer() {
  _reminderTimer?.cancel();
  _reminderTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
    final pendingTickets = await getPendingCheckInTickets();
    for (final ticketId in pendingTickets) {
      await NotificationService().sendLocalNotification(
        title: 'Ticket Reminder',
        body: 'Please Check-in your ticket',
      );
    }
  });
}
// === End Pending Check-in Reminder Utilities ===

void onDidReceiveBackgroundNotificationResponse(NotificationResponse notificationResponse) {
  print("📩 Background notification clicked: ${notificationResponse.payload}");
}


void onDidReceiveNotificationResponse(NotificationResponse notificationResponse) {
  print("📩 Notification clicked: ${notificationResponse.payload}");
}