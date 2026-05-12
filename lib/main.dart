import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'odoo_service.dart';
import 'pushnoti/notification_service.dart'; // Import your NotificationService
import 'pushnoti/serverkey.dart'; // Import ServerKey classl
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:timezone/data/latest.dart' as tz;
import 'home.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    // Remove Firebase initialization from here since it's already handled in main()
    print("📩 [BACKGROUND] Notifikasi diterima: ${message.notification?.title}");

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
      title: message.notification?.title ?? "New Ticket Alert",
      body: message.notification?.body ?? "Check your new ticket now!",
    );
  } catch (e) {
    print("⚠️ Error in background handler: $e");
  }
}

void main() async {
  try {
    print("🚀 Starting Ticket application...");
    WidgetsFlutterBinding.ensureInitialized();
    
    // Initialize timezone first (fast)
    tz.initializeTimeZones();
    print("✅ Flutter binding initialized");

    // Get initial page immediately (fast)
    print("🏠 Getting initial page...");
    final initialPage = await getInitialPage();
    print("✅ Initial page determined, running app...");
    
    // Run app immediately with initial page
    runApp(MyApp(initialPageFuture: Future.value(initialPage)));

    // Initialize Firebase and other services in background (non-blocking)
    _initializeServicesInBackground();
    
    print("✅ App started successfully");
  } catch (e, stackTrace) {
    print("❌ CRITICAL ERROR during app initialization: $e");
    print("❌ Stack trace: $stackTrace");
    // Show error screen instead of crashing
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'App Error',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Error: $e',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Restart app
                  main();
                },
                child: const Text('Restart App'),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}

// Initialize services in background without blocking UI
void _initializeServicesInBackground() async {
  try {
    // Initialize Firebase
    if (Firebase.apps.isEmpty) {
      print("🔥 Initializing Firebase in background...");
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print("✅ Firebase initialized successfully");
    } else {
      print("ℹ️ Firebase already initialized, using existing instance.");
    }

    // Initialize Firebase Messaging
    print("🔔 Setting up Firebase Messaging in background...");
    final messaging = FirebaseMessaging.instance;
    
    // Request permission
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print("🔔 Notification permission status: ${settings.authorizationStatus}");

    // Get FCM token
    String? token = await messaging.getToken();
    print("🔥 FCM Token: $token");

    // Initialize Notification Service
    print("🔔 Initializing Notification Service in background...");
    await NotificationService().initialize();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle initial message
    try {
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          print('📦 App opened from notification: ${message.notification?.title}');
          NotificationService.notifyNewTicket();
        }
      });
    } catch (e) {
      print("⚠️ Failed to handle initial message: $e");
    }

    // Optional: Test network connectivity (non-blocking)
    _testNetworkConnectivityInBackground();
    
    // Optional: Fetch server key (non-blocking)
    _fetchServerKeyInBackground();

  } catch (e) {
    print("⚠️ Error during background initialization: $e");
    // Continue without Firebase if it fails
  }
}

// Test network connectivity in background
void _testNetworkConnectivityInBackground() async {
  try {
    print("🌐 Testing network connectivity in background...");
    final response = await http.get(Uri.parse('https://sigmarectrix.com'));
    print("✅ Network connectivity test: ${response.statusCode}");
  } catch (e) {
    print("❌ Network connectivity test failed: $e");
  }
}

// Fetch server key in background
void _fetchServerKeyInBackground() async {
  try {
    print("🔑 Fetching server key in background...");
    final serverKey = ServerKey();
    String serverToken = await serverKey.server_token();
    print("DEBUG: ServerKey from serverkey.dart: $serverToken");
  } catch (e) {
    print("❌ Failed to fetch server key: $e");
  }
}

// 👇 Dapatkan halaman pertama bergantung pada login cache (optimized)
Future<Widget> getInitialPage({void Function(bool)? onThemeChanged}) async {
  try {
    print("🔍 Checking for stored credentials...");
    final prefs = await SharedPreferences.getInstance();
    final String? email = prefs.getString('email');
    final String? password = prefs.getString('password');
    final String? sessionId = prefs.getString('sessionId');
    final String? userId = prefs.getString('user_id');

    print("📧 Stored email: ${email != null ? 'Found' : 'Not found'} - Value: '$email' - Length: ${email?.length ?? 0}");
    print("🔑 Stored password: ${password != null ? 'Found' : 'Not found'} - Value: '${password != null ? '***' : null}' - Length: ${password?.length ?? 0}");
    print("🍪 Stored sessionId: ${sessionId != null ? 'Found' : 'Not found'} - Value: '$sessionId' - Length: ${sessionId?.length ?? 0}");
    print("👤 Stored userId: ${userId != null ? 'Found' : 'Not found'} - Value: '$userId' - Length: ${userId?.length ?? 0}");

    // Jika sessionId dan userId masih ada, langsung ke HomePage (fast path)
    if (sessionId != null && userId != null && email != null && password != null && 
        email.isNotEmpty && password.isNotEmpty) {
      print("✅ Session found, skip auto-login - returning HomePage immediately");
      print("✅ HomePage email: '$email', password length: ${password.length}");
      print("✅ Creating HomePage with email: '$email', password length: ${password.length}");
      return HomePage(email: email, password: password, onThemeChanged: onThemeChanged);
    }

    // Jika tidak ada session, lakukan auto-login (background)
    if (email != null && password != null && email.isNotEmpty && password.isNotEmpty) {
      print("🔄 Attempting auto-login in background...");
      print("🔄 HomePage email: '$email', password length: ${password.length}");
      print("🔄 Creating HomePage with email: '$email', password length: ${password.length}");
      
      // Return HomePage immediately, do auto-login in background
      final homePage = HomePage(email: email, password: password, onThemeChanged: onThemeChanged);
      
      // Do auto-login in background without blocking UI
      _performAutoLoginInBackground(email, password);
      
      return homePage;
    }

    print("🔐 No valid credentials found, showing login page");
    return const LoginPage();
  } catch (e) {
    print("❌ Error in getInitialPage: $e");
    return const LoginPage();
  }
}

// Perform auto-login in background without blocking UI
void _performAutoLoginInBackground(String email, String password) async {
  try {
    print("🔄 Background auto-login for $email...");
    final odooService = OdooService();
    
    final userId = await odooService.authenticate(email, password);

    if (userId != null) {
      print("✅ Background auto-login successful for $email");
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userId);
      
      // Also save email and password to ensure they're available
      await prefs.setString('email', email);
      await prefs.setString('password', password);
      
      // Verify the save immediately
      final savedEmail = prefs.getString('email');
      final savedPassword = prefs.getString('password');
      print("🔍 Background save verify - email: '$savedEmail', password length: ${savedPassword?.length ?? 0}");
      
      // Save FCM token in background (non-blocking)
      saveFcmToken(email).catchError((e) {
        print("⚠️ Failed to save FCM token in background: $e");
      });
      
      // Check admin status in background (non-blocking)
      try {
        final isAdmin = await odooService.isAdmin();
        print("👤 User admin status: $isAdmin");
      } catch (e) {
        print("⚠️ Error checking admin status in background: $e");
      }
    } else {
      print("❌ Background auto-login failed: clearing stored credentials");
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('email');
      await prefs.remove('password');
      await prefs.remove('sessionId');
      await prefs.remove('user_id');
    }
  } catch (e) {
    print("❌ Background auto-login error: $e");
    // Clear credentials on error
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('email');
    await prefs.remove('password');
    await prefs.remove('sessionId');
    await prefs.remove('user_id');
  }
}

Future<void> saveLoginInfo(String username, String password) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('email', username);
  await prefs.setString('password', password);
}

void logout() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('is_logged_in', false); // keep email/password
}

Future<void> saveFcmToken(String email, {BuildContext? context}) async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    print("🔥 FCM Token: $token");

    final prefs = await SharedPreferences.getInstance();
    final userIdStr = prefs.getString('user_id');
    final storedEmail = prefs.getString('email');
    final storedPassword = prefs.getString('password');

    if (token == null || userIdStr == null || storedEmail == null || storedPassword == null) {
      print("❌ Missing required data for FCM token sending");
      return;
    }

    // Use OdooService to send FCM token with credential-based authentication
    print("🔄 Sending FCM token using credential-based authentication...");
    try {
      final success = await OdooService().sendFcmToken(token);
      if (success) {
        print("✅ FCM token sent successfully via OdooService");
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("FCM token updated successfully"), backgroundColor: Colors.green),
          );
        }
      } else {
        print("❌ Failed to send FCM token via OdooService");
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to update FCM token"), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      print("❌ Error sending FCM token: $e");
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to update FCM token"), backgroundColor: Colors.red),
        );
      }
    }
  } catch (e) {
    print('❌ Error in saveFcmToken: $e');
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to update FCM token"), backgroundColor: Colors.red),
      );
    }
  }
}

class MyApp extends StatefulWidget {
  final Future<Widget> initialPageFuture;
  const MyApp({super.key, required this.initialPageFuture});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _setTheme(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDark);
    setState(() {
      _isDarkMode = isDark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange, brightness: Brightness.dark),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: FutureBuilder<Widget>(
        future: widget.initialPageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasError) {
            return const Scaffold(
              body: Center(child: Text("❌ Error initializing app")),
            );
          } else {
            final Widget page = snapshot.data!;
            if (page is HomePage) {
              return HomePage(
                email: page.email,
                password: page.password,
                onThemeChanged: _setTheme,
              );
            }
            return page;
          }
        },
      ),
    );
  }
}


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});



  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final OdooService _odooService = OdooService();
  bool _isLoading = false;
  bool _isPasswordVisible = false;




  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  

Future<void> _login() async {
  if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
    _showSnackBar("Please enter both email and password.");
    return;
  }

  setState(() {
    _isLoading = true;
  });

  try {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    final userId = await _odooService.authenticate(email, password);
    debugPrint("🔑 Authentication result - User ID: $userId");

    if (userId != null && mounted) {
      debugPrint("✅ Login successful for user: $email");
      debugPrint("🔍 DEBUG: User ID returned from authentication: $userId");
      
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('email', email);
      await prefs.setString('password', password);
      await prefs.setString('user_id', userId); // Store user_id after successful login
      
      debugPrint("🔍 DEBUG: Stored user_id in SharedPreferences: $userId");
      
      // Debug: Check all stored preferences
      final allKeys = prefs.getKeys();
      debugPrint("🔍 DEBUG: All stored preferences after login: $allKeys");
      for (String key in allKeys) {
        final value = prefs.get(key);
        debugPrint("🔍 DEBUG: $key = $value");
      }

      // Save FCM token
      try {
        await saveFcmToken(email, context: context);
        debugPrint("✅ FCM token saved successfully");
      } catch (e) {
        debugPrint("❌ FCM token save failed: $e");
        // Continue anyway - don't block login
      }

      debugPrint("🔄 Redirecting to home page...");
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(email: email, password: password),
          ),
        );
      }
    } else {
      _showSnackBar("❌ Login failed. Check your credentials.");
    }
  } catch (e) {
    debugPrint("❌ Error during login: $e");
    _showSnackBar("❌ Error during login: "+e.toString());
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}





    final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

    @override
  void initState() {
    super.initState();
    _loadSavedLogin(); // panggil function autofill
  }

  void _loadSavedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    emailController.text = prefs.getString('email') ?? '';
    passwordController.text = prefs.getString('password') ?? '';
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF9BE7A6), Color(0xFF020035)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Card(
                    color: Colors.white, // Card sentiasa putih
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Hero(
                            tag: 'logo',
                            child: Image.asset(
                              'images/myerp.com.png',
                              width: 120,
                              height: 120,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _emailController,
                            style: const TextStyle(color: Colors.black), // Teks sentiasa hitam
                            decoration: InputDecoration(
                              labelText: 'Email',
                              labelStyle: const TextStyle(color: Colors.black), // Label sentiasa hitam
                              prefixIcon: const Icon(Icons.email_outlined, color: Colors.black),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            obscureText: !_isPasswordVisible,
                            style: const TextStyle(color: Colors.black), // Teks sentiasa hitam
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.black), // Label sentiasa hitam
                              prefixIcon: const Icon(Icons.lock_outline, color: Colors.black),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                  color: Colors.black,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isPasswordVisible = !_isPasswordVisible;
                                  });
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          _isLoading
                              ? const CircularProgressIndicator(color: Color(0xFF020035))
                              : ElevatedButton(
                                  onPressed: _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF020035),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'LOGIN',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              // Add forgot password functionality here
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.8),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}




