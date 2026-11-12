import 'package:flutter/material.dart';

/// House button at the top-left of the Gig Worker / Gig Host dashboard
/// headers (Option A of the bottom-nav mockup): leaves the dashboard for the
/// Home screen ("Choose a mode to get started"). Same size and style as the
/// headers' back button.
class HeaderHomeButton extends StatelessWidget {
  final VoidCallback onTap;
  const HeaderHomeButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Home',
      child: Semantics(
        button: true,
        label: 'Home',
        child: Material(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: const SizedBox(
              width: 34,
              height: 34,
              child: Icon(Icons.home_rounded, color: Colors.white, size: 19),
            ),
          ),
        ),
      ),
    );
  }
}
