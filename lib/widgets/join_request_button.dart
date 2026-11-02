/// ปุ่มส่งคำขอเข้าร่วมทีม ซึ่งแสดงสถานะคำขอและป้องกันการส่งซ้ำระหว่างหน้าจอ.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// สร้างปุ่มตามสถานะคำขอของผู้ใช้ และเก็บสถานะ pending ชั่วคราวระหว่างรอ Firestore.
class JoinRequestButton extends StatelessWidget {
  static final ValueNotifier<Map<String, String>> localStatuses =
      ValueNotifier<Map<String, String>>(<String, String>{});

  static String _statusKey(String userUid, String postId) => '$userUid:$postId';

  static void markPending(String userUid, String postId) {
    localStatuses.value = {
      ...localStatuses.value,
      _statusKey(userUid, postId): 'pending',
    };
  }

  const JoinRequestButton({
    super.key,
    required this.postId,
    required this.ownerUid,
    required this.currentUserUid,
    required this.isOwnPost,
    required this.hasJoined,
    required this.requestSentOnPost,
    required this.requestSentLocally,
    required this.isFull,
    required this.isClosed,
    required this.onPressed,
    this.compact = false,
  });

  final String postId;
  final String ownerUid;
  final String? currentUserUid;
  final bool isOwnPost;
  final bool hasJoined;
  final bool requestSentOnPost;
  final bool requestSentLocally;
  final bool isFull;
  final bool isClosed;
  final VoidCallback onPressed;
  final bool compact;

  /// เลือก label, สี และการกดได้ตาม pending/accepted ของคำขอ.
  Widget _button({required bool pending, required bool accepted}) {
    final disabled = isOwnPost || pending || accepted || isFull || isClosed;
    final label = isOwnPost
        ? 'โพสต์ของคุณ'
        : accepted
            ? 'เข้าร่วมเรียบร้อย'
            : pending
                ? 'ขอเข้าแล้ว'
                : isFull
                    ? 'เต็มแล้ว'
                    : isClosed
                        ? 'ปิดรับแล้ว'
                        : 'ขอเข้าร่วม';
    final icon = accepted
        ? Icons.check_circle_rounded
        : pending
            ? Icons.hourglass_top_rounded
            : Icons.person_add_alt_1_rounded;

    return FilledButton.icon(
      onPressed: disabled ? null : onPressed,
      icon: Icon(icon, size: compact ? 15 : 17),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: compact ? const Color(0xFFC9FF70) : const Color(0xFF9B7CFF),
        foregroundColor: compact ? const Color(0xFF171225) : Colors.white,
        disabledBackgroundColor: const Color(0xFF302B3C),
        disabledForegroundColor: const Color(0xFFAAA7B7),
        minimumSize: compact ? const Size(0, 36) : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 14 : 15,
          vertical: compact ? 9 : 10,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 10 : 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserUid == null || ownerUid.isEmpty || isOwnPost) {
      return _button(pending: requestSentLocally || requestSentOnPost, accepted: hasJoined);
    }

    final requests = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('joinRequests')
        .where('senderUid', isEqualTo: currentUserUid)
        .snapshots();

    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: localStatuses,
      builder: (context, statuses, _) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: requests,
        builder: (context, snapshot) {
          final matching = snapshot.data?.docs
                  .where((request) =>
                      request.data()['postId'] == postId &&
                      request.data()['ownerUid'] == ownerUid)
                  .toList() ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final hasAcceptedRequest =
              matching.any((request) => request.data()['status'] == 'accepted');
          final hasPendingRequest =
              matching.any((request) => request.data()['status'] == 'pending');
          final allDeclined = matching.isNotEmpty &&
              !hasAcceptedRequest &&
              !hasPendingRequest &&
              matching.every((request) => request.data()['status'] == 'declined');
          final localStatus = statuses[_statusKey(currentUserUid!, postId)];
          final accepted = hasJoined ||
              hasAcceptedRequest ||
              localStatus == 'accepted';
          final pending = !accepted &&
              (hasPendingRequest ||
                  (!allDeclined &&
                      (requestSentOnPost ||
                          requestSentLocally ||
                          localStatus == 'pending')));
          return _button(pending: pending, accepted: accepted);
        },
      ),
    );
  }
}
