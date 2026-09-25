import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/messaging_service.dart';
import '../utils/ui_utils.dart';
import 'private_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  final Course course;
  const ChatScreen({super.key, required this.course});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _announcementController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  bool _isComposingAnnouncement = false;
  String? _selectedAttachment;

  @override
  void initState() {
    super.initState();
    _loadStreamPosts();
  }

  Future<void> _loadStreamPosts() async {
    final savedPosts = await MessagingService.loadStreamPosts(
        widget.course.id, widget.course.name);
    if (savedPosts.isNotEmpty) {
      if (mounted) {
        setState(() {
          widget.course.streamPosts.clear();
          widget.course.streamPosts.addAll(savedPosts);
        });
      }
    } else {
      _initSamplePosts();
      await MessagingService.saveStreamPosts(
          widget.course.id, widget.course.name, widget.course.streamPosts);
      if (mounted) setState(() {});
    }
  }

  void _initSamplePosts() {
    if (widget.course.streamPosts.isNotEmpty) return;

    widget.course.streamPosts.addAll([
      StreamPost(
        id: 'post_1',
        authorName: widget.course.instructor,
        authorRole: 'Instructor',
        content:
            'Good Evening,\nAttached is the schedule per batch of your examination tomorrow, Tuesday. See the attached file so you can plan your travel ahead.',
        timestamp: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
        postType: 'announcement',
        attachmentName: 'Schedule for ${widget.course.name} Prelim Exam.pdf',
        attachmentType: 'pdf',
        comments: [
          ClassComment(
            id: 'c1',
            authorName: 'Alex Student',
            text: 'Thank you prof! Will review the schedule.',
            timestamp:
                DateTime.now().subtract(const Duration(days: 2, hours: 2)),
            isMe: false,
          ),
        ],
        allowComments: true,
        isMe: widget.course.isOwner,
      ),
      StreamPost(
        id: 'post_2',
        authorName: widget.course.instructor,
        authorRole: 'Instructor',
        title: 'New material: General Instructions for Competition',
        content:
            'Please review the attached reference guidelines prior to starting your activity.',
        timestamp: DateTime.now().subtract(const Duration(days: 6)),
        postType: 'material',
        allowComments: true,
        isMe: widget.course.isOwner,
      ),
      StreamPost(
        id: 'post_3',
        authorName: widget.course.instructor,
        authorRole: 'Instructor',
        content:
            'Good afternoon, everyone.\nPlease form groups with a maximum of five (5) members for our final course activities. You may also choose to work individually or in smaller groups.',
        timestamp: DateTime.now().subtract(const Duration(days: 10)),
        postType: 'announcement',
        allowComments: true,
        isMe: widget.course.isOwner,
      ),
    ]);
  }

  Future<void> _postAnnouncement() async {
    final text = _announcementController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      widget.course.streamPosts.insert(
        0,
        StreamPost(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          authorName: widget.course.instructor,
          authorRole: 'Instructor',
          content: text,
          timestamp: DateTime.now(),
          postType: 'announcement',
          attachmentName: _selectedAttachment,
          attachmentType: _selectedAttachment != null ? 'pdf' : null,
          allowComments: true,
          isMe: true,
        ),
      );
      _announcementController.clear();
      _selectedAttachment = null;
      _isComposingAnnouncement = false;
    });

    await MessagingService.saveStreamPosts(
        widget.course.id, widget.course.name, widget.course.streamPosts);
    if (mounted) {
      CheckMateUi.showTopPrompt(context, 'Announcement posted to Stream!',
          isError: false);
    }
  }

  Future<void> _addComment(StreamPost post) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      post.comments.add(
        ClassComment(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          authorName: widget.course.isOwner ? widget.course.instructor : 'Me',
          text: text,
          timestamp: DateTime.now(),
          isMe: true,
        ),
      );
      _commentController.clear();
    });

    await MessagingService.saveStreamPosts(
        widget.course.id, widget.course.name, widget.course.streamPosts);
    if (mounted) {
      Navigator.pop(context); // Close comment sheet
      CheckMateUi.showTopPrompt(context, 'Comment added!', isError: false);
    }
  }

  String _formatPostDate(StreamPost post) {
    final dt = post.timestamp;
    final now = DateTime.now();
    final diff = now.difference(dt);
    String dateStr;
    if (diff.inDays == 0) {
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final minute = dt.minute.toString().padLeft(2, '0');
      dateStr = 'Posted Today at $hour:$minute $period';
    } else if (diff.inDays == 1) {
      dateStr = 'Posted Yesterday';
    } else {
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      dateStr = 'Posted ${months[dt.month - 1]} ${dt.day}';
    }

    if (post.editedTimestamp != null) {
      dateStr += ' (Edited)';
    }

    return dateStr;
  }

  String _formatFullDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${days[dt.weekday % 7]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $period';
  }

  void _showPostOptionsMenu(
      StreamPost post, bool isDark, Color accentColor, Color textColor) {
    final isCanManage = widget.course.isOwner || post.isMe;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Icon(Icons.info_outline, color: accentColor),
                  title: Text('View Post Info',
                      style: TextStyle(
                          color: textColor, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    _showPostInfoSheet(post, isDark, accentColor, textColor);
                  },
                ),
                if (isCanManage) ...[
                  ListTile(
                    leading: Icon(Icons.edit_outlined, color: textColor),
                    title: Text('Edit Announcement',
                        style: TextStyle(color: textColor)),
                    onTap: () {
                      Navigator.pop(context);
                      _showEditAnnouncementDialog(
                          post, isDark, accentColor, textColor);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      post.allowComments
                          ? Icons.comments_disabled_outlined
                          : Icons.comment_outlined,
                      color: textColor,
                    ),
                    title: Text(
                      post.allowComments
                          ? 'Turn Off Class Comments'
                          : 'Turn On Class Comments',
                      style: TextStyle(color: textColor),
                    ),
                    onTap: () async {
                      Navigator.pop(context);
                      setState(() {
                        post.allowComments = !post.allowComments;
                      });
                      await MessagingService.saveStreamPosts(widget.course.id,
                          widget.course.name, widget.course.streamPosts);
                      if (mounted) {
                        CheckMateUi.showTopPrompt(
                          context,
                          post.allowComments
                              ? 'Comments enabled for this post.'
                              : 'Comments disabled for this post.',
                          isError: false,
                        );
                      }
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.delete_outline, color: Colors.red),
                    title: const Text('Delete Announcement',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(context);
                      _showDeleteConfirmation(post, isDark, textColor);
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditAnnouncementDialog(
      StreamPost post, bool isDark, Color accentColor, Color textColor) {
    final editController = TextEditingController(text: post.content);
    String? editAttachment = post.attachmentName;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text('Edit Announcement',
                  style:
                      TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: editController,
                      maxLines: 4,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        hintText: 'Edit post content...',
                        hintStyle:
                            TextStyle(color: textColor.withValues(alpha: 0.5)),
                      ),
                    ),
                    if (editAttachment != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.black26 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.picture_as_pdf,
                                color: Colors.red, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                editAttachment!,
                                style:
                                    TextStyle(fontSize: 12, color: textColor),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon:
                                  Icon(Icons.close, size: 16, color: textColor),
                              onPressed: () {
                                setDialogState(() {
                                  editAttachment = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('CANCEL',
                      style:
                          TextStyle(color: textColor.withValues(alpha: 0.7))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                  ),
                  onPressed: () async {
                    if (editController.text.trim().isEmpty) return;
                    setState(() {
                      post.content = editController.text.trim();
                      post.attachmentName = editAttachment;
                      post.attachmentType =
                          editAttachment != null ? 'pdf' : null;
                      post.editedTimestamp = DateTime.now();
                    });
                    await MessagingService.saveStreamPosts(widget.course.id,
                        widget.course.name, widget.course.streamPosts);
                    if (mounted) {
                      Navigator.pop(context);
                      CheckMateUi.showTopPrompt(
                          context, 'Announcement updated!',
                          isError: false);
                    }
                  },
                  child: const Text('SAVE',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmation(StreamPost post, bool isDark, Color textColor) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Delete Announcement?',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          content: Text(
            'This post will be permanently removed from the class stream.',
            style: TextStyle(color: textColor.withValues(alpha: 0.8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL',
                  style: TextStyle(color: textColor.withValues(alpha: 0.7))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                setState(() {
                  widget.course.streamPosts.removeWhere((p) => p.id == post.id);
                });
                await MessagingService.saveStreamPosts(widget.course.id,
                    widget.course.name, widget.course.streamPosts);
                if (mounted) {
                  Navigator.pop(context);
                  CheckMateUi.showTopPrompt(context, 'Announcement deleted.',
                      isError: false);
                }
              },
              child: const Text('DELETE',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showPostInfoSheet(
      StreamPost post, bool isDark, Color accentColor, Color textColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: accentColor),
                  const SizedBox(width: 12),
                  Text(
                    'Post Information',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                ],
              ),
              const Divider(height: 24),
              _infoRow('Posted By', '${post.authorName} (${post.authorRole})',
                  textColor, accentColor),
              const SizedBox(height: 12),
              _infoRow('Sent Date & Time', _formatFullDateTime(post.timestamp),
                  textColor, accentColor),
              if (post.editedTimestamp != null) ...[
                const SizedBox(height: 12),
                _infoRow(
                    'Edited At',
                    _formatFullDateTime(post.editedTimestamp!),
                    textColor,
                    accentColor),
              ],
              const SizedBox(height: 12),
              _infoRow(
                  'Course Stream', widget.course.name, textColor, accentColor),
              const SizedBox(height: 12),
              _infoRow('Category', post.postType.toUpperCase(), textColor,
                  accentColor),
              const SizedBox(height: 12),
              _infoRow('Comments', post.allowComments ? 'Enabled' : 'Disabled',
                  textColor, post.allowComments ? Colors.green : Colors.red),
              const SizedBox(height: 12),
              _infoRow('Sync Status', 'Published on Google Class Stream',
                  textColor, Colors.green),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(
      String label, String value, Color textColor, Color accentColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, color: textColor.withValues(alpha: 0.6))),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
        ),
      ],
    );
  }

  void _showCommentsSheet(
      StreamPost post, bool isDark, Color accentColor, Color textColor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height -
                    MediaQuery.viewInsetsOf(context).bottom -
                    MediaQuery.paddingOf(context).top -
                    32)
                .clamp(0.0, 450.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                        child: Text('Class Comments (${post.comments.length})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textColor))),
                    IconButton(
                      icon: Icon(Icons.close, color: textColor),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: post.comments.isEmpty
                      ? Center(
                          child: Text(
                              'No class comments yet. Start the conversation!',
                              style: TextStyle(
                                  color: textColor.withValues(alpha: 0.6))),
                        )
                      : ListView.builder(
                          itemCount: post.comments.length,
                          itemBuilder: (context, index) {
                            final c = post.comments[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    accentColor.withValues(alpha: 0.2),
                                foregroundColor: accentColor,
                                child: Text(c.authorName[0].toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                              title: Text(c.authorName,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: textColor)),
                              subtitle: Text(c.text,
                                  style: TextStyle(
                                      color: textColor.withValues(alpha: 0.9))),
                              trailing: Text(
                                _formatFullDateTime(c.timestamp)
                                    .split('at')
                                    .last
                                    .trim(),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: textColor.withValues(alpha: 0.5)),
                              ),
                            );
                          },
                        ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Add class comment...',
                            hintStyle: TextStyle(
                                color: textColor.withValues(alpha: 0.5)),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.send, color: accentColor),
                        onPressed: () => _addComment(post),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _announcementController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.yellow : Colors.blue;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade100;
    final cardBgColor = isDark ? const Color(0xFF1E1E24) : Colors.white;
    final cardBorderColor =
        isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('${widget.course.name} Stream',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => CheckMateUi.showTopPrompt(
                context, '${widget.course.name} • ${widget.course.instructor}',
                isError: false),
            tooltip: 'Course Info',
          ),
          if (!widget.course.isOwner)
            IconButton(
              icon: const Icon(Icons.person),
              tooltip: 'Message Professor',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PrivateChatScreen(
                      course: widget.course,
                      student: Student(
                        id: '${widget.course.id}_private_chat',
                        name: widget.course.instructor,
                        avatar: widget.course.instructor[0],
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadStreamPosts();
        },
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width > 880
                ? (MediaQuery.sizeOf(context).width - 840) / 2
                : 16,
            vertical: 16,
          ),
          children: [
            // 1. Course Banner Card (Google Classroom Banner Style)
            _buildCourseHeaderCard(isDark, cardBgColor, textColor),
            const SizedBox(height: 16),

            // 2. New Announcement Trigger Card / Composer (INSTRUCTORS ONLY)
            if (widget.course.isOwner) ...[
              _buildNewAnnouncementCard(
                  isDark, cardBgColor, cardBorderColor, textColor, accentColor),
              const SizedBox(height: 16),
            ],

            // 3. Stream Feed Cards List
            ...widget.course.streamPosts.map((post) => _buildStreamCard(post,
                isDark, cardBgColor, cardBorderColor, textColor, accentColor)),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseHeaderCard(
      bool isDark, Color cardBgColor, Color textColor) {
    final gradient = widget.course.adaptiveGradient(context);
    final bannerContentColor = isDark ? const Color(0xFF141318) : Colors.white;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.course.name,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: bannerContentColor,
              shadows: isDark
                  ? null
                  : const [Shadow(color: Colors.black45, blurRadius: 4)],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.course.instructor,
            style: TextStyle(
              fontSize: 15,
              color: bannerContentColor.withValues(alpha: isDark ? 0.85 : 0.90),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewAnnouncementCard(bool isDark, Color cardBgColor,
      Color cardBorderColor, Color textColor, Color accentColor) {
    if (_isComposingAnnouncement) {
      return Card(
        color: cardBgColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: accentColor, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accentColor.withValues(alpha: 0.2),
                    foregroundColor: accentColor,
                    child: Text(
                      widget.course.instructor[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Announce something to your class',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: textColor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _announcementController,
                maxLines: 4,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  hintText: 'Share an update, schedule, or message...',
                  hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: isDark ? Colors.black12 : Colors.grey.shade50,
                ),
              ),
              if (_selectedAttachment != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.picture_as_pdf,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Flexible(
                          child: Text(_selectedAttachment!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(fontSize: 12, color: textColor))),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _selectedAttachment = null),
                        child: Icon(Icons.cancel,
                            size: 16, color: textColor.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(Icons.attach_file, color: accentColor),
                    tooltip: 'Attach File',
                    onPressed: () {
                      setState(() {
                        _selectedAttachment =
                            'Schedule_${widget.course.code}_Prelim_Exam.pdf';
                      });
                    },
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            setState(() => _isComposingAnnouncement = false),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: textColor.withValues(alpha: 0.7))),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _postAnnouncement,
                        child: const Text('Post',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      color: cardBgColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cardBorderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => setState(() => _isComposingAnnouncement = true),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.edit_outlined, color: accentColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                'Announce something to your class',
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreamCard(StreamPost post, bool isDark, Color cardBgColor,
      Color cardBorderColor, Color textColor, Color accentColor) {
    if (post.postType == 'material' || post.postType == 'assignment') {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: cardBgColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: cardBorderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: () => _showPostInfoSheet(post, isDark, accentColor, textColor),
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor:
                          isDark ? Colors.black38 : Colors.grey.shade200,
                      foregroundColor: textColor,
                      child: Icon(
                          post.postType == 'material'
                              ? Icons.menu_book
                              : Icons.assignment,
                          color: accentColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.title ?? 'New Course Activity',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: textColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatPostDate(post),
                            style: TextStyle(
                                fontSize: 12,
                                color: textColor.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.more_vert,
                          color: textColor.withValues(alpha: 0.6)),
                      onPressed: () => _showPostOptionsMenu(
                          post, isDark, accentColor, textColor),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: cardBorderColor),
              InkWell(
                onTap: () {
                  if (post.allowComments) {
                    _showCommentsSheet(post, isDark, accentColor, textColor);
                  } else {
                    CheckMateUi.showTopPrompt(
                      context,
                      widget.course.isOwner
                          ? 'Comments are turned off. Enable them from post options.'
                          : 'Class comments are disabled for this announcement.',
                      isError: false,
                    );
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        post.allowComments
                            ? Icons.add_comment_outlined
                            : Icons.comments_disabled_outlined,
                        size: 16,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        !post.allowComments
                            ? 'Class comments turned off'
                            : (post.comments.isEmpty
                                ? 'Add class comment'
                                : '${post.comments.length} class comment(s)'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: textColor.withValues(
                              alpha: post.allowComments ? 0.7 : 0.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Default Announcement Card
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: cardBgColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: cardBorderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showPostInfoSheet(post, isDark, accentColor, textColor),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: accentColor.withValues(alpha: 0.2),
                    foregroundColor: accentColor,
                    child: Text(
                      post.authorName[0].toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.authorName,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: textColor),
                        ),
                        Text(
                          _formatPostDate(post),
                          style: TextStyle(
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert,
                        color: textColor.withValues(alpha: 0.6)),
                    onPressed: () => _showPostOptionsMenu(
                        post, isDark, accentColor, textColor),
                  ),
                ],
              ),
            ),

            // Content Body
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                post.content,
                style: TextStyle(fontSize: 14, height: 1.4, color: textColor),
              ),
            ),

            // Attachment Pill
            if (post.attachmentName != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black38 : Colors.grey.shade100,
                    border: Border.all(color: cardBorderColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.picture_as_pdf,
                            color: Colors.red, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          post.attachmentName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            Divider(height: 1, color: cardBorderColor),

            // Class Comment Footer
            InkWell(
              onTap: () {
                if (post.allowComments) {
                  _showCommentsSheet(post, isDark, accentColor, textColor);
                } else {
                  CheckMateUi.showTopPrompt(
                    context,
                    widget.course.isOwner
                        ? 'Comments are turned off. Enable them from post options.'
                        : 'Class comments are disabled for this announcement.',
                    isError: false,
                  );
                }
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      post.allowComments
                          ? Icons.add_comment_outlined
                          : Icons.comments_disabled_outlined,
                      size: 16,
                      color: textColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      !post.allowComments
                          ? 'Class comments turned off'
                          : (post.comments.isEmpty
                              ? 'Add class comment'
                              : '${post.comments.length} class comment(s)'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textColor.withValues(
                            alpha: post.allowComments ? 0.7 : 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
