import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/call/call_service.dart';
import 'package:giggre_app/features/call/voice_call_screen.dart';
import 'package:giggre_app/features/call/video_call_screen.dart';
import 'package:giggre_app/helpers/snackbar_helper.dart';

enum CallType { voice, video }

class CallUserAction extends StatefulWidget {
  const CallUserAction({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.callType,
    this.token = '',
  });

  final String targetUserId;
  final String targetUserName;
  final CallType callType;
  final String token;

  @override
  State<CallUserAction> createState() => _CallUserActionState();
}

class _CallUserActionState extends State<CallUserAction>
    with SingleTickerProviderStateMixin {
  bool _isCalling = false;
  late String _channelName = _makeChannel();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  Stream<bool> _targetOnCallStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('userId', isEqualTo: widget.targetUserId)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return false;
      final data = snap.docs.first.data();
      final incoming = data['incomingCall'] as Map<String, dynamic>?;
      final outgoing = data['outgoingCall'] as Map<String, dynamic>?;
      return incoming != null || outgoing != null;
    });
  }

  static String _makeChannel() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    return '${uid}_${DateTime.now().millisecondsSinceEpoch}';
  }

  bool get _isVideo => widget.callType == CallType.video;
  Color get _callColor => _isVideo ? Colors.purple : kBlue;
  IconData get _callIcon =>
      _isVideo ? Icons.videocam_rounded : Icons.call_rounded;

  Future<void> _startCall() async {
    await initiateCall(
      context: context,
      targetUserId: widget.targetUserId,
      channelName: _channelName,
      token: widget.token,
      isVideo: _isVideo,
      setLoading: (v) {
        if (mounted) setState(() => _isCalling = v);
        if (!v && mounted) setState(() => _channelName = _makeChannel());
      },
      buildScreen: (ch, tk) => _isVideo
          ? VideoCallScreen(channelName: ch, token: tk)
          : VoiceCallScreen(channelName: ch, token: tk),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _targetOnCallStream(),
      builder: (context, snapshot) {
        final isTargetOnCall = snapshot.data ?? false;

        if (isTargetOnCall) {
          return GestureDetector(
            onTap: () => SnackbarHelper.showWarning(context, 'User is currently on a call'),
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _pulseAnimation.value,
                  child: const Icon(
                    Icons.wifi_calling_3_rounded,
                    color: Colors.orange,
                    size: 22,
                  ),
                );
              },
            ),
          );
        }

        return IconButton(
          onPressed: _isCalling ? null : _startCall,
          icon: _isCalling
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _callColor,
                  ),
                )
              : Icon(_callIcon, color: _callColor, size: 22),
        );
      },
    );
  }
}