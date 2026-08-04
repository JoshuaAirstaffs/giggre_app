import 'package:flutter/material.dart';
import 'dev_options_sheet.dart';

/// An invisible tap target meant to sit in the bottom-right corner of a
/// screen (wrap in a Stack + Positioned at the call site). Five taps within
/// [_tapWindow] of each other opens the Developer Options modal; a pause
/// longer than that resets the count, so it takes a deliberate, quick burst
/// rather than five taps scattered across a normal reading session.
class DevModeEntryPoint extends StatefulWidget {
  const DevModeEntryPoint({super.key});

  @override
  State<DevModeEntryPoint> createState() => _DevModeEntryPointState();
}

class _DevModeEntryPointState extends State<DevModeEntryPoint> {
  static const _requiredTaps = 5;
  static const _tapWindow = Duration(milliseconds: 1500);

  int _tapCount = 0;
  DateTime? _lastTapAt;

  void _onTap() {
    final now = DateTime.now();
    final withinWindow =
        _lastTapAt != null && now.difference(_lastTapAt!) <= _tapWindow;
    _tapCount = withinWindow ? _tapCount + 1 : 1;
    _lastTapAt = now;

    if (_tapCount >= _requiredTaps) {
      _tapCount = 0;
      _lastTapAt = null;
      DevOptionsSheet.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: const SizedBox(width: 48, height: 48),
    );
  }
}
