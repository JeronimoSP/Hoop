import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/challenge_alarm_scheduler.dart';
import '../../data/repositories/challenge_repository.dart';
import '../../domain/models/challenge.dart';

class SessionMediaScreen extends ConsumerStatefulWidget {
  const SessionMediaScreen({
    super.key,
    required this.challenge,
    required this.session,
    this.autoplay = false,
  });

  final Challenge challenge;
  final ChallengeSession session;
  final bool autoplay;

  @override
  ConsumerState<SessionMediaScreen> createState() => _SessionMediaScreenState();
}

class _SessionMediaScreenState extends ConsumerState<SessionMediaScreen> {
  AudioPlayer? _audio;
  VideoPlayerController? _video;
  String? _audioUrl;
  bool _audioStarted = false;
  bool _loading = true;
  bool _playing = false;
  bool _completing = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _done = widget.session.state == SessionState.completed;
    _prepare();
  }

  Future<void> _prepare() async {
    final path = widget.challenge.storagePath;
    if (path == null || path.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No practice file on this challenge';
      });
      return;
    }
    try {
      if (widget.session.state == SessionState.scheduled) {
        await ref
            .read(challengeRepositoryProvider)
            .markSessionInProgress(widget.session.id);
      }
      final url =
          await ref.read(challengeRepositoryProvider).getDownloadUrl(path);
      if (widget.challenge.mediaKind == ChallengeMediaKind.video) {
        final controller =
            VideoPlayerController.networkUrl(Uri.parse(url));
        await controller.initialize();
        controller.addListener(_onVideoTick);
        _video = controller;
      } else {
        final player = AudioPlayer();
        player.onPlayerComplete.listen((_) => _onPlaybackEnded());
        _audio = player;
        _audioUrl = url;
      }
      if (mounted) setState(() => _loading = false);
      if (widget.autoplay && !_done) {
        await _togglePlay();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the practice file';
        });
      }
    }
  }

  void _onVideoTick() {
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    final pos = v.value.position;
    final dur = v.value.duration;
    if (dur.inMilliseconds > 0 &&
        pos >= dur - const Duration(milliseconds: 400) &&
        !_done &&
        !_completing) {
      _onPlaybackEnded();
    }
    final playing = v.value.isPlaying;
    if (playing != _playing && mounted) {
      setState(() => _playing = playing);
    }
  }

  Future<void> _onPlaybackEnded() async {
    if (_done || _completing) return;
    setState(() {
      _completing = true;
      _playing = false;
    });
    try {
      await ref
          .read(challengeRepositoryProvider)
          .completeMediaSession(widget.session.id);
      await ref
          .read(challengeAlarmSchedulerProvider)
          .cancelSession(widget.session.id);
      if (mounted) setState(() => _done = true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save completion');
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_done) return;
    final video = _video;
    final audio = _audio;
    if (video != null) {
      if (video.value.isPlaying) {
        await video.pause();
      } else {
        await video.play();
      }
      return;
    }
    if (audio != null) {
      if (_playing) {
        await audio.pause();
        setState(() => _playing = false);
      } else {
        final url = _audioUrl;
        if (!_audioStarted && url != null) {
          await audio.play(UrlSource(url));
          _audioStarted = true;
        } else {
          await audio.resume();
        }
        setState(() => _playing = true);
      }
    }
  }

  Future<void> _skip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Skip this day?'),
        content: const Text(
          'Skipped days do not count as completed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _audio?.stop();
    await _video?.pause();
    await ref.read(challengeRepositoryProvider).skipSession(widget.session.id);
    await ref
        .read(challengeAlarmSchedulerProvider)
        .cancelSession(widget.session.id);
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideoTick);
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Day ${widget.session.dayIndex}',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (!_done)
            TextButton(
              onPressed: _skip,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.challenge.title,
              style: brandDisplay(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Play the practice to the end. Cues are in the recording.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const Spacer(),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              )
            else if (_done)
              Column(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Day ${widget.session.dayIndex} complete',
                    style: brandDisplay(fontSize: 20),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('Done'),
                  ),
                ],
              )
            else ...[
              if (_video != null && _video!.value.isInitialized)
                AspectRatio(
                  aspectRatio: _video!.value.aspectRatio == 0
                      ? 16 / 9
                      : _video!.value.aspectRatio,
                  child: VideoPlayer(_video!),
                )
              else
                Icon(
                  Icons.headphones,
                  size: 72,
                  color: AppColors.accent.withValues(alpha: 0.7),
                ),
              const SizedBox(height: 24),
              Center(
                child: IconButton.filled(
                  iconSize: 40,
                  onPressed: _togglePlay,
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                ),
              ),
              if (_completing) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
            const Spacer(),
          ],
        ),
      ),
    );
  }
}
