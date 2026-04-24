import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceCallScreen extends StatefulWidget {
  final String channelName;
  final String token;

  const VoiceCallScreen({
    super.key,
    required this.channelName,
    required this.token,
  });

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with SingleTickerProviderStateMixin {
  late final RtcEngine _engine;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  final AudioPlayer _ringbackPlayer = AudioPlayer();

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _remoteUserJoined = false;
  bool _isConnecting = true;
  bool _isEnding = false; // guard against double-end

  int _callSeconds = 0;
  Timer? _callTimer;
  StreamSubscription<DocumentSnapshot>? _outgoingCallSub;

  static const _appId = '75426b0c60784c2ebd9ab32cfcc5288f';
  static const _bg = Color(0xFF121212);
  static const _blue = Color(0xFF4A90D9);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initAgora();
    _listenForDecline();
  }

  // ── Listen for callee declining ────────────────────────────────────────────
  void _listenForDecline() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _outgoingCallSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final status = snap.data()?['outgoingCall']?['status'];
      if (status == 'declined' && mounted) {
        _endCall();
      }
    });
  }

  Future<void> _startRingback() async {
    await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
    await _ringbackPlayer
        .play(AssetSource('sounds/waiting_to_answer_sound.mp3'));
  }

  Future<void> _stopRingback() async {
    await _ringbackPlayer.stop();
  }

  Future<void> _initAgora() async {
    await Permission.microphone.request();

    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(appId: _appId));

    _engine.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        if (mounted) {
          setState(() => _isConnecting = false);
          _startRingback();
        }
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        if (mounted) {
          _stopRingback();
          setState(() => _remoteUserJoined = true);
          _startTimer();
        }
      },
      onUserOffline: (connection, remoteUid, reason) {
        if (mounted) setState(() => _remoteUserJoined = false);
        _endCall();
      },
      onError: (err, msg) => debugPrint('Agora error: $err - $msg'),
    ));

    await _engine.enableAudio();
    await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine.joinChannel(
      token: widget.token,
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
      ),
    );
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callSeconds = 0;
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String get _callDuration {
    final h = _callSeconds ~/ 3600;
    final m = (_callSeconds % 3600 ~/ 60).toString().padLeft(2, '0');
    final s = (_callSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    await _engine.muteLocalAudioStream(_isMuted);
  }

  Future<void> _toggleSpeaker() async {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    await _engine.setEnableSpeakerphone(_isSpeakerOn);
  }

  Future<void> _endCall() async {
    if (_isEnding) return;
    _isEnding = true;

    _callTimer?.cancel();
    _outgoingCallSub?.cancel();
    await _stopRingback();
    await _ringbackPlayer.dispose();
    await _engine.leaveChannel();
    await _engine.release();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final firestore = FirebaseFirestore.instance;

      // Always read targetId before wiping outgoingCall
      final mySnap = await firestore.collection('users').doc(uid).get();
      final targetId = mySnap.data()?['outgoingCall']?['targetId'] as String?;

      final batch = firestore.batch();

      // Always clean up caller's outgoingCall
      batch.update(
        firestore.collection('users').doc(uid),
        {'outgoingCall': FieldValue.delete()},
      );

      // If callee still has our incomingCall, delete it so their screen closes
      if (targetId != null) {
        batch.update(
          firestore.collection('users').doc(targetId),
          {'incomingCall': FieldValue.delete()},
        );
      }

      await batch.commit();
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _outgoingCallSub?.cancel();
    _pulseController.dispose();
    _ringbackPlayer.dispose();
    _engine.leaveChannel();
    _engine.release();
    super.dispose();
  }

  String get _statusLabel {
    if (_isConnecting) return 'Connecting...';
    if (_remoteUserJoined) return 'Connected';
    return 'Waiting...';
  }

  Color get _statusColor {
    if (_isConnecting) return Colors.white38;
    if (_remoteUserJoined) return const Color(0xFF66BB6A);
    return const Color(0xFFFFA726);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _endCall,
                    icon: Icon(
                      Icons.arrow_back_ios_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Voice Call',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            const Spacer(),

            // ── Avatar ───────────────────────────────────────
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (_, child) => Transform.scale(
                scale: _pulseAnimation.value,
                child: child,
              ),
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _blue.withValues(alpha: 0.15),
                  border: Border.all(
                    color: _remoteUserJoined
                        ? const Color(0xFF66BB6A).withValues(alpha: 0.7)
                        : _blue.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 52,
                  color: Color(0xFFB5D4F4),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Title ────────────────────────────────────────
            const Text(
              'Voice Call',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 10),

            // ── Status or duration ───────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: _remoteUserJoined
                  ? Text(
                      _callDuration,
                      key: const ValueKey('duration'),
                      style: const TextStyle(
                        color: Color(0xFF66BB6A),
                        fontSize: 22,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    )
                  : Row(
                      key: const ValueKey('status'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isConnecting)
                          Padding(
                            padding: const EdgeInsets.only(right: 7),
                            child: SizedBox(
                              width: 11,
                              height: 11,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: _statusColor,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(right: 7),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _statusColor,
                            ),
                          ),
                        Text(
                          _statusLabel,
                          style: TextStyle(
                            color: _statusColor,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
            ),

            const Spacer(),

            // ── Controls ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ControlButton(
                    icon: _isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    label: _isMuted ? 'Unmute' : 'Mute',
                    active: _isMuted,
                    onTap: _toggleMute,
                  ),
                  _EndCallButton(onTap: _endCall),
                  _ControlButton(
                    icon: _isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_down_rounded,
                    label: _isSpeakerOn ? 'Speaker' : 'Earpiece',
                    active: _isSpeakerOn,
                    onTap: _toggleSpeaker,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 52),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  static const _blue = Color(0xFF4A90D9);

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? _blue : Colors.white24,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;

  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFFE53935),
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'End',
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}