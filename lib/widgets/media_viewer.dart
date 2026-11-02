// ตัวแสดงรูปหรือวิดีโอแบบเต็มหน้าจอสำหรับสื่อที่แนบในแชต.

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// เปิดรูปภาพหรือวิดีโอในหน้าดูสื่อแบบเต็มจอ
/// เปิด viewer แบบเต็มจอเป็น route แยก โดยส่ง URL และชนิดสื่อเข้าไป.
Future<void> showChatMediaViewer(
  BuildContext context, {
  required String url,
  required bool isVideo,
}) async {
  await Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) =>
          _ChatMediaViewer(url: url, isVideo: isVideo),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(
        opacity: animation,
        child: child,
      ),
    ),
  );
}

class _ChatMediaViewer extends StatefulWidget {
  const _ChatMediaViewer({
    required this.url,
    required this.isVideo,
  });

  final String url;
  final bool isVideo;

  @override
  State<_ChatMediaViewer> createState() =>
      _ChatMediaViewerState();
}

/// จัดการการโหลด/เล่นวิดีโอและการซูมภาพของ viewer พร้อมคืน controller ตอนปิด.
class _ChatMediaViewerState extends State<_ChatMediaViewer> {
  VideoPlayerController? _controller;

  bool _showControls = true;
  bool _failed = false;

  Uri _playbackUri() {
    final source = Uri.parse(widget.url);

    if (source.host != 'res.cloudinary.com') {
      return source;
    }

    final path = source.path.replaceFirst(
      RegExp(r'/video/upload/'),
      '/video/upload/f_mp4,vc_h264/',
    );

    return source.replace(path: path);
  }

  @override
  void initState() {
    super.initState();

    if (widget.isVideo) {
      _initializeVideo();
    }
  }

  /// เตรียมวิดีโอสำหรับหน้าดูเต็มจอและบันทึกสถานะ error เพื่อให้ลองใหม่ได้.
  Future<void> _initializeVideo() async {
    final controller =
        VideoPlayerController.networkUrl(_playbackUri());

    _controller = controller;

    try {
      await controller.initialize();

      await controller.setLooping(false);

      if (!mounted) return;

      await controller.play();

      if (!mounted) return;

      setState(() {});
    } catch (e) {
      debugPrint('[MediaViewer] Video load failed: $e');

      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: widget.isVideo
                  ? _buildVideo(controller)
                  : GestureDetector(
                      onTap: () {
                        setState(() {
                          _showControls = !_showControls;
                        });
                      },
                      child: Center(
                        child: InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 5,
                          child: Image.network(
                            widget.url,
                            fit: BoxFit.contain,
                            loadingBuilder:
                                (context, child, progress) {
                              if (progress == null) {
                                return child;
                              }

                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) {
                              return const Icon(
                                Icons.broken_image_outlined,
                                color: Colors.white70,
                                size: 54,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
            ),

            // ปุ่มย้อนกลับ
            if (_showControls)
              Positioned(
                top: 8,
                left: 8,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    tooltip: 'กลับ',
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // แถบควบคุมวิดีโอ
            if (widget.isVideo &&
                _showControls &&
                controller != null &&
                controller.value.isInitialized)
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () async {
                        if (controller.value.isPlaying) {
                          await controller.pause();
                        } else {
                          await controller.play();
                        }

                        if (mounted) {
                          setState(() {});
                        }
                      },
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),

                    const SizedBox(width: 8),

                    Expanded(
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFFB77CFF),
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    Text(
                      _duration(controller.value.position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// สร้าง UI วิดีโอแยกจากภาพ โดยรองรับ loading, error และปุ่มควบคุม.
  Widget _buildVideo(VideoPlayerController? controller) {
    if (_failed) {
      return const Center(
        child: Text(
          'โหลดวิดีโอไม่สำเร็จ',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    if (controller == null ||
        !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
        ),
      );
    }

    final aspectRatio =
        controller.value.aspectRatio > 0
            ? controller.value.aspectRatio
            : 16 / 9;

    return GestureDetector(
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }

  String _duration(Duration value) {
    final minutes = value.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    final seconds = value.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return '${value.inHours > 0 ? '${value.inHours}:' : ''}'
        '$minutes:$seconds';
  }
}
