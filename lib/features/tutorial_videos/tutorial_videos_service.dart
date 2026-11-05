import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// Admin-managed how-to videos (giggre-admin → Content Management → Tutorial
// Videos, lib/tutorialVideos.ts there).
//
//   app_content/tutorial_videos/items/{id}
//     { title, description, placements: [welcome|login|signup|help],
//       source: upload|youtube, videoUrl, youtubeUrl, youtubeId,
//       thumbnailUrl, durationSec, published, order,
//       tl: null | { source, videoUrl, youtubeUrl, youtubeId, thumbnailUrl,
//                    durationSec, title, description } }
//
// Top-level fields = the English version (the default). `tl` = an optional
// Tagalog version shown to users in the Philippines (TutorialRegion);
// everyone else — and PH users when there's no Tagalog — gets English.
//
// Public read (firestore.rules app_content) because the Welcome / Log In /
// Sign Up screens are shown before sign-in.

enum TutorialPlacement { welcome, login, signup, help }

class TutorialVideo {
  final String id;
  final String title;
  final String description;
  final Set<TutorialPlacement> placements;
  final bool isYoutube;
  final String videoUrl;
  final String youtubeUrl;
  final String youtubeId;
  final String thumbnailUrl;
  final int? durationSec;
  final int order;

  /// Extra search words set by the admin (Video Tutorials search).
  final List<String> keywords;

  /// The Tagalog version (title/description fall back to English), or null.
  final TutorialVideo? tagalog;

  const TutorialVideo({
    required this.id,
    required this.title,
    required this.description,
    required this.placements,
    required this.isYoutube,
    required this.videoUrl,
    required this.youtubeUrl,
    required this.youtubeId,
    required this.thumbnailUrl,
    required this.durationSec,
    required this.order,
    this.keywords = const [],
    this.tagalog,
  });

  /// The version to show: Tagalog in the Philippines when there is one,
  /// otherwise English.
  TutorialVideo forRegion({required bool philippines}) =>
      philippines && tagalog != null ? tagalog! : this;

  /// Something to show on the card, if any.
  String? get thumbnail => thumbnailUrl.isNotEmpty
      ? thumbnailUrl
      : isYoutube && youtubeId.isNotEmpty
          ? 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg'
          : null;

  bool get playable => isYoutube ? youtubeUrl.isNotEmpty : videoUrl.isNotEmpty;

  String? get durationLabel {
    final d = durationSec;
    if (d == null) return null;
    return '${d ~/ 60}:${(d % 60).toString().padLeft(2, '0')}';
  }

  static TutorialVideo? fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data();
    if (d['published'] != true) return null;
    String str(Object? v) => v is String ? v.trim() : '';
    final placements = <TutorialPlacement>{
      if (d['placements'] is List)
        for (final p in d['placements'] as List)
          for (final t in TutorialPlacement.values)
            if (t.name == p) t,
    };
    final v = TutorialVideo(
      id: s.id,
      title: str(d['title']),
      description: str(d['description']),
      placements: placements,
      isYoutube: d['source'] == 'youtube',
      videoUrl: str(d['videoUrl']),
      youtubeUrl: str(d['youtubeUrl']),
      youtubeId: str(d['youtubeId']),
      thumbnailUrl: str(d['thumbnailUrl']),
      durationSec: (d['durationSec'] as num?)?.round(),
      order: (d['order'] as num?)?.toInt() ?? 0,
      keywords: [
        if (d['keywords'] is List)
          for (final k in d['keywords'] as List)
            if (k is String && k.trim().isNotEmpty) k.trim(),
      ],
      tagalog: null,
    );
    if (v.title.isEmpty || !v.playable) return null;
    return v._withTagalog(d['tl']);
  }

  TutorialVideo _withTagalog(Object? raw) {
    if (raw is! Map) return this;
    String str(Object? x) => x is String ? x.trim() : '';
    final title = str(raw['title']);
    final desc = str(raw['description']);
    final tl = TutorialVideo(
      id: '${id}_tl',
      title: title.isEmpty ? this.title : title,
      description: desc.isEmpty ? description : desc,
      placements: placements,
      isYoutube: raw['source'] == 'youtube',
      videoUrl: str(raw['videoUrl']),
      youtubeUrl: str(raw['youtubeUrl']),
      youtubeId: str(raw['youtubeId']),
      thumbnailUrl: str(raw['thumbnailUrl']),
      durationSec: (raw['durationSec'] as num?)?.round(),
      order: order,
    );
    if (!tl.playable) return this;
    return TutorialVideo(
      id: id,
      title: this.title,
      description: description,
      placements: placements,
      isYoutube: isYoutube,
      videoUrl: videoUrl,
      youtubeUrl: youtubeUrl,
      youtubeId: youtubeId,
      thumbnailUrl: thumbnailUrl,
      durationSec: durationSec,
      order: order,
      keywords: keywords,
      tagalog: tl,
    );
  }
}

class TutorialVideosService {
  TutorialVideosService._();

  static final _items = FirebaseFirestore.instance
      .collection('app_content')
      .doc('tutorial_videos')
      .collection('items');

  /// Published videos for one place in the app, in the admin's order. The
  /// collection is small, so it's read whole and filtered on the device (no
  /// index needed); Firestore shares the underlying listener between rows.
  static Stream<List<TutorialVideo>> forPlacement(TutorialPlacement p) => _items
      .snapshots()
      .map((q) {
        final list = q.docs
            .map(TutorialVideo.fromDoc)
            .whereType<TutorialVideo>()
            .where((v) => v.placements.contains(p))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
        return list;
      })
      .handleError((Object e) => debugPrint('[TutorialVideos] $e'));
}
