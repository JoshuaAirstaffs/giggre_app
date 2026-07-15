import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Header — blue gradient band
// ─────────────────────────────────────────────────────────────────────────────
class WorkerHeader extends StatelessWidget {
  final String userId;
  final String name;
  final String email;
  final String phone;
  final String photoUrl;
  final double rating;
  final int ratingCount;
  final String memberSince;
  final bool isDark;
  final VoidCallback onEdit;
  final String isVerified;
  final bool showBackButton;
  final VoidCallback? onNotifications;

  const WorkerHeader({
    super.key,
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.photoUrl,
    required this.rating,
    required this.ratingCount,
    required this.memberSince,
    required this.isDark,
    required this.onEdit,
    required this.isVerified,
    this.showBackButton = true,
    this.onNotifications,
  });

  @override
  Widget build(BuildContext context) {
    // Even when a caller asks for the back arrow, don't render one with
    // nothing to pop to (e.g. if ever shown at the root of the navigator).
    final showBack = showBackButton && Navigator.canPop(context);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(26),
        bottomRight: Radius.circular(26),
      ),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2B6FB5), Color(0xFF1F4D80)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title row ────────────────────────────────────────────
                Row(
                  children: [
                    if (showBack) ...[
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    const Expanded(
                      child: Text(
                        'Worker Dashboard',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    if (onNotifications != null)
                      GestureDetector(
                        onTap: onNotifications,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                // ── Profile row ──────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _WorkerAvatar(photoUrl: photoUrl, name: name, size: 50),
                        if (isVerified == 'verified')
                          Positioned(
                            bottom: -1,
                            right: -1,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E9E6B),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        name.isNotEmpty ? name : 'Worker',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Avatar helpers
// ─────────────────────────────────────────────────────────────────────────────
class _WorkerAvatar extends StatelessWidget {
  final String photoUrl;
  final String name;
  final double size;
  const _WorkerAvatar({
    required this.photoUrl,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (ctx, url) => _InitialAvatar(name: name, size: size),
          errorWidget: (ctx, url, err) =>
              _InitialAvatar(name: name, size: size),
        ),
      );
    }
    return _InitialAvatar(name: name, size: size);
  }
}

class _InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  const _InitialAvatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF33475E),
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
