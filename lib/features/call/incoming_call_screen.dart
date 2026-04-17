import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:giggre_app/features/call/voice_call_screen.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callerId;
  final String callerName;
  final String callerRole;
  final String channelName;
  final String token;

  const IncomingCallScreen({
    super.key,
    required this.callerId,
    required this.callerName,
    this.callerRole = 'Gig worker',
    required this.channelName,
    required this.token,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<DocumentSnapshot>? _callSub;

  static const _bg = Color(0xFF121212);
  static const _blue = Color(0xFF4A90D9);

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startRingtone();
    _listenForCancellation();
  }

  // Dismiss automatically if the caller hangs up before answer
  void _listenForCancellation() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _callSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final incomingCall = snap.data()?['incomingCall'];
      if (incomingCall == null && mounted) {
        _callSub?.cancel();
        _audioPlayer.stop();
        Navigator.pop(context);
      }
    });
  }

  Future<void> _startRingtone() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/incoming_call_sound.mp3'));
  }

  Future<void> _stopRingtone() async {
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _pulseController.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  String get _initials {
    final parts = widget.callerName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0].substring(0, parts[0].length.clamp(0, 2)).toUpperCase();
  }

  Future<void> _acceptCall() async {
    _callSub?.cancel();
    await _stopRingtone();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'incomingCall.status': 'accepted'});

    if (!mounted) return;

    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => VoiceCallScreen(
          channelName: widget.channelName,
          token: widget.token,
        ),
      ),
    );

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'incomingCall': FieldValue.delete()});
  }

  Future<void> _declineCall() async {
    _callSub?.cancel();
    await _stopRingtone();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    batch.update(
      firestore.collection('users').doc(uid),
      {'incomingCall': FieldValue.delete()},
    );

    batch.update(
      firestore.collection('users').doc(widget.callerId),
      {'outgoingCall.status': 'declined'},
    );

    await batch.commit();

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),

            Text(
              'Incoming Voice Call',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.45),
                letterSpacing: 0.4,
              ),
            ),

            const SizedBox(height: 48),

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
                    color: _blue.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFB5D4F4),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.callerRole,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ActionButton(
                    icon: Icons.call_end_rounded,
                    label: 'Decline',
                    color: const Color(0xFFE53935),
                    onTap: _declineCall,
                  ),
                  _ActionButton(
                    icon: Icons.call_rounded,
                    label: 'Accept',
                    color: const Color(0xFF43A047),
                    onTap: _acceptCall,
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}