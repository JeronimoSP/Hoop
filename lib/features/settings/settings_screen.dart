import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/repositories/app_config_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/media_repository.dart';
import '../../data/repositories/messaging_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _aliasCtrl = TextEditingController();
  bool _busy = false;
  bool _aliasDirty = false;
  bool _aliasHydrated = false;
  String? _message;

  @override
  void dispose() {
    _aliasCtrl.dispose();
    super.dispose();
  }

  void _hydrateAlias(String? alias) {
    if (_aliasHydrated || _aliasDirty) return;
    // Alias complements the Google name — do not prefill with name.
    _aliasCtrl.text = alias?.trim() ?? '';
    _aliasHydrated = true;
  }

  Future<void> _saveAlias() async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(userRepositoryProvider).updateAlias(uid, _aliasCtrl.text);
      setState(() {
        _aliasDirty = false;
        _message = 'Alias saved.';
      });
    } catch (_) {
      setState(() => _message = 'Could not save alias.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPhoto() async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final picked =
          await ref.read(mediaRepositoryProvider).pickCompressedImage();
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      await ref.read(userRepositoryProvider).uploadProfilePhoto(
            uid: uid,
            bytes: picked.bytes,
            contentType: picked.contentType,
            fileName: picked.fileName,
          );
      setState(() => _message = 'Profile photo updated.');
    } catch (e) {
      setState(() {
        _message = e is StateError
            ? e.message
            : 'Could not upload photo. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _promote() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final configRepo = ref.read(appConfigRepositoryProvider);
      await configRepo.ensureBootstrapSettings();
      final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
      if (uid == null) throw StateError('Not signed in');
      await ref.read(userRepositoryProvider).promoteToPlatformAdmin(uid);
      setState(
        () => _message =
            'You are now a facilitator. Go home to open a Circle with your community.',
      );
    } catch (e) {
      setState(() => _message = 'Could not update your role. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setSelfPromote(bool enabled) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(appConfigRepositoryProvider).setSelfPromoteEnabled(enabled);
      setState(
        () => _message = enabled
            ? 'Facilitator sign-up is open.'
            : 'Facilitator sign-up is closed.',
      );
    } catch (e) {
      setState(() => _message = 'Could not update that setting.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentAppUserProvider).asData?.value;
    if (user != null) {
      _hydrateAlias(user.alias);
    }
    final config = ref.watch(appConfigProvider).asData?.value;
    final promoteAvailable =
        config == null || !config.exists || config.selfPromoteEnabled;
    final showPromote =
        user != null && !user.isPlatformAdmin && promoteAvailable;

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Settings',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      UserAvatar(
                        photoURL: user?.avatarURL,
                        label: user?.displayName ?? '?',
                        size: UserAvatarSize.lg,
                      ),
                      Material(
                        color: AppColors.accent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _busy ? null : _pickPhoto,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(
                              Icons.camera_alt_outlined,
                              size: 18,
                              color: AppColors.textOnDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (user?.hasCustomPhoto == true) ...[
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Using a Circle photo (Google account unchanged)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  user?.name.isNotEmpty == true ? user!.name : '…',
                  style: brandDisplay(fontSize: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _aliasCtrl,
                  enabled: !_busy && user != null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Alias',
                    hintText: 'Optional nickname shown with your name',
                    helperText: 'Shown as Name (alias) across Circle',
                  ),
                  onChanged: (_) {
                    if (!_aliasDirty) setState(() => _aliasDirty = true);
                  },
                ),
                if (_aliasDirty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _busy ? null : _saveAlias,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save alias'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (user?.isPlatformAdmin == true)
            const ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Facilitator'),
              subtitle: Text('You can create Circles and support your community'),
            ),
          if (showPromote) ...[
            const Divider(color: AppColors.hairline),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Become a facilitator'),
              subtitle: const Text(
                'Turn on the role to create Circles and invite others',
              ),
              trailing: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _busy ? null : _promote,
            ),
          ],
          if (user?.isPlatformAdmin == true) ...[
            const Divider(color: AppColors.hairline),
            SwitchListTile(
              secondary: const Icon(Icons.lock_outline),
              title: const Text('Allow new facilitator sign-ups'),
              subtitle: const Text(
                'Turn this off when your facilitator community is ready',
              ),
              value: config?.selfPromoteEnabled == true,
              onChanged: _busy ? null : _setSelfPromote,
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _message!,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          const Divider(color: AppColors.hairline),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text(
              'Sign out',
              style: TextStyle(color: AppColors.danger),
            ),
            onTap: () async {
              await ref.read(messagingRepositoryProvider).stop();
              await ref.read(authRepositoryProvider).signOut();
              if (context.mounted) context.go('/auth');
            },
          ),
        ],
      ),
    );
  }
}
