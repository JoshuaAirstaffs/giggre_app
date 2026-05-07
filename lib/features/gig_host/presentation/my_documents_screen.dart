import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class MyDocumentsScreen extends StatefulWidget {
  final String userId;
  const MyDocumentsScreen({super.key, required this.userId});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  static const Color _indeedBlue = Color(0xFF2164F3);
  static const Color _hostOrange = Color(0xFFF57C00);

  static const List<_DocCategory> _workerCategories = [
    _DocCategory(
      key: 'worker_valid_id',
      label: 'Valid ID',
      subtitle: 'Government-issued ID (e.g. Passport, Driver\'s License, National ID)',
      icon: Icons.badge_outlined,
      color: Color(0xFFE8F0FE),
      iconColor: Color(0xFF2164F3),
      maxFiles: 2,
    ),
    _DocCategory(
      key: 'worker_skill_certificate',
      label: 'Skill Certificates',
      subtitle: 'Training certificates, licenses, or other credentials',
      icon: Icons.workspace_premium_outlined,
      color: Color(0xFFF3E5F5),
      iconColor: Color(0xFF7B1FA2),
      maxFiles: 5,
    ),
    _DocCategory(
      key: 'worker_resume',
      label: 'Resume / CV',
      subtitle: 'Your latest resume or curriculum vitae',
      icon: Icons.description_outlined,
      color: Color(0xFFE0F7FA),
      iconColor: Color(0xFF00838F),
      maxFiles: 1,
    ),
    _DocCategory(
      key: 'worker_other',
      label: 'Other Documents',
      subtitle: 'Any other supporting documents',
      icon: Icons.folder_outlined,
      color: Color(0xFFE8F5E9),
      iconColor: Color(0xFF388E3C),
      maxFiles: 5,
    ),
  ];

  static const List<_DocCategory> _hostCategories = [
    _DocCategory(
      key: 'host_valid_id',
      label: 'Valid ID',
      subtitle: 'Government-issued ID (e.g. Passport, Driver\'s License, National ID)',
      icon: Icons.badge_outlined,
      color: Color(0xFFE8F0FE),
      iconColor: Color(0xFF2164F3),
      maxFiles: 2,
    ),
    _DocCategory(
      key: 'host_business_certificate',
      label: 'Business Certificate',
      subtitle: 'Business registration or permit documents',
      icon: Icons.business_center_outlined,
      color: Color(0xFFFFF3E0),
      iconColor: Color(0xFFF57C00),
      maxFiles: 3,
    ),
    _DocCategory(
      key: 'host_business_permit',
      label: 'Business Permit',
      subtitle: 'Local or municipal business operating permit',
      icon: Icons.verified_outlined,
      color: Color(0xFFFCE4EC),
      iconColor: Color(0xFFC62828),
      maxFiles: 2,
    ),
    _DocCategory(
      key: 'host_tax_document',
      label: 'Tax Documents',
      subtitle: 'Tax identification or compliance documents',
      icon: Icons.receipt_long_outlined,
      color: Color(0xFFEDE7F6),
      iconColor: Color(0xFF4527A0),
      maxFiles: 3,
    ),
    _DocCategory(
      key: 'host_other',
      label: 'Other Documents',
      subtitle: 'Any other supporting documents',
      icon: Icons.folder_outlined,
      color: Color(0xFFE8F5E9),
      iconColor: Color(0xFF388E3C),
      maxFiles: 5,
    ),
  ];

  final Map<String, List<Map<String, String>>> _uploadedDocs = {};
  final Map<String, double?> _uploadProgress = {};

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .collection('documents')
        .get();

    final Map<String, List<Map<String, String>>> loaded = {};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final category = data['category'] as String;
      loaded.putIfAbsent(category, () => []);
      loaded[category]!.add({
        'docId': doc.id,
        'name': data['name'] ?? '',
        'url': data['url'] ?? '',
        'path': data['storagePath'] ?? '',
        'fileSize': data['fileSize']?.toString() ?? '',
      });
    }

    setState(() {
      _uploadedDocs.addAll(loaded);
    });
  }

  Future<bool> _requestPermission() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 33) {
      final photos = await Permission.photos.request();
      final videos = await Permission.videos.request();
      return photos.isGranted || videos.isGranted;
    } else {
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }
  }

  void _showResultModal({
    required bool success,
    required String title,
    required String message,
  }) {
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: (success ? Colors.green : Colors.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                success ? Icons.check_circle_outline : Icons.error_outline,
                color: success ? Colors.green : Colors.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: onSurface.withOpacity(0.55)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: success ? Colors.green : Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(_DocCategory category) async {
    final granted = await _requestPermission();
    if (!granted) {
      if (mounted) {
        _showResultModal(
          success: false,
          title: 'Permission Denied',
          message: 'Storage permission is required to upload files. Please enable it in settings.',
        );
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null) return;

    final file = File(result.files.single.path!);
    final fileName = result.files.single.name;
    final fileSize = result.files.single.size;
    final storagePath =
        'users/${widget.userId}/documents/${category.key}/$fileName';

    setState(() => _uploadProgress[category.key] = 0.0);

    try {
      final ref = FirebaseStorage.instance.ref().child(storagePath);
      final uploadTask = ref.putFile(file);

      uploadTask.snapshotEvents.listen((snap) {
        if (snap.totalBytes > 0 && mounted) {
          setState(() {
            _uploadProgress[category.key] =
                snap.bytesTransferred / snap.totalBytes;
          });
        }
      });

      await uploadTask;
      final url = await ref.getDownloadURL();

      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .collection('documents')
          .add({
            'category': category.key,
            'name': fileName,
            'url': url,
            'storagePath': storagePath,
            'fileSize': fileSize,
            'uploadedAt': FieldValue.serverTimestamp(),
          });

      setState(() {
        _uploadedDocs.putIfAbsent(category.key, () => []);
        _uploadedDocs[category.key]!.add({
          'docId': docRef.id,
          'name': fileName,
          'url': url,
          'path': storagePath,
          'fileSize': fileSize.toString(),
        });
      });

      if (mounted) {
        _showResultModal(
          success: true,
          title: 'Upload Successful',
          message: '$fileName has been uploaded successfully.',
        );
      }
    } catch (e) {
      if (mounted) {
        _showResultModal(
          success: false,
          title: 'Upload Failed',
          message: 'Failed to upload $fileName. Please try again.',
        );
      }
    } finally {
      setState(() => _uploadProgress[category.key] = null);
    }
  }

  Future<void> _deleteDocument(
    _DocCategory category,
    Map<String, String> doc,
  ) async {
    final name = doc['name'] ?? '';
    final isPdf = name.toLowerCase().endsWith('.pdf');
    final isImage = name.toLowerCase().endsWith('.jpg') ||
        name.toLowerCase().endsWith('.jpeg') ||
        name.toLowerCase().endsWith('.png');
    final url = doc['url'] ?? '';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        bool isDeleting = false;

        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.all(24),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  'Delete Document',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: isImage && url.isNotEmpty
                            ? Image.network(url,
                                width: 40, height: 40, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 40, height: 40,
                                  color: _indeedBlue.withOpacity(0.1),
                                  child: const Icon(Icons.image, size: 20, color: _indeedBlue),
                                ),
                              )
                            : Container(
                                width: 40, height: 40,
                                color: isPdf
                                    ? Colors.red.withOpacity(0.1)
                                    : _indeedBlue.withOpacity(0.1),
                                child: Icon(
                                  isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file_outlined,
                                  size: 20,
                                  color: isPdf ? Colors.red : _indeedBlue,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              category.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: onSurface.withOpacity(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This action cannot be undone.',
                  style: TextStyle(fontSize: 13, color: onSurface.withOpacity(0.45)),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: onSurface.withOpacity(0.15)),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: onSurface.withOpacity(isDeleting ? 0.3 : 0.55),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isDeleting
                            ? null
                            : () async {
                                setDialogState(() => isDeleting = true);
                                try {
                                  await FirebaseStorage.instance
                                      .ref()
                                      .child(doc['path']!)
                                      .delete();
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(widget.userId)
                                      .collection('documents')
                                      .doc(doc['docId'])
                                      .delete();
                                  setState(() {
                                    _uploadedDocs[category.key]?.remove(doc);
                                  });
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    _showResultModal(
                                      success: true,
                                      title: 'Document Deleted',
                                      message: '$name has been deleted successfully.',
                                    );
                                  }
                                } catch (e) {
                                  setDialogState(() => isDeleting = false);
                                  if (mounted) {
                                    _showResultModal(
                                      success: false,
                                      title: 'Delete Failed',
                                      message: 'Failed to delete $name. Please try again.',
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: isDeleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Delete',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _previewDocument(Map<String, String> doc) {
    final name = doc['name'] ?? '';
    final url = doc['url'] ?? '';
    final isPdf = name.toLowerCase().endsWith('.pdf');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            if (isPdf)
              Container(
                height: 300,
                color: Colors.grey[900],
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.red, size: 64),
                      SizedBox(height: 12),
                      Text(
                        'PDF Preview not available.\nOpen in browser to view.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                ),
                color: Colors.black,
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return SizedBox(
                        height: 300,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!
                                : null,
                            color: _indeedBlue,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => const SizedBox(
                      height: 300,
                      child: Center(
                        child: Icon(Icons.broken_image,
                            color: Colors.white38, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showCategoryBottomSheet(_DocCategory category) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cardColor = Theme.of(ctx).cardColor;
        final onSurface = Theme.of(ctx).colorScheme.onSurface;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final docs = _uploadedDocs[category.key] ?? [];
            final isUploading = _uploadProgress[category.key] != null;
            final progress = _uploadProgress[category.key];
            final canUpload = docs.length < category.maxFiles;

            return Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: onSurface.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: category.color.withOpacity(isDark ? 0.2 : 1.0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(category.icon, color: category.iconColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              category.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: onSurface,
                              ),
                            ),
                            Text(
                              category.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: onSurface.withOpacity(0.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${docs.length}/${category.maxFiles}',
                        style: TextStyle(
                          fontSize: 13,
                          color: onSurface.withOpacity(0.38),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Uploaded files list
                  if (docs.isNotEmpty) ...[
                    ...docs.map((doc) => _buildDocTileSheet(category, doc, onSurface, isDark)),
                    const SizedBox(height: 8),
                  ],

                  // Empty state
                  if (docs.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            color: onSurface.withOpacity(0.26),
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No files uploaded yet',
                            style: TextStyle(
                              fontSize: 13,
                              color: onSurface.withOpacity(0.38),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Upload progress bar
                  if (isUploading && progress != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: _indeedBlue.withOpacity(0.12),
                        valueColor: const AlwaysStoppedAnimation(_indeedBlue),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Uploading... ${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: _indeedBlue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Upload button
                  if (canUpload)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isUploading
                            ? null
                            : () async {
                                Navigator.pop(context);
                                await _pickAndUpload(category);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _indeedBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: isUploading
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                  value: progress,
                                ),
                              )
                            : const Icon(Icons.upload_outlined, size: 18),
                        label: Text(
                          isUploading
                              ? 'Uploading ${((progress ?? 0) * 100).toInt()}%...'
                              : 'Upload File',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: onSurface.withOpacity(0.38),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Maximum files reached',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: onSurface.withOpacity(0.38),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDocTileSheet(
    _DocCategory category,
    Map<String, String> doc,
    Color onSurface,
    bool isDark,
  ) {
    final name = doc['name'] ?? 'Document';
    final url = doc['url'] ?? '';
    final isPdf = name.toLowerCase().endsWith('.pdf');
    final isImage = name.toLowerCase().endsWith('.jpg') ||
        name.toLowerCase().endsWith('.jpeg') ||
        name.toLowerCase().endsWith('.png');
    final sizeBytes = int.tryParse(doc['fileSize'] ?? '');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _previewDocument(doc),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isImage && url.isNotEmpty
              ? Image.network(
                  url,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 36,
                      height: 36,
                      color: _indeedBlue.withOpacity(0.1),
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    width: 36,
                    height: 36,
                    color: _indeedBlue.withOpacity(0.1),
                    child: const Icon(Icons.broken_image, size: 18, color: _indeedBlue),
                  ),
                )
              : Container(
                  width: 36,
                  height: 36,
                  color: isPdf
                      ? Colors.red.withOpacity(0.1)
                      : _indeedBlue.withOpacity(0.1),
                  child: Icon(
                    isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file_outlined,
                    size: 18,
                    color: isPdf ? Colors.red : _indeedBlue,
                  ),
                ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: onSurface,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          sizeBytes != null
              ? '${_formatBytes(sizeBytes)}  ·  Tap to preview'
              : 'Tap to preview',
          style: TextStyle(fontSize: 11, color: onSurface.withOpacity(0.38)),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: onSurface.withOpacity(0.38), size: 20),
          onPressed: () async {
            Navigator.pop(context);
            await _deleteDocument(category, doc);
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryGrid(List<_DocCategory> categories) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (context, index) =>
          _buildCategoryGridCard(categories[index]),
    );
  }

Widget _buildCategoryGridCard(_DocCategory category) {
  final cardColor = Theme.of(context).cardColor;
  final onSurface = Theme.of(context).colorScheme.onSurface;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final docs = _uploadedDocs[category.key] ?? [];
  final isUploading = _uploadProgress[category.key] != null;
  final progress = _uploadProgress[category.key];
  final canUpload = docs.length < category.maxFiles;

  return GestureDetector(
    onTap: () => _showCategoryBottomSheet(category),
    child: Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + count
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: category.color.withOpacity(isDark ? 0.2 : 1.0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(category.icon, color: category.iconColor, size: 18),
              ),
              Text(
                '${docs.length}/${category.maxFiles}',
                style: TextStyle(fontSize: 11, color: onSurface.withOpacity(0.38)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Label + subtitle — Expanded absorbs remaining space
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  category.subtitle,
                  style: TextStyle(fontSize: 11, color: onSurface.withOpacity(0.45)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Progress bar — only when uploading
          if (isUploading && progress != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: _indeedBlue.withOpacity(0.12),
                valueColor: const AlwaysStoppedAnimation(_indeedBlue),
              ),
            ),
            const SizedBox(height: 6),
          ],

          // Bottom status row
          Row(
            children: [
              isUploading
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: _indeedBlue,
                        value: progress,
                      ),
                    )
                  : Icon(
                      canUpload
                          ? Icons.upload_outlined
                          : Icons.check_circle_outline,
                      size: 13,
                      color: canUpload ? _indeedBlue : Colors.green,
                    ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  isUploading
                      ? '${((progress ?? 0) * 100).toInt()}%'
                      : canUpload
                          ? 'Upload File'
                          : 'Max reached',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: canUpload ? _indeedBlue : onSurface.withOpacity(0.38),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (docs.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _indeedBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${docs.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _indeedBlue,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Documents',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: _indeedBlue,
        onRefresh: () async {
          setState(() => _uploadedDocs.clear());
          await _loadDocuments();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _indeedBlue.withOpacity(isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: _indeedBlue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Upload clear photos or PDFs. Tap a file to preview.',
                      style: TextStyle(color: _indeedBlue, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Gig Worker Section
            _sectionHeader('Gig Worker', Icons.work_outline, _indeedBlue),
            _buildCategoryGrid(_workerCategories),

            const SizedBox(height: 16),

            // Gig Host Section
            _sectionHeader('Gig Host', Icons.business_center_outlined, _hostOrange),
            _buildCategoryGrid(_hostCategories),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DocCategory {
  final String key;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final int maxFiles;

  const _DocCategory({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.maxFiles,
  });
}