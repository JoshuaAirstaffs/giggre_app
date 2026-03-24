import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AboutGiggre extends StatefulWidget {
  const AboutGiggre({super.key});

  @override
  State<AboutGiggre> createState() => _AboutGiggreState();
}

class _AboutGiggreState extends State<AboutGiggre> {
  String _mission = '';
  String _whatIsGiggre = '';
  String _website = '';
  List<String> _howItWorks = [];
   List<String> _values = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('about_giggre')
          .get();
      final sampleData = await FirebaseFirestore.instance
    .collection('app_content')
    .doc('about_giggre')
    .collection('items')  // 👈 subcollection
    .get();

    debugPrint(sampleData.docs.map((doc) => doc.data()).toString());
      if (mounted) {
        setState(() {
          _mission = response.data()?['mission'] ?? '';
          _whatIsGiggre = response.data()?['what_is_giggre'] ?? '';
          _website = response.data()?['website'] ?? '';
          _howItWorks = List<String>.from(response.data()?['how_it_works'] ?? []);
          _values = List<String>.from(response.data()?['values'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading about giggre: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
        title: Text(
          'About Giggre',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _Card(
                        title: 'Our Mission',
                        content: _mission,
                        icon: const Icon(Icons.lightbulb_outline),
                      ),
                      const SizedBox(height: 16),
                      _Card(
                        title: 'What is Giggre?',
                        content: _whatIsGiggre,
                        icon: const Icon(Icons.info_outline),
                      ),
                      const SizedBox(height: 16),
                      _CardList(
                        title: 'How It Works',
                        items: _howItWorks,
                        icon: const Icon(Icons.sync_alt),
                      ),
                      const SizedBox(height: 16),
                      _CardList(
                        title: 'Our Values',
                        items: _values,
                        icon: const Icon(Icons.favorite),
                      ),
                      const SizedBox(height: 16),
                     // instead of Expanded
                      Container(
                        width: double.infinity, // ← takes full width without needing Expanded
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.language, color: Colors.white),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Visit Us',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _website,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
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

// ← outside _AboutGiggreState
class _Card extends StatelessWidget {
  final String title;
  final String content;
  final Icon icon;

  const _Card({
    required this.title,
    required this.content,
    required this.icon,
  });


  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBg = isDark ? const Color(0xFF001B52) : const Color(0xFFEBF0FB);
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon.icon, size: 20, color: kBlue),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, height: 1.6, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CardList extends StatelessWidget {
  final String title;
  final List<String> items;
  final Icon icon;

  const _CardList({
    required this.title,
    required this.items,
    required this.icon,
  });

  static const _indeedBlue = Color(0xFF1A56DB);
  static const _darkNavy = Color.fromARGB(255, 0, 27, 82);

  @override

  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBg = isDark ? const Color(0xFF001B52) : const Color(0xFFEBF0FB);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon.icon, size: 20, color: kBlue),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.asMap().entries.map((entry) => Text(
            '${entry.key + 1}. ${entry.value}',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, height: 1.6, fontSize: 12),
          )),
        ],
      ),
    );
  }
}