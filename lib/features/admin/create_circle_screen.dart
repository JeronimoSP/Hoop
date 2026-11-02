import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/circle_repository.dart';

class CreateCircleScreen extends ConsumerStatefulWidget {
  const CreateCircleScreen({super.key});

  @override
  ConsumerState<CreateCircleScreen> createState() => _CreateCircleScreenState();
}

class _CreateCircleScreenState extends ConsumerState<CreateCircleScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _emailsCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _emailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }
    final user = ref.read(authStateProvider).asData?.value;
    final appUser = ref.read(currentAppUserProvider).asData?.value;
    if (user == null || appUser?.isPlatformAdmin != true) {
      setState(() => _error = 'Only a facilitator can create Hoops');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final emails = _emailsCtrl.text
          .split(RegExp(r'[\s,;]+'))
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.contains('@'))
          .toSet();

      final memberIds = <String>[];
      final usersRepo = ref.read(userRepositoryProvider);
      for (final email in emails) {
        final found = await usersRepo.getByEmail(email);
        if (found != null) memberIds.add(found.uid);
      }

      final circleId = await ref.read(circleRepositoryProvider).createCircle(
            name: name,
            description: _descCtrl.text,
            createdBy: user.uid,
            memberUserIds: memberIds,
          );

      if (!mounted) return;
      context.go('/circles/$circleId');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'New Hoop',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailsCtrl,
            decoration: const InputDecoration(
              labelText: 'Members (emails, optional)',
              hintText: 'ana@mail.com, luis@mail.com',
              helperText:
                  'Only users who have already signed in once can be added',
            ),
            maxLines: 2,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
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
                : const Text('Create'),
          ),
        ],
      ),
    );
  }
}
