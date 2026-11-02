/// หน้าสนทนาระหว่างผู้ใช้สองคน จัดการข้อความ สื่อ ประวัติ และสถานะห้องแชต.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/cloudinary_service.dart';
import '../widgets/inline_video_player.dart';
import '../widgets/media_viewer.dart';
import '../utils/date_time_format.dart';

class PrivateChatScreen extends StatefulWidget {
  final String peerUid;
  final String peerName;

  const PrivateChatScreen({
    super.key,
    required this.peerUid,
    required this.peerName,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

/// ควบคุมห้องส่วนตัว: composer ข้อความ สถานะส่ง/ลบ และ reference ของห้องกับข้อความ.
class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _sending = false;
  bool _clearingHistory = false;

  User? get _user => _auth.currentUser;

  String get _myUid => _user?.uid ?? '';

  String get _chatId {
    final ids = [_myUid, widget.peerUid]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      _firestore.collection('privateChats').doc(_chatId);

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      _chatRef.collection('messages');

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // ส่งข้อความ
  // ============================================================
  /// ตรวจข้อความและสถานะ busy ก่อนส่งผ่านเมธอดเขียนข้อความแบบ transaction/batch.
  Future<void> _sendText() async {
    final text = _textController.text.trim();
    final user = _user;

    if (text.isEmpty || _sending || _clearingHistory) return;

    if (user == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    if (widget.peerUid == user.uid) {
      _showMessage('ไม่สามารถเปิดแชทกับบัญชีตัวเองได้');
      return;
    }

    setState(() => _sending = true);

    try {
      final success = await _writeMessage(
        text: text,
        type: 'text',
      );

      if (success && mounted) {
        _textController.clear();
      }
    } catch (e, stackTrace) {
      debugPrint('Send text error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage('ส่งข้อความไม่สำเร็จ: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  /// ลบข้อความเป็นชุดย่อยจนหมด แล้วปรับ lastMessage ของห้องเพื่อไม่ให้ยังแสดงข้อความเก่า.
  Future<void> _clearChatHistory() async {
    if (_clearingHistory || _sending) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบประวัติแชตส่วนตัว'),
        content: const Text(
          'ข้อความและสื่อทั้งหมดในห้องนี้จะถูกลบสำหรับคุณและอีกฝ่าย และกู้คืนไม่ได้ ต้องการดำเนินการต่อหรือไม่?',
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
      while (true) {
        final page = await _messagesRef.limit(400).get();
        if (page.docs.isEmpty) break;
        final batch = _firestore.batch();
        for (final message in page.docs) {
          batch.delete(message.reference);
        }
        await batch.commit();
      }

      final chat = await _chatRef.get();
      if (chat.exists) {
        await _chatRef.update({
          'lastMessage': 'ล้างประวัติแชตแล้ว',
          'lastSenderUid': _myUid,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) _showMessage('ลบประวัติแชตแล้ว');
    } on FirebaseException catch (error) {
      if (mounted) _showMessage('ลบประวัติไม่สำเร็จ (${error.code})');
    } finally {
      if (mounted) setState(() => _clearingHistory = false);
    }
  }

  // ============================================================
  // บันทึกข้อความลง Firestore
  // ============================================================
  /// เขียนเอกสารห้องและข้อความอย่างสอดคล้อง พร้อมอัปเดต preview และสร้าง notification ให้ผู้รับ.
  Future<bool> _writeMessage({
    required String text,
    required String type,
    String? mediaUrl,
    String? fileName,
  }) async {
    final user = _user;

    if (user == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อน');
      return false;
    }

    try {
      final ids = [user.uid, widget.peerUid]..sort();
      final batch = _firestore.batch();

      batch.set(
        _chatRef,
        {
          'members': ids,
          'memberNames': {
            user.uid: user.displayName ?? user.email ?? 'ผู้ใช้',
            widget.peerUid: widget.peerName,
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'lastMessage': type == 'text'
              ? text
              : type == 'image'
                  ? 'ส่งรูปภาพ'
                  : 'ส่งวิดีโอ',
          'lastSenderUid': user.uid,
          'hiddenBy': <String>[],
        },
        SetOptions(merge: true),
      );

      final messageData = <String, dynamic>{
        'uid': user.uid,
        'name': user.displayName ?? user.email ?? 'ผู้ใช้',
        'text': text,
        'type': type,
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        messageData['mediaUrl'] = mediaUrl;
      }

      if (fileName != null && fileName.isNotEmpty) {
        messageData['fileName'] = fileName;
      }

      batch.set(_messagesRef.doc(), messageData);

      final notificationBody = type == 'text'
          ? text
          : type == 'image'
              ? 'ส่งรูปภาพ'
              : 'ส่งวิดีโอ';
      batch.set(
        _firestore
            .collection('users')
            .doc(widget.peerUid)
            .collection('notifications')
            .doc(),
        {
          'type': 'chat_message',
          'chatId': _chatId,
          'senderUid': user.uid,
          'senderName': user.displayName ?? user.email ?? 'ผู้เล่น',
          'body': notificationBody,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        },
      );

      await batch.commit();

      if (mounted) {
        _scrollToLatest();
      }

      return true;
    } on FirebaseException catch (e) {
      debugPrint('Firestore write error: ${e.code} ${e.message}');

      if (mounted) {
        _showMessage(_friendlyError(e));
      }

      return false;
    } catch (e, stackTrace) {
      debugPrint('Write message error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage('ส่งข้อความไม่สำเร็จ: $e');
      }

      return false;
    }
  }

  // ============================================================
  // เลือกรูปภาพหรือวิดีโอ และอัปโหลดไป Cloudinary
  // ============================================================
  /// เลือกรูป/วิดีโอ อัปโหลด Cloudinary แล้วส่ง URL เป็นข้อความชนิด media.
  Future<void> _pickAndUploadMedia({
    required bool video,
    required ImageSource source,
  }) async {
    final user = _user;

    if (_sending || _clearingHistory) return;

    if (user == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    if (widget.peerUid == user.uid) {
      _showMessage('ไม่สามารถเปิดแชทกับบัญชีตัวเองได้');
      return;
    }

    XFile? pickedFile;

    try {
      debugPrint(
        '[Media] Opening ${video ? 'video' : 'image'} picker...',
      );

      // บน Web ให้เลือกไฟล์จากแกลเลอรี/ไฟล์ในเครื่อง
      pickedFile = video
          ? await _picker.pickVideo(source: source)
          : await _picker.pickImage(
              source: source,
              imageQuality: 85,
            );

      if (!mounted) return;

      if (pickedFile == null) {
        debugPrint('[Media] User cancelled file picker');
        return;
      }

      debugPrint('[Media] Selected file: ${pickedFile.name}');

      setState(() => _sending = true);

      _showMessage(
        'กำลังตรวจสอบไฟล์ ${pickedFile.name}...',
      );

      // ใช้ length() แทนการอ่าน bytes ทั้งไฟล์เพื่อเช็กขนาดก่อน
      final fileSize = await pickedFile.length();

      debugPrint('[Media] File size: $fileSize bytes');

      const maxFileSize = 50 * 1024 * 1024;

      if (fileSize == 0) {
        _showMessage('ไฟล์ว่างเปล่า กรุณาเลือกไฟล์ใหม่');
        return;
      }

      if (fileSize > maxFileSize) {
        _showMessage('ไฟล์ต้องมีขนาดไม่เกิน 50 MB');
        return;
      }

      if (!mounted) return;

      _showMessage(
        'กำลังอัปโหลด${video ? 'วิดีโอ' : 'รูปภาพ'}...',
      );

      // CloudinaryService ต้องรองรับ XFile และ Web
      final String? mediaUrl = await CloudinaryService.uploadMedia(
        pickedFile,
        isVideo: video,
      );

      if (!mounted) return;

      if (mediaUrl == null || mediaUrl.trim().isEmpty) {
        _showMessage(
          'อัปโหลดไม่สำเร็จ กรุณาตรวจสอบ Cloudinary Upload Preset',
        );
        return;
      }

      debugPrint('[Media] Upload success: $mediaUrl');

      final success = await _writeMessage(
        text: '',
        type: video ? 'video' : 'image',
        mediaUrl: mediaUrl,
        fileName: pickedFile.name,
      );

      if (!mounted) return;

      if (success) {
        _showMessage(
          'ส่ง${video ? 'วิดีโอ' : 'รูปภาพ'}สำเร็จ',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[Media] Upload/picker error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage(
          'เลือกหรืออัปโหลดไฟล์ไม่สำเร็จ: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  // ============================================================
  // เมนูเลือกรูปภาพหรือวิดีโอ
  // ============================================================
  Future<void> _showMediaOptions() async {
    if (_sending || _clearingHistory) return;

    final video = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: Color(0xFF6C63FF),
                ),
                title: const Text('เลือกรูปภาพ'),
                subtitle: const Text('เลือกภาพจากเครื่อง'),
                onTap: () {
                  Navigator.pop(sheetContext, false);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.video_library_outlined,
                  color: Color(0xFF6C63FF),
                ),
                title: const Text('เลือกวิดีโอ'),
                subtitle: const Text('เลือกวิดีโอจากเครื่อง'),
                onTap: () {
                  Navigator.pop(sheetContext, true);
                },
              ),
            ],
          ),
        );
      },
    );

    // รอให้ bottom sheet ปิดสนิทก่อนเปิด file picker บนเว็บ
    // เพื่อไม่ให้สอง overlay กำลังเปลี่ยนสถานะพร้อมกัน
    if (video == null || !mounted) return;

    await _pickAndUploadMedia(
      video: video,
      source: ImageSource.gallery,
    );
  }

  // ============================================================
  // ลบข้อความของตัวเอง
  // ============================================================
  /// ลบข้อความที่ผู้ใช้มีสิทธิ์ลบ และอัปเดตข้อมูล preview หากจำเป็น.
  Future<void> _deleteMessage(
    QueryDocumentSnapshot<Map<String, dynamic>> message,
  ) async {
    final user = _user;

    if (user == null) return;

    final data = message.data();

    if (data['uid'] != user.uid) {
      _showMessage('ลบได้เฉพาะข้อความของตัวเอง');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบข้อความ'),
        content: const Text('ต้องการลบข้อความนี้ใช่หรือไม่?'),
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

    if (confirmed != true) return;

    try {
      // ลบเอกสารข้อความใน Firestore เท่านั้น
      // ไฟล์สื่อเดิมบน Cloudinary จะไม่ถูกลบโดยโค้ดนี้
      await message.reference.delete();

      if (mounted) {
        _showMessage('ลบข้อความแล้ว');
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showMessage(_friendlyError(e));
      }
    } catch (e) {
      if (mounted) {
        _showMessage('ลบข้อความไม่สำเร็จ: $e');
      }
    }
  }

  // ============================================================
  // เลื่อนไปยังข้อความล่าสุด
  // ============================================================
  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ============================================================
  // แสดงข้อความแจ้งเตือน
  // ============================================================
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

  // ============================================================
  // แปล Firebase Error
  // ============================================================
  String _friendlyError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'ไม่มีสิทธิ์เข้าถึงข้อมูล กรุณาตรวจสอบ Firestore Rules';

      case 'unauthenticated':
        return 'กรุณาเข้าสู่ระบบก่อน';

      case 'unavailable':
        return 'เชื่อมต่อ Firebase ไม่ได้ กรุณาลองอีกครั้ง';

      case 'quota-exceeded':
        return 'โควตา Firebase ไม่เพียงพอ';

      case 'not-found':
        return 'ไม่พบข้อมูลที่ต้องการ';

      default:
        return 'Firebase error (${e.code}): '
            '${e.message ?? 'ไม่ทราบสาเหตุ'}';
    }
  }

  // ============================================================
  // หน้าจอหลัก
  // ============================================================
  @override
  /// ฟังข้อความเรียลไทม์ เรียงตามเวลา แสดง bubble และ composer สำหรับส่งข้อความ/สื่อ.
  Widget build(BuildContext context) {
    final user = _user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.peerName),
        ),
        body: const Center(
          child: Text('กรุณาเข้าสู่ระบบก่อนใช้งานแชท'),
        ),
      );
    }

    if (widget.peerUid == user.uid) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.peerName),
        ),
        body: const Center(
          child: Text('ไม่สามารถเปิดแชทกับบัญชีตัวเองได้'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF44375F),
              child: Text(
                widget.peerName.isEmpty
                    ? 'ผ'
                    : widget.peerName.characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.peerName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                  const Text('แชตส่วนตัว',
                      style: TextStyle(fontSize: 10, color: Color(0xFF9291A4))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'ลบประวัติแชต',
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
            tooltip: 'ข้อมูลแชต',
            onPressed: () => _showMessage('แชตส่วนตัวกับ ${widget.peerName}'),
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // ------------------------------------------------------
          // รายการข้อความ
          // ------------------------------------------------------
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesRef
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'โหลดข้อความไม่สำเร็จ\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final messages = snapshot.data?.docs ?? [];

                if (messages.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 52,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 12),
                        Text('เริ่มต้นส่งข้อความได้เลย'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data();
                    final timeLabel = formatChatTimeLabel(data['createdAt']);
                    final showDateDivider = index == messages.length - 1 ||
                        !isSameChatDay(
                          data['createdAt'],
                          messages[index + 1].data()['createdAt'],
                        );
                    final dateLabel =
                        formatChatDateDividerLabel(data['createdAt']);

                    final isMe = data['uid'] == user.uid;
                    final type = data['type'] ?? 'text';
                    final text = data['text'] ?? '';
                    final mediaUrl = data['mediaUrl'];

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
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (isMe && timeLabel != null)
                            ChatTimeLabel(label: timeLabel),
                          GestureDetector(
                            onLongPress:
                                isMe ? () => _deleteMessage(message) : null,
                            child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.62,
                          ),
                          margin: const EdgeInsets.symmetric(
                            vertical: 5,
                          ),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF594A8B)
                                : const Color(0xFF242231),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(15),
                              topRight: const Radius.circular(15),
                              bottomLeft: Radius.circular(isMe ? 15 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 15),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: 4,
                                  ),
                                  child: Text(
                                    data['name'] ?? widget.peerName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),

                              // รูปภาพ
                              if (type == 'image' &&
                                  mediaUrl is String &&
                                  mediaUrl.isNotEmpty)
                                GestureDetector(
                                  onTap: () => showChatMediaViewer(
                                    context,
                                    url: mediaUrl,
                                    isVideo: false,
                                  ),
                                  child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    mediaUrl,
                                    width:
                                        MediaQuery.of(context).size.width * 0.54,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (
                                      context,
                                      child,
                                      progress,
                                    ) {
                                      if (progress == null) {
                                        return child;
                                      }

                                      return const SizedBox(
                                        width: 230,
                                        height: 150,
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    },
                                    errorBuilder: (
                                      context,
                                      error,
                                      stackTrace,
                                    ) {
                                      return const SizedBox(
                                        width: 230,
                                        height: 100,
                                        child: Center(
                                          child: Text(
                                            'โหลดรูปภาพไม่สำเร็จ',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                )

                              // วิดีโอ
                              else if (type == 'video' &&
                                  mediaUrl is String && mediaUrl.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: InlineVideoPlayer(
                                    url: mediaUrl,
                                    height: 170,
                                    onOpen: () => showChatMediaViewer(
                                      context,
                                      url: mediaUrl,
                                      isVideo: true,
                                    ),
                                  ),
                                )

                              // แสดงข้อความเฉพาะเมื่อมีข้อความจริง
                              else if (text.toString().trim().isNotEmpty)
                                Text(text.toString()),

                              if (isMe)
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text(
                                    'กดค้างเพื่อลบ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                          ),
                          if (!isMe && timeLabel != null)
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

          // ------------------------------------------------------
          // ช่องพิมพ์ข้อความ
          // ------------------------------------------------------
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _sending ? null : _showMediaOptions,
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'ส่งรูปภาพหรือวิดีโอ',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendText,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send),
                    tooltip: 'ส่งข้อความ',
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
