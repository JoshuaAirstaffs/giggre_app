import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/theme_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TermsAndConditions extends StatefulWidget {
  const TermsAndConditions({Key? key}) : super(key: key);

  @override
  _TermsAndConditionsState createState() => _TermsAndConditionsState();
}

class _TermsAndConditionsState extends State<TermsAndConditions> {
  List<Map<String, dynamic>> _termsAndConditions = [];
  String? _latestUpdateDate;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      //get the latest date from updatedDate
      final latestUpdate = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('terms_and_conditions')
          .collection('items')
          .where('sortNumber', isEqualTo: 1)
          .orderBy('dateUpdated', descending: true)
          .limit(1)
          .get();

      final formattedDate = DateFormat('MMMM d, y').format((latestUpdate.docs.first.data()['dateUpdated'] as Timestamp).toDate());
      _latestUpdateDate = formattedDate;

      final response = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('terms_and_conditions')
          .collection('items')
          .get();
      final filteredData = response.docs
          .map((doc) => doc.data()['sortNumber'] == 1 ? doc.data() : null)
          .where((element) => element != null)
          .toList();
      setState(() {
        _termsAndConditions = filteredData.cast<Map<String, dynamic>>();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading terms and conditions: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Terms & Conditions',
            style: TextStyle(color: onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: kBlue))
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    spacing: 16,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: kBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.white),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Terms and Conditions',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                                Text('Last updated: $_latestUpdateDate',
                                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ..._termsAndConditions.map((term) => _TermsAndConditionsCard(
                            title: term['title'] ?? '',
                            content: term['body'] ?? '',
                          )),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 255, 191, 94),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color.fromARGB(255, 255, 149, 0)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                color: Color.fromARGB(255, 255, 149, 0), size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'By using our services, you agree to these terms and conditions.',
                                style: TextStyle(color: Colors.black, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _TermsAndConditionsCard extends StatelessWidget {
  const _TermsAndConditionsCard({
    super.key,
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? null : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? const Color.fromARGB(118, 0, 0, 0).withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: kBlue, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(content,
              style: TextStyle(
                  color: isDark ? onSurface : Colors.black, fontSize: 12)),
        ],
      ),
    );
  }
}