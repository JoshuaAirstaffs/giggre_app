import 'package:flutter/material.dart';

/// Keeps [child] mounted when a lazy list (SliverList, ListView) scrolls it
/// far off screen. Without this the list disposes it and rebuilds it from
/// scratch on the way back, e.g. a carousel re-fetching its slides and
/// restarting its video.
class KeepAliveWrapper extends StatefulWidget {
  const KeepAliveWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
