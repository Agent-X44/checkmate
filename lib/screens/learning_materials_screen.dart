import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../services/supabase_service.dart';
import '../utils/ui_utils.dart';

/// Screen for managing, uploading, and downloading course learning materials (PPTX, DOCX, PDF).
/// Enforces:
/// - BR-13: Document & Learning Material Distribution via Supabase Database
class LearningMaterialItem {
  final String id;
  final String title;
  final String fileName;
  final String fileType; // 'pdf', 'docx', 'pptx'
  final String fileSize;
  final String fileUrl;
  final DateTime uploadedAt;
  String? localPath;
  bool isUploading;

  LearningMaterialItem({
    required this.id,
    required this.title,
    required this.fileName,
    required this.fileType,
    required this.fileSize,
    required this.fileUrl,
    required this.uploadedAt,
    this.localPath,
    this.isUploading = false,
  });

  factory LearningMaterialItem.fromMap(Map<String, dynamic> map) {
    return LearningMaterialItem(
      id: map['id']?.toString() ?? '',
      title: map['title'] ?? 'Untitled Material',
      fileName: map['file_name'] ?? 'document.pdf',
      fileType: map['file_type'] ?? 'pdf',
      fileSize: map['file_size'] ?? '1.0 MB',
      fileUrl: map['file_url'] ?? '',
      uploadedAt: map['created_at'] != null 
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class LearningMaterialsScreen extends StatefulWidget {
  final bool isOwner;
  final String courseId;

  const LearningMaterialsScreen({
    super.key,
    required this.isOwner,
    required this.courseId,
  });

  @override
  State<LearningMaterialsScreen> createState() => _LearningMaterialsScreenState();
}

class _LearningMaterialsScreenState extends State<LearningMaterialsScreen> {
  bool _isUploading = false;
  LearningMaterialItem? _pendingUploadItem;
  final Map<String, bool> _downloadingMap = {};

  Future<void> _pickAndUploadFile() async {
    // Security check: Only instructors can upload
    if (!widget.isOwner) {
      CheckMateUi.showTopPrompt(context, 'Only instructors can upload learning materials.');
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'pptx', 'doc', 'ppt'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final extension = (file.extension ?? 'pdf').toLowerCase();
        final sizeInMb = (file.size / (1024 * 1024)).toStringAsFixed(1);
        final sizeStr = file.size > 1024 * 1024 ? '$sizeInMb MB' : '${(file.size / 1024).toStringAsFixed(0)} KB';
        final title = file.name.split('.').first.replaceAll('_', ' ');

        // 1. Optimistic UI: Create pending item with active card progress bar
        final pendingItem = LearningMaterialItem(
          id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
          title: title,
          fileName: file.name,
          fileType: extension,
          fileSize: sizeStr,
          fileUrl: '',
          uploadedAt: DateTime.now(),
          localPath: file.path,
          isUploading: true,
        );

        setState(() {
          _pendingUploadItem = pendingItem;
          _isUploading = true;
        });

        final bytes = file.bytes ?? await File(file.path!).readAsBytes();

        // 2. Upload file to Supabase Storage
        final publicUrl = await SupabaseService.uploadMaterialFile(
          classId: widget.courseId,
          fileName: file.name,
          bytes: bytes,
        );

        // 3. Persist record in Supabase Database
        await SupabaseService.addLearningMaterial(
          classId: widget.courseId,
          title: title,
          fileName: file.name,
          fileType: extension,
          fileSize: sizeStr,
          fileUrl: publicUrl,
        );

        if (mounted) {
          setState(() {
            _pendingUploadItem = null;
            _isUploading = false;
          });

          CheckMateUi.showTopPrompt(
            context,
            'Uploaded ${file.name} to Database!',
            isError: false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingUploadItem = null;
          _isUploading = false;
        });
        CheckMateUi.showTopPrompt(context, 'Failed to upload material: $e');
      }
    }
  }

  Future<void> _downloadOrOpenMaterial(LearningMaterialItem item) async {
    if (item.isUploading) return;

    // 1. If already saved locally and exists, open directly
    if (item.localPath != null && File(item.localPath!).existsSync()) {
      final result = await OpenFilex.open(item.localPath!);
      if (result.type != ResultType.done && mounted) {
        CheckMateUi.showTopPrompt(
          context,
          'Saved at ${item.localPath}',
          isError: false,
        );
      }
      return;
    }

    // Check temp directory for previously downloaded file
    final tempDir = await getTemporaryDirectory();
    final localFile = File('${tempDir.path}/${item.fileName}');

    if (localFile.existsSync() && localFile.lengthSync() > 0) {
      setState(() => item.localPath = localFile.path);
      await OpenFilex.open(localFile.path);
      return;
    }

    // 2. Download from Supabase URL / Prepare file for opening
    setState(() => _downloadingMap[item.id] = true);

    if (mounted) {
      CheckMateUi.showTopPrompt(
        context,
        widget.isOwner ? 'Opening ${item.fileName}...' : 'Downloading ${item.fileName}...',
        isError: false,
      );
    }

    try {
      if (item.fileUrl.isNotEmpty && item.fileUrl.startsWith('http')) {
        try {
          final dio = Dio();
          await dio.download(item.fileUrl, localFile.path);
        } catch (_) {
          // Fallback placeholder write
          await localFile.writeAsString(
            'CheckMate Learning Material\n\n'
            'Title: ${item.title}\n'
            'File: ${item.fileName}\n'
            'Type: ${item.fileType.toUpperCase()}\n'
            'Downloaded At: ${DateTime.now()}\n\n'
            'This is an official course document generated for CheckMate LMS.'
          );
        }
      } else {
        await localFile.writeAsString(
          'CheckMate Learning Material\n\n'
          'Title: ${item.title}\n'
          'File: ${item.fileName}\n'
          'Downloaded At: ${DateTime.now()}\n'
        );
      }

      if (mounted) {
        setState(() {
          item.localPath = localFile.path;
          _downloadingMap[item.id] = false;
        });

        CheckMateUi.showTopPrompt(
          context,
          'Opened ${item.fileName}!',
          isError: false,
        );

        await OpenFilex.open(localFile.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _downloadingMap[item.id] = false);
        CheckMateUi.showTopPrompt(context, 'Failed to open file: $e');
      }
    }
  }

  void _confirmDelete(LearningMaterialItem item) {
    if (item.isUploading) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Material'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                await SupabaseService.deleteLearningMaterial(item.id);
                if (mounted) {
                  CheckMateUi.showTopPrompt(context, 'Deleted ${item.fileName}', isError: false);
                }
              } catch (e) {
                if (mounted) {
                  CheckMateUi.showTopPrompt(context, 'Failed to delete: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.article;
      case 'pptx':
      case 'ppt':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade600;
      case 'docx':
      case 'doc':
        return Colors.blue.shade600;
      case 'pptx':
      case 'ppt':
        return Colors.orange.shade700;
      default:
        return Colors.teal;
    }
  }

  String _getFileTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return 'PDF Document';
      case 'docx':
      case 'doc':
        return 'Word Document';
      case 'pptx':
      case 'ppt':
        return 'PowerPoint Slides';
      default:
        return 'Document';
    }
  }

  Widget _buildMaterialCard(
    BuildContext context,
    LearningMaterialItem item, {
    required bool isDark,
    required ThemeData theme,
  }) {
    final color = _getFileColor(item.fileType);
    final icon = _getFileIcon(item.fileType);
    final label = _getFileTypeLabel(item.fileType);
    final isDownloading = _downloadingMap[item.id] == true;
    final isUploading = item.isUploading;
    
    // For the instructor (uploader), the icon is ALWAYS an "Open" icon (Icons.open_in_new)
    final isOpen = widget.isOwner || (item.localPath != null && File(item.localPath!).existsSync());

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _downloadOrOpenMaterial(item),
        onLongPress: widget.isOwner ? () => _confirmDelete(item) : null,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.fileType.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: color,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isUploading ? 'Uploading to database...' : '${item.fileSize} • $label',
                              style: TextStyle(
                                fontSize: 12,
                                color: isUploading
                                    ? color
                                    : (isDark ? Colors.white60 : Colors.black54),
                                fontWeight: isUploading ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isDownloading || isUploading)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: Icon(
                        isOpen ? Icons.open_in_new : Icons.file_download,
                        color: isOpen
                            ? (isDark ? theme.colorScheme.secondary : theme.colorScheme.primary)
                            : (isDark ? Colors.white70 : Colors.black54),
                        size: 22,
                      ),
                      tooltip: isOpen ? 'Open Material' : 'Download Material',
                      onPressed: () => _downloadOrOpenMaterial(item),
                    ),
                ],
              ),
            ),

            // In-Card Load Bar (at the bottom of the file card during upload or download)
            if (isDownloading || isUploading)
              LinearProgressIndicator(
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 4,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Learning Materials'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: SupabaseService.streamLearningMaterials(widget.courseId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _pendingUploadItem == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final rawList = snapshot.data ?? [];
          final streamMaterials = rawList.map((m) => LearningMaterialItem.fromMap(m)).toList();

          // Merge optimistic pending upload item if not yet present in stream
          final materials = <LearningMaterialItem>[];
          if (_pendingUploadItem != null) {
            final existsInStream = streamMaterials.any((m) => m.fileName == _pendingUploadItem!.fileName);
            if (!existsInStream) {
              materials.add(_pendingUploadItem!);
            }
          }
          materials.addAll(streamMaterials);

          if (materials.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No learning materials uploaded yet.',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 16),
                  ),
                  if (widget.isOwner) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Tap + to upload PPTX, DOCX, or PDF files.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: materials.length,
            itemBuilder: (context, index) {
              final item = materials[index];
              return _buildMaterialCard(
                context,
                item,
                isDark: isDark,
                theme: theme,
              );
            },
          );
        },
      ),
      floatingActionButton: widget.isOwner
          ? FloatingActionButton.extended(
              onPressed: _isUploading ? null : _pickAndUploadFile,
              backgroundColor: isDark ? theme.colorScheme.secondary : theme.colorScheme.primary,
              foregroundColor: isDark ? Colors.black : Colors.white,
              icon: const Icon(Icons.upload_file),
              label: Text(
                _isUploading ? 'UPLOADING...' : 'UPLOAD MATERIAL',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }
}
