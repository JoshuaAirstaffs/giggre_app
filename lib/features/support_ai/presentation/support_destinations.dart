// Giggre AI support — screens Gab can offer as "open this screen" buttons.
//
// Gab adds "[GO:<id>]" to an answer; askSupport turns it into an `actions`
// id. Keep the ids in sync with DESTINATIONS in functions/src/askSupport.ts
// and the tag list in functions/src/support-rules.md. Ids this app version
// doesn't know are ignored.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/current_user_provider.dart';
import '../../../core/services/sign_out_service.dart';
import '../../../screens/app_contents/about_giggre.dart';
import '../../../screens/app_contents/contact_us.dart';
import '../../../screens/app_contents/help_faq.dart';
import '../../../screens/app_contents/privacy_policy.dart';
import '../../../screens/app_contents/terms_and_conditions.dart';
import '../../../screens/referrals/my_referral_screen.dart';
import '../../gig_host/presentation/host_gigs_screen.dart';
import '../../gig_host/presentation/my_documents_screen.dart';
import '../../gig_host/presentation/post_offered_gig_screen.dart';
import '../../gig_host/presentation/post_open_gig_screen.dart';
import '../../gig_host/presentation/post_quick_gig_screen.dart';
import '../../gig_points/presentation/gig_points_screen.dart';
import '../../gig_worker/presentation/gig_history_screen.dart';
import '../../gig_worker/presentation/saved_screen.dart';
import '../../gig_worker/presentation/verification_screen.dart';
import '../../gig_worker/presentation/worker_ratings_screen.dart';
import '../../gig_worker/presentation/worker_settings_screen.dart';
import '../../home/presentation/profile_tab.dart';
import '../../tutorial_demo/demo_hub_screen.dart';
import '../../wallet/presentation/wallet_screen.dart';
import 'support_bubble.dart';

class SupportDestination {
  const SupportDestination(this.label, this.icon, this.builder);

  final String label;
  final IconData icon;
  final Widget Function(BuildContext context, GiggreMode mode) builder;

  static SupportDestination? byId(String id) => _destinations[id];
}

String _uid() => FirebaseAuth.instance.currentUser?.uid ?? '';

String _hostName(BuildContext context) =>
    context.read<CurrentUserProvider>().currentName ?? '';

final Map<String, SupportDestination> _destinations = {
  'profile': SupportDestination(
    'Open Profile',
    Icons.person_outline_rounded,
    (context, mode) => Scaffold(
      body: ProfileTab(
        initialRole: mode.name,
        isTabRoot: false,
        onLogout: () => performSignOut(context),
      ),
    ),
  ),
  'settings': SupportDestination(
    'Open Settings',
    Icons.settings_outlined,
    (_, _) => const WorkerSettingsScreen(),
  ),
  'wallet': SupportDestination(
    'Open Gig Wallet',
    Icons.account_balance_wallet_outlined,
    (_, mode) => WalletScreen(role: mode.name),
  ),
  'gig_points': SupportDestination(
    'Open Gig Points',
    Icons.stars_outlined,
    (_, _) => const GigPointsScreen(),
  ),
  'referrals': SupportDestination(
    'Open My Referrals',
    Icons.group_add_outlined,
    (_, _) => const MyReferralScreen(),
  ),
  'verification': SupportDestination(
    'Open Verification',
    Icons.verified_user_outlined,
    (_, _) => const VerificationScreen(),
  ),
  'documents': SupportDestination(
    'Open My Documents',
    Icons.folder_outlined,
    (_, _) => MyDocumentsScreen(userId: _uid()),
  ),
  'gig_history': SupportDestination(
    'Open Gig History',
    Icons.history_rounded,
    (_, _) => const GigHistoryScreen(),
  ),
  'my_ratings': SupportDestination(
    'Open Ratings & Reviews',
    Icons.star_outline_rounded,
    (_, _) => const WorkerRatingsScreen(),
  ),
  'saved_gigs': SupportDestination(
    'Open Saved gigs',
    Icons.bookmark_outline_rounded,
    (_, _) => SavedScreen(uid: _uid()),
  ),
  'my_gigs': SupportDestination(
    'Open My gigs',
    Icons.work_outline_rounded,
    (_, _) => HostGigsScreen(uid: _uid(), isTabRoot: false),
  ),
  'post_quick_gig': SupportDestination(
    'Post a Quick Gig',
    Icons.bolt_rounded,
    (context, _) => PostQuickGigScreen(hostName: _hostName(context)),
  ),
  'post_open_gig': SupportDestination(
    'Post an Open Gig',
    Icons.campaign_outlined,
    (context, _) => PostOpenGigScreen(hostName: _hostName(context)),
  ),
  'post_offered_gig': SupportDestination(
    'Post an Offered Gig',
    Icons.send_outlined,
    (context, _) => PostOfferedGigScreen(hostName: _hostName(context)),
  ),
  'demos': SupportDestination(
    'Watch Demo',
    Icons.play_circle_outline_rounded,
    (_, _) => const TutorialDemoHubScreen(),
  ),
  'contact_us': SupportDestination(
    'Open Contact Us',
    Icons.mail_outline_rounded,
    (_, _) => const ContactUs(),
  ),
  'help_faq': SupportDestination(
    'Open Help & FAQ',
    Icons.help_outline_rounded,
    (_, _) => HelpFaq(),
  ),
  'terms': SupportDestination(
    'Open Terms of Service',
    Icons.description_outlined,
    (_, _) => const TermsAndConditions(),
  ),
  'privacy': SupportDestination(
    'Open Privacy Policy',
    Icons.privacy_tip_outlined,
    (_, _) => PrivacyPolicy(),
  ),
  'about': SupportDestination(
    'About Giggre',
    Icons.info_outline_rounded,
    (_, _) => const AboutGiggre(),
  ),
};
