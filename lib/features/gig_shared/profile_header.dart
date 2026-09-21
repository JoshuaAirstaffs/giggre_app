import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/models/rating_summary.dart';
import '../../core/services/rating_service.dart';
import '../../core/theme/app_colors.dart';
import 'active_gig_theme.dart';
import 'profile_stats.dart';
import 'user_profile_sheet.dart' show ProfileAvatar;

/// Role accent for a profile: blue for a worker, gold for a host, matching
/// the two Active Gig screens.
ActiveGigAccent profileAccent(RateeRole role) =>
    role == RateeRole.worker ? kWorkerAccent : kHostAccent;

/// Header gradient per role.
///
/// The host side is the brand gold straight from the logo — the same pair the
/// Active Gig host header uses, in both themes, so the two surfaces match.
/// White cannot sit on it (about 1.9:1), so that side takes navy text instead;
/// see [ProfileHeaderPalette].
///
/// The worker side blends its blue accent down toward navy, which keeps white
/// text clear and matches the app's dark surfaces. That blend only works
/// because the accent is already blue: run the gold through it and both stops
/// land in the same brown, because gold and navy have almost no blue between
/// them to carry the hue.
List<Color> profileHeaderGradient(RateeRole role, bool isDark) {
  if (role == RateeRole.host) {
    return const [Color(0xFFF0A830), Color(0xFFD88810)];
  }
  const accent = kWorkerAccent;
  return [
    Color.lerp(accent.solid, const Color(0xFF16233A), isDark ? 0.74 : 0.38)!,
    Color.lerp(accent.solid, const Color(0xFF0B1220), isDark ? 0.9 : 0.66)!,
  ];
}

/// Everything drawn on top of the header gradient.
///
/// Two sets, because the two gradients need opposite foregrounds: the worker's
/// deep blue takes white, the host's gold takes navy. Status colours are
/// darkened on the gold side for the same reason — the light green that reads
/// as "verified" on navy is only 1.7:1 against gold.
class ProfileHeaderPalette {
  /// Primary text, and the colour every translucent fill is tinted from.
  final Color fg;

  /// Filled and unfilled stars. Gold stars vanish on a gold header, so that
  /// side borrows the foreground instead.
  final Color star;
  final Color starEmpty;

  final Color chipFill;
  final Color chipFillStrong;
  final Color chipBorder;

  final Color verified;
  final Color provisional;
  final Color unverified;

  /// The disc behind the tick on the avatar, and the tick itself.
  final Color tickBg;
  final Color tick;

  /// Status bar icons, since the header runs under them.
  final SystemUiOverlayStyle overlay;

  const ProfileHeaderPalette({
    required this.fg,
    required this.star,
    required this.starEmpty,
    required this.chipFill,
    required this.chipFillStrong,
    required this.chipBorder,
    required this.verified,
    required this.provisional,
    required this.unverified,
    required this.tickBg,
    required this.tick,
    required this.overlay,
  });

  static const _navy = Color(0xFF17263D);

  /// Navy on gold. Contrast runs 7.3:1 for the text and 4.5:1 or better for
  /// every status colour.
  static const host = ProfileHeaderPalette(
    fg: _navy,
    star: _navy,
    starEmpty: Color(0x3317263D),
    chipFill: Color(0x1A17263D),
    chipFillStrong: Color(0x2E17263D),
    chipBorder: Color(0x3317263D),
    verified: Color(0xFF14532D),
    provisional: Color(0xFF713F12),
    unverified: Color(0xFF7F1D1D),
    tickBg: _navy,
    tick: Color(0xFF4ADE80),
    overlay: SystemUiOverlayStyle.dark,
  );

  static const worker = ProfileHeaderPalette(
    fg: Colors.white,
    star: kGold,
    starEmpty: Color(0x47FFFFFF),
    chipFill: Color(0x24FFFFFF),
    chipFillStrong: Color(0x38FFFFFF),
    chipBorder: Color(0x29FFFFFF),
    verified: Color(0xFF4ADE80),
    provisional: kAmber,
    unverified: Color(0xFFFF9A9A),
    tickBg: Color(0xFF0E1B2F),
    tick: Color(0xFF4ADE80),
    overlay: SystemUiOverlayStyle.light,
  );

  static ProfileHeaderPalette of(RateeRole role) =>
      role == RateeRole.host ? host : worker;
}

/// The identity block at the top of a profile: avatar on the left, and to its
/// right everything that says who this is — name, rating, skills and bio.
///
/// Takes plain values rather than the user document so it renders the same
/// from any caller and can be laid out without Firestore.
class ProfileHeader extends StatefulWidget {
  final String name;
  final String photoUrl;

  /// The Giggre avatar they picked, if any — animates in place of the
  /// photo.
  final String? avatarId;

  /// The `isVerified` field as stored: 'verified', 'pending', 'rejected' or
  /// 'unverified'.
  final String verification;

  /// `general_config/gig_visibility_rules.allowGigAccessForUnverified` — when
  /// on, an unverified user got through deliberately and is labelled
  /// "Provisional" rather than "Unverified".
  final bool allowUnverified;

  final RateeRole role;
  final RatingSummary summary;
  final List<String> skills;
  final String bio;
  final DateTime? memberSince;
  final bool isDark;

  /// True until the profile lands, so the rating line says so instead of
  /// claiming there are no ratings.
  final bool loading;

  /// Space above the content, for the bar floating over this.
  final double topPadding;

  const ProfileHeader({
    super.key,
    required this.name,
    required this.photoUrl,
    this.avatarId,
    required this.verification,
    required this.allowUnverified,
    required this.role,
    required this.summary,
    required this.skills,
    required this.bio,
    required this.memberSince,
    required this.isDark,
    required this.loading,
    this.topPadding = 0,
  });

  /// How many skills and bio lines show before the header offers to expand —
  /// enough to judge someone at a glance without eating a phone screen.
  static const collapsedSkills = 4;
  static const collapsedBioLines = 3;

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  bool _skillsExpanded = false;
  bool _bioExpanded = false;

  bool get _isWorker => widget.role == RateeRole.worker;
  List<Color> get _gradient =>
      profileHeaderGradient(widget.role, widget.isDark);
  ProfileHeaderPalette get _p => ProfileHeaderPalette.of(widget.role);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, widget.topPadding, 16, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.4 : 0.18),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileEntrance(
                slideOffset: 0,
                scaleFrom: 0.84,
                child: _avatar(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ProfileEntrance(
                  delay: const Duration(milliseconds: 70),
                  slideOffset: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: TextStyle(
                          color: _p.fg,
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 7),
                      _rating(),
                      _skills(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          _bioBlock(),
          const SizedBox(height: 14),
          ProfileEntrance(
            delay: const Duration(milliseconds: 150),
            slideOffset: 12,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _chip(
                  _isWorker ? Icons.handyman_rounded : Icons.storefront_rounded,
                  _isWorker ? 'Gig Worker' : 'Gig Host',
                ),
                _verificationPill(),
                if (widget.memberSince != null)
                  _chip(
                    Icons.calendar_today_rounded,
                    'Since ${DateFormat('MMM y').format(widget.memberSince!)}',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() {
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        children: [
          // Soft ring so the photo reads as lit from the page rather than
          // pasted onto the gradient. Stays white on both roles: it is a rim
          // highlight rather than text, and it catches the light against the
          // gold as readily as against the navy.
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ProfileAvatar(
              photoUrl: widget.photoUrl,
              avatarId: widget.avatarId,
              name: widget.name,
              size: 74,
              // Same disc as the verification tick, so the two circles on the
              // avatar read as one family rather than two stray accents.
              fallbackColor: _p.tickBg,
            ),
          ),
          if (widget.verification == 'verified')
            Positioned(
              right: 2,
              bottom: 2,
              child: Tooltip(
                message: 'Identity verified',
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _p.tickBg,
                  ),
                  child: Icon(Icons.verified_rounded, size: 17, color: _p.tick),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rating() {
    if (widget.loading) {
      return Text(
        'Loading…',
        style: TextStyle(color: _p.fg.withValues(alpha: 0.7), fontSize: 13),
      );
    }
    if (!widget.summary.hasRatings) {
      return Text(
        'No ratings yet',
        style: TextStyle(
          color: _p.fg.withValues(alpha: 0.78),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Row(
      children: [
        AnimatedStarRating(
          rating: widget.summary.average!,
          size: 15,
          gap: 1.5,
          color: _p.star,
          emptyColor: _p.starEmpty,
        ),
        const SizedBox(width: 7),
        Text(
          widget.summary.shortLabel,
          style: TextStyle(
            color: _p.fg,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '(${widget.summary.count})',
            style: TextStyle(
              color: _p.fg.withValues(alpha: 0.85),
              fontSize: 12.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Skills beside the avatar, capped to one glance's worth. Tapping the
  /// "+n" chip reveals the rest in place rather than pushing a second screen.
  Widget _skills() {
    final skills = widget.skills
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (skills.isEmpty) return const SizedBox.shrink();

    final hidden = skills.length - ProfileHeader.collapsedSkills;
    final shown = _skillsExpanded || hidden <= 0
        ? skills
        : skills.take(ProfileHeader.collapsedSkills).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topLeft,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in shown) _skillChip(s),
            if (hidden > 0)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _skillsExpanded = !_skillsExpanded);
                },
                child: _skillChip(
                  _skillsExpanded ? 'Show less' : '+$hidden more',
                  emphasised: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _skillChip(String label, {bool emphasised = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: emphasised ? _p.chipFillStrong : _p.chipFill,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _p.chipBorder),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: _p.fg.withValues(alpha: 0.95),
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  /// Bio sits under the identity block rather than beside it — a sentence or
  /// two wants the full width, and tapping opens the rest in place.
  Widget _bioBlock() {
    final bio = widget.bio.trim();
    if (bio.isEmpty) return const SizedBox.shrink();

    return ProfileEntrance(
      delay: const Duration(milliseconds: 110),
      slideOffset: 12,
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: GestureDetector(
          onTap: () => setState(() => _bioExpanded = !_bioExpanded),
          behavior: HitTestBehavior.opaque,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: Text(
              bio,
              maxLines: _bioExpanded ? null : ProfileHeader.collapsedBioLines,
              overflow: _bioExpanded
                  ? TextOverflow.clip
                  : TextOverflow.ellipsis,
              style: TextStyle(
                color: _p.fg.withValues(alpha: 0.88),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Same three states as [verificationBadge], restyled to sit on the header
  /// gradient — the sheet's tinted-on-surface badge disappears against it.
  Widget _verificationPill() {
    final (label, icon, color) = widget.verification == 'verified'
        ? ('Verified', Icons.verified_rounded, _p.verified)
        : widget.allowUnverified
        ? ('Provisional', Icons.shield_outlined, _p.provisional)
        : ('Unverified', Icons.error_outline_rounded, _p.unverified);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _p.chipFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _p.chipFill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _p.chipBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _p.fg.withValues(alpha: 0.85)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: _p.fg.withValues(alpha: 0.92),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
