import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../dev_actions.dart';
import '../dev_toggles.dart';
import '../models/dev_action.dart';
import '../models/dev_toggle.dart';

class DevOptionsSheet {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The sheet's own context dies with it on tap, so actions are handed
      // the caller's context instead — a dialog opened from a row outlives
      // the sheet that launched it.
      builder: (_) => _DevOptionsSheetBody(hostContext: context),
    );
  }
}

class _DevOptionsSheetBody extends StatelessWidget {
  final BuildContext hostContext;

  const _DevOptionsSheetBody({required this.hostContext});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: isDark ? kCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.developer_mode_rounded, color: kAmber, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Developer Options',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF17263D),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Internal testing switches — not visible to regular users.',
              style: TextStyle(fontSize: 12, color: kSub),
            ),
            const SizedBox(height: 8),
            for (final toggle in devToggles) _DevToggleRow(toggle: toggle),
            if (devActions.isNotEmpty) ...[
              const Divider(height: 24),
              Text(
                'PREVIEWS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: kSub,
                ),
              ),
              const SizedBox(height: 4),
              for (final action in devActions)
                _DevActionRow(action: action, hostContext: hostContext),
            ],
          ],
        ),
      ),
    );
  }
}

class _DevToggleRow extends StatefulWidget {
  final DevToggleDescriptor toggle;
  const _DevToggleRow({required this.toggle});

  @override
  State<_DevToggleRow> createState() => _DevToggleRowState();
}

class _DevToggleRowState extends State<_DevToggleRow> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    widget.toggle.getValue().then((v) {
      if (mounted) setState(() => _value = v);
    });
  }

  Future<void> _onChanged(bool value) async {
    setState(() => _value = value); // optimistic — sheet stays responsive
    await widget.toggle.setValue(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_value == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      activeThumbColor: kAmber,
      title: Text(
        widget.toggle.label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        widget.toggle.description,
        style: TextStyle(fontSize: 12, color: kSub),
      ),
      value: _value!,
      onChanged: _onChanged,
    );
  }
}


class _DevActionRow extends StatelessWidget {
  final DevActionDescriptor action;
  final BuildContext hostContext;

  const _DevActionRow({required this.action, required this.hostContext});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(action.icon, color: kAmber, size: 22),
      title: Text(
        action.label,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        action.description,
        style: TextStyle(fontSize: 12, color: kSub),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: kSub, size: 20),
      onTap: () {
        Navigator.pop(context);
        action.run(hostContext);
      },
    );
  }
}
