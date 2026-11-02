/// ทดสอบการแปลงชนิดและข้อมูลแจ้งเตือนเป็นข้อความ/ไอคอนที่ผู้ใช้เห็น.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_party_week2_week4/utils/notification_presentation.dart';

void main() {
  group('NotificationPresentation.fromData', () {
    test('shows a like notification title', () {
      final result = NotificationPresentation.fromData({
        'type': 'post_like',
        'senderName': 'Mew',
        'reaction': 'like',
      });
      expect(result.title, 'Mew ถูกใจโพสต์ของคุณ');
      expect(result.icon, Icons.favorite_rounded);
    });

    test('shows a non-like reaction in the title', () {
      final result = NotificationPresentation.fromData({
        'type': 'post_like',
        'senderName': 'Mew',
        'reaction': '🔥',
      });
      expect(result.title, 'Mew แสดงความรู้สึก 🔥 บนโพสต์ของคุณ');
    });

    test('uses player when the reaction sender is missing', () {
      final result = NotificationPresentation.fromData({'type': 'post_like'});
      expect(result.title, 'ผู้เล่น ถูกใจโพสต์ของคุณ');
    });

    test('shows a new follower notification', () {
      final result = NotificationPresentation.fromData({
        'type': 'new_follower',
        'senderName': 'Mew',
      });
      expect(result.title, 'มีผู้ติดตามใหม่: Mew');
      expect(result.icon, Icons.person_add_alt_1_rounded);
    });

    test('falls back to player for an unnamed follower', () {
      final result = NotificationPresentation.fromData({
        'type': 'new_follower',
        'senderName': '',
      });
      expect(result.title, 'มีผู้ติดตามใหม่: ผู้เล่น');
    });

    test('shows a post comment notification', () {
      final result = NotificationPresentation.fromData({
        'type': 'post_comment',
        'senderName': 'Mew',
        'body': 'สวัสดี',
      });
      expect(result.title, 'Mew แสดงความคิดเห็นในโพสต์ของคุณ');
      expect(result.subtitle, 'สวัสดี');
    });

    test('shows the group name for a group message', () {
      final result = NotificationPresentation.fromData({
        'type': 'group_chat_message',
        'senderName': 'Mew',
        'groupName': 'ทีมเกม',
      });
      expect(result.title, 'Mew ส่งข้อความในกลุ่ม ทีมเกม');
      expect(result.icon, Icons.groups_rounded);
    });

    test('uses the default group name when missing', () {
      final result = NotificationPresentation.fromData({
        'type': 'group_chat_message',
        'senderName': 'Mew',
      });
      expect(result.title, 'Mew ส่งข้อความในกลุ่ม กลุ่มแชต');
    });

    test('shows a received join request', () {
      final result = NotificationPresentation.fromData({
        'type': 'join_request_received',
        'senderName': 'Mew',
      });
      expect(result.title, 'มีคำขอเข้าร่วมทีมจาก Mew');
    });

    test('shows an accepted join request', () {
      final result = NotificationPresentation.fromData({
        'type': 'join_request_accepted',
      });
      expect(result.title, 'คำขอเข้าร่วมได้รับการตอบรับ');
    });

    test('shows private chat sender when available', () {
      final result = NotificationPresentation.fromData({
        'type': 'private_message',
        'senderName': 'Mew',
      });
      expect(result.title, 'ข้อความใหม่จาก Mew');
    });

    test('falls back when private chat sender is blank', () {
      final result = NotificationPresentation.fromData({
        'type': 'private_message',
        'senderName': '',
      });
      expect(result.title, 'ข้อความใหม่ในแชต');
    });

    test('uses a default subtitle for missing or empty body', () {
      expect(
        NotificationPresentation.fromData({'type': 'new_follower'}).subtitle,
        'แตะเพื่อเปิดบทสนทนา',
      );
      expect(
        NotificationPresentation.fromData({
          'type': 'new_follower',
          'body': '',
        }).subtitle,
        'แตะเพื่อเปิดบทสนทนา',
      );
    });
  });
}
