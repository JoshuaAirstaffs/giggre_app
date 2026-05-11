import 'dart:io';
import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Privacy & Security',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: onSurface,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kBlue,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Row(
              children: [
                Icon(Icons.lock_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy Policy',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Last updated: October 20, 2025',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _introductionCard(cardColor, onSurface),
          const SizedBox(height: 16),
          _dataWeCollect(cardColor, onSurface),
          const SizedBox(height: 16),
          _thirdPartyServices(cardColor, onSurface),
          const SizedBox(height: 24),
          _howWeUseYourData(cardColor, onSurface),
          const SizedBox(height: 24),
          _locationData(cardColor, onSurface),
          const SizedBox(height: 24),
          _dataSharing(cardColor, onSurface),
          const SizedBox(height: 24),
          _dataRetention(cardColor, onSurface),
          const SizedBox(height: 24),
          _yourRights(cardColor, onSurface),
          const SizedBox(height: 24),
          _childrensPrivacy(cardColor, onSurface),
          const SizedBox(height: 24),
          _security(cardColor, onSurface),
          const SizedBox(height: 24),
          _questionCard(),
          const SizedBox(height: 24),
          Text(
            '© 2026 Giggre. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(color: onSurface.withValues(alpha: 0.38), fontSize: 12),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

Widget _sectionCard({
  required Color cardColor,
  required Widget child,
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: child,
  );
}

Widget _sectionHeader(IconData icon, String title) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: kBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: kBlue, size: 20),
      ),
      const SizedBox(width: 12),
      Text(
        title,
        style: TextStyle(
          color: kBlue,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}

TextStyle _bodyStyle(Color onSurface) =>
    TextStyle(color: onSurface, fontSize: 12, height: 1.5);

Widget _introductionCard(Color cardColor, Color onSurface) {
  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.info_outline, '1. Introduction'),
        Text(
          'Welcome to Giggre - a gig economy platform connecting GigHost (employers) with GigWorkers (freelancers).\n\n'
          'This Privacy Policy explains how we collect, use, and protect your personal information when you use our services.\n\n'
          'Giggre is intended for users 18 years of age and older. We do not knowingly collect data from anyone under 18.',
          style: _bodyStyle(onSurface),
        ),
      ],
    ),
  );
}

Widget _dataWeCollect(Color cardColor, Color onSurface) {
  final content = [
    'Fullname - Profile display, gig listings, chat identity',
    'Email Address - Account creation and login',
    'Phone Number - Contact between GigHost and GigWorker',
    'Date of birth - Age verification (18+ requirement)',
    'Profile Photo - Profile Display',
    'GPS Location - Gig location display, worker tracking during active gig',
    'Camera & microphone - Audio and video calls between users',
    'Messages - In-app chat between GigHost and Gigworker',
    'Ratings and reviews - Worker and host reputations system.',
  ];

  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.dataset, '2. Data We Collect'),
        ...content.map((item) => Text(item, style: _bodyStyle(onSurface))),
      ],
    ),
  );
}

Widget _thirdPartyServices(Color cardColor, Color onSurface) {
  final content = [
    'Firebase Auth (Google LLC) - Account Verification',
    'Cloud Firestore (Google LLC) - Data (profiles, gigs, chats, etc.)',
    'Firebase Storage (Google LLC) - Profile photos and media',
    'Firebase Cloud Messaging (Google LLC) - Push Notifications',
    'Google Sign in (Google LLC) - OAuth authentication',
    'Agora RTC (Agora.io) - Realtime audio/video calls',
  ];

  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.handshake_outlined, '3. Third-Party Services'),
        ...content.map((item) => Text(item, style: _bodyStyle(onSurface))),
        Text(
          'These services have their own privacy policies governed by Google and Agora.io.',
          style: _bodyStyle(onSurface),
        ),
      ],
    ),
  );
}

Widget _howWeUseYourData(Color cardColor, Color onSurface) {
  final content = [
    'To create and manage your account',
    'To match GigWorkers with available gigs.',
    'To facilitate communication between GigCreators and GigWorkers.',
    'To track gig progress and worker location during active gigs.',
    'To process payments and manage transactions.',
    'To enforce our 18+ age requirement.',
    'To send app notifications (new gigs, messages, call alerts)',
    'To improve app performance and user experience',
  ];

  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.data_object, '4. How We Use Your Data'),
        ...content.map((item) => Text('• $item', style: _bodyStyle(onSurface))),
      ],
    ),
  );
}

Widget _locationData(Color cardColor, Color onSurface) {
  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.location_on, '5. Location Data'),
        Text('Giggre collects your GPS location in the following cases', style: _bodyStyle(onSurface)),
        Text('• GigHost: To pin the location of a gig job posting', style: _bodyStyle(onSurface)),
        Text('• GigWorker: To track your location during gig execution', style: _bodyStyle(onSurface)),
        Text(
          'Location tracking is only active during an active gig session. We do not track your location in the background outside of active gigs.',
          style: _bodyStyle(onSurface),
        ),
      ],
    ),
  );
}

Widget _dataSharing(Color cardColor, Color onSurface) {
  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.share, '6. Data Sharing'),
        Text(
          'We do not sell your personal data to third parties. We may share limited information with:',
          style: _bodyStyle(onSurface),
        ),
        Text('• The other party in a gig transaction (name and phone number shared between GigHost and GigWorker)', style: _bodyStyle(onSurface)),
        Text('• Firebase and Agora for app functionality', style: _bodyStyle(onSurface)),
        Text('• Law enforcement when required by law or to protect user safety', style: _bodyStyle(onSurface)),
      ],
    ),
  );
}

Widget _dataRetention(Color cardColor, Color onSurface) {
  final content = [
    'Your profile, gigs, and applications are permanently deleted',
    "Your chat messages are anonymized ('Deleted user')",
    "Your ratings given to others are anonymized ('Deleted User')",
    'Your Firebase Auth account is permanently deleted',
  ];

  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.history, '7. Data Retention'),
        Text(
          'We retain your data for as long as your account is active. When you delete your account:',
          style: _bodyStyle(onSurface),
        ),
        ...content.map((item) => Text('• $item', style: _bodyStyle(onSurface))),
      ],
    ),
  );
}

Widget _yourRights(Color cardColor, Color onSurface) {
  final content = [
    'Access: View your profile data within the app',
    'Correction: Update your name and profile information',
    'Deletion: Request permanent deletion of your account and data',
    'Data portability: Export your data in a structured format',
  ];

  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.gavel, '8. Your Rights'),
        ...content.map((item) => Text('• $item', style: _bodyStyle(onSurface))),
        Text('To exercise these rights, contact us at support@giggre.com', style: _bodyStyle(onSurface)),
      ],
    ),
  );
}

Widget _childrensPrivacy(Color cardColor, Color onSurface) {
  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.child_care, "9. Children's Privacy"),
        Text(
          'Giggre is strictly for users 18 years of age and older. We verify age during registration. If we discover a user under 18, we will immediately delete their account.',
          style: _bodyStyle(onSurface),
        ),
      ],
    ),
  );
}

Widget _security(Color cardColor, Color onSurface) {
  final content = [
    'All data stored on Google Firebase with industry-standard encryption.',
    'Authentication handled by Google Firebase Authentication.',
    'HTTPS enforced on all connections',
  ];

  return _sectionCard(
    cardColor: cardColor,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        _sectionHeader(Icons.security, '10. Security'),
        ...content.map((item) => Text('• $item', style: _bodyStyle(onSurface))),
      ],
    ),
  );
}

Widget _questionCard() {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.shade50,
      border: Border.all(color: Colors.orange.shade200),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(Icons.mail_outline, color: Colors.orange),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Questions about your privacy? Contact us at support@giggre.com',
            style: TextStyle(color: Colors.black87, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}