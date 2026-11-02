/// หน้าโปรไฟล์ของตนเองหรือผู้ใช้อื่น รองรับแก้ข้อมูล ติดตาม แชต ดูโพสต์ และตั้งค่าความเป็นส่วนตัว.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/app_bottom_nav.dart';
import 'notification_screen.dart';
import 'private_chat_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<int>? onNavigate;
  final String? userId;

  const ProfileScreen({
    super.key,
    required this.onBack,
    this.onNavigate,
    this.userId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

/// รองรับดูโปรไฟล์ตัวเองหรือคนอื่น โดย _targetUid เลือก UID เป้าหมายและ _isOwnProfile คุมสิทธิ์ UI.
class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  bool _editing = false;
  bool _saving = false;
  bool _followingBusy = false;
  bool _profileChecked = false;
  bool _isPrivate = false;
  bool _controllersInitialized = false;
  List<String> _selectedGames = <String>[];

  static const List<String> _availableGames = [
    'Valorant', 'ROV', 'Minecraft', 'PUBG', 'Free Fire', 'Genshin Impact',
  ];

  String? get _myUid => _auth.currentUser?.uid;
  String? get _targetUid => widget.userId ?? _myUid;

  bool get _isOwnProfile => _myUid != null && _myUid == _targetUid;

  DocumentReference<Map<String, dynamic>>? get _userRef {
    final uid = _targetUid;
    if (uid == null || uid.isEmpty) return null;
    return _db.collection('users').doc(uid);
  }

  @override
  void initState() {
    super.initState();
    _ensureOwnProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// สร้างเอกสารโปรไฟล์เริ่มต้นให้เจ้าของบัญชีเมื่อยังไม่มี โดยไม่เขียนทับข้อมูลที่มี.
  Future<void> _ensureOwnProfile() async {
    final user = _auth.currentUser;

    if (user == null || !_isOwnProfile) {
      if (mounted) {
        setState(() => _profileChecked = true);
      }
      return;
    }

    try {
      final ref = _db.collection('users').doc(user.uid);
      final snapshot = await ref.get();

      final fallbackName =
          user.displayName ?? user.email?.split('@').first ?? 'ผู้เล่น';

      if (!snapshot.exists) {
        await ref.set({
          'uid': user.uid,
          'displayName': fallbackName,
          'email': user.email ?? '',
          'photoURL': user.photoURL ?? '',
          'bio': '',
          'isPrivate': false,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final data = snapshot.data() ?? <String, dynamic>{};
        final updates = <String, dynamic>{};

        if ((data['uid'] ?? '').toString().isEmpty) {
          updates['uid'] = user.uid;
        }

        if ((data['displayName'] ?? '').toString().trim().isEmpty) {
          updates['displayName'] = fallbackName;
        }

        if ((data['email'] ?? '').toString().isEmpty && user.email != null) {
          updates['email'] = user.email;
        }

        if ((data['photoURL'] ?? '').toString().isEmpty &&
            user.photoURL != null) {
          updates['photoURL'] = user.photoURL;
        }

        if (updates.isNotEmpty) {
          updates['updatedAt'] = FieldValue.serverTimestamp();
          await ref.set(updates, SetOptions(merge: true));
        }
      }
    } catch (e) {
      if (mounted) _showMessage(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _profileChecked = true);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _errorMessage(Object error) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'ไม่มีสิทธิ์เข้าถึงข้อมูล กรุณาตรวจสอบ Firestore Rules';
        case 'unavailable':
          return 'เชื่อมต่อไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ต';
        case 'unauthenticated':
          return 'กรุณาเข้าสู่ระบบใหม่อีกครั้ง';
        case 'not-found':
          return 'ไม่พบข้อมูลที่ต้องการ';
        default:
          return 'เกิดข้อผิดพลาด (${error.code})';
      }
    }

    return 'เกิดข้อผิดพลาด กรุณาลองใหม่';
  }

  String _displayName(
    Map<String, dynamic> data, {
    User? authUser,
  }) {
    final value = data['displayName'] ??
        data['name'] ??
        data['username'] ??
        authUser?.displayName ??
        authUser?.email?.split('@').first ??
        'ผู้เล่น';

    final name = value.toString().trim();
    return name.isEmpty ? 'ผู้เล่น' : name;
  }

  // เรียกหลัง build เพื่อไม่แก้ไข controller ระหว่าง build
  void _syncProfileFields(
      String name, String bio, bool isPrivate, List<String> games) {
    if (_editing || _controllersInitialized) return;

    _controllersInitialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editing) return;

      _nameController.text = name;
      _bioController.text = bio;
      _selectedGames = games;

      setState(() {
        _isPrivate = isPrivate;
      });
    });
  }

  void _startEditing({
    required String name,
    required String bio,
    required bool isPrivate,
    required List<String> games,
  }) {
    _nameController.text = name;
    _bioController.text = bio;

    setState(() {
      _isPrivate = isPrivate;
      _selectedGames = List<String>.from(games);
      _editing = true;
    });
  }

  /// ตรวจและบันทึกชื่อ ประวัติ และเกมที่สนใจกลับ users/{uid}.
  Future<void> _saveProfile() async {
    final user = _auth.currentUser;
    final ref = _userRef;

    if (user == null || ref == null || !_isOwnProfile) return;

    final name = _nameController.text.trim();
    final bio = _bioController.text.trim();

    if (name.isEmpty) {
      _showMessage('กรุณากรอกชื่อที่ต้องการแสดง');
      return;
    }

    setState(() => _saving = true);

    try {
      await ref.set({
        'uid': user.uid,
        'displayName': name,
        'email': user.email ?? '',
        'photoURL': user.photoURL ?? '',
        'bio': bio,
        'isPrivate': _isPrivate,
        'favoriteGames': _selectedGames,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (user.displayName != name) {
        await user.updateDisplayName(name);
      }

      if (!mounted) return;

      setState(() {
        _editing = false;
        _controllersInitialized = true;
      });

      _showMessage('บันทึกโปรไฟล์เรียบร้อยแล้ว');
    } catch (e) {
      _showMessage(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  /// เพิ่มหรือลบความสัมพันธ์ followers/following และแจ้งผู้ใช้เมื่อเริ่มติดตาม.
  Future<void> _toggleFollow() async {
    final myUid = _myUid;
    final targetUid = _targetUid;

    if (myUid == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อนติดตามสมาชิก');
      return;
    }

    if (targetUid == null || targetUid.isEmpty || myUid == targetUid) {
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อนติดตามสมาชิก');
      return;
    }

    if (_followingBusy) return;

    setState(() => _followingBusy = true);

    final followerRef = _db
        .collection('users')
        .doc(targetUid)
        .collection('followers')
        .doc(myUid);

    final followingRef = _db
        .collection('users')
        .doc(myUid)
        .collection('following')
        .doc(targetUid);
    final notificationRef = _db
        .collection('users')
        .doc(targetUid)
        .collection('notifications')
        .doc();
    final followerName = currentUser.displayName?.trim().isNotEmpty == true
        ? currentUser.displayName!.trim()
        : (currentUser.email?.split('@').first ?? 'ผู้เล่น');

    try {
      await _db.runTransaction((transaction) async {
        final followerSnapshot = await transaction.get(followerRef);
        final followingSnapshot = await transaction.get(followingRef);

        if (followerSnapshot.exists) {
          transaction.delete(followerRef);

          if (followingSnapshot.exists) {
            transaction.delete(followingRef);
          }
        } else {
          transaction.set(followerRef, {
            'uid': myUid,
            'createdAt': FieldValue.serverTimestamp(),
          });

          transaction.set(followingRef, {
            'uid': targetUid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          transaction.set(notificationRef, {
            'type': 'new_follower',
            'senderUid': myUid,
            'senderName': followerName,
            'body': '$followerName เริ่มติดตามคุณ',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        }
      });

      _showMessage('อัปเดตการติดตามเรียบร้อยแล้ว');
    } catch (e) {
      _showMessage(_errorMessage(e));
    } finally {
      if (mounted) {
        setState(() => _followingBusy = false);
      }
    }
  }

  void _openChat(String name) {
    final myUid = _myUid;
    final targetUid = _targetUid;

    if (myUid == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อนเริ่มแชท');
      return;
    }

    if (targetUid == null || targetUid.isEmpty || targetUid == myUid) {
      _showMessage('ไม่สามารถเปิดแชทนี้ได้');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrivateChatScreen(
          peerUid: targetUid,
          peerName: name,
        ),
      ),
    );
  }

  void _openUserList(String uid, String subcollection) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => UserListScreen(
          ownerUid: uid,
          subcollection: subcollection,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ออกจากระบบ'),
        content: const Text('คุณต้องการออกจากระบบหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _auth.signOut();

      if (mounted) widget.onBack();
    } catch (e) {
      _showMessage(_errorMessage(e));
    }
  }

  /// บันทึกค่าความเป็นส่วนตัวของโปรไฟล์สำหรับเจ้าของบัญชีเท่านั้น.
  Future<void> _setPrivate(bool value) async {
    final ref = _userRef;
    final uid = _targetUid;

    if (ref == null || uid == null || !_isOwnProfile) return;

    setState(() => _isPrivate = value);

    try {
      await ref.set({
        'uid': uid,
        'isPrivate': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        setState(() => _isPrivate = !value);
        _showMessage(_errorMessage(e));
      }
    }
  }

  Widget _buildCount({
    required String label,
    required String uid,
    required String subcollection,
    bool clickable = false,
    bool hidden = false,
  }) {
    if (hidden) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF191824),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF302E3D)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '—',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFC9FF70),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Color(0xFFAAA7B7)),
            ),
          ],
        ),
      );
    }

    final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

    if (subcollection == 'posts') {
      stream = _db.collection('posts').where('uid', isEqualTo: uid).snapshots();
    } else {
      stream = _db
          .collection('users')
          .doc(uid)
          .collection(subcollection)
          .snapshots();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;

        return InkWell(
          onTap: clickable ? () => _openUserList(uid, subcollection) : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF191824),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF302E3D)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC9FF70),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Color(0xFFAAA7B7)),
                ),
                if (clickable)
                  const Text(
                    'ดูรายชื่อ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 9, color: Color(0xFF9B7CFF)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFollowButton() {
    final myUid = _myUid;
    final targetUid = _targetUid;

    if (myUid == null || targetUid == null || targetUid == myUid) {
      return const SizedBox.shrink();
    }

    final ref = _db
        .collection('users')
        .doc(targetUid)
        .collection('followers')
        .doc(myUid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snapshot) {
        final isFollowing = snapshot.data?.exists ?? false;

        return OutlinedButton.icon(
          onPressed: _followingBusy ? null : _toggleFollow,
          icon: Icon(
            isFollowing ? Icons.person_remove_outlined : Icons.person_add_alt_1,
          ),
          label: Text(
            _followingBusy
                ? 'กำลังดำเนินการ...'
                : isFollowing
                    ? 'เลิกติดตาม'
                    : 'ติดตาม',
          ),
        );
      },
    );
  }

  Widget _buildGameChips(
    String uid,
    List<String> profileGames, {
    required bool includePostGames,
  }) {
    Widget buildChips(Set<String> games) {
      if (games.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('เกมที่เลือกจะปรากฏที่นี่',
              style: TextStyle(fontSize: 11, color: Color(0xFF9291A4))),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: games.take(5).map((game) => Padding(
            padding: const EdgeInsets.only(right: 7),
            child: Chip(
              avatar: const Text('🎮', style: TextStyle(fontSize: 13)),
              label: Text(game, style: const TextStyle(fontSize: 10)),
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: Color(0xFF51436F)),
              backgroundColor: const Color(0xFF252332),
            ),
          )).toList(),
        ),
      );
    }

    if (!includePostGames) {
      return buildChips(profileGames.toSet());
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('posts').where('uid', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        final games = <String>{...profileGames};
        for (final post in snapshot.data?.docs ?? const []) {
          final game = (post.data()['game'] ?? '').toString().trim();
          if (game.isNotEmpty) games.add(game);
        }
        return buildChips(games);
      },
    );
  }

  /// อ่านโพสต์ของ UID เป้าหมายและแสดงเป็นรายการบนหน้าโปรไฟล์.
  Widget _buildPosts(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('posts').where('uid', isEqualTo: uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(_errorMessage(snapshot.error!)),
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final posts = snapshot.data!.docs.toList();

        posts.sort((a, b) {
          final at = a.data()['createdAt'];
          final bt = b.data()['createdAt'];

          final ad = at is Timestamp
              ? at.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);

          final bd = bt is Timestamp
              ? bt.toDate()
              : DateTime.fromMillisecondsSinceEpoch(0);

          return bd.compareTo(ad);
        });

        if (posts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 35),
            child: Center(child: Text('ยังไม่มีโพสต์')),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = posts[index].data();

            final title = (data['title'] ?? '').toString();
            final detail = (data['detail'] ?? '').toString();
            final game = (data['game'] ?? '').toString();
            final imageUrl = (data['imageUrl'] ?? '').toString();

            final likes = data['likes'] ?? 0;
            final dislikes = data['dislikes'] ?? 0;
            final createdAt = data['createdAt'];

            return Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (game.isNotEmpty)
                      Text(
                        game,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(detail),
                    ],
                    if (imageUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
                          width: double.infinity,
                          height: 230,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 60,
                            child: Center(
                              child: Icon(Icons.broken_image_outlined),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.favorite_border,
                              size: 17,
                            ),
                            const SizedBox(width: 5),
                            Text('$likes'),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.thumb_down_alt_outlined,
                              size: 17,
                            ),
                            const SizedBox(width: 5),
                            Text('$dislikes'),
                          ],
                        ),
                        if (createdAt is Timestamp)
                          Text(
                            _formatDate(createdAt.toDate()),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(date.day)}/${two(date.month)}/${date.year} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final uid = _targetUid;

    if (uid == null || uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('โปรไฟล์'),
        ),
        body: const Center(
          child: Text('กรุณาเข้าสู่ระบบเพื่อดูโปรไฟล์'),
        ),
      );
    }

    if (!_profileChecked && _isOwnProfile) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: widget.onBack,
          ),
          title: const Text('โปรไฟล์ของฉัน'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final userRef = _userRef;
    if (userRef == null) {
      return const Scaffold(
        body: Center(child: Text('ไม่พบข้อมูลบัญชีนี้')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Text(
          _isOwnProfile ? 'โปรไฟล์ของฉัน' : 'โปรไฟล์สมาชิก',
        ),
        actions: [
          if (_isOwnProfile && !_editing)
            IconButton(
              tooltip: 'แก้ไขโปรไฟล์',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _startEditing(
                name: _nameController.text,
                bio: _bioController.text,
                isPrivate: _isPrivate,
                games: _selectedGames,
              ),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_errorMessage(snapshot.error!)),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userSnapshot = snapshot.data!;
          final data = userSnapshot.data() ?? <String, dynamic>{};

          if (!userSnapshot.exists && !_isOwnProfile) {
            return const Center(child: Text('ไม่พบข้อมูลบัญชีนี้'));
          }

          final authUser = _auth.currentUser;

          final displayName = _displayName(
            data,
            authUser: _isOwnProfile ? authUser : null,
          );

          final email =
              (data['email'] ?? (_isOwnProfile ? authUser?.email : null) ?? '')
                  .toString();

          final bio = (data['bio'] ?? '').toString();
          final isPrivate = data['isPrivate'] == true;

          final photoUrl = (data['photoURL'] ??
                  data['photoUrl'] ??
                  data['profileImageUrl'] ??
                  (_isOwnProfile ? authUser?.photoURL : null) ??
                  '')
              .toString();

          final profileGames = List<String>.from(data['favoriteGames'] ?? const <String>[]);
          _syncProfileFields(displayName, bio, isPrivate, profileGames);

          final avatarLetter =
              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'ผ';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [Color(0xFF35294F), Color(0xFF1B1928)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF45385F)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('PLAYER CARD', style: TextStyle(
                          fontSize: 9, letterSpacing: 1.4,
                          fontWeight: FontWeight.w700, color: Color(0xFFC9B7FF),
                        )),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF232A21),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('● ACTIVE', style: TextStyle(
                            fontSize: 8, color: Color(0xFFC9FF70), fontWeight: FontWeight.w600,
                          )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Color(0xFFFF9EC4), Color(0xFF9B7CFF)]),
                      ),
                      child: CircleAvatar(
                        radius: 42,
                        backgroundColor: const Color(0xFF544177),
                        backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                        child: photoUrl.isEmpty
                            ? Text(avatarLetter, style: const TextStyle(
                                fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white,
                              ))
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.bold),
                    ),
                    if (_isOwnProfile && email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(email,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFB7B1C4), fontSize: 12)),
                    ],
                    if (bio.isNotEmpty && !_editing) ...[
                      const SizedBox(height: 9),
                      Text(bio,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFCEC9D8))),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (!_editing) ...[
                // ใช้ Expanded ป้องกัน Row ล้นหน้าจอ
                Row(
                  children: [
                    Expanded(
                      child: _buildCount(
                        label: 'โพสต์',
                        uid: uid,
                        subcollection: 'posts',
                        hidden: isPrivate && !_isOwnProfile,
                      ),
                    ),
                    Expanded(
                      child: _buildCount(
                        label: 'ผู้ติดตาม',
                        uid: uid,
                        subcollection: 'followers',
                        clickable: true,
                      ),
                    ),
                    Expanded(
                      child: _buildCount(
                        label: 'กำลังติดตาม',
                        uid: uid,
                        subcollection: 'following',
                        clickable: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                Row(children: [
                  const Expanded(child: Text('เกมที่เล่น',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                  TextButton(onPressed: () => widget.onNavigate?.call(1),
                      child: const Text('เพิ่มเกม ›', style: TextStyle(fontSize: 10))),
                ]),
                _buildGameChips(
                  uid,
                  profileGames,
                  includePostGames: !isPrivate || _isOwnProfile,
                ),

                if (!_isOwnProfile)
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _buildFollowButton(),
                      FilledButton.icon(
                        onPressed: () => _openChat(displayName),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('แชทส่วนตัว'),
                      ),
                    ],
                  ),

                const SizedBox(height: 20),
                Text(
                  _isOwnProfile
                      ? 'โพสต์ของฉัน'
                      : isPrivate
                          ? 'โพสต์'
                          : 'โพสต์ของ $displayName',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (isPrivate && !_isOwnProfile)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 24,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191824),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF302E3D)),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 32,
                          color: Color(0xFFB69EFF),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'บัญชีนี้เป็นส่วนตัว',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'โพสต์ของบัญชีนี้จะแสดงให้เจ้าของบัญชีเห็นเท่านั้น',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9291A4),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _buildPosts(uid),
                if (_isOwnProfile) ...[
                  const SizedBox(height: 18),
                  const Text('บัญชีและความเป็นส่วนตัว',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(children: [
                      SwitchListTile(
                        title: const Text('บัญชีส่วนตัว', style: TextStyle(fontSize: 12)),
                        subtitle: const Text('ควบคุมการแสดงโปรไฟล์ของคุณ',
                            style: TextStyle(fontSize: 10, color: Color(0xFF9291A4))),
                        value: isPrivate,
                        onChanged: _setPrivate,
                      ),
                      const Divider(height: 1, indent: 14, endIndent: 14),
                      ListTile(
                        leading: const Icon(Icons.notifications_none_rounded, color: Color(0xFFB69EFF)),
                        title: const Text('การแจ้งเตือน', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const NotificationScreen()),
                        ),
                      ),
                      const Divider(height: 1, indent: 14, endIndent: 14),
                      ListTile(
                        leading: const Icon(Icons.logout_rounded, color: Color(0xFFFF9EAF)),
                        title: const Text('ออกจากระบบ', style: TextStyle(fontSize: 12, color: Color(0xFFFF9EAF))),
                        onTap: _logout,
                      ),
                    ]),
                  ),
                ],
              ] else ...[
                TextField(
                  controller: _nameController,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อที่แสดง',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioController,
                  maxLines: 3,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'แนะนำตัว',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.info_outline),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('บัญชีส่วนตัว'),
                  value: _isPrivate,
                  onChanged: (value) {
                    setState(() => _isPrivate = value);
                  },
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('เกมที่เล่น', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  runSpacing: 2,
                  children: _availableGames.map((game) => FilterChip(
                    label: Text(game, style: const TextStyle(fontSize: 10)),
                    selected: _selectedGames.contains(game),
                    showCheckmark: false,
                    onSelected: _saving ? null : (selected) => setState(() {
                      selected ? _selectedGames.add(game) : _selectedGames.remove(game);
                    }),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _saveProfile,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('บันทึก'),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          setState(() {
                            _editing = false;
                            _isPrivate = isPrivate;
                            _selectedGames = profileGames;
                            _nameController.text = displayName;
                            _bioController.text = bio;
                          });
                        },
                  child: const Text('ยกเลิก'),
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: widget.onNavigate == null
          ? null
          : AppBottomNav(currentIndex: 3, onTap: widget.onNavigate!),
    );
  }
}

/// หน้าแสดงรายชื่อ follower หรือ following ที่เปิดมาจากตัวเลขบนโปรไฟล์.
class UserListScreen extends StatelessWidget {
  final String ownerUid;
  final String subcollection;

  const UserListScreen({
    super.key,
    required this.ownerUid,
    required this.subcollection,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final isFollowers = subcollection == 'followers';

    return Scaffold(
      appBar: AppBar(
        title: Text(isFollowers ? 'ผู้ติดตาม' : 'กำลังติดตาม'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('users')
            .doc(ownerUid)
            .collection(subcollection)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'โหลดรายชื่อไม่ได้ กรุณาตรวจสอบ Firestore Rules',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          if (docs.isEmpty) {
            return Center(
              child: Text(
                isFollowers ? 'ยังไม่มีผู้ติดตาม' : 'ยังไม่ได้ติดตามใคร',
              ),
            );
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final targetUid = docs[index].id;

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: db.collection('users').doc(targetUid).snapshots(),
                builder: (context, userSnapshot) {
                  if (userSnapshot.hasError) {
                    return const ListTile(
                      leading: CircleAvatar(
                        child: Icon(Icons.person),
                      ),
                      title: Text('โหลดข้อมูลสมาชิกไม่ได้'),
                    );
                  }

                  if (!userSnapshot.hasData) {
                    return const ListTile(
                      leading: CircleAvatar(
                        child: Icon(Icons.person),
                      ),
                      title: Text('กำลังโหลด...'),
                    );
                  }

                  final userData = userSnapshot.data!.data();

                  if (userData == null) {
                    return const ListTile(
                      leading: CircleAvatar(
                        child: Icon(Icons.person_off),
                      ),
                      title: Text('ไม่พบข้อมูลบัญชีนี้'),
                    );
                  }

                  final name = (userData['displayName'] ??
                          userData['name'] ??
                          userData['username'] ??
                          'ผู้เล่น')
                      .toString();

                  final photoUrl = (userData['photoURL'] ??
                          userData['photoUrl'] ??
                          userData['profileImageUrl'] ??
                          '')
                      .toString();

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                      child: photoUrl.isEmpty ? const Icon(Icons.person) : null,
                    ),
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            userId: targetUid,
                            onBack: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
