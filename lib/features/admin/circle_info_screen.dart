import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/circle_repository.dart';
import '../../domain/models/circle.dart';

class CircleInfoScreen extends ConsumerStatefulWidget {
  const CircleInfoScreen({super.key, required this.circleId});

  final String circleId;

  @override
  ConsumerState<CircleInfoScreen> createState() => _CircleInfoScreenState();
}

class _CircleInfoScreenState extends ConsumerState<CircleInfoScreen> {
  final _emailCtrl = TextEditingController();
  bool _adding = false;
  String? _message;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;
    setState(() {
      _adding = true;
      _message = null;
    });
    try {
      final found = await ref.read(userRepositoryProvider).getByEmail(email);
      if (found == null) {
        setState(() => _message =
            'Account not found. Ask them to sign in to Circle first.');
        return;
      }
      await ref.read(circleRepositoryProvider).addMember(
            circleId: widget.circleId,
            userId: found.uid,
          );
      _emailCtrl.clear();
      setState(() => _message = 'Welcome to the circle');
    } catch (e) {
      setState(() => _message = 'Could not add member. Please try again.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final circleAsync = ref.watch(_circleProvider(widget.circleId));
    final membersAsync = ref.watch(_membersProvider(widget.circleId));
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final members = membersAsync.asData?.value ?? const <Membership>[];
    Membership? myMembership;
    for (final m in members) {
      if (m.userId == uid) {
        myMembership = m;
        break;
      }
    }
    final isAdmin = myMembership?.isAdmin == true;

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Circle info',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      body: circleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (circle) {
          if (circle == null) {
            return const Center(child: Text('Circle not found'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(circle.name, style: brandDisplay(fontSize: 24)),
              if (circle.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  circle.description,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.spa_outlined, color: AppColors.accent),
                title: const Text('Challenges'),
                subtitle: const Text('Daily media practice or quests'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/circles/${widget.circleId}/challenges'),
              ),
              const SizedBox(height: 8),
              Text(
                'Members',
                style: brandDisplay(fontSize: 18),
              ),
              const SizedBox(height: 8),
              membersAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (members) {
                  final myUid =
                      ref.watch(authStateProvider).asData?.value?.uid;
                  return Column(
                    children: members
                        .map(
                          (m) => _MemberTile(
                            userId: m.userId,
                            role: m.role,
                            myUid: myUid,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              if (isAdmin) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Add member by email',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _adding ? null : _addMember,
                    child: _adding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add'),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({
    required this.userId,
    required this.role,
    this.myUid,
  });

  final String userId;
  final String role;
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(appUserProvider(userId)).asData?.value;
    final isMe = myUid != null && userId == myUid;
    final label = user?.displayLabel.trim() ?? '';
    final title = isMe
        ? (label.isNotEmpty ? '$label · You' : 'You')
        : (label.isNotEmpty ? label : 'Member');

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(
        photoURL: user?.avatarURL,
        label: user?.displayName.isNotEmpty == true
            ? user!.displayName
            : title,
        size: UserAvatarSize.md,
      ),
      title: Text(title),
      subtitle: Text(role),
      dense: true,
    );
  }
}

final _circleProvider =
    StreamProvider.autoDispose.family<Circle?, String>((ref, circleId) {
  return ref.watch(circleRepositoryProvider).watchCircle(circleId);
});

final _membersProvider =
    StreamProvider.autoDispose.family<List<Membership>, String>((ref, circleId) {
  return ref.watch(circleRepositoryProvider).watchMembers(circleId);
});
