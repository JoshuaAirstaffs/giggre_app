import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/theme_provider.dart';
import 'package:giggre_app/core/widgets/update_card.dart';

class GiggreUpdates extends StatelessWidget {
  const GiggreUpdates({super.key});

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
            children: listOfUpdates.map((update) {
              return GestureDetector(
                onTap: () => _openUpdateDetail(context, update),
                child: UpdateCard(
                  title: update["title"] as String,
                  icon: update["icon"] as IconData,
                  date: update["date"] as String,
                  category: update["category"] as String,
                  description: update["description"] as String,
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

final listOfUpdates = [
  {
    "title": "Welcome to Giggre!",
    "icon": Icons.update,
    "date": "2025-10-15",
    "category": "Announcement",
    "description":
        "We are officially launching Giggre! We're excited to bring you the best gig economy platform. Join us and start your journey today!",
  },
  {
    "title": "New Feature: Giggre Rewards",
    "icon": Icons.star,
    "date": "2025-10-15",
    "category": "Feature",
    "description":
        "We've added a new feature to Giggre! You can now earn rewards for completing gigs and referrals. Check it out and start earning today!",
  },
  {
    "title": "New Feature: Giggre Rewards",
    "icon": Icons.star,
    "date": "2025-10-15",
    "category": "Feature",
    "description":
        "We've added a new feature to Giggre! You can now earn rewards for completing gigs and referrals. Check it out and start earning today!",
  },
];

void _openUpdateDetail(BuildContext context, Map update) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final badgeBg = isDark ? const Color(0xFF001B52) : const Color(0xFFDDE9FB);
        final badgeText = Theme.of(context).colorScheme.primary;
        final iconBg = isDark ? const Color(0xFF001B52) : const Color(0xFFEBF0FB);
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

                // Drag handle
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

                // Category + date row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        update["category"] as String,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color:badgeText,
                        ),
                      ),
                    ),
                    Text(
                      update["date"] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF888888),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Icon + title row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        update["icon"] as IconData,
                        size: 20,
                        color: kBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        update["title"] as String,
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

                // Full description
                Text(
                  update["description"] as String,
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