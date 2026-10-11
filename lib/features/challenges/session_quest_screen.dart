import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/challenge_alarm_scheduler.dart';
import '../../data/repositories/challenge_repository.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/models/challenge.dart';

class SessionQuestScreen extends ConsumerStatefulWidget {
  const SessionQuestScreen({
    super.key,
    required this.challenge,
    required this.session,
  });

  final Challenge challenge;
  final ChallengeSession session;

  @override
  ConsumerState<SessionQuestScreen> createState() => _SessionQuestScreenState();
}

class _SessionQuestScreenState extends ConsumerState<SessionQuestScreen> {
  final _textCtrl = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageName;
  Uint8List? _audioBytes;
  String? _audioName;
  bool _recording = false;
  bool _submitting = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _done = widget.session.state == SessionState.completed;
    if (widget.session.state == SessionState.scheduled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref
            .read(challengeRepositoryProvider)
            .markSessionInProgress(widget.session.id);
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final picked =
          await ref.read(mediaRepositoryProvider).pickCompressedImage();
      if (picked == null) return;
      setState(() {
        _imageBytes = picked.bytes;
        _imageName = picked.fileName;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Could not add image');
    }
  }

  Future<void> _toggleRecord() async {
    final media = ref.read(mediaRepositoryProvider);
    try {
      if (_recording) {
        final note = await media.stopVoiceNote();
        setState(() {
          _recording = false;
          if (note != null) {
            _audioBytes = note.bytes;
            _audioName = note.fileName;
          }
        });
      } else {
        await media.startVoiceNote();
        setState(() {
          _recording = true;
          _error = null;
        });
      }
    } catch (_) {
      setState(() {
        _recording = false;
        _error = 'Microphone unavailable';
      });
    }
  }

  Future<void> _submit() async {
    if (_recording) {
      setState(() => _error = 'Stop recording before submitting');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(challengeRepositoryProvider).completeQuestSession(
            session: widget.session,
            text: _textCtrl.text,
            imageBytes: _imageBytes,
            imageFileName: _imageName,
            audioBytes: _audioBytes,
            audioFileName: _audioName,
          );
      await ref
          .read(challengeAlarmSchedulerProvider)
          .cancelSession(widget.session.id);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      setState(() {
        _error = e is StateError
            ? e.message
            : 'Could not submit feedback. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
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
    if (_recording) {
      await ref.read(mediaRepositoryProvider).stopVoiceNote(cancel: true);
    }
    await ref.read(challengeRepositoryProvider).skipSession(widget.session.id);
    await ref
        .read(challengeAlarmSchedulerProvider)
        .cancelSession(widget.session.id);
    if (mounted) context.pop();
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
              onPressed: _submitting ? null : _skip,
              child: const Text('Skip'),
            ),
        ],
      ),
      body: _done
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.challenge.title,
                  style: brandDisplay(fontSize: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  'Instructions',
                  style: brandDisplay(fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.challenge.instructions ?? '',
                  style: const TextStyle(height: 1.4),
                ),
                const SizedBox(height: 24),
                Text(
                  'Your feedback',
                  style: brandDisplay(fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Add text, a photo, and/or a voice note — at least one.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _textCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Write a reflection…',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickImage,
                      icon: const Icon(Icons.photo_outlined),
                      label: Text(
                        _imageBytes == null ? 'Photo' : 'Photo added',
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _submitting ? null : _toggleRecord,
                      icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                      label: Text(_recording
                          ? 'Stop'
                          : (_audioBytes == null ? 'Voice' : 'Voice added')),
                    ),
                  ],
                ),
                if (_imageBytes != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _imageBytes!,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _imageBytes = null;
                      _imageName = null;
                    }),
                    child: const Text('Remove photo'),
                  ),
                ],
                if (_audioBytes != null && !_recording)
                  TextButton(
                    onPressed: () => setState(() {
                      _audioBytes = null;
                      _audioName = null;
                    }),
                    child: const Text('Remove voice note'),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit day'),
                ),
              ],
            ),
    );
  }
}
