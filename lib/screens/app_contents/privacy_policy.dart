import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/theme_provider.dart';
import 'package:provider/provider.dart';

class PrivacyPolicy extends StatefulWidget {
  PrivacyPolicy({Key? key}) : super(key: key);

  @override
  _PrivacyPolicyState createState() => _PrivacyPolicyState();
}



class _PrivacyPolicyState extends State<PrivacyPolicy> {
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
        child: SingleChildScrollView(
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
                          Text('Last updated: October 20, 2025', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                _PrivacyPolicyCard(
                  title: 'Our Commitment to Your Privacy',
                  content: 'At Giggre, we are committed to protecting your privacy and ensuring the security of your personal information. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application.',
                ),
                _PrivacyPolicyCard(
                  title: 'Information We Collect',
                  content: 'We may collect personal information such as your name, email address, and profile details when you create an account. We also collect usage data, such as your interactions with the app, to improve your experience.',
                ),
                _PrivacyPolicyCard(
                  title: 'How We Use Your Information',
                  content: 'We use the information we collect to provide and improve our services, personalize your experience, and communicate with you about updates and offers.',
                ),
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