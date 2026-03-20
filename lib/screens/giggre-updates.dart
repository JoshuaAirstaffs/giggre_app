import 'package:flutter/material.dart';
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
            children: const [
              UpdateCard(
                title: "Welcome to Giggre!",
                icon: Icons.update,
                date: "2025-10-15",
                category: "Announcement",
                description:
                    "We are officially launching Giggre! We're excited to bring you the best gig economy platform. Join us and start your journey today!",
              ),
              UpdateCard(
                title: "New Feature: Giggre Rewards",
                icon: Icons.star,
                date: "2025-10-15",
                category: "Feature",
                description:
                    "We've added a new feature to Giggre! You can now earn rewards for completing gigs and referrals. Check it out and start earning today!",
              ),
              UpdateCard(
                title: "New Feature: Giggre Rewards",
                icon: Icons.star,
                date: "2025-10-15",
                category: "Feature",
                description:
                    "We've added a new feature to Giggre! You can now earn rewards for completing gigs and referrals. Check it out and start earning today!",
              ),
            ],
          ),
        ),
      ),
    );
  }
}
