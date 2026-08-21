import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../controller/demo_audio_controller.dart';
import '../controller/demo_controller.dart';
import 'demo_theme.dart';

/// Shared chrome for the demo player: segmented progress bar, step counter,
/// Skip/Close controls, and a Replay/Done card once the sequence finishes.
/// The demo never *requires* a tap to continue — it keeps auto-advancing on
/// its own timer regardless — but tapping anywhere in the content area is
/// an optional shortcut to jump to the next step early.
///
/// The header is a real flex child above the content (not an overlay), so
/// it can never cover anything the current step renders underneath it.
class DemoChrome extends StatelessWidget {
  final String title;
  final Widget child;
  final DemoAudioController? audioController;

  const DemoChrome({
    super.key,
    required this.title,
    required this.child,
    this.audioController,
  });

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DemoController>();

    return Stack(
      children: [
        Column(
          children: [
            SafeArea(
              bottom: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: dCard,
                  border: Border(bottom: BorderSide(color: dBorder)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _ChromeIconButton(
                          icon: Icons.close_rounded,
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        if (audioController != null) ...[
                          const SizedBox(width: 10),
                          _MuteButton(controller: audioController!),
                        ],
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: dTitle,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${controller.stepIndex + 1} / ${controller.stepCount}',
                          style: const TextStyle(
                            color: dBody,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: dBody,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(controller.stepCount, (i) {
                        final active = i <= controller.stepIndex;
                        return Expanded(
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            height: 3,
                            decoration: BoxDecoration(
                              color: active ? kGold : dBorder,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                key: const Key('demoTapToAdvance'),
                behavior: HitTestBehavior.translucent,
                onTap: controller.isCompleted ? null : controller.skipToNext,
                child: child,
              ),
            ),
          ],
        ),
        if (controller.isCompleted)
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: _CompletedCard(controller: controller),
            ),
          ),
      ],
    );
  }
}

/// Mute/unmute toggle for the demo's narration and background music.
/// Listens directly to [DemoAudioController] (a plain [ChangeNotifier])
/// rather than through Provider, since only [DemoChrome] needs it.
class _MuteButton extends StatelessWidget {
  final DemoAudioController controller;
  const _MuteButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _ChromeIconButton(
        icon: controller.isMuted
            ? Icons.volume_off_rounded
            : Icons.volume_up_rounded,
        onTap: controller.toggleMute,
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ChromeIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(color: dBg, shape: BoxShape.circle),
        child: Icon(icon, color: dBody, size: 18),
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  final DemoController controller;
  const _CompletedCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: dProgressStatus.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              color: dProgressStatus,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            "That's the demo!",
            style: TextStyle(
              color: dTitle,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Watch it again or head back to pick another one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: dBody, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: controller.replay,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: dTitle,
                    side: const BorderSide(color: dBorder),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Replay'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
