import 'package:flutter/material.dart';

/// Builds the user-facing title, icon, and body for an inbox notification.
/// Kept independent from Firebase so notification behavior can be unit tested.
class NotificationPresentation {
  const NotificationPresentation({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  factory NotificationPresentation.fromData(Map<String, dynamic> data) {
    final type = data['type'];
    final senderValue = data['senderName'];
    final sender = senderValue is String && senderValue.isNotEmpty
        ? senderValue
        : 'ผู้เล่น';
    final bodyValue = data['body'];
    final body = bodyValue is String && bodyValue.isNotEmpty
        ? bodyValue
        : 'แตะเพื่อเปิดบทสนทนา';

    if (type == 'post_like') {
      final reaction = (data['reaction'] ?? 'like').toString();
      return NotificationPresentation(
        icon: Icons.favorite_rounded,
        title: reaction.isEmpty || reaction == 'like'
            ? '$sender ถูกใจโพสต์ของคุณ'
            : '$sender แสดงความรู้สึก $reaction บนโพสต์ของคุณ',
        subtitle: body,
      );
    }
    if (type == 'new_follower') {
      return NotificationPresentation(
        icon: Icons.person_add_alt_1_rounded,
        title: 'มีผู้ติดตามใหม่: $sender',
        subtitle: body,
      );
    }
    if (type == 'post_comment') {
      return NotificationPresentation(
        icon: Icons.mode_comment_outlined,
        title: '$sender แสดงความคิดเห็นในโพสต์ของคุณ',
        subtitle: body,
      );
    }
    if (type == 'post_removed') {
      return NotificationPresentation(
        icon: Icons.gpp_bad_rounded,
        title: 'โพสต์ของคุณถูกลบ',
        subtitle: body,
      );
    }
    if (type == 'admin_report') {
      return NotificationPresentation(
        icon: Icons.flag_rounded,
        title: 'มีรายงานโพสต์ใหม่',
        subtitle: body,
      );
    }
    if (type == 'post_report') {
      return NotificationPresentation(
        icon: Icons.flag_rounded,
        title: 'โพสต์ของคุณมีการถูกรายงาน',
        subtitle: body,
      );
    }
    if (type == 'group_chat_message') {
      final groupName = (data['groupName'] ?? 'กลุ่มแชต').toString();
      return NotificationPresentation(
        icon: Icons.groups_rounded,
        title: '$sender ส่งข้อความในกลุ่ม $groupName',
        subtitle: body,
      );
    }
    if (type == 'join_request_received') {
      return NotificationPresentation(
        icon: Icons.group_rounded,
        title: 'มีคำขอเข้าร่วมทีมจาก $sender',
        subtitle: body,
      );
    }
    if (type == 'join_request_accepted') {
      return NotificationPresentation(
        icon: Icons.group_rounded,
        title: 'คำขอเข้าร่วมได้รับการตอบรับ',
        subtitle: body,
      );
    }

    return NotificationPresentation(
      icon: Icons.chat_bubble_rounded,
      title: senderValue is String && senderValue.isNotEmpty
          ? 'ข้อความใหม่จาก $senderValue'
          : 'ข้อความใหม่ในแชต',
      subtitle: body,
    );
  }
}
