import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'helpdesk ticket/ticketprogress.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';


class OdooActionResult {
  final int? id;
  final String? error;
  const OdooActionResult({this.id, this.error});
}

class OdooService {
  final String baseUrl = 'https://myerp.com.my';
  final String jsonRpcUrl = 'https://myerp.com.my/jsonrpc';
  final String database = 'myerp_db';
  String? _password;
  String? _userId;
  String? lastErrorMessage;

  /// Odoo `/api/update_check_in` and `/api/update_check_out` expect `yyyy-MM-dd HH:mm:ss`.
  static String formatOdooApiDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dateTime);
  }

  static String normalizeOdooApiDateTimeString(String value) {
    const patterns = [
      'yyyy-MM-dd HH:mm:ss',
      'dd/MM/yyyy HH:mm:ss',
      'yyyy-MM-dd',
      'dd/MM/yyyy',
    ];
    for (final pattern in patterns) {
      try {
        final parsed = DateFormat(pattern).parse(value.trim());
        return formatOdooApiDateTime(parsed);
      } catch (_) {}
    }
    return value.trim();
  }

  bool _isJsonRpcSuccess(dynamic result) {
    if (result is Map) {
      if (result.containsKey('error')) return false;
      if (result['success'] == true) return true;
      final nested = result['result'];
      if (nested is Map) {
        if (nested.containsKey('error')) return false;
        if (nested['success'] == true) return true;
      }
    }
    return false;
  }

  String? _extractJsonRpcErrorMessage(dynamic payload) {
    if (payload is! Map) return null;
    final direct = payload['error'];
    if (direct is Map && direct['message'] != null) {
      return direct['message'].toString();
    }
    final result = payload['result'];
    if (result is Map) {
      final nested = result['error'];
      if (nested is Map && nested['message'] != null) {
        return nested['message'].toString();
      }
    }
    return null;
  }

  bool _isHttpNotFound(dynamic payload, {int? statusCode}) {
    if (statusCode == 404) return true;
    if (payload is! Map) return false;
    final error = payload['error'];
    if (error is Map) {
      final code = error['code'];
      if (code == 404 || code == '404') return true;
      final message = error['message']?.toString() ?? '';
      if (message.contains('404') || message.contains('Not Found')) return true;
    }
    return false;
  }

  String _sanitizePlainText(String input) {
    // Remove HTML tags + normalize common entities so only real text is stored/sent.
    String s = input;
    s = s.replaceAll(RegExp(r'<[^>]*>'), '');
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
  
  
  
  get ticketId => null;
  get checkOutTime => null;
  

  /// Hydrate in-memory credentials from SharedPreferences (fast path after app restart).
  Future<void> loadSessionCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? _userId;
    _password = prefs.getString('user_password') ??
        prefs.getString('password') ??
        _password;
  }

  Future<bool> checkAndLoadUserCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email') ?? prefs.getString('email');
    final password =
        prefs.getString('user_password') ?? prefs.getString('password');
    final userId = prefs.getString('user_id');
    final sessionId =
        prefs.getString('session_id') ?? prefs.getString('sessionId');

    if (userId != null &&
        password != null &&
        password.isNotEmpty &&
        (sessionId != null && sessionId.isNotEmpty)) {
      _userId = userId;
      _password = password;
      return true;
    }

    if (email != null && password != null && password.isNotEmpty) {
      return await authenticate(email, password) != null;
    }
    return false;
  }

  
  Future<String?> authenticate(String email, String password) async {
    try {
      print("🔹 Attempting to authenticate with email: $email via /web/session/authenticate");

      final response = await http.post(
        Uri.parse('$baseUrl/web/session/authenticate'), // Use the session authentication endpoint
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "params": {
            "db": database,
            "login": email,
            "password": password,
            "context": {},
          }
        }),
      );

      print("🔹 Authentication Response Status: "+response.statusCode.toString());
      print("🔹 Authentication Response Body: ${response.body}");

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        
        if (responseData.containsKey('error')) {
          final error = responseData['error'];
          print("❌ Authentication failed: ${error['data']['message']}");
          throw Exception("Authentication failed: ${error['data']['message'] ?? 'Unknown error'}");
        }

        if (responseData.containsKey('result')) {
          final result = responseData['result'];

          if (result == null || result['uid'] == false || result['uid'] == 0) {
            print("❌ Invalid login: Empty or zero result.");
            throw Exception("Invalid login credentials");
          }

          // Extract and save the session ID
          final String? rawCookie = response.headers['set-cookie'];
          print("🍪 Raw 'set-cookie' header from Odoo: $rawCookie"); // Enhanced logging

          if (rawCookie != null) {
            // A simple regex to extract session_id, adjust if format is different
            final RegExp sessionIdRegex = RegExp(r'session_id=([^;]+)');
            final Match? match = sessionIdRegex.firstMatch(rawCookie);

            if (match != null && match.groupCount >= 1) {
              final String sessionId = match.group(1)!;
              final String sessionCookieValue = 'session_id=$sessionId';
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString('sessionId', sessionId); // <-- Fix: save as sessionId
              await prefs.setString('session_id', sessionCookieValue); // for legacy code if needed
              await prefs.setString('odooUrl', baseUrl); // <-- Save odooUrl for HomePage
              print("✅ Session ID saved successfully: $sessionId");
            } else {
              print("❌ Regex did not find session_id in the cookie string.");
            }
          } else {
            print("❌ 'set-cookie' header not found in the response.");
          }

          _userId = result['uid'].toString();
          _password = password;
          
          print("🔍 DEBUG: Authentication result: $result");
          print("🔍 DEBUG: User ID (uid): ${result['uid']}");
          print("🔍 DEBUG: User ID type: ${result['uid'].runtimeType}");
          print("🔍 DEBUG: User ID as string: $_userId");

          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_email', email);
          await prefs.setString('user_password', password);
          await prefs.setString('email', email);
          await prefs.setString('password', password);
          await prefs.setString('user_id', _userId!); // <-- Ensure user_id is always saved

          // Fetch and save user image after login
          try {
            final imageBase64 = await fetchUserImage();
            if (imageBase64 != null && imageBase64.isNotEmpty) {
              await prefs.setString('user_image_base64', imageBase64);
            } else {
              await prefs.remove('user_image_base64');
            }
          } catch (e) {
            print('❌ Error fetching/saving user image: $e');
            await prefs.remove('user_image_base64');
          }

          // === Tambah: Hantar FCM token ke Odoo selepas login ===
          try {
            String? fcmToken = await FirebaseMessaging.instance.getToken();
            if (fcmToken != null && fcmToken.isNotEmpty) {
              final sent = await sendFcmToken(fcmToken);
              if (sent) {
                print('✅ FCM token sent to Odoo after login.');
              } else {
                print('❌ FCM token was not stored by Odoo after login.');
              }
            } else {
              print('❌ FCM token not available after login.');
            }
          } catch (e) {
            print('❌ Error sending FCM token after login: $e');
          }
          // === Tamat ===

          print("✅ User authenticated with ID: $_userId");
          return _userId;
        } else {
          print("❌ Unexpected authentication response format.");
          throw Exception("Unexpected response format from server");
        }
      } else {
        print("❌ HTTP Error: ${response.statusCode}, Response: ${response.body}");
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Authentication Error: $e");
      rethrow; // Rethrow to handle in UI
    }
  }



Future<bool> submitCheckOut(int ticketId, String checkOutString) async {
  if (_password == null || _userId == null) {
    print("⚠️ User not authenticated. Please login first.");
    return false;
  }

    try {
      final apiTime = normalizeOdooApiDateTimeString(checkOutString);
      print("🔹 Submitting Check-Out: Ticket ID: $ticketId, Check-Out Time: $apiTime");

      final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('session_id');

    if (sessionCookie == null) {
      print("❌ Session cookie not found. User needs to re-authenticate.");
      return false;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/update_check_out'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': sessionCookie,
      },
      body: json.encode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'ticket_id': ticketId,
          'check_out_time': apiTime,
        },
        'id': 1,
      }),
    );

    print("🔹 Check-Out Response: ${response.body}");

    if (response.statusCode != 200) {
      print("❌ Check-Out submission failed. Status Code: ${response.statusCode}, Response: ${response.body}");
      return false;
    }

    final responseData = json.decode(response.body);
    final errorMessage = _extractJsonRpcErrorMessage(responseData);
    if (errorMessage != null) {
      lastErrorMessage = errorMessage;
      print("❌ Check-Out submission failed. Response: ${response.body}");
      return false;
    }

    if (_isJsonRpcSuccess(responseData['result'])) {
      print("✅ Check-Out submitted successfully.");
      return true;
    }

    print("❌ Check-Out submission failed. Response: ${response.body}");
    return false;
  } catch (e) {
    print("❌ Error during check-out: $e");
    return false;
  }
}

  // Fetch the list of workers (users) from Odoo
  Future<List<Map<String, dynamic>>> fetchWorkers() async {
    try {
      print("🔹 Fetching Workers from Odoo...");

      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
       'jsonrpc': '2.0',
       'method': 'call',
       'params': {
          'service': 'object',
          'method': 'execute_kw',
          'args': [
            database,
           int.parse(_userId!),
           _password,
           'helpdesk.ticket',
           'write',
          [[ticketId], {'check_out_string': checkOutTime}],
        ],
      },
      'id': 3,
     })
,
      );

      print("🔹 Fetch Workers Response: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['result'] != null) {
          final workers = responseData['result'] as List<dynamic>;
          print("✅ Fetched workers: $workers");

          return workers.map((worker) {
          return {
            'id': worker['id'].toString(),
            'name': worker['name']?.toString() ?? '',
            };
          }).toList();
        } else {
          print("❌ Error fetching workers: ${responseData['error']}");
          return [];
        }
      } else {
        print("❌ Error fetching workers: ${response.statusCode}, Response: ${response.body}");
        return [];
      }
    } catch (e) {
      print("❌ Error during fetching workers: $e");
      return [];
    }
  }

  

  // Fetch tickets from Odoo based on user ID using HTTP API endpoint
  Future<List<dynamic>> fetchTickets(String userId) async {
    try {
      print("🔹 Fetching Tickets for User ID: $userId using HTTP API");
      print("🔹 Base URL: $baseUrl");

      // Get session cookie for authentication
      final prefs = await SharedPreferences.getInstance();
      final String? sessionCookie = prefs.getString('session_id');
      
      print("🍪 Session cookie retrieved: $sessionCookie");
      
      if (sessionCookie == null) {
        print("❌ Session cookie not found. User needs to re-authenticate.");
        return [];
      }

      // Use the HTTP API endpoint with session authentication
      // For type='http' routes, use GET method to avoid JSON-RPC routing
      // GET is better for HTTP endpoints as it doesn't trigger JSON-RPC handler
      final response = await http.get(
        Uri.parse('$baseUrl/api/tickets?user_id=${int.parse(userId)}'),
        headers: {
          'Cookie': sessionCookie,
        },
      );

      print("🔹 Fetch Tickets Response: ${response.body}");

      if (response.statusCode == 200) {
        try {
          final responseData = json.decode(response.body);

          if (responseData['result'] != null) {
            final tickets = responseData['result'] as List<dynamic>;
            print("✅ Successfully fetched ${tickets.length} tickets via HTTP API");
            return tickets;
          } else if (responseData['error'] != null) {
            print("❌ Error in response: ${responseData['error']}");
            return [];
          } else {
            print("❌ Unexpected response format: ${response.body}");
            return [];
          }
        } catch (e) {
          print("❌ Error parsing JSON response: $e");
          print("❌ Response body: ${response.body}");
          return [];
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Session expired, try to re-authenticate
        print("🔄 Session expired, attempting to re-authenticate...");
        
        final String? email = prefs.getString('user_email');
        final String? password = prefs.getString('user_password');
        
        if (email != null && password != null) {
          final String? newUserId = await authenticate(email, password);
          if (newUserId != null) {
            print("✅ Re-authentication successful, retrying ticket fetch...");
            return await fetchTickets(userId); // Retry with new session
          }
        }
        
        print("❌ Re-authentication failed or no credentials found");
        return [];
      } else if (response.statusCode == 400) {
        // Handle 400 Bad Request - might be due to session or data format issues
        print("❌ Bad Request (400) - Response: ${response.body}");
        
        // Try to re-authenticate and retry
        print("🔄 Attempting to re-authenticate due to 400 error...");
        final String? email = prefs.getString('user_email');
        final String? password = prefs.getString('user_password');
        
        if (email != null && password != null) {
          final String? newUserId = await authenticate(email, password);
          if (newUserId != null) {
            print("✅ Re-authentication successful, retrying ticket fetch...");
            return await fetchTickets(userId); // Retry with new session
          }
        }
        
        print("❌ Re-authentication failed or no credentials found");
        return [];
      } else {
        print("❌ Error fetching tickets: ${response.statusCode}, Response: ${response.body}");
        return [];
      }
    } catch (e) {
      print("❌ Error during fetching tickets: $e");
      return [];
    }
  }

  // Submit check-in for a ticket
  Future<bool> submitCheckIn(int ticketId, String checkInString) async {
    if (_password == null || _userId == null) {
      print("⚠️ User not authenticated. Please login first.");
      return false;
    }

    try {
      final apiTime = normalizeOdooApiDateTimeString(checkInString);
      print("🔹 Submitting Check-In: Ticket ID: $ticketId, Check-In Time: $apiTime");

      // Use custom API endpoint /api/update_check_in instead of direct write
      // This endpoint uses sudo().write() which bypasses permission checks
      final prefs = await SharedPreferences.getInstance();
      final String? sessionCookie = prefs.getString('session_id');
      
      if (sessionCookie == null) {
        print("❌ Session cookie not found. User needs to re-authenticate.");
        return false;
      }

      // Use JSON-RPC format for /api/update_check_in endpoint (type='json')
      final response = await http.post(
        Uri.parse('$baseUrl/api/update_check_in'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': sessionCookie,
        },
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'ticket_id': ticketId,
            'check_in_time': apiTime,
          },
          'id': 1,
        }),
      );

      print("🔹 Check-In Response: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        final errorMessage = _extractJsonRpcErrorMessage(responseData);
        if (errorMessage != null) {
          lastErrorMessage = errorMessage;
          print("❌ Check-In submission failed. Response: ${response.body}");
          return false;
        }

        if (_isJsonRpcSuccess(responseData['result'])) {
          print("✅ Check-In submitted successfully.");
          return true;
        }

        print("❌ Check-In submission failed. Response: ${response.body}");
        return false;
      } else {
        print("❌ Check-In submission failed. Status Code: ${response.statusCode}, Response: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Error during check-in: $e");
      return false;
    }
  }

  // Simpan status check-out dalam SharedPreferences
  Future<void> saveCheckOutStatus(int ticketId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('checkout_$ticketId', true);

    
  }

  // Semak sama ada tiket telah di-checkout sebelum ini
  Future<bool> hasCheckedOut(int ticketId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('checkout_$ticketId') ?? false;
  }

Future<List<Map<String, dynamic>>> fetchUsersFromOdoo() async {
  try {
    final response = await http.post(
      Uri.parse('https://myerp.com.my/jsonrpc'), // Guna URL Odoo yang betul
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),  // Pastikan _userId tidak null
            _password,
            "res.users",
            "search_read",
            [], // Get all users first to test
            {"fields": ["id", "name", "login", "email"], "limit": 50}
          ]
        },
        "id": 1,
      }),
    );

    print("🔹 Odoo Response: ${response.body}"); // Debugging log

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      print("🔹 Raw Odoo response: $result");
      
      if (result['result'] == null) {
        print("⚠️ No users found in Odoo response");
        return [];
      }
      
      if (result['result'] is List) {
        return List<Map<String, dynamic>>.from(result['result']);
      } else {
        print("⚠️ Unexpected result format: ${result['result']}");
        return [];
      }
    } else {
      print("❌ HTTP Error: ${response.statusCode}, Response: ${response.body}");
      throw Exception("Failed to fetch users from Odoo: HTTP ${response.statusCode}");
    }
  } catch (e) {
    print("❌ Error fetching users: $e");
    
    // Try a simpler query as fallback
    try {
      print("🔄 Trying fallback query...");
      final fallbackResponse = await http.post(
      Uri.parse('https://myerp.com.my/jsonrpc'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "res.users",
              "search_read",
              [],
              {"fields": ["id", "name"], "limit": 10}
            ]
          },
          "id": 2,
        }),
      );
      
      if (fallbackResponse.statusCode == 200) {
        final fallbackResult = jsonDecode(fallbackResponse.body);
        if (fallbackResult['result'] is List) {
          print("✅ Fallback query successful");
          return List<Map<String, dynamic>>.from(fallbackResult['result']);
        }
      }
    } catch (fallbackError) {
      print("❌ Fallback query also failed: $fallbackError");
    }
    
    return [];
  }
}

// ✅ Simpan login info selepas login berjaya
Future<void> saveLoginCredentials(String email, String password) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('email', email);
  await prefs.setString('password', password);
}

// ✅ Padam login info masa logout
Future<void> clearLoginCredentials() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('email');
  await prefs.remove('password');
}


Future<Map<String, dynamic>?> getTicketDetails(int ticketId) async {
  bool isAuthenticated = await checkAndLoadUserCredentials();
  if (!isAuthenticated || _userId == null || _password == null) {
    print("❌ User not authenticated, cannot fetch ticket details.");
    return null;
  }

  try {
    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!), 
            _password,
            "helpdesk.ticket",
            "search_read",
            [[["id", "=", ticketId]]],
            {"fields": [
              "id",
              "close_comment",
              "description",
              "feedback_scale1",
              "feedback_scale2",
              "feedback_scale3",
              "feedback_scale4",
              "feedback_scale5",
              "feedback_scale6"
            ]}
          ]
        },
        "id": 6,
      }),
    );

    final responseData = json.decode(response.body);
    print("🔍 Response from Odoo: $responseData"); // ✅ Debug 

    if (responseData["result"] != null && responseData["result"].isNotEmpty) {
      var ticketData = responseData["result"][0];

      // ✅ Pastikan nilai close_comment dan description tidak false/null
      ticketData["close_comment"] = ticketData["close_comment"] ?? "";
      ticketData["description"] = ticketData["description"] ?? "";

      print("✅ Final close_comment: ${ticketData["close_comment"]}"); // ✅ Debug 
      print("✅ Final description: ${ticketData["description"]}"); // ✅ Debug 

      return ticketData;
    }
  } catch (e) {
    print("❌ Error fetching ticket details: $e");
  }
  return null;
}


Future<bool> submitCloseComment(int ticketId, String closeComment) async {
  if (_password == null || _userId == null) {
    print("⚠️ User not authenticated. Please login first.");
    return false;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('session_id');
    if (sessionCookie == null) {
      print("❌ Session cookie not found. User needs to re-authenticate.");
      return false;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/update_close_comment'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': sessionCookie,
      },
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "ticket_id": ticketId,
          "close_comment": closeComment,
        },
        "id": 1,
      }),
    );

    print("🔹 Close Comment Response: ${response.body}");
    if (response.statusCode != 200) return false;

    final responseData = jsonDecode(response.body);
    if (responseData["error"] != null) return false;

    final result = responseData["result"];
    if (result is Map && result["success"] == true) return true;
    if (result is Map && result["result"] is Map && (result["result"] as Map)["success"] == true) return true;
    return false;
  } catch (e) {
    print("❌ Error submitting Close Comment: $e");
    return false;
  }
}



  Future<List<ProgressStep>> fetchProgressSteps(int ticketId) async {
  bool isAuthenticated = await checkAndLoadUserCredentials();
  if (!isAuthenticated) return [];

  try {
    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "helpdesk.ticket",
            "search_read",
            [[["id", "=", ticketId]]],
            {"fields": ["id", "progress_steps"]}
          ]
        },
        "id": 6,
      }),
    );

    final responseData = json.decode(response.body);
    if (responseData["result"] != null && responseData["result"].isNotEmpty) {
      List<dynamic> steps = responseData["result"][0]["progress_steps"] ?? [];

      return steps.map((step) {
        return ProgressStep(
  title: step["title"] ?? "Unknown Step",
  timestamp: DateTime.tryParse(step["timestamp"] ?? ""),
  isCompleted: step["is_completed"] ?? false,
  icon: null, // ✅ Gunakan null kerana ini backend
);

      }).toList();
    }
  } catch (e) {
    print("❌ Error fetching progress steps: $e");
  }

  return [];
}

Future<String> getSessionId() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString('session_id') ?? "";
}


Future<bool> uploadFileToOdoo(int ticketId, String fileName, Uint8List fileBytes, String mimeType) async {
  bool isAuthenticated = await checkAndLoadUserCredentials();
  if (!isAuthenticated) return false;

  // Odoo `type='json'` routes expect JSON-RPC envelopes even on custom endpoints.
  // Also: server-side route signature is (ticket_id, file_name, file_data) so we MUST NOT send `mimetype`.
  final prefs = await SharedPreferences.getInstance();
  final String? sessionCookie = prefs.getString('session_id');

  final response = await http.post(
    Uri.parse('$baseUrl/api/helpdesk/upload_file'),
    headers: {
      'Content-Type': 'application/json',
      if (sessionCookie != null) 'Cookie': sessionCookie,
    },
    body: jsonEncode({
      "jsonrpc": "2.0",
      "method": "call",
      "params": {
        "ticket_id": ticketId,
        "file_name": fileName,
        "file_data": base64Encode(fileBytes),
      },
      "id": 1,
    }),
  );

  if (response.statusCode != 200) return false;
  final responseData = jsonDecode(response.body);
  if (responseData['error'] != null) return false;
  final result = responseData['result'];
  return result is Map && result['success'] == true;
}



Future<bool> submitDescription(int ticketId, String description) async {
  try {
    final clean = _sanitizePlainText(description);
    if (clean.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('session_id');
    if (sessionCookie == null || sessionCookie.isEmpty) {
      lastErrorMessage = 'Session expired. Please login again.';
      return false;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/update_description'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': sessionCookie,
      },
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "ticket_id": ticketId,
          "description": clean,
        },
        "id": 1,
      }),
    );

    print("🔹 Update Description Response: ${response.body}");

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      if (_isHttpNotFound(responseData)) {
        print("🔁 /api/update_description not found — falling back to JSON-RPC");
        return await _submitDescriptionViaRpc(ticketId, clean);
      }

      final errorMessage = _extractJsonRpcErrorMessage(responseData);
      if (errorMessage != null) {
        lastErrorMessage = errorMessage;
        return false;
      }

      if (_isJsonRpcSuccess(responseData['result'])) {
        lastErrorMessage = null;
        return true;
      }
    }

    if (response.statusCode == 404) {
      print("🔁 /api/update_description returned 404 — falling back to JSON-RPC");
      return await _submitDescriptionViaRpc(ticketId, clean);
    }

    lastErrorMessage = 'Failed to update description (HTTP ${response.statusCode}).';
    return false;
  } catch (e) {
    print("❌ Error updating description: $e");
    lastErrorMessage = 'Error updating description: $e';
    return false;
  }
}

Future<bool> _submitDescriptionViaRpc(int ticketId, String clean) async {
  if (!await checkAndLoadUserCredentials() || _userId == null || _password == null) {
    lastErrorMessage = 'Not authenticated. Please login again.';
    return false;
  }

  try {
    final ts = formatOdooApiDateTime(DateTime.now());
    final followUpText = '\nFollow-up ($ts): $clean\n';

    final readResponse = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "helpdesk.ticket",
            "search_read",
            [
              [ticketId]
            ],
            {"fields": ["description"]},
          ],
        },
        "id": 71,
      }),
    );

    if (readResponse.statusCode != 200) {
      lastErrorMessage = 'Failed to read ticket description (HTTP ${readResponse.statusCode}).';
      return false;
    }

    final readData = jsonDecode(readResponse.body);
    if (readData is Map && readData['error'] != null) {
      lastErrorMessage = readData['error']['message']?.toString() ?? 'Failed to read ticket.';
      return false;
    }

    String existing = '';
    final rows = readData['result'];
    if (rows is List && rows.isNotEmpty && rows[0] is Map) {
      existing = _sanitizePlainText(rows[0]['description']?.toString() ?? '');
    }

    final newDescription = existing.trim().isEmpty
        ? followUpText.trim()
        : '${existing.trim()}$followUpText';

    final writeResponse = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "helpdesk.ticket",
            "write",
            [
              [ticketId],
              {"description": newDescription},
            ],
          ],
        },
        "id": 72,
      }),
    );

    print("🔹 Update Description (RPC) Response: ${writeResponse.body}");

    if (writeResponse.statusCode != 200) {
      lastErrorMessage = 'Failed to update description (HTTP ${writeResponse.statusCode}).';
      return false;
    }

    final writeData = jsonDecode(writeResponse.body);
    if (writeData is Map && writeData['error'] != null) {
      lastErrorMessage = writeData['error']['message']?.toString() ?? 'Failed to update description.';
      return false;
    }

    if (writeData['result'] == true) {
      lastErrorMessage = null;
      return true;
    }

    lastErrorMessage = 'Failed to update description.';
    return false;
  } catch (e) {
    print("❌ Error updating description via RPC: $e");
    lastErrorMessage = 'Error updating description: $e';
    return false;
  }
}



Future<bool> submitTicketProgress(
    int ticketId, String description, Uint8List fileData, String fileName) async {
  
  String base64File = base64Encode(fileData);
  String currentTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  final response = await http.post(
    Uri.parse('$jsonRpcUrl'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode({
      "jsonrpc": "2.0",
      "method": "call",
      "params": {
        "service": "object",
        "method": "execute_kw",
        "args": [
          database,
          int.parse(_userId!),
          _password,
          "helpdesk.ticket",
          "write",
          [
            [ticketId],
            {
              "description": description,
              "description_time": currentTime,
              "attached_files": [[0, 0, {
                "name": fileName,
                "type": "binary",
                "datas": base64File,
                "res_model": "helpdesk.ticket",
                "res_id": ticketId
              }]],
              "attach_files_time": currentTime
            }
          ]
        ]
      },
      "id": 5,
    }),
  );

  final responseData = json.decode(response.body);
  return responseData["result"] == true;
}

  Future<List<Map<String, dynamic>>> fetchTasksFromOdoo(int projectId) async {
    bool isAuthenticated = await checkAndLoadUserCredentials();
    if (!isAuthenticated) {
      throw Exception("User not authenticated");
    }

    try {
      print("🔍 Fetching tasks for project ID: $projectId");
      print("🔍 Database: $database, User ID: $_userId");
      
      // Try with minimal fields first
      final requestBody = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "project.task",
            "search_read",
              [
                [
                  ["project_id", "=", projectId]
                ],
              [
                "id",
                "name", 
                "description",
                "user_id",
                "date_deadline",
                "stage_id",
                "priority",
                "create_date",
                "write_date",
                "project_id",
                "kanban_state",
                "active",
                "planned_hours",
                "effective_hours",
                "progress",
                "remaining_hours",
                "total_hours_spent",
                "timesheet_ids",
                "subtask_planned_hours",
                "subtask_effective_hours",
                "child_ids"
              ]
            ]
          ],
          "id": 0
        }
      };

      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        // Check for Odoo server errors
        if (responseData.containsKey("error")) {
          final error = responseData["error"];
          final errorMessage = error["message"] ?? "Unknown server error";
          print("❌ Odoo Server Error: $errorMessage");
          throw Exception("Odoo Server Error: $errorMessage");
        }
        
        if (responseData["result"] != null) {
          final tasks = responseData["result"] as List;
          print("✅ Fetched ${tasks.length} tasks for project $projectId");
          
          // Transform the data to include user names and stage names
          List<Map<String, dynamic>> transformedTasks = [];
          for (var task in tasks) {
            Map<String, dynamic> transformedTask = Map<String, dynamic>.from(task);
            
            // Get user name if user_id exists
            if (task["user_id"] != null && task["user_id"].isNotEmpty) {
              try {
                final userResponse = await http.post(
                  Uri.parse(jsonRpcUrl),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode({
                    "jsonrpc": "2.0",
                    "method": "call",
                    "params": {
                      "service": "object",
                      "method": "execute_kw",
                      "args": [
                        database,
                        int.parse(_userId!),
                        _password,
                        "res.users",
                        "read",
                        [
                          [task["user_id"][0]]
                        ],
                        ["name", "login", "email"]
                      ]
                    },
                    "id": 7,
                  }),
                );
                
                if (userResponse.statusCode == 200) {
                  final userData = json.decode(userResponse.body);
                  if (userData["result"] != null && userData["result"].isNotEmpty) {
                    final user = userData["result"][0];
                    transformedTask["user_name"] = user["name"];
                    transformedTask["user_email"] = user["login"] ?? user["email"];
                  }
                }
              } catch (e) {
                print("⚠️ Error fetching user details: $e");
              }
            }
            
            // Get stage name if stage_id exists
            if (task["stage_id"] != null && task["stage_id"].isNotEmpty) {
              try {
                final stageResponse = await http.post(
                  Uri.parse(jsonRpcUrl),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode({
                    "jsonrpc": "2.0",
                    "method": "call",
                    "params": {
                      "service": "object",
                      "method": "execute_kw",
                      "args": [
                        database,
                        int.parse(_userId!),
                        _password,
                        "project.task.type",
                        "read",
                        [
                          [task["stage_id"][0]]
                        ],
                        ["name"]
                      ]
                    },
                    "id": 8,
                  }),
                );
                
                if (stageResponse.statusCode == 200) {
                  final stageData = json.decode(stageResponse.body);
                  if (stageData["result"] != null && stageData["result"].isNotEmpty) {
                    transformedTask["stage_name"] = stageData["result"][0]["name"];
                  }
                }
              } catch (e) {
                print("⚠️ Error fetching stage details: $e");
              }
            }
            
            transformedTasks.add(transformedTask);
          }
          
          return transformedTasks;
        } else {
          print("❌ No tasks found for project $projectId");
          return await _fetchTasksWithBasicFields(projectId);
        }
      } else {
        print("❌ Error fetching tasks: ${response.statusCode} - ${response.body}");
        throw Exception("Failed to fetch tasks: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error in fetchTasksFromOdoo: $e");
      try {
        return await _fetchTasksWithBasicFields(projectId);
      } catch (fallbackError) {
        print("❌ Fallback also failed: $fallbackError");
        throw Exception("Failed to fetch tasks: $e");
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTasksWithBasicFields(int projectId) async {
    try {
      print("🔍 Fallback: Fetching tasks with basic fields only for project ID: $projectId");
      
      final requestBody = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "project.task",
            "search_read",
              [
                [
                  ["project_id", "=", projectId]
                ],
              [
                "id",
                "name", 
                "description",
                "project_id",
                "active",
                "planned_hours",
                "effective_hours",
                "progress",
                "remaining_hours",
                "total_hours_spent",
                "timesheet_ids"
              ]
            ]
          ]
        },
        "id": 7,
      };
      
      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData.containsKey("error")) {
          final error = responseData["error"];
          final errorMessage = error["message"] ?? "Unknown server error";
          print("❌ Fallback Odoo Server Error: $errorMessage");
          throw Exception("Odoo Server Error: $errorMessage");
        }
        
        if (responseData["result"] != null) {
          final tasks = responseData["result"] as List;
          print("✅ Fallback: Fetched ${tasks.length} tasks for project $projectId");
          
          List<Map<String, dynamic>> basicTasks = [];
          for (var task in tasks) {
            Map<String, dynamic> basicTask = Map<String, dynamic>.from(task);
            basicTask["user_name"] = "Unknown User";
            basicTask["stage_name"] = "Unknown Stage";
            basicTask["priority"] = "0";
            basicTask["date_deadline"] = null;
            basicTask["kanban_state"] = "normal";
            basicTasks.add(basicTask);
          }
          
          return basicTasks;
        } else {
          print("❌ Fallback: No tasks found for project $projectId");
          return [];
        }
      } else {
        print("❌ Fallback: Error fetching tasks: ${response.statusCode} - ${response.body}");
        throw Exception("Failed to fetch tasks: ${response.statusCode}");
      }
    } catch (e) {
      print("❌ Error in fallback fetchTasksWithBasicFields: $e");
      throw Exception("Failed to fetch tasks with fallback: $e");
    }
  }


Future<bool> uploadFileToTicket(int ticketId, PlatformFile file) async {
  bool isAuthenticated = await checkAndLoadUserCredentials();
  if (!isAuthenticated) return false;

  try {
    final fileBytes = file.bytes ?? await File(file.path!).readAsBytes();
    final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('session_id');

    final response = await http.post(
      Uri.parse('$baseUrl/api/helpdesk/upload_file'),
      headers: {
        'Content-Type': 'application/json',
        if (sessionCookie != null) 'Cookie': sessionCookie,
      },
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "ticket_id": ticketId,
          "file_name": file.name,
          "file_data": base64Encode(fileBytes),
        },
        "id": 1,
      }),
    );

    print("🔹 Upload File Response: ${response.body}");

    if (response.statusCode != 200) {
      print('❌ Failed to upload file: ${response.statusCode} ${response.body}');
      return false;
    }

    final responseData = jsonDecode(response.body);
    if (responseData["error"] != null) {
      print("❌ Server Error: ${responseData["error"]}");
      return false;
    }

    final result = responseData["result"];
    return result is Map && result["success"] == true;
  } catch (e) {
    print('❌ Error uploading file: $e');
    return false;
  }
}

Future<List<Map<String, dynamic>>> getTicketAttachments(int ticketId) async {
  bool isAuthenticated = await checkAndLoadUserCredentials();
  if (!isAuthenticated) {
    print("❌ User not authenticated");
    return [];
  }

  try {
    // Use the standard Odoo JSON-RPC endpoint instead of a custom endpoint
    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "helpdesk.ticket",
            "search_read",
            [[["id", "=", ticketId]]],
            {"fields": ["attachment_ids"]}
          ]
        },
        "id": 5,
      }),
    );

    final responseData = json.decode(response.body);
    print("🔹 Attachments Response: ${response.body}");

    if (responseData["result"] != null && responseData["result"].isNotEmpty) {
      final ticket = responseData["result"][0];
      if (ticket["attachment_ids"] != null) {
        // Fetch attachment details
        final attachmentIds = List<int>.from(ticket["attachment_ids"]);
        if (attachmentIds.isEmpty) {
          return [];
        }

        final attachmentResponse = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
              "service": "object",
              "method": "execute_kw",
              "args": [
                database,
                int.parse(_userId!),
                _password,
                "ir.attachment",
                "search_read",
                [[["id", "in", attachmentIds]]],
                {"fields": ["name", "mimetype", "url"]}
              ]
            },
            "id": 6,
          }),
        );

        final attachmentData = json.decode(attachmentResponse.body);
        if (attachmentData["result"] != null) {
          return List<Map<String, dynamic>>.from(attachmentData["result"]);
        }
      }
    }
    
    print("⚠️ No attachments found for ticket ID: $ticketId");
    return [];
  } catch (e) {
    print("❌ Error fetching attachments: $e");
    return [];
  }
}

Future<bool> closeTicket(int ticketId) async {
  bool isAuthenticated = await checkAndLoadUserCredentials();
  if (!isAuthenticated) return false;

  try {
    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "helpdesk.ticket",
            "write",
            [[ticketId], {"stage_id": 5}] // Using stage_id 5 for Cancelled status
          ]
        },
        "id": 1,
      }),
    );

    print("🔹 Close Ticket Response: ${response.body}");

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      return responseData["result"] == true;
    }
    return false;
  } catch (e) {
    print("❌ Error closing ticket: $e");
    return false;
  }
}

Future<bool> markTicketAsClosed(int ticketId) async {
  lastErrorMessage = null;
  final safeTicketId = int.tryParse(ticketId.toString());
  if (safeTicketId == null || safeTicketId <= 0) {
    lastErrorMessage = "Invalid ticket id: $ticketId";
    return false;
  }

  bool isAuthenticated = false;
  try {
    isAuthenticated = await checkAndLoadUserCredentials();
  } catch (e) {
    lastErrorMessage = "Authentication error: $e";
    debugPrint("❌ $lastErrorMessage");
    return false;
  }
  if (!isAuthenticated) {
    lastErrorMessage = "Not authenticated. Please login again.";
    return false;
  }

  // Prefer the same pattern used in the other app (myerp): close via JSON-RPC.
  // This avoids type-casting issues that may happen through controller kwargs.
  final rpcSuccess = await _markTicketAsClosedViaRpc(safeTicketId);
  if (rpcSuccess) return true;

  try {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString('sessionId') ?? '';

    if (sessionId.isEmpty) {
      lastErrorMessage = "Session expired. Please login again.";
      // Session cookie missing; fall back to RPC (uses uid/password).
      return false;
    }

    debugPrint("🔍 Closing ticketId=$safeTicketId (type=${safeTicketId.runtimeType}) via /close_ticket");

    final requestBody = jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'ticket_id': safeTicketId, // keep as int
      },
      'id': 1,
    });
    debugPrint("🔍 /close_ticket requestBody: $requestBody");

    final response = await http.post(
      Uri.parse('$baseUrl/close_ticket'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'session_id=$sessionId',
      },
      // Odoo `type='json'` controllers expect JSON-RPC envelope where args live under `params`.
      body: requestBody,
    );

    debugPrint("🔹 Close Ticket (/close_ticket) Status: ${response.statusCode}");
    debugPrint("🔹 Close Ticket (/close_ticket) Body: ${response.body}");

    if (response.statusCode != 200) {
      lastErrorMessage = "HTTP ${response.statusCode}: Failed to close ticket.";
      return false;
    }

    final data = jsonDecode(response.body);
    if (data is Map<String, dynamic>) {
      // Odoo may wrap the controller return under `result` even if it contains an `error`.
      final topError = data['error'];
      if (topError is Map<String, dynamic>) {
        lastErrorMessage = topError['message']?.toString() ?? "Failed to close ticket.";
        return await _markTicketAsClosedViaRpc(ticketId);
      }

      final result = data['result'];
      if (result is Map<String, dynamic>) {
        final nestedError = result['error'];
        if (nestedError is Map<String, dynamic>) {
          lastErrorMessage = nestedError['message']?.toString() ?? "Failed to close ticket.";
          // If server complains about ticket_id type, fall back to RPC call.
          return false;
        }

        // Our controller returns { "result": { "success": true, ... } }
        final nestedResult = result['result'];
        if (nestedResult is Map<String, dynamic> && nestedResult['success'] == true) {
          lastErrorMessage = null;
          return true;
        }

        if (nestedResult is Map<String, dynamic> && nestedResult['message'] != null) {
          lastErrorMessage = nestedResult['message']?.toString();
          return false;
        }

        if (result['message'] != null) {
          lastErrorMessage = result['message']?.toString();
          return false;
        }
      }
    }

    lastErrorMessage = "Failed to close ticket.";
    return false;
  } catch (e) {
    lastErrorMessage = "Error closing ticket: $e";
    debugPrint("❌ $lastErrorMessage");
    return false;
  }
}

Future<bool> _markTicketAsClosedViaRpc(int ticketId) async {
  try {
    if (_userId == null || _password == null) {
      lastErrorMessage = lastErrorMessage ?? "Missing credentials. Please login again.";
      return false;
    }

    debugPrint("🔁 Fallback: closing ticketId=$ticketId via JSON-RPC execute_kw(helpdesk.ticket.close_ticket)");

    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "helpdesk.ticket",
            "close_ticket",
            [ticketId],
          ]
        },
        "id": 99,
      }),
    );

    debugPrint("🔹 Close Ticket (RPC close_ticket) Status: ${response.statusCode}");
    debugPrint("🔹 Close Ticket (RPC close_ticket) Body: ${response.body}");

    if (response.statusCode != 200) {
      lastErrorMessage = "HTTP ${response.statusCode}: Failed to close ticket (RPC).";
      return false;
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      lastErrorMessage = "Invalid response from server (RPC).";
      return false;
    }

    final topError = data['error'];
    if (topError is Map<String, dynamic>) {
      lastErrorMessage = topError['message']?.toString() ?? "Failed to close ticket (RPC).";
      return false;
    }

    final result = data['result'];
    if (result is Map<String, dynamic>) {
      // Python method returns either {error:{...}} or {result:{success:true,...}}
      final nestedError = result['error'];
      if (nestedError is Map<String, dynamic>) {
        lastErrorMessage = nestedError['message']?.toString() ?? "Failed to close ticket (RPC).";
        return false;
      }
      final nestedResult = result['result'];
      if (nestedResult is Map<String, dynamic> && nestedResult['success'] == true) {
        lastErrorMessage = null;
        return true;
      }
      if (nestedResult is Map<String, dynamic> && nestedResult['message'] != null) {
        lastErrorMessage = nestedResult['message']?.toString();
        return false;
      }
    }

    // Some implementations may directly return a boolean
    if (result == true) {
      lastErrorMessage = null;
      return true;
    }

    lastErrorMessage = lastErrorMessage ?? "Failed to close ticket (RPC).";
    return false;
  } catch (e) {
    lastErrorMessage = "Error closing ticket (RPC): $e";
    debugPrint("❌ $lastErrorMessage");
    return false;
  }
}

Future<bool> submitFeedbackToOdoo({
  required int ticketId,
  required double scale1,
  required double scale2,
  required double scale3,
  required double scale4,
  required double scale5,
  required double scale6,
  required Uint8List signatureBytes,
}) async {
  bool isAuthenticated = await checkAndLoadUserCredentials();
  if (!isAuthenticated) return false;

  try {
    String base64Signature = base64Encode(signatureBytes);

    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!),
            _password,
            "helpdesk.ticket",
            "write",
            [
              [ticketId],
              {
                "feedback_scale1": scale1.toInt().toString(),
                "feedback_scale2": scale2.toInt().toString(),
                "feedback_scale3": scale3.toInt().toString(),
                "feedback_scale4": scale4.toInt().toString(),
                "feedback_scale5": scale5.toInt().toString(),
                "feedback_scale6": scale6.toInt().toString(),
                "customer_signature": base64Signature,
              }
            ]
          ]
        },
        "id": 20,
      }),
    );

    final data = jsonDecode(response.body);
    return data["result"] == true;
  } catch (e) {
    print("❌ Error submit feedback: $e");
    return false;
  }
}

Future<String?> fetchUserImage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userIdStr = prefs.getString('user_id') ?? _userId ?? '';
    final pwd = prefs.getString('user_password') ?? _password;
    if (userIdStr.isEmpty || pwd == null || pwd.isEmpty) {
      return null;
    }
    final uid = int.tryParse(userIdStr);
    if (uid == null) return null;

    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'service': 'object',
          'method': 'execute_kw',
          'args': [
            database,
            uid,
            pwd,
            'res.users',
            'read',
            [
              [uid]
            ],
            ['image_128'],
          ],
        },
        'id': 1,
      }),
    );

    if (response.statusCode != 200) {
      debugPrint(
          'User image: HTTP ${response.statusCode} (no avatar cached).');
      return null;
    }
    final data = jsonDecode(response.body);
    if (data['error'] != null) {
      debugPrint('User image: Odoo RPC error (no avatar cached).');
      return null;
    }
    final result = data['result'];
    if (result is List && result.isNotEmpty) {
      final row = result[0];
      if (row is Map<String, dynamic>) {
        final img = row['image_128'];
        if (img is String && img.isNotEmpty) {
          return img;
        }
      }
    }
  } catch (e) {
    debugPrint('User image fetch failed: $e');
  }
  return null;
}

Future<List<dynamic>> fetchAllTicketsForAdmin(String db, int uid, String password) async {
  debugPrint("🔍 Fetching all tickets as admin from DB: $db, UID: $uid");

  try {
    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'service': 'object',
          'method': 'execute_kw',
          'args': [
            db,
            uid,
            password,
            'helpdesk.ticket',
            'search_read',
            [[]], // ✅ Correct domain structure
            {
              'fields': [
                'id',
                'name',
                'ticket_number_display',
                'category_name',
                'stage_id',
                'stage_name',
                'create_date',
                'user_id',
                'priority',
                'description',
                'partner_name',
                'address',
                'prob_name',
                'sub_name',
                'serial_name',
                'equipment_user',
                'person_name',
                'department',
                'partner_email',
                'partner_phone'
              ],
              'order': 'create_date desc',
            },
          ],
        },
        'id': 1,
      }),
    );

    debugPrint("📡 Response status code: ${response.statusCode}");
    debugPrint("📡 Response body: ${response.body}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['result'] != null) {
        final tickets = data['result'] as List<dynamic>;
        debugPrint("✅ Fetched ${tickets.length} tickets successfully");
        return tickets;
      } else {
        debugPrint("❌ No result in response: ${data['error']}");
        return [];
      }
    } else {
      debugPrint("❌ Failed to fetch tickets. Status code: ${response.statusCode}");
      return [];
    }
  } catch (e) {
    debugPrint("❌ Exception occurred in fetchAllTicketsForAdmin: $e");
    return [];
  }
}

Future<bool> isAdmin() async {
  try {
    await loadSessionCredentials();
    if (_userId == null || _password == null) {
      final ok = await checkAndLoadUserCredentials();
      if (!ok) {
        debugPrint("❌ User ID or password is null");
        return false;
      }
    }
    debugPrint("🔍 Checking admin status for user ID: $_userId");

    final url = Uri.parse(jsonRpcUrl);
    final payload = {
      "jsonrpc": "2.0",
      "method": "call",
      "params": {
        "service": "object",
        "method": "execute_kw",
        "args": [
          database,
          int.parse(_userId!),
          _password,
          "res.users",
          "has_group",
          [
            "base.group_system" // ✅ Betul: hanya 1 argumen
          ]
        ]
      },
      "id": 1
    };

    debugPrint("📤 Sending admin check request: ${json.encode(payload)}");

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(payload),
    );

    debugPrint("📡 Admin check response: ${response.body}");

    if (response.statusCode == 200) {
      final Map<String, dynamic> responseData = json.decode(response.body);
      if (responseData.containsKey('result')) {
        final isAdmin = responseData['result'] == true;
        debugPrint("✅ Admin check result: $isAdmin");
        return isAdmin;
      } else {
        debugPrint("❌ No result key in response.");
      }
    } else {
      debugPrint("❌ Admin check failed: ${response.statusCode}");
    }

    return false;
  } catch (e) {
    debugPrint("❌ Error checking admin status: $e");
    return false;
  }
}

Future<void> initAndSendFcmToken() async {
  String? token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    print("📱 FCM Token: $token");
    await sendFcmToken(token);
  } else {
    print("❌ Could not get FCM token.");
  }
}

Future<bool> sendFcmToken(String token) async {
  if (_userId == null) {
    print("❌ User not logged in, cannot send FCM token.");
    bool reAuthenticated = await checkAndLoadUserCredentials();
    if (!reAuthenticated || _userId == null) {
      print("❌ Re-authentication failed, cannot send FCM token.");
      return false;
    }
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('session_id');
    final uid = int.tryParse(_userId!);

    if (sessionCookie == null || uid == null) {
      print("❌ Session or user id missing. Cannot send FCM token.");
      return false;
    }

    // Odoo `helpdesk_ticket.store_fcm_token_api` reads `request.jsonrequest`
    // for `user_id` and `token` — POST to /api/fcm/token, not /jsonrpc.
    final response = await http.post(
      Uri.parse('$baseUrl/api/fcm/token'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': sessionCookie,
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'user_id': uid,
          'token': token,
        },
        'id': 1,
      }),
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);

      if (responseData.containsKey('error')) {
        final error = responseData['error'];
        print(
            "❌ Failed to send FCM Token: ${error['data']?['message'] ?? error['message']}");
        return false;
      }

      bool rpcSuccess(dynamic node, [int depth = 0]) {
        if (depth > 6 || node == null) return false;
        if (node is Map) {
          if (node['success'] == true) return true;
          if (node['error'] != null) return false;
          for (final v in node.values) {
            if (rpcSuccess(v, depth + 1)) return true;
          }
        }
        return false;
      }

      if (rpcSuccess(responseData)) {
        print("✅ FCM token sent successfully.");
        return true;
      }

      print("❌ Failed to send FCM Token: ${responseData['result'] ?? responseData}");
      return false;
    } else {
      print(
          "❌ Error sending FCM token. Status Code: ${response.statusCode}, Response: ${response.body}");
      return false;
    }
  } catch (e) {
    print("❌ Exception while sending FCM token: $e");
    return false;
  }
}

Future<bool> submitTechnicianResolution(int ticketId, String resolution) async {
  if (_password == null || _userId == null) {
    print("⚠️ User not authenticated. Please login first.");
    return false;
  }

  try {
    final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('session_id');
    if (sessionCookie == null) {
      print("❌ Session cookie not found. User needs to re-authenticate.");
      return false;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/api/update_resolution_tech'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': sessionCookie,
      },
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "ticket_id": ticketId,
          "resolution": resolution,
        },
        "id": 1,
      }),
    );

    print("🔹 Technician Resolution Response: ${response.body}");
    if (response.statusCode != 200) return false;

    final responseData = jsonDecode(response.body);
    if (responseData["error"] != null) return false;

    final result = responseData["result"];
    if (result is Map && result["success"] == true) return true;
    if (result is Map && result["result"] is Map && (result["result"] as Map)["success"] == true) return true;
    return false;
  } catch (e) {
    print("❌ Error submitting Technician Resolution: $e");
    return false;
  }
}

Future<bool> setNotificationEmail(String notificationEmail) async {
    // Ensure user is authenticated before making the call
    if (_userId == null || _password == null) {
      print("❌ User not authenticated. Cannot set notification email.");
      bool reAuthenticated = await checkAndLoadUserCredentials();
      if (!reAuthenticated) {
        return false;
      }
    }

    try {
      // For 'auth=user' endpoints, Odoo uses the session cookie for authentication.
      final prefs = await SharedPreferences.getInstance();
      final String? sessionCookie = prefs.getString('session_id');

      if (sessionCookie == null) {
        print("❌ Session cookie not found. The user might need to log in again.");
        return false;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/set_notification_email'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': sessionCookie, // Pass the session cookie for authentication
        },
        body: jsonEncode({
          "params": {
            "notification_email": notificationEmail,
          }
        }),
      );

      print("🔹 Set Notification Email Response: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['result'] != null && responseData['result']['success'] == true) {
          print("✅ Notification email updated successfully on the backend.");
          return true;
        } else {
          final errorMessage = responseData['error']?['data']?['message'] ?? responseData['error']?['message'] ?? 'Unknown error';
          print("❌ Failed to update notification email on backend: $errorMessage");
          return false;
        }
      } else {
        print("❌ Error setting notification email. Status Code: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("❌ Exception while setting notification email: $e");
      return false;
    }
  }

Future<Map<String, dynamic>> fetchUserData(String email, String password) async {
  final response = await http.post(
    Uri.parse('https://myerp.com.my/jsonrpc'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'jsonrpc': '2.0',
      'method': 'call',
      'params': {
        'service': 'object',
        'method': 'execute_kw',
        'args': [
          'your_db_name',
          2,
          password,
          'res.users',
          'search_read',
          [
            ['login', '=', email]
          ],
          {
            'fields': ['id', 'name', 'status'],  // pastikan 'status' wujud
            'limit': 1,
          },
        ],
      },
      'id': 1,
    }),
  );

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    return data['result'][0];
  } else {
    throw Exception('Login failed');
  }
}




Future<void> sendTicketNotification(String userToken, String ticketTitle, String ticketId) async {
  final String fcmUrl = 'https://myerp.com.my/fcm/send';
  final Map<String, String> headers = {
    'Content-Type': 'application/json',
    'Authorization': 'key=YOUR_FIREBASE_SERVER_KEY_HERE',
  };

  final Map<String, dynamic> notificationPayload = {
    'to': userToken,
    'notification': {
      'title': 'New Ticket Assigned',
      'body': 'A new ticket has been assigned to you: $ticketTitle',
    },
    'data': {
      'ticket_id': ticketId,
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
    },
  };

  final response = await http.post(
    Uri.parse(fcmUrl),
    headers: headers,
    body: json.encode(notificationPayload),
  );

  if (response.statusCode == 200) {
    print("✅ FCM Notification Sent Successfully.");
  } else {
    print("❌ Failed to send FCM Notification: ${response.body}");
  }
}

Future<void> _sendFcmToken(String? token) async {
  if (token == null) {
    print('FCM Token is null, cannot send to server.');
    return;
  }

  try {
    // Dapatkan instance OdooService (anda mungkin perlu sesuaikan dengan cara anda)
    OdooService odooService = OdooService();

    // Pastikan user_id wujud sebelum menghantar
    bool isAuthenticated = await odooService.checkAndLoadUserCredentials();
    if (isAuthenticated && odooService._userId != null) {
      bool success = await odooService.sendFcmToken(token);
      if (success) {
        print('✅ FCM Token sent successfully to Odoo.');
      } else {
        print('❌ Failed to send FCM Token to Odoo.');
      }
    } else {
      print('User is not authenticated, cannot send FCM token.');
    }
  } catch (e) {
    print('An error occurred while sending FCM token: $e');
  }
}

  Future<bool> createProjectTask({
    required String title,
    required String project,
    required int assignedUserId,
    required DateTime dueDate,
    String? description,
  }) async {
    bool isAuthenticated = await checkAndLoadUserCredentials();
    if (!isAuthenticated) return false;

    try {
      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "project.task",
              "create",
              [
                {
                  "name": title,
                  "project_id": project, // You may need to resolve project name to project_id
                  "user_ids": [[6, false, [assignedUserId]]],
                  "date_deadline": dueDate.toIso8601String().split('T')[0],
                  if (description != null) "description": description,
                }
              ]
            ]
          },
          "id": 1,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData["result"] != null) {
          print("✅ Task created in Odoo: "+responseData["result"].toString());
          return true;
        } else {
          print("❌ Failed to create task: ${response.body}");
          return false;
        }
      } else {
        print("❌ HTTP error creating task: ${response.statusCode}, ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Error creating project.task: $e");
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchLeaves(int year, int month) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    final response = await http.post(
      Uri.parse('https://myerp.com.my/api/leaves'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'employee_id': int.parse(userId!),
        'year': year,
        'month': month,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final leaves = data['result'] ?? [];
      return List<Map<String, dynamic>>.from(leaves);
    } else {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchLeavesWithUserId(String? userId, int year, int month) async {
    if (userId == null) return [];
    
    // Get employee_id for this user first
    int? employeeId;
    try {
      final employeeData = await checkEmployeeData(int.parse(userId));
      if (employeeData['result'] != null && employeeData['result']['employee'] != null) {
        employeeId = employeeData['result']['employee']['id'];
        print('🔍 DEBUG: Found employee_id: $employeeId for user_id: $userId');
      }
    } catch (e) {
      print('❌ DEBUG: Error getting employee_id: $e');
    }
    
    final requestBody = {
      'user_id': int.parse(userId),
      'employee_id': employeeId, // Add employee_id to request
      'year': year,
      'month': month,
    };
    
    print('🔍 DEBUG: Fetching leaves with request: $requestBody');
    print('🔍 DEBUG: User ID: $userId, Employee ID: $employeeId, Year: $year, Month: $month');
    
    final response = await http.post(
      Uri.parse('https://myerp.com.my/api/leaves'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );
    
    print('🔍 DEBUG: Leaves response status: ${response.statusCode}');
    print('🔍 DEBUG: Leaves response body: ${response.body}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final leaves = data['result'] ?? [];
      
      print('✅ Fetched ${leaves.length} leaves for user $userId');
      
      // Debug: Show each leave
      for (var leave in leaves) {
        print('🔍 DEBUG: Leave ID: ${leave['id']}, Employee: ${leave['employee_name']}, Type: ${leave['leave_type']}, State: ${leave['state']}');
      }
      
      return List<Map<String, dynamic>>.from(leaves);
    } else {
      print('❌ Error fetching leaves with user_id: ${response.statusCode} ${response.body}');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchApprovalLeaves() async {
    try {
      final requestBody = {
        'approval_only': true, // Flag to get only leaves that need approval
      };
      
      print('🔍 DEBUG: Fetching approval leaves with request: $requestBody');
      
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/leaves'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      print('🔍 DEBUG: Approval leaves response status: ${response.statusCode}');
      print('🔍 DEBUG: Approval leaves response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final leaves = data['result'] ?? [];
        print('✅ Fetched ${leaves.length} approval leaves');
        
        // Debug: Check for specific leave ID
        for (var leave in leaves) {
          if (leave['id'] == 76) {
            print('🎯 DEBUG: Leave 76 found in API response with state: ${leave['state']}');
          }
        }
        
        return List<Map<String, dynamic>>.from(leaves);
      } else {
        print('❌ Error fetching approval leaves: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Exception fetching approval leaves: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchManagerApprovalLeaves(int managerId) async {
    try {
      final requestBody = {
        'manager_id': managerId,
      };
      
      print('🔍 DEBUG: Fetching manager approval leaves with request: $requestBody');
      print('🔍 DEBUG: Manager ID type: ${managerId.runtimeType}, value: $managerId');
      
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/leaves/manager/list'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );
      
      print('🔍 DEBUG: Manager approval leaves response status: ${response.statusCode}');
      print('🔍 DEBUG: Manager approval leaves response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔍 DEBUG: Response data type: ${data.runtimeType}');
        
        final leaves = data['result'] ?? [];
        print('✅ Fetched ${leaves.length} manager approval leaves');
        
        // Debug: Show each leave
        for (var leave in leaves) {
          print('🔍 DEBUG: Leave ID: ${leave['id']}, Employee: ${leave['employee_name']}, State: ${leave['state']}');
        }
        
        return List<Map<String, dynamic>>.from(leaves);
      } else {
        print('❌ Error fetching manager approval leaves: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Exception fetching manager approval leaves: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> managerApproveLeave(int leaveId, int managerId) async {
    try {
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/leaves/manager/approve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'leave_id': leaveId,
          'manager_id': managerId,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Leave approved by manager successfully: $leaveId');
        print('🔍 DEBUG: Manager approval response data: $data');
        return data;
      } else {
        print('❌ Error approving leave by manager: ${response.statusCode} ${response.body}');
        return {'success': false, 'error': 'Server error: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ Exception approving leave by manager: $e');
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  Future<bool> isUserManager(int userId) async {
    try {
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/leaves/manager/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
        }),
      );
      
      print('🔍 DEBUG: Manager check response status: ${response.statusCode}');
      print('🔍 DEBUG: Manager check response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔍 DEBUG: Manager check response data: $data');
        print('🔍 DEBUG: Response data type: ${data.runtimeType}');
        
        // Handle different response formats
        bool isManager = false;
        if (data is Map<String, dynamic>) {
          print('🔍 DEBUG: Data is Map<String, dynamic>');
          print('🔍 DEBUG: Data keys: ${data.keys.toList()}');
          
          if (data.containsKey('result')) {
            final result = data['result'];
            print('🔍 DEBUG: Result value: $result (type: ${result.runtimeType})');
            isManager = result == true;
          } else if (data.containsKey('success')) {
            final success = data['success'];
            print('🔍 DEBUG: Success value: $success (type: ${success.runtimeType})');
            isManager = success == true;
          }
        } else {
          print('🔍 DEBUG: Data is not Map<String, dynamic>');
        }
        
        print('🔍 DEBUG: User $userId is manager: $isManager');
        return isManager;
      } else {
        print('❌ Error checking if user is manager: ${response.statusCode} ${response.body}');
        // Return false if API error, but don't throw exception
        return false;
      }
    } catch (e) {
      print('❌ Exception checking if user is manager: $e');
      print('❌ Exception type: ${e.runtimeType}');
      // Return false if exception, but don't re-throw
      return false;
    }
  }

  Future<Map<String, dynamic>> checkEmployeeData(int userId) async {
    try {
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/leaves/employee/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
        }),
      );
      
      print('🔍 DEBUG: Employee check response status: ${response.statusCode}');
      print('🔍 DEBUG: Employee check response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('🔍 DEBUG: Employee check response data: $data');
        return data;
      } else {
        print('❌ Error checking employee data: ${response.statusCode} ${response.body}');
        return {'result': false, 'error': 'Server error: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ Exception checking employee data: $e');
      return {'result': false, 'error': 'Exception: $e'};
    }
  }

  Future<Map<String, dynamic>> approveLeave(int leaveId) async {
    try {
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/leaves/approve'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'leave_id': leaveId,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Leave approved successfully: $leaveId');
        print('🔍 DEBUG: Approval response data: $data');
        return data;
      } else {
        print('❌ Error approving leave: ${response.statusCode} ${response.body}');
        return {'success': false, 'error': 'Server error: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ Exception approving leave: $e');
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  Future<Map<String, dynamic>> refuseLeave(int leaveId) async {
    try {
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/leaves/refuse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'leave_id': leaveId,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ Leave refused successfully: $leaveId');
        return data;
      } else {
        print('❌ Error refusing leave: ${response.statusCode} ${response.body}');
        return {'success': false, 'error': 'Server error: ${response.statusCode}'};
      }
    } catch (e) {
      print('❌ Exception refusing leave: $e');
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  Future<Map<String, dynamic>> createLeaveRequest({
    required String? userId,
    required DateTime? dateFrom,
    required DateTime? dateTo,
    required String leaveType,
    required String description,
  }) async {
    if (userId == null || dateFrom == null || dateTo == null) {
      return {'success': false, 'error': 'Missing required fields'};
    }

    // Format dates as 'yyyy-MM-dd HH:mm:ss' for backend compatibility
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final dateFromStr = dateFormat.format(dateFrom);
    final dateToStr = dateFormat.format(dateTo);

    final requestBody = {
      'user_id': userId,
      'date_from': dateFromStr,
      'date_to': dateToStr,
      'leave_type': leaveType,
      'description': description,
    };

    print('🔍 DEBUG: Creating leave request with data: $requestBody');

    final response = await http.post(
      Uri.parse('$baseUrl/api/leaves/create'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );
    print('🔍 DEBUG: Response status: ${response.statusCode}');
    print('🔍 DEBUG: Response body: ${response.body}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('🔍 DEBUG: Parsed response data: $data');
      return data['result'] ?? {};
    } else {
      print('❌ DEBUG: Server error response: ${response.body}');
      return {'success': false, 'error': 'Server error: ${response.statusCode} - ${response.body}'};
    }
  }

  Future<List<Map<String, dynamic>>> fetchProjectsFromOdoo() async {
    try {
      print('🔍 DEBUG: fetchProjectsFromOdoo() called');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      print('🔍 DEBUG: User ID from prefs: $userId');
      print('🔍 DEBUG: Password exists: ${password != null}');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated - userId: $userId, password exists: ${password != null}');
        return [];
      }

      // First test connection
      final isConnected = await testOdooConnection();
      if (!isConnected) {
        print('❌ Cannot connect to Odoo server');
        return [];
      }

      // Check user groups
      final groupInfo = await checkUserGroups();
      if (!groupInfo['has_project_access']) {
        print('❌ User does not have project access permissions');
        print('🔍 DEBUG: User groups: ${groupInfo['groups']}');
        return [];
      }

      print('🔍 DEBUG: Making request to Odoo...');
      print('🔍 DEBUG: URL: $jsonRpcUrl');
      print('🔍 DEBUG: Database: $database');

      final response = await http.post(
        Uri.parse('$jsonRpcUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'project.project',
              'search_read',
              [[]], // Try without any domain filter first
              {
                'fields': [
                  'id', 
                  'name', 
                  'description', 
                  'partner_id', 
                  'company_id', 
                  'user_id', 
                  'date_start',
                  'date', // expiration date
                  'color',
                  'sequence',
                  'allow_subtasks',
                  'allow_recurring_tasks',
                  'allow_task_dependencies',
                  'privacy_visibility',
                  'label_tasks',
                  'task_count',
                  'task_count_with_subtasks',
                  'doc_count',
                  'is_favorite',
                  // Removed stage_id - requires special permissions
                  'last_update_status',
                  'milestone_count',
                  'collaborator_count',
                  'rating_active',
                  'rating_status',
                  'create_date',
                  'write_date'
                ],
                'order': 'sequence, name',
                'limit': 100
              }
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Project fetch response status: ${response.statusCode}');
      print('🔍 DEBUG: Project fetch response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('🔍 DEBUG: Parsed result: $result');
        
        // Check for AccessError or other permission issues
        if (result.containsKey('error')) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Access Error or Permission Issue: $errorMessage');
          
          // If it's an AccessError, return empty list to trigger mock data fallback
          if (errorMessage.contains('AccessError') || 
              errorMessage.contains('Access Denied') ||
              errorMessage.contains('permission')) {
            print('🔍 DEBUG: Access denied, will use mock data as fallback');
            return [];
          }
          
          // For other errors, throw exception
          throw Exception('Odoo Server Error: $errorMessage');
        }
        
        if (result['result'] is List) {
          final projects = List<Map<String, dynamic>>.from(result['result']);
          print('🔍 DEBUG: Found ${projects.length} projects');
          
          // Process and enhance the project data
          for (var project in projects) {
            print('🔍 DEBUG: Processing project: ${project['name']}');
            
            // Convert partner_id from [id, name] to readable format
            if (project['partner_id'] is List && project['partner_id'].length >= 2) {
              project['partner_name'] = project['partner_id'][1];
              project['partner_id'] = project['partner_id'][0];
            }
            
            // Convert user_id from [id, name] to readable format
            if (project['user_id'] is List && project['user_id'].length >= 2) {
              project['manager_name'] = project['user_id'][1];
              project['user_id'] = project['user_id'][0];
            }
            
            // Convert company_id from [id, name] to readable format
            if (project['company_id'] is List && project['company_id'].length >= 2) {
              project['company_name'] = project['company_id'][1];
              project['company_id'] = project['company_id'][0];
            }
            
            // Set default values for missing fields
            project['description'] = project['description'] ?? '';
            project['task_count'] = project['task_count'] ?? 0;
            project['doc_count'] = project['doc_count'] ?? 0;
            project['is_favorite'] = project['is_favorite'] ?? false;
            project['color'] = project['color'] ?? 0;
            project['stage_id'] = null; // Set default since we removed it from fields
            project['stage_name'] = 'Default'; // Set default stage name
          }
          
          print('✅ Successfully fetched ${projects.length} projects');
          return projects;
        } else {
          print('❌ Result is not a list: ${result['result']}');
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
      }
      
      print('❌ Failed to fetch projects: ${response.body}');
      return [];
    } catch (e) {
      print('❌ Error fetching projects: $e');
      print('❌ Error stack trace: ${StackTrace.current}');
      
      // If it's an AccessError or permission issue, return empty list to trigger mock data
      if (e.toString().contains('AccessError') || 
          e.toString().contains('Access Denied') ||
          e.toString().contains('permission')) {
        print('🔍 DEBUG: Access denied detected, returning empty list for mock data fallback');
        return [];
      }
      
      return [];
    }
  }

  Future<Map<String, dynamic>> createProjectInOdoo({
    required String name,
    String? description,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated');
        return {'success': false, 'error': 'User not authenticated'};
      }

      // First check if user has project access
      final hasAccess = await checkProjectAccess();
      if (!hasAccess) {
        print('❌ User does not have project access permissions');
        return {
          'success': false, 
          'error': 'Permission denied. Contact administrator to grant project access.',
          'permission_issue': true
        };
      }

      final response = await http.post(
        Uri.parse('$jsonRpcUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'project.project',
              'create',
              [{
                'name': name,
                'description': description ?? '',
                'active': true,
                'privacy_visibility': 'employees',
                // Removed fields that require special permissions
                'rating_active': false,
              }]
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 Create project response status: ${response.statusCode}');
      print('🔍 Create project response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        if (result['result'] != null) {
          print('✅ Project created successfully with ID: ${result['result']}');
          return {
            'success': true,
            'project_id': result['result'],
            'message': 'Project created successfully'
          };
        } else if (result['error'] != null) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Failed to create project: $errorMessage');
          
          // Check if it's a permission issue
          if (errorMessage.contains('AccessError') || 
              errorMessage.contains('Access Denied') ||
              errorMessage.contains('permission')) {
            return {
              'success': false,
              'error': 'Permission denied. Contact administrator to grant project creation rights.',
              'permission_issue': true
            };
          }
          
          return {
            'success': false,
            'error': errorMessage
          };
        }
      }
      
      print('❌ Failed to create project: ${response.body}');
      return {'success': false, 'error': 'Server error: ${response.statusCode}'};
    } catch (e) {
      print('❌ Error creating project: $e');
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  // Test method to check if there are any projects in the database
  Future<Map<String, dynamic>> testProjectDatabase() async {
    try {
      print('🔍 DEBUG: Testing project database...');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        return {'success': false, 'error': 'User not authenticated'};
      }

      // First, let's check if we can access the project.project model
      final response = await http.post(
        Uri.parse('$jsonRpcUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'project.project',
              'search',
              [[]], // Search all projects
              {'limit': 1}
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Test response status: ${response.statusCode}');
      print('🔍 DEBUG: Test response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['result'] != null) {
          final projectIds = result['result'] as List;
          print('🔍 DEBUG: Found ${projectIds.length} project IDs: $projectIds');
          
          if (projectIds.isNotEmpty) {
            // Try to read the first project
            final readResponse = await http.post(
              Uri.parse('$jsonRpcUrl'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'jsonrpc': '2.0',
                'method': 'call',
                'params': {
                  'service': 'object',
                  'method': 'execute_kw',
                  'args': [
                    database,
                    int.parse(userId),
                    password,
                    'project.project',
                    'read',
                    [projectIds.first],
                    {'fields': ['id', 'name', 'active']}
                  ]
                },
                'id': 2,
              }),
            );

            print('🔍 DEBUG: Read response: ${readResponse.body}');
            
            if (readResponse.statusCode == 200) {
              final readResult = jsonDecode(readResponse.body);
              return {
                'success': true,
                'project_count': projectIds.length,
                'first_project': readResult['result'] ?? 'No data'
              };
            }
          }
          
          return {
            'success': true,
            'project_count': projectIds.length,
            'message': 'No projects found in database'
          };
        }
      }
      
      return {'success': false, 'error': 'Failed to test database'};
    } catch (e) {
      print('❌ Error testing project database: $e');
      return {'success': false, 'error': 'Exception: $e'};
    }
  }

  // Method to get mock project data for testing
  Future<List<Map<String, dynamic>>> getMockProjects() async {
    print('🔍 DEBUG: Returning mock project data for testing');
    return [
      {
        'id': 1,
        'name': 'Test Project 1',
        'description': 'This is a test project for debugging the UI',
        'manager_name': 'John Doe',
        'manager_email': 'john.doe@company.com',
        'task_count': 5,
        'doc_count': 2,
        'milestone_count': 1,
        'date_start': '2024-01-01',
        'date': '2024-12-31',
        'last_update_status': 'on_track',
        'is_favorite': true,
        'color': 1,
      },
      {
        'id': 2,
        'name': 'Sample Project 2',
        'description': 'Another test project to verify the UI works correctly',
        'manager_name': 'Jane Smith',
        'manager_email': 'jane.smith@company.com',
        'task_count': 3,
        'doc_count': 1,
        'milestone_count': 0,
        'date_start': '2024-02-01',
        'date': '2024-11-30',
        'last_update_status': 'at_risk',
        'is_favorite': false,
        'color': 2,
      },
      {
        'id': 3,
        'name': 'Development Project',
        'description': 'A longer description to test how the UI handles longer text content in the project description field',
        'manager_name': 'Mike Johnson',
        'manager_email': 'mike.johnson@company.com',
        'task_count': 8,
        'doc_count': 4,
        'milestone_count': 2,
        'date_start': '2024-03-01',
        'date': '2024-10-31',
        'last_update_status': 'off_track',
        'is_favorite': true,
        'color': 3,
      },
    ];
  }

  // Check if user has project access permissions
  Future<bool> checkProjectAccess() async {
    try {
      print('🔍 DEBUG: Checking project access permissions...');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated');
        return false;
      }

      // Try to access project.project model with minimal fields
      final response = await http.post(
        Uri.parse('$jsonRpcUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'project.project',
              'search',
              [[]],
              {'limit': 1}
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Permission check response: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result.containsKey('error')) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Permission check failed: $errorMessage');
          return false;
        }
        
        print('✅ User has project access permissions');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking project access: $e');
      return false;
    }
  }

  // Get user's access rights information
  Future<Map<String, dynamic>> getUserAccessRights() async {
    try {
      print('🔍 DEBUG: Getting user access rights...');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        return {'has_access': false, 'error': 'User not authenticated'};
      }

      // Check various project-related permissions
      final response = await http.post(
        Uri.parse('$jsonRpcUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'res.users',
              'has_group',
              [
                'project.group_project_user' // Check if user has project user group
              ]
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Access rights response: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result.containsKey('error')) {
          return {'has_access': false, 'error': result['error']['data']['message'] ?? 'Unknown error'};
        }
        
        final hasProjectAccess = result['result'] == true;
        return {
          'has_access': hasProjectAccess,
          'user_id': userId,
          'message': hasProjectAccess ? 'User has project access' : 'User needs project permissions'
        };
      }
      
      return {'has_access': false, 'error': 'Failed to check permissions'};
    } catch (e) {
      print('❌ Error getting user access rights: $e');
      return {'has_access': false, 'error': 'Exception: $e'};
    }
  }

  // Get administrator instructions for granting project access
  Future<String> getAdminInstructions() async {
    return '''
To grant project access to users in Odoo:

1. **Add User to Project Group:**
   - Go to Settings > Users & Companies > Users
   - Find the user and edit their record
   - In the "Access Rights" tab, add them to "Project User" group

2. **Grant Model Access:**
   - Go to Settings > Technical > Security > Access Control Lists
   - Create or edit ACL for "project.project" model
   - Add the user's group with read/write/create access

3. **Alternative Method:**
   - Go to Settings > Users & Companies > Users
   - Edit the user record
   - In "Access Rights" tab, manually add:
     * project.project: read, write, create
     * project.task: read, write, create

4. **Check Permissions:**
   - The user should be able to access Projects menu
   - They should see existing projects and be able to create new ones

Note: These changes require administrator privileges in Odoo.
''';
  }

  // Check user groups and permissions
  Future<Map<String, dynamic>> checkUserGroups() async {
    try {
      print('🔍 DEBUG: Checking user groups...');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        return {'success': false, 'error': 'User not authenticated'};
      }

      // Check various project-related groups
      final groups = [
        'project.group_project_user',
        'project.group_project_manager', 
        'base.group_user',
        'base.group_system'
      ];

      Map<String, bool> groupResults = {};
      
      for (String group in groups) {
        try {
          final response = await http.post(
            Uri.parse('$jsonRpcUrl'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {
                'service': 'object',
                'method': 'execute_kw',
                'args': [
                  database,
                  int.parse(userId),
                  password,
                  'res.users',
                  'has_group',
                  [group]
                ]
              },
              'id': 1,
            }),
          );

          if (response.statusCode == 200) {
            final result = jsonDecode(response.body);
            if (result.containsKey('error')) {
              print('❌ Error checking group $group: ${result['error']}');
              groupResults[group] = false;
            } else {
              groupResults[group] = result['result'] == true;
              print('🔍 DEBUG: Group $group: ${result['result']}');
            }
          } else {
            print('❌ HTTP error checking group $group: ${response.statusCode}');
            groupResults[group] = false;
          }
        } catch (e) {
          print('❌ Exception checking group $group: $e');
          groupResults[group] = false;
        }
      }

      print('🔍 DEBUG: User groups: $groupResults');
      
      // Check if user has any project access
      bool hasProjectAccess = groupResults['project.group_project_user'] == true || 
                             groupResults['project.group_project_manager'] == true;
      
      return {
        'success': true,
        'has_project_access': hasProjectAccess,
        'groups': groupResults,
        'user_id': userId,
        'message': hasProjectAccess 
          ? 'User has project access' 
          : 'User needs project permissions'
      };
      
    } catch (e) {
      print('❌ Error checking project groups: $e');
      return {
        'success': false, 
        'error': 'Connection error: $e',
        'has_project_access': false
      };
    }
  }

  // Test connection to Odoo server
  Future<bool> testOdooConnection() async {
    try {
      print('🔍 DEBUG: Testing Odoo connection...');
      
      final response = await http.post(
        Uri.parse('$jsonRpcUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'common',
            'method': 'version',
            'args': []
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Connection test response: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result.containsKey('result')) {
          print('✅ Odoo connection successful');
          return true;
        }
      }
      
      print('❌ Odoo connection failed');
      return false;
    } catch (e) {
      print('❌ Connection error: $e');
      return false;
    }
  }

  // Fetch projects with minimal fields (no special permissions required)
  Future<List<Map<String, dynamic>>> fetchProjectsBasic() async {
    try {
      print('🔍 DEBUG: fetchProjectsBasic() called');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated');
        return [];
      }

      print('🔍 DEBUG: Making basic project request...');

      final response = await http.post(
        Uri.parse('$jsonRpcUrl'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'project.project',
              'search_read',
              [[]], // Get all projects
              {
                'fields': [
                  'id', 
                  'name', 
                  'description', 
                  'user_id', 
                  'date_start',
                  'date',
                  'color',
                  'sequence',
                  'task_count',
                  'doc_count',
                  'is_favorite',
                  'create_date',
                  'write_date',
                  'last_update_status', // Add status field
                ],
                'order': 'sequence, name',
                'limit': 100
              }
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Basic project fetch response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('🔍 DEBUG: Basic project result: $result');
        
        if (result.containsKey('error')) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Basic project fetch error: $errorMessage');
          return [];
        }
        
        if (result['result'] is List) {
          final projects = List<Map<String, dynamic>>.from(result['result']);
          print('🔍 DEBUG: Found ${projects.length} projects with basic fields');
          
          // Process basic project data
          for (var project in projects) {
            print('🔍 DEBUG: Processing basic project: ${project['name']}');
            
            // Convert user_id from [id, name] to readable format
            if (project['user_id'] is List && project['user_id'].length >= 2) {
              project['manager_name'] = project['user_id'][1];
              project['user_id'] = project['user_id'][0];
              
              // Try to get manager email from user data
              try {
                final userResponse = await http.post(
                  Uri.parse('$jsonRpcUrl'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'jsonrpc': '2.0',
                    'method': 'call',
                    'params': {
                      'service': 'object',
                      'method': 'execute_kw',
                      'args': [
                        database,
                        int.parse(userId),
                        password,
                        'res.users',
                        'read',
                        [[project['user_id']]],
                        {'fields': ['email']}
                      ]
                    },
                    'id': 2,
                  }),
                );

                if (userResponse.statusCode == 200) {
                  final userResult = jsonDecode(userResponse.body);
                  if (userResult['result'] != null && userResult['result'].isNotEmpty) {
                    project['manager_email'] = userResult['result'][0]['email'];
                  }
                }
              } catch (e) {
                print('❌ Error fetching manager email: $e');
                project['manager_email'] = null;
              }
            }
            
            // Set default values for missing fields
            project['description'] = project['description'] ?? '';
            project['task_count'] = project['task_count'] ?? 0;
            project['doc_count'] = project['doc_count'] ?? 0;
            project['is_favorite'] = project['is_favorite'] ?? false;
            project['color'] = project['color'] ?? 0;
            project['stage_id'] = null;
            project['stage_name'] = 'Default';
            project['milestone_count'] = 0;
            project['last_update_status'] = project['last_update_status'] ?? 'on_track';
          }
          
          print('✅ Successfully fetched ${projects.length} projects with basic fields');
          return projects;
        }
      }
      
      print('❌ Failed to fetch basic projects');
      return [];
    } catch (e) {
      print('❌ Error fetching basic projects: $e');
      return [];
    }
  }

  // Fetch calendar events from Odoo
  Future<List<Map<String, dynamic>>> fetchCalendarEvents() async {
    try {
      print('🔍 DEBUG: fetchCalendarEvents() called');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated for calendar events');
        return [];
      }

      print('🔍 DEBUG: Fetching calendar events for user: $userId');

      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'calendar.event',
              'search_read',
              [
                [
                  ['user_id', '=', int.parse(userId)]
                ]
              ],
              {
                'fields': [
                  'id',
                  'name',
                  'description',
                  'start',
                  'stop',
                  'location',
                  'videocall_location',
                  'allday',
                  'duration',
                  'privacy',
                  'show_as',
                  'partner_ids',
                  'attendee_ids',
                  'create_date',
                  'write_date'
                ],
                'order': 'start asc',
                'limit': 100
              }
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Calendar events response status: ${response.statusCode}');
      print('🔍 DEBUG: Calendar events response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        if (result.containsKey('error')) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Error fetching calendar events: $errorMessage');
          return [];
        }
        
        if (result['result'] is List) {
          final events = List<Map<String, dynamic>>.from(result['result']);
          print('✅ Successfully fetched ${events.length} calendar events from Odoo');
          return events;
        } else {
          print('⚠️ Unexpected result format: ${result['result']}');
          return [];
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}, Response: ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Error fetching calendar events from Odoo: $e');
      return [];
    }
  }

  // Create a new calendar event in Odoo
  Future<Map<String, dynamic>?> createCalendarEvent({
    required String name,
    required DateTime start,
    required DateTime stop,
    String? description,
    String? location,
    String? videocallLocation,
    bool allday = false,
  }) async {
    try {
      print('🔍 DEBUG: createCalendarEvent() called');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated for creating calendar event');
        return null;
      }

      print('🔍 DEBUG: Creating calendar event: $name');

      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'calendar.event',
              'create',
              [
                {
                  'name': name,
                  'start': allday ? start.toIso8601String().split('T')[0] + ' 08:00:00' : start.toIso8601String(),
                  'stop': allday ? stop.toIso8601String().split('T')[0] + ' 18:00:00' : stop.toIso8601String(),
                  'description': description ?? '',
                  'location': location ?? '',
                  'videocall_location': videocallLocation ?? '',
                  'allday': allday,
                  'user_id': int.parse(userId),
                  'privacy': 'public',
                  'show_as': 'busy',
                }
              ]
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Create calendar event response status: ${response.statusCode}');
      print('🔍 DEBUG: Create calendar event response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        if (result.containsKey('error')) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Error creating calendar event: $errorMessage');
          return null;
        }
        
        if (result['result'] != null) {
          print('✅ Successfully created calendar event with ID: ${result['result']}');
          return {'id': result['result']};
        } else {
          print('⚠️ Unexpected result format: ${result['result']}');
          return null;
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}, Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Error creating calendar event: $e');
      return null;
    }
  }

  // Update an existing calendar event in Odoo
  Future<Map<String, dynamic>?> updateCalendarEvent({
    required int eventId,
    required String name,
    required DateTime start,
    required DateTime stop,
    String? description,
    String? location,
    String? videocallLocation,
    bool allday = false,
  }) async {
    try {
      print('🔍 DEBUG: updateCalendarEvent() called for ID: $eventId');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated for updating calendar event');
        return null;
      }

      print('🔍 DEBUG: Updating calendar event: $name');

      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'calendar.event',
              'write',
              [
                [eventId],
                {
                  'name': name,
                  'start': allday ? start.toIso8601String().split('T')[0] + ' 08:00:00' : start.toIso8601String(),
                  'stop': allday ? stop.toIso8601String().split('T')[0] + ' 18:00:00' : stop.toIso8601String(),
                  'description': description ?? '',
                  'location': location ?? '',
                  'videocall_location': videocallLocation ?? '',
                  'allday': allday,
                }
              ]
            ]
          },
          'id': 1,
        }),
      );

      print('🔍 DEBUG: Update calendar event response status: ${response.statusCode}');
      print('🔍 DEBUG: Update calendar event response body: ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        if (result.containsKey('error')) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Error updating calendar event: $errorMessage');
          return null;
        }
        
        if (result['result'] == true) {
          print('✅ Successfully updated calendar event with ID: $eventId');
          return {'id': eventId};
        } else {
          print('⚠️ Unexpected result format: ${result['result']}');
          return null;
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}, Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Error updating calendar event: $e');
      return null;
    }
  }

  // Delete a calendar event from Odoo
  Future<bool> deleteCalendarEvent(int eventId) async {
    try {
      print('🔍 DEBUG: deleteCalendarEvent() called for ID: $eventId');
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      final password = prefs.getString('user_password');
      
      if (userId == null || password == null) {
        print('❌ User not authenticated for deleting calendar event');
        return false;
      }

      print('🔍 DEBUG: Deleting calendar event with ID: $eventId');

      // Optimized request with shorter timeout
      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {
          'Content-Type': 'application/json',
          'Connection': 'keep-alive',
        },
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              password,
              'calendar.event',
              'unlink',
              [
                [eventId]
              ]
            ]
          },
          'id': 1,
        }),
      ).timeout(
        const Duration(seconds: 8), // Shorter timeout
        onTimeout: () {
          print('❌ Delete request timeout');
          throw Exception('Request timeout');
        },
      );

      print('🔍 DEBUG: Delete calendar event response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        
        if (result.containsKey('error')) {
          final error = result['error'];
          final errorMessage = error['data']?['message'] ?? error['message'] ?? 'Unknown error';
          print('❌ Error deleting calendar event: $errorMessage');
          return false;
        }
        
        if (result['result'] == true) {
          print('✅ Successfully deleted calendar event with ID: $eventId');
          return true;
        } else {
          print('⚠️ Unexpected result format: ${result['result']}');
          return false;
        }
      } else {
        print('❌ HTTP Error: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error deleting calendar event: $e');
      return false;
    }
  }

  Future<List<Project>> fetchProjects() async {
    print("🔍 Fetching projects...");

    if (_userId == null || _password == null) {
      print("❌ User not authenticated. Cannot fetch projects.");
      return [];
    }

    try {
      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "project.project",
              "search_read",
              [],
              {
                "fields": [
                  "id",
                  "name",
                  "description",
                  "partner_id",
                  "partner_email",
                  "partner_phone",
                  "date_start",
                  "date",
                  "task_count",
                  "color",
                  "is_favorite",
                  "user_id",
                  "last_update_status",
                ],
                "order": "name asc",
                "limit": 100,
              },
            ]
          },
          "id": 1
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['error'] != null) {
          final err = data['error'];
          final msg = err['data']?['message'] ?? err['message'] ?? err.toString();
          print("❌ fetchProjects Odoo error: $msg");
          lastErrorMessage = msg.toString();
          return [];
        }
        if (data['result'] != null) {
          final list = data['result'] as List;
          print("✅ Projects fetched successfully: ${list.length} projects");
          lastErrorMessage = null;
          return list
              .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
        print("❌ No projects found in response");
        return [];
      }
      print("❌ Error fetching projects: ${response.statusCode}");
      return [];
    } catch (e) {
      print("❌ Exception fetching projects: $e");
      return [];
    }
  }

  Future<Map<String, dynamic>?> createProject({
    required String name,
    String? description,
    String? partnerName,
    DateTime? dateStart,
    DateTime? dateEnd,
    String? stageName,
  }) async {
    print("🔍 Creating project: $name");
    
    if (_userId == null || _password == null) {
      print("❌ User not authenticated. Cannot create project.");
      return null;
    }

    try {
      Map<String, dynamic> projectData = {
        'name': name,
        'description': description ?? '',
        'active': true,
      };

      if (dateStart != null) {
        projectData['date_start'] = DateFormat('yyyy-MM-dd').format(dateStart);
      }
      if (dateEnd != null) {
        projectData['date'] = DateFormat('yyyy-MM-dd').format(dateEnd);
      }

      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "project.project",
              "create",
              [projectData]
            ]
          },
          "id": 1
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print("⏰ Project creation timed out after 10 seconds");
          throw Exception('Request timeout - please try again');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] != null) {
          print("✅ Project created successfully with ID: ${data['result']}");
          return {
            'id': data['result'],
            'name': name,
            'success': true,
          };
        } else {
          print("❌ Failed to create project: ${data['error']}");
          return null;
        }
      } else {
        print("❌ Error creating project: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      print("❌ Exception creating project: $e");
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> findTasksWithSubtasks(int projectId) async {
    bool isAuthenticated = await checkAndLoadUserCredentials();
    if (!isAuthenticated) {
      throw Exception("User not authenticated");
    }

    print("🔍 DEBUG: Finding tasks with subtasks in project $projectId");
    
    try {
      final response = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "project.task",
              "search_read",
              [
                [
                  ["project_id", "=", projectId],
                  ["child_ids", "!=", false]
                ],
                {
                  "fields": ["id", "name", "child_ids", "parent_id"]
                }
              ]
            ]
          },
          "id": 0
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["result"] != null) {
          final tasks = data["result"] as List<dynamic>;
          print("🔍 DEBUG: Found ${tasks.length} tasks with subtasks in project $projectId");
          return tasks.cast<Map<String, dynamic>>();
        }
      }
    } catch (e) {
      print("⚠️ Error finding tasks with subtasks: $e");
    }
    
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchSubTasks(int parentTaskId) async {
    bool isAuthenticated = await checkAndLoadUserCredentials();
    if (!isAuthenticated) {
      throw Exception("User not authenticated");
    }

    print("🔍 Fetching sub-tasks for parent task ID: $parentTaskId");
    
    try {
      final directResponse = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "project.task",
              "read",
              [
                [parentTaskId]
              ],
              ["id", "name", "child_ids"]
            ]
          },
          "id": 0
        }),
      );

      if (directResponse.statusCode == 200) {
        final directData = jsonDecode(directResponse.body);
        
        if (directData["result"] != null && directData["result"].isNotEmpty) {
          final taskData = directData["result"][0];
          final childIds = taskData["child_ids"];
          
          if (childIds != null && childIds.isNotEmpty) {
            final childTasksResponse = await http.post(
              Uri.parse(jsonRpcUrl),
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                "jsonrpc": "2.0",
                "method": "call",
                "params": {
                  "service": "object",
                  "method": "execute_kw",
                  "args": [
                    database,
                    int.parse(_userId!),
                    _password,
                    "project.task",
                    "read",
                    [childIds],
                    [
                      "id", "name", "description", "user_id", "date_deadline",
                      "stage_id", "priority", "create_date", "write_date",
                      "project_id", "kanban_state", "active", "planned_hours",
                      "effective_hours", "progress", "remaining_hours",
                      "total_hours_spent", "timesheet_ids", "subtask_planned_hours",
                      "subtask_effective_hours"
                    ]
                  ]
                },
                "id": 0
              }),
            );

            if (childTasksResponse.statusCode == 200) {
              final childTasksData = jsonDecode(childTasksResponse.body);
              if (childTasksData["result"] != null) {
                final childTasks = childTasksData["result"] as List<dynamic>;
                
                List<Map<String, dynamic>> transformedTasks = [];
                for (var task in childTasks) {
                  Map<String, dynamic> transformedTask = Map<String, dynamic>.from(task);
                  
                  if (task["stage_id"] != null && task["stage_id"].isNotEmpty) {
                    try {
                      final stageResponse = await http.post(
                        Uri.parse(jsonRpcUrl),
                        headers: {'Content-Type': 'application/json'},
                        body: json.encode({
                          "jsonrpc": "2.0",
                          "method": "call",
                          "params": {
                            "service": "object",
                            "method": "execute_kw",
                            "args": [
                              database,
                              int.parse(_userId!),
                              _password,
                              "project.task.type",
                              "read",
                              [
                                [task["stage_id"][0]]
                              ],
                              ["name"]
                            ]
                          },
                          "id": 8,
                        }),
                      );

                      if (stageResponse.statusCode == 200) {
                        final stageData = json.decode(stageResponse.body);
                        if (stageData["result"] != null && stageData["result"].isNotEmpty) {
                          transformedTask["stage_name"] = stageData["result"][0]["name"];
                        }
                      }
                    } catch (e) {
                      print("⚠️ Error fetching stage details: $e");
                    }
                  }
                  
                  transformedTasks.add(transformedTask);
                }
                
                return transformedTasks;
              }
            }
          }
        }
      }
    } catch (e) {
      print("⚠️ Error fetching subtasks: $e");
    }
    
    return [];
  }

  // ---------------------------------------------------------------------------
  // Preventive maintenance / PM module (Odoo custom models — adjust if needed)
  // ---------------------------------------------------------------------------
  static const String _odooPmModel = 'preventive.maintenance';
  static const String _odooPmRequestModel = 'maintenance.request';
  static const String _odooPmTaskModel = 'preventive.maintenance.task';
  static const String _odooPmTaskModelAlt = 'preventive.maintenance.line';

  static const List<String> _pmFormFields = [
    'id',
    'name',
    'project_id',
    'zone_id',
    'lot_location',
    'lot_serial_number',
    'serial_number_id',
    'lot_product',
    'equipment_type',
    'equipment_user',
    'lot_department',
    'lot_ip_address',
    'lot_user_mail',
    'lot_user_no',
    'rack_no',
    'technician',
    'user_signature',
    'user_signature_date',
    'representative_name',
    'pic_sign',
    'pic_sign_date',
    'pic_name',
    'qr_code_user',
    'qr_code_pic',
    'stage',
    'remarks',
    'pm_name',
  ];

  Future<Map<String, String>> _prefsAuth() async {
    await loadSessionCredentials();
    final prefs = await SharedPreferences.getInstance();
    final uidStr = _userId ?? prefs.getString('user_id');
    final pwd = _password ??
        prefs.getString('user_password') ??
        prefs.getString('password');
    if (uidStr != null && pwd != null && pwd.isNotEmpty) {
      _userId = uidStr;
      _password = pwd;
      return {'uid': uidStr, 'pwd': pwd};
    }
    final email = prefs.getString('user_email') ?? prefs.getString('email');
    if (email != null && pwd != null && pwd.isNotEmpty) {
      final uid = await authenticate(email, pwd);
      if (uid != null) return {'uid': uid, 'pwd': pwd};
    }
    throw Exception('User not authenticated. Please login again.');
  }

  String _friendlyOdooError(dynamic error) {
    String raw = error.toString();
    if (error is Map) {
      final data = error['data'];
      if (data is Map && data['message'] != null) {
        raw = data['message'].toString();
      } else if (error['message'] != null) {
        raw = error['message'].toString();
      }
    }
    if (raw.contains('maintenance.request') &&
        (raw.contains('AccessError') ||
            raw.contains('not allowed to access'))) {
      return 'Your account cannot access Preventive Maintenance. '
          'Ask your Odoo admin to add you to a PM group '
          '(Technician / PM Manager / APMM / MKN / PKNS User).';
    }
    return raw;
  }

  Future<dynamic> _executeKwRaw(List<dynamic> args) async {
    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': {
          'service': 'object',
          'method': 'execute_kw',
          'args': args,
        },
        'id': 1,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['error'] != null) {
      lastErrorMessage = _friendlyOdooError(decoded['error']);
      throw Exception(lastErrorMessage!);
    }
    return decoded['result'];
  }

  Future<Map<String, dynamic>?> _pmMobileApiCall(
    String path,
    Map<String, dynamic> params,
  ) async {
    final cookie = await _sessionCookieHeader();
    if (cookie == null || cookie.isEmpty) return null;

    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': cookie,
      },
      body: jsonEncode({
        'jsonrpc': '2.0',
        'method': 'call',
        'params': params,
        'id': 1,
      }),
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final errorMessage = _extractJsonRpcErrorMessage(decoded);
    if (errorMessage != null) {
      lastErrorMessage = errorMessage;
      throw Exception(errorMessage);
    }

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      if (result['success'] == true) return result;
      if (result['error'] != null) {
        lastErrorMessage = result['error'].toString();
        throw Exception(lastErrorMessage!);
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _pmRowsFromApiResult(Map<String, dynamic>? api) {
    if (api == null) return [];
    final records = api['records'];
    if (records is! List) return [];
    return records
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  int _pmM2oId(dynamic v) {
    if (v is List && v.isNotEmpty) {
      final id = v[0];
      if (id is int) return id;
      return int.tryParse(id?.toString() ?? '') ?? 0;
    }
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  bool _isPmLineDone(dynamic stage) {
    final s = (stage ?? '').toString().toLowerCase();
    return s == 'done' || s == 'complete' || s == 'collected';
  }

  Future<List<Map<String, dynamic>>> _fetchPmKanbanViaRpc({
    required bool includeAll,
    required String status,
  }) async {
    const fields = [
      'id',
      'name',
      'project_id',
      'preventive_maintenance_count_done',
      'preventive_maintenance_count_new',
      'preventive_maintenance_done_percentage',
      'days_left_deadline',
    ];

    final List<dynamic> domain = [];
    if (!includeAll) {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      domain.add(['deadline', '>=', today]);
    }
    if (status == 'active') {
      domain.add(['preventive_maintenance_count_new', '>', 0]);
    } else if (status == 'complete') {
      domain.addAll([
        '|',
        ['preventive_maintenance_done_percentage', '>=', 100],
        '&',
        ['preventive_maintenance_count_new', '=', 0],
        ['preventive_maintenance_count_done', '>', 0],
      ]);
    }

    var rows = await _searchRead(
      _odooPmRequestModel,
      domain,
      {
        'fields': fields,
        'limit': includeAll ? 2500 : 600,
        'order': 'deadline asc,id desc',
      },
    );

    if (rows.isEmpty && !includeAll && status == 'all') {
      rows = await _searchRead(
        _odooPmRequestModel,
        [],
        {
          'fields': fields,
          'limit': 200,
          'order': 'deadline desc,id desc',
        },
      );
      for (final m in rows) {
        m['_fallback_all'] = true;
      }
    }
    return rows;
  }

  /// Build PM UI cards from `preventive.maintenance` lines (Odoo Masterlist)
  /// when no `maintenance.request` kanban records exist yet.
  Future<List<Map<String, dynamic>>> _synthesizePmKanbanFromPreventiveLines({
    required String status,
  }) async {
    const lineFields = ['id', 'name', 'project_id', 'pm_name', 'stage'];
    List<Map<String, dynamic>> lines;
    try {
      lines = await _searchRead(
        _odooPmModel,
        [],
        {
          'fields': lineFields,
          'limit': 4000,
          'order': 'project_id, id desc',
        },
      );
    } catch (e) {
      debugPrint('⚠️ Cannot read preventive.maintenance: $e');
      return [];
    }

    if (lines.isEmpty) return [];

    final Map<int, Map<String, dynamic>> byProject = {};
    for (final line in lines) {
      final projectId = _pmM2oId(line['project_id']);
      if (projectId <= 0) continue;

      final card = byProject.putIfAbsent(projectId, () {
        return {
          'id': 0,
          'name': 'Preventive Maintenance',
          'project_id': line['project_id'],
          'preventive_maintenance_count_done': 0,
          'preventive_maintenance_count_new': 0,
          'preventive_maintenance_done_percentage': 0.0,
          'days_left_deadline': 30,
          '_synthetic_from_pm': true,
        };
      });

      if (_isPmLineDone(line['stage'])) {
        card['preventive_maintenance_count_done'] =
            (card['preventive_maintenance_count_done'] as int) + 1;
      } else {
        card['preventive_maintenance_count_new'] =
            (card['preventive_maintenance_count_new'] as int) + 1;
      }

      final reqId = _pmM2oId(line['pm_name']);
      if (reqId > 0 && (card['id'] as int) == 0) {
        card['id'] = reqId;
      }
    }

    for (final card in byProject.values) {
      final done = card['preventive_maintenance_count_done'] as int;
      final todo = card['preventive_maintenance_count_new'] as int;
      final total = done + todo;
      card['preventive_maintenance_done_percentage'] =
          total > 0 ? (done / total * 100.0) : 0.0;
    }

    debugPrint(
      '✅ PM UI: built ${byProject.length} project card(s) from preventive.maintenance',
    );
    return byProject.values.toList();
  }

  List<Map<String, dynamic>> _filterPmKanbanRows(
    List<Map<String, dynamic>> rows,
    String status,
  ) {
    int doneCount(Map<String, dynamic> r) {
      final v = r['preventive_maintenance_count_done'];
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    int newCount(Map<String, dynamic> r) {
      final v = r['preventive_maintenance_count_new'];
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    if (status == 'active') {
      return rows.where((r) => newCount(r) > 0).toList();
    }
    if (status == 'complete') {
      return rows
          .where((r) => newCount(r) == 0 && doneCount(r) > 0)
          .toList();
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _searchRead(
    String model,
    List<dynamic> domain,
    Map<String, dynamic> kwargs,
  ) async {
    final auth = await _prefsAuth();
    final result = await _executeKwRaw([
      database,
      int.parse(auth['uid']!),
      auth['pwd']!,
      model,
      'search_read',
      [domain],
      kwargs,
    ]);
    if (result is! List) return [];
    return List<Map<String, dynamic>>.from(
      result.map((e) => Map<String, dynamic>.from(e as Map)),
    );
  }

  Future<void> _writeModel(
    String model,
    List<int> ids,
    Map<String, dynamic> values,
  ) async {
    final auth = await _prefsAuth();
    await _executeKwRaw([
      database,
      int.parse(auth['uid']!),
      auth['pwd']!,
      model,
      'write',
      [
        ids,
        values,
      ],
    ]);
  }

  Future<int> _createModel(String model, Map<String, dynamic> values) async {
    final auth = await _prefsAuth();
    final result = await _executeKwRaw([
      database,
      int.parse(auth['uid']!),
      auth['pwd']!,
      model,
      'create',
      [values],
    ]);
    if (result is int) return result;
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  Future<void> _unlinkModel(String model, List<int> ids) async {
    final auth = await _prefsAuth();
    await _executeKwRaw([
      database,
      int.parse(auth['uid']!),
      auth['pwd']!,
      model,
      'unlink',
      [ids],
    ]);
  }

  Future<String?> _sessionCookieHeader() async {
    final prefs = await SharedPreferences.getInstance();
    String? cookie = prefs.getString('session_id');
    final sessId = prefs.getString('sessionId') ?? '';
    if ((cookie == null || cookie.isEmpty) && sessId.isNotEmpty) {
      cookie = 'session_id=$sessId';
    }
    return cookie;
  }

  Future<List<Map<String, dynamic>>> fetchPmKanbanRequests({
    required bool includeAll,
    required String status,
  }) async {
    try {
      await checkAndLoadUserCredentials();

      List<Map<String, dynamic>> rows = [];

      try {
        final api = await _pmMobileApiCall(
          '/api/pm/kanban_requests',
          {
            'include_all': includeAll,
            'status': status,
          },
        );
        if (api != null && api['success'] == true) {
          rows = _pmRowsFromApiResult(api);
          debugPrint('🔹 PM kanban API returned ${rows.length} row(s)');
        }
      } catch (e) {
        debugPrint('⚠️ PM kanban API: $e');
      }

      if (rows.isEmpty) {
        rows = await _fetchPmKanbanViaRpc(
          includeAll: includeAll,
          status: status,
        );
        debugPrint('🔹 PM kanban RPC returned ${rows.length} row(s)');
      }

      if (rows.isEmpty) {
        rows = await _synthesizePmKanbanFromPreventiveLines(status: status);
      }

      return _filterPmKanbanRows(rows, status);
    } catch (e) {
      debugPrint('❌ fetchPmKanbanRequests: $e');
      lastErrorMessage ??= e.toString();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fetchPreventiveMaintenanceByProject({
    required int projectId,
    required String stage,
  }) async {
    await checkAndLoadUserCredentials();
    final all = await _searchRead(
      _odooPmModel,
      [
        ['project_id', '=', projectId],
      ],
      {
        'fields': _pmFormFields,
        'limit': 2000,
        'order': 'lot_location, id',
      },
    );
    final wantDone = stage == 'done';
    return all
        .where((r) => wantDone ? _isPmLineDone(r['stage']) : !_isPmLineDone(r['stage']))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchPreventiveMaintenanceDashboardRows() async {
    try {
      await checkAndLoadUserCredentials();

      try {
        final api = await _pmMobileApiCall('/api/pm/dashboard_rows', {});
        final rows = _pmRowsFromApiResult(api);
        if (rows.isNotEmpty || api != null) return rows;
      } catch (e) {
        debugPrint('⚠️ PM dashboard API: $e');
      }

      return await _searchRead(
        _odooPmModel,
        [],
        {
          'fields': [
            'stage',
            'technician',
            'create_date',
            'write_date',
            'user_signature_date',
          ],
          'limit': 4000,
        },
      );
    } catch (e) {
      debugPrint('❌ fetchPreventiveMaintenanceDashboardRows: $e');
      lastErrorMessage ??= e.toString();
      rethrow;
    }
  }

  Future<Map<int, Map<String, dynamic>>> fetchUsersByIds(List<int> ids) async {
    final uniq = ids.toSet().toList();
    if (uniq.isEmpty) return {};
    final rows = await _searchRead(
      'res.users',
      [
        ['id', 'in', uniq],
      ],
      {
        'fields': ['id', 'name', 'image_128'],
        'limit': uniq.length,
      },
    );
    final out = <int, Map<String, dynamic>>{};
    for (final r in rows) {
      final id = r['id'];
      if (id is int) out[id] = r;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> fetchCollectionDashboardCards() async {
    const fields = [
      'id',
      'name',
      'project_id',
      'cf_name',
      'project_collection_count_done',
      'project_collection_count_new',
      'project_collection_done_percentage',
    ];
    try {
      await checkAndLoadUserCredentials();

      try {
        final api = await _pmMobileApiCall('/api/pm/collection_cards', {});
        final rows = _pmRowsFromApiResult(api);
        if (rows.isNotEmpty || api != null) return rows;
      } catch (e) {
        debugPrint('⚠️ Collection dashboard API: $e');
      }

      return await _searchRead(
        _odooPmRequestModel,
        [],
        {'fields': fields, 'limit': 800, 'order': 'name'},
      );
    } catch (e) {
      print('⚠️ fetchCollectionDashboardCards: $e');
      lastErrorMessage ??= e.toString();
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchUatDashboardProjects() async {
    const fields = [
      'id',
      'name',
      'done_count',
      'todo_count',
      'progress_percentage',
    ];
    try {
      return await _searchRead(
        _odooPmRequestModel,
        [],
        {'fields': fields, 'limit': 800, 'order': 'name'},
      );
    } catch (e) {
      print('⚠️ fetchUatDashboardProjects: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchPreventiveMaintenanceByRequest({
    required int requestId,
    required String stage,
  }) async {
    final domains = <List<dynamic>>[
      [
        ['pm_name', '=', requestId],
        ['stage', '=', stage],
      ],
      [
        ['request_id', '=', requestId],
        ['stage', '=', stage],
      ],
      [
        ['maintenance_request_id', '=', requestId],
        ['stage', '=', stage],
      ],
    ];
    for (final d in domains) {
      try {
        return await _searchRead(
          _odooPmModel,
          d,
          {
            'fields': _pmFormFields,
            'limit': 2000,
            'order': 'lot_location, id',
          },
        );
      } catch (_) {}
    }
    throw Exception(
      'Could not load PM lines for request $requestId (check Odoo domain fields).',
    );
  }

  Future<Map<String, dynamic>?> fetchPreventiveMaintenanceDetail(int pmId) async {
    final rows = await _searchRead(
      _odooPmModel,
      [
        ['id', '=', pmId],
      ],
      {'fields': _pmFormFields, 'limit': 1},
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> fetchMaintenanceTasksByPmId(int pmId) async {
    const taskFields = [
      'id',
      'name',
      'equipment_task',
      'note',
      'remarks',
      'category_id',
      'category',
      'equipment',
      'check',
      'is_yes',
      'is_no',
    ];
    for (final model in [_odooPmTaskModel, _odooPmTaskModelAlt]) {
      for (final fk in [
        'maintenance_id',
        'pm_id',
        'preventive_maintenance_id',
      ]) {
        try {
          final rows = await _searchRead(
            model,
            [
              [fk, '=', pmId],
            ],
            {'fields': taskFields, 'limit': 2000, 'order': 'id'},
          );
          return rows;
        } catch (_) {}
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchTechnicians() async {
    return _searchRead(
      'res.users',
      [
        ['active', '=', true],
        ['share', '=', false],
      ],
      {'fields': ['id', 'name', 'login'], 'limit': 500, 'order': 'name'},
    );
  }

  Future<void> updatePreventiveMaintenanceTechnician({
    required int pmId,
    required int technicianId,
  }) async {
    await _writeModel(_odooPmModel, [pmId], {'technician': technicianId});
  }

  Future<bool> updatePreventiveMaintenanceSignatures({
    required int pmId,
    Uint8List? userSignatureBytes,
    Uint8List? picSignatureBytes,
    String? representativeName,
    String? userSignatureDate,
    String? picName,
    String? picSignatureDate,
    bool markDone = false,
  }) async {
    final vals = <String, dynamic>{};
    if (userSignatureBytes != null) {
      vals['user_signature'] = base64Encode(userSignatureBytes);
    }
    if (picSignatureBytes != null) {
      vals['pic_sign'] = base64Encode(picSignatureBytes);
    }
    if (representativeName != null) {
      vals['representative_name'] = representativeName;
    }
    if (userSignatureDate != null) {
      vals['user_signature_date'] = userSignatureDate;
    }
    if (picName != null) vals['pic_name'] = picName;
    if (picSignatureDate != null) {
      vals['pic_sign_date'] = picSignatureDate;
    }
    if (markDone) vals['stage'] = 'done';
    await _writeModel(_odooPmModel, [pmId], vals);
    return markDone;
  }

  Future<void> clearPreventiveMaintenanceSignatures({
    required int pmId,
    bool clearUser = false,
    bool clearPic = false,
  }) async {
    final vals = <String, dynamic>{};
    if (clearUser) {
      vals['user_signature'] = false;
      vals['user_signature_date'] = false;
      vals['representative_name'] = false;
    }
    if (clearPic) {
      vals['pic_sign'] = false;
      vals['pic_sign_date'] = false;
      vals['pic_name'] = false;
    }
    if (vals.isEmpty) return;
    await _writeModel(_odooPmModel, [pmId], vals);
  }

  Future<Uint8List> fetchPreventiveMaintenanceReportPdf({
    required int pmId,
    required String reportName,
  }) async {
    final cookie = await _sessionCookieHeader();
    final path = '/report/pdf/${Uri.encodeComponent(reportName)}/$pmId';
    final resp = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie},
    );
    if (resp.statusCode != 200) {
      throw Exception('Report HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<Uint8List> fetchPreventiveMaintenanceReportPdfForIds({
    required List<int> pmIds,
    required String reportName,
  }) async {
    if (pmIds.isEmpty) return Uint8List(0);
    final cookie = await _sessionCookieHeader();
    final joined = pmIds.join(',');
    final path =
        '/report/pdf/${Uri.encodeComponent(reportName)}/$joined';
    final resp = await http.get(
      Uri.parse('$baseUrl$path'),
      headers: {if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie},
    );
    if (resp.statusCode != 200) {
      throw Exception('Report HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  Future<void> updateMaintenanceTaskStatus({
    required int taskId,
    bool? check,
    bool? isYes,
    bool? isNo,
  }) async {
    final vals = <String, dynamic>{};
    if (check != null) vals['check'] = check;
    if (isYes != null) vals['is_yes'] = isYes;
    if (isNo != null) vals['is_no'] = isNo;
    if (vals.isEmpty) return;
    for (final model in [_odooPmTaskModel, _odooPmTaskModelAlt]) {
      try {
        await _writeModel(model, [taskId], vals);
        return;
      } catch (_) {}
    }
    throw Exception('Could not update task $taskId');
  }

  Future<void> updateMaintenanceTasksBulk({
    required List<int> taskIds,
    required Map<String, dynamic> values,
  }) async {
    if (taskIds.isEmpty || values.isEmpty) return;
    for (final model in [_odooPmTaskModel, _odooPmTaskModelAlt]) {
      try {
        await _writeModel(model, taskIds, values);
        return;
      } catch (_) {}
    }
    throw Exception('Could not bulk-update tasks');
  }

  Future<bool> uploadPmAttachment({
    required int pmId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    try {
      await _createModel('ir.attachment', {
        'name': fileName,
        'type': 'binary',
        'datas': base64Encode(bytes),
        'mimetype': mimeType ?? 'application/octet-stream',
        'res_model': _odooPmModel,
        'res_id': pmId,
      });
      return true;
    } catch (e) {
      print('❌ uploadPmAttachment: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getPmAttachments(int pmId) async {
    return _searchRead(
      'ir.attachment',
      [
        ['res_model', '=', _odooPmModel],
        ['res_id', '=', pmId],
      ],
      {
        'fields': ['id', 'name', 'mimetype', 'url', 'type'],
        'limit': 200,
        'order': 'id desc',
      },
    );
  }

  Future<bool> deletePmAttachment(int attachmentId) async {
    try {
      await _unlinkModel('ir.attachment', [attachmentId]);
      return true;
    } catch (e) {
      print('❌ deletePmAttachment: $e');
      return false;
    }
  }

  Future<void> updatePreventiveMaintenanceRemarks({
    required int pmId,
    required String remarks,
  }) async {
    await _writeModel(_odooPmModel, [pmId], {'remarks': remarks});
  }

  Future<void> updatePreventiveMaintenanceFields({
    required int pmId,
    required Map<String, dynamic> fields,
  }) async {
    if (fields.isEmpty) return;
    await _writeModel(_odooPmModel, [pmId], fields);
  }

  /// Collection drill-down: tries a few common collection stage field names.
  Future<List<Map<String, dynamic>>> fetchCollectionPmRows({
    required int projectId,
    required String stage,
  }) async {
    final stageVariants = <String>{
      stage,
      if (stage == 'collected') ...['done', 'collected', 'complete'],
      if (stage == 'new') ...['new', 'draft', 'todo'],
    }.toList();
    for (final field in [
      'collection_stage',
      'collection_status',
      'cf_stage',
    ]) {
      for (final st in stageVariants) {
        try {
          return await _searchRead(
            _odooPmModel,
            [
              ['project_id', '=', projectId],
              [field, '=', st],
            ],
            {
              'fields': _pmFormFields,
              'limit': 2000,
              'order': 'lot_location, id',
            },
          );
        } catch (_) {}
      }
    }
    try {
      return await _searchRead(
        _odooPmModel,
        [
          ['project_id', '=', projectId],
        ],
        {
          'fields': _pmFormFields,
          'limit': 2000,
          'order': 'id desc',
        },
      );
    } catch (e) {
      print('⚠️ fetchCollectionPmRows: $e');
      return [];
    }
  }


  static const Map<String, String> _expenseRpcHeaders = {
    'Content-Type': 'application/json',
  };

  Future<void> _ensureWebSession({bool force = false}) async {
    await checkAndLoadUserCredentials();
  }

  Future<Map<String, String>> _odooHeaders() async => _expenseRpcHeaders;

  /// Sum of hr.expense total_amount for current user's employee where state = draft — "To Report" (not yet submitted).
  Future<double> getExpenseToReportTotal() async {
    return _getExpenseTotalForStates(["draft"]);
  }

  /// Sum of hr.expense total_amount where state = reported — "Under Validation" (submitted, awaiting approval).
  Future<double> getExpenseUnderValidationTotal() async {
    return _getExpenseTotalForStates(["reported"]);
  }

  /// Sum of hr.expense total_amount where state = approved — "To be reimbursed".
  Future<double> getExpenseToBeReimbursedTotal() async {
    return _getExpenseTotalForStates(["approved"]);
  }

  Future<double> _getExpenseTotalForStates(List<String> states) async {
    final ok = await checkAndLoadUserCredentials();
    if (!ok || _userId == null) return 0;
    try {
      final empResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "hr.employee",
              "search_read",
              [
                [
                  ["user_id", "=", int.parse(_userId!)]
                ]
              ],
              {
                "fields": ["id"],
                "limit": 1
              }
            ]
          },
          "id": 1
        }),
      );
      if (empResp.statusCode != 200) return 0;
      final empData = json.decode(empResp.body);
      if (empData["result"] == null || (empData["result"] as List).isEmpty)
        return 0;
      final employeeId = (empData["result"] as List).first["id"] as int;
      final expResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              int.parse(_userId!),
              _password,
              "hr.expense",
              "search_read",
              [
                [
                  ["employee_id", "=", employeeId],
                  ["state", "in", states]
                ]
              ],
              {
                "fields": ["total_amount"]
              }
            ]
          },
          "id": 2
        }),
      );
      if (expResp.statusCode != 200) return 0;
      final expData = json.decode(expResp.body);
      if (expData["result"] == null || expData["result"] is! List) return 0;
      double sum = 0;
      for (final e in expData["result"] as List) {
        if (e is Map && e["total_amount"] != null)
          sum += (e["total_amount"] is num)
              ? (e["total_amount"] as num).toDouble()
              : 0;
      }
      return sum;
    } catch (e) {
      debugPrint('_getExpenseTotalForStates($states): $e');
      return 0;
    }
  }

  /// Fetch current user's expenses for list/cards: to report, under validation, to reimburse.
  /// Returns list of maps: id, name (description), total_amount, date, state, employee_name, employee_image (base64), attachment_count.
  Future<List<Map<String, dynamic>>> fetchMyExpenses() async {
    final list = <Map<String, dynamic>>[];
    final ok = await checkAndLoadUserCredentials();
    if (!ok || _userId == null) return list;
    try {
      final uid = int.parse(_userId!);
      // 1) Get current user's employee_id
      final empResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              uid,
              _password,
              "hr.employee",
              "search_read",
              [
                [
                  ["user_id", "=", uid]
                ]
              ],
              {
                "fields": ["id"],
                "limit": 1
              }
            ]
          },
          "id": 1
        }),
      );
      if (empResp.statusCode != 200) return list;
      final empData = json.decode(empResp.body);
      if (empData["result"] == null || (empData["result"] as List).isEmpty)
        return list;
      final employeeId = (empData["result"] as List).first["id"] as int;
      // 2) Fetch hr.expense for this employee (all states: draft, reported, approved, refuse, done)
      final expResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "jsonrpc": "2.0",
          "method": "call",
          "params": {
            "service": "object",
            "method": "execute_kw",
            "args": [
              database,
              uid,
              _password,
              "hr.expense",
              "search_read",
              [
                [
                  ["employee_id", "=", employeeId]
                ]
              ],
              {
                "fields": [
                  "id",
                  "name",
                  "employee_id",
                  "total_amount",
                  "date",
                  "state",
                  "sheet_id"
                ],
                "order": "date desc, id desc"
              }
            ]
          },
          "id": 2
        }),
      );
      if (expResp.statusCode != 200) return list;
      final expData = json.decode(expResp.body);
      final expenses =
          expData["result"] is List ? expData["result"] as List : <dynamic>[];
      if (expenses.isEmpty) return list;
      final empIds = <int>{};
      for (final e in expenses) {
        if (e is! Map) continue;
        final emp = e["employee_id"];
        if (emp is int)
          empIds.add(emp);
        else if (emp is List && emp.isNotEmpty && emp[0] != null)
          empIds.add(emp[0] is int
              ? emp[0] as int
              : int.tryParse(emp[0].toString()) ?? 0);
      }
      // 3) Get employee name and image
      final Map<int, Map<String, dynamic>> empMap = {};
      if (empIds.isNotEmpty) {
        final empReadResp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
              "service": "object",
              "method": "execute_kw",
              "args": [
                database,
                uid,
                _password,
                "hr.employee",
                "search_read",
                [
                  [
                    ["id", "in", empIds.toList()]
                  ]
                ],
                {
                  "fields": ["id", "name", "image_128"]
                }
              ]
            },
            "id": 3
          }),
        );
        if (empReadResp.statusCode == 200) {
          final empReadData = json.decode(empReadResp.body);
          final empList = empReadData["result"] is List
              ? empReadData["result"] as List
              : <dynamic>[];
          for (final m in empList) {
            if (m is Map) {
              final id = m["id"] is int
                  ? m["id"] as int
                  : int.tryParse(m["id"]?.toString() ?? '0') ?? 0;
              empMap[id] = {
                "name": m["name"]?.toString() ?? '',
                "image_128": m["image_128"]
              };
            }
          }
        }
      }
      // 4) Attachment count per expense (ir.attachment res_model=hr.expense, res_id=expense_id)
      final Map<int, int> attachmentCountMap = {};
      try {
        final attResp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            "jsonrpc": "2.0",
            "method": "call",
            "params": {
              "service": "object",
              "method": "execute_kw",
              "args": [
                database,
                uid,
                _password,
                "ir.attachment",
                "search_read",
                [
                  [
                    ["res_model", "=", "hr.expense"],
                    [
                      "res_id",
                      "in",
                      expenses
                          .map<int>((e) => e is Map && e["id"] != null
                              ? (e["id"] is int
                                  ? e["id"] as int
                                  : int.tryParse(e["id"].toString()) ?? 0)
                              : 0)
                          .where((v) => v > 0)
                          .toList()
                    ]
                  ]
                ],
                {
                  "fields": ["res_id"]
                }
              ]
            },
            "id": 4
          }),
        );
        if (attResp.statusCode == 200) {
          final attData = json.decode(attResp.body);
          final attList = attData["result"] is List
              ? attData["result"] as List
              : <dynamic>[];
          for (final a in attList) {
            if (a is Map && a["res_id"] != null) {
              final rid = a["res_id"] is int
                  ? a["res_id"] as int
                  : int.tryParse(a["res_id"]?.toString() ?? '0') ?? 0;
              attachmentCountMap[rid] = (attachmentCountMap[rid] ?? 0) + 1;
            }
          }
        }
      } catch (_) {}
      // 5) Build result list
      for (final e in expenses) {
        if (e is! Map) continue;
        final eid = e["id"] is int
            ? e["id"] as int
            : int.tryParse(e["id"]?.toString() ?? '0') ?? 0;
        int? empId;
        final empRaw = e["employee_id"];
        if (empRaw is int) {
          empId = empRaw;
        } else if (empRaw is List && empRaw.isNotEmpty && empRaw[0] != null) {
          empId = empRaw[0] is int
              ? empRaw[0] as int
              : int.tryParse(empRaw[0].toString());
        }
        final empInfo = empId != null ? empMap[empId] : null;
        String empName = empInfo?["name"] ?? '';
        if (empName.isEmpty &&
            empRaw is List &&
            empRaw.length > 1 &&
            empRaw[1] != null) {
          empName = empRaw[1].toString();
        }
        if (empName.isEmpty) empName = '—';
        list.add({
          "id": eid,
          "name": e["name"]?.toString() ?? '—',
          "total_amount": e["total_amount"] is num
              ? (e["total_amount"] as num).toDouble()
              : 0.0,
          "date": e["date"]?.toString(),
          "state": e["state"]?.toString() ?? 'draft',
          "sheet_id": e["sheet_id"],
          "employee_name": empName,
          "employee_image": empInfo?["image_128"],
          "attachment_count": attachmentCountMap[eid] ?? 0,
        });
      }
      return list;
    } catch (e) {
      debugPrint('fetchMyExpenses: $e');
      return list;
    }
  }

  /// Fetch expense reports (`hr.expense.sheet`) for current user with linked expense lines.
  Future<List<Map<String, dynamic>>> fetchMyExpenseReports() async {
    final reports = <Map<String, dynamic>>[];
    final ok = await checkAndLoadUserCredentials();
    if (!ok || _userId == null) return reports;
    try {
      final uid = int.parse(_userId!);
      final empResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.employee',
              'search_read',
              [
                [
                  ['user_id', '=', uid]
                ]
              ],
              {
                'fields': ['id'],
                'limit': 1
              }
            ]
          },
          'id': 1
        }),
      );
      if (empResp.statusCode != 200) return reports;
      final empData = json.decode(empResp.body);
      if (empData['error'] != null ||
          empData['result'] is! List ||
          (empData['result'] as List).isEmpty) {
        return reports;
      }
      final employeeId = (empData['result'] as List).first['id'] as int;

      final sheetResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.expense.sheet',
              'search_read',
              [
                [
                  ['employee_id', '=', employeeId]
                ]
              ],
              {
                'fields': [
                  'id',
                  'name',
                  'state',
                  'total_amount',
                  'accounting_date',
                  'expense_line_ids'
                ],
                'order': 'id desc'
              }
            ]
          },
          'id': 2
        }),
      );
      if (sheetResp.statusCode != 200) return reports;
      final sheetData = json.decode(sheetResp.body);
      if (sheetData['error'] != null || sheetData['result'] is! List)
        return reports;
      final sheetList = sheetData['result'] as List;
      if (sheetList.isEmpty) return reports;

      final expenseIds = <int>{};
      for (final sheet in sheetList) {
        if (sheet is! Map) continue;
        final raw = sheet['expense_line_ids'];
        if (raw is List) {
          for (final id in raw) {
            final parsed = id is int ? id : int.tryParse(id.toString());
            if (parsed != null && parsed > 0) expenseIds.add(parsed);
          }
        }
      }

      final Map<int, Map<String, dynamic>> expenseMap = {};
      if (expenseIds.isNotEmpty) {
        final expResp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'hr.expense',
                'search_read',
                [
                  [
                    ['id', 'in', expenseIds.toList()]
                  ]
                ],
                {
                  'fields': ['id', 'name', 'total_amount', 'date', 'state']
                }
              ]
            },
            'id': 3
          }),
        );
        if (expResp.statusCode == 200) {
          final expData = json.decode(expResp.body);
          final expList = expData['result'] is List
              ? expData['result'] as List
              : <dynamic>[];
          for (final item in expList) {
            if (item is! Map || item['id'] == null) continue;
            final id = item['id'] is int
                ? item['id'] as int
                : int.tryParse(item['id'].toString()) ?? 0;
            if (id <= 0) continue;
            expenseMap[id] = {
              'id': id,
              'name': item['name']?.toString() ?? '—',
              'total_amount': item['total_amount'] is num
                  ? (item['total_amount'] as num).toDouble()
                  : 0.0,
              'date': item['date']?.toString(),
              'state': item['state']?.toString() ?? '',
            };
          }
        }
      }

      for (final sheet in sheetList) {
        if (sheet is! Map) continue;
        final lineIdsRaw = sheet['expense_line_ids'];
        final lines = <Map<String, dynamic>>[];
        if (lineIdsRaw is List) {
          for (final rawId in lineIdsRaw) {
            final lineId =
                rawId is int ? rawId : int.tryParse(rawId.toString());
            if (lineId != null && lineId > 0 && expenseMap[lineId] != null) {
              lines.add(expenseMap[lineId]!);
            }
          }
        }
        reports.add({
          'id': sheet['id'],
          'name': sheet['name']?.toString() ?? 'Report',
          'state': sheet['state']?.toString() ?? '',
          'total_amount': sheet['total_amount'] is num
              ? (sheet['total_amount'] as num).toDouble()
              : 0.0,
          'date': sheet['accounting_date']?.toString(),
          'lines': lines,
        });
      }
      return reports;
    } catch (e) {
      debugPrint('fetchMyExpenseReports: $e');
      return reports;
    }
  }

  Future<OdooActionResult> createExpenseReportFromExpenses(
    List<int> expenseIds, {
    String? reportTitle,
  }) async {
    if (!await checkAndLoadUserCredentials() || _userId == null) {
      return OdooActionResult(id: null, error: 'Not signed in');
    }
    final cleanIds = expenseIds.where((id) => id > 0).toSet().toList();
    if (cleanIds.isEmpty) {
      return OdooActionResult(id: null, error: 'No expenses selected');
    }
    try {
      final uid = int.parse(_userId!);

      final empResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.employee',
              'search_read',
              [
                [
                  ['user_id', '=', uid]
                ]
              ],
              {
                'fields': ['id'],
                'limit': 1
              }
            ]
          },
          'id': 1
        }),
      );
      if (empResp.statusCode != 200) {
        return OdooActionResult(id: null, error: 'Could not load employee');
      }
      final empData = json.decode(empResp.body);
      if (empData['error'] != null ||
          empData['result'] is! List ||
          (empData['result'] as List).isEmpty) {
        return OdooActionResult(
          id: null,
          error: _odooRpcErrorMessage(empData['error']) ??
              'No employee linked to your user',
        );
      }
      final employeeId = (empData['result'] as List).first['id'] as int;
      final customTitle = reportTitle?.trim();
      final reportName = customTitle != null && customTitle.isNotEmpty
          ? customTitle
          : 'Expense Report ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}';

      final createAttempts = <Map<String, dynamic>>[
        {
          'name': reportName,
          'employee_id': employeeId,
          'expense_line_ids': [
            [6, 0, cleanIds]
          ],
        },
        {
          'name': reportName,
          'employee_id': employeeId,
          'expense_line_ids': cleanIds.map((id) => [4, id]).toList(),
        },
        {
          'name': reportName,
          'employee_id': employeeId,
        },
      ];

      int? createdReportId;
      String? createErr;
      for (var i = 0; i < createAttempts.length; i++) {
        final vals = createAttempts[i];
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'hr.expense.sheet',
                'create',
                [vals],
              ],
            },
            'id': 10 + i,
          }),
        );
        if (resp.statusCode != 200) {
          createErr = 'HTTP ${resp.statusCode}';
          continue;
        }
        final data = json.decode(resp.body);
        if (data['error'] != null) {
          createErr =
              _odooRpcErrorMessage(data['error']) ?? 'Create report failed';
          continue;
        }
        createdReportId = _parseOdooCreateId(data['result']);
        if (createdReportId != null && createdReportId > 0) break;
      }

      if (createdReportId == null || createdReportId <= 0) {
        return OdooActionResult(id: null, error: createErr ?? 'Could not create report');
      }

      final linkAttempts = <Map<String, dynamic>>[
        {'sheet_id': createdReportId},
        {'expense_sheet_id': createdReportId},
      ];
      bool linked = false;
      for (var i = 0; i < linkAttempts.length; i++) {
        final vals = linkAttempts[i];
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'hr.expense',
                'write',
                [
                  cleanIds,
                  vals,
                ],
              ],
            },
            'id': 30 + i,
          }),
        );
        if (resp.statusCode != 200) continue;
        final data = json.decode(resp.body);
        if (data['error'] == null && data['result'] == true) {
          linked = true;
          break;
        }
      }

      if (!linked) {
        final verifyReports = await fetchMyExpenseReports();
        final created = verifyReports.any((r) {
          final id = r['id'] is int
              ? r['id'] as int
              : int.tryParse(r['id']?.toString() ?? '0') ?? 0;
          final lines = r['lines'] is List
              ? List<Map<String, dynamic>>.from(r['lines'] as List)
              : <Map<String, dynamic>>[];
          return id == createdReportId &&
              lines.any((line) {
                final eid = line['id'] is int
                    ? line['id'] as int
                    : int.tryParse(line['id']?.toString() ?? '0') ?? 0;
                return cleanIds.contains(eid);
              });
        });
        if (!created) {
          return OdooActionResult(id: null, error: 'Report created but selected expenses could not be linked');
        }
      }

      return OdooActionResult(id: createdReportId, error: null);
    } catch (e, st) {
      debugPrint('createExpenseReportFromExpenses: $e\n$st');
      return OdooActionResult(id: null, error: e.toString());
    }
  }

  Future<String?> renameExpenseReport({
    required int reportId,
    required String newName,
  }) async {
    if (!await checkAndLoadUserCredentials() || _userId == null)
      return 'Not signed in';
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return 'Report name is required';
    try {
      final uid = int.parse(_userId!);
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.expense.sheet',
              'write',
              [
                [reportId],
                {'name': trimmed},
              ],
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200)
        return 'Update failed (HTTP ${resp.statusCode})';
      final data = json.decode(resp.body);
      if (data['error'] != null) {
        return _odooRpcErrorMessage(data['error']) ?? 'Update failed';
      }
      return null;
    } catch (e) {
      debugPrint('renameExpenseReport: $e');
      return e.toString();
    }
  }

  Future<String?> deleteExpenseReport(int reportId) async {
    if (!await checkAndLoadUserCredentials() || _userId == null)
      return 'Not signed in';
    try {
      final uid = int.parse(_userId!);
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.expense.sheet',
              'unlink',
              [
                [reportId],
              ],
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200)
        return 'Delete failed (HTTP ${resp.statusCode})';
      final data = json.decode(resp.body);
      if (data['error'] != null) {
        return _odooRpcErrorMessage(data['error']) ?? 'Delete failed';
      }
      return null;
    } catch (e) {
      debugPrint('deleteExpenseReport: $e');
      return e.toString();
    }
  }

  Future<String?> submitExpenseReportToManager(int reportId) async {
    if (!await checkAndLoadUserCredentials() || _userId == null)
      return 'Not signed in';
    if (reportId <= 0) return 'Invalid report';
    try {
      final uid = int.parse(_userId!);
      final methodAttempts = <String>[
        'action_submit_sheet',
        'action_submit_expenses',
        'action_submit',
      ];

      String? lastErr;
      for (var i = 0; i < methodAttempts.length; i++) {
        final methodName = methodAttempts[i];
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'hr.expense.sheet',
                methodName,
                [
                  [reportId],
                ],
              ],
            },
            'id': i + 1,
          }),
        );
        if (resp.statusCode != 200) {
          lastErr = 'HTTP ${resp.statusCode}';
          continue;
        }
        final data = json.decode(resp.body);
        if (data['error'] != null) {
          lastErr = _odooRpcErrorMessage(data['error']) ?? 'Submit failed';
          continue;
        }
        return null;
      }
      return lastErr ?? 'Could not submit report to manager';
    } catch (e) {
      debugPrint('submitExpenseReportToManager: $e');
      return e.toString();
    }
  }

  Future<String?> _fetchExpenseReportState(int reportId) async {
    if (!await checkAndLoadUserCredentials() || _userId == null) return null;
    if (reportId <= 0) return null;
    try {
      final uid = int.parse(_userId!);
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.expense.sheet',
              'read',
              [
                [reportId]
              ],
              {
                'fields': ['state']
              },
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data['error'] != null || data['result'] is! List) return null;
      final rows = data['result'] as List;
      if (rows.isEmpty || rows.first is! Map) return null;
      return rows.first['state']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> resetExpenseReportToDraft(int reportId) async {
    if (!await checkAndLoadUserCredentials() || _userId == null)
      return 'Not signed in';
    if (reportId <= 0) return 'Invalid report';
    try {
      final uid = int.parse(_userId!);
      final methodAttempts = <String>[
        'reset_expense_sheets',
        'action_sheet_move_to_draft',
        'action_draft',
        'action_reset_to_draft',
        'reset_to_draft',
        'action_set_to_draft',
        'button_draft',
      ];

      String? lastErr;
      for (var i = 0; i < methodAttempts.length; i++) {
        final methodName = methodAttempts[i];
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'hr.expense.sheet',
                methodName,
                [
                  [reportId],
                ],
              ],
            },
            'id': i + 1,
          }),
        );
        if (resp.statusCode != 200) {
          lastErr = 'HTTP ${resp.statusCode}';
          continue;
        }
        final data = json.decode(resp.body);
        if (data['error'] != null) {
          lastErr =
              _odooRpcErrorMessage(data['error']) ?? 'Reset to draft failed';
          continue;
        }
        final newState = await _fetchExpenseReportState(reportId);
        if (newState == null || newState == 'draft') {
          return null;
        }
        lastErr = 'Reset action succeeded but report is still "$newState"';
      }
      return lastErr ?? 'Could not reset report to draft';
    } catch (e) {
      debugPrint('resetExpenseReportToDraft: $e');
      return e.toString();
    }
  }
  Future<String?> removeExpenseFromReport({
    required int expenseId,
    int? reportId,
  }) async {
    if (!await checkAndLoadUserCredentials() || _userId == null)
      return 'Not signed in';
    if (expenseId <= 0) return 'Invalid expense';
    try {
      final uid = int.parse(_userId!);
      final attempts = <Map<String, dynamic>>[
        {'sheet_id': false},
        {'expense_sheet_id': false},
      ];

      for (var i = 0; i < attempts.length; i++) {
        final vals = attempts[i];
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'hr.expense',
                'write',
                [
                  [expenseId],
                  vals,
                ],
              ],
            },
            'id': i + 1,
          }),
        );
        if (resp.statusCode != 200) continue;
        final data = json.decode(resp.body);
        if (data['error'] == null && data['result'] == true) {
          return null;
        }
      }

      if (reportId != null && reportId > 0) {
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'hr.expense.sheet',
                'write',
                [
                  [reportId],
                  {
                    'expense_line_ids': [
                      [3, expenseId]
                    ]
                  },
                ],
              ],
            },
            'id': 99,
          }),
        );
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          if (data['error'] == null && data['result'] == true) {
            return null;
          }
          if (data['error'] != null) {
            return _odooRpcErrorMessage(data['error']) ??
                'Could not remove expense from report';
          }
        }
      }

      return 'Could not remove expense from report';
    } catch (e) {
      debugPrint('removeExpenseFromReport: $e');
      return e.toString();
    }
  }
  static String? _odooRpcErrorMessage(dynamic error) {
    if (error is! Map) return error?.toString();
    final data = error['data'];
    if (data is Map) {
      final msg = data['message'];
      if (msg != null) return msg.toString();
      final dbg = data['debug'];
      if (dbg != null) return dbg.toString().split('\n').first;
    }
    return error.toString();
  }

  static int? _parseOdooCreateId(dynamic result) {
    if (result is int) return result;
    if (result is List && result.isNotEmpty) {
      final first = result.first;
      if (first is int) return first;
      return int.tryParse(first.toString());
    }
    return null;
  }

  /// Creates a draft [hr.expense] for the current user's linked [hr.employee].
  /// Tries common field combinations for different Odoo versions.
  Future<OdooActionResult> createHrExpense({
    required int productId,
    required String name,
    required double totalAmount,
    required DateTime date,
    required bool paidByEmployee,
    String? note,
    int? projectId,
    int? projectSoId,
    String? wayMode,
    String? fromAddress,
    String? toAddress,
    double? quantity,
    double? unitAmount,
    List<int>? taxIds,
  }) async {
    if (!await checkAndLoadUserCredentials() || _userId == null) {
      return OdooActionResult(id: null, error: 'Not signed in');
    }
    if (name.trim().isEmpty) {
      return OdooActionResult(id: null, error: 'Description is required');
    }
    if (totalAmount <= 0) {
      return OdooActionResult(id: null, error: 'Total must be greater than zero');
    }
    try {
      final uid = int.parse(_userId!);
      final empResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.employee',
              'search_read',
              [
                [
                  ['user_id', '=', uid]
                ]
              ],
              {
                'fields': ['id', 'company_id'],
                'limit': 1
              },
            ],
          },
          'id': 1,
        }),
      );
      if (empResp.statusCode != 200) {
        return OdooActionResult(
          id: null,
          error: 'Could not load employee (${empResp.statusCode})',
        );
      }
      final empData = json.decode(empResp.body);
      if (empData['error'] != null) {
        return OdooActionResult(
          id: null,
          error:
              _odooRpcErrorMessage(empData['error']) ?? 'Employee lookup failed',
        );
      }
      final empRows =
          empData['result'] is List ? empData['result'] as List : <dynamic>[];
      if (empRows.isEmpty) {
        return OdooActionResult(id: null, error: 'No HR employee linked to your user. Ask an admin to link your user to an employee.');
      }
      final empRow = empRows.first;
      if (empRow is! Map) {
        return OdooActionResult(id: null, error: 'Invalid employee response');
      }
      final employeeId = empRow['id'] is int
          ? empRow['id'] as int
          : int.tryParse(empRow['id']?.toString() ?? '0') ?? 0;
      if (employeeId <= 0) {
        return OdooActionResult(id: null, error: 'Invalid employee id');
      }
      int? companyId;
      final cid = empRow['company_id'];
      if (cid is List && cid.isNotEmpty && cid[0] != null && cid[0] != false) {
        companyId =
            cid[0] is int ? cid[0] as int : int.tryParse(cid[0].toString());
      }

      // Odoo validates expense UoM against the product's UoM category (_check_product_uom_category).
      // Without product_uom_id, defaults can mismatch (e.g. Mileage product uses km, default is Units).
      int? productUomId;
      final uomResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'product.product',
              'read',
              [
                [productId]
              ],
              {
                'fields': ['uom_id']
              },
            ],
          },
          'id': 2,
        }),
      );
      if (uomResp.statusCode == 200) {
        final uomData = json.decode(uomResp.body);
        if (uomData['error'] == null && uomData['result'] is List) {
          final uomRows = uomData['result'] as List;
          if (uomRows.isNotEmpty && uomRows.first is Map) {
            final u = (uomRows.first as Map)['uom_id'];
            if (u is List && u.isNotEmpty && u[0] != null && u[0] != false) {
              productUomId =
                  u[0] is int ? u[0] as int : int.tryParse(u[0].toString());
            }
          }
        }
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final mode = paidByEmployee ? 'own_account' : 'company_account';
      final noteTrim = note?.trim();
      final noteEmpty = noteTrim == null || noteTrim.isEmpty;
      final cleanWayMode = (() {
        final raw = wayMode?.trim();
        if (raw == null || raw.isEmpty) return null;
        if (raw == '1way' || raw == '2way') return raw;
        return null;
      })();
      final cleanFrom =
          fromAddress?.trim().isEmpty == true ? null : fromAddress?.trim();
      final cleanTo =
          toAddress?.trim().isEmpty == true ? null : toAddress?.trim();
      final effectiveQty = quantity ?? 1.0;
      final effectiveUnit = unitAmount ?? totalAmount;
      // tax_ids uses Odoo ORM command [(6, 0, [ids])]
      final taxIdsCmd = (taxIds != null && taxIds.isNotEmpty)
          ? [
              [6, 0, taxIds]
            ]
          : null;

      // Build vals with correct Odoo field names (confirmed from hr.expense fields_get).
      // project_customer = Project Name (many2one), from_where / to_where = From/To (char),
      // way_mode = Way (selection: 1way/2way), description = Notes (text).
      final vals = <String, dynamic>{
        'employee_id': employeeId,
        'product_id': productId,
        'name': name.trim(),
        'date': dateStr,
        'payment_mode': mode,
        'quantity': effectiveQty,
        'unit_amount': effectiveUnit,
        if (productUomId != null) 'product_uom_id': productUomId,
        if (!noteEmpty) 'description': noteTrim,
        if (projectId != null) 'project_customer': projectId,
        if (projectSoId != null) 'project_so_no': projectSoId,
        if (cleanWayMode != null) 'way_mode': cleanWayMode,
        if (cleanFrom != null) 'from_where': cleanFrom,
        if (cleanTo != null) 'to_where': cleanTo,
        if (taxIdsCmd != null) 'tax_ids': taxIdsCmd,
        if (companyId != null) 'company_id': companyId,
      };

      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.expense',
              'create',
              [vals],
            ],
          },
          'id': 10,
        }),
      );
      if (resp.statusCode != 200) {
        return OdooActionResult(id: null, error: 'HTTP ${resp.statusCode}');
      }
      final data = json.decode(resp.body);
      if (data['error'] != null) {
        final errMsg = _odooRpcErrorMessage(data['error']) ?? 'Create failed';
        debugPrint('createHrExpense vals=$vals error=${data['error']}');
        return OdooActionResult(id: null, error: errMsg);
      }
      final newId = _parseOdooCreateId(data['result']);
      if (newId != null && newId > 0) {
        return OdooActionResult(id: newId, error: null);
      }
      return OdooActionResult(id: null, error: 'Unexpected create response');
    } catch (e, st) {
      debugPrint('createHrExpense: $e\n$st');
      return OdooActionResult(id: null, error: e.toString());
    }
  }
  Future<String?> deleteMyHrExpense(int expenseId) async {
    if (!await checkAndLoadUserCredentials() || _userId == null) {
      return 'Not signed in';
    }
    if (expenseId <= 0) return 'Invalid expense';
    try {
      final uid = int.parse(_userId!);
      const headers = {'Content-Type': 'application/json'};

      final empResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.employee',
              'search_read',
              [
                [
                  ['user_id', '=', uid]
                ]
              ],
              {
                'fields': ['id'],
                'limit': 1
              },
            ],
          },
          'id': 1,
        }),
      );
      if (empResp.statusCode != 200) return 'Could not verify employee';
      final empData = json.decode(empResp.body);
      if (empData['error'] != null) {
        return _odooRpcErrorMessage(empData['error']) ??
            'Employee lookup failed';
      }
      final empRows =
          empData['result'] is List ? empData['result'] as List : <dynamic>[];
      if (empRows.isEmpty) return 'No employee linked to your user';
      final empRow = empRows.first;
      if (empRow is! Map) return 'Invalid employee';
      final employeeId = empRow['id'] is int
          ? empRow['id'] as int
          : int.tryParse(empRow['id']?.toString() ?? '0') ?? 0;
      if (employeeId <= 0) return 'Invalid employee id';

      final expResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.expense',
              'search_read',
              [
                [
                  ['id', '=', expenseId],
                  ['employee_id', '=', employeeId],
                ],
              ],
              {
                'fields': ['id'],
                'limit': 1
              },
            ],
          },
          'id': 2,
        }),
      );
      if (expResp.statusCode != 200) return 'Could not load expense';
      final expData = json.decode(expResp.body);
      if (expData['error'] != null) {
        return _odooRpcErrorMessage(expData['error']) ??
            'Expense lookup failed';
      }
      final expRows =
          expData['result'] is List ? expData['result'] as List : <dynamic>[];
      if (expRows.isEmpty) {
        return 'Expense not found or you cannot delete it';
      }

      final delResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'hr.expense',
              'unlink',
              [
                [expenseId]
              ],
            ],
          },
          'id': 3,
        }),
      );
      if (delResp.statusCode != 200)
        return 'Delete failed (HTTP ${delResp.statusCode})';
      final delData = json.decode(delResp.body);
      if (delData['error'] != null) {
        return _odooRpcErrorMessage(delData['error']) ?? 'Delete failed';
      }
      return null;
    } catch (e, st) {
      debugPrint('deleteMyHrExpense: $e\n$st');
      return e.toString();
    }
  }
  /// Default company on [res.users] (for expense product domain).
  Future<int?> _readCurrentUserCompanyId() async {
    if (_userId == null || _password == null) return null;
    try {
      final uid = int.parse(_userId!);
      const headers = _expenseRpcHeaders;
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'res.users',
              'read',
              [
                [uid]
              ],
              {
                'fields': ['company_id']
              },
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body);
      if (data['error'] != null || data['result'] is! List) return null;
      final rows = data['result'] as List;
      if (rows.isEmpty || rows.first is! Map) return null;
      final cid = (rows.first as Map)['company_id'];
      if (cid is List && cid.isNotEmpty && cid[0] != false && cid[0] != null) {
        final id = cid[0];
        if (id is int) return id;
        return int.tryParse(id.toString());
      }
      return null;
    } catch (e) {
      debugPrint('_readCurrentUserCompanyId: $e');
      return null;
    }
  }

  /// Expense [product_id] options: same rules as Odoo `hr.expense` form — `can_be_expensed`,
  /// and company is empty or matches current user's company (see `product.product` domain on expense).
  Future<List<Map<String, dynamic>>> fetchExpenseProductList() async {
    final list = <Map<String, dynamic>>[];
    final ok = await checkAndLoadUserCredentials();
    if (!ok || _userId == null) return list;
    try {
      final uid = int.parse(_userId!);
      const headers = _expenseRpcHeaders;
      final companyId = await _readCurrentUserCompanyId();

      /// Returns `null` if Odoo rejected the domain (try next); non-null list = use as result.
      Future<List<dynamic>?> searchWithDomain(
          List<dynamic> domain, List<String> fields) async {
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: headers,
          body: json.encode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'product.product',
                'search_read',
                [domain],
                {
                  'fields': fields,
                  'limit': 500,
                  'order': 'name asc',
                },
              ],
            },
            'id': 1,
          }),
        );
        if (resp.statusCode != 200) return null;
        final data = json.decode(resp.body);
        if (data['error'] != null) {
          debugPrint(
              'fetchExpenseProductList domain=$domain fields=$fields → ${data['error']}');
          return null;
        }
        return data['result'] is List ? data['result'] as List : <dynamic>[];
      }

      final domains = <List<dynamic>>[];
      if (companyId != null) {
        domains.add([
          '&',
          '&',
          ['active', '=', true],
          ['can_be_expensed', '=', true],
          '|',
          ['company_id', '=', false],
          ['company_id', '=', companyId],
        ]);
      }
      domains.add([
        '&',
        ['active', '=', true],
        ['can_be_expensed', '=', true],
      ]);
      if (companyId != null) {
        domains.add([
          '&',
          ['active', '=', true],
          '|',
          ['company_id', '=', false],
          ['company_id', '=', companyId],
        ]);
      }
      domains.add([
        ['active', '=', true],
      ]);

      List<dynamic>? result;
      final fieldSets = <List<String>>[
        ['id', 'name', 'display_name', 'standard_price', 'expense_unit_amount', 'list_price'],
        ['id', 'name', 'standard_price'],
        ['id', 'name', 'display_name'],
        ['id', 'name'],
      ];
      outer:
      for (final d in domains) {
        for (final fields in fieldSets) {
          result = await searchWithDomain(d, fields);
          if (result != null) break outer;
        }
      }
      if (result == null) return list;

      for (final e in result) {
        if (e is Map && e['id'] != null) {
          final id = e['id'] is int
              ? e['id'] as int
              : int.tryParse(e['id']?.toString() ?? '0') ?? 0;
          if (id <= 0) continue;
          final dn = e['display_name']?.toString().trim();
          final nm = e['name']?.toString().trim();
          final label = (dn != null && dn.isNotEmpty) ? dn : (nm ?? '');
          final rawPrice = e['standard_price'];
          final standardPrice = rawPrice is num
              ? rawPrice.toDouble()
              : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
          final rawExpenseAmt = e['expense_unit_amount'];
          final expenseUnitAmount = rawExpenseAmt is num
              ? rawExpenseAmt.toDouble()
              : double.tryParse(rawExpenseAmt?.toString() ?? '') ?? 0.0;
          final rawList = e['list_price'];
          final listPrice = rawList is num
              ? rawList.toDouble()
              : double.tryParse(rawList?.toString() ?? '') ?? 0.0;
          list.add({
            'id': id,
            'name': label,
            'standard_price': standardPrice,
            if (expenseUnitAmount > 0) 'expense_unit_amount': expenseUnitAmount,
            if (listPrice > 0) 'list_price': listPrice,
          });
        }
      }
      return list;
    } catch (e) {
      debugPrint('fetchExpenseProductList: $e');
      return list;
    }
  }

  /// Fetch project list for expense dropdown (project.project). Returns [{id, name}, ...].
  /// Fetch customer/project list for expense dropdown (hr.expenses.customer).
  /// Mapped to the `project_customer` field on hr.expense.
  Future<List<Map<String, dynamic>>> fetchExpenseProjectList() async {
    return _fetchExpenseSimpleList(
        'hr.expenses.customer', 'fetchExpenseProjectList');
  }

  /// Fetch sales-order list for expense dropdown (hr.expenses.project).
  /// Mapped to the `project_so_no` field on hr.expense.
  Future<List<Map<String, dynamic>>> fetchExpenseProjectSalesOrderList() async {
    return _fetchExpenseSimpleList(
        'hr.expenses.project', 'fetchExpenseProjectSalesOrderList');
  }

  Future<List<Map<String, dynamic>>> _fetchExpenseSimpleList(
      String model, String debugTag) async {
    final list = <Map<String, dynamic>>[];
    final ok = await checkAndLoadUserCredentials();
    if (!ok || _userId == null) return list;
    try {
      final uid = int.parse(_userId!);
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              model,
              'search_read',
              [[]],
              {
                'fields': ['id', 'name'],
                'order': 'name asc',
                'limit': 500,
              },
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200) return list;
      final data = json.decode(resp.body);
      if (data['error'] != null) {
        debugPrint('$debugTag: ${data['error']}');
        return list;
      }
      final result =
          data['result'] is List ? data['result'] as List : <dynamic>[];
      for (final e in result) {
        if (e is Map && e['id'] != null) {
          list.add({
            'id': e['id'] is int
                ? e['id'] as int
                : int.tryParse(e['id']?.toString() ?? '0') ?? 0,
            'name': e['name']?.toString() ?? '',
          });
        }
      }
      return list;
    } catch (e) {
      debugPrint('$debugTag: $e');
      return list;
    }
  }

  /// Fetch tax list for expense (account.tax). Returns [{id, name}, ...].
  Future<List<Map<String, dynamic>>> fetchExpenseTaxList() async {
    final list = <Map<String, dynamic>>[];
    final ok = await checkAndLoadUserCredentials();
    if (!ok || _userId == null) return list;
    try {
      final uid = int.parse(_userId!);
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'account.tax',
              'search_read',
              [
                [
                  ['active', '=', true],
                  [
                    'type_tax_use',
                    'in',
                    ['purchase', 'all']
                  ],
                ]
              ],
              {
                'fields': ['id', 'name'],
                'order': 'name asc',
                'limit': 200,
              },
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200) return list;
      final data = json.decode(resp.body);
      if (data['error'] != null) {
        debugPrint('fetchExpenseTaxList: ${data['error']}');
        return list;
      }
      final result =
          data['result'] is List ? data['result'] as List : <dynamic>[];
      for (final e in result) {
        if (e is Map && e['id'] != null) {
          list.add({
            'id': e['id'] is int
                ? e['id'] as int
                : int.tryParse(e['id']?.toString() ?? '0') ?? 0,
            'name': e['name']?.toString() ?? '',
          });
        }
      }
      return list;
    } catch (e) {
      debugPrint('fetchExpenseTaxList: \$e');
      return list;
    }
  }
  Future<List<Map<String, dynamic>>> getExpenseAttachments(
      int expenseId) async {
    try {
      final ok = await checkAndLoadUserCredentials();
      if (!ok || _userId == null || _password == null) return [];
      final uid = int.parse(_userId!);
      const headers = _expenseRpcHeaders;
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'ir.attachment',
              'search_read',
              [
                [
                  ['res_model', '=', 'hr.expense'],
                  ['res_id', '=', expenseId],
                ]
              ],
              {
                'fields': ['id', 'name', 'mimetype']
              },
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data['error'] != null || data['result'] == null) return [];
      final list =
          data['result'] is List ? data['result'] as List : <dynamic>[];
      return list
          .map((e) => {
                'id': e['id'] is int
                    ? e['id'] as int
                    : int.tryParse(e['id']?.toString() ?? '0'),
                'name': e['name']?.toString() ?? 'file',
                'mimetype': e['mimetype']?.toString() ?? '',
              })
          .where((m) => (m['id'] as int) > 0)
          .toList();
    } catch (e) {
      debugPrint('getExpenseAttachments: $e');
      return [];
    }
  }

  /// Upload one attachment to [hr.expense] via [ir.attachment] and link by [res_model]/[res_id].
  /// Returns `null` on success, or an error string.
  Future<String?> uploadExpenseAttachment({
    required int expenseId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    try {
      final ok = await checkAndLoadUserCredentials();
      if (!ok || _userId == null || _password == null) return 'Not signed in';
      final uid = int.parse(_userId!);
      const headers = _expenseRpcHeaders;
      final encoded = base64Encode(bytes);
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'ir.attachment',
              'create',
              [
                {
                  'name': fileName,
                  'type': 'binary',
                  'datas': encoded,
                  'res_model': 'hr.expense',
                  'res_id': expenseId,
                  if (mimeType != null && mimeType.trim().isNotEmpty)
                    'mimetype': mimeType.trim(),
                }
              ],
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200)
        return 'Upload failed (HTTP ${resp.statusCode})';
      final data = jsonDecode(resp.body);
      if (data['error'] != null) {
        return _odooRpcErrorMessage(data['error']) ?? 'Upload failed';
      }
      return null;
    } catch (e) {
      debugPrint('uploadExpenseAttachment: $e');
      return e.toString();
    }
  }

  /// Replace one expense attachment with a new file.
  Future<String?> replaceExpenseAttachment({
    required int attachmentId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    try {
      final ok = await checkAndLoadUserCredentials();
      if (!ok || _userId == null || _password == null) return 'Not signed in';
      final trimmed = fileName.trim();
      if (trimmed.isEmpty) return 'File name is required';
      final uid = int.parse(_userId!);
      const headers = _expenseRpcHeaders;
      final encoded = base64Encode(bytes);
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'ir.attachment',
              'write',
              [
                [attachmentId],
                {
                  'name': trimmed,
                  'datas_fname': trimmed,
                  'datas': encoded,
                  if (mimeType != null && mimeType.trim().isNotEmpty)
                    'mimetype': mimeType.trim(),
                },
              ],
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200)
        return 'Replace failed (HTTP ${resp.statusCode})';
      final data = jsonDecode(resp.body);
      if (data['error'] != null) {
        return _odooRpcErrorMessage(data['error']) ?? 'Replace failed';
      }
      return null;
    } catch (e) {
      debugPrint('replaceExpenseAttachment: $e');
      return e.toString();
    }
  }

  /// Delete one expense attachment.
  Future<String?> deleteExpenseAttachment(int attachmentId) async {
    try {
      final ok = await checkAndLoadUserCredentials();
      if (!ok || _userId == null || _password == null) return 'Not signed in';
      final uid = int.parse(_userId!);
      const headers = _expenseRpcHeaders;
      final resp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'ir.attachment',
              'unlink',
              [
                [attachmentId],
              ],
            ],
          },
          'id': 1,
        }),
      );
      if (resp.statusCode != 200)
        return 'Delete failed (HTTP ${resp.statusCode})';
      final data = jsonDecode(resp.body);
      if (data['error'] != null) {
        return _odooRpcErrorMessage(data['error']) ?? 'Delete failed';
      }
      return null;
    } catch (e) {
      debugPrint('deleteExpenseAttachment: $e');
      return e.toString();
    }
  }

  static bool _looksLikeHtml(Uint8List b) {
    if (b.length < 4) return false;
    if (b[0] != 0x3C) return false; // '<'
    if (b[1] == 0x21 || b[1] == 0x3F) return true; // '<!' or '<?'
    if (b.length >= 5 &&
        b[1] == 0x68 &&
        b[2] == 0x74 &&
        b[3] == 0x6D &&
        b[4] == 0x6C) return true; // 'html'
    return false;
  }

  /// Headers for GET /web/content – Cookie only (no Content-Type). Matches PMform/OKR approach.
  Future<Map<String, String>> _expenseAttachmentGetHeaders(
      {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (forceRefresh) {
      await _ensureWebSession(force: true);
    }
    String? cookie = prefs.getString('session_id');
    final sessId = prefs.getString('sessionId') ?? '';
    if ((cookie == null || cookie.isEmpty) && sessId.isNotEmpty)
      cookie = 'session_id=$sessId';
    if ((cookie == null || cookie.isEmpty) && !forceRefresh) {
      await checkAndLoadUserCredentials();
      final refreshed = await SharedPreferences.getInstance();
      cookie = refreshed.getString('session_id');
      final rs = refreshed.getString('sessionId') ?? '';
      if ((cookie == null || cookie.isEmpty) && rs.isNotEmpty)
        cookie = 'session_id=$rs';
    }
    return {if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie};
  }

  /// Download expense attachment as raw bytes. Tries /web/content then JSON-RPC. Returns null if response looks like HTML or fails.
  Future<Uint8List?> getExpenseAttachmentBytes(
      int attachmentId, String fileName) async {
    try {
      final ok = await checkAndLoadUserCredentials();
      if (!ok) return null;
      final encodedName = Uri.encodeComponent(
          fileName.trim().isEmpty ? 'attachment' : fileName.trim());
      final dbSuffix = database.isNotEmpty ? '&db=$database' : '';
      final dbPrefix = database.isNotEmpty ? '?db=$database' : '';
      final prefs = await SharedPreferences.getInstance();
      final sessId = prefs.getString('sessionId') ?? '';
      final sessParam =
          sessId.isNotEmpty ? '&session_id=${Uri.encodeComponent(sessId)}' : '';
      final candidates = <String>[
        '$baseUrl/web/content/$attachmentId?download=1&filename=$encodedName$dbSuffix$sessParam',
        '$baseUrl/web/content/$attachmentId/$encodedName?download=1$dbSuffix$sessParam',
        '$baseUrl/web/content/$attachmentId?download=1$dbSuffix$sessParam',
        '$baseUrl/web/content/$attachmentId$dbPrefix$sessParam',
        '$baseUrl/web/content/$attachmentId?download=1&filename=$encodedName$dbSuffix',
        '$baseUrl/web/content/$attachmentId/$encodedName?download=1$dbSuffix',
        '$baseUrl/web/content/$attachmentId?download=1$dbSuffix',
        '$baseUrl/web/content/$attachmentId$dbPrefix',
      ];

      // Use Cookie-only headers for GET (no Content-Type) – /web/content may reject GET with application/json
      Future<Uint8List?> tryWithHeaders(Map<String, String> headers) async {
        for (final url in candidates) {
          final resp = await http.get(Uri.parse(url), headers: headers);
          final contentType = resp.headers['content-type']?.toLowerCase() ?? '';
          if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) continue;
          if (contentType.contains('text/html') ||
              _looksLikeHtml(resp.bodyBytes)) continue;
          return resp.bodyBytes;
        }
        return null;
      }

      Uint8List? result =
          await tryWithHeaders(await _expenseAttachmentGetHeaders());
      if (result != null) return result;
      // Retry with forced session refresh (PMform pattern)
      result = await tryWithHeaders(
          await _expenseAttachmentGetHeaders(forceRefresh: true));
      if (result != null) return result;
      // Fallback: JSON-RPC read datas
      if (_userId == null || _password == null) return null;
      final uid = int.parse(_userId!);
      final headers2 = await _odooHeaders();
      final rpcResp = await http.post(
        Uri.parse(jsonRpcUrl),
        headers: headers2,
        body: jsonEncode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              uid,
              _password,
              'ir.attachment',
              'search_read',
              [
                [
                  ['id', '=', attachmentId]
                ]
              ],
              {
                'fields': ['datas']
              },
            ],
          },
          'id': 1,
        }),
      );
      if (rpcResp.statusCode != 200) return null;
      final data = jsonDecode(rpcResp.body);
      if (data['error'] != null || data['result'] == null) return null;
      final list =
          data['result'] is List ? data['result'] as List : <dynamic>[];
      if (list.isEmpty) return null;
      final att = list[0];
      if (att is! Map) return null;
      final datas = att['datas'];
      if (datas == null || datas is! String) return null;
      return base64Decode(datas);
    } catch (e) {
      debugPrint('getExpenseAttachmentBytes: $e');
      return null;
    }
  }

  /// Download expense (or any) attachment. Tries /web/content first (works with filestore), then JSON-RPC datas.
  /// Returns local file path or null on failure.
  Future<String?> getExpenseAttachmentFile(
      int attachmentId, String fileName) async {
    try {
      final ok = await checkAndLoadUserCredentials();
      if (!ok) return null;
      final encodedName = Uri.encodeComponent(
          fileName.trim().isEmpty ? 'attachment' : fileName.trim());
      final dbSuffix = database.isNotEmpty ? '&db=$database' : '';
      final dbPrefix = database.isNotEmpty ? '?db=$database' : '';
      final candidates = <String>[
        '$baseUrl/web/content/$attachmentId?download=1&filename=$encodedName$dbSuffix',
        '$baseUrl/web/content/$attachmentId/$encodedName?download=1$dbSuffix',
        '$baseUrl/web/content/$attachmentId?download=1$dbSuffix',
        '$baseUrl/web/content/$attachmentId$dbPrefix',
      ];
      Future<String?> tryWithHeaders(Map<String, String> headers) async {
        for (final url in candidates) {
          final resp = await http.get(Uri.parse(url), headers: headers);
          final contentType = resp.headers['content-type']?.toLowerCase() ?? '';
          if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) continue;
          if (contentType.contains('text/html') ||
              _looksLikeHtml(resp.bodyBytes)) continue;
          final ext = fileName.contains('.') ? fileName.split('.').last : 'bin';
          final safeExt = ext.length > 10 ? 'bin' : ext;
          final file = File(
              '${Directory.systemTemp.path}/exp_att_${attachmentId}_${DateTime.now().millisecondsSinceEpoch}.$safeExt');
          await file.writeAsBytes(resp.bodyBytes, flush: true);
          return file.path;
        }
        return null;
      }

      String? path = await tryWithHeaders(await _expenseAttachmentGetHeaders());
      if (path != null) return path;
      path = await tryWithHeaders(
          await _expenseAttachmentGetHeaders(forceRefresh: true));
      if (path != null) return path;
      return null;
    } catch (e) {
      debugPrint('getExpenseAttachmentFile: $e');
      return null;
    }
  }

  Future<String?> fetchExpenseSheetReportPdf(int reportId,
      {bool preferSigma = true}) async {
    return null;
  }

  /// Products for Inventory (name, price, on hand, optional thumbnail).
  /// Each map: `id`, `name`, `list_price`, `qty_available`, `uom`, `image_base64`.
  Future<List<Map<String, dynamic>>> fetchInventoryProductList() async {
    try {
      final ok = await checkAndLoadUserCredentials();
      if (!ok || _userId == null || _password == null) return [];
      final uid = int.parse(_userId!);
      const headers = _expenseRpcHeaders;

      String m2o(dynamic v) {
        if (v is List && v.length > 1) return v[1]?.toString() ?? '';
        return '';
      }

      Future<List<Map<String, dynamic>>?> tryFields(
          List<String> fields, List<dynamic> domain) async {
        final resp = await http.post(
          Uri.parse(jsonRpcUrl),
          headers: headers,
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'call',
            'params': {
              'service': 'object',
              'method': 'execute_kw',
              'args': [
                database,
                uid,
                _password,
                'product.product',
                'search_read',
                [domain],
                {
                  'fields': fields,
                  'limit': 5000,
                  'order': 'name asc',
                },
              ],
            },
            'id': 1,
          }),
        );
        if (resp.statusCode != 200) return null;
        final data = jsonDecode(resp.body);
        if (data['error'] != null) {
          debugPrint(
              '⚠️ fetchInventoryProductList fields=$fields → ${data['error']}');
          return null;
        }
        final list =
            data['result'] is List ? data['result'] as List : <dynamic>[];
        final out = <Map<String, dynamic>>[];
        for (final e in list) {
          if (e is! Map) continue;
          final id = e['id'];
          dynamic img = e['image_128'];
          if (img == false || img == null) img = e['image_256'];
          String? imgStr;
          if (img is String && img.isNotEmpty) imgStr = img;
          final priceRaw = e['list_price'] ?? e['lst_price'];
          final qty = e['qty_available'];
          final pid = id is int ? id : int.tryParse(id?.toString() ?? '');
          out.add({
            'id': pid,
            'name': (e['display_name'] ?? e['name'] ?? '—').toString(),
            'list_price': priceRaw is num
                ? priceRaw.toDouble()
                : double.tryParse(priceRaw?.toString() ?? '') ?? 0.0,
            'qty_available': qty is num
                ? qty.toDouble()
                : double.tryParse(qty?.toString() ?? '') ?? 0.0,
            'uom': m2o(e['uom_id']),
            'image_base64': imgStr,
          });
        }
        return out;
      }

      final domains = <List<dynamic>>[
        [
          ['active', '=', true],
          ['type', '=', 'product'],
        ],
        [
          ['active', '=', true],
        ],
      ];

      final fieldSets = <List<String>>[
        [
          'name',
          'display_name',
          'list_price',
          'lst_price',
          'qty_available',
          'uom_id',
          'image_128',
        ],
        [
          'name',
          'list_price',
          'lst_price',
          'qty_available',
          'uom_id',
          'image_128',
        ],
        ['name', 'list_price', 'qty_available', 'uom_id'],
        ['name', 'qty_available', 'uom_id'],
        ['name', 'qty_available'],
        ['name'],
      ];

      for (final domain in domains) {
        for (final fields in fieldSets) {
          final r = await tryFields(fields, domain);
          if (r != null) {
            debugPrint('✅ fetchInventoryProductList: ${r.length} products');
            return r;
          }
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ fetchInventoryProductList: $e');
      return [];
    }
  }
}

// Project model class
class Project {
  final int id;
  final String name;
  final String? description;
  final String? partnerName;
  final String? partnerEmail;
  final String? partnerPhone;
  final String? dateStart;
  final String? dateEnd;
  final String? duration;
  final String? warranty;
  final int taskCount;
  final String? stageName;
  final int? color;
  final bool isFavorite;
  final String? userImage;
  final int? userId;

  Project({
    required this.id,
    required this.name,
    this.description,
    this.partnerName,
    this.partnerEmail,
    this.partnerPhone,
    this.dateStart,
    this.dateEnd,
    this.duration,
    this.warranty,
    required this.taskCount,
    this.stageName,
    this.color,
    required this.isFavorite,
    this.userImage,
    this.userId,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      description: json['description'] is String ? json['description'] : '',
      partnerName: json['partner_id'] != null && json['partner_id'] is List ? json['partner_id'][1] : null,
      partnerEmail: json['partner_email'] is String ? json['partner_email'] : '',
      partnerPhone: json['partner_phone'] is String ? json['partner_phone'] : '',
      dateStart: json['date_start'] is String ? json['date_start'] : '',
      dateEnd: json['date'] is String ? json['date'] : '',
      duration: json['duration'] is String ? json['duration'] : '',
      warranty: json['warranty'] != null ? json['warranty'].toString() : '',
      taskCount: json['task_count'] is int ? json['task_count'] : 0,
      stageName: json['stage_id'] != null && json['stage_id'] is List
          ? json['stage_id'][1] as String?
          : (json['last_update_status'] != null &&
                  json['last_update_status'] != false
              ? json['last_update_status'].toString()
              : null),
      color: json['color'] is int ? json['color'] : 0,
      isFavorite: json['is_favorite'] is bool ? json['is_favorite'] : false,
      userImage: json['user_image'] is String ? json['user_image'] : '',
      userId: json['user_id'] != null && json['user_id'] is List ? json['user_id'][0] : null,
    );
  }
}


