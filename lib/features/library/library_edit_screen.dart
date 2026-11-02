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
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/models/assignment.dart';
import '../../domain/models/challenge.dart';
import '../../domain/models/library_item.dart';
import 'library_providers.dart';
import 'library_publish_sheet.dart';

class LibraryEditScreen extends ConsumerStatefulWidget {
  const LibraryEditScreen({
    super.key,
    this.itemId,
    this.initialKind,
  });

  final String? itemId;
  final LibraryItemKind? initialKind;

  bool get isNew => itemId == null || itemId == 'new';

  @override
  ConsumerState<LibraryEditScreen> createState() => _LibraryEditScreenState();
}

class _LibraryEditScreenState extends ConsumerState<LibraryEditScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _daysCtrl = TextEditingController(text: '21');
  final _preAlarmCtrl = TextEditingController(text: '10');

  LibraryItemKind _kind = LibraryItemKind.resource;
  String _resourceKind = 'link';
  ChallengeKind _challengeKind = ChallengeKind.quest;
  ChallengeMediaKind _mediaKind = ChallengeMediaKind.audio;

  Map<String, dynamic> _meta = {};
  Uint8List? _pendingBytes;
  String? _pendingFileName;
  String? _pendingContentType;

  bool _hydrated = false;
  bool _saving = false;
  bool _deleting = false;
  String? _error;
  LibraryItem? _existing;

  @override
  void initState() {
    super.initState();
    if (widget.isNew) {
      _kind = widget.initialKind ?? LibraryItemKind.resource;
      _hydrated = true;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _urlCtrl.dispose();
    _instructionsCtrl.dispose();
    _daysCtrl.dispose();
    _preAlarmCtrl.dispose();
    super.dispose();
  }

  void _hydrate(LibraryItem item) {
    if (_hydrated) return;
    _existing = item;
    _kind = item.kind;
    _titleCtrl.text = item.title;
    _bodyCtrl.text = item.body;
    _meta = Map<String, dynamic>.from(item.meta);
    switch (item.kind) {
      case LibraryItemKind.resource:
        _resourceKind = item.meta['kind'] as String? ?? 'link';
        _urlCtrl.text = item.meta['url'] as String? ?? '';
      case LibraryItemKind.challenge:
        _challengeKind = challengeKindFromString(
          item.meta['kind'] as String? ?? 'quest',
        );
        _instructionsCtrl.text = item.meta['instructions'] as String? ?? '';
        _daysCtrl.text = '${item.meta['durationDays'] ?? 21}';
        _preAlarmCtrl.text = '${item.meta['preAlarmMinutes'] ?? 10}';
        if (item.meta['mediaKind'] != null) {
          _mediaKind = challengeMediaKindFromString(
            item.meta['mediaKind'] as String,
          );
        }
      case LibraryItemKind.assignment:
        break;
    }
    _hydrated = true;
  }

  Future<void> _pickResourceFile() async {
    setState(() => _error = null);
    try {
      final media = ref.read(mediaRepositoryProvider);
      PickedFileBytes? picked;
      switch (_resourceKind) {
        case 'pdf':
          picked = await media.pickPdf();
        case 'audio':
          picked = await media.pickAudioFile();
        case 'video':
          picked = await media.pickCameraVideo();
        default:
          return;
      }
      if (picked == null) return;
      setState(() {
        _pendingBytes = picked!.bytes;
        _pendingFileName = picked.fileName;
        _pendingContentType = picked.contentType;
      });
    } catch (_) {
      setState(() => _error = 'Could not pick file');
    }
  }

  Future<void> _pickChallengeMedia() async {
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
        _pendingBytes = bytes;
        _pendingFileName = name.replaceAll(RegExp(r'[^\w.\-]+'), '_');
        _pendingContentType =
            lookupMimeType(name, headerBytes: bytes) ?? fallbackType;
      });
    } catch (_) {
      setState(() => _error = 'Could not pick file');
    }
  }

  Map<String, dynamic> _linkMeta() => {
        if (_meta['source'] != null) 'source': _meta['source'],
        if (_meta['circleId'] != null) 'circleId': _meta['circleId'],
        if (_meta['postId'] != null) 'postId': _meta['postId'],
        if (_meta['challengeId'] != null) 'challengeId': _meta['challengeId'],
        if (_meta['assignmentId'] != null)
          'assignmentId': _meta['assignmentId'],
      };

  Map<String, dynamic> _buildMeta() {
    switch (_kind) {
      case LibraryItemKind.resource:
        if (_resourceKind == 'link' || _resourceKind == 'googleDoc') {
          return {
            ..._linkMeta(),
            'kind': _resourceKind,
            'url': _urlCtrl.text.trim(),
          };
        }
        return {
          ..._linkMeta(),
          'kind': _resourceKind,
          if (_meta['storagePath'] != null) 'storagePath': _meta['storagePath'],
          if (_meta['contentType'] != null) 'contentType': _meta['contentType'],
          if (_meta['fileName'] != null) 'fileName': _meta['fileName'],
          if (_meta['byteSize'] != null) 'byteSize': _meta['byteSize'],
        };
      case LibraryItemKind.challenge:
        return {
          ..._linkMeta(),
          'kind': challengeKindToString(_challengeKind),
          'durationDays': int.tryParse(_daysCtrl.text.trim()) ?? 21,
          'preAlarmMinutes': int.tryParse(_preAlarmCtrl.text.trim()) ?? 10,
          if (_challengeKind == ChallengeKind.quest)
            'instructions': _instructionsCtrl.text.trim(),
          if (_challengeKind == ChallengeKind.media) ...{
            'mediaKind': challengeMediaKindToString(_mediaKind),
            if (_meta['storagePath'] != null)
              'storagePath': _meta['storagePath'],
            if (_meta['contentType'] != null)
              'contentType': _meta['contentType'],
            if (_meta['fileName'] != null) 'fileName': _meta['fileName'],
          },
        };
      case LibraryItemKind.assignment:
        final out = <String, dynamic>{
          if (_meta['source'] != null) 'source': _meta['source'],
          if (_meta['circleId'] != null) 'circleId': _meta['circleId'],
          if (_meta['assignmentId'] != null)
            'assignmentId': _meta['assignmentId'],
          if (_meta['blocks'] is List) 'blocks': _meta['blocks'],
        };
        final existing = _meta['objectives'];
        if (existing is List && existing.isNotEmpty) {
          out['objectives'] = existing;
        } else if (out['blocks'] == null) {
          out['objectives'] = [
            {
              'type': 'purpose',
              'label': Objective(
                id: '',
                assignmentId: '',
                type: ObjectiveType.purpose,
                order: 0,
              ).label,
            },
            {
              'type': 'morning_practice',
              'label': Objective(
                id: '',
                assignmentId: '',
                type: ObjectiveType.morningPractice,
                order: 1,
              ).label,
            },
          ];
        }
        return out;
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

    if (_kind == LibraryItemKind.resource) {
      if ((_resourceKind == 'link' || _resourceKind == 'googleDoc') &&
          _urlCtrl.text.trim().isEmpty) {
        setState(() => _error = 'URL is required');
        return;
      }
      if (_resourceKind != 'link' &&
          _resourceKind != 'googleDoc' &&
          _pendingBytes == null &&
          _meta['storagePath'] == null) {
        setState(() => _error = 'Attach a file');
        return;
      }
    }

    if (_kind == LibraryItemKind.challenge) {
      final days = int.tryParse(_daysCtrl.text.trim()) ?? 0;
      if (days < 1) {
        setState(() => _error = 'Duration must be at least 1 day');
        return;
      }
      if (_challengeKind == ChallengeKind.quest &&
          _instructionsCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Instructions are required');
        return;
      }
      if (_challengeKind == ChallengeKind.media &&
          _pendingBytes == null &&
          _meta['storagePath'] == null) {
        setState(() => _error = 'Upload media for this challenge');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ref.read(libraryRepositoryProvider);
      late String itemId;
      if (widget.isNew) {
        itemId = await repo.createItem(
          ownerId: uid,
          kind: _kind,
          title: title,
          body: _bodyCtrl.text,
          meta: _buildMeta(),
        );
      } else {
        itemId = widget.itemId!;
        await repo.updateItem(
          itemId: itemId,
          title: title,
          body: _bodyCtrl.text,
          meta: _buildMeta(),
        );
      }

      var meta = _buildMeta();
      if (_pendingBytes != null && _pendingFileName != null) {
        final uploaded = await repo.uploadLibraryFile(
          ownerId: uid,
          itemId: itemId,
          bytes: _pendingBytes!,
          fileName: _pendingFileName!,
          contentType: _pendingContentType,
        );
        meta = {...meta, ...uploaded};
        await repo.updateItem(itemId: itemId, meta: meta);
      }

      if (!mounted) return;
      if (widget.isNew) {
        context.go('/library/$itemId');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
        setState(() {
          _meta = meta;
          _pendingBytes = null;
          _pendingFileName = null;
          _pendingContentType = null;
          if (_existing != null) {
            _existing = _existing!.copyWithMeta(
              title: title,
              body: _bodyCtrl.text,
              meta: meta,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not save. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final item = _existing;
    if (item == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete library item?'),
        content: Text('“${item.title}” will be removed from your library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(libraryRepositoryProvider).deleteItem(item);
      if (!mounted) return;
      context.go('/library');
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not delete';
          _deleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isNew) {
      final async = ref.watch(libraryItemProvider(widget.itemId!));
      final item = async.asData?.value;
      if (item != null && !_hydrated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_hydrated) setState(() => _hydrate(item));
        });
      }
      if (!_hydrated) {
        return Scaffold(
          appBar: brandAppBar(
            title: Text(
              'Library',
              style: brandDisplay(fontWeight: FontWeight.w600),
            ),
          ),
          body: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (item) {
              if (item == null) {
                return const Center(child: Text('Item not found'));
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        );
      }
    }

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          widget.isNew
              ? 'New ${libraryItemKindLabel(_kind).toLowerCase()}'
              : libraryItemKindLabel(_kind),
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (!widget.isNew && _existing != null)
            IconButton(
              icon: const Icon(Icons.publish_outlined),
              tooltip: 'Publish to Hoop',
              onPressed: _saving || _deleting
                  ? null
                  : () => showPublishLibraryItemSheet(
                        context: context,
                        ref: ref,
                        item: _existing!.copyWithMeta(
                          title: _titleCtrl.text.trim().isEmpty
                              ? _existing!.title
                              : _titleCtrl.text.trim(),
                          body: _bodyCtrl.text,
                          meta: _buildMeta()
                            ..addAll({
                              if (_meta['storagePath'] != null)
                                'storagePath': _meta['storagePath'],
                              if (_meta['contentType'] != null)
                                'contentType': _meta['contentType'],
                              if (_meta['fileName'] != null)
                                'fileName': _meta['fileName'],
                            }),
                        ),
                      ),
            ),
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving || _deleting ? null : _delete,
            ),
        ],
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
            controller: _bodyCtrl,
            decoration: InputDecoration(
              labelText: _kind == LibraryItemKind.assignment
                  ? 'Description'
                  : _kind == LibraryItemKind.challenge
                      ? 'Description'
                      : 'Caption / notes',
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          if (_kind == LibraryItemKind.resource) ..._resourceFields(),
          if (_kind == LibraryItemKind.challenge) ..._challengeFields(),
          if (_kind == LibraryItemKind.assignment) ..._assignmentFields(),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving || _deleting ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.isNew ? 'Create' : 'Save'),
          ),
        ],
      ),
    );
  }

  List<Widget> _assignmentFields() {
    final circleId = _meta['circleId'] as String?;
    final assignmentId = _meta['assignmentId'] as String?;
    final hasLink = circleId != null &&
        circleId.isNotEmpty &&
        assignmentId != null &&
        assignmentId.isNotEmpty;
    final blockCount =
        (_meta['blocks'] is List) ? (_meta['blocks'] as List).length : 0;

    return [
      Text(
        hasLink
            ? (blockCount > 0
                ? 'Linked to a Hoop assignment ($blockCount content blocks). '
                    'Edit the full chat in the Hoop; title and description here '
                    'update the library catalog.'
                : 'Linked to a Hoop assignment. Open it to edit content blocks.')
            : 'Title and description are reused when you publish into a Hoop. '
                'New templates get a short text + question starter; linked '
                'items keep their block snapshot when available.',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
        ),
      ),
      if (hasLink) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push(
            '/circles/$circleId/assignments/$assignmentId',
          ),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open in Hoop'),
        ),
      ],
    ];
  }

  List<Widget> _resourceFields() {
    return [
      DropdownButtonFormField<String>(
        value: _resourceKind,
        decoration: const InputDecoration(labelText: 'Resource type'),
        items: const [
          DropdownMenuItem(value: 'link', child: Text('Link')),
          DropdownMenuItem(value: 'googleDoc', child: Text('Google Doc')),
          DropdownMenuItem(value: 'pdf', child: Text('PDF')),
          DropdownMenuItem(value: 'audio', child: Text('Audio')),
          DropdownMenuItem(value: 'video', child: Text('Video')),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _resourceKind = v;
            _pendingBytes = null;
            _pendingFileName = null;
          });
        },
      ),
      const SizedBox(height: 12),
      if (_resourceKind == 'link' || _resourceKind == 'googleDoc')
        TextField(
          controller: _urlCtrl,
          decoration: InputDecoration(
            labelText:
                _resourceKind == 'googleDoc' ? 'Google Docs URL' : 'URL',
          ),
          keyboardType: TextInputType.url,
        )
      else ...[
        OutlinedButton.icon(
          onPressed: _pickResourceFile,
          icon: const Icon(Icons.attach_file),
          label: Text(
            _pendingFileName ??
                (_meta['fileName'] as String?) ??
                'Choose file',
          ),
        ),
      ],
    ];
  }

  List<Widget> _challengeFields() {
    return [
      SegmentedButton<ChallengeKind>(
        segments: const [
          ButtonSegment(
            value: ChallengeKind.quest,
            label: Text('Quest'),
            icon: Icon(Icons.flag_outlined),
          ),
          ButtonSegment(
            value: ChallengeKind.media,
            label: Text('Media'),
            icon: Icon(Icons.headphones_outlined),
          ),
        ],
        selected: {_challengeKind},
        onSelectionChanged: (s) {
          setState(() {
            _challengeKind = s.first;
            _pendingBytes = null;
          });
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _daysCtrl,
        decoration: const InputDecoration(labelText: 'Duration (days)'),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _preAlarmCtrl,
        decoration: const InputDecoration(labelText: 'Pre-alarm (minutes)'),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      if (_challengeKind == ChallengeKind.quest)
        TextField(
          controller: _instructionsCtrl,
          decoration: const InputDecoration(labelText: 'Daily instructions'),
          maxLines: 4,
        )
      else ...[
        DropdownButtonFormField<ChallengeMediaKind>(
          value: _mediaKind,
          decoration: const InputDecoration(labelText: 'Media type'),
          items: const [
            DropdownMenuItem(
              value: ChallengeMediaKind.audio,
              child: Text('Audio'),
            ),
            DropdownMenuItem(
              value: ChallengeMediaKind.video,
              child: Text('Video'),
            ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _mediaKind = v;
              _pendingBytes = null;
            });
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickChallengeMedia,
          icon: const Icon(Icons.upload_file),
          label: Text(
            _pendingFileName ??
                (_meta['fileName'] as String?) ??
                'Upload media',
          ),
        ),
      ],
    ];
  }
}

extension on LibraryItem {
  LibraryItem copyWithMeta({
    String? title,
    String? body,
    Map<String, dynamic>? meta,
  }) {
    return LibraryItem(
      id: id,
      ownerId: ownerId,
      kind: kind,
      title: title ?? this.title,
      body: body ?? this.body,
      meta: meta ?? this.meta,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
