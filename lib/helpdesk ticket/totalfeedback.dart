import 'package:flutter/material.dart';
import '../odoo_service.dart';

/// Brand purple + accent green (MyERP-style).
const Color _kBrand = Color(0xFF282454);
const Color _kAccent = Color(0xFF0D7A57);

class TotalFeedbackScreen extends StatefulWidget {
  final int ticketId;
  const TotalFeedbackScreen({super.key, required this.ticketId});

  @override
  State<TotalFeedbackScreen> createState() => _TotalFeedbackScreenState();
}

class _TotalFeedbackScreenState extends State<TotalFeedbackScreen> {
  double _totalScore = 0.0;
  final List<Map<String, dynamic>> _feedbackData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFeedbackData();
  }

  Future<void> _loadFeedbackData() async {
    final data = await OdooService().getTicketDetails(widget.ticketId);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _feedbackData.clear();
      if (data != null) {
        _feedbackData.addAll([
          {
            "label": "Keeping you informed",
            "subtitle": "During problem resolution",
            "value": double.tryParse(data["feedback_scale1"]?.toString() ?? "0") ?? 0,
          },
          {
            "label": "Engineer attitude",
            "subtitle": "Professionalism & courtesy",
            "value": double.tryParse(data["feedback_scale2"]?.toString() ?? "0") ?? 0,
          },
          {
            "label": "Technical ability",
            "subtitle": "Skills & diagnosis",
            "value": double.tryParse(data["feedback_scale3"]?.toString() ?? "0") ?? 0,
          },
          {
            "label": "Time to resolve",
            "subtitle": "Speed of resolution",
            "value": double.tryParse(data["feedback_scale4"]?.toString() ?? "0") ?? 0,
          },
          {
            "label": "Punctuality",
            "subtitle": "Arrived on time",
            "value": double.tryParse(data["feedback_scale5"]?.toString() ?? "0") ?? 0,
          },
          {
            "label": "Overall satisfaction",
            "subtitle": "Support experience",
            "value": double.tryParse(data["feedback_scale6"]?.toString() ?? "0") ?? 0,
          },
        ]);
        _totalScore =
            _feedbackData.map((e) => e["value"] as double).fold(0.0, (a, b) => a + b);
      }
    });
  }

  Color _scoreTint(double value) {
    final t = (value / 5).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFFE57373), _kAccent, t) ?? _kAccent;
  }

  Widget _buildSummaryHeader(double pct) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kBrand.withValues(alpha: 0.07),
            _kAccent.withValues(alpha: 0.06),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kBrand.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: _kBrand.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.insights_rounded, color: _kBrand.withValues(alpha: 0.85), size: 22),
              const SizedBox(width: 8),
              Text(
                'Feedback summary',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: _kBrand.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _totalScore.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  color: _kBrand,
                ),
              ),
              Text(
                ' / 30',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${pct.toStringAsFixed(1)}% overall',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: _kAccent.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: (_totalScore / 30).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              color: _kAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriterionCard(Map<String, dynamic> item, int index) {
    final value = item["value"] as double;
    final label = item["label"] as String;
    final subtitle = item["subtitle"] as String;
    final ratio = (value / 5).clamp(0.0, 1.0);
    final tint = _scoreTint(value);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _kBrand.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _kBrand,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${value.toStringAsFixed(1)} / 5',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: tint.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: Colors.grey.shade200,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topBarForeground = _kBrand.withValues(alpha: 0.92);
    final pct = _feedbackData.isEmpty ? 0.0 : (100 * _totalScore / 30);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: topBarForeground),
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'Feedback Summary',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                        color: topBarForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: _kBrand.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading feedback…',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _feedbackData.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.feedback_outlined,
                                  size: 56,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No feedback data for this ticket.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildSummaryHeader(pct),
                              const SizedBox(height: 22),
                              Row(
                                children: [
                                  Icon(
                                    Icons.analytics_outlined,
                                    size: 20,
                                    color: _kBrand.withValues(alpha: 0.75),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Criteria breakdown',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: _kBrand.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Each item is scored out of 5.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              ...List.generate(
                                _feedbackData.length,
                                (i) => _buildCriterionCard(_feedbackData[i], i),
                              ),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
