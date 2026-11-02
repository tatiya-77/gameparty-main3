import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'chat_list_screen.dart';
import 'group_chat_screen.dart';
import 'private_chat_screen.dart';
import 'profile_screen.dart';
import '../utils/notification_presentation.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  CollectionReference<Map<String, dynamic>>? _inbox() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications');
  }

  Future<void> _markAllRead(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in docs) {
      if (doc.data()['isRead'] == false) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
    }
    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('ทำเครื่องหมายว่าอ่านแล้วไม่สำเร็จ (${error.code})')),
      );
    }
  }

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final senderUid = data['senderUid'];
    final senderName = data['senderName'];
    try {
      if (data['isRead'] != true) {
        await doc.reference.update({
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('อัปเดตการแจ้งเตือนไม่สำเร็จ (${error.code})')),
        );
      }
    }

    if (data['type'] == 'join_request_received') {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatListScreen(
            onBack: () => Navigator.of(context).pop(),
            openInvitations: true,
          ),
        ),
      );
      return;
    }

    if (data['type'] == 'join_request_accepted') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (data['body'] ?? 'คำขอเข้าร่วมได้รับการตอบรับแล้ว').toString(),
            ),
          ),
        );
      }
      return;
    }

    if (data['type'] == 'post_like') {
      final reaction = (data['reaction'] ?? 'like').toString();
      if (context.mounted) {
        final postTitle = (data['postTitle'] ?? 'โพสต์ของคุณ').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reaction == 'like'
                ? 'มีคนถูกใจโพสต์: $postTitle'
                : 'มีคนแสดงความรู้สึก $reaction บนโพสต์: $postTitle'),
          ),
        );
      }
      return;
    }

    if (data['type'] == 'post_comment') {
      if (context.mounted) {
        final sender = (senderName ?? 'ผู้เล่น').toString();
        final body = (data['body'] ?? '').toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$sender แสดงความคิดเห็น: $body')),
        );
      }
      return;
    }

    if (data['type'] == 'post_report') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (data['body'] ?? 'โพสต์ของคุณมีการถูกรายงาน').toString(),
            ),
          ),
        );
      }
      return;
    }

    if (data['type'] == 'group_chat_message') {
      final groupId = data['groupId'];
      if (!context.mounted || groupId is! String || groupId.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GroupChatScreen(
            groupId: groupId,
            groupName: (data['groupName'] ?? 'กลุ่มแชต').toString(),
          ),
        ),
      );
      return;
    }

    if (data['type'] == 'new_follower') {
      if (!context.mounted || senderUid is! String || senderUid.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (profileContext) => ProfileScreen(
            userId: senderUid,
            onBack: () => Navigator.of(profileContext).pop(),
          ),
        ),
      );
      return;
    }

    if (!context.mounted || senderUid is! String || senderUid.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PrivateChatScreen(
          peerUid: senderUid,
          peerName: senderName is String && senderName.isNotEmpty
              ? senderName
              : 'ผู้เล่น',
        ),
      ),
    );
  }

  String _timeLabel(dynamic value) {
    if (value is! Timestamp) return 'เมื่อสักครู่';
    final time = value.toDate().toLocal();
    final now = DateTime.now();
    if (now.difference(time).inDays == 0 && now.day == time.day) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day}/${time.month}/${time.year}  ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final inbox = _inbox();
    return Scaffold(
      appBar: AppBar(
        title: const Text('การแจ้งเตือน'),
        actions: [
          if (inbox != null)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: inbox
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final hasUnread =
                    docs.any((doc) => doc.data()['isRead'] == false);
                if (!hasUnread) return const SizedBox.shrink();
                return TextButton(
                  onPressed: () => _markAllRead(context, docs),
                  child: const Text('อ่านทั้งหมด'),
                );
              },
            ),
        ],
      ),
      body: inbox == null
          ? const _EmptyNotifications(
              icon: Icons.lock_outline_rounded,
              title: 'กรุณาเข้าสู่ระบบ',
              subtitle: 'เข้าสู่ระบบเพื่อดูการแจ้งเตือนของคุณ',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: inbox
                  .orderBy('createdAt', descending: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _EmptyNotifications(
                    icon: Icons.error_outline_rounded,
                    title: 'โหลดการแจ้งเตือนไม่สำเร็จ',
                    subtitle: snapshot.error is FirebaseException
                        ? 'ตรวจสอบ Firestore Rules สำหรับ users/{uid}/notifications'
                        : 'กรุณาลองใหม่อีกครั้ง',
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const _EmptyNotifications(
                    icon: Icons.notifications_none_rounded,
                    title: 'ยังไม่มีการแจ้งเตือน',
                    subtitle: 'เมื่อมีข้อความใหม่ การแจ้งเตือนจะแสดงที่นี่',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final isRead = data['isRead'] == true;
                    final presentation =
                        NotificationPresentation.fromData(data);
                    return Material(
                      color: isRead
                          ? const Color(0xFF171621)
                          : const Color(0xFF252039),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _openNotification(context, doc),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF44375F),
                                child: Icon(
                                  presentation.icon,
                                  color: isRead
                                      ? Colors.white60
                                      : const Color(0xFFCFB8FF),
                                  size: 19,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      presentation.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      presentation.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                    const SizedBox(height: 7),
                                    Text(
                                      _timeLabel(data['createdAt']),
                                      style: const TextStyle(
                                          color: Colors.white38, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isRead)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8, top: 7),
                                  child: CircleAvatar(
                                      radius: 4,
                                      backgroundColor: Color(0xFFB388FF)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 58, color: const Color(0xFFB388FF)),
            const SizedBox(height: 14),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 7),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60)),
          ],
        ),
      ),
    );
  }
}
