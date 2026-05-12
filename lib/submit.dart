import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'helpdesk ticket/ticketprogress.dart';
import 'dart:io';

const Color primaryPurple = Color(0xFF282454);
const Color lightPurple = Color(0xFFBFB9FA);
const Color greyButton = Color(0xFFE0E0E0);

class SubmitPage extends StatefulWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onSubmissionComplete;
  final bool isDarkMode; // Add dark mode parameter

  const SubmitPage({
    Key? key,
    required this.ticket,
    required this.onSubmissionComplete,
    required this.isDarkMode, // Pass dark mode state
  }) : super(key: key);

  @override
  State<SubmitPage> createState() => _SubmitPageState();
}

class _SubmitPageState extends State<SubmitPage> {
  String? uploadedFileName;
  File? selectedFile;
  final TextEditingController resolutionController = TextEditingController();
  final TextEditingController followUpController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  bool isUploading = false;

  @override
  void dispose() {
    resolutionController.dispose();
    followUpController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

@override
Widget build(BuildContext context) {
  final isDarkMode = widget.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        title: const Text(
          'Submit Ticket',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: isDarkMode ? Colors.white : primaryPurple),
          onPressed: () => Navigator.pop(context),
        ),
        titleTextStyle: TextStyle(
          color: isDarkMode ? Colors.white : primaryPurple,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Image.asset(
                        'images/purple.png',
                        width: 200,
                        height: 200,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildTextField('Resolution', resolutionController, isDarkMode),
                    const SizedBox(height: 10),
                    _buildTextField('Follow-up', followUpController, isDarkMode),
                    const SizedBox(height: 10),
                    _buildTextField('Description', descriptionController, isDarkMode),
                    const SizedBox(height: 20),
                    Text(
                      'Upload proof of work (optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildUploadButton(isDarkMode),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDarkMode ? Colors.grey[800] : greyButton,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(fontSize: 16, color: isDarkMode ? Colors.white : primaryPurple),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryPurple,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Submit Ticket',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                          Icon(Icons.arrow_forward, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, bool isDarkMode) {
    return TextField(
      controller: controller,
      style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 16,
          color: isDarkMode ? lightPurple : primaryPurple,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDarkMode ? lightPurple : primaryPurple),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDarkMode ? lightPurple : primaryPurple),
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[800] : Colors.white,
      ),
      maxLines: 2,
    );
  }

Future<void> _pickFile() async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'pdf', 'doc', 'docx', 'png'],
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.path != null) {
        final fileToUpload = File(file.path!);
        if (await fileToUpload.exists()) {
          setState(() {
            selectedFile = fileToUpload;
            uploadedFileName = file.name;
          });
          // Debugging: Confirm file selection
          debugPrint('File Selected in SubmitPage: ${file.name}, Path: ${file.path}');
        }
      }
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error selecting file: ${e.toString()}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}


Widget _buildUploadButton(bool isDarkMode) {
  final isDarkMode = widget.isDarkMode;
  return InkWell(
    onTap: isUploading ? null : _pickFile,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryPurple),
        color: isDarkMode ? Colors.grey[800] : Colors.white,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isUploading)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(primaryPurple),
              ),
            )
          else
            Icon(Icons.upload_file, color: isDarkMode ? lightPurple : primaryPurple),
          const SizedBox(width: 8),
          Text(
            isUploading ? 'Uploading...' : (uploadedFileName ?? 'Upload File'),
            style: TextStyle(
              fontSize: 16,
              color: isDarkMode ? lightPurple : primaryPurple,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}



  Future<void> _uploadFile(File file) async {
    try {
      setState(() {
        isUploading = true;
      });

      await Future.delayed(const Duration(seconds: 2)); // Simulate upload

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('File uploaded successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading file: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isUploading = false;
        });
      }
    }
  }
void _handleSubmit() async {
  if (resolutionController.text.isEmpty ||
      followUpController.text.isEmpty ||
      descriptionController.text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Please fill in all fields."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }


  try {
    // Collect attached file details
    List<PlatformFile> attachedFiles = [];
    if (selectedFile != null) {
      attachedFiles.add(
        PlatformFile(
          name: uploadedFileName ?? '',
          path: selectedFile!.path,
          size: await selectedFile!.length(),
        ),
      );
    }

    // Add new progress step
    widget.ticket['progressSteps'] ??= [];
    widget.ticket['progressSteps'].add(
      ProgressStep(
        title: 'Technician Submitted the Ticket',
        timestamp: DateTime.now(),
        isCompleted: true,
        icon: Icons.upload_file,
        attachedFiles: attachedFiles,
        resolution: resolutionController.text, // Add resolution
        followUp: followUpController.text,     // Add follow-up
        description: descriptionController.text, // Add description
      ),
    );

    // Update ticket status to closed
    widget.ticket['status'] = 'closed'; // Mark ticket as closed
    widget.ticket['closedTimestamp'] = DateTime.now(); // Add closed timestamp

    debugPrint('Progress Steps after submission: ${widget.ticket['progressSteps']}');
    debugPrint('Ticket Status Updated to Closed');

    // Trigger callback to notify changes
    widget.onSubmissionComplete();

    if (mounted) {
      Navigator.pop(context);
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error submitting: ${e.toString()}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
}
