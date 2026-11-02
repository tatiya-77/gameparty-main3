// หน้ารวมแชตส่วนตัว แชตกลุ่ม และคำเชิญเข้าทีม รวมถึงค้นหาสมาชิกและตอบคำขอ.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../widgets/app_bottom_nav.dart';
import 'group_chat_screen.dart';
import 'private_chat_screen.dart';
import 'profile_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.onBack,
    this.onNavigate,
    this.openInvitations = false,
  });

  final VoidCallback onBack;
  final ValueChanged<int>? onNavigate;
  final bool openInvitations;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

/// จัดการแท็บคำเชิญและแชต รวม query ของห้องส่วนตัว/กลุ่มและสถานะการโหลด.
class _ChatListScreenState extends State<ChatListScreen> {
  int _reloadKey = 0;
  bool _showInvitations = false;
  bool _showGroups = false;
  final TextEditingController _searchController = TextEditingController();

  static const Color _background = Color(0xFF10101A);
  static const Color _surface = Color(0xFF202036);
  static const Color _purple = Color(0xFFB388FF);

  @override
  void initState() {
    super.initState();
    _showInvitations = widget.openInvitations;
  }

  void _reload() {
    setState(() {
      _reloadKey++;
    });
  }

  /// ซ่อนห้องจากรายการของผู้ใช้ โดยไม่ลบข้อมูลห้องหรือประวัติของสมาชิกคนอื่น.
  Future<void> _hideChat(
    DocumentReference<Map<String, dynamic>> reference,
    String chatName,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบแชตนี้หรือไม่?'),
        content: Text('“$chatName” จะถูกซ่อนจากรายการแชตของคุณ ประวัติของสมาชิกคนอื่นยังอยู่ และแชตจะแสดงอีกครั้งเมื่อมีข้อความใหม่'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('ยกเลิก')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('ลบแชต'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await reference.update({'hiddenBy': FieldValue.arrayUnion([user.uid])});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ซ่อนแชตแล้ว')),
        );
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ลบแชตไม่สำเร็จ (${error.code})')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _otherMemberName(
    Map<String, dynamic> data,
    String peerUid,
  ) {
    final names = data['memberNames'];

    if (names is Map) {
      final name = names[peerUid];

      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }

    if (names is List) {
      final members = data['members'];

      if (members is List) {
        final index = members.indexOf(peerUid);

        if (index >= 0 && index < names.length) {
          final name = names[index];

          if (name is String && name.trim().isNotEmpty) {
            return name.trim();
          }
        }
      }
    }

    return 'ผู้เล่น';
  }

  DateTime _getUpdatedAt(Map<String, dynamic> data) {
    final value = data['updatedAt'];

    if (value is Timestamp) {
      return value.toDate();
    }

    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// เปิดฟอร์มสร้างกลุ่มและนำทางไปยังห้องกลุ่มเมื่อสร้างสำเร็จ.
  Future<void> _createGroup() async {
    final group = await showCreateGroupDialog(context);
    if (!mounted || group == null) return;
    setState(() {
      _showGroups = true;
      _showInvitations = false;
    });
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GroupChatScreen(
          groupId: group.id,
          groupName: group.name,
        ),
      ),
    );
  }

  /// ค้นหาบัญชีผู้ใช้เพื่อเริ่มแชตหรือเพิ่มสมาชิก โดยนำผลไปแสดงใน dialog.
  Future<void> _searchUsers() async {
    final profile = await showDialog<_UserSearchResult>(
      context: context,
      builder: (_) => const _SearchUsersDialog(),
    );
    if (!mounted || profile == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (profileContext) => ProfileScreen(
          userId: profile.uid,
          onBack: () => Navigator.of(profileContext).pop(),
        ),
      ),
    );
  }

  /// เจ้าของโพสต์ตอบรับ/ปฏิเสธคำขอ และปรับจำนวนสมาชิก/สถานะโพสต์เมื่อรับเข้าทีม.
  Future<void> _respondToJoinRequest(
    QueryDocumentSnapshot<Map<String, dynamic>> request, {
    required bool accept,
  }) async {
    final owner = FirebaseAuth.instance.currentUser;
    if (owner == null) return;
    final data = request.data();
    final postId = (data['postId'] ?? '').toString();
    final senderUid = (data['senderUid'] ?? '').toString();
    if (postId.isEmpty || senderUid.isEmpty) return;

    final firestore = FirebaseFirestore.instance;
    final postRef = firestore.collection('posts').doc(postId);
    try {
      if (accept) {
        var acceptedTitle = (data['postTitle'] ?? 'ทีมของคุณ').toString();
        await firestore.runTransaction((transaction) async {
          final requestSnapshot = await transaction.get(request.reference);
          final postSnapshot = await transaction.get(postRef);
          if (!requestSnapshot.exists || !postSnapshot.exists) {
            throw StateError('ไม่พบคำขอหรือโพสต์นี้แล้ว');
          }
          final requestData = requestSnapshot.data()!;
          final postData = postSnapshot.data()!;
          if (requestData['status'] != 'pending') {
            throw StateError('คำขอนี้ได้รับการตอบกลับแล้ว');
          }
          acceptedTitle = (postData['title'] ?? acceptedTitle).toString();

          final rawCapacity = postData.containsKey('maxPlayers')
              ? postData['maxPlayers']
              : (postData['slots'] ?? 5);
          final maxPlayers = rawCapacity is num
              ? rawCapacity.toInt()
              : int.tryParse(rawCapacity?.toString() ?? '');
          final rawCount = postData['memberCount'];
          final memberCount = rawCount is num
              ? rawCount.toInt()
              : int.tryParse(rawCount?.toString() ?? '') ?? 1;
          final memberUids = postData['memberUids'] is List
              ? List<String>.from(postData['memberUids'] as List)
              : <String>[];
          if (memberUids.contains(senderUid)) {
            throw StateError('ผู้เล่นนี้เป็นสมาชิกทีมอยู่แล้ว');
          }
          if (postData['isRecruiting'] == false ||
              postData['joinStatus'] == 'closed' ||
              postData['joinStatus'] == 'full' ||
              (maxPlayers != null && memberCount >= maxPlayers)) {
            throw StateError('ทีมเต็มหรือปิดรับสมาชิกแล้ว');
          }
          final newMemberCount = memberCount + 1;
          final isFull = maxPlayers != null && newMemberCount >= maxPlayers;

          transaction.update(postRef, {
            'memberCount': newMemberCount,
            'memberUids': FieldValue.arrayUnion([senderUid]),
            'joinRequestUids': FieldValue.arrayRemove([senderUid]),
            'joinStatus': isFull ? 'full' : 'open',
            'isRecruiting': !isFull,
          });
          transaction.update(request.reference, {'status': 'accepted'});
        });

        // Notification failure must not roll back a successful acceptance or
        // leave the team member count unchanged.
        try {
          await firestore
              .collection('users')
              .doc(senderUid)
              .collection('notifications')
              .add({
            'type': 'join_request_accepted',
            'postId': postId,
            'joinRequestId': request.id,
            'senderUid': owner.uid,
            'senderName': owner.displayName?.trim().isNotEmpty == true
                ? owner.displayName!.trim()
                : (owner.email?.split('@').first ?? 'ผู้เล่น'),
            'body': 'คำขอเข้าร่วม "$acceptedTitle" ได้รับการตอบรับแล้ว',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        } on FirebaseException catch (error) {
          debugPrint('Could not create join acceptance notification: ${error.code}');
        }
      } else {
        final batch = firestore.batch();
        batch.update(request.reference, {'status': 'declined'});
        batch.update(postRef, {
          'joinRequestUids': FieldValue.arrayRemove([senderUid]),
        });
        await batch.commit();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'ตอบรับคำขอและเพิ่มสมาชิกแล้ว' : 'ปฏิเสธคำขอแล้ว'),
        ),
      );
    } on FirebaseException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ดำเนินการไม่สำเร็จ (${error.code})')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  /// อ่าน joinRequests ใต้บัญชีเจ้าของและแสดงสถานะ/ปุ่มจัดการคำเชิญ.
  Widget _buildInvitations(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('joinRequests')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildMessage(
            icon: Icons.cloud_off_outlined,
            title: 'โหลดคำเชิญไม่สำเร็จ',
            subtitle: 'ตรวจสอบการเชื่อมต่อหรือ Firestore Rules',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }
        final requests = snapshot.data!.docs;
        if (requests.isEmpty) {
          return _buildMessage(
            icon: Icons.mark_email_read_outlined,
            title: 'ยังไม่มีคำเชิญเข้าตี้',
            subtitle: 'เมื่อมีผู้เล่นขอเข้าร่วมโพสต์ของคุณ คำขอจะแสดงที่นี่',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 9),
          itemBuilder: (context, index) {
            final request = requests[index];
            final data = request.data();
            final pending = data['status'] == 'pending';
            final accepted = data['status'] == 'accepted';
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF44375F),
                        child: Text((data['senderName'] ?? 'ผ').toString().characters.first),
                      ),
                      const SizedBox(width: 9),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${data['senderName'] ?? 'ผู้เล่น'} ขอเข้าร่วมตี้',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        Text('${data['game'] ?? 'เกม'} · ${data['postTitle'] ?? 'โพสต์ของคุณ'}',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10, color: Color(0xFFAAA7B7))),
                      ])),
                      if (!pending) _statusBadge(accepted ? 'ยอมรับแล้ว' : 'ปฏิเสธแล้ว', accepted),
                    ]),
                    if (pending) ...[
                      const SizedBox(height: 11),
                      Row(children: [
                        Expanded(child: OutlinedButton(
                          onPressed: () => _respondToJoinRequest(request, accept: false),
                          child: const Text('ปฏิเสธ'),
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: FilledButton(
                          onPressed: () => _respondToJoinRequest(request, accept: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFC9FF70),
                            foregroundColor: const Color(0xFF171225),
                          ),
                          child: const Text('ตอบรับคำขอ'),
                        )),
                      ]),
                    ],
                    if (accepted) Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => PrivateChatScreen(
                            peerUid: data['senderUid'].toString(),
                            peerName: data['senderName'].toString(),
                          ),
                        )),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                        label: const Text('เปิดแชต'),
                      ),
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

  /// โหลดห้องส่วนตัวและกลุ่มของผู้ใช้ แล้วกรองด้วยคำค้นก่อนสร้างรายการแชต.
  Widget _buildGroups(String uid, String keyword) {
    final groups = FirebaseFirestore.instance.collection('groupChats');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: groups.where('members', arrayContains: uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final projectId = FirebaseFirestore.instance.app.options.projectId;
          return _buildMessage(
            icon: Icons.lock_outline_rounded,
            title: 'โหลดกลุ่มไม่สำเร็จ',
            subtitle: 'Firebase $projectId · ${_firestoreErrorCode(snapshot.error)}\nUID $uid · ตรวจว่า UID นี้อยู่ใน members ของเอกสาร groupChats',
            showRefresh: true,
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }

        final visibleGroups = snapshot.data!.docs.where((doc) {
          final data = doc.data();
          final hiddenBy = data['hiddenBy'];
          if (hiddenBy is List && hiddenBy.contains(uid)) return false;
          final name = (data['name'] ?? 'กลุ่มแชต').toString().toLowerCase();
          final lastMessage = (data['lastMessage'] ?? '').toString().toLowerCase();
          return keyword.isEmpty || name.contains(keyword) || lastMessage.contains(keyword);
        }).toList()
          ..sort((a, b) => _getUpdatedAt(b.data()).compareTo(_getUpdatedAt(a.data())));

        if (visibleGroups.isEmpty) {
          return _buildMessage(
            icon: Icons.groups_2_outlined,
            title: keyword.isEmpty ? 'ยังไม่มีกลุ่มแชต' : 'ไม่พบกลุ่มที่ค้นหา',
            subtitle: keyword.isEmpty ? 'ไม่พบกลุ่มที่บัญชีนี้เป็นสมาชิก' : 'ลองค้นหาด้วยชื่อกลุ่ม',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: visibleGroups.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final doc = visibleGroups[index];
            final data = doc.data();
            final name = (data['name'] ?? 'กลุ่มแชต').toString();
            final members = data['members'] is List ? (data['members'] as List).length : 0;
            return Card(
              color: _surface,
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF44375F),
                  child: Icon(Icons.groups_rounded, color: Color(0xFFC9FF70)),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${data['lastMessage'] ?? 'เริ่มคุยในกลุ่ม'} · $members สมาชิก',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60),
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'ลบแชต',
                    onPressed: () => _hideChat(doc.reference, name),
                    icon: const Icon(Icons.delete_outline, color: Colors.white70),
                  ),
                  const Icon(Icons.chevron_right, color: _purple),
                ]),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => GroupChatScreen(groupId: doc.id, groupName: name),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _firestoreErrorCode(Object? error) {
    return error is FirebaseException ? error.code : '$error';
  }

  Widget _statusBadge(String label, bool accepted) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accepted ? const Color(0xFF232A21) : const Color(0xFF302943),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 9,
          color: accepted ? const Color(0xFFC9FF70) : const Color(0xFFC5AFFF),
        )),
      );

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0C0C13),
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('แชต', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('คุยกับเพื่อนและทีมของคุณ',
                style: TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'ค้นหาผู้ใช้',
              onPressed: _searchUsers,
              icon: const Icon(Icons.person_search_outlined),
            ),
          if (user != null)
            IconButton(
              tooltip: 'สร้างกลุ่มแชต',
              onPressed: _createGroup,
              icon: const Icon(Icons.group_add_outlined),
            ),
          if (user != null)
            IconButton(
              tooltip: 'คำเชิญเข้าตี้',
              onPressed: () => setState(() {
                _showInvitations = true;
                _showGroups = false;
              }),
              icon: const Icon(Icons.mark_email_unread_outlined),
            ),
          IconButton(
            tooltip: 'โหลดรายการใหม่',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: widget.onNavigate == null
          ? null
          : AppBottomNav(currentIndex: 2, onTap: widget.onNavigate!),
      body: user == null
          ? _buildMessage(
              icon: Icons.lock_outline,
              title: 'กรุณาเข้าสู่ระบบก่อน',
              subtitle: 'เข้าสู่ระบบเพื่อดูรายการแชทส่วนตัว',
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey(_reloadKey),
              stream: FirebaseFirestore.instance
                  .collection('privateChats')
                  .where(
                    'members',
                    arrayContains: user.uid,
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final error = snapshot.error.toString();

                  debugPrint('Chat list error: $error');
                  debugPrint('Current UID: ${user.uid}');
                  debugPrint(
                    'Firebase project: '
                    '${FirebaseFirestore.instance.app.options.projectId}',
                  );

                  if (snapshot.error is FirebaseException &&
                      (snapshot.error as FirebaseException).code ==
                          'permission-denied') {
                    return _buildMessage(
                      icon: Icons.lock_outline_rounded,
                      title: 'Firestore Rules ยังไม่อนุญาตให้ดูแชต',
                      subtitle: 'แอปกำลังเชื่อมต่อโปรเจ็กต์ '
                          '${FirebaseFirestore.instance.app.options.projectId}\n'
                          'ตรวจว่าได้กด Publish Rules ในโปรเจ็กต์นี้แล้ว '
                          'และกำลังเข้าสู่ระบบด้วยบัญชีที่ถูกต้อง',
                      showRefresh: true,
                    );
                  }

                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 60,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'โหลดรายการแชทไม่สำเร็จ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SelectableText(
                            error,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh),
                            label: const Text('ลองโหลดใหม่'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: _purple,
                    ),
                  );
                }

                final chats = [
                  ...?snapshot.data?.docs,
                ];

                // เรียงห้องแชทตามเวลาที่อัปเดตล่าสุด
                chats.sort((a, b) {
                  return _getUpdatedAt(b.data()).compareTo(
                    _getUpdatedAt(a.data()),
                  );
                });

                // เลือกเฉพาะห้องที่มีสมาชิก 2 คน
                // และมี UID ของผู้ใช้ที่ล็อกอินอยู่
                final keyword = _searchController.text.trim().toLowerCase();
                final validChats = chats.where((doc) {
                  final data = doc.data();
                  final hiddenBy = data['hiddenBy'];
                  if (hiddenBy is List && hiddenBy.contains(user.uid)) return false;
                  final members = data['members'];

                  if (members is! List || members.length != 2) {
                    return false;
                  }

                  final uids = members.whereType<String>().toList();

                  final peerUid = uids.firstWhere(
                    (uid) => uid != user.uid,
                    orElse: () => '',
                  );
                  final peerName = _otherMemberName(data, peerUid);
                  final lastMessage =
                      (data['lastMessage'] ?? '').toString();

                  return (keyword.isEmpty ||
                          peerName.toLowerCase().contains(keyword) ||
                          lastMessage.toLowerCase().contains(keyword)) &&
                      uids.length == 2 &&
                      uids.toSet().length == 2 &&
                      uids.contains(user.uid);
                }).toList();

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: _sectionTab(
                              label: 'ข้อความ',
                              icon: Icons.chat_bubble_rounded,
                              selected: !_showInvitations && !_showGroups,
                              onTap: () => setState(() {
                                _showInvitations = false;
                                _showGroups = false;
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _sectionTab(
                              label: 'กลุ่ม',
                              icon: Icons.groups_rounded,
                              selected: _showGroups,
                              onTap: () => setState(() {
                                _showInvitations = false;
                                _showGroups = true;
                              }),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _sectionTab(
                              label: 'คำเชิญ',
                              icon: Icons.mark_email_unread_outlined,
                              selected: _showInvitations,
                              onTap: () => setState(() {
                                _showInvitations = true;
                                _showGroups = false;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 3),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'ค้นหาบทสนทนา...',
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
                    Expanded(
                      child: _showInvitations
                          ? _buildInvitations(user.uid)
                          : _showGroups
                              ? _buildGroups(user.uid, keyword)
                          : validChats.isEmpty
                          ? _buildMessage(
                              icon: Icons.forum_outlined,
                              title: keyword.isEmpty
                                  ? 'ยังไม่มีแชตส่วนตัว'
                                  : 'ไม่พบบทสนทนา',
                              subtitle: keyword.isEmpty
                                  ? 'เมื่อเริ่มสนทนากับผู้เล่น ห้องแชตจะแสดงที่นี่'
                                  : 'ลองค้นหาด้วยชื่อผู้เล่นหรือข้อความอื่น',
                              showRefresh: true,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: validChats.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final doc = validChats[index];
                                final data = doc.data();
                                final members = (data['members'] as List)
                                    .whereType<String>();

                                final peerUid = members.firstWhere(
                                  (uid) => uid != user.uid,
                                  orElse: () => '',
                                );

                                if (peerUid.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                final peerName = _otherMemberName(
                                  data,
                                  peerUid,
                                );

                                final rawMessage = data['lastMessage'];

                                final lastMessage = rawMessage is String &&
                                        rawMessage.trim().isNotEmpty
                                    ? rawMessage.trim()
                                    : 'เริ่มสนทนา';

                                return Card(
                                  color: _surface,
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: const BorderSide(
                                      color: Color(0xFF393957),
                                    ),
                                  ),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      radius: 26,
                                      backgroundColor: const Color(0xFF6C3CC9),
                                      child: Text(
                                        peerName.isNotEmpty
                                            ? peerName.characters.first
                                                .toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      peerName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 5),
                                      child: Text(
                                        lastMessage,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white60,
                                        ),
                                      ),
                                    ),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      IconButton(
                                        tooltip: 'ลบแชต',
                                        onPressed: () => _hideChat(doc.reference, peerName),
                                        icon: const Icon(Icons.delete_outline, color: Colors.white70),
                                      ),
                                      const Icon(Icons.chevron_right, color: _purple),
                                    ]),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PrivateChatScreen(
                                            peerUid: peerUid,
                                            peerName: peerName,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Widget _sectionTab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final color = selected ? const Color(0xFF332A4E) : const Color(0xFF191824);
    final border = selected ? const Color(0xFF51436F) : const Color(0xFF302E3D);
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 11),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? const Color(0xFFC9FF70) : const Color(0xFFB69EFF),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    required String subtitle,
    bool showRefresh = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 72,
              color: _purple,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
              ),
            ),
            if (showRefresh) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
                label: const Text('โหลดรายการใหม่'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _purple,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserSearchResult {
  const _UserSearchResult({required this.uid, required this.name});

  final String uid;
  final String name;
}

class _SearchUsersDialog extends StatefulWidget {
  const _SearchUsersDialog();

  @override
  State<_SearchUsersDialog> createState() => _SearchUsersDialogState();
}

/// สถานะและ UI ของหน้าต่างค้นหาผู้ใช้ แยกจากรายการแชตหลัก.
class _SearchUsersDialogState extends State<_SearchUsersDialog> {
  final _controller = TextEditingController();
  final _currentUid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _nameOf(Map<String, dynamic> data) {
    for (final key in ['displayName', 'name', 'username']) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    final email = data['email']?.toString() ?? '';
    return email.contains('@') ? email.split('@').first : 'ผู้เล่น';
  }

  @override
  Widget build(BuildContext context) {
    final keyword = _controller.text.trim().toLowerCase();
    return AlertDialog(
      title: const Text('ค้นหาผู้ใช้'),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ชื่อผู้ใช้ อีเมล หรือ UID',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'ล้างคำค้นหา',
                        onPressed: () {
                          _controller.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('โหลดรายชื่อผู้ใช้ไม่สำเร็จ'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final profiles = snapshot.data!.docs.where((doc) {
                    if (doc.id == _currentUid) return false;
                    if (keyword.isEmpty) return true;
                    final data = doc.data();
                    final searchable = <String>[
                      doc.id,
                      data['displayName']?.toString() ?? '',
                      data['name']?.toString() ?? '',
                      data['username']?.toString() ?? '',
                      data['email']?.toString() ?? '',
                    ].join(' ').toLowerCase();
                    return searchable.contains(keyword);
                  }).toList()
                    ..sort((a, b) => _nameOf(a.data())
                        .toLowerCase()
                        .compareTo(_nameOf(b.data()).toLowerCase()));

                  if (profiles.isEmpty) {
                    return Center(
                      child: Text(keyword.isEmpty
                          ? 'ยังไม่มีผู้ใช้อื่น'
                          : 'ไม่พบผู้ใช้ที่ค้นหา'),
                    );
                  }

                  return ListView.separated(
                    itemCount: profiles.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final data = profile.data();
                      final name = _nameOf(data);
                      final email = (data['email'] ?? '').toString();
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(name.characters.first.toUpperCase()),
                        ),
                        title: Text(name),
                        subtitle: Text(
                          email.isEmpty ? 'UID: ${profile.id}' : email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).pop(
                          _UserSearchResult(uid: profile.id, name: name),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ปิด'),
        ),
      ],
    );
  }
}
