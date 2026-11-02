import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/app_bottom_nav.dart';
import '../widgets/inline_video_player.dart';
import '../widgets/join_request_button.dart';
import '../utils/date_time_format.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({
    super.key,
    required this.onNavigate,
    this.initialGame = 'ทั้งหมด',
  });

  final ValueChanged<int> onNavigate;
  final String initialGame;

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();
  final Set<String> _sentJoinRequestPostIds = <String>{};
  final Set<String> _joiningPostIds = <String>{};
  String _selectedGame = 'ทั้งหมด';
  bool _availableNowOnly = false;
  bool _micOnly = false;

  static const _games = [
    'ทั้งหมด',
    'Valorant',
    'ROV',
    'Minecraft',
    'PUBG',
    'Free Fire',
    'Genshin Impact',
  ];

  @override
  void initState() {
    super.initState();
    if (_games.contains(widget.initialGame)) {
      _selectedGame = widget.initialGame;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _requestJoin(String postId, Map<String, dynamic> post) async {
    final user = FirebaseAuth.instance.currentUser;
    final ownerUid = (post['uid'] ?? '').toString();
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนส่งคำขอ')),
      );
      return;
    }
    if (ownerUid.isEmpty || ownerUid == user.uid) return;
    if (_joiningPostIds.contains(postId) ||
        _sentJoinRequestPostIds.contains(postId)) {
      return;
    }
    final rawCapacity = post.containsKey('maxPlayers')
        ? post['maxPlayers']
        : (post['slots'] ?? 5);
    final maxPlayers = rawCapacity is num
        ? rawCapacity.toInt()
        : int.tryParse(rawCapacity?.toString() ?? '');
    final rawMemberCount = post['memberCount'];
    final memberCount = rawMemberCount is num
        ? rawMemberCount.toInt()
        : int.tryParse(rawMemberCount?.toString() ?? '') ?? 1;
    if (post['isRecruiting'] == false || post['joinStatus'] == 'closed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('โพสต์นี้ปิดรับสมาชิกแล้ว')),
      );
      return;
    }
    if (post['joinStatus'] == 'full' ||
        (maxPlayers != null && memberCount >= maxPlayers)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ทีมนี้เต็มแล้ว')),
      );
      return;
    }
    final requestId = '${postId}_${user.uid}';
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('joinRequests')
        .doc(requestId);
    final senderName = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'ผู้เล่น');
    setState(() => _joiningPostIds.add(postId));
    try {
      await ref.set({
        'postId': postId,
        'postTitle': (post['title'] ?? 'กำลังหาเพื่อนเล่น').toString(),
        'game': (post['game'] ?? 'เกม').toString(),
        'ownerUid': ownerUid,
        'senderUid': user.uid,
        'senderName': senderName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      JoinRequestButton.markPending(user.uid, postId);
      if (!mounted) return;
      setState(() {
        _joiningPostIds.remove(postId);
        _sentJoinRequestPostIds.add(postId);
      });
      var notificationSent = true;
      try {
        await FirebaseFirestore.instance.collection('posts').doc(postId).update({
          'joinRequestUids': FieldValue.arrayUnion([user.uid]),
        });
      } on FirebaseException catch (error) {
        debugPrint('Could not mirror join request on post: ${error.code}');
      }
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerUid)
            .collection('notifications')
            .doc('join_request_${ref.id}')
            .set({
          'type': 'join_request_received',
          'postId': postId,
          'joinRequestId': ref.id,
          'senderUid': user.uid,
          'senderName': senderName,
          'body': '$senderName ขอเข้าร่วมทีม "${post['title'] ?? 'ทีมของคุณ'}"',
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } on FirebaseException catch (error) {
        debugPrint('Could not create join request notification: ${error.code}');
        notificationSent = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(notificationSent
            ? 'ส่งคำขอเข้าร่วมแล้ว'
            : 'ส่งคำขอแล้ว แต่แจ้งเตือนติดสิทธิ์ Firebase กรุณา Publish firestore.rules ล่าสุด'),
      ));
    } catch (error) {
      if (!mounted) return;
      setState(() => _joiningPostIds.remove(postId));
      final message = error is FirebaseException &&
              error.code == 'permission-denied'
          ? 'ส่งคำขอไม่ได้: Firestore Rules ของ game-party-202 ยังไม่อนุญาตให้สร้างคำขอเข้าร่วม'
          : 'ส่งคำขอไม่สำเร็จ: $error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ค้นหาตี้', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              'เจอทีมที่ใช่ แล้วไปสนุกด้วยกัน',
              style: TextStyle(fontSize: 11, color: Color(0xFF9291A4)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'ค้นหา',
            onPressed: () => setState(
              () => _availableNowOnly = !_availableNowOnly,
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ค้นหาเกมหรือแรงค์...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 2, 18, 7),
            child: Row(children: [
              const Expanded(child: Text('เกมยอดนิยม',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              TextButton(onPressed: () => setState(() => _selectedGame = 'ทั้งหมด'),
                  child: const Text('ดูทั้งหมด  ›', style: TextStyle(fontSize: 10))),
            ]),
          ),
          SizedBox(
            height: 96,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: _games.length,
              separatorBuilder: (_, __) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final game = _games[index];
                final selected = game == _selectedGame;
                final emoji = switch (game) {
                  'Valorant' => '⚡',
                  'ROV' => '🛡️',
                  'Minecraft' => '⛏️',
                  'PUBG' => '🎯',
                  'Free Fire' => '🔥',
                  'Genshin Impact' => '✨',
                  _ => '🎮',
                };

                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _selectedGame = game),
                  child: Container(
                    width: 78,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF302849)
                          : const Color(0xFF171621),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF9B7CFF)
                            : const Color(0xFF2A2938),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 25)),
                        const SizedBox(height: 5),
                        Text(
                          game,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: selected ? Colors.white : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 3),
            child: Row(children: [
              const Expanded(child: Text('ตัวกรองตี้',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              TextButton.icon(onPressed: () => setState(() {
                _availableNowOnly = false;
                _micOnly = false;
              }), icon: const Icon(Icons.tune_rounded, size: 14),
                  label: const Text('ล้างตัวกรอง', style: TextStyle(fontSize: 10))),
            ]),
          ),
          SizedBox(
            height: 38,
            child: ListView(scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                FilterChip(label: const Text('ทุกแรงค์'), selected: !_availableNowOnly && !_micOnly,
                  onSelected: (_) => setState(() { _availableNowOnly = false; _micOnly = false; }),
                  showCheckmark: false, visualDensity: VisualDensity.compact),
                const SizedBox(width: 7),
                FilterChip(label: const Text('มีไมค์'), selected: _micOnly,
                  onSelected: (value) => setState(() => _micOnly = value),
                  showCheckmark: false, visualDensity: VisualDensity.compact),
                const SizedBox(width: 7),
                FilterChip(label: const Text('เล่นตอนนี้'), selected: _availableNowOnly,
                  onSelected: (value) => setState(() => _availableNowOnly = value),
                  avatar: const Icon(Icons.bolt_rounded, size: 15),
                  showCheckmark: false, visualDensity: VisualDensity.compact),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 8, 18, 5),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('โพสต์ที่กำลังหาเพื่อน',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _message(
                    Icons.cloud_off_outlined,
                    'โหลดโพสต์ไม่สำเร็จ',
                    'ลองตรวจสอบการเชื่อมต่อแล้วโหลดใหม่',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final keyword = _searchController.text.trim().toLowerCase();
                final posts = snapshot.data!.docs.where((doc) {
                  final data = doc.data();
                  final game = (data['game'] ?? '').toString();
                  if (_selectedGame != 'ทั้งหมด' &&
                      game.toLowerCase() != _selectedGame.toLowerCase()) {
                    return false;
                  }
                  if (_availableNowOnly && data['availableNow'] == false) {
                    return false;
                  }
                  if (_micOnly && data['hasMic'] != true) return false;
                  if (keyword.isEmpty) return true;
                  return ['game', 'title', 'detail', 'userName'].any(
                    (key) => (data[key] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(keyword),
                  );
                }).toList();

                if (posts.isEmpty) {
                  return _message(
                    Icons.search_off_rounded,
                    'ยังไม่พบโพสต์ที่ตรงกัน',
                    'ลองเลือกเกมอื่นหรือเปลี่ยนคำค้นหา',
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final data = posts[index].data();
                    final owner = (data['uid'] ?? '').toString();
                    final ownPost = owner == user?.uid;
                    final game = (data['game'] ?? 'เกม').toString();
                    final playerName =
                        (data['userName'] ?? 'ผู้เล่น').toString();
                    final title =
                        (data['title'] ?? 'กำลังหาเพื่อนเล่น').toString();
                    final createdAtLabel = formatDateTimeLabel(data['createdAt']);
                    final detail = (data['detail'] ?? '').toString();
                    final mediaUrl =
                        (data['mediaUrl'] ?? data['imageUrl'] ?? '').toString();
                    final isVideo = data['mediaType'] == 'video';
                    final rawCapacity = data.containsKey('maxPlayers')
                        ? data['maxPlayers']
                        : (data['slots'] ?? 5);
                    final maxPlayers = rawCapacity is num
                        ? rawCapacity.toInt()
                        : int.tryParse(rawCapacity?.toString() ?? '');
                    final rawMemberCount = data['memberCount'];
                    final memberCount = rawMemberCount is num
                        ? rawMemberCount.toInt()
                        : int.tryParse(rawMemberCount?.toString() ?? '') ?? 1;
                    final joinRequestUids =
                        List<String>.from(data['joinRequestUids'] ?? const []);
                    final memberUids =
                        List<String>.from(data['memberUids'] ?? const []);
                    final requested = user != null && joinRequestUids.contains(user.uid);
                    final hasJoined = user != null && memberUids.contains(user.uid);
                    final isFull = data['joinStatus'] == 'full' ||
                        (maxPlayers != null && memberCount >= maxPlayers);
                    final isClosed = data['isRecruiting'] == false ||
                        data['joinStatus'] == 'closed';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 11),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF44375F),
                                  child: Text(
                                    playerName.isEmpty
                                        ? 'ผ'
                                        : playerName.characters.first,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(playerName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      Text(game,
                                          style: const TextStyle(
                                              color: Color(0xFFB69EFF),
                                              fontSize: 11)),
                                      if (createdAtLabel != null)
                                        Text(
                                          createdAtLabel,
                                          style: const TextStyle(
                                            color: Color(0xFF9291A4),
                                            fontSize: 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF302943),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(game.toUpperCase(),
                                      style: const TextStyle(fontSize: 9, color: Color(0xFFC5AFFF))),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(title,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            if (detail.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(detail,
                                  style: const TextStyle(
                                      color: Color(0xFFAAA7B7), height: 1.45)),
                            ],
                            if (mediaUrl.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(13),
                                child: isVideo
                                    ? InlineVideoPlayer(url: mediaUrl, height: 190)
                                    : Image.network(mediaUrl,
                                        height: 190,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const SizedBox(height: 80)),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                _tag('🎮 $game'),
                                if (data['hasMic'] == true) _tag('🎙️ มีไมค์'),
                                _tag('● กำลังหาเพื่อน',
                                    color: const Color(0xFF273020)),
                              ],
                            ),
                            const SizedBox(height: 9),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.only(top: 9),
                              child: Row(
                                children: [
                                  const Icon(Icons.group_outlined, size: 17, color: Color(0xFFAAA7B7)),
                                  const SizedBox(width: 5),
                                  Text('สมาชิก $memberCount/${maxPlayers ?? '∞'}',
                                      style: const TextStyle(fontSize: 10, color: Color(0xFFAAA7B7))),
                                  const Spacer(),
                                  JoinRequestButton(
                                    postId: posts[index].id,
                                    ownerUid: owner,
                                    currentUserUid: user?.uid,
                                    isOwnPost: ownPost,
                                    hasJoined: hasJoined,
                                    requestSentOnPost: requested,
                                    requestSentLocally:
                                        _sentJoinRequestPostIds.contains(posts[index].id) ||
                                            _joiningPostIds.contains(posts[index].id),
                                    isFull: isFull,
                                    isClosed: isClosed,
                                    compact: true,
                                    onPressed: () => _requestJoin(posts[index].id, data),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 1,
        onTap: widget.onNavigate,
      ),
    );
  }

  Widget _tag(String label, {Color color = const Color(0xFF252332)}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(label, style: const TextStyle(fontSize: 10)),
      ),
    );
  }

  Widget _message(IconData icon, String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: const Color(0xFF9B7CFF)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Text(detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9291A4))),
          ],
        ),
      ),
    );
  }
}
