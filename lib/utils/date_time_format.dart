// ฟังก์ชันช่วยแปลงเวลา Firestore/DateTime เป็นป้ายเวลาข้อความและหัวข้อแบ่งวันในแชต.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Formats a Firestore timestamp as a local date and time for display.
/// Returns null for older documents that do not have a valid timestamp.
String? formatDateTimeLabel(dynamic value) {
  final dateTime = _dateTimeFrom(value);
  if (dateTime == null) return null;

  final local = dateTime.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} · $hour:$minute';
}

/// Formats a message timestamp as the compact clock label used beside a bubble.
String? formatChatTimeLabel(dynamic value) {
  final dateTime = _dateTimeFrom(value);
  if (dateTime == null) return null;

  final local = dateTime.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}


/// Returns a friendly date heading for a chat day group.
String? formatChatDateDividerLabel(dynamic value) {
  final date = _dateTimeFrom(value)?.toLocal();
  if (date == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final messageDay = DateTime(date.year, date.month, date.day);
  final difference = today.difference(messageDay).inDays;
  if (difference == 0) return 'วันนี้';
  if (difference == 1) return 'เมื่อวาน';
  const months = <String>[
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
}

/// ใช้ตัดสินว่าข้อความสองรายการอยู่วันเดียวกันหรือไม่ สำหรับแสดงหัวข้อแบ่งวัน.
bool isSameChatDay(dynamic first, dynamic second) {
  final a = _dateTimeFrom(first)?.toLocal();
  final b = _dateTimeFrom(second)?.toLocal();
  if (a == null || b == null) return true;
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// แปลงชนิดเวลาที่รองรับเป็น DateTime; ค่าอื่นคืน null เพื่อให้ UI ใช้ fallback.
DateTime? _dateTimeFrom(dynamic value) {
  return switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    _ => null,
  };
}

/// widget เล็กสำหรับแสดงเวลาไว้ข้าง bubble โดยใช้รูปแบบเดียวกันทุกห้อง.
class ChatTimeLabel extends StatelessWidget {
  const ChatTimeLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.white60),
      ),
    );
  }
}
