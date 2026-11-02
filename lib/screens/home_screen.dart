import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/cloudinary_service.dart';
import '../services/notification_service.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/join_request_button.dart';
import '../widgets/post_card.dart';
import 'chat_list_screen.dart';
import 'discover_screen.dart';
import 'notification_screen.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _sentJoinRequestPostIds = <String>{};
  final Set<String> _joiningPostIds = <String>{};

  final CollectionReference<Map<String, dynamic>> _postsRef =
      FirebaseFirestore.instance.collection('posts');

  int _currentPage = 0;
  String _selectedDiscoverGame = 'ทั้งหมด';
  String _homeGameFilter = 'ทั้งหมด';

  static const List<String> _games = [
    'Valorant',
    'ROV',
    'Minecraft',
    'PUBG',
    'Free Fire',
    'Genshin Impact',
    'อื่น ๆ',
  ];

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      NotificationService.bindUser(user.uid);
      _ensureSearchableUserProfile(user);
    }
  }

  Future<void> _ensureSearchableUserProfile(User user) async {
    final authName = user.displayName?.trim() ?? '';
    final fallbackName = authName.isNotEmpty
        ? authName
        : (user.email?.split('@').first ?? 'ผู้เล่น');
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'displayName': fallbackName,
        'email': user.email ?? '',
        'photoURL': user.photoURL ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      debugPrint('Could not sync searchable user profile: ${error.code}');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    NotificationService.unbindUser();
    super.dispose();
  }

  // ==========================================
  // ชื่อผู้ใช้ปัจจุบัน
  // ==========================================

  String get _currentUserName {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return 'ผู้เล่น';

    final name = user.displayName?.trim();

    if (name != null && name.isNotEmpty) {
      return name;
    }

    return user.email?.split('@').first ?? 'ผู้เล่น';
  }

  // ==========================================
  // แสดงข้อความแจ้งเตือน
  // ==========================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.redAccent : Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _friendlyFirebaseError(
    Object error, [
    String fallback = 'เกิดข้อผิดพลาด กรุณาลองใหม่',
  ]) {
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'ไม่มีสิทธิ์ดำเนินการ กรุณาตรวจสอบ Firestore Rules';
        case 'unauthenticated':
          return 'กรุณาเข้าสู่ระบบก่อนดำเนินการ';
        case 'unavailable':
          return 'ไม่สามารถเชื่อมต่อ Firebase ได้ กรุณาลองใหม่';
        case 'deadline-exceeded':
          return 'การเชื่อมต่อใช้เวลานานเกินไป';
        case 'not-found':
          return 'ไม่พบข้อมูลที่ต้องการ';
        case 'resource-exhausted':
          return 'มีการใช้งานเกินกำหนด กรุณาลองใหม่ภายหลัง';
        default:
          return '$fallback (${error.code})';
      }
    }

    return fallback;
  }

  // ==========================================
  // สร้างโพสต์ใหม่
  // ==========================================

  Future<void> _createPost() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage(
        'กรุณาเข้าสู่ระบบก่อนสร้างโพสต์',
        isError: true,
      );
      return;
    }

    final posted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreatePostDialog(
        games: _games,
        onSubmit: (game, title, detail, media, isVideo, maxPlayers,
            isRecruiting) async {
          try {
            String? mediaUrl;

            if (media != null) {
              mediaUrl = await CloudinaryService.uploadMedia(
                media,
                isVideo: isVideo,
              );
              if (mediaUrl == null || mediaUrl.isEmpty) {
                throw Exception('บริการอัปโหลดไม่ส่งลิงก์สื่อกลับมา');
              }
            }

            await _postsRef.add({
              'uid': user.uid,
              'userName': _currentUserName,
              'game': game,
              'title': title,
              'detail': detail,
              'imageUrl': isVideo ? '' : (mediaUrl ?? ''),
              'mediaUrl': mediaUrl ?? '',
              'mediaType': media == null ? '' : (isVideo ? 'video' : 'image'),
              'createdAt': FieldValue.serverTimestamp(),
              'likes': 0,
              'dislikes': 0,
              'likedBy': <String>[],
              'dislikedBy': <String>[],
              'reactions': <String, dynamic>{},
              'reactionUsers': <String, dynamic>{},
              'reactionByUid': <String, String>{},
              'commentCount': 0,
              'memberCount': 1,
              'memberUids': <String>[user.uid],
              'maxPlayers': maxPlayers,
              'isRecruiting': isRecruiting,
              'joinStatus': isRecruiting ? 'open' : 'closed',
              'joinRequestUids': <String>[],
            });
          } catch (error) {
            final message = error is FirebaseException
                ? _friendlyFirebaseError(error, 'สร้างโพสต์ไม่สำเร็จ')
                : error.toString().replaceFirst('Exception: ', '');
            throw Exception(message);
          }
        },
      ),
    );

    if (posted == true && mounted) {
      _showMessage('สร้างโพสต์สำเร็จ');
    }
  }

  // ==========================================
  // กดถูกใจ
  // ==========================================

  Future<void> _toggleLike(DocumentSnapshot<Map<String, dynamic>> doc) =>
      _setPostReaction(doc, 'like');

  Future<void> _toggleDislike(DocumentSnapshot<Map<String, dynamic>> doc) =>
      _setPostReaction(doc, 'dislike');

  Future<void> _addReaction(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String emoji,
  ) =>
      _setPostReaction(doc, emoji);

  Future<void> _setPostReaction(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String requestedReaction,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อน', isError: true);
      return;
    }

    const emojis = ['❤️', '😂', '😮', '😢', '😡', '🔥', '🎮', '👏'];
    if (requestedReaction != 'like' &&
        requestedReaction != 'dislike' &&
        !emojis.contains(requestedReaction)) {
      return;
    }

    final postData = doc.data() ?? <String, dynamic>{};
    final ownerUid = (postData['uid'] ?? '').toString();
    final voteRef = doc.reference.collection('reactions').doc(user.uid);
    final eventId =
        FirebaseFirestore.instance.collection('_reactionEventIds').doc().id;
    final notificationRef = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('notifications')
        .doc('post_reaction_${doc.id}_${user.uid}_$eventId');
    var savedReaction = '';

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final voteSnapshot = await transaction.get(voteRef);
        String currentReaction;
        if (voteSnapshot.exists) {
          currentReaction = (voteSnapshot.data()?['reaction'] ?? '').toString();
        } else {
          final legacyMap = postData['reactionByUid'];
          final legacyLiked = List<String>.from(
            postData['likedBy'] ?? <String>[],
          );
          final legacyDisliked = List<String>.from(
            postData['dislikedBy'] ?? <String>[],
          );
          final legacyEmojiUsers = Map<String, dynamic>.from(
            postData['reactionUsers'] ?? <String, dynamic>{},
          );
          currentReaction = legacyMap is Map && legacyMap.containsKey(user.uid)
              ? (legacyMap[user.uid] ?? '').toString()
              : legacyLiked.contains(user.uid)
                  ? 'like'
                  : legacyDisliked.contains(user.uid)
                      ? 'dislike'
                      : emojis.firstWhere(
                          (emoji) => List<String>.from(
                            legacyEmojiUsers[emoji] ?? <String>[],
                          ).contains(user.uid),
                          orElse: () => '',
                        );
        }
        final nextReaction =
            currentReaction == requestedReaction ? '' : requestedReaction;
        savedReaction = nextReaction;

        transaction.set(voteRef, {
          'uid': user.uid,
          'reaction': nextReaction,
          'eventId': eventId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (savedReaction.isNotEmpty &&
          savedReaction != 'dislike' &&
          ownerUid.isNotEmpty &&
          ownerUid != user.uid) {
        final rawTitle = postData['title'];
        final postTitle = rawTitle is String && rawTitle.isNotEmpty
            ? rawTitle
            : 'โพสต์ของคุณ';
        final reactionText = savedReaction == 'like'
            ? 'กดถูกใจ'
            : 'แสดงความรู้สึก $savedReaction';
        try {
          await notificationRef.set({
            'type': 'post_like',
            'postId': doc.id,
            'postTitle': postTitle,
            'reaction': savedReaction,
            'eventId': eventId,
            'senderUid': user.uid,
            'senderName': _currentUserName,
            'body': '$reactionText โพสต์ “$postTitle”',
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        } on FirebaseException catch (error) {
          debugPrint('Could not notify post owner: ${error.code}');
        }
      }
    } catch (error) {
      _showMessage(
        _friendlyFirebaseError(error, 'บันทึกการตอบสนองไม่สำเร็จ'),
        isError: true,
      );
    }
  }

  Future<void> _showReactionPicker(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    const emojis = ['❤️', '😂', '😮', '😢', '😡', '🔥', '🎮', '👏'];

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: emojis.map((emoji) {
                return InkWell(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _addReaction(doc, emoji);
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 30),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // คอมเมนต์
  // ==========================================

  Future<void> _showComments(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final commentController = TextEditingController();
    final commentFocusNode = FocusNode();

    void submitComment() {
      commentFocusNode.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      _addComment(doc, commentController);
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        // The comments list handles vertical scrolling. Letting the modal
        // route also consume downward drags can tear down its inherited
        // dependencies while the list is rebuilding on Flutter Web.
        enableDrag: false,
        builder: (sheetContext) {
          return SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.78,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'ความคิดเห็น',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: doc.reference
                        .collection('comments')
                        .orderBy('createdAt', descending: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('โหลดความคิดเห็นไม่สำเร็จ'),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final comments = snapshot.data?.docs ?? [];

                      return ListView.builder(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: comments.isEmpty ? 1 : comments.length,
                        itemBuilder: (context, index) {
                          if (comments.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: Center(child: Text('ยังไม่มีความคิดเห็น')),
                            );
                          }
                          final comment = comments[index].data();

                          final currentUser = FirebaseAuth.instance.currentUser;
                          final canDelete = currentUser != null &&
                              ((comment['uid'] ?? comment['userId']) ==
                                      currentUser.uid ||
                                  doc.data()?['uid'] == currentUser.uid);

                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.person),
                            ),
                            title: Text(
                              comment['userName']?.toString() ?? 'ผู้เล่น',
                            ),
                            subtitle: Text(
                              comment['text']?.toString() ?? '',
                            ),
                            trailing: canDelete
                                ? IconButton(
                                    tooltip: 'ลบความคิดเห็น',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteComment(
                                      doc,
                                      comments[index],
                                    ),
                                  )
                                : null,
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 8,
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 8,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'ใส่อีโมจิ',
                        onPressed: () async {
                          const emojis = [
                            '😀',
                            '😂',
                            '🥰',
                            '😍',
                            '😎',
                            '😭',
                            '😡',
                            '😮',
                            '❤️',
                            '👍',
                            '👏',
                            '🔥',
                            '🎮',
                            '✨',
                            '🙏',
                            '💯',
                          ];
                          final emoji = await showModalBottomSheet<String>(
                            context: sheetContext,
                            builder: (pickerContext) => SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: emojis
                                      .map((emoji) => InkWell(
                                            onTap: () => Navigator.pop(
                                                pickerContext, emoji),
                                            child: Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: Text(emoji,
                                                  style: const TextStyle(
                                                      fontSize: 28)),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ),
                            ),
                          );
                          if (emoji == null) return;
                          final value = commentController.value;
                          final start = value.selection.isValid
                              ? value.selection.start
                              : value.text.length;
                          final end = value.selection.isValid
                              ? value.selection.end
                              : value.text.length;
                          final text =
                              value.text.replaceRange(start, end, emoji);
                          commentController.value = TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                                offset: start + emoji.length),
                          );
                        },
                        icon: const Icon(Icons.emoji_emotions_outlined),
                      ),
                      Expanded(
                        child: TextField(
                          controller: commentController,
                          focusNode: commentFocusNode,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => submitComment(),
                          decoration: const InputDecoration(
                            hintText: 'เขียนความคิดเห็น...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: submitComment,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      commentController.dispose();
      commentFocusNode.dispose();
    }
  }

  Future<void> _addComment(
    DocumentSnapshot<Map<String, dynamic>> doc,
    TextEditingController controller,
  ) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final user = FirebaseAuth.instance.currentUser;
    final text = controller.text.trim();

    if (user == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อน', isError: true);
      return;
    }

    if (text.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final commentRef = doc.reference.collection('comments').doc();

      batch.set(commentRef, {
        'uid': user.uid,
        'userName': _currentUserName,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.update(doc.reference, {
        'commentCount': FieldValue.increment(1),
      });

      await batch.commit();

      final postData = doc.data() ?? <String, dynamic>{};
      final postOwnerUid = (postData['uid'] ?? '').toString();
      if (postOwnerUid.isNotEmpty && postOwnerUid != user.uid) {
        final rawTitle = postData['title'];
        final postTitle = rawTitle is String && rawTitle.trim().isNotEmpty
            ? rawTitle.trim()
            : 'โพสต์ของคุณ';
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(postOwnerUid)
              .collection('notifications')
              .doc('post_comment_${doc.id}_${commentRef.id}')
              .set({
            'type': 'post_comment',
            'postId': doc.id,
            'commentId': commentRef.id,
            'postTitle': postTitle,
            'senderUid': user.uid,
            'senderName': _currentUserName,
            'body': text,
            'createdAt': FieldValue.serverTimestamp(),
            'isRead': false,
          });
        } on FirebaseException catch (error) {
          debugPrint('Could not notify post owner about comment: ${error.code}');
        }
      }

      if (mounted) controller.clear();
    } catch (error) {
      _showMessage(
        _friendlyFirebaseError(error, 'ส่งความคิดเห็นไม่สำเร็จ'),
        isError: true,
      );
    }
  }

  Future<void> _deleteComment(
    DocumentSnapshot<Map<String, dynamic>> post,
    QueryDocumentSnapshot<Map<String, dynamic>> comment,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final postOwner = post.data()?['uid']?.toString();
    final commentData = comment.data();
    final commentOwner =
        (commentData['uid'] ?? commentData['userId'])?.toString();
    if (user == null || (user.uid != postOwner && user.uid != commentOwner)) {
      _showMessage('คุณไม่มีสิทธิ์ลบความคิดเห็นนี้', isError: true);
      return;
    }

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(comment.reference);
      batch.update(post.reference, {
        'commentCount': FieldValue.increment(-1),
        'lastCommentDeletion': comment.id,
      });
      await batch.commit();
    } catch (error) {
      _showMessage(
        _friendlyFirebaseError(error, 'ลบความคิดเห็นไม่สำเร็จ'),
        isError: true,
      );
    }
  }

  // ==========================================
  // แก้ไขโพสต์
  // ==========================================

  Future<void> _editPost(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();

    if (data == null) return;

    final titleController = TextEditingController(
      text: data['title']?.toString() ?? '',
    );
    final detailController = TextEditingController(
      text: data['detail']?.toString() ?? '',
    );

    String selectedGame =
        _games.contains(data['game']) ? data['game'] as String : _games.first;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('แก้ไขโพสต์'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedGame,
                        decoration: const InputDecoration(
                          labelText: 'เกม',
                        ),
                        items: _games.map((game) {
                          return DropdownMenuItem<String>(
                            value: game,
                            child: Text(game),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedGame = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'หัวข้อ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: detailController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'รายละเอียด',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('ยกเลิก'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      final title = titleController.text.trim();

                      if (title.isEmpty) {
                        _showMessage(
                          'กรุณากรอกหัวข้อโพสต์',
                          isError: true,
                        );
                        return;
                      }

                      try {
                        await doc.reference.update({
                          'game': selectedGame,
                          'title': title,
                          'detail': detailController.text.trim(),
                          'updatedAt': FieldValue.serverTimestamp(),
                        });

                        if (!mounted || !dialogContext.mounted) return;

                        Navigator.of(dialogContext).pop();
                        _showMessage('แก้ไขโพสต์สำเร็จ');
                      } catch (error) {
                        if (mounted) {
                          _showMessage(
                            _friendlyFirebaseError(
                              error,
                              'แก้ไขโพสต์ไม่สำเร็จ',
                            ),
                            isError: true,
                          );
                        }
                      }
                    },
                    child: const Text('บันทึก'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      detailController.dispose();
    }
  }

  // ==========================================
  // ลบโพสต์
  // ==========================================

  Future<void> _deletePost(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('ลบโพสต์'),
          content: const Text('คุณต้องการลบโพสต์นี้ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('ลบโพสต์'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    try {
      await doc.reference.delete();

      if (!mounted) return;

      _showMessage('ลบโพสต์สำเร็จ');
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        _friendlyFirebaseError(error, 'ลบโพสต์ไม่สำเร็จ'),
        isError: true,
      );
    }
  }

  // ==========================================
  // รายงานโพสต์
  // ==========================================

  Future<void> _reportPost(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อน', isError: true);
      return;
    }

    const reasons = [
      'เนื้อหาไม่เหมาะสม',
      'สแปมหรือโฆษณา',
      'ใช้ถ้อยคำไม่สุภาพ',
      'เหตุผลอื่น ๆ',
    ];

    String selectedReason = reasons.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('รายงานโพสต์'),
              content: DropdownButtonFormField<String>(
                initialValue: selectedReason,
                decoration: const InputDecoration(
                  labelText: 'เลือกเหตุผล',
                ),
                items: reasons.map((reason) {
                  return DropdownMenuItem<String>(
                    value: reason,
                    child: Text(reason),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      selectedReason = value;
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('ส่งรายงาน'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || confirmed != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final postOwnerUid = (doc.data()?['uid'] ?? '').toString();
      if (postOwnerUid.isEmpty || postOwnerUid == user.uid) {
        _showMessage('ไม่สามารถรายงานโพสต์ของตัวเองได้', isError: true);
        return;
      }
      final reportRef = db.collection('reports').doc('${doc.id}_${user.uid}');
      final notificationRef = db
          .collection('users')
          .doc(postOwnerUid)
          .collection('notifications')
          .doc();

      await db.runTransaction((transaction) async {
        final existingReport = await transaction.get(reportRef);
        if (existingReport.exists) {
          throw StateError('คุณได้ทำการรายงานโพสต์นี้แล้ว');
        }
        final currentPost = await transaction.get(doc.reference);
        if (!currentPost.exists) throw StateError('ไม่พบโพสต์นี้แล้ว');
        final postData = currentPost.data() ?? <String, dynamic>{};
        if (postData['uid'] != postOwnerUid) {
          throw StateError('โพสต์นี้มีการเปลี่ยนแปลง กรุณาลองใหม่');
        }

        transaction.set(reportRef, {
          'postId': doc.id,
          'postOwnerUid': postOwnerUid,
          'postOwnerName': (postData['userName'] ?? postData['displayName'] ?? 'ผู้เล่น').toString(),
          'postText': (postData['text'] ?? postData['description'] ?? '').toString(),
          'reporterName': user.displayName ?? 'ผู้เล่น',
          'reporterUid': user.uid,
          'reason': selectedReason,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
        transaction.set(notificationRef, {
          'type': 'post_report',
          'postId': doc.id,
          'postTitle': (postData['title'] ?? 'โพสต์ของคุณ').toString(),
          'body': 'โพสต์ของคุณมีการถูกรายงาน ทีมงานจะตรวจสอบ',
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      });

      if (!mounted) return;

      _showMessage('คุณได้ทำการรายงานโพสต์นี้แล้ว');
    } on StateError catch (error) {
      if (mounted) _showMessage(error.message, isError: true);
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        _friendlyFirebaseError(error, 'ส่งรายงานไม่สำเร็จ'),
        isError: true,
      );
    }
  }

  // ==========================================
  // เมนูของโพสต์
  // ==========================================

  Future<void> _showPostMenu(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final data = doc.data();

    if (data == null) return;

    final isOwner = user != null && data['uid'] == user.uid;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOwner) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('แก้ไขโพสต์'),
                  onTap: () {
                    Navigator.of(sheetContext).pop('edit');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  title: const Text('ลบโพสต์'),
                  onTap: () {
                    Navigator.of(sheetContext).pop('delete');
                  },
                ),
              ] else
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('รายงานโพสต์'),
                  onTap: () {
                    Navigator.of(sheetContext).pop('report');
                  },
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'edit':
        await _editPost(doc);
        break;
      case 'delete':
        await _deletePost(doc);
        break;
      case 'report':
        await _reportPost(doc);
        break;
    }
  }

  // ==========================================
  // การ์ดโพสต์
  // ==========================================

  Widget _buildPostCard(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: doc.reference.collection('reactions').snapshots(),
      builder: (context, snapshot) {
        final data = _mergeReactionData(
          doc.data() ?? <String, dynamic>{},
          snapshot.data?.docs ?? const [],
        );
        return PostCard(
          doc: doc,
          dataOverride: data,
          onMenu: () => _showPostMenu(doc),
          onLike: () => _toggleLike(doc),
          onDislike: () => _toggleDislike(doc),
          onComments: () => _showComments(doc),
          onReaction: () => _showReactionPicker(doc),
          onJoin: () => _requestJoin(doc),
          requestSentOverride: _sentJoinRequestPostIds.contains(doc.id) ||
              _joiningPostIds.contains(doc.id),
        );
      },
    );
  }

  Map<String, dynamic> _mergeReactionData(
    Map<String, dynamic> postData,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> voteDocs,
  ) {
    const emojis = ['❤️', '😂', '😮', '😢', '😡', '🔥', '🎮', '👏'];
    final data = Map<String, dynamic>.from(postData);
    final legacyVotes = <String, String>{};
    final savedVotes = postData['reactionByUid'];
    if (savedVotes is Map) {
      for (final entry in savedVotes.entries) {
        if (entry.key is String) {
          legacyVotes[entry.key as String] = (entry.value ?? '').toString();
        }
      }
    }
    for (final uid in List<String>.from(postData['likedBy'] ?? <String>[])) {
      legacyVotes.putIfAbsent(uid, () => 'like');
    }
    for (final uid in List<String>.from(postData['dislikedBy'] ?? <String>[])) {
      legacyVotes.putIfAbsent(uid, () => 'dislike');
    }
    final oldEmojiUsers = postData['reactionUsers'];
    if (oldEmojiUsers is Map) {
      for (final emoji in emojis) {
        for (final uid
            in List<String>.from(oldEmojiUsers[emoji] ?? <String>[])) {
          legacyVotes.putIfAbsent(uid, () => emoji);
        }
      }
    }

    final votes = Map<String, String>.from(legacyVotes);
    final reactions = Map<String, dynamic>.from(postData['reactions'] ?? {});
    int likes = postData['likes'] is num
        ? (postData['likes'] as num).toInt()
        : legacyVotes.values.where((value) => value == 'like').length;
    int dislikes = postData['dislikes'] is num
        ? (postData['dislikes'] as num).toInt()
        : legacyVotes.values.where((value) => value == 'dislike').length;
    for (final emoji in emojis) {
      reactions.putIfAbsent(
        emoji,
        () => legacyVotes.values.where((value) => value == emoji).length,
      );
    }

    void applyDelta(String reaction, int delta) {
      if (reaction == 'like') likes += delta;
      if (reaction == 'dislike') dislikes += delta;
      if (emojis.contains(reaction)) {
        final oldCount = reactions[reaction];
        reactions[reaction] = (oldCount is num ? oldCount.toInt() : 0) + delta;
      }
    }

    for (final voteDoc in voteDocs) {
      final nextReaction = (voteDoc.data()['reaction'] ?? '').toString();
      final previousReaction = legacyVotes[voteDoc.id] ?? '';
      applyDelta(previousReaction, -1);
      applyDelta(nextReaction, 1);
      votes[voteDoc.id] = nextReaction;
    }

    final likedBy = <String>[];
    final dislikedBy = <String>[];
    final reactionUsers = <String, dynamic>{
      for (final emoji in emojis) emoji: <String>[],
    };
    for (final entry in votes.entries) {
      if (entry.value == 'like') likedBy.add(entry.key);
      if (entry.value == 'dislike') dislikedBy.add(entry.key);
      if (emojis.contains(entry.value)) {
        (reactionUsers[entry.value] as List<String>).add(entry.key);
      }
    }

    data['reactionByUid'] = votes;
    data['likedBy'] = likedBy;
    data['dislikedBy'] = dislikedBy;
    data['reactionUsers'] = reactionUsers;
    data['likes'] = likes;
    data['dislikes'] = dislikes;
    data['reactions'] = reactions;
    return data;
  }

  Future<void> _requestJoin(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    final post = doc.data() ?? <String, dynamic>{};
    final ownerUid = (post['uid'] ?? '').toString();
    if (user == null) {
      _showMessage('กรุณาเข้าสู่ระบบก่อนส่งคำขอ', isError: true);
      return;
    }
    if (ownerUid.isEmpty || ownerUid == user.uid) return;
    if (_joiningPostIds.contains(doc.id) ||
        _sentJoinRequestPostIds.contains(doc.id)) {
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
      _showMessage('โพสต์นี้ปิดรับสมาชิกแล้ว');
      return;
    }
    if (post['joinStatus'] == 'full' ||
        (maxPlayers != null && memberCount >= maxPlayers)) {
      _showMessage('ทีมนี้เต็มแล้ว');
      return;
    }

    final requestRef = FirebaseFirestore.instance
        .collection('users')
        .doc(ownerUid)
        .collection('joinRequests')
        .doc('${doc.id}_${user.uid}');
    setState(() => _joiningPostIds.add(doc.id));
    try {
      await requestRef.set({
        'postId': doc.id,
        'postTitle': (post['title'] ?? 'กำลังหาเพื่อนเล่น').toString(),
        'game': (post['game'] ?? 'เกม').toString(),
        'ownerUid': ownerUid,
        'senderUid': user.uid,
        'senderName': _currentUserName,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      JoinRequestButton.markPending(user.uid, doc.id);
      if (!mounted) return;
      setState(() {
        _joiningPostIds.remove(doc.id);
        _sentJoinRequestPostIds.add(doc.id);
      });

      // Notifications are separate so their rules cannot roll back the request.
      var notificationSent = true;
      try {
        await doc.reference.update({
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
            .doc('join_request_${requestRef.id}')
            .set({
          'type': 'join_request_received',
          'postId': doc.id,
          'joinRequestId': requestRef.id,
          'senderUid': user.uid,
          'senderName': _currentUserName,
          'body':
              '$_currentUserName ขอเข้าร่วมทีม "${post['title'] ?? 'ทีมของคุณ'}"',
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      } on FirebaseException catch (error) {
        debugPrint('Could not create join request notification: ${error.code}');
        notificationSent = false;
      }
      if (!mounted) return;
      _showMessage(notificationSent
          ? 'ส่งคำขอเข้าร่วมแล้ว'
          : 'ส่งคำขอแล้ว แต่แจ้งเตือนติดสิทธิ์ Firebase กรุณา Publish firestore.rules ล่าสุด');
    } catch (error) {
      if (!mounted) return;
      setState(() => _joiningPostIds.remove(doc.id));
      final message = error is FirebaseException &&
              error.code == 'permission-denied'
          ? 'ส่งคำขอไม่ได้: Firestore Rules ของ game-party-202 ยังไม่อนุญาตให้สร้างคำขอเข้าร่วม'
          : 'ส่งคำขอไม่สำเร็จ: $error';
      _showMessage(message, isError: true);
    }
  }

  // ==========================================
  // หน้าฟีดว่าง
  // ==========================================

  Widget _buildEmptyFeed() {
    final searching = _searchController.text.trim().isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching ? Icons.search_off : Icons.sports_esports,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'ไม่พบโพสต์ที่ค้นหา' : 'ยังไม่มีโพสต์หาตี้เกม',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'ลองเปลี่ยนคำค้นหา'
                  : 'กดปุ่ม + เพื่อสร้างโพสต์แรกของคุณ',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // เปิดหน้าแชตรวม
  // ==========================================

  void _onNavigate(int index) {
    setState(() => _currentPage = index);
  }

  void _openGameSearch(String game) {
    setState(() {
      _selectedDiscoverGame = game;
      _currentPage = 1;
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotificationScreen(),
      ),
    );
  }

  // ==========================================
  // หน้าจอหลัก
  // ==========================================

  @override
  Widget build(BuildContext context) {
    if (_currentPage == 1) {
      return DiscoverScreen(
        initialGame: _selectedDiscoverGame,
        onNavigate: _onNavigate,
      );
    }

    if (_currentPage == 2) {
      return ChatListScreen(
        onBack: () => _onNavigate(0),
        onNavigate: _onNavigate,
      );
    }

    if (_currentPage == 3) {
      return ProfileScreen(
        onBack: () => _onNavigate(0),
        onNavigate: _onNavigate,
      );
    }

    // หน้าฟีดหลัก
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: const LinearGradient(
                  colors: [Color(0xFFAD8DFF), Color(0xFF7048EF)],
                ),
              ),
              child: const Icon(Icons.sports_esports_rounded, size: 21),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('GAME PARTY',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: .3)),
                Text('หาเพื่อน • เล่นด้วยกัน • สนุกกว่าเดิม',
                    style: TextStyle(fontSize: 10, color: Color(0xFF9291A4))),
              ],
            ),
          ],
        ),
        actions: [
          if (FirebaseAuth.instance.currentUser != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('admins')
                  .doc(FirebaseAuth.instance.currentUser!.uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.data?.exists != true) return const SizedBox.shrink();
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance.collection('reports').snapshots(),
                  builder: (context, reportsSnapshot) {
                    final pending = reportsSnapshot.data?.docs
                            .where((report) => report.data()['status'] == 'pending')
                            .length ??
                        0;
                    return IconButton(
                      tooltip: 'จัดการระบบ${pending > 0 ? ' ($pending รายงานรอตรวจสอบ)' : ''}',
                      icon: Badge(
                        isLabelVisible: pending > 0,
                        label: Text(pending > 99 ? '99+' : '$pending'),
                        child: const Icon(Icons.admin_panel_settings_outlined),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => const AdminScreen()),
                      ),
                    );
                  },
                );
              },
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseAuth.instance.currentUser == null
                ? null
                : FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .collection('notifications')
                    .where('isRead', isEqualTo: false)
                    .snapshots(),
            builder: (context, snapshot) {
              final unread = snapshot.data?.docs.length ?? 0;
              return IconButton(
                tooltip: 'การแจ้งเตือน${unread > 0 ? ' ($unread ใหม่)' : ''}',
                onPressed: _openNotifications,
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 5, 18, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ยินดีต้อนรับกลับมา $_currentUserName',
                        style: const TextStyle(
                            color: Color(0xFFAAA7B7), fontSize: 12)),
                    const SizedBox(height: 1),
                    const Text('พร้อมลงสนามหรือยัง? ✦',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'ค้นหาเกม ชื่อ หรือโพสต์...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'ล้างคำค้นหา',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 5, 18, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('เลือกเกมที่ชอบ',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(
                    onPressed: () => _onNavigate(1),
                    child: const Text('ดูทั้งหมด  ›',
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 82,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                children: [
                  _gameShortcut('⚡', 'Valorant'),
                  _gameShortcut('🛡️', 'ROV'),
                  _gameShortcut('⛏️', 'Minecraft'),
                  _gameShortcut('🎯', 'PUBG'),
                  _gameShortcut('🔥', 'Free Fire'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
              child: Row(
                children: [
                  const Expanded(
                      child: Text('โพสต์หาเพื่อนเล่น',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600))),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _homeGameFilter = 'ทั้งหมด'),
                    icon: const Icon(Icons.schedule_rounded, size: 14),
                    label: const Text('ล่าสุด', style: TextStyle(fontSize: 10)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 38,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                children: ['ทั้งหมด', ..._games.take(4)].map((game) {
                  final selected = _homeGameFilter == game;
                  return Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      label: Text(game, style: const TextStyle(fontSize: 10)),
                      selected: selected,
                      onSelected: (_) => setState(() => _homeGameFilter = game),
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                      selectedColor: const Color(0xFFA184FF),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 4),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  _postsRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'โหลดโพสต์ไม่สำเร็จ\n${snapshot.error}',
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

                final posts = snapshot.data?.docs ?? [];
                final keyword = _searchController.text.trim().toLowerCase();

                final filteredPosts = posts.where((doc) {
                  final data = doc.data();

                  if (_homeGameFilter != 'ทั้งหมด' &&
                      (data['game'] ?? '').toString().toLowerCase() !=
                          _homeGameFilter.toLowerCase()) {
                    return false;
                  }

                  if (keyword.isEmpty) return true;

                  final game = (data['game'] ?? '').toString().toLowerCase();
                  final title = (data['title'] ?? '').toString().toLowerCase();
                  final detail =
                      (data['detail'] ?? '').toString().toLowerCase();
                  final userName =
                      (data['userName'] ?? '').toString().toLowerCase();

                  return game.contains(keyword) ||
                      title.contains(keyword) ||
                      detail.contains(keyword) ||
                      userName.contains(keyword);
                }).toList();

                if (filteredPosts.isEmpty) {
                  return _buildEmptyFeed();
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 12,
                    top: 4,
                    bottom: 90,
                  ),
                  itemCount: filteredPosts.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildPostCard(filteredPosts[index]),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'สร้างโพสต์หาเพื่อน',
        onPressed: _createPost,
        backgroundColor: const Color(0xFF9272F7),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add_rounded, size: 27),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: 0,
        onTap: _onNavigate,
      ),
    );
  }

  Widget _gameShortcut(String emoji, String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(15),
      onTap: () => _openGameSearch(label),
      child: Container(
        width: 78,
        margin: const EdgeInsets.only(right: 9),
        decoration: BoxDecoration(
          color: const Color(0xFF171621),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xFF2A2938)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 23)),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatePostDialog extends StatefulWidget {
  const _CreatePostDialog({
    required this.games,
    required this.onSubmit,
  });

  final List<String> games;
  final Future<void> Function(
    String game,
    String title,
    String detail,
    XFile? media,
    bool isVideo,
    int? maxPlayers,
    bool isRecruiting,
  ) onSubmit;

  @override
  State<_CreatePostDialog> createState() => _CreatePostDialogState();
}

class _CreatePostDialogState extends State<_CreatePostDialog> {
  final _titleController = TextEditingController();
  final _detailController = TextEditingController();
  final _picker = ImagePicker();

  String? _selectedGame;
  XFile? _selectedMedia;
  bool _selectedIsVideo = false;
  int _maxPlayers = 5;
  bool _isRecruiting = true;
  Uint8List? _mediaBytes;
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedGame = widget.games.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _detailController.dispose();
    super.dispose();
  }

  Future<void> _chooseMedia({required bool video}) async {
    try {
      final media = video
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 80,
            );
      if (media == null || !mounted) return;

      final bytes = video ? null : await media.readAsBytes();
      if (!mounted) return;
      if (!video && (bytes == null || bytes.isEmpty)) {
        setState(() => _errorMessage = 'ไฟล์รูปภาพไม่มีข้อมูล');
        return;
      }

      setState(() {
        _selectedMedia = media;
        _selectedIsVideo = video;
        _mediaBytes = bytes;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'เลือก${video ? 'วิดีโอ' : 'รูปภาพ'}ไม่สำเร็จ: '
            '${error.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกหัวข้อโพสต์');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onSubmit(
        _selectedGame!,
        title,
        _detailController.text.trim(),
        _selectedMedia,
        _selectedIsVideo,
        _maxPlayers == 0 ? null : _maxPlayers,
        _isRecruiting,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
      return;
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('สร้างโพสต์หาตี้เกม'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedGame,
              decoration: const InputDecoration(labelText: 'เลือกเกม'),
              items: widget.games
                  .map((game) => DropdownMenuItem(
                        value: game,
                        child: Text(game),
                      ))
                  .toList(),
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedGame = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleController,
              enabled: !_isSubmitting,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'หัวข้อโพสต์',
                hintText: 'เช่น หาเพื่อนเล่นแรงก์',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailController,
              enabled: !_isSubmitting,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'รายละเอียด',
                hintText: 'ระบุเวลาที่จะเล่นหรือจำนวนคนที่ต้องการ',
              ),
            ),
            if (_mediaBytes != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _mediaBytes!,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _maxPlayers,
              decoration: const InputDecoration(
                labelText: 'จำนวนสมาชิกสูงสุด (รวมผู้สร้าง)',
              ),
              items: [2, 3, 4, 5, 6, 8, 10, 0]
                  .map((value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text(value == 0 ? 'ไม่จำกัด' : '$value คน'),
                      ))
                  .toList(),
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      if (value != null) setState(() => _maxPlayers = value);
                    },
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isRecruiting,
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() => _isRecruiting = value),
              title: const Text('เปิดรับคำขอเข้าร่วม'),
              subtitle:
                  Text(_isRecruiting ? 'ผู้เล่นส่งคำขอได้' : 'ปิดรับสมาชิก'),
            ),
            const SizedBox(height: 8),
            if (_selectedIsVideo && _selectedMedia != null)
              Container(
                height: 110,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF252332),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.video_file_outlined,
                    size: 42, color: Color(0xFFB69EFF)),
              ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _isSubmitting ? null : () => _chooseMedia(video: false),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('รูปภาพ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _isSubmitting ? null : () => _chooseMedia(video: true),
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('วิดีโอ'),
                ),
              ),
            ]),
            if (_selectedMedia != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'เลือกแล้ว · ${_selectedMedia!.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFFAAA7B7)),
                ),
              ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFFFF8C9A), fontSize: 12),
              ),
            ],
            if (_isSubmitting) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                'กำลังอัปโหลดสื่อและสร้างโพสต์...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('โพสต์'),
        ),
      ],
    );
  }
}
