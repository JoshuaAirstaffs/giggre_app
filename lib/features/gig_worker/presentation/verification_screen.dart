import 'package:flutter/material.dart';
import 'package:giggre_app/core/theme/app_colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _isSubmitting = false;
  String _isVerified = 'unverified';
  bool _loadingStatus = true;

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _fetchVerificationStatus();
  }

  Future<void> _fetchVerificationStatus() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final doc = await _firestore.collection('users').doc(uid).get();
    if (mounted) {
      setState(() {
        _isVerified = doc.data()?['isVerified'] ?? 'unverified';
        _loadingStatus = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.grey, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Verify your account',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _loadingStatus
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusBanner(),
                  const SizedBox(height: 24),
                  _sectionLabel('Perks of being verified'),
                  const SizedBox(height: 10),
                  _perksList(),
                  const SizedBox(height: 24),
                  _sectionLabel('Verification Process'),
                  const SizedBox(height: 10),
                  _processList(),
                  const SizedBox(height: 28),
                  if (_isVerified == 'unverified' || _isVerified == 'rejected') ...[
                    _submitButton(),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Review typically takes 24–48 hours',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ),
                  ] else if (_isVerified == 'pending') ...[
                    _cancelButton(),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Review typically takes 24–48 hours',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    switch (_isVerified) {
      case 'pending':
        return StatusBanner(
          icon: Icons.hourglass_empty_outlined,
          title: 'Pending Request',
          subtitle: 'Your verification request is being processed',
          color: Colors.orange,
        );
      case 'verified':
        return StatusBanner(
          icon: Icons.check_circle_outline,
          title: 'Verified',
          subtitle: 'Your identity has been verified',
          color: Colors.green,
        );
      case 'rejected':
        return StatusBanner(
          icon: Icons.cancel_outlined,
          title: 'Rejected',
          subtitle: 'Your verification request has been rejected. Please resubmit.',
          color: Colors.red,
        );
      default:
        return StatusBanner(
          icon: Icons.verified_user_outlined,
          title: 'Not Verified',
          subtitle: 'Verify your identity to build trust with workers',
          color: kBlue,
        );
    }
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
    );
  }

  Widget _perksList() {
    const perks = [
      (Icons.verified, Colors.purple, 'Verified Badge', 'A badge visible to all workers on your profile and gig listings'),
      (Icons.trending_up, Colors.green, 'Higher Visibility', 'Verified hosts appear higher in worker search results'),
      (Icons.people_alt_outlined, Colors.blue, 'More Applicants', 'Workers are more likely to apply to gigs from verified hosts'),
      (Icons.security_outlined, Colors.orange, 'Trust & Safety', 'Show workers that your business is legitimate and trustworthy'),
    ];

    return Column(
      spacing: 10,
      children: perks
          .map((p) => PerkCard(icon: p.$1, iconColor: p.$2, title: p.$3, description: p.$4))
          .toList(),
    );
  }

  Widget _processList() {
    return Column(
      children: [
        _processStep('1', 'Submit Request', 'Tap the button below to send your verification request'),
        _processConnector(),
        _processStep('2', 'Manual Review', 'Our team reviews your profile and account activities within 24–48 hours'),
        _processConnector(),
        _processStep('3', 'Get Verified', "You'll receive a notification once your account is approved"),
      ],
    );
  }

  Widget _processStep(String step, String title, String desc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        spacing: 14,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kBlue.withAlpha(25),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              step,
              style: TextStyle(color: kBlue, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _processConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 31),
      child: Container(width: 1.5, height: 10, color: Colors.grey.shade300),
    );
  }

  Widget _submitButton() {
    final label = _isVerified == 'rejected' ? 'Resubmit Verification Request' : 'Submit Verification Request';
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _handleSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isVerified == 'rejected' ? Colors.red : kBlue,
          disabledBackgroundColor: kBlue.withAlpha(120),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _cancelButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _isSubmitting ? null : _handleCancel,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2),
              )
            : const Text(
                'Cancel Verification Request',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  void _handleSubmit() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSubmitting = true);

    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      await _firestore.collection('verification_requests').doc(uid).set({
        'userId'       : uid,
        'name'         : userData['name'] ?? '',
        'email'        : userData['email'] ?? '',
        'phone'        : userData['phone'] ?? '',
        'photoUrl'     : userData['photoUrl'] ?? '',
        'status'       : 'pending',
        'submittedAt'  : FieldValue.serverTimestamp(),
        'reviewedAt'   : null,
        'reviewedBy'   : null,
        'rejectReason' : null,
        'attemptCount' : FieldValue.increment(1),
      }, SetOptions(merge: true));

      await _firestore.collection('users').doc(uid).update({
        'isVerified': 'pending',
      });

      if (mounted) {
        setState(() => _isVerified = 'pending');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.hourglass_empty, color: Colors.white),
              SizedBox(width: 10),
              Expanded(child: Text('Verification request submitted!')),
            ]),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to submit request. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _handleCancel() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSubmitting = true);

    try {
      await _firestore.collection('verification_requests').doc(uid).update({
        'status'      : 'cancelled',
        'cancelledAt' : FieldValue.serverTimestamp(),
      });

      await _firestore.collection('users').doc(uid).update({
        'isVerified': 'unverified',
      });

      if (mounted) {
        setState(() => _isVerified = 'unverified');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.cancel_outlined, color: Colors.white),
              SizedBox(width: 10),
              Expanded(child: Text('Verification request cancelled.')),
            ]),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to cancel request. Please try again.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

class StatusBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badgeLabel;
  final Color color;

  const StatusBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withBlue((color.blue + 40).clamp(0, 255))],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFCFDFF8),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (badgeLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(35),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badgeLabel!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PerkCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;

  const PerkCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        spacing: 14,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}