import 'package:flutter/material.dart';

import 'tutorial_region.dart';
import 'tutorial_videos_row.dart';
import 'tutorial_videos_service.dart';

/// Profile → Settings → Video Tutorials: every published tutorial video with
/// the "Video Tutorials" placement (stored as `help`), in the admin's order,
/// in Tagalog for users in the Philippines when there's a Tagalog version.
class VideoTutorialsScreen extends StatefulWidget {
  const VideoTutorialsScreen({super.key});

  @override
  State<VideoTutorialsScreen> createState() => _VideoTutorialsScreenState();
}

class _VideoTutorialsScreenState extends State<VideoTutorialsScreen> {
  late final Stream<List<TutorialVideo>> _stream =
      TutorialVideosService.forPlacement(TutorialPlacement.help);

  @override
  void initState() {
    super.initState();
    TutorialRegion.ensure(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: const Text('Video Tutorials', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ValueListenableBuilder<bool?>(
        valueListenable: TutorialRegion.isPhilippines,
        builder: (context, ph, _) => StreamBuilder<List<TutorialVideo>>(
          stream: _stream,
          builder: (context, snap) {
            if (!snap.hasData && !snap.hasError) {
              return const Center(child: CircularProgressIndicator());
            }
            final videos = (snap.data ?? const <TutorialVideo>[])
                .map((v) => v.forRegion(philippines: ph ?? false))
                .toList();
            if (videos.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.ondemand_video_rounded, size: 40, color: muted),
                      const SizedBox(height: 10),
                      Text(
                        snap.hasError ? "Couldn't load the videos. Check your connection." : 'No video tutorials yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: muted, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: videos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 14),
              itemBuilder: (context, i) => _VideoCard(video: videos[i]),
            );
          },
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.video});
  final TutorialVideo video;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openTutorialVideo(context, video),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: TutorialVideoThumb(video: video)),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TextStyle(color: scheme.onSurface, fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (video.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      video.description,
                      style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
