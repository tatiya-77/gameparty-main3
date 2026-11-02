
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PostService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // อ้างอิง Collection posts
  CollectionReference<Map<String, dynamic>> get _posts {
    return _db.collection('posts');
  }

  // ==========================================
  // 1. แสดงโพสต์ทั้งหมดแบบ Real-time
  // ==========================================
  Stream<QuerySnapshot<Map<String, dynamic>>> getPosts() {
    return _posts
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // ==========================================
  // 2. เพิ่มโพสต์หาตี้
  // ==========================================
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
