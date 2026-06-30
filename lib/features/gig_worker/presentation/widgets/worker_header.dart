import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Header — blue gradient band (mirrors Gig Host gold band)
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
  final VoidCallback? onNotifications;
  final VoidCallback? onLogout;

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
    this.onNotifications,
    this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kBlue, Color(0xFF034FA0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Action row ─────────────────────────────────────────────────
              Row(
                children: [
                  // Left: back + "Gig Worker / Dashboard" label
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
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
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Gig Worker',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Dashboard',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Right: action icons (white)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onNotifications != null)
                        IconButton(
                          tooltip: 'Notifications',
                          icon: const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                          ),
                          onPressed: onNotifications,
                          style: IconButton.styleFrom(
                              foregroundColor: Colors.white),
                        ),
                      IconButton(
                        tooltip: 'Edit Profile',
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                        ),
                        onPressed: onEdit,
                        style: IconButton.styleFrom(
                            foregroundColor: Colors.white),
                      ),
                      ColorFiltered(
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                        child: const ThemeToggleButton(),
                      ),
                      if (onLogout != null)
                        IconButton(
                          tooltip: 'Log Out',
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                          ),
                          onPressed: onLogout,
                          style: IconButton.styleFrom(
                              foregroundColor: Colors.white),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // ── Profile strip ───────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Stack(
                    children: [
                      _WorkerAvatar(photoUrl: photoUrl, size: 50),
                      if (isVerified == 'verified')
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 17,
                            height: 17,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2BB673),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF034FA0),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isNotEmpty ? name : 'Worker',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: kAmber,
                              size: 14,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (userId.isNotEmpty)
                              Text(
                                '  ·  ID $userId',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
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
  final double size;
  const _WorkerAvatar({required this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (photoUrl.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (ctx, url) => _DefaultWorkerAvatar(size: size),
          errorWidget: (ctx, url, err) => _DefaultWorkerAvatar(size: size),
        ),
      );
    }
    return _DefaultWorkerAvatar(size: size);
  }
}

class _DefaultWorkerAvatar extends StatelessWidget {
  final double size;
  const _DefaultWorkerAvatar({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: size * 0.5,
      ),
    );
  }
}
