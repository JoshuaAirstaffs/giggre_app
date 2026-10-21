import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/profile_tab_theme.dart';
import '../services/wallet_requests_service.dart';
import 'send_amount_screen.dart';
import 'widgets/wallet_page_header.dart';

/// "Choose Recipient" for Send. The user types a PH mobile number; a
/// contacts list will sit below once contact access is added.
///
/// Not wired up yet:
///  • Contacts — needs a contacts package (e.g. flutter_contacts), the
///    READ_CONTACTS / NSContactsUsageDescription permissions, and a Google
///    Play "contacts" permission declaration.
///  Tapping the matched number looks it up server-side
///  (lookupWalletRecipient) and opens SendAmountScreen.
class ChooseRecipientScreen extends StatefulWidget {
  const ChooseRecipientScreen({super.key, this.role});

  final String? role;

  @override
  State<ChooseRecipientScreen> createState() => _ChooseRecipientScreenState();
}

class _ChooseRecipientScreenState extends State<ChooseRecipientScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Digits after +63, e.g. "9171234567".
  String get _digits => _controller.text.replaceAll(' ', '');

  /// PH mobile: 10 digits starting with 9.
  bool get _isValid => RegExp(r'^9\d{9}$').hasMatch(_digits);

  String get _pretty {
    final d = _digits;
    if (d.length != 10) return '+63 $d';
    return '+63 ${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
  }

  bool _looking = false;

  Future<void> _lookup() async {
    if (_looking) return;
    setState(() => _looking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final config = await WalletRequestsService.fetchConfig();
      if (!config.canSend) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Send isn't available right now.")),
        );
        return;
      }
      final r = await WalletRequestsService.lookupRecipient('+63$_digits');
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SendAmountScreen(
            role: widget.role,
            recipient: r,
            config: config,
          ),
        ),
      );
    } on WalletRequestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is coming soon.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<ProfileTabTokens>()!;
    final accent = walletAccentFor(widget.role);

    return Scaffold(
      backgroundColor: tokens.screenBg,
      appBar: AppBar(
        backgroundColor: tokens.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close',
          icon: Icon(Icons.close_rounded, color: tokens.textPrimary),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Choose Recipient',
          style: TextStyle(
            color: tokens.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: tokens.divider),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ── Mobile number field ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isValid ? accent : tokens.cardBorder,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Text('🇵🇭', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Text(
                      '+63',
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: tokens.divider,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        keyboardType: TextInputType.phone,
                        cursorColor: accent,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        style: TextStyle(
                          color: tokens.textPrimary,
                          fontSize: 15,
                          letterSpacing: 0.3,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter a mobile number',
                          hintStyle: TextStyle(
                            color: tokens.textMuted,
                            fontSize: 15,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                    if (_controller.text.isNotEmpty)
                      GestureDetector(
                        onTap: _controller.clear,
                        child: Icon(
                          Icons.cancel_rounded,
                          size: 18,
                          color: tokens.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Matched number → recipient row ───────────────────────────
            if (_isValid)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Material(
                  color: tokens.cardSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: tokens.cardBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _looking ? null : _lookup,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.person_rounded,
                              color: accent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Send to $_pretty',
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Giggre account',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: tokens.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Contacts (empty state until access is added) ─────────────
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Allow Giggre to access your contacts to send '
                        'money easily.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => _comingSoon('Contact access'),
                        style: TextButton.styleFrom(foregroundColor: accent),
                        child: const Text(
                          'Allow access',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
