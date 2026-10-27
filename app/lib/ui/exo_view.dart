import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'theme.dart';

/// عرض ExoPlayer مع أزرار تحكم (video_player لا يأتي بواجهة تحكم جاهزة):
/// تشغيل/إيقاف، شريط تقدم (للمحتوى غير المباشر)، ملء الشاشة، ومؤشر تحميل.
class ExoView extends StatefulWidget {
  const ExoView({super.key, required this.controller, this.fullscreen = false});

  final VideoPlayerController controller;
  final bool fullscreen;

  @override
  State<ExoView> createState() => _ExoViewState();
}

class _ExoViewState extends State<ExoView> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && widget.controller.value.isPlaying) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  Future<void> _togglePlay() async {
    final c = widget.controller;
    try {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        await c.play();
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _showControls = true);
      _scheduleHide();
    }
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, __, ___) => _ExoFullscreenPage(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ColoredBox(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, v, _) {
            final ratio = v.isInitialized && v.aspectRatio > 0 ? v.aspectRatio : 16 / 9;
            final live = !v.isInitialized || v.duration.inSeconds <= 0;
            return Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(c)),
                ),
                if (v.isBuffering && v.isInitialized)
                  const Center(
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: kOrange,
                        backgroundColor: Color.fromRGBO(255, 255, 255, .15),
                      ),
                    ),
                  ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _showControls ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: GestureDetector(
                            onTap: _togglePlay,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color.fromRGBO(0, 0, 0, .55),
                              ),
                              child: Icon(
                                v.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Color.fromRGBO(0, 0, 0, .7), Color.fromRGBO(0, 0, 0, 0)],
                              ),
                            ),
                            child: Row(
                              children: [
                                if (live)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: kOrange,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('مباشر', style: cairo(size: 12, weight: 700)),
                                  )
                                else
                                  Expanded(
                                    child: VideoProgressIndicator(
                                      c,
                                      allowScrubbing: true,
                                      colors: const VideoProgressColors(
                                        playedColor: kOrange,
                                        bufferedColor: Color.fromRGBO(255, 255, 255, .35),
                                        backgroundColor: Color.fromRGBO(255, 255, 255, .15),
                                      ),
                                    ),
                                  ),
                                if (live) const Spacer(),
                                IconButton(
                                  onPressed: widget.fullscreen ? () => Navigator.of(context).maybePop() : _openFullscreen,
                                  icon: Icon(
                                    widget.fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExoFullscreenPage extends StatefulWidget {
  const _ExoFullscreenPage({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_ExoFullscreenPage> createState() => _ExoFullscreenPageState();
}

class _ExoFullscreenPageState extends State<_ExoFullscreenPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ExoView(controller: widget.controller, fullscreen: true),
    );
  }
}
