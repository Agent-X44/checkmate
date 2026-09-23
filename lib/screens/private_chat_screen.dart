import 'dart:async';
import 'package:flutter/material.dart';
import '../models/course.dart';
import '../services/messaging_service.dart';
import '../utils/ui_utils.dart';

class PrivateChatScreen extends StatefulWidget {
  final Course course;
  final Student student;

  const PrivateChatScreen({
    super.key,
    required this.course,
    required this.student,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _controller = TextEditingController();
  late PrivateChat _chat;
  late String _chatKey;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Use course-bound canonical chat key so student and instructor always sync
    _chatKey = '${widget.course.id}_private_chat';
    _chat = widget.course.privateChats.putIfAbsent(
      _chatKey,
      () => PrivateChat(studentId: _chatKey),
    );
    _loadPrivateChat(_chatKey);

    // Real-time polling every 1 second to instantly sync messages between instructor and student views
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      final saved = await MessagingService.loadPrivateChat(widget.course.id, widget.course.name, _chatKey);
      if (mounted && saved.length != _chat.messages.length) {
        setState(() {
          _chat.messages.clear();
          _chat.messages.addAll(saved);
        });
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadPrivateChat(String chatKey) async {
    final saved = await MessagingService.loadPrivateChat(widget.course.id, widget.course.name, chatKey);
    if (saved.isNotEmpty && mounted) {
      setState(() {
        _chat.messages.clear();
        _chat.messages.addAll(saved);
      });
    }
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    final senderId = widget.course.isOwner ? 'instructor' : 'student';
    final senderName = widget.course.isOwner ? widget.course.instructor : 'Student';

    setState(() {
      _chat.messages.add(
        ChatMessage(
          senderId: senderId,
          senderName: senderName,
          text: _controller.text,
          timestamp: DateTime.now(),
        ),
      );
      _controller.clear();
    });
    await MessagingService.savePrivateChat(widget.course.id, widget.course.name, _chatKey, _chat.messages);
  }

  String _formatFullDateTime(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${days[dt.weekday % 7]}, ${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:$minute $period';
  }

  void _showMessageOptions(ChatMessage message, bool isDark, Color accentColor, Color textColor) {
    final isMe = message.getIsMe(widget.course.isOwner);

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
                  title: Text('Message Details', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    _showMessageInfoSheet(message, isDark, accentColor, textColor);
                  },
                ),
                if (isMe) ...[
                  ListTile(
                    leading: Icon(Icons.edit_outlined, color: textColor),
                    title: Text('Edit Message', style: TextStyle(color: textColor)),
                    onTap: () {
                      Navigator.pop(context);
                      _showEditMessageDialog(message, isDark, accentColor, textColor);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.undo, color: Colors.red),
                    title: const Text('Unsend Message', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    onTap: () async {
                      Navigator.pop(context);
                      setState(() {
                        _chat.messages.removeWhere((m) => m.id == message.id);
                      });
                      await MessagingService.savePrivateChat(widget.course.id, widget.course.name, _chatKey, _chat.messages);
                      if (mounted) {
                        CheckMateUi.showTopPrompt(context, 'Message unsent.', isError: false);
                      }
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

  void _showEditMessageDialog(ChatMessage message, bool isDark, Color accentColor, Color textColor) {
    final editController = TextEditingController(text: message.text);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Edit Message', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: editController,
            maxLines: 3,
            style: TextStyle(color: textColor),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              hintText: 'Edit message...',
              hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: textColor.withValues(alpha: 0.7))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: isDark ? Colors.black : Colors.white,
              ),
              onPressed: () async {
                if (editController.text.trim().isEmpty) return;
                setState(() {
                  message.text = editController.text.trim();
                  message.isEdited = true;
                  message.editedTimestamp = DateTime.now();
                });
                await MessagingService.savePrivateChat(widget.course.id, widget.course.name, _chatKey, _chat.messages);
                if (mounted) {
                  Navigator.pop(context);
                  CheckMateUi.showTopPrompt(context, 'Message updated!', isError: false);
                }
              },
              child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _showMessageInfoSheet(ChatMessage message, bool isDark, Color accentColor, Color textColor) {
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
                    'Direct Message Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                  ),
                ],
              ),
              const Divider(height: 24),
              _infoRow('Sent By', message.senderName, textColor, accentColor),
              const SizedBox(height: 12),
              _infoRow('Date & Time', _formatFullDateTime(message.timestamp), textColor, accentColor),
              if (message.editedTimestamp != null) ...[
                const SizedBox(height: 12),
                _infoRow('Edited At', _formatFullDateTime(message.editedTimestamp!), textColor, accentColor),
              ],
              const SizedBox(height: 12),
              _infoRow('Course', widget.course.name, textColor, accentColor),
              const SizedBox(height: 12),
              _infoRow('Status', 'Delivered & Encrypted', textColor, Colors.green),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CLOSE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value, Color textColor, Color accentColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: TextStyle(fontSize: 13, color: textColor.withValues(alpha: 0.6))),
        ),
        Expanded(
          child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? Colors.yellow : Colors.blue;
    final textColor = isDark ? Colors.white : Colors.black;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade100;
    bool canSend = widget.course.isOwner || widget.course.globalCanStudentReply;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.student.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
            Text(widget.course.name,
                style: TextStyle(fontSize: 12, color: textColor.withValues(alpha: 0.7))),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!widget.course.globalCanStudentReply && !widget.course.isOwner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: isDark ? Colors.amber.shade900.withValues(alpha: 0.3) : Colors.orange.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_clock, size: 16, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    'The instructor has disabled replies for this course.',
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.amber.shade200 : Colors.orange.shade900,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              reverse: true,
              itemCount: _chat.messages.length,
              itemBuilder: (context, index) {
                final message =
                    _chat.messages[_chat.messages.length - 1 - index];
                return _buildMessageBubble(message, isDark, accentColor, textColor);
              },
            ),
          ),
          if (canSend) _buildInputArea(isDark, accentColor, textColor) else const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isDark, Color accentColor, Color textColor) {
    final isMe = message.getIsMe(widget.course.isOwner);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _showMessageOptions(message, isDark, accentColor, textColor),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isMe
                ? accentColor
                : (isDark ? const Color(0xFF1E1E24) : Colors.white),
            border: isMe
                ? null
                : Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(20).copyWith(
              bottomRight: isMe
                  ? const Radius.circular(0)
                  : const Radius.circular(20),
              bottomLeft: isMe
                  ? const Radius.circular(20)
                  : const Radius.circular(0),
            ),
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    message.senderName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              Text(
                message.text,
                style: TextStyle(
                  color: isMe
                      ? (isDark ? Colors.black : Colors.white)
                      : textColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.isEdited)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: Text(
                        'edited',
                        style: TextStyle(
                          fontSize: 9,
                          fontStyle: FontStyle.italic,
                          color: isMe
                              ? (isDark ? Colors.black54 : Colors.white70)
                              : textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  Text(
                    'Tap for options',
                    style: TextStyle(
                      fontSize: 9,
                      color: isMe
                          ? (isDark ? Colors.black54 : Colors.white70)
                          : textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isDark, Color accentColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E24) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.send, color: accentColor),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}
