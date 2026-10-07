import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:giggre_app/core/providers/current_user_provider.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:giggre_app/features/call/call_log.dart';
import 'package:giggre_app/features/call/call_service.dart';
import 'package:giggre_app/features/call/voice_call_screen.dart';
import 'package:giggre_app/features/call/video_call_screen.dart';
import 'package:giggre_app/helpers/snackbar_helper.dart';

enum CallType { voice, video }

/// Starts a voice/video call to [targetUserId] and, when [gigId] is set,
/// logs how it ended into that gig's chat (see call_log.dart). Shared by
/// CallUserAction's icon button and the chat's "Call back" on a call card.
/// Returns once the call screen has closed.
Future<void> placeCall({
  required BuildContext context,
  required String targetUserId,
  required String targetUserName,
  required bool isVideo,
  String? gigId,
  bool? viewerIsWorker,
  void Function(bool)? setLoading,
}) async {
  final myName = context.read<CurrentUserProvider>().currentName ?? '';
  final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  final channelName = '${uid}_${DateTime.now().millisecondsSinceEpoch}';

  final result = await initiateCall(
    context: context,
    targetUserId: targetUserId,
    channelName: channelName,
    isVideo: isVideo,
    setLoading: setLoading ?? (_) {},
    buildScreen: (ch, tk) => isVideo
        ? VideoCallScreen(channelName: ch, token: tk)
        : VoiceCallScreen(channelName: ch, token: tk),
  );

  if (result != null && gigId != null) {
    await logCallToGigChat(
      gigId: gigId,
      peerUid: targetUserId,
      peerName: targetUserName,
      myName: myName,
      viewerIsWorker: viewerIsWorker,
      isVideo: isVideo,
      result: result,
    );
  }
}

class CallUserAction extends StatefulWidget {
  const CallUserAction({
    super.key,
    required this.targetUserId,
    required this.targetUserName,
    required this.callType,
    this.iconColor,
    this.gigId,
    this.viewerIsWorker,
  });

  final String targetUserId;
  final String targetUserName;
  final CallType callType;
  // Overrides the default icon color (purple for video, kBlue for voice).
  // Null preserves today's look everywhere this widget is already used.
  final Color? iconColor;
  // When set, the finished call (completed/declined/missed) is logged as a
  // message in this gig's chat room — see call_log.dart. viewerIsWorker is
  // only used if that room has to be created, same as GigChatParams.
  final String? gigId;
  final bool? viewerIsWorker;

  @override
  State<CallUserAction> createState() => _CallUserActionState();
}

class _CallUserActionState extends State<CallUserAction>
    with SingleTickerProviderStateMixin {
  bool _isCalling = false;
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

  bool get _isVideo => widget.callType == CallType.video;
  Color get _callColor =>
      widget.iconColor ?? (_isVideo ? Colors.purple : kBlue);
  IconData get _callIcon =>
      _isVideo ? Icons.videocam_rounded : Icons.call_rounded;

  Future<void> _startCall() => placeCall(
    context: context,
    targetUserId: widget.targetUserId,
    targetUserName: widget.targetUserName,
    isVideo: _isVideo,
    gigId: widget.gigId,
    viewerIsWorker: widget.viewerIsWorker,
    setLoading: (v) {
      if (mounted) setState(() => _isCalling = v);
    },
  );

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