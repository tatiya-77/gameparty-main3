import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/profile_screen.dart';
import '../utils/date_time_format.dart';
import 'inline_video_player.dart';
import 'join_request_button.dart';

class PostCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onMenu;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onComments;
  final VoidCallback onReaction;
  final VoidCallback onJoin;
  final bool requestSentOverride;
  final Map<String, dynamic>? dataOverride;

  const PostCard({
    super.key,
    required this.doc,
    required this.onMenu,
    required this.onLike,
    required this.onDislike,
    required this.onComments,
    required this.onReaction,
    required this.onJoin,
    this.requestSentOverride = false,
    this.dataOverride,
  });

  @override
  Widget build(BuildContext context) {
    final data = dataOverride ?? doc.data() ?? {};
    final user = FirebaseAuth.instance.currentUser;

    final likedBy = List<dynamic>.from(data['likedBy'] ?? []);
    final dislikedBy = List<dynamic>.from(data['dislikedBy'] ?? []);

    final isLiked = user != null && likedBy.contains(user.uid);
    final isDisliked = user != null && dislikedBy.contains(user.uid);
    final reactionByUid = Map<String, dynamic>.from(
      data['reactionByUid'] ?? const <String, dynamic>{},
    );
    final reactionUsers = Map<String, dynamic>.from(
      data['reactionUsers'] ?? const <String, dynamic>{},
    );
    const emojiChoices = ['❤️', '😂', '😮', '😢', '😡', '🔥', '🎮', '👏'];
    final selectedEmoji = user == null
        ? ''
        : emojiChoices.firstWhere(
            (emoji) => List<dynamic>.from(
              reactionUsers[emoji] ?? const [],
            ).contains(user.uid),
            orElse: () => '',
          );
    final selectedReaction = user == null
        ? ''
        : (reactionByUid[user.uid] ??
                (isLiked
                    ? 'like'
                    : isDisliked
                        ? 'dislike'
                        : selectedEmoji))
            .toString();
    final isOwnPost =
        user != null && (data['uid'] ?? '').toString() == user.uid;
    final requestUids = List<String>.from(data['joinRequestUids'] ?? const []);
    final memberUids = List<String>.from(data['memberUids'] ?? const []);
    final rawCapacity = data.containsKey('maxPlayers')
        ? data['maxPlayers']
        : (data['slots'] ?? 5);
    final maxPlayers = rawCapacity is num
        ? rawCapacity.toInt()
        : int.tryParse(rawCapacity?.toString() ?? '');
    final memberCountValue = data['memberCount'];
    final memberCount = memberCountValue is num
        ? memberCountValue.toInt()
        : int.tryParse(memberCountValue?.toString() ?? '') ?? 1;
    final isFull = data['joinStatus'] == 'full' ||
        (maxPlayers != null && memberCount >= maxPlayers);
    final isClosed =
        data['isRecruiting'] == false || data['joinStatus'] == 'closed';
    final hasJoined = user != null && memberUids.contains(user.uid);
    final requestSent =
        requestSentOverride || (user != null && requestUids.contains(user.uid));

    final likes = data['likes'] ?? 0;
    final dislikes = data['dislikes'] ?? 0;
    final comments = data['commentCount'] ?? 0;
    final mediaUrl = (data['mediaUrl'] ?? data['imageUrl'] ?? '').toString();
    final isVideo = data['mediaType'] == 'video';
    final createdAtLabel = formatDateTimeLabel(data['createdAt']);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.fromLTRB(13, 7, 8, 4),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF9B7CFF).withValues(alpha: 0.18),
              child: const Icon(
                Icons.person_rounded,
                color: Color(0xFFB69EFF),
              ),
            ),
            title: InkWell(
              onTap: () {
                final authorUid = (data['uid'] ?? '').toString();
                if (authorUid.isEmpty) return;

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      userId: authorUid,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
                );
              },
              child: Text(
                data['userName'] ?? 'ผู้เล่น',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sports_esports_outlined, size: 15),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        data['game'] ?? '',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (createdAtLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    createdAtLabel,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ],
            ),
            trailing: IconButton(
              tooltip: 'เพิ่มเติม',
              onPressed: onMenu,
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ),
          if (mediaUrl.isNotEmpty)
            isVideo
                ? InlineVideoPlayer(url: mediaUrl, height: 180)
                : Image.network(
                    mediaUrl,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 180,
                      color: const Color(0xFF242331),
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined,
                          size: 50, color: Colors.grey),
                    ),
                  ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if ((data['detail'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    data['detail'] ?? '',
                    style: const TextStyle(
                      height: 1.4,
                      color: Color(0xFFAAA7B7),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '$likes ถูกใจ',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$dislikes ไม่ถูกใจ',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$comments ความคิดเห็น',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'สมาชิก $memberCount/${maxPlayers ?? '∞'}',
                    style: const TextStyle(
                      color: Color(0xFFAAA7B7),
                      fontSize: 12,
                    ),
                  ),
                ),
                JoinRequestButton(
                  postId: doc.id,
                  ownerUid: (data['uid'] ?? '').toString(),
                  currentUserUid: user?.uid,
                  isOwnPost: isOwnPost,
                  hasJoined: hasJoined,
                  requestSentOnPost: requestSent,
                  requestSentLocally: requestSentOverride,
                  isFull: isFull,
                  isClosed: isClosed,
                  onPressed: onJoin,
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 14, endIndent: 14),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: isLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: 'ถูกใจ',
                    count: likes,
                    color: isLiked ? Colors.red : const Color(0xFF9291A4),
                    onPressed: onLike,
                  ),
                ),
                Expanded(
                  child: _ActionButton(
                    icon: isDisliked
                        ? Icons.thumb_down_rounded
                        : Icons.thumb_down_outlined,
                    label: 'ไม่ถูกใจ',
                    count: dislikes,
                    color: isDisliked ? Colors.orange : const Color(0xFF9291A4),
                    onPressed: onDislike,
                  ),
                ),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    label: 'ความคิดเห็น',
                    count: comments,
                    color: const Color(0xFF9291A4),
                    onPressed: onComments,
                  ),
                ),
                IconButton(
                  tooltip: 'Reaction',
                  onPressed: onReaction,
                  icon: const Text(
                    '😊',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              ],
            ),
          ),
          _buildReactionSummary(data, selectedReaction),
        ],
      ),
    );
  }

  Widget _buildReactionSummary(
    Map<String, dynamic> data,
    String selectedReaction,
  ) {
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});

    if (reactions.isEmpty) return const SizedBox.shrink();

    final entries =
        reactions.entries.where((entry) => (entry.value ?? 0) > 0).toList();

    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 6,
        children: entries.map((entry) {
          return Chip(
            backgroundColor:
                selectedReaction == entry.key ? const Color(0xFF51436F) : null,
            label: Text(
              '${entry.key} ${entry.value}',
              style: const TextStyle(fontSize: 12),
            ),
            visualDensity: VisualDensity.compact,
          );
        }).toList(),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic count;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
          vertical: 8,
        ),
      ),
      icon: Icon(icon, size: 17),
      label: Text(
        count == null ? label : '$label ${count == 0 ? '' : count}',
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: const TextStyle(fontSize: 10),
      ),
    );
  }
}
