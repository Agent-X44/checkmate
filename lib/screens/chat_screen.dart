import 'package:flutter/material.dart';
import '../models/course.dart';
import 'private_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  final Course course;
  const ChatScreen({super.key, required this.course});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;
    setState(() {
      widget.course.groupMessages.add(
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
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.course.code} Discussion'),
        actions: [
          // If the user is a student (NOT the owner), show the "Message Professor" button
          if (!widget.course.isOwner)
            TextButton.icon(
              onPressed: () {
                // Navigate to a private chat with the professor
                // Using a dummy 'instructor' student object for simulation
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PrivateChatScreen(
                      course: widget.course,
                      student: Student(
                          id: 'instructor_id',
                          name: widget.course.instructor,
                          avatar: widget.course.instructor[0]),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.person, color: Colors.white, size: 18),
              label: const Text('PROFESSOR',
                  style: TextStyle(color: Colors.white, fontSize: 12)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              reverse: true,
              itemCount: widget.course.groupMessages.length,
              itemBuilder: (context, index) {
                final message = widget.course.groupMessages[
                    widget.course.groupMessages.length - 1 - index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          _buildInputArea(),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.isMe)
              Text(
                message.sender,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            Text(
              message.text,
              style: TextStyle(
                color: message.isMe ? Colors.white : Colors.black87,
              ),
            ),
          ],
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
            color: Colors.black.withAlpha(20),
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
