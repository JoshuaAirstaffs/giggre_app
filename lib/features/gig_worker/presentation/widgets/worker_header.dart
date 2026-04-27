import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Worker Header — gradient banner with profile info, info rows, and edit CTA
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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0A1628), const Color(0xFF0F2040)]
              : [const Color(0xFF046BD2), const Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Navigation row ───────────────────────────────────────────
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('My Profile',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  // ── Edit button ──────────────────────────────────────────
                  GestureDetector(
                    onTap: onEdit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: kAmber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: kAmber.withValues(alpha: 0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              color: kAmber, size: 13),
                          SizedBox(width: 5),
                          Text('Edit',
                              style: TextStyle(
                                  color: kAmber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Avatar + identity ────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _WorkerAvatar(photoUrl: photoUrl, size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isNotEmpty ? name : 'Worker',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            ...List.generate(5, (i) {
                              final full = i < rating.floor();
                              final half = !full &&
                                  i < rating &&
                                  rating - i >= 0.5;
                              return Icon(
                                full
                                    ? Icons.star_rounded
                                    : half
                                        ? Icons.star_half_rounded
                                        : Icons.star_outline_rounded,
                                color: kAmber,
                                size: 15,
                              );
                            }),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '${rating.toStringAsFixed(1)}  '
                                '($ratingCount '
                                '${ratingCount == 1 ? 'rating' : 'ratings'})',
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (memberSince.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Member since $memberSince',
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.55),
                                  fontSize: 11)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Info panel ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Column(
                  children: [
                    _HeaderInfoRow(
                        icon: Icons.email_outlined, value: email),
                    if (phone.isNotEmpty) ...[
                      Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 16),
                      _HeaderInfoRow(
                          icon: Icons.phone_outlined, value: phone),
                    ],
                    if (userId.isNotEmpty) ...[
                      Divider(
                          color: Colors.white.withValues(alpha: 0.1),
                          height: 16),
                      _HeaderInfoRow(
                          icon: Icons.badge_outlined,
                          value: 'ID: $userId'),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Info row inside the header panel
// ─────────────────────────────────────────────────────────────────────────────
class _HeaderInfoRow extends StatelessWidget {
  final IconData icon;
  final String value;
  const _HeaderInfoRow({required this.icon, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            color: Colors.white.withValues(alpha: 0.55), size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
        color: kAmber.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
      ),
      child: Icon(Icons.person_rounded, color: kAmber, size: size * 0.5),
    );
  }
}