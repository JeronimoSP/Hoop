import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mime/mime.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/challenge_repository.dart';
import '../../domain/models/challenge.dart';

class ChallengeEditScreen extends ConsumerStatefulWidget {
  const ChallengeEditScreen({super.key, required this.circleId});

  final String circleId;

  @override
  ConsumerState<ChallengeEditScreen> createState() =>
      _ChallengeEditScreenState();
}

class _ChallengeEditScreenState extends ConsumerState<ChallengeEditScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _daysCtrl = TextEditingController(text: '21');
  final _preAlarmCtrl = TextEditingController(text: '10');

  ChallengeKind _kind = ChallengeKind.quest;
  ChallengeMediaKind _mediaKind = ChallengeMediaKind.audio;
  Uint8List? _mediaBytes;
  String? _mediaFileName;
  String? _mediaContentType;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _instructionsCtrl.dispose();
    _daysCtrl.dispose();
    _preAlarmCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    setState(() => _error = null);
    try {
      final isVideo = _mediaKind == ChallengeMediaKind.video;
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: isVideo
            ? const ['mp4', 'mov', 'webm', 'm4v']
            : const ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'webm'],
      );
      if (files.isEmpty) return;
      final file = files.single;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() => _error = 'Could not read the file');
        return;
      }
      if (bytes.length > 100 * 1024 * 1024) {
        setState(() => _error = 'File must be 100 MB or less');
        return;
      }
      final fallbackName = isVideo ? 'practice.mp4' : 'practice.mp3';
      final name = file.name.trim().isEmpty ? fallbackName : file.name;
      final fallbackType = isVideo ? 'video/mp4' : 'audio/mpeg';
      setState(() {
        _mediaBytes = bytes;
        _mediaFileName = name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
        _mediaContentType =
            lookupMimeType(name, headerBytes: bytes) ?? fallbackType;
      });
    } catch (e) {
      setState(() => _error = 'Could not pick file');
    }
  }

  Future<void> _save() async {
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    if (uid == null) return;

    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    final days = int.tryParse(_daysCtrl.text.trim()) ?? 0;
    if (days < 1) {
      setState(() => _error = 'Duration must be at least 1 day');
      return;
    }
    final preAlarm = int.tryParse(_preAlarmCtrl.text.trim()) ?? 10;

    if (_kind == ChallengeKind.media && _mediaBytes == null) {
      setState(() => _error = 'Upload an audio or video file');
      return;
    }
    if (_kind == ChallengeKind.quest &&
        _instructionsCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Instructions are required for quest challenges');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(challengeRepositoryProvider).createChallenge(
            circleId: widget.circleId,
            createdBy: uid,
            title: title,
            description: _descCtrl.text,
            kind: _kind,
            durationDays: days,
            preAlarmMinutes: preAlarm.clamp(0, 180),
            mediaKind: _kind == ChallengeKind.media ? _mediaKind : null,
            instructions:
                _kind == ChallengeKind.quest ? _instructionsCtrl.text : null,
            mediaBytes: _mediaBytes,
            mediaFileName: _mediaFileName,
            mediaContentType: _mediaContentType,
          );
      if (!mounted) return;
      context.go('/circles/${widget.circleId}/challenges/$id');
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not create challenge. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'New challenge',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
            ),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          Text('Kind', style: brandDisplay(fontSize: 16)),
          const SizedBox(height: 8),
          SegmentedButton<ChallengeKind>(
            segments: const [
              ButtonSegment(
                value: ChallengeKind.media,
                label: Text('Media'),
                icon: Icon(Icons.play_circle_outline),
              ),
              ButtonSegment(
                value: ChallengeKind.quest,
                label: Text('Quest'),
                icon: Icon(Icons.edit_note),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _daysCtrl,
                  decoration: const InputDecoration(labelText: 'Duration (days)'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _preAlarmCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pre-alarm (min)',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_kind == ChallengeKind.media) ...[
            Text('Practice file', style: brandDisplay(fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              'Cues (gong, guidance, music) must be inside this file. The app only plays it.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 8),
            SegmentedButton<ChallengeMediaKind>(
              segments: const [
                ButtonSegment(
                  value: ChallengeMediaKind.audio,
                  label: Text('Audio'),
                ),
                ButtonSegment(
                  value: ChallengeMediaKind.video,
                  label: Text('Video'),
                ),
              ],
              selected: {_mediaKind},
              onSelectionChanged: (s) => setState(() {
                _mediaKind = s.first;
                _mediaBytes = null;
                _mediaFileName = null;
                _mediaContentType = null;
              }),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickMedia,
              icon: const Icon(Icons.upload_file),
              label: Text(
                _mediaFileName == null
                    ? 'Choose ${_mediaKind == ChallengeMediaKind.video ? 'video' : 'audio'}'
                    : _mediaFileName!,
              ),
            ),
          ] else ...[
            Text('Instructions', style: brandDisplay(fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionsCtrl,
              decoration: const InputDecoration(
                hintText: 'What should members reflect on or do each day?',
                alignLabelWithHint: true,
              ),
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Publish challenge'),
          ),
        ],
      ),
    );
  }
}
