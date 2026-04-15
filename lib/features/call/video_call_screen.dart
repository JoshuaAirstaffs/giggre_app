import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoCallScreen extends StatefulWidget {
  final String channelName;
  final String token;

  const VideoCallScreen({
    super.key,
    required this.channelName,
    required this.token,
  });

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen>
    with SingleTickerProviderStateMixin {
  RtcEngine? _engine;

  bool _isMuted = false;
  bool _isCameraOff = false;
  bool _isFrontCamera = true;
  bool _remoteUserJoined = false;
  bool _remoteCameraOff = false;
  bool _isConnecting = true;

  int? _remoteUid;
  int _callSeconds = 0;
  Timer? _callTimer;

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

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
  }

  Future<void> _initAgora() async {
    await [Permission.microphone, Permission.camera].request();

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(const RtcEngineContext(appId: _appId));

    _engine!.registerEventHandler(RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        if (mounted) setState(() => _isConnecting = false);
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        if (mounted) {
          setState(() {
            _remoteUid = remoteUid;
            _remoteUserJoined = true;
          });
          _startTimer();
        }
      },
      onUserOffline: (connection, remoteUid, reason) {
        if (mounted) {
          setState(() {
            _remoteUid = null;
            _remoteUserJoined = false;
            _remoteCameraOff = false;
          });
        }
        _endCall();
      },
      onRemoteVideoStateChanged: (connection, remoteUid, state, reason, elapsed) {
        if (mounted) {
          setState(() {
            _remoteCameraOff =
                state == RemoteVideoState.remoteVideoStateStopped ||
                state == RemoteVideoState.remoteVideoStateFrozen;
          });
        }
      },
      onError: (err, msg) => debugPrint('❌ VIDEO Agora error: $err - $msg'),
    ));

    await _engine!.enableVideo();
    await _engine!.enableAudio();
    await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    await _engine!.startPreview();

    await _engine!.joinChannel(
      token: widget.token,
      channelId: widget.channelName,
      uid: 0,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
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
    await _engine?.muteLocalAudioStream(_isMuted);
  }

  Future<void> _toggleCamera() async {
    setState(() => _isCameraOff = !_isCameraOff);
    await _engine?.muteLocalVideoStream(_isCameraOff);
  }

  Future<void> _switchCamera() async {
    setState(() => _isFrontCamera = !_isFrontCamera);
    await _engine?.switchCamera();
  }

  Future<void> _endCall() async {
    _callTimer?.cancel();
    await _engine?.leaveChannel();
    await _engine?.release();
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _callTimer?.cancel();
    _pulseController.dispose();
    _engine?.leaveChannel();
    _engine?.release();
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

  Widget _buildRemotePlaceholder({bool cameraOff = false}) {
    return Container(
      color: _bg,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (_, child) => Transform.scale(
                scale: cameraOff ? 1.0 : _pulseAnimation.value,
                child: child,
              ),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _blue.withValues(alpha: 0.15),
                  border: Border.all(
                    color: _blue.withValues(alpha: 0.6),
                    width: 2,
                  ),
                ),
                child: Icon(
                  cameraOff
                      ? Icons.videocam_off_rounded
                      : Icons.person_rounded,
                  size: 48,
                  color: const Color(0xFFB5D4F4),
                ),
              ),
            ),
            if (cameraOff) ...[
              const SizedBox(height: 16),
              Text(
                'Camera is off',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // final showRemoteVideo =
    //     _remoteUserJoined && _remoteUid != null && _engine != null && !_remoteCameraOff;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned.fill(
  child: _buildRemotePlaceholder(
    cameraOff: _remoteUserJoined,
  ),
),
          // ── Remote video / fallback ────────────────────────
          // Positioned.fill(
          //   child: showRemoteVideo
          //       ? AgoraVideoView(
          //           controller: VideoViewController.remote(
          //             rtcEngine: _engine!,
          //             canvas: VideoCanvas(uid: _remoteUid),
          //             connection:
          //                 RtcConnection(channelId: widget.channelName),
          //           ),
          //         )
          //       : _buildRemotePlaceholder(
          //           cameraOff: _remoteUserJoined && _remoteCameraOff,
          //         ),
          // ),

          // ── Local video (picture-in-picture) ───────────────
          Positioned(
            top: 60,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 110,
                height: 160,
                child: _isCameraOff || _engine == null
                    ? Container(
                        color: Colors.grey[850],
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.videocam_off_rounded,
                              color: Colors.white38,
                              size: 28,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Cam off',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      )
                    : AgoraVideoView(
                        controller: VideoViewController(
                          rtcEngine: _engine!,
                          canvas: const VideoCanvas(uid: 0),
                        ),
                      ),
              ),
            ),
          ),

          // ── Top bar ────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _endCall,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.4),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 0.5,
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 16,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        children: [
                          Text(
                            widget.channelName,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 400),
                            child: _remoteUserJoined
                                ? Text(
                                    _callDuration,
                                    key: const ValueKey('duration'),
                                    style: const TextStyle(
                                      color: Color(0xFF66BB6A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.2,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  )
                                : Row(
                                    key: const ValueKey('status'),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_isConnecting)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              right: 6),
                                          child: SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: _statusColor,
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin: const EdgeInsets.only(
                                              right: 6),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _statusColor,
                                          ),
                                        ),
                                      Text(
                                        _statusLabel,
                                        style: TextStyle(
                                          color: _statusColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(width: 36),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Controls ─────────────────────────────────
                Container(
                  margin: const EdgeInsets.only(
                      left: 24, right: 24, bottom: 48),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _VideoControlButton(
                        icon: _isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        active: _isMuted,
                        onTap: _toggleMute,
                      ),
                      _VideoControlButton(
                        icon: _isCameraOff
                            ? Icons.videocam_off_rounded
                            : Icons.videocam_rounded,
                        label: _isCameraOff ? 'Cam off' : 'Cam on',
                        active: _isCameraOff,
                        onTap: _toggleCamera,
                      ),
                      GestureDetector(
                        onTap: _endCall,
                        child: Column(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFE53935),
                              ),
                              child: const Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'End',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _VideoControlButton(
                        icon: Icons.cameraswitch_rounded,
                        label: 'Flip',
                        active: false,
                        onTap: _switchCamera,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  static const _blue = Color(0xFF4A90D9);

  const _VideoControlButton({
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? _blue.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}