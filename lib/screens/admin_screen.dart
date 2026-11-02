// หน้าผู้ดูแลระบบ: ตรวจสิทธิ์จากเอกสาร admins จัดการรายงานโพสต์ และดูรายชื่อสมาชิก.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// ก่อนให้เห็นข้อมูลแอดมิน ตรวจเอกสาร admins/{uid}; Firestore Rules ยังเป็นด่านสิทธิ์หลัก.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('กรุณาเข้าสู่ระบบ')));
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('admins').doc(uid).snapshots(),
      builder: (context, access) {
        if (access.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (access.data?.exists != true) {
          return const Scaffold(body: Center(child: Text('ไม่มีสิทธิ์เข้าถึงหน้านี้')));
        }
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('จัดการระบบ'),
              bottom: const TabBar(tabs: [
                Tab(icon: Icon(Icons.flag_outlined), text: 'รายงานโพสต์'),
                Tab(icon: Icon(Icons.people_outline), text: 'สมาชิก'),
              ]),
            ),
            body: const TabBarView(children: [_ReportsTab(), _UsersTab()]),
          ),
        );
      },
    );
  }
}

/// ฟัง reports เรียงใหม่ก่อน แล้วให้แอดมินเปิดโพสต์หรือตัดสินผลรายงาน.
class _ReportsTab extends StatelessWidget {
  const _ReportsTab();

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('reports')
            .orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('โหลดรายงานไม่สำเร็จ'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final reports = snapshot.data!.docs;
          if (reports.isEmpty) return const Center(child: Text('ยังไม่มีรายงานโพสต์'));
          return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: reports.length,
                  itemBuilder: (context, index) {
              final report = reports[index];
              final data = report.data();
              final pending = data['status'] == 'pending';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.flag_rounded, color: Color(0xFFCFB8FF)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '${data['reporterName'] ?? 'ผู้ใช้'} รายงานโพสต์ของ ${data['postOwnerName'] ?? 'ผู้ใช้'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )),
                      Text(pending ? 'รอตรวจสอบ' : (data['status'] == 'deleted' ? 'ลบโพสต์แล้ว' : 'ตรวจสอบแล้ว'),
                          style: TextStyle(color: pending ? Colors.amber : Colors.white54)),
                    ]),
                    const SizedBox(height: 8),
                    Text('เหตุผล: ${data['reason'] ?? 'ไม่ได้ระบุ'}'),
                    if ((data['postText'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('โพสต์: ${data['postText']}', maxLines: 4, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _showReportedPost(context, data),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('ดูรายละเอียดโพสต์'),
                      ),
                    ),
                    if (pending) ...[
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(
                          onPressed: () => _resolve(context, report, deletePost: false),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('ไม่พบความผิด'),
                        ),
                        FilledButton.icon(
                          onPressed: () => _resolve(context, report, deletePost: true),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('ลบโพสต์และแจ้งเจ้าของ'),
                        ),
                      ]),
                    ],
                  ]),
                ),
                  );
                  },
                );
        },
      );

  /// ดึงโพสต์ต้นฉบับจาก posts/{postId}; ถ้าถูกลบหรืออ่านไม่ได้ ใช้ snapshot ที่แนบมากับรายงานแทน.
  Future<void> _showReportedPost(
    BuildContext context,
    Map<String, dynamic> reportData,
  ) async {
    final postId = reportData['postId'];
    Map<String, dynamic>? postData;
    if (postId is String && postId.isNotEmpty) {
      try {
        final post = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
        if (post.exists) postData = post.data();
      } on FirebaseException {
        // Continue with the post snapshot saved in the report.
      }
    }
    if (!context.mounted) return;
    final details = postData ?? reportData;
    final title = (details['title'] ?? details['postTitle'] ?? '').toString();
    final body = (details['detail'] ?? details['text'] ?? details['description'] ?? details['postText'] ?? '').toString();
    final owner = (details['userName'] ?? details['displayName'] ?? reportData['postOwnerName'] ?? 'ผู้เล่น').toString();
    final game = (details['game'] ?? '').toString();
    final mediaUrl = (details['mediaUrl'] ?? details['imageUrl'] ?? details['photoUrl'] ?? '').toString();
    final mediaType = (details['mediaType'] ?? '').toString();
    final maxPlayers = details['maxPlayers'];
    final memberCount = details['memberCount'];
    final recruiting = details['isRecruiting'] == true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title.isEmpty ? 'รายละเอียดโพสต์' : title),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(owner, style: Theme.of(dialogContext).textTheme.titleSmall),
                        if (game.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('เกม: $game'),
                        ],
                        if (postId is String && postId.isNotEmpty)
                          Text('รหัสโพสต์: $postId'),
                        const Divider(height: 20),
                        Text(title.isEmpty ? 'โพสต์ไม่มีหัวข้อ' : title,
                            style: Theme.of(dialogContext).textTheme.titleMedium),
                        if (mediaUrl.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          if (mediaType == 'video')
                            const Row(children: [
                              Icon(Icons.videocam_outlined),
                              SizedBox(width: 8),
                              Text('โพสต์นี้มีวิดีโอแนบ'),
                            ])
                          else
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                mediaUrl,
                                width: double.infinity,
                                height: 200,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                        ],
                        const SizedBox(height: 12),
                        Text(body.isEmpty ? 'ไม่มีรายละเอียดเพิ่มเติม' : body),
                        if (maxPlayers != null || memberCount != null) ...[
                          const SizedBox(height: 12),
                          Text('สมาชิก: ${memberCount ?? 0}${maxPlayers == null ? '' : ' / $maxPlayers'} คน'),
                        ],
                        const SizedBox(height: 8),
                        Chip(label: Text(recruiting ? 'กำลังหาสมาชิก' : 'ปิดรับสมาชิก')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('เหตุผลที่รายงาน: ${(reportData['reason'] ?? 'ไม่ได้ระบุ')}'),
                if (postData == null) ...[
                  const SizedBox(height: 8),
                  const Text('โพสต์ต้นฉบับไม่พร้อมใช้งาน แสดงข้อมูลที่บันทึกไว้ในรายงาน'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  /// อัปเดตสถานะรายงาน และเมื่อลบจะลบโพสต์พร้อมบันทึก notification ให้เจ้าของใน batch เดียว.
  Future<void> _resolve(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> report,
      {required bool deletePost}) async {
    final data = report.data();
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(report.reference, {
      'status': deletePost ? 'deleted' : 'reviewed',
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedBy': FirebaseAuth.instance.currentUser!.uid,
    });
    final postId = data['postId'];
    if (deletePost && postId is String && postId.isNotEmpty) {
      batch.delete(db.collection('posts').doc(postId));
      final ownerUid = data['postOwnerUid'];
      if (ownerUid is String && ownerUid.isNotEmpty) {
        batch.set(db.collection('users').doc(ownerUid).collection('notifications').doc(), {
          'type': 'post_removed',
          'body': 'โพสต์ของคุณถูกลบหลังตรวจสอบรายงาน เนื่องจากมีเนื้อหาที่ไม่เหมาะสม',
          'postId': postId,
          'reportId': report.id,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }
    }
    try {
      await batch.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(deletePost ? 'ลบโพสต์และแจ้งเจ้าของแล้ว' : 'ทำเครื่องหมายว่าตรวจสอบแล้ว'),
        ));
      }
    } on FirebaseException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ดำเนินการไม่สำเร็จ (${error.code})')),
        );
      }
    }
  }
}

/// อ่าน users collection เพื่อแสดงรายชื่อและอีเมลของสมาชิกแก่ผู้ดูแล.
class _UsersTab extends StatelessWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('โหลดสมาชิกไม่สำเร็จ'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final users = snapshot.data!.docs;
          if (users.isEmpty) return const Center(child: Text('ยังไม่มีสมาชิก'));
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final user = users[index].data();
              final name = (user['displayName'] ?? user['name'] ?? 'ผู้เล่น').toString();
              return ListTile(
                tileColor: const Color(0xFF171621),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(name),
                subtitle: Text((user['email'] ?? '').toString()),
              );
            },
          );
        },
      );
}
