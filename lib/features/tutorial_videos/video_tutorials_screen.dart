import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/current_user_provider.dart';

import 'tutorial_region.dart';
import 'tutorial_search.dart';
import 'tutorial_videos_row.dart';
import 'tutorial_videos_service.dart';

/// Profile → Settings → Video Tutorials: every published tutorial video with
/// the "Video Tutorials" placement (stored as `help`), in the admin's order,
/// in Tagalog for users in the Philippines when there's a Tagalog version.
/// The search bar matches titles, descriptions and admin keywords in both
/// languages, with synonyms and typo tolerance (tutorial_search.dart).
class VideoTutorialsScreen extends StatefulWidget {
  const VideoTutorialsScreen({super.key});

  @override
  State<VideoTutorialsScreen> createState() => _VideoTutorialsScreenState();
}

class _VideoTutorialsScreenState extends State<VideoTutorialsScreen> {
  late final Stream<List<TutorialVideo>> _stream =
      TutorialVideosService.forPlacement(TutorialPlacement.help);
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    TutorialRegion.ensure(context);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-run when the user's detected country / currency changes (GPS
    // detection after login can land a few seconds later).
    CurrentUserProvider? user;
    try {
      user = Provider.of<CurrentUserProvider>(context);
    } catch (_) {}
    if (user != null) {
      final u = user;
      WidgetsBinding.instance.addPostFrameCallback((_) => TutorialRegion.syncUser(u));
    }
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
            final all = snap.data ?? const <TutorialVideo>[];
            // Search the full video (both languages), then show the user's version.
            final videos = searchTutorialVideos(all, _query)
                .map((v) => v.forRegion(philippines: ph ?? false))
                .toList();
            if (all.isEmpty) {
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
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search videos, e.g. "sign up" or "top up"',
                      hintStyle: TextStyle(color: muted, fontSize: 13.5),
                      prefixIcon: Icon(Icons.search_rounded, color: muted),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear',
                              icon: Icon(Icons.close_rounded, color: muted),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                      filled: true,
                      fillColor: Theme.of(context).cardColor,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                  ),
                ),
                if (_query.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        videos.isEmpty
                            ? ''
                            : '${videos.length} video${videos.length == 1 ? '' : 's'} found',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                  ),
                Expanded(
                  child: videos.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 40, color: muted),
                                const SizedBox(height: 10),
                                Text(
                                  'No videos match "${_query.trim()}".\nTry another word, like "register" or "wallet".',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: muted, fontSize: 13.5, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: videos.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 14),
                          itemBuilder: (context, i) => _VideoCard(video: videos[i]),
                        ),
                ),
              ],
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
