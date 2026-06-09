import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ticketprogress.dart';
import '../odoo_service.dart';
import 'dart:convert'; // ✅ Tambahkan ini untuk gunakan jsonDecode()
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'flutter_pdfview.dart';
import 'feedback.dart';  // Updated import path
import 'totalfeedback.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:async'; // ✅ Tambahkan ini untuk Timer
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../odoo_display.dart';

Future<Position> determinePosition() async {
  bool serviceEnabled;
  LocationPermission permission;

  // Check if GPS is on
  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return Future.error('Location services are disabled.');
  }

  // Check permission status
  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return Future.error('Location permissions are denied');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return Future.error(
        'Location permissions are permanently denied, we cannot request.');
  }

  // Get current position
  return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high);
}

class TicketDetailsPage extends StatefulWidget {
  final VoidCallback? onTicketUpdated;
  final Map<String, dynamic> ticket;
  final OdooService odooService;
  final bool isDarkMode;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final bool isAdminView;

  const TicketDetailsPage({
    super.key,
    required this.ticket,
    required this.odooService,
    required this.isDarkMode,
    this.checkInTime,
    this.checkOutTime,
    this.onTicketUpdated,
    this.isAdminView = false,
  });
  

  @override
  _TicketDetailsPageState createState() => _TicketDetailsPageState();
}

class _TicketDetailsPageState extends State<TicketDetailsPage> {
  bool isCheckedIn = false;
  bool isCheckoutComplete = false;
  DateTime? checkInTime;
  bool _isFeedbackGiven = false;

  late Ticket ticket;

  Future<void> _showLoadingDialog(String message) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  

@override
void initState() {
  super.initState();
  _loadCheckInStatus();
  _fetchCheckOutFromOdoo();
  _createTicketObject();
  _loadProgressFromSharedPreferences();
  _refreshTicketFromOdoo(); // Tambah ini
}

Future<void> _refreshTicketFromOdoo() async {
  Map<String, dynamic>? updatedTicket = await widget.odooService.getTicketDetails(widget.ticket['id']);
  if (updatedTicket != null) {
    widget.ticket.addAll(updatedTicket);

    // Tambah log untuk semak nilai
    debugPrint("🎯 Feedback Scales: ${updatedTicket['feedback_scale1']}, ${updatedTicket['feedback_scale2']}, ${updatedTicket['feedback_scale3']}, ${updatedTicket['feedback_scale4']}, ${updatedTicket['feedback_scale5']}, ${updatedTicket['feedback_scale6']}");

    bool feedbackStatus = [
      updatedTicket['feedback_scale1'],
      updatedTicket['feedback_scale2'],
      updatedTicket['feedback_scale3'],
      updatedTicket['feedback_scale4'],
      updatedTicket['feedback_scale5'],
      updatedTicket['feedback_scale6'],
    ].every((scale) =>
        scale != null &&
        scale.toString().trim().isNotEmpty &&
        double.tryParse(scale.toString()) != null &&
        double.parse(scale.toString()) > 0.0); // ✅ pastikan lebih dari 0

    setState(() {
      _isFeedbackGiven = feedbackStatus;
    });

    debugPrint("✅ Feedback status updated: $_isFeedbackGiven");
  }
}



IconData getIconByName(String? name) {
  switch (name) {
    case 'login':
      return Icons.login;
    case 'logout':
      return Icons.logout;
    case 'description':
      return Icons.description;
    case 'comment':
      return Icons.comment;
    case 'attach_file':
      return Icons.attach_file;
    default:
      return Icons.help_outline;
  }
}

String _iconName(IconData? icon) {
  if (icon == Icons.login) return 'login';
  if (icon == Icons.logout) return 'logout';
  if (icon == Icons.description) return 'description';
  if (icon == Icons.comment) return 'comment';
  if (icon == Icons.attach_file) return 'attach_file';
  return 'help_outline';
}


  

  void _createTicketObject() {
    ticket = Ticket(
      title: odooStr(widget.ticket['title'] ?? widget.ticket['name'], 'No Title'),
      id: widget.ticket['id'],
      isCompleted: widget.ticket['isCompleted'] ?? false,
      checkInTime: null,
      progressSteps: [],
    );
  }

DateTime? _parseOdooDateTime(dynamic raw) {
  if (raw == null || raw == false) return null;
  final s = raw.toString().trim();
  if (s.isEmpty || s == 'false') return null;
  try {
    return DateFormat('yyyy-MM-dd HH:mm:ss').parse(s);
  } catch (_) {
    try {
      return DateFormat('dd/MM/yyyy HH:mm:ss').parse(s);
    } catch (_) {
      return null;
    }
  }
}

Future<void> _loadCheckInStatus() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  final ticketId = widget.ticket['id'];

  // Prefer Odoo (source of truth), then ticket map from list API, then local prefs.
  Map<String, dynamic>? ticketData =
      await widget.odooService.getTicketDetails(ticketId);
  DateTime? checkInTime = _parseOdooDateTime(ticketData?['check_in']) ??
      _parseOdooDateTime(widget.ticket['check_in']);

  if (checkInTime != null) {
    setState(() {
      ticket.checkInTime = checkInTime;
      isCheckedIn = true;
    });
    await prefs.setBool('checked_in_$ticketId', true);
    await prefs.setString(
      'checkInTime_$ticketId',
      DateFormat('dd/MM/yyyy HH:mm:ss').format(checkInTime),
    );
    widget.ticket['check_in'] =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(checkInTime);
    return;
  }

  // No server check-in — clear stale local flag so Check In buttons show again.
  await prefs.remove('checked_in_$ticketId');
  await prefs.remove('checkInTime_$ticketId');
  if (mounted) {
    setState(() {
      isCheckedIn = false;
      ticket.checkInTime = null;
    });
  }
}

void _checkAndRequestLocation() async {
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    print('Lat: ${position.latitude}, Long: ${position.longitude}');
  } else {
    print('Permission not granted');
  }
}


Future<double> calculateDistance(double lat1, double lon1) async {
  bool serviceEnabled;
  LocationPermission permission;

  serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Location services are disabled.');
  }

  permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Location permissions are denied.');
    }
  }

  Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high);

  return Geolocator.distanceBetween(
      lat1, lon1, position.latitude, position.longitude);
}


Future<void> _saveCheckInStatus(DateTime checkInTime) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setBool('checked_in_${widget.ticket['id']}', true);
  await prefs.setString('checkInTime_${widget.ticket['id']}', DateFormat('dd/MM/yyyy HH:mm:ss').format(checkInTime));
}


Future<void> _saveCheckOutStatus() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isCheckedOut_${widget.ticket['id']}', true);
  await prefs.setString('checkOutTime_${widget.ticket['id']}', DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()));
}


Future<void> _fetchCheckOutFromOdoo() async {
  Map<String, dynamic>? ticketData = await widget.odooService.getTicketDetails(widget.ticket['id']);

  final checkOutTime = _parseOdooDateTime(ticketData?['check_out']);
  if (checkOutTime != null) {
    setState(() {
      ticket.progressSteps.add(
        ProgressStep(
          title: 'Technician Check Out',
          timestamp: checkOutTime,
          isCompleted: true,
          icon: Icons.logout,
        ),
      );
      isCheckoutComplete = true;
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('checkOutTime_${widget.ticket['id']}', DateFormat('dd/MM/yyyy HH:mm:ss').format(checkOutTime));
  }
}



  @override
  Widget build(BuildContext context) {
    final ticketTitle = odooStr(
      widget.ticket['ticket_number_display'] ?? widget.ticket['name'],
      'Ticket Details',
    );
    final topBarForeground =
        widget.isDarkMode ? Colors.black87 : const Color(0xFF282454);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: topBarForeground),
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      ticketTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: topBarForeground,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const FaIcon(
                      FontAwesomeIcons.whatsapp,
                      color: Color(0xFF25D366),
                    ),
                    tooltip: 'WhatsApp',
                    onPressed: _openWhatsAppChat,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    children: [
                      _buildTicketInfoCard(),
                      const SizedBox(height: 16),
                      _buildLocationButton(),
                      const SizedBox(height: 16),
                      _buildCheckInOrUpdateButton(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 4,
      color: widget.isDarkMode ? Colors.black : Colors.white, // Black for dark mode, white for light
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _buildDetailRow(
                    'Created Date',
                    odooStr(widget.ticket['create_date'], 'N/A'),
                    Icons.calendar_today,
                    const Color(0xFF6EE7B7), // Light green for date icon
                    iconSize: 16,
                    textSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(widget.ticket['stage_name']),
                const SizedBox(width: 8),
                _buildPriorityBadge(widget.ticket['priority']),
              ],
            ),
            const Divider(),
            ..._buildDetailsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationButton() {
    return Center(
      child: SizedBox(
        width: 50,
        height: 50,
        child: FloatingActionButton(
          heroTag: 'locationBtn',
          backgroundColor: widget.isDarkMode ? Colors.grey[800] : Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(100),
            side: BorderSide(color: Colors.grey, width: 1),
          ),
          onPressed: _showLocationDialog,
          child: widget.isDarkMode
              ? const Icon(
                  Icons.location_on,
                  size: 24,
                  color: Colors.white,
                )
              : ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      colors: [
                        Color(0xFF4285F4), // Biru Google
                        Color(0xFF34A853), // Hijau Google
                        Color(0xFFFBBC05), // Kuning Google
                        Color(0xFFEA4335), // Merah Google
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds);
                  },
                  child: const Icon(
                    Icons.location_on,
                    size: 24,
                    color: Colors.white, // Akan di-mask oleh gradient
                  ),
                ),
        ),
      ),
    );
  }

  String? _getWhatsappPhone() {
    final rawPhone = widget.ticket['partner_phone']?.toString().trim();
    if (rawPhone == null || rawPhone.isEmpty) {
      return null;
    }

    final cleaned = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) {
      return null;
    }

    if (cleaned.startsWith('+')) {
      final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? null : digits;
    }

    final digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return null;
    }

    // Default Malaysia format if no country code provided.
    if (digits.startsWith('0')) {
      return '60${digits.substring(1)}';
    }

    return digits;
  }

  Future<void> _openWhatsAppChat() async {
    final phone = _getWhatsappPhone();
    if (phone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact number not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final appUri = Uri.parse('whatsapp://send?phone=$phone');
    final webUri = Uri.parse('https://wa.me/$phone');

    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri, mode: LaunchMode.externalApplication);
      return;
    }

    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to open WhatsApp'),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showLocationDialog() async {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return FutureBuilder<Map<String, dynamic>>(
          future: _getLocationAndDistance(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Container(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFF46BBFE).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFF46BBFE),
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Getting Location...',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF282454),
                        ),
                      ),
                      const SizedBox(height: 15),
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF46BBFE)),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Location Error',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF282454),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF46BBFE),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                  ),
                ],
                  ),
                ),
              );
            }
            final data = snapshot.data!;
            // DEBUG: Print values
            print("User Lat: ${data['userLat']}, User Lon: ${data['userLon']}");
            print("Ticket Lat: ${data['ticketLat']}, Ticket Lon: ${data['ticketLon']}");

            if (data['ticketLat'] == null || data['ticketLon'] == null) {
              debugPrint('FALLBACK: ticket location fallback ke Cyberjaya');
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF46BBFE), Color(0xFF19543E)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF46BBFE).withOpacity(0.3),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.white,
                          size: 35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Location Information',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF282454),
                        ),
              ),
                      const SizedBox(height: 24),
                      
                      // Your Location Section
                      _buildLocationSection(
                        'Your Current Location',
                        Icons.my_location,
                        const Color(0xFF46BBFE),
                        data['userLat'],
                        data['userLon'],
                        null,
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Ticket Location Section
                      _buildLocationSection(
                        'Ticket Location',
                        Icons.location_on,
                        const Color(0xFF19543E),
                        data['ticketLat'],
                        data['ticketLon'],
                        widget.ticket['address'],
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Your Distance to Get In Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF46BBFE).withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF46BBFE).withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF46BBFE),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.directions_walk,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Attendance Status',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF282454),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Builder(
                              builder: (context) {
                                final double distance = data['distance'] ?? 999999.0;
                                if (distance <= 700) {
                                  return Column(
                                    children: [
                                      const Icon(Icons.verified, color: Colors.green, size: 32),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'You are within the ticket area',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Distance: ${distance.toStringAsFixed(0)}m (within 700m radius)',
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  );
                                } else {
                                  return Column(
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.red, size: 32),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'You are not within the ticket area',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Distance: ${distance.toStringAsFixed(0)}m (must be within 700m radius to check-in)',
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontSize: 14,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      
                      // Warning if using default location
                      if (data['usingDefault'] == true) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange[700],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                      child: Text(
                                  'Ticket location not set. Using default location (Cyberjaya).',
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                      ),
                    ),
                ],
              ),
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      
                      // Close Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF282454),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Close',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                ),
              ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLocationSection(String title, IconData icon, Color color, double? lat, double? lon, String? address) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF282454),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (address != null && address.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.home,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    address,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: _buildCoordinateRow('Latitude', lat),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCoordinateRow('Longitude', lon),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateRow(String label, double? value) {
    String displayValue = (value is double)
        ? value.toStringAsFixed(6)
        : (value?.toString() ?? 'N/A');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.grey.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Text(
            displayValue,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF282454),
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }

  String _formatDistance(double distance) {
    if (distance >= 1000) {
      return '${(distance / 1000).toStringAsFixed(2)} km';
    } else {
      return '${distance.toStringAsFixed(1)} m';
    }
  }

  DateTime _parseDateOnly(String value) {
    try {
      return DateFormat('dd/MM/yyyy HH:mm:ss').parse(value);
    } catch (_) {
      try {
        return DateFormat('dd/MM/yyyy').parse(value);
      } catch (_) {
        try {
        return DateFormat('yyyy-MM-dd HH:mm:ss').parse(value);
        } catch (_) {
          return DateTime.parse(value);
        }
      }
    }
  }

  Future<Map<String, dynamic>> _getLocationAndDistance() async {
    double? ticketLat;
    double? ticketLon;
    try {
      ticketLat = double.tryParse(widget.ticket['latitude']?.toString() ?? '');
      ticketLon = double.tryParse(widget.ticket['longitude']?.toString() ?? '');
      debugPrint('DEBUG: widget.ticket[latitude]=${widget.ticket['latitude']}');
      debugPrint('DEBUG: widget.ticket[longitude]=${widget.ticket['longitude']}');
      debugPrint('DEBUG: ticketLat=$ticketLat, ticketLon=$ticketLon');
    } catch (e) {
      debugPrint('ERROR parsing lat/lon: $e');
      throw Exception('Ralat parsing koordinat ticket: $e');
    }
    final String address = odooStr(widget.ticket['address']);

    // Jika tiada koordinat dan tiada alamat, hentikan cepat supaya UI responsif.
    if ((ticketLat == null || ticketLon == null || ticketLat == 0.0 || ticketLon == 0.0) &&
        (address == null || address.isEmpty)) {
      throw Exception('Lokasi ticket tidak set. Sila kemaskini alamat/koordinat di Odoo.');
    }
    // Jika koordinat null, cuba geocode alamat
    if (ticketLat == null || ticketLon == null || ticketLat == 0.0 || ticketLon == 0.0) {
      if (address != null && address.isNotEmpty) {
        debugPrint('DEBUG: Mencuba geocode alamat: $address');
        try {
          // Guna Google Maps Geocoding API secara langsung
          String apiKey = 'AIzaSyDZ-xCpbuA7lEBEkA-TZjg1SZgDugcOseY';
          String encodedAddress = Uri.encodeComponent(address);
          String url = 'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=$apiKey';
          
          final response = await http.get(Uri.parse(url));
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['status'] == 'OK' && data['results'].isNotEmpty) {
              var location = data['results'][0]['geometry']['location'];
              ticketLat = location['lat'].toDouble();
              ticketLon = location['lng'].toDouble();
              debugPrint('DEBUG: Geocoding berjaya: $ticketLat, $ticketLon');
            }
          }
        } catch (e) {
          debugPrint('DEBUG: Geocoding gagal: $e');
        }
      }
      
      // Jika masih null, throw error
      if (ticketLat == null || ticketLon == null || ticketLat == 0.0 || ticketLon == 0.0) {
        debugPrint('ERROR: Koordinat ticket tidak sah!');
        throw Exception('Lokasi ticket tidak sah. Sila semak data di Odoo.');
      }
    }

    Position position = await determinePosition();

    double straightLineDistance = Geolocator.distanceBetween(
        ticketLat, ticketLon, position.latitude, position.longitude);

    return {
      'userLat': position.latitude,
      'userLon': position.longitude,
      'ticketLat': ticketLat,
      'ticketLon': ticketLon,
      'distance': straightLineDistance,
    };
  }

  Widget _buildCheckInButton() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF282454), // Warna biru gelap
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: () async {
        // Check distance before allowing check-in
        try {
          final locationData = await _getLocationAndDistance();
          double distance = locationData['distance'];
          
          if (distance <= 700) {
            // User dalam 700m radius, boleh check-in
            _handleCheckIn();
          } else {
            // User luar 700m radius, paparkan alert
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Invalid Location'),
                content: Text(
                  'You are ${distance.toStringAsFixed(0)}m away from the ticket location. '
                  'You must be within a 700m radius to check in.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showLocationDialog();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        } catch (e) {
          // Error getting location, paparkan alert
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Location Error'),
              content: Text('Unable to get location: $e'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      },
      child: const Text(
        'Check In',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );
}

Widget _buildCheckInWithoutGeoButton() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF46BBFE),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: _handleCheckInWithoutGeo,
      child: const Text(
        'Check In With Geo',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );
}

Widget _buildUpdateProgressButton() {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF19543E), // Warna hijau gelap
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: () async {
        await _updateTicketProgress(); // ✅ Simpan semua progress ke SharedPreferences
        _navigateToChecklist(context); // ✅ Buka halaman "Ticket Progress"
      },
      child: const Text(
        'Update Ticket Progress',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );
}

Widget _buildCheckInOrUpdateButton() {
  if (widget.ticket['stage_name'].toString().toLowerCase().contains('closed')) {
    return Column(
      children: [
        _buildFeedbackActionButtons(),
        const SizedBox(height: 16),
      ],
    );
  }

  return Column(
    children: [
      if (!isCheckedIn) ...[
        _buildCheckInButton(),
        _buildCheckInWithoutGeoButton(),
      ],
      if (isCheckedIn && !isCheckoutComplete) _buildUpdateProgressButton(),
      if (isCheckoutComplete && !widget.ticket['stage_name'].toString().toLowerCase().contains('closed'))
        _buildCloseTicketButton(widget.ticket['id']),
      _buildFeedbackActionButtons(),
      const SizedBox(height: 16),
    ],
  );
}

Widget _buildFeedbackActionButtons() {
  return Column(
    children: [
      _buildFeedbackNavButton(
        label: 'Feedback',
        backgroundColor: const Color(0xFF46BBFE),
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FeedbackScreen(
                ticketId: widget.ticket['id'].toString(),
              ),
            ),
          );

          if (result == true) {
            await Future.delayed(const Duration(milliseconds: 300));
            await _refreshTicketFromOdoo();
            widget.onTicketUpdated?.call();
            if (mounted) setState(() {});
          }
        },
      ),
      _buildFeedbackNavButton(
        label: 'Total Feedback',
        backgroundColor: const Color(0xFF19543E),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TotalFeedbackScreen(
                ticketId: widget.ticket['id'],
              ),
            ),
          );
        },
      ),
    ],
  );
}

Widget _buildFeedbackNavButton({
  required String label,
  required Color backgroundColor,
  required VoidCallback onPressed,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: onPressed,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );
}






Widget _buildCloseTicketButton(int ticketId) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.red,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Close Ticket?'),
            content: const Text('Are you sure you want to mark this ticket as closed? This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Close Ticket'),
              ),
            ],
          ),
        );

        if (confirm == true) {
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      _showLoadingDialog('Closing ticket...');
          bool success = await widget.odooService.markTicketAsClosed(ticketId);
      if (mounted) {
        rootNavigator.pop();
      }
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ Ticket closed successfully'), backgroundColor: Colors.green),
            );
            Navigator.pop(context, {'closed': true}); // ✅ KEMASKINI
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.odooService.lastErrorMessage ?? '❌ Failed to close ticket'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
      child: const Text(
        'Close Ticket',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ),
  );
}



Future<void> _updateTicketProgress() async {
  debugPrint("🔄 Updating ticket progress for Ticket ID: ${widget.ticket['id']}");
  SharedPreferences prefs = await SharedPreferences.getInstance();
  int ticketId = widget.ticket['id'];

  // Ambil progress lama
  List<String> oldProgressList = prefs.getStringList('progressSteps_$ticketId') ?? [];
  List<ProgressStep> oldSteps = oldProgressList.map((json) {
    Map<String, dynamic> data = jsonDecode(json);
    return ProgressStep(
      title: odooStr(data['title'], 'Step'),
      timestamp: data['timestamp'] != null ? DateTime.parse(data['timestamp']) : null,
      isCompleted: data['isCompleted'] ?? false,
       icon: getIconByName(data['iconName']),
      description: data['description'],
      attachedFiles: data['attachedFiles'] != null
        ? (data['attachedFiles'] as List).map((f) {
            final decodedBytes = base64Decode(f['bytes']);
            return PlatformFile.fromMap({
              'name': f['name'],
              'bytes': decodedBytes,
              'size': decodedBytes.length,
              'extension': f['extension'],
            });
          }).toList()
        : null,
    );
  }).toList();



  // Gabungkan progress baru & lama, elakkan duplicate
  List<ProgressStep> allSteps = [...oldSteps];

  for (var newStep in ticket.progressSteps) {
    final bool exists;
    if (newStep.title == 'Resolution' || newStep.title == 'Follow Up Added') {
      exists = allSteps.any((step) =>
          step.title == newStep.title &&
          (step.description ?? '').trim() ==
              (newStep.description ?? '').trim());
    } else {
      exists = allSteps.any((step) =>
          step.title == newStep.title &&
          step.timestamp?.toIso8601String() ==
              newStep.timestamp?.toIso8601String());
    }
    if (!exists) {
      allSteps.add(newStep);
    }
  }

  // Encode untuk simpan
  List<String> encoded = allSteps.map((step) {
    return jsonEncode({
      "title": step.title,
      "timestamp": step.timestamp?.toIso8601String(),
      "isCompleted": step.isCompleted,
      "iconName": _iconName(step.icon),
      "description": step.description ?? "",
      "attachedFiles": step.attachedFiles?.map((f) => {
        "name": f.name,
        "bytes": base64Encode(f.bytes!),
        "extension": f.extension,
      }).toList(),
    });
  }).toList();

  // Simpan dalam SharedPreferences
  await prefs.setStringList('progressSteps_$ticketId', encoded);

  setState(() {
    ticket.progressSteps = allSteps;
  });

  debugPrint("✅ Updated ${allSteps.length} progress steps for Ticket ID: $ticketId");
}





void _handleCheckIn() => _performCheckIn(autoResolutionAfterCheckIn: false);

void _handleCheckInWithoutGeo() => _performCheckIn(autoResolutionAfterCheckIn: true);

Future<void> _performCheckIn({required bool autoResolutionAfterCheckIn}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Check-In'),
      content: Text(
        autoResolutionAfterCheckIn
            ? 'Check in without location verification and auto-add ticket problem as resolution?'
            : 'Are you sure you want to check in for this ticket?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
      ],
    ),
  );

  if (confirm != true) return;

  final checkInTime = DateTime.now();
  final formattedCheckIn = OdooService.formatOdooApiDateTime(checkInTime);
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  _showLoadingDialog('Submitting check-in...');
  final success = await widget.odooService.submitCheckIn(
    widget.ticket['id'],
    formattedCheckIn,
  );
  if (mounted) {
    rootNavigator.pop();
  }

  if (!success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.odooService.lastErrorMessage ?? 'Failed to submit check-in',
        ),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }

  await _saveCheckInStatus(checkInTime);

  final prefs = await SharedPreferences.getInstance();
  final ticketId = widget.ticket['id'] as int;
  await prefs.setBool(
    'auto_resolution_after_checkin_$ticketId',
    autoResolutionAfterCheckIn,
  );

  final probName = (widget.ticket['prob_name']?.toString() ?? '').trim();

  setState(() {
    isCheckedIn = true;
    widget.ticket['check_in'] =
        DateFormat('dd/MM/yyyy HH:mm:ss').format(checkInTime);
    ticket.checkInTime = checkInTime;
    ticket.progressSteps.add(
      ProgressStep(
        title: 'Technician Check In',
        timestamp: checkInTime,
        isCompleted: true,
        icon: Icons.login,
      ),
    );

    if (autoResolutionAfterCheckIn && probName.isNotEmpty) {
      ticket.progressSteps.add(
        ProgressStep(
          title: 'Resolution',
          timestamp: checkInTime.add(const Duration(minutes: 1)),
          isCompleted: true,
          icon: Icons.build_circle_outlined,
          description: probName,
          resolution: probName,
        ),
      );
    }
  });

  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Check-in submitted successfully')),
  );

  _navigateToChecklist(
    context,
    checkInTime: checkInTime,
    autoResolutionAfterCheckIn: autoResolutionAfterCheckIn,
  );
}

void _navigateToChecklist(
  BuildContext context, {
  DateTime? checkInTime,
  bool autoResolutionAfterCheckIn = false,
}) async {
  debugPrint("🔄 Navigating to ChecklistPage for Ticket ID: ${widget.ticket['id']}");
  await _updateTicketProgress();

  if (!autoResolutionAfterCheckIn) {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    int ticketId = widget.ticket['id'];
    List<String>? savedProgressList =
        prefs.getStringList('progressSteps_$ticketId');

    if (savedProgressList != null) {
      setState(() {
        ticket.progressSteps = savedProgressList.map((progressJson) {
          Map<String, dynamic> progressData = jsonDecode(progressJson);

          List<PlatformFile>? attachedFiles;
          if (progressData['attachedFiles'] != null) {
            attachedFiles = (progressData['attachedFiles'] as List).map((f) {
              final decodedBytes = base64Decode(f['bytes']);
              return PlatformFile.fromMap({
                'name': f['name'],
                'bytes': decodedBytes,
                'size': decodedBytes.length,
                'extension': f['extension'],
              });
            }).toList();
          }

          return ProgressStep(
            title: progressData['title'],
            timestamp: progressData['timestamp'] != null
                ? DateTime.parse(progressData['timestamp'])
                : null,
            isCompleted: progressData['isCompleted'] ?? false,
            icon: getIconByName(progressData['iconName']),
            description: progressData['description'],
            attachedFiles: attachedFiles,
          );
        }).toList();
      });
    }
  }

  final result = await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ChecklistPage(
        initialCheckInTime: checkInTime ?? ticket.checkInTime,
        isDarkMode: widget.isDarkMode,
        odooService: widget.odooService,
        ticket: ticket,
        autoResolutionAfterCheckIn: autoResolutionAfterCheckIn,
      ),
    ),
  );

  if (result != null && result is Map && result['closed'] == true) {
    setState(() {
      widget.ticket['stage_name'] = 'Closed';
      isCheckoutComplete = true;
    });

    await _refreshTicketFromOdoo(); // ⬅️ WAJIB refresh selepas ticket closed
  }
}




Future<void> _saveProgressToSharedPreferences(Ticket updatedTicket) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  int ticketId = updatedTicket.id;

  List<String> progressList = updatedTicket.progressSteps.map((step) {
    return jsonEncode({
      "title": step.title,
      "timestamp": step.timestamp?.toIso8601String(),
      "isCompleted": step.isCompleted,
      "iconName": _iconName(step.icon),
      "description": step.description ?? "",
    });
  }).toList();

  await prefs.setStringList('progressSteps_$ticketId', progressList);
  debugPrint("✅ Saved progress to SharedPreferences for Ticket ID: $ticketId");
}

List<Widget> _buildDetailsList() {
  final details = {
    'CUSTOMER': {'value': widget.ticket['partner_name'], 'icon': Icons.person},
    'EMAIL': {'value': widget.ticket['partner_email'], 'icon': Icons.email},
    'EQUIPMENT SERIAL NUMBER': {'value': widget.ticket['serial_name'], 'icon': Icons.qr_code},
    'EQUIPMENT USER': {'value': widget.ticket['equipment_user'], 'icon': Icons.person_outline},
    'REPORTED BY': {'value': widget.ticket['person_name'], 'icon': Icons.report},
    'CONTACT NUMBER': {'value': widget.ticket['partner_phone'], 'icon': Icons.phone},
    'DEPARTMENT': {'value': widget.ticket['department'], 'icon': Icons.business},
    'ADDRESS': {'value': widget.ticket['address'], 'icon': Icons.location_on},
    'CATEGORY': {'value': widget.ticket['category_name'], 'icon': Icons.category},
    'SUB-CATEGORY': {'value': widget.ticket['sub_name'], 'icon': Icons.subdirectory_arrow_right},
    'PROBLEM': {'value': widget.ticket['prob_name'], 'icon': Icons.build},
  };

  return details.entries.map((entry) {
    bool isLastItem = entry.key == 'PROBLEM';
    final value = entry.value['value'];
    String displayValue = '';
    
    if (value != null && value != false && value.toString().trim().isNotEmpty && value.toString().toLowerCase() != 'false') {
      displayValue = value.toString();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(entry.value['icon'], color: widget.isDarkMode ? Colors.white : const Color(0xFF282454), size: 18),
            const SizedBox(width: 6),
            Text(
              entry.key,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: widget.isDarkMode ? Colors.white : const Color(0xFF282454),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 24),
          child: Text(
            displayValue,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: widget.isDarkMode ? Colors.white : const Color(0xFF800000),
            ),
          ),
        ),
        if (!isLastItem) const Divider(),
      ],
    );
  }).toList();
}


  Widget _buildStatusBadge(dynamic status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStageColor(status),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _getStageLabel(odooStr(status, 'Unknown')),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }


Future<void> _loadProgressFromSharedPreferences() async {
  debugPrint("🔄 Loading progress from SharedPreferences for Ticket ID: ${widget.ticket['id']}");
  SharedPreferences prefs = await SharedPreferences.getInstance();
  int ticketId = widget.ticket['id'];

  List<String>? savedProgressList = prefs.getStringList('progressSteps_$ticketId');

  if (savedProgressList != null) {
    setState(() {
      ticket.progressSteps = savedProgressList.map((progressJson) {
        Map<String, dynamic> progressData = jsonDecode(progressJson);

        // ✅ Decode attachedFiles dari Base64 (jika ada)
        List<PlatformFile>? attachedFiles;
        if (progressData['attachedFiles'] != null) {
          attachedFiles = (progressData['attachedFiles'] as List).map((f) {
  final decodedBytes = base64Decode(f['bytes']);
  return PlatformFile.fromMap({
    'name': f['name'],
    'bytes': decodedBytes,
    'size': decodedBytes.length,
  });
}).toList();

        }

        return ProgressStep(
          title: progressData['title'],
          timestamp: progressData['timestamp'] != null
              ? DateTime.parse(progressData['timestamp'])
              : null,
          isCompleted: progressData['isCompleted'] ?? false,
          icon: getIconByName(progressData['iconName']),
          description: progressData['description'],
          attachedFiles: attachedFiles, // ✅ Masukkan fail di sini
        );
      }).toList();
    });

    // ✅ Check-in
    if (!ticket.progressSteps.any((step) => step.title == "Technician Check In")) {
      String? savedCheckIn = prefs.getString('checkInTime_$ticketId');
      if (savedCheckIn != null) {
        setState(() {
          ticket.progressSteps.insert(
            0,
            ProgressStep(
              title: 'Technician Check In',
              timestamp: _parseDateOnly(savedCheckIn),
              isCompleted: true,
              icon: Icons.login,
            ),
          );
        });
      }
    }

    // ✅ Check-out
    if (!ticket.progressSteps.any((step) => step.title == "Technician Check Out")) {
      String? savedCheckOut = prefs.getString('checkOutTime_$ticketId');
      if (savedCheckOut != null) {
        setState(() {
          ticket.progressSteps.add(
            ProgressStep(
              title: 'Technician Check Out',
              timestamp: _parseDateOnly(savedCheckOut),
              isCompleted: true,
              icon: Icons.logout,
            ),
          );
        });
      }
    }

    // ✅ Close Comment
    String? savedCloseComment = prefs.getString('closeComment_$ticketId');
    if (savedCloseComment != null && savedCloseComment.isNotEmpty &&
        !ticket.progressSteps.any((step) => step.title == "Close Comment")) {
      setState(() {
        ticket.progressSteps.add(
          ProgressStep(
            title: "Close Comment",
            timestamp: DateTime.now(),
            isCompleted: true,
            icon: Icons.comment,
            description: savedCloseComment,
          ),
        );
      });
    }

    debugPrint("✅ Loaded ${ticket.progressSteps.length} progress steps from SharedPreferences");
  } else {
    debugPrint("⚠️ No progress found in SharedPreferences");
  }
}



  Widget _buildPriorityBadge(dynamic priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getPriorityColor(priority),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _getPriorityLabel(priority),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStageColor(dynamic stage) {
    final s = odooStr(stage);
    if (s.isEmpty) return Colors.grey;
    final stageLower = s.toLowerCase();
    if (stageLower.contains('closed')) return Colors.grey;
    if (stageLower.contains('open')) return const Color(0xFF46BBFE);
    return const Color(0xFF282454);
  }

  String _getStageLabel(dynamic stage) {
    final s = odooStr(stage, 'Unknown');
    if (s.toLowerCase().contains('staff closed')) return 'Closed';
    return s;
  }

  Color _getPriorityColor(dynamic priority) {
    switch (priority?.toString()) {
      case '3':
        return const Color(0xFF800000);
      case '2':
        return const Color(0xFFFF6B00);
      case '1':
      case '0':
        return const Color(0xFF2E7D32);
      default:
        return Colors.grey;
    }
  }

  String _getPriorityLabel(dynamic priority) {
    switch (priority?.toString()) {
      case '3':
        return 'URGENT';
      case '2':
        return 'HIGH';
      case '1':
      case '0':
        return 'LOW';
      default:
        return 'NORMAL';
    }
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color,
      {double iconSize = 24, double textSize = 16}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: iconSize, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: textSize - 4,
                    color: widget.isDarkMode ? Colors.white70 : Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: textSize - 2,
                    fontWeight: FontWeight.w500,
                    color: widget.isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressStep(ProgressStep step, Ticket ticket) {
    debugPrint("🛠️ Step Title: ${step.title}");
    debugPrint("🛠️ Attached Files Count: ${step.attachedFiles?.length ?? 0}");
    String formattedDate = DateFormat('dd/MM/yyyy').format(step.timestamp!);
    String formattedTime = DateFormat('HH:mm:ss').format(step.timestamp!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: step.title == "Description Added"
                    ? Colors.orangeAccent
                    : const Color(0xFF19543E),
                shape: BoxShape.circle,
              ),
              child: Icon(
                step.icon,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 12, color: Color(0xFF003366)),
                      const SizedBox(width: 4),
                      Text(
                        formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.access_time, size: 12, color: Color(0xFF003366)),
                      const SizedBox(width: 4),
                      Text(
                        formattedTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  if (step.description != null && step.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5.0),
                      child: Text(
                        step.description!,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // ✅ Jika ada fail dilampirkan, papar dalam senarai
        if (step.attachedFiles != null && step.attachedFiles!.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Attached Files:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              ...step.attachedFiles!.map((file) {
                return GestureDetector(
                  onTap: () => _showFileDetails(file),
                  child: ListTile(
                    leading: const Icon(Icons.attach_file, color: Color(0xFF19543E)),
                    title: Text(
                      file.name,
                      style: const TextStyle(fontSize: 12, color: Colors.black),
                    ),
                  ),
                );
              }).toList(),
            ],
          ),
      ],
    );
  }

  void _showFileDetails(PlatformFile file) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(file.name),
          content: file.extension != null
              ? (_isImage(file.extension!)
                  ? Image.file(
                      File(file.path!), // Display image preview
                      fit: BoxFit.cover,
                    )
                  : (file.extension!.toLowerCase() == 'pdf' && file.path != null
                      ? ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // Close the dialog
                            _viewPdf(file.path!); // Open PDF viewer
                          },
                          child: const Text('Open PDF'),
                        )
                      : Text(
                          'File Path: ${file.path ?? "Unavailable"}',
                          style: const TextStyle(fontSize: 16),
                        )))
              : const Text('Unsupported file format.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  bool _isImage(String extension) {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return imageExtensions.contains(extension.toLowerCase());
  }

  void _viewPdf(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerPage(filePath: path),
      ),
    );
  }

  void _showAddDescriptionDialog(Ticket ticket) {
    final TextEditingController descriptionController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add Follow Up'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add a new follow-up to this ticket. The follow-up will be appended to the existing description with a timestamp.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Enter Follow Up',
                  hintText: 'Enter your follow-up details here...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (descriptionController.text.isNotEmpty) {
                  bool success = await widget.odooService.submitDescription(
                    ticket.id,
                    descriptionController.text,
                  );

                  if (success) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("✅ Follow-up added successfully!"),
                        backgroundColor: Colors.green,
                      ),
                    );
                    
                    // Refresh the ticket details to show the new follow-up
                    setState(() {
                      _refreshTicketDescription(ticket.id);
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("❌ Failed to add follow-up."),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("⚠️ Please enter a follow-up!"),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _insertUserProgress(ProgressStep step) {
    setState(() {
      // Cari index Check Out, kalau ada
      int checkOutIndex = ticket.progressSteps.indexWhere((s) => s.title == "Technician Check Out");

      // Cari index Check In (wajib ada)
      int checkInIndex = ticket.progressSteps.indexWhere((s) => s.title == "Technician Check In");

      // Cari index Close Ticket (jika sudah ada)
      int closeTicketIndex = ticket.progressSteps.indexWhere((s) => s.title == "Ticket Closed");

      // Insert selepas Check In dan sebelum Technician Check Out atau Close Ticket
      int insertIndex = ticket.progressSteps.length;

      if (checkOutIndex != -1) {
        insertIndex = checkOutIndex;
      } else if (closeTicketIndex != -1) {
        insertIndex = closeTicketIndex;
      }

      if (checkInIndex != -1 && insertIndex <= checkInIndex) {
        insertIndex = checkInIndex + 1;
      }

      ticket.progressSteps.insert(insertIndex, step);
    });
  }

  Future<void> _refreshTicketDescription(int ticketId) async {
    debugPrint("🔄 Fetching updated description for Ticket ID: $ticketId...");

    Map<String, dynamic>? ticketData = await widget.odooService.getTicketDetails(ticketId);
    if (ticketData != null && ticketData.containsKey('description')) {
      setState(() {
        // Update the ticket description in the UI
        if (widget.ticket is Map<String, dynamic>) {
          (widget.ticket as Map<String, dynamic>)['description'] = ticketData['description'];
        }
      });

      debugPrint("✅ Updated description from Odoo: ${ticketData['description']}");
    } else {
      debugPrint("⚠️ No updated description found in Odoo.");
    }
  }

}

Future<double?> getDrivingDistance(double startLat, double startLng, double endLat, double endLng) async {
  // Use the provided Google Maps API key
  const apiKey = 'AIzaSyDZ-xCpbuA7lEBEkA-TZjg1SZgDugcOseY';
  
  try {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=$startLat,$startLng&destination=$endLat,$endLng&key=$apiKey');

    final response = await http.get(url).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      
      // Check if API returned an error
      if (data['status'] == 'OK' && data['routes'] != null && data['routes'].isNotEmpty) {
        final distanceMeters = data['routes'][0]['legs'][0]['distance']['value'];
        return distanceMeters.toDouble(); // Return in meters
      } else {
        print('Google Directions API Error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
        return null;
      }
    } else {
      print('HTTP Error: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    print('Error getting driving distance: $e');
    return null;
  }
}

