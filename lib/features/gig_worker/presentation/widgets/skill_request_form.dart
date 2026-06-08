import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/theme/app_colors.dart';

const _kCategories = [
  'Technical',
  'Creative',
  'Hospitality',
  'Delivery',
  'Cleaning',
  'Construction',
  'Admin',
  'Others',
];

const _kLevels = ['Beginner', 'Intermediate', 'Expert'];

class SkillRequestForm extends StatefulWidget {
  final String? initialSkillName;
  final String? initialCategory;
  final String? initialSkillId;
  final String? initialSkillDocId;
  final bool isApplyMode;

  const SkillRequestForm({
    super.key,
    this.initialSkillName,
    this.initialCategory,
    this.initialSkillId,
    this.initialSkillDocId,
    this.isApplyMode = false,
  });

  static Future<void> push(
    BuildContext context, {
    String? initialSkillName,
    String? initialCategory,
    String? initialSkillId,
    String? initialSkillDocId,
    bool isApplyMode = false,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SkillRequestForm(
          initialSkillName: initialSkillName,
          initialCategory: initialCategory,
          initialSkillId: initialSkillId,
          initialSkillDocId: initialSkillDocId,
          isApplyMode: isApplyMode,
        ),
      ),
    );
  }

  @override
  State<SkillRequestForm> createState() => _SkillRequestFormState();
}

class _SkillRequestFormState extends State<SkillRequestForm> {
  final _formKey = GlobalKey<FormState>();

  final _skillNameCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _yearsCtrl = TextEditingController();
  final _monthsCtrl = TextEditingController();
  final _relatedExpCtrl = TextEditingController();
  final _suggestedReqCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();

  String? _category;
  String? _level;
  String? _skillId;
  String? _skillDocId;

  // Proof files
  final List<PlatformFile> _proofFiles = [];
  double _uploadProgress = 0;
  bool _submitting = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSkillName != null) {
      _skillNameCtrl.text = widget.initialSkillName!;
    }
    if (widget.initialCategory != null &&
        _kCategories.contains(widget.initialCategory)) {
      _category = widget.initialCategory;
    }
    _skillId = widget.initialSkillId;
    _skillDocId = widget.initialSkillDocId;
  }

  @override
  void dispose() {
    _skillNameCtrl.dispose();
    _reasonCtrl.dispose();
    _yearsCtrl.dispose();
    _monthsCtrl.dispose();
    _relatedExpCtrl.dispose();
    _suggestedReqCtrl.dispose();
    _contactCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (!_proofFiles.any((e) => e.name == f.name)) {
          _proofFiles.add(f);
        }
      }
    });
  }

  void _removeFile(int index) => setState(() => _proofFiles.removeAt(index));

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_category == null) {
      _snack('Please select a skill category.');
      return;
    }
    if (_level == null) {
      _snack('Please select an experience level.');
      return;
    }

    setState(() {
      _submitting = true;
      _uploadProgress = 0;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data() ?? {};
      final userName = userData['name'] as String? ?? '';
      final userEmail = userData['email'] as String? ?? '';
      final gigWorkerId = userData['userId'] as String? ?? uid;

      // Upload proof files
      final List<String> proofUrls = [];
      final List<String> proofPaths = [];
      final List<String> proofNames = [];

      for (int i = 0; i < _proofFiles.length; i++) {
        final pf = _proofFiles[i];
        if (pf.path == null) continue;
        final file = File(pf.path!);
        final ts = DateTime.now().millisecondsSinceEpoch;
        final storagePath = 'skill_requests/$uid/${ts}_${pf.name}';
        final ref = FirebaseStorage.instance.ref().child(storagePath);
        final task = ref.putFile(file);

        task.snapshotEvents.listen((snap) {
          if (snap.totalBytes > 0 && mounted) {
            setState(() {
              _uploadProgress =
                  (i + snap.bytesTransferred / snap.totalBytes) /
                      _proofFiles.length;
            });
          }
        });

        await task;
        proofUrls.add(await ref.getDownloadURL());
        proofPaths.add(storagePath);
        proofNames.add(pf.name);
      }

      // Save to Firestore
      await FirebaseFirestore.instance.collection('skill_requests').add({
        'userId': uid,
        'gigWorkerId': gigWorkerId,
        'skillId': _skillId ?? '',
        'skill_req_Id': _skillDocId ?? '',
        'userName': userName,
        'userEmail': userEmail,
        'skillName': _skillNameCtrl.text.trim(),
        'skillCategory': _category,
        'reason': _reasonCtrl.text.trim(),
        'experienceLevel': _level,
        'experienceDuration':
            '${_yearsCtrl.text.trim()} year/s and ${_monthsCtrl.text.trim()} month/s',
        'proofUrls': proofUrls,
        'proofPaths': proofPaths,
        'proofNames': proofNames,
        'relatedExperience': _relatedExpCtrl.text.trim(),
        'suggestedRequirement': _suggestedReqCtrl.text.trim(),
        'contactAvailability': _contactCtrl.text.trim(),
        'status': 'pending',
        'adminRemarks': '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        _snack('Submission failed. Please try again.');
        setState(() => _submitting = false);
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Request a Skill',
            style: TextStyle(
                color: onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
              height: 1,
              color: isDark ? kBorder : const Color(0xFFE2E8F0)),
        ),
      ),
      body: _done ? _buildSuccess(onSurface) : _buildForm(isDark, onSurface, cardColor),
    );
  }

  Widget _buildSuccess(Color onSurface) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFF22C55E),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 38),
            ),
            const SizedBox(height: 20),
            Text('Request Submitted!',
                style: TextStyle(
                    color: onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text(
              'Your skill request has been sent to the admin for review. You can track the status in your Toolchest.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSub, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAmber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back to Toolchest',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark, Color onSurface, Color cardColor) {
    return Stack(
      children: [
        Form(
          key: _formKey,
          child: ListView(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            children: [
              // ── 1. Skill Name ─────────────────────────────────
              _SectionHeader(
                  number: '1', title: 'Skill Name', required: true),
              const SizedBox(height: 8),
              _Field(
                controller: _skillNameCtrl,
                hint: 'e.g. Plumbing, Graphic Design, Bartending',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 20),

              // ── 2. Skill Category ─────────────────────────────
              _SectionHeader(
                  number: '2', title: 'Skill Category', required: true),
              const SizedBox(height: 8),
              _DropdownField<String>(
                value: _category,
                hint: 'Select a category',
                items: _kCategories,
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 20),

              // ── 3. Reason (Request mode only) ─────────────────
              if (!widget.isApplyMode) ...[
                _SectionHeader(
                    number: '3',
                    title: 'Why do you want this skill added?',
                    required: true),
                const SizedBox(height: 8),
                _Field(
                  controller: _reasonCtrl,
                  hint: 'Short explanation...',
                  maxLines: 3,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 20),
              ],

              // ── 4. Experience Level ───────────────────────────
              _SectionHeader(
                  number: '4', title: 'Experience Level', required: true),
              const SizedBox(height: 8),
              _LevelSelector(
                selected: _level,
                onChanged: (v) => setState(() => _level = v),
              ),
              const SizedBox(height: 20),

              // ── 5. Years/Months of Experience ─────────────────
              _SectionHeader(
                  number: '5',
                  title: 'Years or Months of Experience',
                  required: true),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NumericField(
                      controller: _yearsCtrl,
                      hint: 'Years',
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumericField(
                      controller: _monthsCtrl,
                      hint: 'Months',
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null || n < 0 || n > 11) {
                          return '0–11';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── 6. Proof Documents ────────────────────────────
              _SectionHeader(
                  number: '6',
                  title: 'Proof or Supporting Documents',
                  required: false),
              const SizedBox(height: 8),
              _ProofUploadSection(
                files: _proofFiles,
                onPick: _pickFiles,
                onRemove: _removeFile,
                isDark: isDark,
              ),
              const SizedBox(height: 20),

              // ── 7. Related Work Experience ────────────────────
              _SectionHeader(
                  number: '7',
                  title: 'Related Work Experience',
                  required: false),
              const SizedBox(height: 8),
              _Field(
                controller: _relatedExpCtrl,
                hint:
                    'Where have you used this skill before?',
                maxLines: 4,
              ),
              const SizedBox(height: 20),

              // ── 8. Suggested Requirement ──────────────────────
              _SectionHeader(
                  number: '8',
                  title: 'Suggested Requirement',
                  required: false,
                  subtitle: 'Optional: suggest what admin should require'),
              const SizedBox(height: 8),
              _Field(
                controller: _suggestedReqCtrl,
                hint:
                    'e.g. "Must upload TESDA certificate"',
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // ── 9. Contact / Availability ─────────────────────
              _SectionHeader(
                  number: '9',
                  title: 'Contact / Availability for Verification',
                  required: false,
                  subtitle: 'Optional: phone, email, or preferred time'),
              const SizedBox(height: 8),
              _Field(
                controller: _contactCtrl,
                hint: 'e.g. 09XX-XXX-XXXX, weekdays 9am–5pm',
                maxLines: 2,
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),

        // ── Fixed submit button ───────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                  top: BorderSide(
                      color: isDark
                          ? kBorder
                          : const Color(0xFFE2E8F0))),
            ),
            child: _submitting
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LinearProgressIndicator(
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                        backgroundColor: kSub.withValues(alpha: 0.2),
                        color: kAmber,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _uploadProgress > 0
                            ? 'Uploading files... ${(_uploadProgress * 100).toInt()}%'
                            : 'Submitting...',
                        style: const TextStyle(color: kSub, fontSize: 12),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kAmber,
                        foregroundColor: Colors.black,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Submit Request',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Section header
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String number;
  final String title;
  final bool required;
  final String? subtitle;

  const _SectionHeader({
    required this.number,
    required this.title,
    required this.required,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: kAmber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(number,
                    style: const TextStyle(
                        color: kAmber,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      color: onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            if (required)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Required',
                    style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(subtitle!,
                style: const TextStyle(color: kSub, fontSize: 11)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Text field
// ─────────────────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kSub, fontSize: 13),
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kSub.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kSub.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAmber),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.redAccent.withValues(alpha: 0.6)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: validator,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Numeric-only text field
// ─────────────────────────────────────────────────────────────────────────────
class _NumericField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final String? Function(String?)? validator;

  const _NumericField({
    required this.controller,
    required this.hint,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kSub, fontSize: 13),
        filled: true,
        fillColor: isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kSub.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kSub.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kAmber),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.redAccent.withValues(alpha: 0.6)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      validator: validator,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Dropdown field
// ─────────────────────────────────────────────────────────────────────────────
class _DropdownField<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSub.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: Theme.of(context).cardColor,
          style: TextStyle(color: onSurface, fontSize: 14),
          hint: Text(hint, style: const TextStyle(color: kSub, fontSize: 13)),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: kSub),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString()),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Experience level selector
// ─────────────────────────────────────────────────────────────────────────────
class _LevelSelector extends StatelessWidget {
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _LevelSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _kLevels.map((level) {
        final isSelected = selected == level;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(level),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(
                  right: level != _kLevels.last ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? kAmber.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected
                      ? kAmber
                      : kSub.withValues(alpha: 0.25),
                ),
              ),
              child: Center(
                child: Text(level,
                    style: TextStyle(
                        color: isSelected ? kAmber : kSub,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Proof upload section
// ─────────────────────────────────────────────────────────────────────────────
class _ProofUploadSection extends StatelessWidget {
  final List<PlatformFile> files;
  final VoidCallback onPick;
  final void Function(int) onRemove;
  final bool isDark;

  const _ProofUploadSection({
    required this.files,
    required this.onPick,
    required this.onRemove,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (files.isNotEmpty) ...[
          ...files.asMap().entries.map((e) => _FileChip(
                name: e.value.name,
                onRemove: () => onRemove(e.key),
              )),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: kSub.withValues(alpha: 0.2),
                  style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file_rounded,
                    color: kSub.withValues(alpha: 0.6), size: 28),
                const SizedBox(height: 6),
                const Text('Tap to upload files',
                    style: TextStyle(color: kSub, fontSize: 12)),
                const Text('PDF, JPG, PNG',
                    style: TextStyle(color: kSub, fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FileChip extends StatelessWidget {
  final String name;
  final VoidCallback onRemove;

  const _FileChip({required this.name, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kAmber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kAmber.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined,
              color: kAmber, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name,
                style: const TextStyle(color: kAmber, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, color: kSub, size: 16),
          ),
        ],
      ),
    );
  }
}
