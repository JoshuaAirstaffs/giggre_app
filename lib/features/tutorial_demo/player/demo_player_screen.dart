import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../controller/demo_controller.dart';
import '../models/demo_sequence.dart';
import '../widgets/demo_chrome.dart';
import '../widgets/demo_theme.dart';

/// Full-screen host for one [DemoSequence]. Fully automatic — the sequence
/// starts playing the instant this screen mounts and advances itself via
/// [DemoController]. The only user actions available are leaving early
/// (Skip/Close) or watching again (Replay), never "Next".
class DemoPlayerScreen extends StatefulWidget {
  final DemoSequence sequence;

  const DemoPlayerScreen({super.key, required this.sequence});

  @override
  State<DemoPlayerScreen> createState() => _DemoPlayerScreenState();
}

class _DemoPlayerScreenState extends State<DemoPlayerScreen> {
  late final DemoController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DemoController(widget.sequence)..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DemoController>.value(
      value: _controller,
      // Forced light — this demo is meant to look like the real Giggre
      // screens regardless of the viewer's own dark-mode setting, and
      // several reused production widgets (e.g. `OfferedGigOfferCard`)
      // read `Theme.of(context)` for their colors.
      child: Theme(
        data: ThemeProvider.lightTheme,
        child: Scaffold(
          backgroundColor: dBg,
          body: DemoChrome(
            title: widget.sequence.title,
            child: Consumer<DemoController>(
              builder: (context, controller, _) {
                final step = widget.sequence.steps[controller.stepIndex];
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.03),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(step.id),
                    child: step.builder(context),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
