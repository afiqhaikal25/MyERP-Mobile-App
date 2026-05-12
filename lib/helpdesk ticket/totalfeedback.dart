import 'package:flutter/material.dart';
import '../odoo_service.dart';

class TotalFeedbackScreen extends StatefulWidget {
  final int ticketId;
  const TotalFeedbackScreen({super.key, required this.ticketId});

  @override
  State<TotalFeedbackScreen> createState() => _TotalFeedbackScreenState();
}

class _TotalFeedbackScreenState extends State<TotalFeedbackScreen> {
  double _totalScore = 0.0;
  final List<Map<String, dynamic>> _feedbackData = [];

  @override
  void initState() {
    super.initState();
    _loadFeedbackData();
  }

  Future<void> _loadFeedbackData() async {
    final data = await OdooService().getTicketDetails(widget.ticketId);
    if (data != null) {
      setState(() {
        _feedbackData.clear();
        _feedbackData.addAll([
          {"label": "1. Keeping you informed", "value": double.parse(data["feedback_scale1"] ?? "0")},
          {"label": "2. Engineer attitude", "value": double.parse(data["feedback_scale2"] ?? "0")},
          {"label": "3. Technical ability", "value": double.parse(data["feedback_scale3"] ?? "0")},
          {"label": "4. Time to resolve", "value": double.parse(data["feedback_scale4"] ?? "0")},
          {"label": "5. Punctuality", "value": double.parse(data["feedback_scale5"] ?? "0")},
          {"label": "6. Overall satisfaction", "value": double.parse(data["feedback_scale6"] ?? "0")},
        ]);
        _totalScore = _feedbackData.map((e) => e["value"] as double).reduce((a, b) => a + b);
      });
    }
  }

  Widget _buildPercentageBar(String title, double value) {
    double percentage = value / 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: percentage,
          minHeight: 12,
          borderRadius: BorderRadius.circular(10),
          backgroundColor: Colors.grey.shade300,
          color: Color.lerp(Colors.red, Colors.green, percentage),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text("Feedback Summary", style: TextStyle(color: Colors.white)),
        backgroundColor: isDarkMode ? Colors.black : const Color(0xFF282454),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              isDarkMode ? 'images/woodb.png' : 'images/wood.png',
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _feedbackData.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Total Score: ${_totalScore.toStringAsFixed(1)} / 30",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text("Percentage Score: ${(100 * _totalScore / 30).toStringAsFixed(1)}%",
                          style: TextStyle(
                            fontSize: 16,
                            color: isDarkMode ? Colors.white : Colors.grey,
                          )),
                      const SizedBox(height: 16),
                      ..._feedbackData.map((item) =>
                          _buildPercentageBar(item["label"], item["value"])).toList(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
