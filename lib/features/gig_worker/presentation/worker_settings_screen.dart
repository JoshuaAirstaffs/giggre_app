import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/delete_account_service.dart';
import 'widgets/worker_widgets.dart';

class WorkerSettingsScreen extends StatelessWidget {
  const WorkerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: TextStyle(
            color: onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1,
              color: isDark ? kBorder : const Color(0xFFE2E8F0)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          const SectionLabel('ACCOUNT'),
          const SizedBox(height: 8),
          MenuCard(children: [
            MenuRow(
              icon: Icons.delete_outline_rounded,
              iconColor: Colors.redAccent,
              label: 'Delete Account',
              labelColor: Colors.redAccent,
              onTap: () => DeleteAccountService.deleteAccount(context),
              showArrow: false,
            ),
          ]),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Deleting your account is permanent and cannot be undone. All your data, including your worker profile, will be removed from Giggre.',
              style: const TextStyle(
                  color: kSub, fontSize: 12, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}
