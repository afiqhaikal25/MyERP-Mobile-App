import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'flutter_pdfview.dart';
import '../odoo_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

class Ticket {
  String title;
  bool isCompleted;
  DateTime? checkInTime;
  List<ProgressStep> progressSteps;
  int id; // Tambahkan ID tiket
  bool isCheckedOut; // Add this field
  String? closeComment; // ✅ Tambah field closeComment
  String? description; // ✅ Tambah field description
  String? stageName; // Add stageName field
  
  Ticket({
    required this.title,
    required this.id, // Wajib ada ID tiket
    this.isCompleted = false,
    this.checkInTime,
    required this.progressSteps,
    this.isCheckedOut = false, // Initialize the field
    this.closeComment, // ✅ Tambahkan ini
    this.stageName, // Add stageName parameter
  });

  @override
  String toString() {
    return 'Ticket(title: $title, isCompleted: $isCompleted, progressSteps: $progressSteps)';
  }
  
}

class ProgressStep {
  String title;
  DateTime? timestamp;
  bool isCompleted;
  IconData? icon;
  List<PlatformFile>? attachedFiles;
  String? resolution; // New field
  String? followUp; // New field
  String? description; // New field

  ProgressStep({
    required this.title,
    this.timestamp,
    this.isCompleted = false,
    required this.icon,
    this.attachedFiles,
    this.resolution, // Initialize
    this.followUp, // Initialize
    this.description, // Initialize
  });
}

class ChecklistPage extends StatefulWidget {
  final DateTime? initialCheckInTime;
  final bool isDarkMode;
  final Ticket ticket;
  final OdooService odooService; // ✅ Tambahkan ini

  const ChecklistPage({
    Key? key,
    this.initialCheckInTime,
    required this.isDarkMode,
    required this.ticket,
    required this.odooService, // ✅ Pastikan ini diberikan dari parent widget
  }) : super(key: key);
  

  @override
  ChecklistPageState createState() => ChecklistPageState();
}

class ChecklistPageState extends State<ChecklistPage> {
  bool isTicketSubmitted = false;
  bool isCheckoutComplete = false;
  bool isCloseCommentAdded = false;
  bool isFileAttached = false;

  final TextEditingController _commentController = TextEditingController();
  List<Ticket> tickets = [];

@override
void initState() {
  super.initState();

  tickets = [
    Ticket(
      title: 'Ticket Progress',
      id: widget.ticket.id,
      isCompleted: widget.ticket.isCompleted,
      checkInTime: widget.ticket.checkInTime,
      isCheckedOut: widget.ticket.isCheckedOut,
      closeComment: widget.ticket.closeComment,
      stageName: widget.ticket.stageName,
      progressSteps: List.from(widget.ticket.progressSteps),
    ),
  ];

  _loadDescription(widget.ticket.id);
  _loadCloseComment(widget.ticket.id);
  _loadCheckoutStatus();

  // ✅ Force update widget.ticket state after loading checkout status
  Future.delayed(const Duration(milliseconds: 300), () {
    if (widget.ticket.isCheckedOut != tickets[0].isCheckedOut) {
      setState(() {
        widget.ticket.isCheckedOut = tickets[0].isCheckedOut;
      });
    }
  });

  _loadProgressStepsFromOdoo(widget.ticket.id);
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


Future<void> _loadCloseComment(int ticketId) async {
  debugPrint("🔍 Loading Close Comment for Ticket ID: $ticketId");

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedComment = prefs.getString('closeComment_$ticketId');

  // 🔹 Semak jika sudah ada Close Comment dalam progressSteps
  bool alreadyExists = tickets[0].progressSteps.any((step) => step.title == "Resolution");

  if (savedComment != null && savedComment.isNotEmpty && !alreadyExists) {
    setState(() {
      widget.ticket.closeComment = savedComment;
      tickets[0].progressSteps.add(
        ProgressStep(
          title: "Resolution",
          timestamp: DateTime.now(),
          isCompleted: true,
          icon: Icons.comment,
          description: savedComment,
        ),
      );
    });
    debugPrint("✅ Loaded Close Comment from SharedPreferences: $savedComment");
  } else {
    debugPrint("⚠️ No saved Close Comment in SharedPreferences, fetching from Odoo...");

    Map<String, dynamic>? ticketData = await widget.odooService.getTicketDetails(ticketId);
    if (ticketData != null && ticketData.containsKey('close_comment')) {
      var closeCommentData = ticketData['close_comment'];
      String fetchedComment = '';
      
      // Handle different types of close_comment data
      if (closeCommentData is String && closeCommentData.isNotEmpty) {
        fetchedComment = closeCommentData;
      } else if (closeCommentData is bool) {
        // If it's a boolean false, treat it as no comment
        fetchedComment = '';
      }

      if (fetchedComment.isNotEmpty && !alreadyExists) {
        setState(() {
          widget.ticket.closeComment = fetchedComment;
          tickets[0].progressSteps.add(
            ProgressStep(
              title: "Close Comment",
              timestamp: DateTime.now(),
              isCompleted: true,
              icon: Icons.comment,
              description: fetchedComment,
            ),
          );
        });
        await prefs.setString('closeComment_$ticketId', fetchedComment);
        debugPrint("✅ Fetched Close Comment from Odoo & saved: $fetchedComment");
      }
    }
  }
}

Future<void> _updateTicketProgress() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  int ticketId = widget.ticket.id;

  List<String> oldProgressList = prefs.getStringList('progressSteps_$ticketId') ?? [];
  List<ProgressStep> oldSteps = oldProgressList.map((json) {
    Map<String, dynamic> data = jsonDecode(json);
    return ProgressStep(
      title: data['title'],
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

  // Gabungkan progress lama + baru, elak duplikasi
  List<ProgressStep> allSteps = [...oldSteps];

for (var newStep in widget.ticket.progressSteps) {
  int existingIndex;

  // Untuk Follow Up & Resolution, hanya semak berdasarkan title
  if (newStep.title == "Follow Up Added" || newStep.title == "Resolution") {
    existingIndex = allSteps.indexWhere((step) => step.title == newStep.title);
  } else {
    existingIndex = allSteps.indexWhere((step) =>
      step.title == newStep.title &&
      step.timestamp?.toIso8601String() == newStep.timestamp?.toIso8601String()
    );
  }

  if (existingIndex != -1) {
    allSteps[existingIndex] = newStep;
  } else {
    allSteps.add(newStep);
  }
}



  // ✅ Tambah Follow Up kalau description wujud & belum wujud dalam progress
// ✅ Semak jika ada progress "Follow Up Added"
int followUpIndex = allSteps.indexWhere((step) => step.title == "Follow Up Added");

if (widget.ticket.description != null && widget.ticket.description!.isNotEmpty) {
  if (followUpIndex != -1) {
    // ✅ Kemas kini step sedia ada
    allSteps[followUpIndex] = ProgressStep(
      title: "Follow Up Added",
      timestamp: DateTime.now(),
      isCompleted: true,
      icon: Icons.description,
      description: widget.ticket.description!,
    );
  } else {
    // ✅ Tambah baru jika belum ada
    allSteps.add(
      ProgressStep(
        title: "Follow Up Added",
        timestamp: DateTime.now(),
        isCompleted: true,
        icon: Icons.description,
        description: widget.ticket.description!,
      ),
    );
  }
}


  // Simpan semula ke SharedPreferences
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

  await prefs.setStringList('progressSteps_$ticketId', encoded);

  setState(() {
    widget.ticket.progressSteps = allSteps;
  });

  debugPrint("✅ Updated ${allSteps.length} progress steps for Ticket ID: $ticketId");
}



Future<void> _saveCloseComment(int ticketId) async {
  debugPrint("🚀 Saving Close Comment for Ticket ID: $ticketId");

  String closeComment = _commentController.text.trim();
  if (closeComment.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⚠️ Close Comment cannot be empty!"), backgroundColor: Colors.orange),
    );
    return;
  }

  bool success = await widget.odooService.submitCloseComment(ticketId, closeComment);

  if (success) {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('closeComment_$ticketId', closeComment);

    DateTime now = DateTime.now(); // Get the current timestamp
    setState(() {
      widget.ticket.closeComment = closeComment;
      tickets[0].progressSteps.add(
        ProgressStep(
          title: "Close Comment",
          timestamp: now, // Save the timestamp
          isCompleted: true,
          icon: Icons.comment,
          description: closeComment,
        ),
      );
    });

    await _saveProgressToSharedPreferences(ticketId);

    debugPrint("✅ Close Comment saved & added to progressSteps!");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Close Comment saved successfully!"), backgroundColor: Colors.green),
    );
  } else {
    debugPrint("❌ Failed to save Close Comment for Ticket ID: $ticketId");
  }
}
 
  // Load checkout status from SharedPreferences
void _loadCheckoutStatus() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool? checkedOut = prefs.getBool('isCheckedOut_${widget.ticket.id}');
  String? checkOutTime = prefs.getString('checkOutTime_${widget.ticket.id}');

  if (checkedOut == true && checkOutTime != null) {
    setState(() {
      if (!tickets[0].progressSteps.any((step) => step.title == 'Technician Check Out')) {
        tickets[0].progressSteps.add(
          ProgressStep(
            title: 'Technician Check Out',
            timestamp: _parseDateOnly(checkOutTime),
            isCompleted: true,
            icon: Icons.logout,
          ),
        );
      }

      // ✅ Update status checkout untuk kedua-dua tempat
      tickets[0].isCheckedOut = true;
      widget.ticket.isCheckedOut = true;
      isCheckoutComplete = true;
    });

    debugPrint("✅ Loaded checkout status from SharedPreferences for Ticket ID: ${widget.ticket.id}");
  } else {
    debugPrint("ℹ️ Ticket is not checked out yet.");
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



  // Add the _viewPdf method here
void _viewPdf(String path) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PdfViewerPage(filePath: path),
    ),
  );
}

Future<void> _loadDescription(int ticketId) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedDescription = prefs.getString('description_$ticketId');

  if (savedDescription != null && savedDescription.isNotEmpty) {
    // Strip HTML that may have been stored previously in Odoo description.
    final clean = savedDescription
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    setState(() {
      widget.ticket.description = clean;

      // ❌ Remove existing follow up step first to prevent duplication
      tickets[0].progressSteps.removeWhere((step) => step.title == "Follow Up Added");

      // ✅ Add new updated follow up step
      tickets[0].progressSteps.add(
        ProgressStep(
          title: "Follow Up Added",
          timestamp: DateTime.now(),
          isCompleted: true,
          icon: Icons.description,
          description: clean,
        ),
      );
    });

    debugPrint("✅ Loaded Follow Up from SharedPreferences: $clean");
  } else {
    debugPrint("⚠️ No Follow Up description found in SharedPreferences");
  }
}



@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: widget.isDarkMode ? Colors.black : const Color(0xFFE8E6F3),
    appBar: AppBar(
    elevation: 0,
   backgroundColor: widget.isDarkMode ? Colors.grey[900] : const Color(0xFF282454),
  centerTitle: true,
  title: Text(
    'Ticket ID: ${widget.ticket.id}', // Menggunakan widget.ticket.id dengan betul
    style: const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      color: Colors.white,
      letterSpacing: 0.5,
    ),
  ),
    leading: IconButton(
    icon: const Icon(Icons.arrow_back, color: Colors.white), // 🟢 Sentiasa warna putih
    onPressed: () => Navigator.pop(context),
    ),
),

    body: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            widget.isDarkMode ? 'images/woodb.png' : 'images/wood.png',
            fit: BoxFit.cover,
          ),
        ),
        Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ...tickets.map((ticket) => _buildTicketProgressCard(ticket)).toList(),
                  const SizedBox(height: 16),
                  // Only show the checkout button if the ticket is not checked out
                  if (!tickets[0].isCheckedOut) ...[
                    _buildCheckoutButton(tickets[0].id),
                    const SizedBox(height: 8),
                  ],
                  // Show close ticket button if the ticket is checked out but not closed
                  if (tickets[0].isCheckedOut && !_isTicketClosed() && !(tickets[0].stageName?.toLowerCase().contains('closed') ?? false)) ...[
                    _buildCloseTicketButton(tickets[0].id),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// Helper method to check if the ticket is closed
bool _isTicketClosed() {
  return tickets[0].progressSteps.any((step) => step.title == 'Ticket Closed');
}

Widget _buildTicketProgressCard(Ticket ticket) {
  final cardColor = widget.isDarkMode ? Colors.black : Colors.white;
  final textColor = widget.isDarkMode ? Colors.white : const Color(0xFF282454);
  final subTextColor = widget.isDarkMode ? Colors.white70 : Colors.grey[600];

  return Card(
    elevation: 4,
    color: cardColor,
    margin: const EdgeInsets.symmetric(vertical: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    ticket.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
              ),
              if (!ticket.isCheckedOut)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'Add Description') {
                      _showAddDescriptionDialog(ticket);
                    } else if (value == 'Attach Files') {
                      _uploadFileToTicket(ticket);
                    } else if (value == 'Add Close Comment') {
                      _showAddCloseCommentDialog(ticket);
                    }
                  },
                  icon: Icon(Icons.add_circle, color: widget.isDarkMode ? Colors.white : const Color(0xFF19543E)),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'Add Description',
                      child: Text('Add Follow Up'),
                    ),
                    const PopupMenuItem(
                      value: 'Attach Files',
                      child: Text('Attach Files'),
                    ),
                    const PopupMenuItem(
                      value: 'Add Close Comment',
                      child: Text('Add Resolution'),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ticket.progressSteps.length,
            itemBuilder: (context, index) {
              final sortedSteps = [...ticket.progressSteps]..sort((a, b) => a.timestamp!.compareTo(b.timestamp!));
              return _buildProgressStep(sortedSteps[index], ticket, textColor, subTextColor);
            },
          ),
        ],
      ),
    ),
  );
}


void _showAddCloseCommentDialog(Ticket ticket) {
  final TextEditingController closeCommentController = TextEditingController();

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Add Resolution'),
        content: TextField(
          controller: closeCommentController,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Enter Resolution'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (closeCommentController.text.isNotEmpty) {
                // Resolution in this app is stored in `close_comment` (see _loadCloseComment()).
                bool success = await widget.odooService.submitCloseComment(ticket.id, closeCommentController.text);

                if (success) {
                  setState(() {
                    ticket.progressSteps.add(
                      ProgressStep(
                        title: "Resolution",
                        timestamp: DateTime.now(),
                        isCompleted: true,
                        icon: Icons.comment,
                        description: closeCommentController.text,
                      ),
                    );
                  });
                   //await _updateTicketProgress();

                  Navigator.of(context).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("✅ Resolution added successfully!"),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("❌ Failed to add Resolution."),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("⚠️ Please enter a Resolution!"),
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

void _showAddDescriptionDialog(Ticket ticket) {
  final TextEditingController descriptionController = TextEditingController();

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Add Follow Up'),
        content: TextField(
          controller: descriptionController,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Enter Follow Up'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (descriptionController.text.isNotEmpty) {
                final clean = descriptionController.text
                    .replaceAll(RegExp(r'<[^>]*>'), '')
                    .replaceAll('&nbsp;', ' ')
                    .replaceAll('&amp;', '&')
                    .replaceAll('&lt;', '<')
                    .replaceAll('&gt;', '>')
                    .replaceAll('&quot;', '"')
                    .replaceAll('&#39;', "'")
                    .replaceAll(RegExp(r'\s+'), ' ')
                    .trim();
                if (clean.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("⚠️ Please enter a description!"),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                bool success = await widget.odooService.submitDescription(
                  ticket.id,
                  clean,
                );

                if (success) {
                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  await prefs.setString('description_${ticket.id}', clean);

                  final newStep = ProgressStep(
                    title: "Follow Up Added",
                    timestamp: DateTime.now(),
                    isCompleted: true,
                    icon: Icons.description,
                    description: clean,
                  );

                  setState(() {
                    widget.ticket.progressSteps.add(newStep);
                    tickets[0].progressSteps = List.from(widget.ticket.progressSteps); // ⬅️ Ini penting!
                  });


                  await _updateTicketProgress();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("✅ Follow Up updated successfully!"),
                      backgroundColor: Colors.green,
                    ),
                  );

                  Navigator.of(context).pop(); // ✅ Hanya tutup dialog
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("❌ Failed to update description."),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("⚠️ Please enter a description!"),
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





Future<void> _refreshTicketDescription(int ticketId) async {
  debugPrint("🔄 Fetching updated description for Ticket ID: $ticketId...");

  Map<String, dynamic>? ticketData = await widget.odooService.getTicketDetails(ticketId);
  if (ticketData != null && ticketData.containsKey('description')) {
    setState(() {
      widget.ticket.description = ticketData['description'];

      // ✅ Pastikan description diletakkan selepas "Technician Check In"
      int checkInIndex = widget.ticket.progressSteps.indexWhere((step) => step.title == "Technician Check In");
      if (checkInIndex != -1) {
        widget.ticket.progressSteps.insert(
          checkInIndex + 1,
          ProgressStep(
            title: "Description Added",
            timestamp: DateTime.now(),
            isCompleted: true,
            icon: Icons.description,
            description: ticketData['description'], // ✅ Pastikan description ditarik dari Odoo
          ),
        );
      } else {
        widget.ticket.progressSteps.add(
          ProgressStep(
            title: "Description Added",
            timestamp: DateTime.now(),
            isCompleted: true,
            icon: Icons.description,
            description: ticketData['description'], // ✅ Pastikan description ditarik dari Odoo
          ),
        );
      }
    });

    debugPrint("✅ Updated description from Odoo: ${ticketData['description']}");
  } else {
    debugPrint("⚠️ No updated description found in Odoo.");
  }
}
Future<void> _uploadFileToTicket(Ticket ticket) async {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Camera'),
            onTap: () async {
              Navigator.pop(context);
              final pickedImage = await ImagePicker().pickImage(source: ImageSource.camera);
              if (pickedImage != null) {
                final file = PlatformFile(
                  name: pickedImage.name,
                  path: pickedImage.path,
                  size: await pickedImage.length(),
                  bytes: await pickedImage.readAsBytes(),
                );
                await _confirmAndUpload(ticket, file);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: () async {
              Navigator.pop(context);
              final pickedImage = await ImagePicker().pickImage(source: ImageSource.gallery);
              if (pickedImage != null) {
                final file = PlatformFile(
                  name: pickedImage.name,
                  path: pickedImage.path,
                  size: await pickedImage.length(),
                  bytes: await pickedImage.readAsBytes(),
                );
                await _confirmAndUpload(ticket, file);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('Folder'),
            onTap: () async {
              Navigator.pop(context);
              FilePickerResult? result = await FilePicker.platform.pickFiles(
                allowMultiple: false,
                withData: true,
                type: FileType.any,
              );
              if (result != null && result.files.isNotEmpty) {
                await _confirmAndUpload(ticket, result.files.first);
              }
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmAndUpload(Ticket ticket, PlatformFile selectedFile) async {
  bool? confirm = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Confirm File Upload'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: ${selectedFile.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Size: ${(selectedFile.size / 1024).toStringAsFixed(2)} KB'),
            Text('Type: ${selectedFile.extension ?? "Unknown"}'),
            const SizedBox(height: 12),
            if (selectedFile.extension != null && _isImage(selectedFile.extension!)) ...[
              selectedFile.bytes != null
                  ? Image.memory(selectedFile.bytes!, height: 150, fit: BoxFit.contain)
                  : const Text('⚠️ Preview not available'),
            ] else if (selectedFile.extension != null &&
                selectedFile.extension!.toLowerCase() == 'pdf' &&
                selectedFile.path != null &&
                File(selectedFile.path!).existsSync()) ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _viewPdf(selectedFile.path!);
                },
                child: const Text('Open PDF'),
              ),
            ] else ...[
              const Text('Preview not available for this file type.'),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Choose Another')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirm Upload')),
        ],
      );
    },
  );

  if (confirm == true) {
    bool success = await widget.odooService.uploadFileToTicket(ticket.id, selectedFile);
    if (success) {
      await _attachFile(ticket.id, selectedFile);
      await _updateTicketProgress();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ File uploaded successfully!"), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Failed to upload file."), backgroundColor: Colors.red),
      );
    }
  }
}



Future<String> _getSessionId() async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  return prefs.getString("session_id") ?? ""; // Pastikan sesi disimpan
}


String _getMimeType(String extension) {
  const mimeTypes = {
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "gif": "image/gif",
    "pdf": "application/pdf",
    "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xls": "application/vnd.ms-excel",
    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "ppt": "application/vnd.ms-powerpoint",
    "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "txt": "text/plain",
    "csv": "text/csv",
    "zip": "application/zip",
    "mp4": "video/mp4",
    "mp3": "audio/mpeg",
    "wav": "audio/wav"
  };
  return mimeTypes[extension.toLowerCase()] ?? "application/octet-stream";
}


Widget _buildProgressStep(ProgressStep step, Ticket ticket, Color textColor, Color? subTextColor) {
  debugPrint("🛠️ Step Title: ${step.title}");
  debugPrint("🛠️ Attached Files Count: ${step.attachedFiles?.length ?? 0}");
  String formattedDate = DateFormat('dd/MM/yyyy').format(step.timestamp!);
  String formattedTime = DateFormat('HH:mm a').format(step.timestamp!);

return IntrinsicHeight(
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // LEFT SIDE: Date, Time & Edit Button
      Expanded(
        flex: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formattedDate,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: subTextColor,
              ),
            ),
            Text(
              formattedTime,
              style: TextStyle(
                fontSize: 13,
                color: subTextColor,
              ),
            ),
            if (step.title == "Follow Up Added" || step.title == "Resolution")
              TextButton.icon(
                onPressed: () => _showEditDialog(ticket, step),
                icon: Icon(Icons.edit, size: 16, color: subTextColor),
                label: Text(
                  'Edit',
                  style: TextStyle(fontSize: 12, color: subTextColor),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
      ),

      // MIDDLE: Icon bulat & line
      SizedBox(
        width: 40,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: step.isCompleted ? Colors.green : Colors.grey[400],
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 2,
                ),
              ),
              child: Icon(
                step.icon ?? Icons.check,
                color: Colors.white,
                size: 16,
              ),
            ),
            if (step != ticket.progressSteps.last)
              Container(
                width: 2,
                height: 40,
                color: Colors.grey[300],
              ),
          ],
        ),
      ),

      // RIGHT SIDE: Title + Description + Files
      Expanded(
        flex: 3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              step.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            if (step.description != null && step.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  step.description!,
                  style: TextStyle(
                    fontSize: 13,
                    color: subTextColor,
                  ),
                ),
              ),
            if (step.attachedFiles != null && step.attachedFiles!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: step.attachedFiles!.map((file) {
                    return GestureDetector(
                      onTap: () => _showFileDetails(file),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            Icon(Icons.attach_file, size: 16, color: subTextColor),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                file.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subTextColor,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    ],
  ),
);
}


// ✅ KEMASKINI PENUH UNTUK SOKONG EDIT FOLLOW UP & RESOLUTION DENGAN BETUL
// Hanya bahagian penting dikemas kini, keseluruhan file tidak disalin semula kerana terlalu panjang
// Anda hanya perlu salin perubahan ini ke dalam `ticketprogress.dart`
void _showEditDialog(Ticket ticket, ProgressStep step) {
  final TextEditingController descriptionController = TextEditingController(text: step.description);

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(step.title == "Follow Up Added" ? 'Edit Follow Up' : 'Edit Resolution'),
        content: TextField(
          controller: descriptionController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: step.title == "Follow Up Added" ? 'Edit Follow Up' : 'Edit Resolution',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (descriptionController.text.isNotEmpty) {
                bool success = false;

                if (step.title == "Follow Up Added") {
                  final clean = descriptionController.text
                      .replaceAll(RegExp(r'<[^>]*>'), '')
                      .replaceAll('&nbsp;', ' ')
                      .replaceAll('&amp;', '&')
                      .replaceAll('&lt;', '<')
                      .replaceAll('&gt;', '>')
                      .replaceAll('&quot;', '"')
                      .replaceAll('&#39;', "'")
                      .replaceAll(RegExp(r'\s+'), ' ')
                      .trim();
                  if (clean.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("⚠️ Please enter a value!"),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  descriptionController.text = clean;
                  success = await widget.odooService.submitDescription(ticket.id, clean);
                } else if (step.title == "Resolution") {
                  success = await widget.odooService.submitCloseComment(ticket.id, descriptionController.text);
                }

if (success) {
  setState(() {
    step.description = descriptionController.text;

    if (step.title == "Follow Up Added") {
      widget.ticket.description = descriptionController.text;
    }
  });

  if (step.title == "Follow Up Added") {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('description_${ticket.id}', descriptionController.text); // ✅ Tambah ini
  }

  await _updateTicketProgress();

  setState(() {
    tickets[0].progressSteps = List.from(widget.ticket.progressSteps);
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text("✅ ${step.title} updated successfully!"),
      backgroundColor: Colors.green,
    ),
  );

  Navigator.of(context).pop();
} else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("❌ Failed to update."),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("⚠️ Please enter a value!"),
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






Widget _buildCheckoutButton(int ticketId) {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF282454),
      padding: const EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    onPressed: () => _performCheckout(), // ✅ Hantar ID tiket yang betul
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(Icons.logout, color: Colors.white),
        SizedBox(width: 8),
        Text(
          'Checkout',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    ),
  );
}

void _performCheckout() async {
  int ticketId = widget.ticket.id;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Confirm Check-Out'),
      content: const Text('Are you sure you want to check out for this ticket?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
      ],
    ),
  );

  if (confirm == true) {
    DateTime checkOutTime = DateTime.now();
    String formattedCheckOut = DateFormat('dd/MM/yyyy HH:mm:ss').format(checkOutTime);

    bool success = await widget.odooService.submitCheckOut(ticketId, formattedCheckOut);

    if (success) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isCheckedOut_$ticketId', true);
      await prefs.setString('checkOutTime_$ticketId', formattedCheckOut);

      // 🛠 Update dalam local ticket object + UI
      setState(() {
        if (!tickets[0].progressSteps.any((step) => step.title == 'Technician Check Out')) {
          tickets[0].progressSteps.add(
            ProgressStep(
              title: 'Technician Check Out',
              timestamp: checkOutTime,
              isCompleted: true,
              icon: Icons.logout,
            ),
          );
        }
        tickets[0].isCheckedOut = true; // ✅ Mark ticket as checked out
        isCheckoutComplete = true; // ✅ Update local flag supaya hide checkout button
      });

      await _updateTicketProgress(); // ✅ Save baru ke SharedPreferences

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Check-out successful'),
          backgroundColor: Colors.green,
        ),
      );

      // Opsyenal: tanya nak close ticket lepas checkout
     // Future.delayed(const Duration(seconds: 1), () {
       // _showCloseTicketPrompt(ticketId);
      //});
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Failed to submit check-out'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}


void _showCloseTicketPrompt(int ticketId) async {
  final close = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Close Ticket?'),
      content: const Text('Do you want to mark this ticket as closed? This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not Now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: const Text('Close Ticket', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (close == true) {
    bool success = await widget.odooService.markTicketAsClosed(ticketId);

    if (success) {
      setState(() {
        // Add a progress step for ticket closure
        tickets[0].progressSteps.add(
          ProgressStep(
            title: 'Ticket Closed',
            timestamp: DateTime.now(),
            isCompleted: true,
            icon: Icons.check_circle,
          ),
        );
        
        // Update the ticket's stage name in the UI
        if (widget.ticket is Map<String, dynamic>) {
          (widget.ticket as Map<String, dynamic>)['stage_name'] = 'Closed';
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Ticket closed successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Navigate back to TicketPage with result to refresh UI
      Navigator.pop(context, widget.ticket); // ✅ Hantar balik object ticket
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Failed to close ticket'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}



Future<void> _loadProgressStepsFromOdoo(int ticketId) async {
  try {
    // 🔹 Fetch progress dari server kalau anda ada function ni (kalau tak, abaikan)
    List<ProgressStep> latestSteps = await widget.odooService.fetchProgressSteps(ticketId);

    // 🔹 Ambil maklumat tiket (description dll)
    Map<String, dynamic>? ticketData = await widget.odooService.getTicketDetails(ticketId);

    // ✅ Fetch senarai attachment dari Odoo
    try {
      List<Map<String, dynamic>> attachments = await widget.odooService.getTicketAttachments(ticketId);
      
      if (attachments.isNotEmpty) {
        for (var attachment in attachments) {
          // Check if attachment already exists in progress steps
          bool attachmentExists = widget.ticket.progressSteps.any((step) => 
            step.title == "File Attached" && 
            step.description == attachment['name']
          );

          if (!attachmentExists) {
            // Safely handle the attachment data
            String? attachmentName = attachment['name']?.toString();
            String? attachmentUrl = attachment['url']?.toString();
            
            if (attachmentName != null) {
              widget.ticket.progressSteps.add(
                ProgressStep(
                  title: "File Attached",
                  timestamp: DateTime.now(),
                  isCompleted: true,
                  icon: Icons.attach_file,
                  description: attachmentName,
                  followUp: attachmentUrl,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Error fetching attachments: $e");
      // Continue without attachments if there's an error
    }

    // ✅ Update state
    if (mounted) {
      setState(() {
        // Only add new steps that don't already exist
        for (var step in latestSteps) {
          bool stepExists = widget.ticket.progressSteps.any((existingStep) =>
            existingStep.title == step.title &&
            existingStep.timestamp?.toIso8601String() == step.timestamp?.toIso8601String()
          );
          
          if (!stepExists) {
            widget.ticket.progressSteps.add(step);
          }
        }
      });
    }
  } catch (e) {
    debugPrint("⚠️ Error loading progress steps: $e");
    // Show error message to user
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to load progress steps from server'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}



void _showProgressUpdateDialog(Ticket ticket, {ProgressStep? step}) {
  final TextEditingController titleController = TextEditingController(text: step?.title ?? '');
  List<PlatformFile> attachedFiles = [];

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Resolution'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Enter Resolution'),
                  ),
                  const SizedBox(height: 16),

                  // Butang pilih fail
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Attach Files', style: TextStyle(fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Choose Files'),
                        onPressed: () async {
                          FilePickerResult? result = await FilePicker.platform.pickFiles(
                            allowMultiple: true,
                          );

                          if (result != null) {
                            setStateDialog(() {
                              attachedFiles.addAll(result.files);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Paparkan senarai fail yang dipilih
                  if (attachedFiles.isNotEmpty)
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
                        ...attachedFiles.map((file) {
                          return ListTile(
                            leading: const Icon(Icons.attach_file, color: Color(0xFF19543E)),
                            title: Text(
                              file.name,
                              style: const TextStyle(fontSize: 12, color: Colors.black),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () {
                                setStateDialog(() {
                                  attachedFiles.remove(file);
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (titleController.text.isNotEmpty) {
                    bool success = await widget.odooService.submitCloseComment(ticket.id, titleController.text);

                    if (success) {
                      setState(() {
                        ticket.progressSteps.add(
                          ProgressStep(
                            title: "Resolution",
                            timestamp: DateTime.now(),
                            isCompleted: true,
                            icon: Icons.comment,
                            description: titleController.text,
                            attachedFiles: attachedFiles, // Simpan fail
                          ),
                        );
                      });

                      // Paksa UI reload setelah menyimpan komentar
                      _loadProgressStepsFromOdoo(ticket.id);

                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Failed to submit Resolution')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a Resolution')),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

void _showFileDetails(PlatformFile file) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      Widget content;

      // Log untuk debug
      debugPrint("📂 File Name: ${file.name}");
      debugPrint("📂 File Extension: ${file.extension}");
      debugPrint("📂 File Path: ${file.path}");
      debugPrint("📂 Bytes exist: ${file.bytes != null}");
      debugPrint("📂 File exists: ${file.path != null && File(file.path!).existsSync()}");

      if (file.extension != null && _isImage(file.extension!)) {
        if (file.extension!.toLowerCase() == 'heic') {
          content = const Text(
            '⚠️ HEIC format is not supported for preview. Please use JPG or PNG.',
            style: TextStyle(fontSize: 14),
          );
        } else if (file.bytes != null) {
          content = Image.memory(
            file.bytes!,
            fit: BoxFit.contain,
          );
        } else if (file.path != null && File(file.path!).existsSync()) {
          content = Image.file(
            File(file.path!),
            fit: BoxFit.contain,
          );
        } else {
          content = const Text(
            '⚠️ Cannot preview this image. File path or bytes unavailable.',
            style: TextStyle(fontSize: 14),
          );
        }
      } else if (file.extension != null &&
          file.extension!.toLowerCase() == 'pdf' &&
          file.path != null &&
          File(file.path!).existsSync()) {
        content = ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            _viewPdf(file.path!);
          },
          child: const Text('Open PDF'),
        );
      } else {
        content = Text(
          'File Path: ${file.path ?? "Unavailable"}',
          style: const TextStyle(fontSize: 14),
        );
      }

      return AlertDialog(
        title: Text(file.name),
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}


bool _isImage(String extension) {
  const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic'];
  return imageExtensions.contains(extension.toLowerCase());
}

  
bool _isUneditableStep(String title) {
  const uneditableTitles = [
    'Technician Check In',
    'Technician Check Out',
  ];
  return uneditableTitles.contains(title);
}

Future<void> _saveProgressToSharedPreferences(int ticketId) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();

  List<String> progressList = tickets[0].progressSteps.map((step) {
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

  await prefs.setStringList('progressSteps_$ticketId', progressList);
  debugPrint("✅ Progress saved to SharedPreferences for Ticket ID: $ticketId");
}

Future<void> _loadProgressFromSharedPreferences() async {
  debugPrint("🔄 Loading progress from SharedPreferences for Ticket ID: ${widget.ticket.id}");
  SharedPreferences prefs = await SharedPreferences.getInstance();
  int ticketId = widget.ticket.id;

  // Clear existing progress steps first
  widget.ticket.progressSteps.clear();

  // Load progress from SharedPreferences
  List<String>? savedProgressList = prefs.getStringList('progressSteps_$ticketId');

  if (savedProgressList != null) {
    setState(() {
      widget.ticket.progressSteps = savedProgressList.map((progressJson) {
        Map<String, dynamic> progressData = jsonDecode(progressJson);
        
        // Handle attached files
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
          attachedFiles: attachedFiles, // Add the attached files here
        );
      }).toList();
    });

    // Ensure Check-in exists if ticket is checked in
    if (widget.ticket.checkInTime != null && 
        !widget.ticket.progressSteps.any((step) => step.title == "Technician Check In")) {
      setState(() {
        widget.ticket.progressSteps.insert(
          0,
          ProgressStep(
            title: 'Technician Check In',
            timestamp: widget.ticket.checkInTime,
            isCompleted: true,
            icon: Icons.login,
          ),
        );
      });
    }

    // Ensure Check-out exists if ticket is checked out
    if (widget.ticket.isCheckedOut && 
        !widget.ticket.progressSteps.any((step) => step.title == "Technician Check Out")) {
      String? savedCheckOut = prefs.getString('checkOutTime_$ticketId');
      if (savedCheckOut != null) {
        setState(() {
          widget.ticket.progressSteps.add(
            ProgressStep(
              title: 'Technician Check Out',
              timestamp: DateTime.parse(savedCheckOut),
              isCompleted: true,
              icon: Icons.logout,
            ),
          );
        });
      }
    }

    debugPrint("✅ Loaded ${widget.ticket.progressSteps.length} progress steps from SharedPreferences");
  } else {
    debugPrint("⚠️ No progress found in SharedPreferences");
  }
}


Future<void> _saveDescription(int ticketId, String description) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setString('description_$ticketId', description);
  debugPrint("✅ Description saved for Ticket ID: $ticketId - $description");
}



Future<void> _addDescription(int ticketId, String newDescription) async {
  SharedPreferences prefs = await SharedPreferences.getInstance();

  // ✅ Dapatkan progress lama dari SharedPreferences
  List<String>? savedProgressList = prefs.getStringList('progressSteps_$ticketId');
  List<ProgressStep> oldProgress = [];

  if (savedProgressList != null) {
    oldProgress = savedProgressList.map((progressJson) {
      Map<String, dynamic> progressData = jsonDecode(progressJson);
      return ProgressStep(
        title: progressData['title'],
        timestamp: progressData['timestamp'] != null
            ? DateTime.parse(progressData['timestamp'])
            : null,
        isCompleted: progressData['isCompleted'] ?? false,
        icon: progressData['icon'] != null ? IconData(progressData['icon'], fontFamily: 'MaterialIcons') : null,
        description: progressData['description'],
      );
    }).toList();
  }

  // ✅ Tambahkan "Description Added" ke dalam progressSteps
  setState(() {
    tickets[0].progressSteps = [...oldProgress]; // ✅ Pastikan progress lama tidak hilang
    tickets[0].progressSteps.add(
      ProgressStep(
        title: "Description Added",
        timestamp: DateTime.now(),
        isCompleted: true,
        icon: Icons.description,
        description: newDescription,
      ),
    );
  });

  await _saveProgressToSharedPreferences(ticketId);
}


Future<void> _attachFile(int ticketId, PlatformFile file) async {
  setState(() {
    // ✅ Tambah fail ke dalam progressSteps
    // Cari index "Technician Check In"
    int checkInIndex = tickets[0].progressSteps.indexWhere((step) => step.title == "Technician Check In");

    // Jika "Technician Check In" ditemui, tambahkan fail selepasnya
    if (checkInIndex != -1) {
      tickets[0].progressSteps.insert(
        checkInIndex + 1,
        ProgressStep(
          title: "File Attached",
          timestamp: DateTime.now(),
          isCompleted: true,
          icon: Icons.attach_file,
          attachedFiles: [file],
        ),
      );
    }
  });

  await _saveProgressToSharedPreferences(ticketId);
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
            content: const Text(
                'Are you sure you want to mark this ticket as closed? This action cannot be undone.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
  onPressed: () => Navigator.pop(context, true),
  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
  child: const Text(
    'Close Ticket',
    style: TextStyle(color: Colors.white), // ✅ Tambah warna putih
  ),
),

            ],
          ),
        );

        if (confirm == true) {
          bool success = await widget.odooService.markTicketAsClosed(ticketId);
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Ticket closed successfully'),
                backgroundColor: Colors.green,
              ),
            );

            /// ‼️ PENTING: Inilah line yang kita betulkan
            Navigator.pop(context, {'closed': true});

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



void _insertUserProgress(ProgressStep step) {
  setState(() {
    // Cari index Check Out, kalau ada
    int checkOutIndex = widget.ticket.progressSteps.indexWhere((s) => s.title == "Technician Check Out");

    // Cari index Check In (wajib ada)
    int checkInIndex = widget.ticket.progressSteps.indexWhere((s) => s.title == "Technician Check In");

    // Cari index Close Ticket (jika sudah ada)
    int closeTicketIndex = widget.ticket.progressSteps.indexWhere((s) => s.title == "Ticket Closed");

    // Insert selepas Check In dan sebelum Technician Check Out atau Close Ticket
    int insertIndex = widget.ticket.progressSteps.length;

    if (checkOutIndex != -1) {
      insertIndex = checkOutIndex;
    } else if (closeTicketIndex != -1) {
      insertIndex = closeTicketIndex;
    }

    if (checkInIndex != -1 && insertIndex <= checkInIndex) {
      insertIndex = checkInIndex + 1;
    }

    widget.ticket.progressSteps.insert(insertIndex, step);
  });
}
}

