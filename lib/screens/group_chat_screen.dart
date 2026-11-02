/// หน้าสนทนากลุ่ม จัดการข้อความ/สื่อ สมาชิก การแจ้งเตือน การลบประวัติ และการออกจากกลุ่ม.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/cloudinary_service.dart';
import '../widgets/inline_video_player.dart';
import '../widgets/media_viewer.dart';
import '../utils/date_time_format.dart';

class GroupChatInfo {
  const GroupChatInfo({required this.id, required this.name});

  final String id;
  final String name;
}

Future<GroupChatInfo?> showCreateGroupDialog(BuildContext context) {
  return showDialog<GroupChatInfo>(
    context: context,
    builder: (_) => const _CreateGroupDialog(),
  );
}

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

/// ถือสถานะห้องกลุ่มและ composer พร้อม reference ไป groupChats/{groupId}.
class _GroupChatScreenState extends State<GroupChatScreen> {
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  bool _sending = false;
  bool _clearingHistory = false;
  bool _leaving = false;

  DocumentReference<Map<String, dynamic>> get _groupRef =>
      FirebaseFirestore.instance.collection('groupChats').doc(widget.groupId);

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// บันทึกข้อความและ lastMessage ของกลุ่มใน batch เดียว จากนั้นสร้างแจ้งเตือนให้สมาชิก.
  Future<void> _send() async {
    final user = FirebaseAuth.instance.currentUser;
    final text = _textController.text.trim();
    if (user == null || text.isEmpty || _sending || _clearingHistory) return;
    setState(() => _sending = true);
    try {
      final groupData = (await _groupRef.get()).data() ?? <String, dynamic>{};
      final batch = FirebaseFirestore.instance.batch();
      batch.update(_groupRef, {
        'lastMessage': text,
        'lastSenderUid': user.uid,
        'hiddenBy': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final messageRef = _groupRef.collection('messages').doc();
      batch.set(messageRef, {
        'uid': user.uid,
        'name': user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email?.split('@').first ?? 'ผู้เล่น'),
        'text': text,
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      await _notifyGroupMembers(
        sender: user,
        groupData: groupData,
        messageId: messageRef.id,
        body: text,
      );
      if (mounted) _textController.clear();
    } on FirebaseException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ส่งข้อความไม่สำเร็จ (${error.code})')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _displayName(User user) {
    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;
    final emailName = user.email?.split('@').first.trim() ?? '';
    return emailName.isNotEmpty ? emailName : 'ผู้เล่น';
  }

  /// ส่ง notification ให้สมาชิกทุกคนยกเว้นผู้ส่ง โดยใช้ ID ที่ป้องกันเอกสารซ้ำ.
  Future<void> _notifyGroupMembers({
    required User sender,
    required Map<String, dynamic> groupData,
    required String messageId,
    required String body,
  }) async {
    final members = (groupData['members'] is List
            ? groupData['members'] as List
            : const <dynamic>[])
        .whereType<String>();
    final groupName = (groupData['name'] ?? widget.groupName).toString();
    final batch = FirebaseFirestore.instance.batch();
    var notificationCount = 0;
    for (final memberUid in members) {
      if (memberUid == sender.uid) continue;
      batch.set(
        FirebaseFirestore.instance
            .collection('users')
            .doc(memberUid)
            .collection('notifications')
            .doc('group_message_${widget.groupId}_${messageId}_$memberUid'),
        {
          'type': 'group_chat_message',
          'groupId': widget.groupId,
          'groupName': groupName,
          'messageId': messageId,
          'senderUid': sender.uid,
          'senderName': _displayName(sender),
          'body': body,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        },
      );
      notificationCount++;
    }
    if (notificationCount == 0) return;
    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      debugPrint('Could not notify group members: ${error.code}');
    }
  }

  Future<void> _chooseMedia() async {
    if (_sending || _clearingHistory) return;
    final isVideo = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปภาพ'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('เลือกวิดีโอ'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (isVideo == null || !mounted) return;
    await _sendMedia(isVideo: isVideo);
  }

  /// อัปโหลดสื่อไป Cloudinary แล้วเพิ่มข้อความสื่อในห้องกลุ่ม.
  Future<void> _sendMedia({required bool isVideo}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _sending || _clearingHistory) return;

    try {
      final file = isVideo
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
      if (file == null || !mounted) return;

      setState(() => _sending = true);
      final fileSize = await file.length();
      const maxFileSize = 50 * 1024 * 1024;
      if (fileSize == 0) {
        _showSnack('ไฟล์ว่างเปล่า กรุณาเลือกไฟล์ใหม่');
        return;
      }
      if (fileSize > maxFileSize) {
        _showSnack('ไฟล์ต้องมีขนาดไม่เกิน 50 MB');
        return;
      }

      _showSnack('กำลังอัปโหลด${isVideo ? 'วิดีโอ' : 'รูปภาพ'}...');
      final mediaUrl = await CloudinaryService.uploadMedia(
        file,
        isVideo: isVideo,
      );
      if (mediaUrl == null || mediaUrl.isEmpty) {
        throw StateError('บริการอัปโหลดไม่ได้ส่ง URL ของไฟล์กลับมา');
      }

      final type = isVideo ? 'video' : 'image';
      final groupData = (await _groupRef.get()).data() ?? <String, dynamic>{};
      final batch = FirebaseFirestore.instance.batch();
      batch.update(_groupRef, {
        'lastMessage': isVideo ? 'ส่งวิดีโอ' : 'ส่งรูปภาพ',
        'lastSenderUid': user.uid,
        'hiddenBy': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final messageRef = _groupRef.collection('messages').doc();
      batch.set(messageRef, {
        'uid': user.uid,
        'name': _displayName(user),
        'text': '',
        'type': type,
        'mediaUrl': mediaUrl,
        'fileName': file.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
      await _notifyGroupMembers(
        sender: user,
        groupData: groupData,
        messageId: messageRef.id,
        body: isVideo ? 'ส่งวิดีโอ' : 'ส่งรูปภาพ',
      );
      if (mounted) _showSnack('ส่ง${isVideo ? 'วิดีโอ' : 'รูปภาพ'}แล้ว');
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('ส่งสื่อไม่สำเร็จ (${error.code})');
    } catch (error) {
      if (mounted) _showSnack('ส่งสื่อไม่สำเร็จ: $error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// อ่านรายชื่อสมาชิกปัจจุบันและเปิดหน้าต่างแสดงข้อมูลสมาชิก.
  Future<void> _showMembers() async {
    try {
      final group = await _groupRef.get();
      if (!mounted || !group.exists) return;
      final data = group.data() ?? {};
      final members = (data['members'] is List ? data['members'] as List : const [])
          .whereType<String>()
          .toList();
      final names = data['memberNames'] is Map
          ? Map<String, dynamic>.from(data['memberNames'] as Map)
          : <String, dynamic>{};
      final ownerUid = (data['ownerUid'] ?? '').toString();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.65,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'สมาชิกกลุ่ม (${members.length})',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                ),
                Expanded(
                  child: members.isEmpty
                      ? const Center(child: Text('ไม่พบรายชื่อสมาชิก'))
                      : ListView.builder(
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final uid = members[index];
                            final name = (names[uid] ?? '').toString().trim();
                            final visibleName = name.isEmpty ? 'ผู้เล่น' : name;
                            final shortUid = uid.length > 8 ? uid.substring(0, 8) : uid;
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  visibleName.isEmpty ? '?' : visibleName[0].toUpperCase(),
                                ),
                              ),
                              title: Text(visibleName),
                              subtitle: Text('UID: $shortUid'),
                              trailing: uid == ownerUid
                                  ? const Chip(label: Text('เจ้าของ'))
                                  : null,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('โหลดรายชื่อสมาชิกไม่สำเร็จ (${error.code})');
    }
  }

  /// เปิด flow เลือกผู้ใช้และเพิ่มเข้า members ของห้องตามสิทธิ์.
  Future<void> _showAddMembers() async {
    DocumentSnapshot<Map<String, dynamic>> groupSnapshot;
    try {
      groupSnapshot = await _groupRef.get();
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('โหลดข้อมูลกลุ่มไม่สำเร็จ (${error.code})');
      return;
    }
    if (!mounted || !groupSnapshot.exists) return;
    final groupData = groupSnapshot.data() ?? <String, dynamic>{};
    final currentMembers = (groupData['members'] is List
            ? groupData['members'] as List
            : const <dynamic>[])
        .whereType<String>()
        .toList();
    final remainingSlots = 50 - currentMembers.length;
    if (remainingSlots <= 0) {
      _showSnack('กลุ่มนี้มีสมาชิกครบ 50 คนแล้ว');
      return;
    }

    final selectedUids = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AddGroupMembersDialog(
        existingUids: currentMembers.toSet(),
        maxSelectable: remainingSlots,
      ),
    );
    if (!mounted || selectedUids == null || selectedUids.isEmpty) return;

    try {
      final profiles = await Future.wait(
        selectedUids.map(
          (uid) => FirebaseFirestore.instance.collection('users').doc(uid).get(),
        ),
      );
      final addedNames = <String, String>{};
      for (final profile in profiles) {
        if (!profile.exists) continue;
        final data = profile.data() ?? <String, dynamic>{};
        final displayName = (data['displayName'] ??
                data['name'] ??
                data['username'] ??
                data['email']?.toString().split('@').first ??
                'ผู้เล่น')
            .toString()
            .trim();
        addedNames[profile.id] = displayName.isEmpty ? 'ผู้เล่น' : displayName;
      }

      var addedCount = 0;
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final freshGroup = await transaction.get(_groupRef);
        if (!freshGroup.exists) throw StateError('ไม่พบกลุ่มนี้แล้ว');
        final data = freshGroup.data() ?? <String, dynamic>{};
        final members = (data['members'] is List
                ? data['members'] as List
                : const <dynamic>[])
            .whereType<String>()
            .toList();
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid == null || !members.contains(currentUid)) {
          throw StateError('เฉพาะสมาชิกกลุ่มเท่านั้นที่เพิ่มสมาชิกได้');
        }
        final newMembers = selectedUids
            .where((uid) => !members.contains(uid))
            .toList();
        if (newMembers.isEmpty) return;
        if (members.length + newMembers.length > 50) {
          throw StateError('กลุ่มมีสมาชิกได้สูงสุด 50 คน');
        }

        final memberNames = data['memberNames'] is Map
            ? Map<String, dynamic>.from(data['memberNames'] as Map)
            : <String, dynamic>{};
        for (final uid in newMembers) {
          // Keep a previous name when inviting someone who left earlier.
          memberNames.putIfAbsent(uid, () => addedNames[uid] ?? 'ผู้เล่น');
        }
        transaction.update(_groupRef, {
          'members': [...members, ...newMembers],
          'memberNames': memberNames,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        addedCount = newMembers.length;
      });

      if (mounted) {
        _showSnack(addedCount == 0 ? 'ผู้เล่นที่เลือกเป็นสมาชิกกลุ่มอยู่แล้ว' : 'เพิ่มสมาชิกแล้ว $addedCount คน');
      }
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('เพิ่มสมาชิกไม่สำเร็จ (${error.code})');
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString().replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _deleteMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> message,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final messageData = message.data();
    DocumentSnapshot<Map<String, dynamic>> group;
    try {
      group = await _groupRef.get();
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('ตรวจสอบสิทธิ์ลบไม่สำเร็จ (${error.code})');
      return;
    }
    if (!mounted) return;
    final isOwner = group.data()?['ownerUid'] == user.uid;
    final isMine = messageData['uid'] == user.uid;
    if (!isMine && !isOwner) {
      _showSnack('ลบได้เฉพาะข้อความของตัวเอง');
      return;
    }

    final isMedia = ['image', 'video'].contains(messageData['type']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isMedia ? 'ลบสื่อออกจากแชต' : 'ลบข้อความ'),
        content: Text(isMedia
            ? 'ต้องการลบ${messageData['type'] == 'video' ? 'วิดีโอ' : 'รูปภาพ'}นี้ออกจากแชตหรือไม่?'
            : 'ต้องการลบข้อความนี้ออกจากแชตหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) return;

    try {
      await message.reference.delete();
      if (mounted) _showSnack(isMedia ? 'ลบสื่อออกจากแชตแล้ว' : 'ลบข้อความแล้ว');
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('ลบไม่สำเร็จ (${error.code})');
    }
  }

  /// ลบข้อความของห้องเป็น batch ขนาดจำกัดจนหมด แล้วล้างข้อความตัวอย่างล่าสุด.
  Future<void> _clearChatHistory() async {
    if (_clearingHistory || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบประวัติแชตกลุ่ม'),
        content: const Text(
          'ข้อความ รูปภาพ และวิดีโอทั้งหมดในกลุ่มนี้จะถูกลบสำหรับสมาชิกทุกคน และกู้คืนไม่ได้ ต้องการดำเนินการต่อหรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบประวัติ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingHistory = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final messages = _groupRef.collection('messages');
      while (true) {
        final page = await messages.limit(400).get();
        if (page.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final message in page.docs) {
          batch.delete(message.reference);
        }
        await batch.commit();
      }
      await _groupRef.update({
        'lastMessage': 'ล้างประวัติแชตแล้ว',
        'lastSenderUid': user.uid,
        'hiddenBy': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnack('ลบประวัติแชตกลุ่มแล้ว');
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('ลบประวัติไม่สำเร็จ (${error.code})');
    } finally {
      if (mounted) setState(() => _clearingHistory = false);
    }
  }

  /// นำผู้ใช้ออกจากสมาชิกห้องและปิดหน้าหลังอัปเดตสำเร็จ.
  Future<void> _leaveGroup() async {
    if (_leaving || _sending || _clearingHistory) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ออกจากกลุ่มนี้?'),
        content: const Text(
          'คุณจะถูกนำออกจากรายชื่อสมาชิกและจะไม่เห็นกลุ่มนี้ในรายการแชตอีก '
          'ประวัติเดิมของสมาชิกคนอื่นจะยังอยู่ ถ้าคุณเป็นเจ้าของกลุ่ม '
          'สิทธิ์เจ้าของจะย้ายไปยังสมาชิกที่เหลือ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('ออกจากกลุ่ม'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _leaving = true);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final group = await transaction.get(_groupRef);
        if (!group.exists) throw StateError('ไม่พบกลุ่มนี้แล้ว');
        final data = group.data() ?? <String, dynamic>{};
        final members = (data['members'] is List
                ? data['members'] as List
                : const <dynamic>[])
            .whereType<String>()
            .toList();
        if (!members.contains(user.uid)) {
          throw StateError('คุณไม่ได้เป็นสมาชิกของกลุ่มนี้แล้ว');
        }

        final ownerUid = (data['ownerUid'] ?? '').toString();
        if (members.length == 1) {
          if (ownerUid != user.uid) {
            throw StateError('ไม่สามารถออกจากกลุ่มที่ไม่มีสมาชิกคนอื่นได้');
          }
          transaction.delete(_groupRef);
          return;
        }

        final remainingMembers = members.where((uid) => uid != user.uid).toList();
        transaction.update(_groupRef, {
          'members': remainingMembers,
          if (ownerUid == user.uid) 'ownerUid': remainingMembers.first,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) Navigator.of(context).pop();
    } on FirebaseException catch (error) {
      if (mounted) _showSnack('ออกจากกลุ่มไม่สำเร็จ (${error.code})');
    } catch (error) {
      if (mounted) {
        _showSnack(error.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _groupRef.snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            final memberCount = data?['members'] is List
                ? (data!['members'] as List).length
                : 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.groupName, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  memberCount > 0 ? 'สมาชิก $memberCount คน' : 'แชตกลุ่ม',
                  style: const TextStyle(fontSize: 10, color: Colors.white60),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            tooltip: 'ออกจากกลุ่ม',
            onPressed: _leaving ? null : _leaveGroup,
            icon: _leaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.logout_rounded),
          ),
          IconButton(
            tooltip: 'ลบประวัติแชตกลุ่ม',
            onPressed: _clearingHistory ? null : _clearChatHistory,
            icon: _clearingHistory
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'เพิ่มสมาชิกในกลุ่ม',
            onPressed: _showAddMembers,
            icon: const Icon(Icons.person_add_alt_1_outlined),
          ),
          IconButton(
            tooltip: 'ดูสมาชิกในกลุ่ม',
            onPressed: _showMembers,
            icon: const Icon(Icons.people_alt_outlined),
          ),
        ],
      ),
      body: uid == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _groupRef
                        .collection('messages')
                        .orderBy('createdAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        final error = snapshot.error;
                        final code = error is FirebaseException ? error.code : '$error';
                        return Center(child: Text('โหลดข้อความกลุ่มไม่สำเร็จ ($code)'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final messages = snapshot.data!.docs;
                      if (messages.isEmpty) {
                        return const Center(child: Text('เริ่มส่งข้อความในกลุ่มได้เลย'));
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(14),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final data = messages[index].data();
                          final timeLabel = formatChatTimeLabel(data['createdAt']);
                          final showDateDivider = index == messages.length - 1 ||
                              !isSameChatDay(
                                data['createdAt'],
                                messages[index + 1].data()['createdAt'],
                              );
                          final dateLabel =
                              formatChatDateDividerLabel(data['createdAt']);
                          final isMine = data['uid'] == uid;
                          final type = (data['type'] ?? 'text').toString();
                          final mediaUrl = (data['mediaUrl'] ?? '').toString();
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showDateDivider && dateLabel != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Center(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF302A3B),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 13, vertical: 6,
                                        ),
                                        child: Text(
                                          dateLabel,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              Align(
                            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (isMine && timeLabel != null)
                                  ChatTimeLabel(label: timeLabel),
                                GestureDetector(
                                  onLongPress: () => _deleteMessage(messages[index]),
                                  child: Container(
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.62,
                                ),
                              margin: const EdgeInsets.only(bottom: 9),
                              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                              decoration: BoxDecoration(
                                color: isMine ? const Color(0xFF6245A5) : const Color(0xFF252332),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isMine)
                                    Text(
                                      (data['name'] ?? 'ผู้เล่น').toString(),
                                      style: const TextStyle(color: Color(0xFFC9FF70), fontSize: 10),
                                    ),
                                  if (type == 'image' && mediaUrl.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => showChatMediaViewer(
                                        context,
                                        url: mediaUrl,
                                        isVideo: false,
                                      ),
                                      child: ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: Image.network(
                                        mediaUrl,
                                        width:
                                            MediaQuery.of(context).size.width *
                                                0.54,
                                        fit: BoxFit.contain,
                                        loadingBuilder: (context, child, progress) =>
                                            progress == null
                                                ? child
                                                : const SizedBox(
                                                    width: 250,
                                                    height: 150,
                                                    child: Center(child: CircularProgressIndicator()),
                                                  ),
                                        errorBuilder: (_, __, ___) => const SizedBox(
                                          width: 250,
                                          height: 90,
                                          child: Center(child: Text('โหลดรูปภาพไม่สำเร็จ')),
                                        ),
                                      ),
                                    ),
                                    )
                                  else if (type == 'video' && mediaUrl.isNotEmpty)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(9),
                                      child: InlineVideoPlayer(
                                        url: mediaUrl,
                                        height: 180,
                                        onOpen: () => showChatMediaViewer(
                                          context,
                                          url: mediaUrl,
                                          isVideo: true,
                                        ),
                                      ),
                                    ),
                                  if ((data['text'] ?? '').toString().trim().isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: mediaUrl.isNotEmpty ? 6 : 0,
                                      ),
                                      child: Text((data['text'] ?? '').toString()),
                                    ),
                                ],
                              ),
                            ),
                                ),
                                if (!isMine && timeLabel != null)
                                  ChatTimeLabel(label: timeLabel),
                              ],
                            ),
                          ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(hintText: 'พิมพ์ข้อความในกลุ่ม...'),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 7),
                        IconButton(
                          tooltip: 'ส่งรูปภาพหรือวิดีโอ',
                          onPressed: _sending || _clearingHistory ? null : _chooseMedia,
                          icon: const Icon(Icons.attach_file_rounded),
                        ),
                        IconButton.filled(
                          onPressed: _sending || _clearingHistory ? null : _send,
                          icon: _sending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

/// เก็บชื่อกลุ่มและสมาชิกเริ่มต้นก่อนสร้างเอกสาร groupChats.
class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _memberSearchController = TextEditingController();
  final Set<String> _selectedUids = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _memberSearchController.dispose();
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

  /// ตรวจข้อมูลแล้วสร้างห้องกลุ่มพร้อมกำหนดเจ้าของและสมาชิกชุดแรก.
  Future<void> _createGroup() async {
    final user = FirebaseAuth.instance.currentUser;
    final name = _nameController.text.trim();
    if (user == null || name.isEmpty || _selectedUids.isEmpty || _saving) {
      setState(() => _error = 'ตั้งชื่อกลุ่มและเลือกสมาชิกอย่างน้อย 1 คน');
      return;
    }
    if (_selectedUids.length > 49) {
      setState(() => _error = 'กลุ่มมีสมาชิกได้สูงสุด 50 คน รวมผู้สร้างกลุ่ม');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final users = await Future.wait(
        _selectedUids.map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).get()),
      );
      final memberNames = <String, String>{
        user.uid: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email?.split('@').first ?? 'ผู้เล่น'),
      };
      for (final profile in users) {
        if (profile.exists) memberNames[profile.id] = _nameOf(profile.data() ?? {});
      }
      final members = [user.uid, ..._selectedUids];
      final ref = FirebaseFirestore.instance.collection('groupChats').doc();
      await ref.set({
        'name': name,
        'ownerUid': user.uid,
        'members': members,
        'memberNames': memberNames,
        'lastMessage': 'สร้างกลุ่มแล้ว',
        'lastSenderUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).pop(GroupChatInfo(id: ref.id, name: name));
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'สร้างกลุ่มไม่สำเร็จ (${error.code})';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return AlertDialog(
      title: const Text('สร้างกลุ่มแชต'),
      content: SizedBox(
        width: 380,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              maxLength: 40,
              decoration: const InputDecoration(labelText: 'ชื่อกลุ่ม'),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('เลือกสมาชิก (${_selectedUids.length} คน)', style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _memberSearchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'ค้นหาชื่อ อีเมล หรือ UID',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _memberSearchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _memberSearchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    final error = snapshot.error;
                    final code = error is FirebaseException ? error.code : '$error';
                    return Center(child: Text('โหลดรายชื่อผู้เล่นไม่ได้ ($code)'));
                  }
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final keyword = _memberSearchController.text.trim().toLowerCase();
                  final profiles = snapshot.data!.docs.where((doc) {
                    if (doc.id == myUid) return false;
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
                    ..sort((a, b) => _nameOf(a.data()).toLowerCase().compareTo(
                          _nameOf(b.data()).toLowerCase(),
                        ));
                  if (profiles.isEmpty) return const Center(child: Text('ยังไม่มีผู้เล่นให้เลือก'));
                  return ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final selected = _selectedUids.contains(profile.id);
                      final displayName = _nameOf(profile.data());
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        title: Text(displayName),
                        subtitle: Text(
                          profile.data()['email']?.toString() ?? profile.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _saving || (!selected && _selectedUids.length >= 49)
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _selectedUids.add(profile.id);
                                  } else {
                                    _selectedUids.remove(profile.id);
                                  }
                                }),
                      );
                    },
                  );
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('ยกเลิก')),
        FilledButton.icon(
          onPressed: _saving ? null : _createGroup,
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.group_add_rounded),
          label: const Text('สร้างกลุ่ม'),
        ),
      ],
    );
  }
}

class _AddGroupMembersDialog extends StatefulWidget {
  const _AddGroupMembersDialog({
    required this.existingUids,
    required this.maxSelectable,
  });

  final Set<String> existingUids;
  final int maxSelectable;

  @override
  State<_AddGroupMembersDialog> createState() => _AddGroupMembersDialogState();
}

/// จัดการการค้นหา/เลือกบัญชีที่จะเพิ่มเข้า group chat.
class _AddGroupMembersDialogState extends State<_AddGroupMembersDialog> {
  final _searchController = TextEditingController();
  final _selectedUids = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
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
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final keyword = _searchController.text.trim().toLowerCase();
    return AlertDialog(
      title: const Text('เพิ่มสมาชิกในกลุ่ม'),
      content: SizedBox(
        width: 380,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'ค้นหาชื่อ อีเมล หรือ UID',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'ล้างคำค้นหา',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'เลือกสมาชิก (${_selectedUids.length}/${widget.maxSelectable})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('users').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('โหลดรายชื่อผู้เล่นไม่สำเร็จ'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final profiles = snapshot.data!.docs.where((profile) {
                    if (profile.id == currentUid ||
                        widget.existingUids.contains(profile.id)) {
                      return false;
                    }
                    if (keyword.isEmpty) return true;
                    final data = profile.data();
                    final searchable = <String>[
                      profile.id,
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
                    return const Center(child: Text('ไม่พบผู้ใช้ที่ค้นหา'));
                  }
                  return ListView.builder(
                    itemCount: profiles.length,
                    itemBuilder: (context, index) {
                      final profile = profiles[index];
                      final selected = _selectedUids.contains(profile.id);
                      final disabled = !selected &&
                          _selectedUids.length >= widget.maxSelectable;
                      final data = profile.data();
                      final email = (data['email'] ?? '').toString();
                      return CheckboxListTile(
                        dense: true,
                        value: selected,
                        title: Text(_nameOf(data)),
                        subtitle: Text(
                          email.isEmpty ? profile.id : email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: disabled
                            ? null
                            : (value) => setState(() {
                                  if (value == true) {
                                    _selectedUids.add(profile.id);
                                  } else {
                                    _selectedUids.remove(profile.id);
                                  }
                                }),
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
          child: const Text('ยกเลิก'),
        ),
        FilledButton.icon(
          onPressed: _selectedUids.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selectedUids.toList()),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('เพิ่มสมาชิก'),
        ),
      ],
    );
  }
}
