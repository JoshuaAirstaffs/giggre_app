import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';

class UpdateCard extends StatelessWidget {
  final String title;
  final String description;
  final DateTime date; // ✅ clean DateTime, no Timestamp dependency
  final String category;

  const UpdateCard({
    super.key,
    required this.title,
    required this.description,
    required this.date,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeBg = isDark ? const Color(0xFF001B52) : const Color(0xFFDDE9FB);
    final badgeText = Theme.of(context).colorScheme.primary;
    final titleColor = Theme.of(context).colorScheme.onSurface;
    final descColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final borderColor = Theme.of(context).dividerColor;

    final formattedDate = DateFormat('MMM dd, yyyy').format(date); // ✅ no cast needed

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: badgeText,
                            ),
                          ),
                        ),
                        Text(
                          formattedDate,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF888888)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: titleColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: descColor, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}