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


class OdooService {
  final String baseUrl = 'https://myerp.com.my';
  final String jsonRpcUrl = 'https://myerp.com.my/jsonrpc';
  final String database = 'myerp_db';
  String? _password;
  String? _userId;
  String? lastErrorMessage;

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
  

  Future<bool> checkAndLoadUserCredentials() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? email = prefs.getString('user_email');
    String? password = prefs.getString('user_password');

    if (email != null && password != null) {
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
              await sendFcmToken(fcmToken);
              print('✅ FCM token sent to Odoo after login.');
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
    print("🔹 Submitting Check-Out: Ticket ID: $ticketId, Check-Out Time: $checkOutString");

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
          'check_out_time': checkOutString,
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
    if (responseData.containsKey('error')) {
      print("❌ Check-Out submission failed. Response: ${response.body}");
      return false;
    }

    final result = responseData['result'];
    bool success = false;
    if (result is Map) {
      if (result['success'] == true) {
        success = true;
      } else if (result['result'] is Map && (result['result'] as Map)['success'] == true) {
        // Handle older double-wrapped server responses
        success = true;
      }
    }

    if (success) {
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
      print("🔹 Submitting Check-In: Ticket ID: $ticketId, Check-In Time: $checkInString");

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
            'check_in_time': checkInString,
          },
          'id': 1,
        }),
      );

      print("🔹 Check-In Response: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Check for JSON-RPC error
        if (responseData.containsKey('error')) {
          print("❌ Check-In submission failed. Response: ${response.body}");
          return false;
        }

        // Check for success in result (JSON-RPC format)
        if (responseData.containsKey('result')) {
          final result = responseData['result'];

          // Odoo `type='json'` controllers get automatically wrapped as:
          // {jsonrpc, id, result: <controller_return>}
          // Your controller currently returns another JSON-RPC-like object, so we may see:
          // result: { jsonrpc, result: { success: true, ... } }
          bool success = false;
          if (result is Map) {
            if (result['success'] == true) {
              success = true;
            } else if (result['result'] is Map && (result['result'] as Map)['success'] == true) {
              success = true;
            }
          }

          if (success) {
            print("✅ Check-In submitted successfully.");
            return true;
          }

          print("❌ Check-In submission failed. Response: ${response.body}");
          return false;
        } else {
          print("❌ Check-In submission failed. Response: ${response.body}");
          return false;
        }
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

    final response = await http.post(
      Uri.parse('$baseUrl/api/update_description'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': await getSessionId(),
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

    if (response.statusCode != 200) return false;
    final responseData = json.decode(response.body);
    if (responseData['error'] != null) return false;

    final result = responseData['result'];
    if (result is Map && result['success'] == true) return true;
    if (result is Map && result['result'] is Map && (result['result'] as Map)['success'] == true) return true;
    return false;
  } catch (e) {
    print("❌ Error updating description: $e");
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
    final odooUrl = prefs.getString('odooUrl') ?? 'https://myerp.com.my';
    final sessionId = prefs.getString('sessionId') ?? '';
    final userId = prefs.getString('user_id') ?? '';

    final response = await http.post(
      Uri.parse('$odooUrl/api/user/image'),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': 'session_id=$sessionId',
      },
      body: jsonEncode({'user_id': userId}),
    );
    print('User image response: ${response.statusCode} ${response.body}');
    final data = jsonDecode(response.body);
    final result = data['result'] ?? {};
    if (result['success'] == true && result['image_base64'] != null) {
      return result['image_base64'];
    }
  } catch (e) {
    print("❌ Error fetching user image: $e");
  }
  return '';
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
    debugPrint("🔍 Checking admin status for user ID: $_userId");

    if (_userId == null || _password == null) {
      debugPrint("❌ User ID or password is null");
      return false;
    }

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
    // Use JSON-RPC format for /store_fcm_token endpoint
    final prefs = await SharedPreferences.getInstance();
    final String? sessionCookie = prefs.getString('session_id');
    
    if (sessionCookie == null) {
      print("❌ Session cookie not found. User needs to re-authenticate.");
      return false;
    }

    final response = await http.post(
      Uri.parse(jsonRpcUrl),
      headers: {
        'Content-Type': 'application/json',
        'Cookie': sessionCookie,
      },
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "token": token,
        },
        "id": 1,
      }),
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      
      // Handle potential JSON-RPC error wrapper from Odoo on failure
      if (responseData.containsKey('error')) {
        final error = responseData['error'];
        print("❌ Failed to send FCM Token: ${error['data']?['message'] ?? error['message']}");
        return false;
      }

      // Check for success in result (JSON-RPC format)
      if (responseData.containsKey('result')) {
        final result = responseData['result'];
        if (result is Map && result['success'] == true) {
          print("✅ FCM token sent successfully.");
          return true;
        } else {
          print("❌ Failed to send FCM Token: ${result['error'] ?? 'Unknown server error'}");
          return false;
        }
      } else if (responseData['success'] == true) {
        // Fallback for non-JSON-RPC response
        print("✅ FCM token sent successfully.");
        return true;
      } else {
        print("❌ Failed to send FCM Token: ${responseData['error'] ?? 'Unknown server error'}");
        return false;
      }
    } else {
      print("❌ Error sending FCM token. Status Code: ${response.statusCode}, Response: ${response.body}");
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
              [
                [
                  ["user_id", "=", int.parse(_userId!)]
                ]
              ],
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
                  "duration",
                  "warranty",
                  "task_count",
                  "stage_id",
                  "color",
                  "is_favorite",
                  "user_id"
                ],
                "order": "name asc"
              }
            ]
          },
          "id": 1
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] != null) {
          print("✅ Projects fetched successfully: ${data['result'].length} projects");
          return (data['result'] as List)
              .map((project) => Project.fromJson(project))
              .toList();
        } else {
          print("❌ No projects found in response");
          return [];
        }
      } else {
        print("❌ Error fetching projects: ${response.statusCode}");
        return [];
      }
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
      stageName: json['stage_id'] != null && json['stage_id'] is List ? json['stage_id'][1] : null,
      color: json['color'] is int ? json['color'] : 0,
      isFavorite: json['is_favorite'] is bool ? json['is_favorite'] : false,
      userImage: json['user_image'] is String ? json['user_image'] : '',
      userId: json['user_id'] != null && json['user_id'] is List ? json['user_id'][0] : null,
    );
  }
}


