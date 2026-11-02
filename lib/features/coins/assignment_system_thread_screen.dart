import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/models/assignment.dart';
import '../challenges/challenges_providers.dart';

final assignmentDocProvider =
    StreamProvider.autoDispose.family<Assignment?, String>((ref, assignmentId) {
  return ref.watch(assignmentRepositoryProvider).watchAssignment(assignmentId);
});

final assignmentBlocksProvider = StreamProvider.autoDispose.family<
    List<AssignmentBlock>,
    ({String circleId, String assignmentId})>((ref, key) {
  return ref.watch(assignmentRepositoryProvider).watchBlocks(
        circleId: key.circleId,
        assignmentId: key.assignmentId,
      );
});

/// Chat-with-the-system assignment thread (draft authoring + student fill).
class AssignmentSystemThreadScreen extends ConsumerStatefulWidget {
  const AssignmentSystemThreadScreen({
    super.key,
    required this.circleId,
    this.assignmentId,
    this.viewAsUserId,
    this.forceEdit = false,
  });

  final String circleId;
  final String? assignmentId;
  final String? viewAsUserId;
  final bool forceEdit;

  @override
  ConsumerState<AssignmentSystemThreadScreen> createState() =>
      _AssignmentSystemThreadScreenState();
}

class _AssignmentSystemThreadScreenState
    extends ConsumerState<AssignmentSystemThreadScreen> {
  String? _assignmentId;
  bool _creating = false;
  bool _structureLocked = false;
  final _composer = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _debounce = <String, Timer>{};
  final _textCtrls = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    _assignmentId = widget.assignmentId;
    if (_assignmentId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureDraft());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLock());
    }
  }

  @override
  void dispose() {
    _composer.dispose();
    _titleCtrl.dispose();
    for (final t in _debounce.values) {
      t.cancel();
    }
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _ensureDraft() async {
    if (_creating || _assignmentId != null) return;
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    if (uid == null) return;
    setState(() => _creating = true);
    try {
      final id = await ref
          .read(assignmentRepositoryProvider)
          .createDraftAssignment(
            circleId: widget.circleId,
            createdBy: uid,
          );
      if (!mounted) return;
      setState(() {
        _assignmentId = id;
        _creating = false;
      });
      context.replace(
        '/circles/${widget.circleId}/assignments/$id/edit',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _loadLock() async {
    final id = _assignmentId;
    if (id == null) return;
    final locked = await ref.read(assignmentRepositoryProvider).hasAnyAnswers(
          circleId: widget.circleId,
          assignmentId: id,
        );
    if (mounted) setState(() => _structureLocked = locked);
  }

  Future<void> _appendBlock({
    required BlockKind kind,
    required String type,
    Map<String, dynamic> payload = const {},
    bool required = true,
  }) async {
    final id = _assignmentId;
    if (id == null || _structureLocked) return;
    final blocks = ref
            .read(
              assignmentBlocksProvider((
                circleId: widget.circleId,
                assignmentId: id,
              )),
            )
            .asData
            ?.value ??
        const [];
    await ref.read(assignmentRepositoryProvider).addBlock(
          circleId: widget.circleId,
          assignmentId: id,
          kind: kind,
          type: type,
          order: blocks.length,
          required: kind == BlockKind.input ? required : false,
          payload: payload,
        );
  }

  Future<void> _sendText() async {
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    await _appendBlock(
      kind: BlockKind.content,
      type: 'text',
      payload: {'body': body},
    );
    _composer.clear();
  }

  Future<void> _showAttachMenu({required bool canAuthor}) async {
    if (!canAuthor || _structureLocked) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Content',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _attachImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Document (PDF)'),
              onTap: () {
                Navigator.pop(ctx);
                _attachPdf();
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Link'),
              onTap: () {
                Navigator.pop(ctx);
                _promptLink();
              },
            ),
            const Divider(),
            const ListTile(
              title: Text(
                'Needs a response',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.short_text),
              title: const Text('Question'),
              onTap: () {
                Navigator.pop(ctx);
                _promptQuestion();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload request'),
              onTap: () {
                Navigator.pop(ctx);
                _appendBlock(
                  kind: BlockKind.input,
                  type: 'upload',
                  payload: {
                    'prompt': 'Upload your file',
                    'allowedMime': ['*/*'],
                    'maxBytes': 20 * 1024 * 1024,
                    'maxFiles': 1,
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_checked),
              title: const Text('Single choice'),
              onTap: () {
                Navigator.pop(ctx);
                _promptChoice(multiple: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist),
              title: const Text('Multiple choice'),
              onTap: () {
                Navigator.pop(ctx);
                _promptChoice(multiple: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _attachImage() async {
    final id = _assignmentId;
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    if (id == null || uid == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final uploaded = await ref.read(mediaRepositoryProvider).uploadCircleFile(
          circleId: widget.circleId,
          userId: uid,
          postId: id,
          file: PickedFileBytes(
            bytes: Uint8List.fromList(bytes),
            contentType: picked.mimeType ?? 'image/jpeg',
            fileName: picked.name,
          ),
        );
    await _appendBlock(
      kind: BlockKind.content,
      type: 'media',
      payload: {
        'mediaKind': 'image',
        'storagePath': uploaded.storagePath,
        'downloadUrl': uploaded.downloadUrl,
        'mime': picked.mimeType ?? 'image/jpeg',
        'fileName': picked.name,
      },
    );
  }

  Future<void> _attachPdf() async {
    final id = _assignmentId;
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    if (id == null || uid == null) return;
    final media = ref.read(mediaRepositoryProvider);
    final picked = await media.pickPdf();
    if (picked == null) return;
    final uploaded = await media.uploadCircleFile(
      circleId: widget.circleId,
      userId: uid,
      postId: id,
      file: picked,
    );
    await _appendBlock(
      kind: BlockKind.content,
      type: 'media',
      payload: {
        'mediaKind': 'pdf',
        'storagePath': uploaded.storagePath,
        'downloadUrl': uploaded.downloadUrl,
        'mime': 'application/pdf',
        'fileName': picked.fileName,
      },
    );
  }

  Future<void> _promptLink() async {
    final urlCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'URL'),
            ),
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      await _appendBlock(
        kind: BlockKind.content,
        type: 'link',
        payload: {
          'url': urlCtrl.text.trim(),
          'label': labelCtrl.text.trim(),
        },
      );
    }
  }

  Future<void> _promptQuestion() async {
    final ctrl = TextEditingController();
    var longAnswer = true;
    var required = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Question'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Prompt'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Long answer'),
                value: longAnswer,
                onChanged: (v) => setLocal(() => longAnswer = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Required'),
                value: required,
                onChanged: (v) => setLocal(() => required = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await _appendBlock(
        kind: BlockKind.input,
        type: 'question',
        required: required,
        payload: {
          'prompt': ctrl.text.trim(),
          'longAnswer': longAnswer,
        },
      );
    }
  }

  Future<void> _promptChoice({required bool multiple}) async {
    final promptCtrl = TextEditingController();
    final optionsCtrl = TextEditingController(text: 'Option A\nOption B');
    var required = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(multiple ? 'Multiple choice' : 'Single choice'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: promptCtrl,
                decoration: const InputDecoration(hintText: 'Prompt'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: optionsCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'One option per line',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Required'),
                value: required,
                onChanged: (v) => setLocal(() => required = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final lines = optionsCtrl.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (promptCtrl.text.trim().isEmpty || lines.length < 2) return;
    await _appendBlock(
      kind: BlockKind.input,
      type: multiple ? 'multipleChoice' : 'singleChoice',
      required: required,
      payload: {
        'prompt': promptCtrl.text.trim(),
        'options': [
          for (var i = 0; i < lines.length; i++)
            {'id': 'opt_$i', 'label': lines[i]},
        ],
      },
    );
  }

  Future<void> _publish(Assignment assignment) async {
    final id = _assignmentId;
    if (id == null) return;
    final titleCtrl = TextEditingController(
      text: assignment.title == 'Untitled assignment'
          ? _titleCtrl.text
          : assignment.title,
    );
    DateTime? opensAt = assignment.opensAt;
    DateTime? dueAt = assignment.dueAt;
    var allowLate = assignment.allowLate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Publish assignment'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    dueAt == null
                        ? 'Due: not set'
                        : 'Due: ${dueAt!.toLocal()}',
                  ),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate:
                          dueAt ?? DateTime.now().add(const Duration(days: 7)),
                      firstDate: DateTime.now(),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (d != null) setLocal(() => dueAt = d);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow late submissions'),
                  value: allowLate,
                  onChanged: (v) => setLocal(() => allowLate = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty) return;
    await ref.read(assignmentRepositoryProvider).publishAssignment(
          assignmentId: id,
          title: titleCtrl.text.trim(),
          opensAt: opensAt,
          dueAt: dueAt,
          allowLate: allowLate,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Assignment published')),
    );
    context.go('/circles/${widget.circleId}/assignments');
  }

  TextEditingController _ctrlFor(String blockId, String initial) {
    return _textCtrls.putIfAbsent(
      blockId,
      () => TextEditingController(text: initial),
    );
  }

  bool _canStudentEdit(Assignment a, AssignmentSubmission? sub) {
    if (widget.viewAsUserId != null) return false;
    final submitted = sub?.status == SubmissionStatus.submitted ||
        sub?.status == SubmissionStatus.late;
    if (!submitted) {
      if (a.dueAt != null &&
          DateTime.now().isAfter(a.dueAt!) &&
          !a.allowLate) {
        return false;
      }
      return true;
    }
    if (a.dueAt == null) return true;
    if (DateTime.now().isBefore(a.dueAt!)) return true;
    return a.allowLate;
  }

  @override
  Widget build(BuildContext context) {
    final id = _assignmentId;
    if (id == null || _creating) {
      return Scaffold(
        appBar: brandAppBar(title: const Text('New assignment')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final myUid = ref.watch(authStateProvider).asData?.value?.uid;
    final viewUid = widget.viewAsUserId ?? myUid;
    final membership = myUid == null
        ? null
        : ref
            .watch(
              circleMembershipProvider(
                (circleId: widget.circleId, userId: myUid),
              ),
            )
            .asData
            ?.value;
    final isAdmin = membership?.isAdmin == true;

    final assignmentAsync = ref.watch(assignmentDocProvider(id));
    final blocksAsync = ref.watch(
      assignmentBlocksProvider((
        circleId: widget.circleId,
        assignmentId: id,
      )),
    );

    return assignmentAsync.when(
      loading: () => Scaffold(
        appBar: brandAppBar(title: const Text('Assignment')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: brandAppBar(title: const Text('Assignment')),
        body: Center(child: Text('$e')),
      ),
      data: (assignment) {
        if (assignment == null) {
          return Scaffold(
            appBar: brandAppBar(title: const Text('Assignment')),
            body: const Center(child: Text('Not found')),
          );
        }

        if (_titleCtrl.text.isEmpty && assignment.title.isNotEmpty) {
          _titleCtrl.text = assignment.title;
        }

        final canAuthor = isAdmin &&
            (assignment.isDraft || widget.forceEdit) &&
            !_structureLocked &&
            widget.viewAsUserId == null;
        final showComposer = canAuthor;
        final studentMode = assignment.isPublished &&
            widget.viewAsUserId == null &&
            !widget.forceEdit;

        return _StudentOrAuthorBody(
          circleId: widget.circleId,
          assignmentId: id,
          assignment: assignment,
          blocksAsync: blocksAsync,
          titleCtrl: _titleCtrl,
          composer: _composer,
          structureLocked: _structureLocked,
          isAdmin: isAdmin,
          canAuthor: canAuthor,
          showComposer: showComposer,
          studentMode: studentMode,
          viewUid: viewUid,
          viewAsUserId: widget.viewAsUserId,
          ctrlFor: _ctrlFor,
          debounce: _debounce,
          canStudentEdit: _canStudentEdit,
          onSendText: _sendText,
          onAttach: () => _showAttachMenu(canAuthor: canAuthor),
          onPublish: () => _publish(assignment),
          onDeleteBlock: (blockId) =>
              ref.read(assignmentRepositoryProvider).deleteBlock(blockId),
          onTitleChanged: (v) {
            ref.read(assignmentRepositoryProvider).updateAssignmentMeta(
                  assignmentId: id,
                  title: v,
                );
          },
        );
      },
    );
  }
}

class _StudentOrAuthorBody extends ConsumerWidget {
  const _StudentOrAuthorBody({
    required this.circleId,
    required this.assignmentId,
    required this.assignment,
    required this.blocksAsync,
    required this.titleCtrl,
    required this.composer,
    required this.structureLocked,
    required this.isAdmin,
    required this.canAuthor,
    required this.showComposer,
    required this.studentMode,
    required this.viewUid,
    required this.viewAsUserId,
    required this.ctrlFor,
    required this.debounce,
    required this.canStudentEdit,
    required this.onSendText,
    required this.onAttach,
    required this.onPublish,
    required this.onDeleteBlock,
    required this.onTitleChanged,
  });

  final String circleId;
  final String assignmentId;
  final Assignment assignment;
  final AsyncValue<List<AssignmentBlock>> blocksAsync;
  final TextEditingController titleCtrl;
  final TextEditingController composer;
  final bool structureLocked;
  final bool isAdmin;
  final bool canAuthor;
  final bool showComposer;
  final bool studentMode;
  final String? viewUid;
  final String? viewAsUserId;
  final TextEditingController Function(String, String) ctrlFor;
  final Map<String, Timer> debounce;
  final bool Function(Assignment, AssignmentSubmission?) canStudentEdit;
  final VoidCallback onSendText;
  final VoidCallback onAttach;
  final VoidCallback onPublish;
  final ValueChanged<String> onDeleteBlock;
  final ValueChanged<String> onTitleChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answersAsync = viewUid == null
        ? const AsyncValue.data(<BlockAnswer>[])
        : ref.watch(_answersProvider((
            circleId: circleId,
            assignmentId: assignmentId,
            userId: viewUid!,
          )));
    final submissionAsync = viewUid == null
        ? const AsyncValue.data(null)
        : ref.watch(_submissionProvider((
            assignmentId: assignmentId,
            userId: viewUid!,
          )));

    final blocks = blocksAsync.asData?.value ?? const [];
    final answers = {
      for (final a in answersAsync.asData?.value ?? const <BlockAnswer>[])
        a.blockId: a,
    };
    final submission = submissionAsync.asData?.value;
    final requiredBlocks =
        blocks.where((b) => b.isInput && b.required).toList();
    final answeredRequired =
        requiredBlocks.where((b) => answers[b.id]?.hasValue == true).length;
    final editAnswers =
        studentMode && canStudentEdit(assignment, submission);
    final canSubmit = editAnswers &&
        requiredBlocks.every((b) => answers[b.id]?.hasValue == true) &&
        submission?.status != SubmissionStatus.submitted &&
        submission?.status != SubmissionStatus.late;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: brandAppBar(
        title: Text(
          assignment.isDraft ? 'Draft · system chat' : assignment.title,
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (isAdmin && assignment.isDraft)
            TextButton(onPressed: onPublish, child: const Text('Publish')),
          if (isAdmin && assignment.isPublished && viewAsUserId == null)
            IconButton(
              tooltip: 'Roster',
              icon: const Icon(Icons.people_outline),
              onPressed: () => context.push(
                '/circles/$circleId/assignments/$assignmentId/roster',
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (canAuthor)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: onTitleChanged,
              ),
            ),
          if (structureLocked)
            const Material(
              color: AppColors.accentSoft,
              child: Padding(
                padding: EdgeInsets.all(10),
                child: Row(
                  children: [
                    Icon(Icons.lock, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Structure locked — responses already exist',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (assignment.isPublished)
            Material(
              color: AppColors.accentSoft,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (assignment.dueAt != null) ...[
                      const Icon(Icons.schedule, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Due ${assignment.dueAt!.toLocal()}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    Text(
                      '$answeredRequired of ${requiredBlocks.length} answered',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: blocksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (blocks) {
                if (blocks.isEmpty) {
                  return Center(
                    child: Text(
                      canAuthor
                          ? 'Message the system: type below or tap +'
                          : 'No content yet',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                  itemCount: blocks.length,
                  itemBuilder: (context, index) {
                    final block = blocks[index];
                    if (block.isContent) {
                      return _ContentBubble(
                        block: block,
                        canDelete: canAuthor,
                        onDelete: () => onDeleteBlock(block.id),
                      );
                    }
                    return _InputBubble(
                      block: block,
                      answer: answers[block.id],
                      enabled: editAnswers,
                      showAuthorChrome: canAuthor,
                      onDelete:
                          canAuthor ? () => onDeleteBlock(block.id) : null,
                      textController: block.type == 'question'
                          ? ctrlFor(
                              block.id,
                              answers[block.id]?.value['text'] as String? ??
                                  '',
                            )
                          : null,
                      onTextChanged: (text) {
                        debounce[block.id]?.cancel();
                        debounce[block.id] = Timer(
                          const Duration(milliseconds: 600),
                          () {
                            ref
                                .read(assignmentRepositoryProvider)
                                .upsertAnswer(
                                  circleId: circleId,
                                  assignmentId: assignmentId,
                                  blockId: block.id,
                                  userId: viewUid!,
                                  value: {'text': text},
                                  blocks: blocks,
                                );
                          },
                        );
                      },
                      onChoiceChanged: (ids) {
                        ref.read(assignmentRepositoryProvider).upsertAnswer(
                              circleId: circleId,
                              assignmentId: assignmentId,
                              blockId: block.id,
                              userId: viewUid!,
                              value: {'selectedOptionIds': ids},
                              blocks: blocks,
                            );
                      },
                    );
                  },
                );
              },
            ),
          ),
          if (showComposer) _ComposerBar(
            controller: composer,
            onAttach: onAttach,
            onSend: onSendText,
          ),
          if (studentMode && viewAsUserId == null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canSubmit
                        ? () async {
                            try {
                              await ref
                                  .read(assignmentRepositoryProvider)
                                  .submitAssignment(
                                    circleId: circleId,
                                    assignmentId: assignmentId,
                                    userId: viewUid!,
                                    blocks: blocks,
                                    assignment: assignment,
                                  );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Submitted'),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$e')),
                                );
                              }
                            }
                          }
                        : null,
                    child: Text(
                      submission?.status == SubmissionStatus.submitted ||
                              submission?.status == SubmissionStatus.late
                          ? 'Submitted'
                          : 'Submit',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final _answersProvider = StreamProvider.autoDispose.family<
    List<BlockAnswer>,
    ({String circleId, String assignmentId, String userId})>((ref, key) {
  return ref.watch(assignmentRepositoryProvider).watchMyAnswers(
        circleId: key.circleId,
        assignmentId: key.assignmentId,
        userId: key.userId,
      );
});

final _submissionProvider = StreamProvider.autoDispose.family<
    AssignmentSubmission?,
    ({String assignmentId, String userId})>((ref, key) {
  return ref.watch(assignmentRepositoryProvider).watchMySubmission(
        assignmentId: key.assignmentId,
        userId: key.userId,
      );
});

class _ComposerBar extends StatelessWidget {
  const _ComposerBar({
    required this.controller,
    required this.onAttach,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onAttach;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Add',
                onPressed: onAttach,
                icon: const Icon(Icons.add_circle_outline),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'Message the assignment…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                onPressed: onSend,
                icon: const Icon(Icons.send),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.textOnDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentBubble extends StatelessWidget {
  const _ContentBubble({
    required this.block,
    required this.canDelete,
    required this.onDelete,
  });

  final AssignmentBlock block;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget child;
    switch (block.type) {
      case 'link':
        final url = block.payload['url'] as String? ?? '';
        final label = (block.payload['label'] as String?)?.trim();
        child = InkWell(
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Text(
            label?.isNotEmpty == true ? label! : url,
            style: const TextStyle(
              color: AppColors.accent,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      case 'media':
        final kind = block.payload['mediaKind'] as String? ?? 'file';
        final url = block.payload['downloadUrl'] as String?;
        final name = block.payload['fileName'] as String? ?? kind;
        if (kind == 'image' && url != null) {
          child = ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url, fit: BoxFit.cover),
          );
        } else {
          child = Row(
            children: [
              const Icon(Icons.attach_file, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(name)),
            ],
          );
        }
      case 'text':
      default:
        child = Text(block.payload['body'] as String? ?? '');
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 40),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bubbleIn,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            child,
            if (canDelete)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InputBubble extends StatelessWidget {
  const _InputBubble({
    required this.block,
    required this.answer,
    required this.enabled,
    required this.showAuthorChrome,
    this.onDelete,
    this.textController,
    this.onTextChanged,
    this.onChoiceChanged,
  });

  final AssignmentBlock block;
  final BlockAnswer? answer;
  final bool enabled;
  final bool showAuthorChrome;
  final VoidCallback? onDelete;
  final TextEditingController? textController;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<List<String>>? onChoiceChanged;

  @override
  Widget build(BuildContext context) {
    final prompt = block.payload['prompt'] as String? ?? block.type;
    final selected = List<String>.from(
      (answer?.value['selectedOptionIds'] as List?) ?? const [],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (block.required)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.lock, size: 16, color: AppColors.accent),
                ),
              Expanded(
                child: Text(
                  prompt,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (onDelete != null)
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          if (showAuthorChrome)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Needs a response · ${block.type}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (block.type == 'question')
            TextField(
              controller: textController,
              enabled: enabled,
              maxLines: block.payload['longAnswer'] == true ? 5 : 1,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Your answer',
              ),
              onChanged: onTextChanged,
            )
          else if (block.type == 'singleChoice' ||
              block.type == 'multipleChoice')
            ..._choices(selected)
          else if (block.type == 'upload')
            Text(
              enabled
                  ? 'Upload from device (attach after publish)'
                  : 'Upload',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }

  List<Widget> _choices(List<String> selected) {
    final options = (block.payload['options'] as List?) ?? const [];
    final multi = block.type == 'multipleChoice';
    return [
      for (final raw in options)
        if (raw is Map)
          multi
              ? CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: selected.contains(raw['id']),
                  title: Text('${raw['label'] ?? ''}'),
                  onChanged: !enabled
                      ? null
                      : (v) {
                          final next = [...selected];
                          final id = raw['id'] as String;
                          if (v == true) {
                            if (!next.contains(id)) next.add(id);
                          } else {
                            next.remove(id);
                          }
                          onChoiceChanged?.call(next);
                        },
                )
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    selected.isNotEmpty && selected.first == raw['id']
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: AppColors.accent,
                  ),
                  title: Text('${raw['label'] ?? ''}'),
                  onTap: !enabled
                      ? null
                      : () =>
                          onChoiceChanged?.call([raw['id'] as String]),
                ),
    ];
  }
}
