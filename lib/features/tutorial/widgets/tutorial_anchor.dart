import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controller/tutorial_controller.dart';

/// Wraps a real widget so the tutorial can spotlight it. Registers its key
/// with [TutorialController] on mount and unregisters on dispose — the
/// controller never needs to be told which screen or sheet this lives in.
class TutorialAnchor extends StatefulWidget {
  final String id;
  final Widget child;
  const TutorialAnchor({required this.id, required this.child, super.key});

  @override
  State<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends State<TutorialAnchor> {
  final GlobalKey _key = GlobalKey();
  TutorialController? _controller;

  @override
  void initState() {
    super.initState();
    context.read<TutorialController>().registerAnchor(widget.id, _key);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = context.read<TutorialController>();
  }

  @override
  void dispose() {
    _controller?.unregisterAnchor(widget.id, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
