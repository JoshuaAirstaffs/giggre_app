import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/widgets/update_card.dart';

class GiggreUpdates extends StatefulWidget {
  GiggreUpdates({Key? key}) : super(key: key);

  @override
  _GiggreUpdatesState createState() => _GiggreUpdatesState();
}

class _GiggreUpdatesState extends State<GiggreUpdates> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white), // ← add this
        title: const Text(
          'Giggre Updates',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            spacing: 16,
            children: [
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
