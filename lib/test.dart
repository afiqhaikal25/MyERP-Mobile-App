import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';


class OdooService {
  final String baseUrl = 'https://myerp.com.my/jsonrpc';
  final String database = 'myerp_db';
  String? _password;
  String? _userId;
  
  get ticketId => null;
  
  get checkOutTime => null;

  
Future<String?> authenticate(String email, String password) async {
    try {
        final response = await http.post(
            Uri.parse(baseUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
                "jsonrpc": "2.0",
                "method": "call",
                "params": {
                    "service": "common",
                    "method": "login",
                    "args": [database, email, password],
                },
                "id": 1,
            }),
        );

        if (response.statusCode == 200) {
            final responseData = json.decode(response.body);
            if (responseData['error'] != null) {
                print("❌ Authentication failed: ${responseData['error']}");
                return null;
            }
            _userId = responseData['result'].toString();
            _password = password;

            // Simpan dalam SharedPreferences
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString('user_email', email);
            await prefs.setString('user_password', password);

            print("✅ User authenticated with ID: $_userId");
            return _userId;
        } else {
            print("❌ HTTP Error: ${response.statusCode}, Response: ${response.body}");
            return null;
        }
    } catch (e) {
        print("❌ Exception Error: $e");
        return null;
    }
}

Future<bool> submitCheckOut(int ticketId, String checkOutTime) async {
  if (_password == null || _userId == null) {
    print("⚠️ User not authenticated. Please login first.");
    return false;
  }

  try {
    print("🔹 Sending Check-Out Request: Ticket ID: $ticketId, Time: $checkOutTime");

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            database,
            int.parse(_userId!), // Pastikan ini bukan null
            _password!,
            "helpdesk.ticket",
            "write",
            [[ticketId], {"check_out_string": checkOutTime}]
          ]
        },
        "id": 2,
      }),
    );

    print("🔹 Check-Out Response: ${response.body}");

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);

      if (responseData['result'] == true) {
        print("✅ Check-Out successful.");
        await saveCheckOutStatus(ticketId); // Simpan status check-out dalam local storage
        return true;
      } else {
        print("❌ Check-Out failed: ${responseData['error']}");
        return false;
      }
    } else {
      print("❌ HTTP Error: ${response.statusCode}, Response: ${response.body}");
      return false;
    }
  } catch (e) {
    print("❌ Exception Error: $e");
    return false;
  }
}



  // Fetch the list of workers (users) from Odoo
  Future<List<Map<String, dynamic>>> fetchWorkers() async {
    try {
      print("🔹 Fetching Workers from Odoo...");

      final response = await http.post(
        Uri.parse(baseUrl),
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
              'id': worker['id'],
              'name': worker['name'],
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

  // Fetch tickets from Odoo based on user ID
  Future<List<dynamic>> fetchTickets(String userId) async {
    try {
      print("🔹 Fetching Tickets for User ID: $userId");

      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jsonrpc': '2.0',
          'method': 'call',
          'params': {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              database,
              int.parse(userId),
              _password,
              'helpdesk.ticket',
              'search_read',
              [
                [
                  ['user_id', '=', int.parse(userId)]
                ]
              ],
              {
                'fields': [
                  'id', 'name', 'priority', 'create_date', 'partner_name', 'stage_name',
                  'partner_email', 'serial_name', 'equipment_user', 'person_name',
                  'partner_phone', 'department', 'address', 'category_name', 'sub_name',
                  'prob_name', 'ticket_number_display'
                ],
                'order': 'create_date desc',
              },
            ],
          },
          'id': 2,
        }),
      );

      print("🔹 Fetch Tickets Response: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['result'] != null) {
          final tickets = responseData['result'] as List<dynamic>;
          print("✅ Fetched tickets: $tickets");
          return tickets;
        } else if (responseData['error'] != null) {
          print("❌ Error fetching tickets: ${responseData['error']}");
          return [];
        } else {
          print("❌ Unexpected response format: ${response.body}");
          return [];
        }
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

      final response = await http.post(
        Uri.parse(baseUrl),
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
              [[ticketId], {'check_in_string': checkInString}],
            ],
          },
          'id': 3,
        }),
      );

      print("🔹 Check-In Response: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        if (responseData['result'] == true) {
          print("✅ Check-In submitted successfully.");
          return true;
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
    final response = await http.post(
      Uri.parse('https://myerp.com.my/jsonrpc'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "model": "res.users",
          "method": "search_read",
          "args": [],
          "kwargs": {
            "fields": ["id", "name"],
            "domain": [],
            "limit": 50
          }
        }
      }),
    );

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(result['result']);
    } else {
      throw Exception("Failed to fetch users from Odoo");
    }

    
  }
}
