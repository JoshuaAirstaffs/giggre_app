import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tutorial_region.dart';
import 'tutorial_video_player_screen.dart';
import 'tutorial_videos_service.dart';

/// "Watch how it works" — a horizontal row of the admin's tutorial videos for
/// [placement]. Takes no space at all while there are none (or while
/// loading), so screens can drop it in unconditionally. Each video is shown
/// in Tagalog to users in the Philippines when the admin added a Tagalog
/// version, otherwise in English (TutorialRegion).
class TutorialVideosRow extends StatefulWidget {
  const TutorialVideosRow({
    super.key,
    required this.placement,
    this.title = 'Watch how it works',
    this.padding = EdgeInsets.zero,
    this.textColor,
    this.mutedColor,
    this.cardColor,
    this.borderColor,
  });

  final TutorialPlacement placement;
  final String title;

  /// Applied only when the row is shown.
  final EdgeInsets padding;
  final Color? textColor;
  final Color? mutedColor;
  final Color? cardColor;
  final Color? borderColor;

  @override
  State<TutorialVideosRow> createState() => _TutorialVideosRowState();
}

class _TutorialVideosRowState extends State<TutorialVideosRow> {
  late final Stream<List<TutorialVideo>> _stream =
      TutorialVideosService.forPlacement(widget.placement);

  @override
  void initState() {
    super.initState();
    TutorialRegion.ensure(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = widget.textColor ?? scheme.onSurface;
    final muted = widget.mutedColor ?? scheme.onSurface.withValues(alpha: 0.6);
    final card = widget.cardColor ?? Theme.of(context).cardColor;
    final border = widget.borderColor ?? Theme.of(context).dividerColor;

    return ValueListenableBuilder<bool?>(
      valueListenable: TutorialRegion.isPhilippines,
      builder: (context, ph, _) => StreamBuilder<List<TutorialVideo>>(
      stream: _stream,
      builder: (context, snap) {
        // Wait for the region so the right language shows from the start.
        if (ph == null) return const SizedBox.shrink();
        final videos = (snap.data ?? const <TutorialVideo>[])
            .map((v) => v.forRegion(philippines: ph))
            .toList();
        if (videos.isEmpty) return const SizedBox.shrink();
        final single = videos.length == 1;
        return Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.play_circle_outline_rounded, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Text(
                    widget.title,
                    style: TextStyle(color: muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: single ? 76 : 150,
                child: single
                    ? _WideCard(video: videos.first, text: text, muted: muted, card: card, border: border)
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: videos.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, i) =>
                            _Card(video: videos[i], text: text, muted: muted, card: card, border: border),
                      ),
              ),
            ],
          ),
        );
      },
      ),
    );
  }
}

Future<void> openTutorialVideo(BuildContext context, TutorialVideo v) async {
  if (v.isYoutube) {
    final uri = Uri.tryParse(v.youtubeUrl);
    final ok = uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the video.")),
      );
    }
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TutorialVideoPlayerScreen(video: v), fullscreenDialog: true),
  );
}

/// 16:9 thumbnail with play button and duration — also used by
/// VideoTutorialsScreen.
class TutorialVideoThumb extends StatelessWidget {
  const TutorialVideoThumb({super.key, required this.video, this.big = true});
  final TutorialVideo video;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final url = video.thumbnail;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null)
          CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const _ThumbFallback(),
            placeholder: (_, _) => const _ThumbFallback(),
          )
        else
          const _ThumbFallback(),
        Container(color: Colors.black.withValues(alpha: 0.18)),
        Center(
          child: Container(
            padding: EdgeInsets.all(big ? 8 : 5),
            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: big ? 26 : 20),
          ),
        ),
        if (video.durationLabel != null)
          Positioned(
            right: 5,
            bottom: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(4)),
              child: Text(video.durationLabel!,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
        if (video.isYoutube)
          const Positioned(
            left: 5,
            top: 5,
            child: Icon(Icons.smart_display_rounded, color: Colors.white, size: 16),
          ),
      ],
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E3A8A), Color(0xFF0EA5E9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      );
}

/// Card in a row of several: 16:9 thumbnail, title underneath.
class _Card extends StatelessWidget {
  const _Card({required this.video, required this.text, required this.muted, required this.card, required this.border});
  final TutorialVideo video;
  final Color text, muted, card, border;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 176,
      child: Material(
        color: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openTutorialVideo(context, video),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: TutorialVideoThumb(video: video)),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 0),
                child: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: text, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single video: full-width row, thumbnail on the left.
class _WideCard extends StatelessWidget {
  const _WideCard({required this.video, required this.text, required this.muted, required this.card, required this.border});
  final TutorialVideo video;
  final Color text, muted, card, border;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openTutorialVideo(context, video),
        child: Row(
          children: [
            SizedBox(width: 76 * 16 / 9, child: TutorialVideoThumb(video: video, big: false)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: text, fontSize: 13.5, fontWeight: FontWeight.w700)),
                    if (video.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(video.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 11.5, height: 1.3)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(Icons.chevron_right_rounded, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
