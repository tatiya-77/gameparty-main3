// ชุดเมธอดจัดการโพสต์ผ่าน Firestore แยกจาก widget (บางหน้าจอมี logic โพสต์ของตนเองด้วย).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// ชั้น service ห่อการอ่านและแก้ไข posts collection เพื่อลด Firebase logic ใน UI.
class PostService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // อ้างอิง Collection posts
  CollectionReference<Map<String, dynamic>> get _posts {
    return _db.collection('posts');
  }

  // ==========================================
  // 1. แสดงโพสต์ทั้งหมดแบบ Real-time
  // ==========================================
  /// ส่ง stream โพสต์เรียงจากใหม่ไปเก่า เพื่อให้ UI อัปเดตแบบเรียลไทม์.
  Stream<QuerySnapshot<Map<String, dynamic>>> getPosts() {
    return _posts
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ==========================================
  // 2. เพิ่มโพสต์หาตี้
  // ==========================================
  /// ตรวจผู้ใช้และฟิลด์บังคับก่อนสร้างเอกสารโพสต์เริ่มต้น.
  Future<void> createPost({
    required String game,
    required String title,
    required String detail,
    String imageUrl = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('กรุณาเข้าสู่ระบบก่อนสร้างโพสต์');
    }

    if (game.trim().isEmpty ||
        title.trim().isEmpty ||
        detail.trim().isEmpty) {
      throw Exception('กรุณากรอกข้อมูลให้ครบ');
    }

    await _posts.add({
      'uid': user.uid,
      'userName': user.displayName ?? 'Player',
      'game': game.trim(),
      'title': title.trim(),
      'detail': detail.trim(),
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': 0,
      'dislikes': 0,
      'likedBy': <String>[],
      'dislikedBy': <String>[],
      'reactions': <String, dynamic>{},
      'reactionUsers': <String, dynamic>{},
      'reactionByUid': <String, String>{},
    });
  }

  // ==========================================
  // 3. แก้ไขโพสต์
  // ==========================================
  /// ตรวจว่าเอกสารมีอยู่และ UID เจ้าของตรงกับบัญชีปัจจุบันก่อนแก้ไข.
  Future<void> updatePost({
    required String postId,
    required String game,
    required String title,
    required String detail,
    String imageUrl = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('กรุณาเข้าสู่ระบบก่อน');
    }

    final postRef = _posts.doc(postId);
    final doc = await postRef.get();

    if (!doc.exists) {
      throw Exception('ไม่พบโพสต์นี้');
    }

    final data = doc.data();

    if (data == null || data['uid'] != user.uid) {
      throw Exception('คุณไม่มีสิทธิ์แก้ไขโพสต์นี้');
    }

    await postRef.update({
      'game': game.trim(),
      'title': title.trim(),
      'detail': detail.trim(),
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ==========================================
  // 4. ลบโพสต์
  // ==========================================
  /// อ่านโพสต์เพื่อยืนยันเจ้าของก่อนลบ ไม่เชื่อ postId จาก UI อย่างเดียว.
  Future<void> deletePost(String postId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('กรุณาเข้าสู่ระบบก่อน');
    }

    final postRef = _posts.doc(postId);
    final doc = await postRef.get();

    if (!doc.exists) {
      throw Exception('ไม่พบโพสต์นี้');
    }

    final data = doc.data();

    if (data == null || data['uid'] != user.uid) {
      throw Exception('คุณไม่มีสิทธิ์ลบโพสต์นี้');
    }

    await postRef.delete();
  }

  // ==========================================
  // 5. ค้นหาโพสต์ตามชื่อเกม หัวข้อ รายละเอียด
  // ==========================================
  /// กรองคำค้นใน game/title/detail จาก snapshot; การกรองนี้ทำบน client.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> searchPosts(
    String keyword,
  ) {
    return _posts.snapshots().map((snapshot) {
      final query = keyword.trim().toLowerCase();

      if (query.isEmpty) {
        return snapshot.docs;
      }

      return snapshot.docs.where((doc) {
        final data = doc.data();

        final game =
            (data['game'] ?? '').toString().toLowerCase();

        final title =
            (data['title'] ?? '').toString().toLowerCase();

        final detail =
            (data['detail'] ?? '').toString().toLowerCase();

        return game.contains(query) ||
            title.contains(query) ||
            detail.contains(query);
      }).toList();
    });
  }

  // ==========================================
  // 6. เพิ่มจำนวน Like
  // ==========================================
  /// เพิ่มจำนวน like ด้วย transaction เพื่อป้องกันการอ่านค่าเก่าแล้วเขียนทับกัน.
  Future<void> likePost(String postId) async {
    final postRef = _posts.doc(postId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(postRef);

      if (!snapshot.exists) {
        throw Exception('ไม่พบโพสต์นี้');
      }

      final data = snapshot.data();
      final currentLikes = data?['likes'] as int? ?? 0;

      transaction.update(postRef, {
        'likes': currentLikes + 1,
      });
    });
  }
}
