import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../core/utils/download_helper.dart';
import '../../core/widgets/user_identity.dart';
import '../../data/repositories/agent_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/circle_repository.dart';
import '../../data/repositories/media_repository.dart';
import '../../data/repositories/post_repository.dart';
import '../../domain/models/circle.dart';
import '../../domain/models/post.dart';
import '../coins/assignment_sheet.dart';

/// Stream media preview max edge (images / PDF covers).
const double kStreamPreviewMaxSide = 320;

/// Bubble outer max width ≈ image preview + horizontal padding (12+12).
const double kMessageBubbleMaxWidth = kStreamPreviewMaxSide + 24;

const _kQuickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

final _circleProvider =
    StreamProvider.autoDispose.family<Circle?, String>((ref, circleId) {
  return ref.watch(circleRepositoryProvider).watchCircle(circleId);
});

final _membershipProvider = StreamProvider.autoDispose
    .family<Membership?, ({String circleId, String userId})>((ref, key) {
  return ref.watch(circleRepositoryProvider).watchMembership(
        circleId: key.circleId,
        userId: key.userId,
      );
});

final _postsProvider =
    StreamProvider.autoDispose.family<List<CirclePost>, String>((ref, circleId) {
  return ref.watch(postRepositoryProvider).watchPosts(circleId);
});

class ThreadScreen extends ConsumerStatefulWidget {
  const ThreadScreen({super.key, required this.circleId});

  final String circleId;

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final _composer = TextEditingController();
  final _scrollController = ScrollController();
  final _composerFocus = FocusNode();
  bool _sending = false;
  String? _pendingLocalId;
  String? _sendError;
  bool _recording = false;
  bool _recordCancelHint = false;
  DateTime? _recordStartedAt;
  Offset? _micDownOrigin;
  Timer? _recordTicker;
  int _lastFeedCount = 0;
  bool _forceScrollToBottom = false;
  bool _didInitialScroll = false;
  PostReplyTo? _replyTo;
  bool _emojiPickerOpen = false;

  static const _nearBottomPx = 120.0;

  @override
  void initState() {
    super.initState();
    _composer.addListener(() {
      if (mounted) setState(() {});
    });
    _composerFocus.addListener(() {
      if (_composerFocus.hasFocus && _emojiPickerOpen) {
        setState(() => _emojiPickerOpen = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _markOpened());
  }

  Future<void> _markOpened() async {
    final uid = ref.read(authStateProvider).asData?.value?.uid;
    if (uid == null) return;
    try {
      await ref.read(circleRepositoryProvider).markCircleOpened(
            circleId: widget.circleId,
            userId: uid,
          );
    } catch (e) {
      // Best-effort; home badge may stay until next successful open.
      debugPrint('markCircleOpened failed: $e');
    }
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    _scrollController.dispose();
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= _nearBottomPx;
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
      // Second frame: pending bubble / media layout may grow extent.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final again = _scrollController.position.maxScrollExtent;
        if ((_scrollController.position.pixels - again).abs() > 1) {
          _scrollController.jumpTo(again);
        }
      });
    });
  }

  void _maybeFollowFeed({required int feedItemCount}) {
    final grew = feedItemCount > _lastFeedCount;
    final firstOpen = !_didInitialScroll && feedItemCount > 0;
    final shouldScroll =
        firstOpen || (grew && (_forceScrollToBottom || _isNearBottom));

    _lastFeedCount = feedItemCount;
    if (!shouldScroll) {
      _forceScrollToBottom = false;
      return;
    }

    final jump = firstOpen;
    _forceScrollToBottom = false;
    _didInitialScroll = true;
    _scrollToBottom(animated: !jump);
  }

  void _setReply(CirclePost post) {
    setState(() {
      _replyTo = PostReplyTo.fromPost(post);
      _emojiPickerOpen = false;
    });
    _composerFocus.requestFocus();
  }

  void _clearReply() => setState(() => _replyTo = null);

  void _toggleEmojiPicker() {
    final open = !_emojiPickerOpen;
    setState(() => _emojiPickerOpen = open);
    if (open) {
      _composerFocus.unfocus();
    } else {
      _composerFocus.requestFocus();
    }
  }

  Future<void> _react({
    required String postId,
    required String uid,
    required String emoji,
  }) async {
    try {
      await ref.read(postRepositoryProvider).toggleReaction(
            circleId: widget.circleId,
            postId: postId,
            userId: uid,
            emoji: emoji,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendError = _friendlySendError(e));
    }
  }

  Future<void> _showPostActions(CirclePost post, String uid) async {
    if (post.id.startsWith('local-')) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final emoji in _kQuickReactionEmojis)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              Navigator.pop(ctx);
                              _react(postId: post.id, uid: uid, emoji: emoji);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(emoji, style: const TextStyle(fontSize: 28)),
                            ),
                          ),
                        ),
                      IconButton(
                        tooltip: 'More emoji',
                        onPressed: () {
                          Navigator.pop(ctx);
                          _pickReactionEmoji(post.id, uid);
                        },
                        icon: const Icon(Icons.add_reaction_outlined),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.reply),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _setReply(post);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickReactionEmoji(String postId, String uid) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 360,
            child: EmojiPicker(
              onEmojiSelected: (category, emoji) {
                Navigator.pop(ctx, emoji.emoji);
              },
              config: Config(
                height: 320,
                checkPlatformCompatibility: true,
                emojiViewConfig: EmojiViewConfig(
                  emojiSizeMax: 28 *
                      (foundation.defaultTargetPlatform == TargetPlatform.iOS
                          ? 1.20
                          : 1.0),
                  backgroundColor: AppColors.bgElevated,
                ),
                categoryViewConfig: const CategoryViewConfig(
                  indicatorColor: AppColors.accent,
                  iconColorSelected: AppColors.accent,
                ),
                bottomActionBarConfig: const BottomActionBarConfig(
                  enabled: false,
                ),
                skinToneConfig: const SkinToneConfig(),
              ),
            ),
          ),
        );
      },
    );
    if (emoji == null || emoji.isEmpty) return;
    await _react(postId: postId, uid: uid, emoji: emoji);
  }

  void _onComposerEmojiSelected(Emoji emoji) {
    final text = _composer.text;
    final selection = _composer.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final next = text.replaceRange(start, end, emoji.emoji);
    _composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.emoji.length),
    );
  }

  Future<void> _sendEmojiOnly(String uid, String emoji) async {
    if (_sending || emoji.trim().isEmpty) return;
    final reply = _replyTo;
    setState(() {
      _sending = true;
      _sendError = null;
      _pendingLocalId = 'local-emoji-${DateTime.now().millisecondsSinceEpoch}';
      _forceScrollToBottom = true;
      _emojiPickerOpen = false;
    });
    _scrollToBottom();
    try {
      await ref.read(postRepositoryProvider).sendEmojiPost(
            circleId: widget.circleId,
            authorId: uid,
            emoji: emoji,
            replyTo: reply,
          );
      _composer.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      setState(() => _sendError = _friendlySendError(e));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingLocalId = null;
        });
      }
    }
  }

  Future<void> _send({required String uid}) async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;

    final reply = _replyTo;
    final emojiOnly = looksLikeEmojiOnly(body);

    setState(() {
      _sending = true;
      _sendError = null;
      _pendingLocalId = emojiOnly
          ? 'local-emoji-${DateTime.now().millisecondsSinceEpoch}'
          : 'local-${DateTime.now().millisecondsSinceEpoch}';
      _forceScrollToBottom = true;
      _emojiPickerOpen = false;
    });
    _scrollToBottom();

    try {
      if (emojiOnly) {
        await ref.read(postRepositoryProvider).sendEmojiPost(
              circleId: widget.circleId,
              authorId: uid,
              emoji: body,
              replyTo: reply,
            );
      } else {
        await ref.read(postRepositoryProvider).sendPost(
              circleId: widget.circleId,
              authorId: uid,
              type: PostType.free,
              body: body,
              replyTo: reply,
            );
      }
      _composer.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      setState(() => _sendError = _friendlySendError(e));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingLocalId = null;
        });
      }
    }
  }

  Future<void> _attachImage(String uid, {bool fromCamera = false}) async {
    if (_sending) return;
    setState(() {
      _sendError = null;
      _sending = true;
      _pendingLocalId = 'local-media-${DateTime.now().millisecondsSinceEpoch}';
      _forceScrollToBottom = true;
    });
    _scrollToBottom();
    try {
      final media = ref.read(mediaRepositoryProvider);
      final picked = fromCamera
          ? await media.pickCameraPhoto()
          : await media.pickCompressedImage();
      if (picked == null) {
        setState(() => _pendingLocalId = null);
        return;
      }
      await ref.read(postRepositoryProvider).sendMediaPost(
            circleId: widget.circleId,
            authorId: uid,
            image: picked,
            caption: _composer.text,
            replyTo: _replyTo,
          );
      _composer.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      setState(() => _sendError = _friendlySendError(e));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingLocalId = null;
        });
      }
    }
  }

  Future<void> _attachVideo(String uid) async {
    if (_sending) return;
    setState(() {
      _sendError = null;
      _sending = true;
      _pendingLocalId = 'local-video-${DateTime.now().millisecondsSinceEpoch}';
      _forceScrollToBottom = true;
    });
    _scrollToBottom();
    try {
      final picked =
          await ref.read(mediaRepositoryProvider).pickCameraVideo();
      if (picked == null) {
        setState(() => _pendingLocalId = null);
        return;
      }
      await ref.read(postRepositoryProvider).sendVideoPost(
            circleId: widget.circleId,
            authorId: uid,
            video: picked,
            caption: _composer.text,
            replyTo: _replyTo,
          );
      _composer.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      setState(() => _sendError = _friendlySendError(e));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingLocalId = null;
        });
      }
    }
  }

  Future<void> _attachPdf(String uid) async {
    if (_sending) return;
    setState(() {
      _sendError = null;
      _sending = true;
      _pendingLocalId = 'local-pdf-${DateTime.now().millisecondsSinceEpoch}';
      _forceScrollToBottom = true;
    });
    _scrollToBottom();
    try {
      final picked = await ref.read(mediaRepositoryProvider).pickPdf();
      if (picked == null) {
        setState(() => _pendingLocalId = null);
        return;
      }
      await ref.read(postRepositoryProvider).sendPdfPost(
            circleId: widget.circleId,
            authorId: uid,
            pdf: picked,
            caption: _composer.text,
            replyTo: _replyTo,
          );
      _composer.clear();
      setState(() => _replyTo = null);
    } catch (e) {
      setState(() => _sendError = _friendlySendError(e));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingLocalId = null;
        });
      }
    }
  }

  Future<void> _startVoice(String uid) async {
    if (_sending || _recording) return;
    try {
      await ref.read(mediaRepositoryProvider).startVoiceNote();
      if (!mounted) return;
      _recordTicker?.cancel();
      _recordTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final start = _recordStartedAt;
        if (start != null &&
            DateTime.now().difference(start).inMilliseconds >=
                kMaxVoiceNoteMs) {
          _finishVoice(uid, cancel: false);
          return;
        }
        setState(() {});
      });
      setState(() {
        _recording = true;
        _recordCancelHint = false;
        _recordStartedAt = DateTime.now();
        _sendError = null;
      });
    } catch (e) {
      setState(() => _sendError = _friendlySendError(e));
    }
  }

  Future<void> _finishVoice(String uid, {required bool cancel}) async {
    if (!_recording) return;
    _recordTicker?.cancel();
    _recordTicker = null;
    setState(() => _recording = false);
    try {
      final picked = await ref.read(mediaRepositoryProvider).stopVoiceNote(
            cancel: cancel,
          );
      if (picked == null || cancel) return;
      setState(() {
        _sending = true;
        _pendingLocalId = 'local-audio-${DateTime.now().millisecondsSinceEpoch}';
        _forceScrollToBottom = true;
      });
      _scrollToBottom();
      await ref.read(postRepositoryProvider).sendAudioPost(
            circleId: widget.circleId,
            authorId: uid,
            audio: picked,
            replyTo: _replyTo,
          );
      if (mounted) setState(() => _replyTo = null);
    } catch (e) {
      if (mounted) setState(() => _sendError = _friendlySendError(e));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _pendingLocalId = null;
          _recordStartedAt = null;
          _recordCancelHint = false;
        });
      }
    }
  }

  void _showAttachMenu(String uid, {required bool isAdmin}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachImage(uid);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachImage(uid, fromCamera: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Video'),
                subtitle: const Text('Up to 60 s'),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachVideo(uid);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Document'),
                subtitle: const Text('PDF'),
                onTap: () {
                  Navigator.pop(ctx);
                  _attachPdf(uid);
                },
              ),
              if (isAdmin) ...[
                ListTile(
                  leading: const Icon(Icons.spa_outlined),
                  title: const Text('Challenge'),
                  subtitle: const Text('Create a media or quest challenge'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/circles/${widget.circleId}/challenges/new');
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.assignment_outlined),
                  title: const Text('Assignment'),
                  subtitle: const Text('Create objectives for the circle'),
                  onTap: () {
                    Navigator.pop(ctx);
                    showCreateAssignmentDialog(
                      context: context,
                      ref: ref,
                      circleId: widget.circleId,
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _friendlySendError(Object e) {
    final raw = e.toString();
    if (raw.contains('object-not-found') ||
        raw.contains('bucket') ||
        raw.contains('storage/')) {
      return 'Could not upload the file. Is Firebase Storage enabled '
          'on the circulo-mvp project?';
    }
    if (raw.contains('Permission') ||
        raw.contains('permission') ||
        raw.contains('micrófono') ||
        raw.contains('NotAllowedError')) {
      return 'Microphone or camera permission is required to continue.';
    }
    if (raw.contains('StateError:') || raw.contains('Bad state:')) {
      return raw
          .replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '');
    }
    return raw;
  }

  String get _recordElapsedLabel {
    final start = _recordStartedAt;
    if (start == null) return '0:00';
    return formatDurationMs(DateTime.now().difference(start).inMilliseconds);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final circleAsync = ref.watch(_circleProvider(widget.circleId));
    final postsAsync = ref.watch(_postsProvider(widget.circleId));
    final membershipAsync = uid == null
        ? const AsyncValue<Membership?>.data(null)
        : ref.watch(
            _membershipProvider((circleId: widget.circleId, userId: uid)),
          );
    final isAdmin = membershipAsync.asData?.value?.isAdmin == true;

    return Scaffold(
      appBar: brandAppBar(
        title: circleAsync.when(
          data: (c) => Text(
            c?.name ?? 'Circle',
            style: brandDisplay(fontWeight: FontWeight.w600),
          ),
          loading: () => const Text('…'),
          error: (_, _) => const Text('Circle'),
        ),
        actions: [
          IconButton(
            tooltip: 'Challenges',
            icon: const Icon(Icons.spa_outlined),
            onPressed: () =>
                context.push('/circles/${widget.circleId}/challenges'),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => context.push('/circles/${widget.circleId}/info'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: postsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (posts) {
                final sticky = posts.where((p) => p.isSticky).toList();
                final feed = posts.where((p) => !p.isSticky).toList();
                final resources = posts
                    .where((p) => p.type == PostType.resource)
                    .toList()
                    .reversed
                    .take(3)
                    .toList();
                final feedItemCount =
                    feed.length + (_pendingLocalId != null ? 1 : 0);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _maybeFollowFeed(feedItemCount: feedItemCount);
                });

                return CustomScrollView(
                  controller: _scrollController,
                  reverse: false,
                  slivers: [
                    if (sticky.isNotEmpty || resources.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _StickyHeader(
                          instructions: sticky,
                          resources: resources,
                        ),
                      ),
                    if (feed.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Text(
                            'Be the first to write',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final post = feed[index];
                            final mine = post.authorId == uid;
                            return _PostBubble(
                              post: post,
                              mine: mine,
                              circleId: widget.circleId,
                              uid: uid,
                              onLongPress: uid == null
                                  ? null
                                  : () => _showPostActions(post, uid),
                              onReply: uid == null
                                  ? null
                                  : () => _setReply(post),
                              onReact: uid == null
                                  ? null
                                  : (emoji) => _react(
                                        postId: post.id,
                                        uid: uid,
                                        emoji: emoji,
                                      ),
                            );
                          },
                          childCount: feed.length,
                        ),
                      ),
                    if (_pendingLocalId != null)
                      SliverToBoxAdapter(
                        child: Builder(
                          builder: (_) {
                            final id = _pendingLocalId!;
                            final isEmoji = id.contains('emoji') ||
                                looksLikeEmojiOnly(_composer.text);
                            final isMedia = id.contains('media') ||
                                id.contains('pdf') ||
                                id.contains('video') ||
                                id.contains('audio');
                            final kind = id.contains('emoji')
                                ? 'emoji'
                                : id.contains('pdf')
                                    ? 'pdf'
                                    : id.contains('video')
                                        ? 'video'
                                        : id.contains('audio')
                                            ? 'audio'
                                            : isMedia
                                                ? 'image'
                                                : isEmoji
                                                    ? 'emoji'
                                                    : 'text';
                            return _PostBubble(
                              post: CirclePost(
                                id: id,
                                authorId: uid ?? '',
                                type: isMedia ? PostType.media : PostType.free,
                                body: _composer.text,
                                createdAt: DateTime.now(),
                                status: PostStatus.pending,
                                replyTo: _replyTo,
                                meta: {
                                  'kind': kind,
                                  if (kind == 'pdf' || kind == 'video')
                                    'coverStatus': 'pending',
                                },
                              ),
                              mine: true,
                              circleId: widget.circleId,
                              uid: uid,
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (_recording)
            Container(
              width: double.infinity,
              color: AppColors.bgElevated,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.mic, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Text(
                    _recordElapsedLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    _recordCancelHint
                        ? 'Release to cancel'
                        : 'Slide to cancel',
                    style: TextStyle(
                      color: _recordCancelHint
                          ? AppColors.danger
                          : AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          if (_sendError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _sendError!,
                style: const TextStyle(color: AppColors.danger, fontSize: 12),
              ),
            ),
          _ComposerBar(
            controller: _composer,
            focusNode: _composerFocus,
            sending: _sending,
            recording: _recording,
            replyTo: _replyTo,
            emojiPickerOpen: _emojiPickerOpen,
            myUid: uid,
            onClearReply: _clearReply,
            onToggleEmojiPicker: _toggleEmojiPicker,
            onEmojiSelected: _onComposerEmojiSelected,
            onSendEmojiOnly: uid == null
                ? null
                : (emoji) => _sendEmojiOnly(uid, emoji),
            onSend: uid == null ? null : () => _send(uid: uid),
            onAttach: uid == null
                ? null
                : () => _showAttachMenu(uid, isAdmin: isAdmin),
            onMicPointerDown: uid == null
                ? null
                : (details) {
                    _micDownOrigin = details.position;
                    _startVoice(uid);
                  },
            onMicPointerMove: uid == null
                ? null
                : (details) {
                    final origin = _micDownOrigin;
                    if (origin == null) return;
                    final cancel = (origin.dx - details.position.dx) > 56;
                    if (cancel != _recordCancelHint) {
                      setState(() => _recordCancelHint = cancel);
                    }
                  },
            onMicPointerUp: uid == null
                ? null
                : (_) => _finishVoice(uid, cancel: _recordCancelHint),
            onMicPointerCancel: uid == null
                ? null
                : () => _finishVoice(uid, cancel: true),
          ),
        ],
      ),
    );
  }
}

class _StickyHeader extends StatelessWidget {
  const _StickyHeader({
    required this.instructions,
    required this.resources,
  });

  final List<CirclePost> instructions;
  final List<CirclePost> resources;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.bgElevated,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in instructions)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.hairline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Instruction',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  Text(p.body, style: messageBodyStyle()),
                ],
              ),
            ),
          for (final r in resources)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.link, color: AppColors.accent),
              title: Text(r.body, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () async {
                final url = r.meta['url']?.toString() ?? r.body;
                final uri = Uri.tryParse(url);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _PostBubble extends ConsumerWidget {
  const _PostBubble({
    required this.post,
    required this.mine,
    required this.circleId,
    this.uid,
    this.onLongPress,
    this.onReply,
    this.onReact,
  });

  final CirclePost post;
  final bool mine;
  final String circleId;
  final String? uid;
  final VoidCallback? onLongPress;
  final VoidCallback? onReply;
  final ValueChanged<String>? onReact;

  Future<void> _downloadPdf(WidgetRef ref) async {
    final bytes = await ref.read(mediaRepositoryProvider).downloadBytes(
          storagePath: post.storagePath,
          downloadUrl: post.mediaUrl,
        );
    final name = post.fileName ?? 'document.pdf';
    await saveOrShareFile(
      bytes: bytes,
      fileName: name,
      mimeType: 'application/pdf',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emojiOnly = post.isEmojiMedia &&
        !post.isImageMedia &&
        !post.isPdfMedia &&
        !post.isAudioMedia &&
        !post.isVideoMedia;
    final reactions = ref.watch(
      postReactionsProvider((
        circleId: circleId,
        postId: post.id,
        uid: uid,
      )),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2, right: 2),
              child: UserIdentityChip(
                userId: post.authorId,
                myUid: uid,
              ),
            ),
            GestureDetector(
              onLongPress: onLongPress,
              onDoubleTap: onReply,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  emojiOnly ? 10 : 12,
                  emojiOnly ? 6 : 8,
                  emojiOnly ? 10 : 12,
                  emojiOnly ? 6 : 8,
                ),
                constraints:
                    const BoxConstraints(maxWidth: kMessageBubbleMaxWidth),
                decoration: BoxDecoration(
                  color: emojiOnly
                      ? Colors.transparent
                      : (mine ? AppColors.bubbleOut : AppColors.bubbleIn),
                  borderRadius: BorderRadius.circular(18),
                  border: mine || emojiOnly
                      ? null
                      : Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!emojiOnly &&
                        showBubbleTypeLabel(post.type, kind: post.kind))
                      Text(
                        postTypeLabel(post.type, kind: post.kind),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent,
                        ),
                      ),
                    if (post.replyTo != null) ...[
                      if (!emojiOnly) const SizedBox(height: 4),
                      _ReplyQuote(
                        replyTo: post.replyTo!,
                        mine: mine,
                        myUid: uid,
                      ),
                    ],
                    if (post.isImageMedia && post.hasMediaRef) ...[
                      const SizedBox(height: 6),
                      _ImageStreamPreview(post: post),
                    ],
                    if (post.isPdfMedia) ...[
                      const SizedBox(height: 6),
                      _PdfAttachmentCard(
                        post: post,
                        onDownload: () => _downloadPdf(ref),
                      ),
                    ],
                    if (post.isAudioMedia) ...[
                      const SizedBox(height: 6),
                      _AudioPostBubble(post: post),
                    ],
                    if (post.isVideoMedia) ...[
                      const SizedBox(height: 6),
                      _VideoPostBubble(post: post),
                    ],
                    if (post.body.isNotEmpty) ...[
                      if (post.isImageMedia ||
                          post.isPdfMedia ||
                          post.isAudioMedia ||
                          post.isVideoMedia)
                        const SizedBox(height: 6),
                      Text(
                        post.body,
                        style: emojiOnly
                            ? const TextStyle(fontSize: 48, height: 1.1)
                            : messageBodyStyle(),
                      ),
                    ] else if (post.isImageMedia && !post.hasMediaRef)
                      Text(
                        'Image…',
                        style:
                            messageBodyStyle(color: AppColors.textSecondary),
                      )
                    else if (post.isPdfMedia && !post.hasMediaRef)
                      Text(
                        'PDF…',
                        style:
                            messageBodyStyle(color: AppColors.textSecondary),
                      )
                    else if (post.isAudioMedia && !post.hasMediaRef)
                      Text(
                        'Audio…',
                        style:
                            messageBodyStyle(color: AppColors.textSecondary),
                      )
                    else if (post.isVideoMedia && !post.hasMediaRef)
                      Text(
                        'Video…',
                        style:
                            messageBodyStyle(color: AppColors.textSecondary),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(post.createdAt),
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 4),
                          Icon(
                            post.status == PostStatus.pending
                                ? Icons.schedule
                                : post.status == PostStatus.failed
                                    ? Icons.error_outline
                                    : Icons.done_all,
                            size: 14,
                            color: post.status == PostStatus.failed
                                ? AppColors.danger
                                : AppColors.textSecondary,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            reactions.when(
              data: (summary) {
                if (summary.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _ReactionChips(
                    summary: summary,
                    onTap: onReact,
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            _AgentActionRow(circleId: circleId, post: post),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _AgentActionRow extends ConsumerStatefulWidget {
  const _AgentActionRow({
    required this.circleId,
    required this.post,
  });

  final String circleId;
  final CirclePost post;

  @override
  ConsumerState<_AgentActionRow> createState() => _AgentActionRowState();
}

class _AgentActionRowState extends ConsumerState<_AgentActionRow> {
  String? _busyActionId;

  Future<void> _onAction(String actionId) async {
    final post = widget.post;
    if (actionId == 'open_pr') {
      final url = post.agentPrUrl;
      if (url == null || url.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No PR URL yet')),
          );
        }
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null) return;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    String? followUp;
    if (actionId == 'continue') {
      followUp = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController(text: 'Continue from last result');
          return AlertDialog(
            title: const Text('Continue'),
            content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Follow-up prompt',
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );
      if (followUp == null || followUp.isEmpty) return;
    }

    setState(() => _busyActionId = actionId);
    try {
      await ref.read(agentRepositoryProvider).agentAction(
            circleId: widget.circleId,
            postId: post.id,
            actionId: actionId,
            followUp: followUp,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              actionId == 'retry' ? 'Retry started' : 'Continue started',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Agent action failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyActionId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = ref.watch(appUserProvider(widget.post.authorId)).asData?.value;
    final show = widget.post.hasAgentMeta || author?.isAgent == true;
    if (!show) return const SizedBox.shrink();

    final actions = widget.post.agentActions.isNotEmpty
        ? widget.post.agentActions
        : const [
            (id: 'continue', label: 'Continue'),
            (id: 'open_pr', label: 'Open PR'),
            (id: 'retry', label: 'Retry'),
          ];

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final a in actions)
            OutlinedButton(
              onPressed: _busyActionId != null
                  ? null
                  : (a.id == 'open_pr' &&
                          (widget.post.agentPrUrl == null ||
                              widget.post.agentPrUrl!.isEmpty))
                      ? null
                      : () => _onAction(a.id),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: _busyActionId == a.id
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(a.label),
            ),
        ],
      ),
    );
  }
}

class _ReplyQuote extends ConsumerWidget {
  const _ReplyQuote({
    required this.replyTo,
    required this.mine,
    this.myUid,
  });

  final PostReplyTo replyTo;
  final bool mine;
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = replyTo.kind == 'emoji'
        ? replyTo.preview
        : replyTo.preview.isEmpty
            ? postTypeLabel(PostType.free, kind: replyTo.kind)
            : replyTo.preview;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: mine ? AppColors.accentSoft : AppColors.bgApp,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserIdentityChip(
            userId: replyTo.authorId,
            myUid: myUid,
          ),
          const SizedBox(height: 2),
          Text(
            preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: replyTo.kind == 'emoji' ? 18 : 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionChips extends StatelessWidget {
  const _ReactionChips({
    required this.summary,
    this.onTap,
  });

  final ReactionSummary summary;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final entries = summary.counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final e in entries)
          Material(
            color: e.key == summary.myEmoji
                ? AppColors.accentSoft
                : AppColors.bgElevated,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap == null ? null : () => onTap!(e.key),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: e.key == summary.myEmoji
                        ? AppColors.accent
                        : AppColors.hairline,
                  ),
                ),
                child: Text(
                  '${e.key} ${e.value}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PdfAttachmentCard extends StatefulWidget {
  const _PdfAttachmentCard({
    required this.post,
    required this.onDownload,
  });

  final CirclePost post;
  final Future<void> Function() onDownload;

  @override
  State<_PdfAttachmentCard> createState() => _PdfAttachmentCardState();
}

class _PdfAttachmentCardState extends State<_PdfAttachmentCard> {
  bool _downloading = false;
  String? _downloadError;

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadError = null;
    });
    try {
      await widget.onDownload();
    } catch (e) {
      if (mounted) {
        setState(() => _downloadError = 'Could not download the PDF');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final fileName = post.fileName ?? 'document.pdf';
    final ready = post.coverStatus == 'ready' && post.hasCoverRef;
    final failed = post.coverStatus == 'failed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: kStreamPreviewMaxSide,
              maxHeight: kStreamPreviewMaxSide,
            ),
            child: ready
                ? _StoragePostImage(
                    cacheKey: '${post.id}-cover',
                    storagePath: post.coverStoragePath,
                    downloadUrl: post.coverDownloadUrl,
                    maxSide: kStreamPreviewMaxSide,
                  )
                : Container(
                    width: kStreamPreviewMaxSide,
                    height: 120,
                    color: AppColors.bgElevated,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          failed
                              ? Icons.picture_as_pdf_outlined
                              : Icons.picture_as_pdf,
                          size: 36,
                          color: AppColors.accent,
                        ),
                        const SizedBox(height: 8),
                        if (!failed)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Text(
                            'No cover',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.picture_as_pdf, size: 18, color: AppColors.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Download PDF',
              onPressed: post.hasMediaRef && !_downloading
                  ? _handleDownload
                  : null,
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
            ),
          ],
        ),
        if (_downloadError != null)
          Text(
            _downloadError!,
            style: const TextStyle(color: AppColors.danger, fontSize: 11),
          ),
      ],
    );
  }
}

class _AudioPostBubble extends ConsumerStatefulWidget {
  const _AudioPostBubble({required this.post});

  final CirclePost post;

  @override
  ConsumerState<_AudioPostBubble> createState() => _AudioPostBubbleState();
}

class _AudioPostBubbleState extends ConsumerState<_AudioPostBubble> {
  final _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = widget.post.mediaUrl;
      if (url != null && url.isNotEmpty) {
        await _player.play(UrlSource(url));
      } else {
        final bytes = await ref.read(mediaRepositoryProvider).downloadBytes(
              storagePath: widget.post.storagePath,
              downloadUrl: widget.post.mediaUrl,
              maxSize: kMaxAudioBytes,
            );
        await _player.play(BytesSource(bytes));
      }
      if (mounted) setState(() => _playing = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not play audio');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filled(
          onPressed: widget.post.hasMediaRef ? _toggle : null,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatDurationMs(widget.post.durationMs),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VideoPostBubble extends ConsumerStatefulWidget {
  const _VideoPostBubble({required this.post});

  final CirclePost post;

  @override
  ConsumerState<_VideoPostBubble> createState() => _VideoPostBubbleState();
}

class _VideoPostBubbleState extends ConsumerState<_VideoPostBubble> {
  bool _opening = false;

  Future<void> _openPlayer() async {
    if (_opening || !widget.post.hasMediaRef) return;
    setState(() => _opening = true);
    try {
      final url = widget.post.mediaUrl;
      if (url == null || url.isEmpty) {
        throw StateError('Video has no URL');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => _VideoPlayerDialog(url: url),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play the video')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final ready = post.coverStatus == 'ready' && post.hasCoverRef;
    final failed = post.coverStatus == 'failed';

    return GestureDetector(
      onTap: _openPlayer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (ready)
              _StoragePostImage(
                cacheKey: '${post.id}-cover',
                storagePath: post.coverStoragePath,
                downloadUrl: post.coverDownloadUrl,
              )
            else
              Container(
                height: 160,
                width: double.infinity,
                color: AppColors.bgElevated,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.videocam_outlined,
                      size: 36,
                      color: AppColors.accent,
                    ),
                    const SizedBox(height: 8),
                    if (!failed && post.coverStatus == 'pending')
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Text(
                        'Video',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(10),
              child: _opening
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 28,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  const _VideoPlayerDialog({required this.url});

  final String url;

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((Object e) {
        if (mounted) setState(() => _error = 'Could not load the video');
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: AspectRatio(
        aspectRatio: _ready ? _controller.value.aspectRatio : 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_error != null)
              Text(_error!)
            else if (!_ready)
              const CircularProgressIndicator()
            else
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
                child: VideoPlayer(_controller),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads chat images via Firebase Storage SDK (authenticated), with
/// [Image.network] only as a last-resort fallback. Bytes are cached in
/// [MediaRepository] (memory + disk) so previously seen media reloads instantly.
/// Stream thumbnail: prefers server `preview.jpg` (≤320); falls back to original.
class _ImageStreamPreview extends StatelessWidget {
  const _ImageStreamPreview({required this.post});

  final CirclePost post;

  void _openLarge(BuildContext context) {
    final path = post.hasLargeRef
        ? post.largeStoragePath
        : post.storagePath;
    final url = post.hasLargeRef
        ? post.largeDownloadUrl
        : post.mediaUrl;
    if (path == null && (url == null || url.isEmpty)) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => _ImageLargeDialog(
        cacheKey: '${post.id}-large',
        storagePath: path,
        downloadUrl: url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewReady = post.hasPreviewRef && post.previewStatus == 'ready';
    final previewPending = post.previewStatus == 'pending';
    final useOriginalFallback =
        !previewReady && (post.previewStatus == 'failed' || !previewPending);

    return GestureDetector(
      onTap: () => _openLarge(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kStreamPreviewMaxSide,
          maxHeight: kStreamPreviewMaxSide,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: previewReady
              ? _StoragePostImage(
                  cacheKey: '${post.id}-preview',
                  storagePath: post.previewStoragePath,
                  downloadUrl: post.previewDownloadUrl,
                  maxSide: kStreamPreviewMaxSide,
                )
              : useOriginalFallback
                  ? _StoragePostImage(
                      cacheKey: post.id,
                      storagePath: post.storagePath,
                      downloadUrl: post.mediaUrl,
                      maxSide: kStreamPreviewMaxSide,
                    )
                  : const SizedBox(
                      width: kStreamPreviewMaxSide,
                      height: 180,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
        ),
      ),
    );
  }
}

class _ImageLargeDialog extends StatelessWidget {
  const _ImageLargeDialog({
    required this.cacheKey,
    this.storagePath,
    this.downloadUrl,
  });

  final String cacheKey;
  final String? storagePath;
  final String? downloadUrl;

  @override
  Widget build(BuildContext context) {
    final maxSide = MediaQuery.sizeOf(context).shortestSide.clamp(0.0, 690.0);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxSide,
              maxHeight: maxSide,
            ),
            child: InteractiveViewer(
              child: _StoragePostImage(
                cacheKey: cacheKey,
                storagePath: storagePath,
                downloadUrl: downloadUrl,
                maxSide: 690,
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoragePostImage extends ConsumerStatefulWidget {
  const _StoragePostImage({
    required this.cacheKey,
    this.storagePath,
    this.downloadUrl,
    this.maxSide = 320,
  });

  final String cacheKey;
  final String? storagePath;
  final String? downloadUrl;
  /// Max width and height for stream/detail previews (aspect preserved).
  final double maxSide;

  @override
  ConsumerState<_StoragePostImage> createState() => _StoragePostImageState();
}

class _StoragePostImageState extends ConsumerState<_StoragePostImage> {
  Uint8List? _bytes;
  Object? _error;
  bool _loading = true;
  bool _tryNetworkFallback = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _StoragePostImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey ||
        oldWidget.storagePath != widget.storagePath ||
        oldWidget.downloadUrl != widget.downloadUrl) {
      setState(() {
        _bytes = null;
        _error = null;
        _loading = true;
        _tryNetworkFallback = false;
      });
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final bytes = await ref.read(mediaRepositoryProvider).downloadImageBytes(
            storagePath: widget.storagePath,
            downloadUrl: widget.downloadUrl,
          );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _error = null;
        _loading = false;
        _tryNetworkFallback = false;
      });
    } catch (e) {
      if (!mounted) return;
      // SDK path failed — try plain network only if we have a URL.
      if (widget.downloadUrl != null && widget.downloadUrl!.isNotEmpty) {
        setState(() {
          _loading = false;
          _tryNetworkFallback = true;
        });
      } else {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxSide = widget.maxSide;
    final Widget imageChild;
    if (_loading) {
      imageChild = SizedBox(
        width: maxSide,
        height: 120,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_bytes != null) {
      imageChild = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxSide, maxHeight: maxSide),
        child: Image.memory(
          _bytes!,
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => SizedBox(
            width: maxSide,
            height: 120,
            child: const Center(
              child: Text(
                'Could not load the image',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      );
    } else if (_tryNetworkFallback && widget.downloadUrl != null) {
      imageChild = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxSide, maxHeight: maxSide),
        child: Image.network(
          widget.downloadUrl!,
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          errorBuilder: (_, _, _) => SizedBox(
            width: maxSide,
            height: 120,
            child: const Center(
              child: Text(
                'Could not load the image',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      );
    } else if (_error != null) {
      imageChild = SizedBox(
        width: maxSide,
        height: 120,
        child: const Center(
          child: Text(
            'Could not load the image',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    } else {
      imageChild = const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      heightFactor: 1,
      child: imageChild,
    );
  }
}

class _ComposerBar extends ConsumerWidget {
  const _ComposerBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.recording,
    required this.replyTo,
    required this.emojiPickerOpen,
    required this.onClearReply,
    required this.onToggleEmojiPicker,
    required this.onEmojiSelected,
    required this.onSend,
    this.myUid,
    this.onSendEmojiOnly,
    this.onAttach,
    this.onMicPointerDown,
    this.onMicPointerMove,
    this.onMicPointerUp,
    this.onMicPointerCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool recording;
  final PostReplyTo? replyTo;
  final bool emojiPickerOpen;
  final String? myUid;
  final VoidCallback onClearReply;
  final VoidCallback onToggleEmojiPicker;
  final ValueChanged<Emoji> onEmojiSelected;
  final ValueChanged<String>? onSendEmojiOnly;
  final VoidCallback? onSend;
  final VoidCallback? onAttach;
  final PointerDownEventListener? onMicPointerDown;
  final PointerMoveEventListener? onMicPointerMove;
  final PointerUpEventListener? onMicPointerUp;
  final VoidCallback? onMicPointerCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasText = controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: const BoxDecoration(
          color: AppColors.bgElevated,
          border: Border(top: BorderSide(color: AppColors.hairline)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyTo != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                decoration: BoxDecoration(
                  color: AppColors.bgApp,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                    left: BorderSide(color: AppColors.accent, width: 3),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UserIdentityChip(
                            userId: replyTo!.authorId,
                            myUid: myUid,
                          ),
                          Text(
                            replyTo!.preview.isEmpty
                                ? postTypeLabel(
                                    PostType.free,
                                    kind: replyTo!.kind,
                                  )
                                : replyTo!.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel reply',
                      onPressed: sending || recording ? null : onClearReply,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Attach',
                  onPressed: sending || recording ? null : onAttach,
                  icon: const Icon(Icons.attach_file),
                ),
                IconButton(
                  tooltip: emojiPickerOpen ? 'Keyboard' : 'Emoji',
                  onPressed: sending || recording ? null : onToggleEmojiPicker,
                  icon: Icon(
                    emojiPickerOpen
                        ? Icons.keyboard_outlined
                        : Icons.emoji_emotions_outlined,
                    color: emojiPickerOpen ? AppColors.accent : null,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !recording,
                    minLines: 1,
                    maxLines: 4,
                    style: messageBodyStyle(),
                    decoration: InputDecoration(
                      hintText: recording ? 'Recording…' : 'Message or caption',
                      hintStyle: messageBodyStyle(
                        color: AppColors.textSecondary,
                      ),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    onTap: () {
                      if (emojiPickerOpen) onToggleEmojiPicker();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                if (hasText)
                  IconButton.filled(
                    onPressed: sending || recording ? null : onSend,
                    icon: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                  )
                else
                  Listener(
                    onPointerDown: sending ? null : onMicPointerDown,
                    onPointerMove: sending ? null : onMicPointerMove,
                    onPointerUp: sending ? null : onMicPointerUp,
                    onPointerCancel: sending
                        ? null
                        : (_) => onMicPointerCancel?.call(),
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor:
                            recording ? AppColors.danger : AppColors.accent,
                      ),
                      onPressed: () {},
                      tooltip: 'Hold to record',
                      icon: Icon(
                        recording ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            if (emojiPickerOpen)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    // Empty composer → send as emoji-only emotion post.
                    if (controller.text.trim().isEmpty &&
                        onSendEmojiOnly != null) {
                      onSendEmojiOnly!(emoji.emoji);
                      return;
                    }
                    onEmojiSelected(emoji);
                  },
                  config: Config(
                    height: 280,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: EmojiViewConfig(
                      emojiSizeMax: 28 *
                          (foundation.defaultTargetPlatform ==
                                  TargetPlatform.iOS
                              ? 1.20
                              : 1.0),
                      backgroundColor: AppColors.bgElevated,
                    ),
                    categoryViewConfig: const CategoryViewConfig(
                      indicatorColor: AppColors.accent,
                      iconColorSelected: AppColors.accent,
                      backgroundColor: AppColors.bgApp,
                    ),
                    bottomActionBarConfig: const BottomActionBarConfig(
                      backgroundColor: AppColors.bgApp,
                      buttonColor: AppColors.accent,
                      buttonIconColor: Colors.white,
                    ),
                    searchViewConfig: const SearchViewConfig(
                      backgroundColor: AppColors.bgElevated,
                      buttonIconColor: AppColors.accent,
                    ),
                    skinToneConfig: const SkinToneConfig(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
