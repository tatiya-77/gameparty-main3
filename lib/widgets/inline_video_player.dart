/// ตัวเล่นวิดีโอภายในเนื้อหาโพสต์ พร้อมสถานะโหลด ข้อผิดพลาด และปุ่มลองใหม่.
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({
    super.key,
    required this.url,
    this.height = 220,
    this.onOpen,
  });

  final String url;
  final double height;
  final VoidCallback? onOpen;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

/// ถือ VideoPlayerController และสถานะกำลังโหลด/ผิดพลาดตลอดอายุ widget.
class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late VideoPlayerController _controller;
  bool _hasError = false;

  Uri _playbackUri() {
    final source = Uri.tryParse(widget.url);
    if (source == null || source.host != 'res.cloudinary.com') {
      return Uri.parse(widget.url);
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
    _initializeController();
  }

  /// สร้าง controller จาก URL, initialize และเริ่ม playback เมื่อพร้อม โดยเช็ก mounted ก่อน setState.
  Future<void> _initializeController() async {
    _hasError = false;
    _controller = VideoPlayerController.networkUrl(_playbackUri());
    try {
      await _controller.initialize();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('[VideoPlayer] Failed to load ${widget.url}: $error');
      if (mounted) setState(() => _hasError = true);
    }
  }

  /// ปล่อย controller เดิมแล้ว initialize ใหม่เมื่อโหลดวิดีโอไม่สำเร็จ.
  Future<void> _retry() async {
    await _controller.dispose();
    if (!mounted) return;
    setState(() => _hasError = false);
    await _initializeController();
  }

  @override
  /// หยุดและคืนทรัพยากร controller ป้องกัน decoder ค้างเมื่อเลื่อนออกจากจอ.
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        final safeBubbleWidth = (screenWidth * 0.62 - 20).clamp(120.0, screenWidth);
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth.clamp(0.0, safeBubbleWidth)
            : safeBubbleWidth;
        final ratio = _controller.value.isInitialized &&
                _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9;
        var displayWidth = availableWidth;
        var displayHeight = displayWidth / ratio;
        final maxHeight = widget.height > 0 ? widget.height * 2 : 360.0;
        if (displayHeight > maxHeight) {
          displayHeight = maxHeight;
          displayWidth = displayHeight * ratio;
        }

        return Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: widget.onOpen,
            child: SizedBox(
              width: displayWidth,
              height: displayHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ColoredBox(
                  color: Colors.black,
                  child: _hasError
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.white70),
                              const SizedBox(height: 6),
                              const Text('โหลดวิดีโอไม่สำเร็จ',
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                              TextButton.icon(
                                onPressed: _retry,
                                icon: const Icon(Icons.refresh_rounded,
                                    size: 16),
                                label: const Text('ลองอีกครั้ง'),
                              ),
                            ],
                          ),
                        )
                      : _controller.value.isInitialized
                          ? Stack(
                              fit: StackFit.expand,
                              alignment: Alignment.center,
                              children: [
                                FittedBox(
                                  fit: BoxFit.contain,
                                  child: SizedBox(
                                    width: _controller.value.size.width,
                                    height: _controller.value.size.height,
                                    child: VideoPlayer(_controller),
                                  ),
                                ),
                                Center(
                                  child: IconButton.filledTonal(
                                    onPressed: widget.onOpen ??
                                        () => setState(() =>
                                            _controller.value.isPlaying
                                                ? _controller.pause()
                                                : _controller.play()),
                                    iconSize: 38,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.black54,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: Icon(_controller.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded),
                                  ),
                                ),
                                Positioned(
                                  left: 8,
                                  right: 8,
                                  bottom: 5,
                                  child: VideoProgressIndicator(
                                    _controller,
                                    allowScrubbing: true,
                                    colors: const VideoProgressColors(
                                      playedColor: Color(0xFFB77CFF),
                                      bufferedColor: Colors.white38,
                                      backgroundColor: Colors.white24,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
