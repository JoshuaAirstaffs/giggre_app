import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';

/// Gig photos for Post a gig (Quick / Open / Offered): up to [maxImages]
/// optional images. Keeps the picked files until the gig is posted, then
/// [uploadAll] puts them in Storage (gig_images/{uid}/…) and returns their
/// download URLs for the gig's `images` field.
class GigImagesController extends ChangeNotifier {
  static const int maxImages = 5;
  final List<XFile> files = [];

  bool get isFull => files.length >= maxImages;

  void add(List<XFile> picked) {
    for (final f in picked) {
      if (isFull) break;
      files.add(f);
    }
    notifyListeners();
  }

  void removeAt(int i) {
    files.removeAt(i);
    notifyListeners();
  }

  void clear() {
    files.clear();
    notifyListeners();
  }

  /// Uploads every picked photo; throws if any upload fails (the gig isn't
  /// posted half-done).
  Future<List<String>> uploadAll() async {
    if (files.isEmpty) return const [];
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');
    final storage = FirebaseStorage.instance;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final ref = storage.ref('gig_images/$uid/${stamp}_$i.jpg');
      final meta = SettableMetadata(contentType: f.mimeType ?? 'image/jpeg');
      if (kIsWeb) {
        await ref.putData(await f.readAsBytes(), meta);
      } else {
        await ref.putFile(File(f.path), meta);
      }
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }
}

/// "Photos (optional)" row: thumbnails with ✕, plus an Add tile that offers
/// Camera or Gallery.
class GigImagesPicker extends StatelessWidget {
  final GigImagesController controller;
  final Color accentColor;
  const GigImagesPicker({super.key, required this.controller, this.accentColor = kGold});

  Future<void> _pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picker = ImagePicker();
    try {
      if (source == ImageSource.camera) {
        final f = await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 80);
        if (f != null) controller.add([f]);
      } else {
        final left = GigImagesController.maxImages - controller.files.length;
        final picked = await picker.pickMultiImage(maxWidth: 1600, imageQuality: 80, limit: left > 1 ? left : null);
        if (picked.length > left && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Only ${GigImagesController.maxImages} photos per gig — added the first $left.')),
          );
        }
        controller.add(picked);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Couldn\'t open your photos. Check the app\'s photo/camera permission.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).dividerColor;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final files = controller.files;
        return SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < files.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb
                            ? Image.network(files[i].path, width: 84, height: 84, fit: BoxFit.cover)
                            : Image.file(File(files[i].path), width: 84, height: 84, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Semantics(
                          button: true,
                          label: 'Remove photo ${i + 1}',
                          child: GestureDetector(
                            onTap: () => controller.removeAt(i),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!controller.isFull)
                Semantics(
                  button: true,
                  label: 'Add photos',
                  child: InkWell(
                    onTap: () => _pick(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border, width: 1.5),
                        color: Theme.of(context).cardColor,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, color: accentColor, size: 24),
                          const SizedBox(height: 4),
                          Text(
                            '${files.length}/${GigImagesController.maxImages}',
                            style: const TextStyle(color: kSub, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Photos on a posted gig — a horizontal strip; tap to view full screen.
class GigImagesStrip extends StatelessWidget {
  final List<String> urls;
  final double height;
  const GigImagesStrip({super.key, required this.urls, this.height = 120});

  void _open(BuildContext context, int start) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _GigImageViewer(urls: urls, initial: start),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Semantics(
          button: true,
          label: 'Gig photo ${i + 1} of ${urls.length}',
          child: GestureDetector(
            onTap: () => _open(context, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                urls[i],
                width: height * 1.3,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: height * 1.3,
                  height: height,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image_outlined, color: kSub),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GigImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initial;
  const _GigImageViewer({required this.urls, required this.initial});

  @override
  State<_GigImageViewer> createState() => _GigImageViewerState();
}

class _GigImageViewerState extends State<_GigImageViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_page + 1} / ${widget.urls.length}', style: const TextStyle(fontSize: 15)),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(child: Image.network(widget.urls[i], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
