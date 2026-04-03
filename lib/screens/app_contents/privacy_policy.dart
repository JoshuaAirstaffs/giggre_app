import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/theme_provider.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PrivacyPolicy extends StatefulWidget {
  PrivacyPolicy({Key? key}) : super(key: key);

  @override
  _PrivacyPolicyState createState() => _PrivacyPolicyState();
}



class _PrivacyPolicyState extends State<PrivacyPolicy> {

  List<Map<String, dynamic>> _privacyPolicyItems = [];
  String _latestUpdateDate = '';
  bool _isLoading = true;

  Future<void> _loadPrivacyPolicy() async {
    setState(() {
      _isLoading = true;
    });
    try {

        //get the latest date from updatedDate
      final latestUpdate = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('privacy')
          .collection('items')
          .where('sortNumber', isEqualTo: 1)
          .orderBy('dateUpdated', descending: true)
          .limit(1)
          .get();

      final formattedDate = DateFormat('MMMM d, y').format((latestUpdate.docs.first.data()['dateUpdated'] as Timestamp).toDate());
      _latestUpdateDate = formattedDate;
      final response = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('privacy')
          .collection('items')
          .where('sortNumber', isEqualTo: 1)
          .get();
      final data = response.docs.map((doc) => doc.data()).toList();
      setState(() {
        _privacyPolicyItems = data;
      });
    } catch (e) {
      debugPrint("Error loading privacy policy: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  @override
  void initState() {
    super.initState();
    _loadPrivacyPolicy();
  }
  
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        title: Text(
          'Privacy Policy',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
       body: SafeArea(
        child: 
        _isLoading 
        ? Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: kBlue,
          ),
        )
        : SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
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
                      Icon(Icons.security, color: Colors.white),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Privacy Policy', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('Last updated: $_latestUpdateDate', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                ..._privacyPolicyItems.map((item) => _PrivacyPolicyCard(
                  title: item['title'] ?? '',
                  content: item['body'] ?? '',
                )),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Color.fromARGB(255, 255, 191, 94) : Color.fromARGB(255, 255, 231, 194),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color:  Color.fromARGB(255, 255, 149, 0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: isDark ? Colors.black : Color.fromARGB(255, 255, 149, 0), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'For more information about how we handle your data, please visit our website or contact our support team. www.giggre.com',
                          style: TextStyle(color: isDark ? Colors.black : onSurface, fontSize: 12),
                        ),
                      ),
                    ],
                  )
                ),
              ],
            ),
          ),
        ),
       ),
    );
  }
}

class _PrivacyPolicyCard extends StatelessWidget {
  const _PrivacyPolicyCard({
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
            color: isDark ? const Color.fromARGB(118, 0, 0, 0).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: kBlue, fontSize: 12, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(content, style: TextStyle(color: isDark ? onSurface : Colors.black, fontSize: 12)),
        ],
      ),
    );
  }
}