import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import '../odoo_service.dart';
import 'package:intl/intl.dart';
import 'totalfeedback.dart';

class FeedbackScreen extends StatefulWidget {
  final String ticketId;
  final String? technicianName;

  const FeedbackScreen({
    Key? key,
    required this.ticketId,
    this.technicianName,
  }) : super(key: key);

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  double _informedRating = 0;
  double _attitudeRating = 0;
  double _technicalRating = 0;
  double _timeRating = 0;
  double _punctualityRating = 0;
  double _overallRating = 0;

  final TextEditingController _customerNameController = TextEditingController();

  final SignatureController _customerSignatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  String get _currentDateTime =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showSatisfactionScaleDialog();
    });
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerSignatureController.dispose();
    super.dispose();
  }

  Future<void> _showSatisfactionScaleDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Satisfaction Scale',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF282454),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScaleItem('1: Dissatisfied'),
                    const SizedBox(height: 8),
                    _buildScaleItem('2: Somewhat Dissatisfied'),
                    const SizedBox(height: 8),
                    _buildScaleItem('3: Somewhat Satisfied'),
                    const SizedBox(height: 8),
                    _buildScaleItem('4: Very Satisfied'),
                    const SizedBox(height: 8),
                    _buildScaleItem('5: Completely Satisfied'),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );
  }

  Widget _buildScaleItem(String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade400),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildCriteriaRating(String title, double value, Function(double) onChanged, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: textColor ?? const Color(0xFF282454),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(5, (index) {
                final rating = (index + 1).toDouble();
                return Radio<double>(
                  value: rating,
                  groupValue: value == 0 ? null : value,
                  activeColor: const Color(0xFF282454),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (newValue) {
                    if (newValue != null) onChanged(newValue);
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // Custom card builder for Service Performance Criteria and Customer Signature
  Widget _buildCustomCard({required Widget child, required bool isDarkMode}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF282454), width: 1),
      ),
      color: isDarkMode ? Colors.black : Colors.white,
      child: child,
    );
  }

  Widget _buildSignatureSection(String title, SignatureController controller, bool isDarkMode) {
    final bgColor = isDarkMode ? Colors.black : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF282454);
    return _buildCustomCard(
      isDarkMode: isDarkMode,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 150,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: bgColor,
              ),
              child: Signature(
                controller: controller,
                backgroundColor: bgColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => controller.clear(),
                  child: Text('Clear', style: TextStyle(color: textColor)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }



Future<void> _submitFeedback() async {
  if (_informedRating == 0 || 
      _attitudeRating == 0 || 
      _technicalRating == 0 || 
      _timeRating == 0 || 
      _punctualityRating == 0 || 
      _overallRating == 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please provide all ratings')),
    );
    return;
  }

  if (_customerSignatureController.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please provide customer signature')),
    );
    return;
  }

  Uint8List? signatureBytes = await _customerSignatureController.toPngBytes();
  if (signatureBytes == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to capture signature')),
    );
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('informed_rating_${widget.ticketId}', _informedRating);
  await prefs.setDouble('attitude_rating_${widget.ticketId}', _attitudeRating);
  await prefs.setDouble('technical_rating_${widget.ticketId}', _technicalRating);
  await prefs.setDouble('time_rating_${widget.ticketId}', _timeRating);
  await prefs.setDouble('punctuality_rating_${widget.ticketId}', _punctualityRating);
  await prefs.setDouble('overall_rating_${widget.ticketId}', _overallRating);
  await prefs.setString('customer_name_${widget.ticketId}', _customerNameController.text);
  await prefs.setString('completion_time_${widget.ticketId}', _currentDateTime);

  bool success = await OdooService().submitFeedbackToOdoo(
    ticketId: int.parse(widget.ticketId),
    scale1: _informedRating,
    scale2: _attitudeRating,
    scale3: _technicalRating,
    scale4: _timeRating,
    scale5: _punctualityRating,
    scale6: _overallRating,
    signatureBytes: signatureBytes,
  );

  if (!success) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to submit to Odoo')),
    );
    return;
  }

  if (!success) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to submit to Odoo')),
    );
    return;
  }

  if (mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TotalFeedbackScreen(ticketId: int.parse(widget.ticketId)),
      ),
    );
  }
} // ✅ PENUTUP UNTUK _submitFeedback()





  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode ? Colors.black : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF282454);
    final subTextColor = isDarkMode ? Colors.white70 : Colors.grey[600];
    final signatureBg = isDarkMode ? Colors.black : Colors.white;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CUSTOMER FEEDBACK',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF282454),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'images/wood.png',
              fit: BoxFit.cover,
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Service Performance Criteria Card
                _buildCustomCard(
                  isDarkMode: isDarkMode,
                  child: Container(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                'Service Performance Criteria',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: textColor,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 5,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: List.generate(
                                  5,
                                  (index) => Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Divider(color: textColor),
                        _buildCriteriaRating(
                          '1. Keeping you informed during problem resolution',
                          _informedRating,
                          (value) => setState(() => _informedRating = value),
                          textColor: textColor,
                        ),
                        _buildCriteriaRating(
                          '2. Attitude of engineer',
                          _attitudeRating,
                          (value) => setState(() => _attitudeRating = value),
                          textColor: textColor,
                        ),
                        _buildCriteriaRating(
                          '3. Technical ability of engineer',
                          _technicalRating,
                          (value) => setState(() => _technicalRating = value),
                          textColor: textColor,
                        ),
                        _buildCriteriaRating(
                          '4. Time taken to resolve problem',
                          _timeRating,
                          (value) => setState(() => _timeRating = value),
                          textColor: textColor,
                        ),
                        _buildCriteriaRating(
                          '5. Did the engineer arrive on time?',
                          _punctualityRating,
                          (value) => setState(() => _punctualityRating = value),
                          textColor: textColor,
                        ),
                        _buildCriteriaRating(
                          '6. Overall satisfaction with this support experience',
                          _overallRating,
                          (value) => setState(() => _overallRating = value),
                          textColor: textColor,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Customer Signature
                _buildSignatureSection('Customer Signature', _customerSignatureController, isDarkMode),
                const SizedBox(height: 16),
                // Submit Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF282454),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _submitFeedback,
                    child: const Text(
                      'Submit Feedback',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildPercentageBar(String title, double rating) {
  double percentage = (rating / 5.0) * 100;

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$title (${percentage.toStringAsFixed(0)}%)",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF282454),
          ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: rating / 5.0,
            minHeight: 10,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
        ),
      ],
    ),
  );
}

