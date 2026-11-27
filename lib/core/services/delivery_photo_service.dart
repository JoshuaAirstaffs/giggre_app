import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Delivery proof photos ───────────────────────────────────────────────────
//
// On a pick-up → drop-off gig the worker must photograph the item twice:
// at the pick-up (taken when they tap Start Gig) and at the drop-off (taken
// when they tap Gig Complete). The status changes right away; the photo
// uploads in the background so a weak signal never holds the worker up.
//
// Fields on the worker's progress doc (the gig doc, or its workers/{uid}
// slot on multi-worker gigs — wherever `status` lives):
//
//   pickupPhotoAt / dropoffPhotoAt          Timestamp  when it was taken
//   pickupPhotoStatus / dropoffPhotoStatus  'uploading' | 'uploaded' | 'failed'
//   pickupPhotoUrl / dropoffPhotoUrl        download URL, once uploaded
//
// Storage: delivery_photos/{collection}/{gigId}/{workerUid}/{kind}.jpg —
// readable by that worker, the gig's host and admins (storage.rules), and
// deleted after 60 days by cleanupDeliveryPhotos (functions/src).

enum DeliveryPhotoKind { pickup, dropoff }

extension DeliveryPhotoKindFields on DeliveryPhotoKind {
  String get key => name; // 'pickup' | 'dropoff'
  String get atField => '${key}PhotoAt';
  String get statusField => '${key}PhotoStatus';
  String get urlField => '${key}PhotoUrl';
}

class DeliveryPhotoService {
  DeliveryPhotoService._();

  static const _pendingKey = 'pending_delivery_photos';

  /// Opens the camera. Camera only — no gallery — so the photo is taken on
  /// the spot. Shrunk to ~1280 px / JPEG 60 (about 150–250 KB), which keeps
  /// uploads fast on mobile data and storage cheap.
  ///
  /// Debug builds fall back to the gallery when there's no camera (the iOS
  /// Simulator), so the flow can still be tested there.
  static Future<File?> capture() async {
    final picker = ImagePicker();
    try {
      final shot = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 60,
        preferredCameraDevice: CameraDevice.rear,
      );
      return shot == null ? null : File(shot.path);
    } catch (e) {
      if (!kDebugMode) rethrow;
      debugPrint('[DeliveryPhoto] camera unavailable ($e) — debug gallery fallback');
      final pick = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 60,
      );
      return pick == null ? null : File(pick.path);
    }
  }

  /// Fields to write together with the status change, marking the photo as
  /// taken and on its way.
  static Map<String, dynamic> takenFields(DeliveryPhotoKind kind) => {
    kind.atField: FieldValue.serverTimestamp(),
    kind.statusField: 'uploading',
  };

  /// Uploads [file] and saves its URL on [progressRef]. Never throws — a
  /// failed upload is remembered and retried by [retryPending] the next time
  /// the working screen opens.
  static Future<void> upload({
    required File file,
    required DocumentReference<Map<String, dynamic>> progressRef,
    required String collection,
    required String gigId,
    required String workerUid,
    required DeliveryPhotoKind kind,
  }) async {
    final job = _Job(
      filePath: file.path,
      docPath: progressRef.path,
      storagePath: 'delivery_photos/$collection/$gigId/$workerUid/${kind.key}.jpg',
      kind: kind,
    );
    await _remember(job);
    await _run(job);
  }

  /// Retries uploads that didn't finish (app closed, no signal). Safe to
  /// call often; does nothing when there's nothing pending.
  static Future<void> retryPending() async {
    final jobs = await _load();
    for (final job in jobs) {
      await _run(job);
    }
  }

  static Future<void> _run(_Job job) async {
    final doc = FirebaseFirestore.instance.doc(job.docPath);
    final file = File(job.filePath);
    if (!file.existsSync()) {
      // The OS cleared the temp file before it could upload — nothing left
      // to send. Mark it so the host sees why there's no photo.
      await _forget(job);
      try {
        await doc.update({job.kind.statusField: 'failed'});
      } catch (_) {}
      return;
    }
    try {
      final ref = FirebaseStorage.instance.ref(job.storagePath);
      await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref.getDownloadURL();
      await doc.update({
        job.kind.urlField: url,
        job.kind.statusField: 'uploaded',
      });
      await _forget(job);
    } catch (e) {
      // Left in the pending list for the next retryPending().
      debugPrint('[DeliveryPhoto] upload failed, will retry: $e');
    }
  }

  // ── Pending list (SharedPreferences) ──────────────────────────────────────

  static Future<List<_Job>> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_pendingKey) ?? const [])
          .map((s) => _Job.fromJson(jsonDecode(s) as Map<String, dynamic>))
          .whereType<_Job>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<_Job> jobs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _pendingKey,
        jobs.map((j) => jsonEncode(j.toJson())).toList(),
      );
    } catch (_) {}
  }

  static Future<void> _remember(_Job job) async {
    final jobs = await _load()
      ..removeWhere((j) => j.storagePath == job.storagePath);
    await _save(jobs..add(job));
  }

  static Future<void> _forget(_Job job) async {
    final jobs = await _load()
      ..removeWhere((j) => j.storagePath == job.storagePath);
    await _save(jobs);
  }
}

class _Job {
  final String filePath;
  final String docPath;
  final String storagePath;
  final DeliveryPhotoKind kind;

  const _Job({
    required this.filePath,
    required this.docPath,
    required this.storagePath,
    required this.kind,
  });

  Map<String, dynamic> toJson() => {
    'file': filePath,
    'doc': docPath,
    'storage': storagePath,
    'kind': kind.key,
  };

  static _Job? fromJson(Map<String, dynamic> m) {
    final kind = DeliveryPhotoKind.values
        .where((k) => k.key == m['kind'])
        .firstOrNull;
    final file = m['file'], doc = m['doc'], storage = m['storage'];
    if (kind == null || file is! String || doc is! String || storage is! String) {
      return null;
    }
    return _Job(filePath: file, docPath: doc, storagePath: storage, kind: kind);
  }
}
