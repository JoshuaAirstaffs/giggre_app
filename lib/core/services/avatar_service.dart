import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../widgets/avatars/giggre_avatar.dart';
import '../widgets/avatars/giggre_avatar_art.dart';

/// Saving a chosen Giggre avatar as someone's profile picture.
///
/// A choice is stored two ways on purpose:
///
/// * `avatarId` — the character they picked. Surfaces that know about avatars
///   read this and play the idle animation.
/// * `photoUrl` — a still of that avatar, rendered here and uploaded to the
///   same Storage path a real photo would use.
///
/// The second one is what makes this safe to ship. `photoUrl` is read in
/// roughly twenty places across gig cards, chat, applicant lists and headers;
/// writing a matching still means every one of them shows the avatar today,
/// rather than falling back to initials until each is taught about avatars.
///
/// Nothing here writes to Firestore. Both callers are already mid-save with an
/// update of their own, and a second write would race it.
class AvatarService {
  const AvatarService._();

  /// Field on the user document holding the chosen character's id.
  static const avatarIdField = 'avatarId';

  /// Matches the cap on uploaded photos, so an avatar costs no more to fetch
  /// than a picture would.
  static const _renderSize = 512.0;

  /// Renders [art] to a still and uploads it as this user's profile picture.
  /// Returns the download URL.
  ///
  /// Throws on failure — the caller is mid-save and must not report success
  /// for a picture that never landed.
  static Future<String> uploadStill({
    required String uid,
    required GiggreAvatarArt art,
  }) async {
    final png = await renderGiggreAvatarPng(art, size: _renderSize);
    final ref = FirebaseStorage.instance.ref().child('profile_images/$uid.jpg');
    // The path keeps the .jpg name every existing photo uses; the metadata is
    // what actually tells clients how to decode it.
    await ref.putData(png, SettableMetadata(contentType: 'image/png'));
    return ref.getDownloadURL();
  }

  /// Fields to merge into a profile save when an avatar was chosen.
  static Map<String, dynamic> avatarUpdates(String photoUrl, String avatarId) =>
      {'photoUrl': photoUrl, avatarIdField: avatarId};

  /// Fields to merge when a real photo was uploaded instead. Clearing the id
  /// is what stops a stale character animating over the new picture.
  static Map<String, dynamic> photoUpdates(String photoUrl) => {
    'photoUrl': photoUrl,
    avatarIdField: FieldValue.delete(),
  };
}
