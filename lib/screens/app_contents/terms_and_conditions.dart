import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/theme_provider.dart';
import 'package:provider/provider.dart';

class TermsAndConditions extends StatefulWidget {
  const TermsAndConditions({Key? key}) : super(key: key);

  @override
  _TermsAndConditionsState createState() => _TermsAndConditionsState();
}

class _TermsAndConditionsState extends State<TermsAndConditions> {
  @override

  Widget build(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text('Terms & Conditions', style: TextStyle(color: onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                      Icon(Icons.info_outline, color: Colors.white),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Terms and Conditions', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                          Text('Last updated: October 20, 2025', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                _TermsAndConditionsCard(
                  title: 'Terms and Conditions',
                  content: 'These terms and conditions outline the rules and regulations for the use of Giggre\'s Website, located at giggre.com.',
                ),
                _TermsAndConditionsCard(
                  title: 'Privacy Policy',
                  content: 'This privacy policy will explain how we use the personal data we collect from you when you use our website.',
                ),
                _TermsAndConditionsCard(
                  title: 'Cookie Policy',
                  content: 'Our website uses cookies to distinguish you from other users of our website. This helps us to provide you with a good experience when you browse our website.',
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, 255, 191, 94),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color:  Color.fromARGB(255, 255, 149, 0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Color.fromARGB(255, 255, 149, 0), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'By using our services, you agree to these terms and conditions.',
                          style: TextStyle(color: Colors.black, fontSize: 12),
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

class _TermsAndConditionsCard extends StatelessWidget {
  const _TermsAndConditionsCard({
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
