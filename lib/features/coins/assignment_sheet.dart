import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../domain/models/assignment.dart';
import 'coin_rail.dart';

Future<void> showAssignmentSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String circleId,
  required CoinView coin,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: _AssignmentSheetBody(circleId: circleId, coin: coin),
      );
    },
  );
}

class _AssignmentSheetBody extends ConsumerWidget {
  const _AssignmentSheetBody({
    required this.circleId,
    required this.coin,
  });

  final String circleId;
  final CoinView coin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authStateProvider).asData?.value?.uid;
    final coinsAsync = ref.watch(coinViewsProvider(circleId));
    CoinView live = coin;
    final list = coinsAsync.asData?.value;
    if (list != null) {
      for (final c in list) {
        if (c.assignment.id == coin.assignment.id) {
          live = c;
          break;
        }
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          live.assignment.title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        if (live.assignment.description != null &&
            live.assignment.description!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            live.assignment.description!,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 16),
        ...live.objectives.map((obj) {
          final completed = live.isObjectiveCompleted(obj.id);
          return CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: completed,
            onChanged: completed || uid == null
                ? null
                : (_) async {
                    await ref
                        .read(assignmentRepositoryProvider)
                        .markObjectiveCompleted(
                          circleId: circleId,
                          assignmentId: live.assignment.id,
                          objectiveId: obj.id,
                          userId: uid,
                          evidence: {'kind': 'check'},
                        );
                  },
            title: Text(obj.label),
            subtitle: Text(
              obj.criteria['label']?.toString() ??
                  'Evidencia: check mínimo',
              style: const TextStyle(fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.accent,
          );
        }),
      ],
    );
  }
}

Future<void> showCreateAssignmentDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String circleId,
}) async {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final objectives = <ObjectiveType>[
    ObjectiveType.purpose,
    ObjectiveType.morningPractice,
  ];

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('New assignment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Default objectives: Purpose + Morning practice',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create'),
          ),
        ],
      );
    },
  );

  if (ok != true) return;
  final uid = ref.read(authStateProvider).asData?.value?.uid;
  if (uid == null || titleCtrl.text.trim().isEmpty) return;

  await ref.read(assignmentRepositoryProvider).createAssignmentWithObjectives(
        circleId: circleId,
        createdBy: uid,
        title: titleCtrl.text,
        description: descCtrl.text,
        objectives: objectives
            .map(
              (t) => (
                type: t,
                label: Objective(
                  id: '',
                  assignmentId: '',
                  type: t,
                  order: 0,
                ).label,
              ),
            )
            .toList(),
      );
}
