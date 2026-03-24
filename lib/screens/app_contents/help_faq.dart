import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/core/theme/theme_provider.dart';
import 'package:provider/provider.dart';

class HelpFaq extends StatefulWidget {
  HelpFaq({Key? key}) : super(key: key);

  @override
  _HelpFaqState createState() => _HelpFaqState();
}

class _HelpFaqState extends State<HelpFaq> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'Help & FAQ',
          style: TextStyle(
            color: onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
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
                      Icon(Icons.help_outline, color: Colors.white),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 4,
                        children: [
                          Text(
                            'Help & FAQ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Get answers to common questions',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.only(left: 4),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFFFBBF24), width: 4),
                    ),
                  ),
                  child: Text(
                    "General",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _HelpFaqCard(
                  title: 'What is Giggre?',
                  content:
                      'Giggre is a platform where freelancers can showcase their skills and find clients for their services.',
                ),
                _HelpFaqCard(
                  title: "Is Giggre free to use?",
                  content:
                      "Yes, Giggre is free to use for both freelancers and clients.",
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.only(left: 4),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFFFBBF24), width: 4),
                    ),
                  ),
                  child: Text(
                    "GigHost",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _HelpFaqCard(
                  title: "How do I create a gig?",
                  content:
                      "You can create a gig by clicking on the 'Create Gig' button on the home page.",
                ),
                _HelpFaqCard(
                  title: "Can I choose which clients to work with?",
                  content:
                      "Yes, you can review client profiles and choose which projects to accept.",
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.only(left: 4),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFFFBBF24), width: 4),
                    ),
                  ),
                  child: Text(
                    "GigWorker",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _HelpFaqCard(
                  title: "How do I find gigs?",
                  content:
                      "You can browse gigs in the 'Explore' section or use the search function.",
                ),
                _HelpFaqCard(
                  title: "Can I apply to multiple gigs?",
                  content:
                      "Yes, you can apply to multiple gigs that match your skills.",
                ),
                SizedBox(height: 4),
                Container(
                  padding: EdgeInsets.only(left: 4),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFFFBBF24), width: 4),
                    ),
                  ),
                  child: Text(
                    "Account",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _HelpFaqCard(
                  title: "How do I sign up?",
                  content:
                      "You can sign up by clicking on the 'Sign Up' button on the home page.",
                ),
                _HelpFaqCard(
                  title: "Can I change my account details?",
                  content:
                      "Yes, you can change your account details by clicking on the 'Settings' button on the home page.",
                ),
                SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Color.fromARGB(255, 255, 191, 94)
                        : Color.fromARGB(255, 255, 231, 194),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Color.fromARGB(255, 255, 149, 0)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.support_agent_outlined,
                        color: isDark
                            ? Colors.black
                            : Color.fromARGB(255, 255, 149, 0),
                        size: 40,
                      ),  
                      const SizedBox(height: 8),
                      Text("Still need help?", 
                        style: TextStyle(
                          color: isDark ? Colors.black : onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Contact our support team and we\'ll get back to you as soon as possible.',
                        style: TextStyle(
                          color: isDark ? Colors.black : onSurface,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                       const SizedBox(height: 12),
                       ElevatedButton(
                        onPressed: () {
                          // TODO: Open support chat or email
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: Size(double.infinity, 48),
                          backgroundColor:  Color.fromARGB(255, 255, 149, 0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Contact Support'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HelpFaqCard extends StatefulWidget {
  const _HelpFaqCard({super.key, required this.title, required this.content});

  final String title;
  final String content;

  @override
  State<_HelpFaqCard> createState() => _HelpFaqCardState();
}

class _HelpFaqCardState extends State<_HelpFaqCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconBg = isDark ? const Color(0xFF001B52) : const Color(0xFFEBF0FB);
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color.fromARGB(255, 6, 50, 97) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.transparent
                  : const Color.fromARGB(
                      255,
                      221,
                      221,
                      221,
                    ).withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _expanded ? Icons.remove : Icons.add,
                    color: isDark ? Colors.white : kBlue,
                    size: 16,
                  ),
                ),
              ],
            ),

            // Expandable content
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: _expanded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          widget.content,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
