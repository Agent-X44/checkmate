import 'package:flutter/material.dart';
import '../models/course.dart';

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

  @override
  void initState() {
    super.initState();
    // Initialize or get existing chat
    _chat = widget.course.privateChats.putIfAbsent(
      widget.student.id,
      () => PrivateChat(studentId: widget.student.id),
    );
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      _chat.messages.add(
        ChatMessage(
          sender: 'Me',
          text: _controller.text,
          timestamp: DateTime.now(),
          isMe: true,
        ),
      );
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Check global course setting for student reply permissions
    bool canSend = widget.course.isOwner || widget.course.globalCanStudentReply;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.student.name, style: const TextStyle(fontSize: 16)),
            Text(widget.course.code,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Inform the student if replies are disabled by the instructor
          if (!widget.course.globalCanStudentReply && !widget.course.isOwner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: Colors.orange.shade50,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_clock, size: 16, color: Colors.orange),
                  SizedBox(width: 8),
                  Text(
                    'The instructor has disabled replies for this course.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
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
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (canSend) _buildInputArea() else const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: message.isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20).copyWith(
            bottomRight: message.isMe
                ? const Radius.circular(0)
                : const Radius.circular(20),
            bottomLeft: message.isMe
                ? const Radius.circular(20)
                : const Radius.circular(0),
          ),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isMe ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 20 / 255),
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
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ),
    );
  }
}
