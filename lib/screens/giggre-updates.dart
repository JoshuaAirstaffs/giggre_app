import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/theme_provider.dart';
import 'package:giggre_app/core/widgets/update_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class GiggreUpdates extends StatefulWidget {
  const GiggreUpdates({super.key});

  @override
  State<GiggreUpdates> createState() => _GiggreUpdatesState();
}

class _GiggreUpdatesState extends State<GiggreUpdates> {
  final List<Map<String, dynamic>> _updates = [];

  @override
  void initState() {
    super.initState();
    _fetchUpdates();
  }

  Future<void> _fetchUpdates() async {
    try {
      final response = await FirebaseFirestore.instance
          .collection('app_content')
          .doc('updates')
          .collection('items')
          .get();

      setState(() {
        _updates.addAll(response.docs.map((doc) {
          final data = doc.data();
          // Normalize Timestamp → DateTime here, once
          if (data['dateUpdated'] is Timestamp) {
            data['dateUpdated'] = (data['dateUpdated'] as Timestamp).toDate();
          }
          return data;
        }));
      });
    } catch (e) {
      debugPrint('Error fetching updates: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: onSurface),
        title: Text(
          'Giggre Updates',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            spacing: 16,
            children: _updates.map((update) {
              return GestureDetector(
                onTap: () => _openUpdateDetail(context, update),
                child: UpdateCard(
                  title: update['title'] as String,
                  date: update['dateUpdated'] as DateTime, // ✅ already DateTime
                  category: update['category'] as String,
                  description: update['body'] as String,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

void _openUpdateDetail(BuildContext context, Map<String, dynamic> update) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final badgeBg = isDark ? const Color(0xFF001B52) : const Color(0xFFDDE9FB);
  final badgeText = Theme.of(context).colorScheme.primary;

  // ✅ dateUpdated is already DateTime — just format it
  final formattedDate = DateFormat('MMM dd, yyyy').format(update['dateUpdated'] as DateTime);

  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ListView(
              controller: scrollController,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        update['category'] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: badgeText,
                        ),
                      ),
                    ),
                    Text(
                      formattedDate, // ✅ pre-formatted string
                      style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        update['title'] as String,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                const SizedBox(height: 12),
                Text(
                  update['body'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      );
    },
  );
}