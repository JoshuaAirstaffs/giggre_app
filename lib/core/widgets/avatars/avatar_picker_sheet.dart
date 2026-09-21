import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'giggre_avatar.dart';
import 'giggre_avatar_art.dart';

/// Lets someone pick one of the Giggre avatars instead of uploading a photo.
///
/// Returns the chosen avatar's id, or null if they backed out. Every tile
/// animates: the whole point of these is that they move, and a grid of stills
/// would sell the wrong thing.
Future<String?> showGiggreAvatarPicker(
  BuildContext context, {
  String? currentAvatarId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _AvatarPickerSheet(currentAvatarId: currentAvatarId),
  );
}

class _AvatarPickerSheet extends StatefulWidget {
  final String? currentAvatarId;

  const _AvatarPickerSheet({this.currentAvatarId});

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  late String? _selected = widget.currentAvatarId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : const Color(0xFF17263D);
    final muted = isDark ? const Color(0xFF94A0B0) : const Color(0xFF5A6778);

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).viewPadding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Choose an avatar',
            style: TextStyle(
              color: onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use one of these instead of a photo. It becomes your profile '
            'picture everywhere on Giggre.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 18),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                alignment: WrapAlignment.center,
                children: [
                  for (final art in kGiggreAvatars)
                    _AvatarTile(
                      art: art,
                      selected: art.id == _selected,
                      isDark: isDark,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = art.id);
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(context, _selected),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: kBlue.withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Use this avatar',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  final GiggreAvatarArt art;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _AvatarTile({
    required this.art,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? const Color(0xFF94A0B0) : const Color(0xFF5A6778);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 96,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? kBlue : Colors.transparent,
                  width: 3,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: kBlue.withValues(alpha: 0.28),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: GiggreAvatar(art: art, size: 80),
            ),
            const SizedBox(height: 7),
            Text(
              art.name,
              style: TextStyle(
                color: selected
                    ? kBlue
                    : (isDark ? Colors.white : const Color(0xFF17263D)),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              art.move,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 10.5, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Where a new profile picture should come from.
enum ProfilePictureSource { camera, gallery, giggreAvatar }

/// The "change your picture" chooser, shared by the worker and host profile
/// screens so both offer the same three routes.
Future<ProfilePictureSource?> showProfilePictureSourceDialog(
  BuildContext context,
) {
  return showDialog<ProfilePictureSource>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Theme.of(c).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: kBlue),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(c, ProfilePictureSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded, color: kBlue),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(c, ProfilePictureSource.gallery),
          ),
          ListTile(
            // A live avatar rather than a flat icon — it says what you get
            // better than any label on the row could.
            leading: SizedBox(
              width: 34,
              height: 34,
              child: GiggreAvatar(art: kGiggreAvatars.first, size: 34),
            ),
            title: const Text('Giggre avatar'),
            subtitle: const Text(
              'Pick a character instead of a photo',
              style: TextStyle(fontSize: 11.5),
            ),
            onTap: () => Navigator.pop(c, ProfilePictureSource.giggreAvatar),
          ),
        ],
      ),
    ),
  );
}
