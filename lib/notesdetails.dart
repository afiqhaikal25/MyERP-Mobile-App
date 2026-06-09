import 'package:flutter/material.dart';
import 'dart:io';

class NotesDetailsPage extends StatelessWidget {
  final String title;
  final String content;
  final File? image;
  final bool isDarkMode;

  const NotesDetailsPage({
    Key? key,
    required this.title,
    required this.content,
    this.image,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : const Color(0xFFE8E6F3),
      appBar: AppBar(
        backgroundColor: isDarkMode ? Colors.grey[900] : const Color(0xFF282454),
        title: const Text(
          "Note Details",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              content,
              style: TextStyle(
                fontSize: 16,
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            if (image != null)
              Expanded(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 5.0, // Allow zooming up to 5x
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      image!,
                      fit: BoxFit.contain, // Ensures the entire image is shown
                    ),
                  ),
                ),
              ),
            if (image == null)
              const Center(
                child: Text(
                  "No image attached",
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
