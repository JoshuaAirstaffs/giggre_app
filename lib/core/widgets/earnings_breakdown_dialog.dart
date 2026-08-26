import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/currency_formatter.dart';

// Shared by the Home dashboard's "Earned so far" card and the Profile tab's
// "Total earned" stat — both only ever show ONE currency's amount up front
// (see each caller), so this is where a worker paid in more than one
// currency can see the full per-currency breakdown instead of the other
// totals being hidden or crammed in unlabeled.
Future<void> showEarningsBreakdownDialog(
  BuildContext context,
  Map<String, double> byCurrency,
) {
  final rows = (byCurrency.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key)));
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Theme.of(ctx).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.payments_rounded, color: kBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Earnings by currency',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              "You've been paid in more than one currency, so these are "
              "kept as separate totals rather than converted together.",
              style: TextStyle(color: kSub, fontSize: 12.5, height: 1.4),
            ),
          ),
          for (final e in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      e.key,
                      style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(e.value, e.key),
                    style: const TextStyle(
                      color: kBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close', style: TextStyle(color: kSub)),
        ),
      ],
    ),
  );
}
