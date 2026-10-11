import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../domain/models/assignment.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/auth_repository.dart';
import 'assignment_sheet.dart';

final coinViewsProvider =
    StreamProvider.autoDispose.family<List<CoinView>, String>((ref, circleId) {
  final uid = ref.watch(authStateProvider).asData?.value?.uid;
  if (uid == null) return Stream.value(const []);

  final repo = ref.watch(assignmentRepositoryProvider);
  return repo.watchAssignments(circleId).asyncExpand((assignments) {
    final ids = assignments.map((a) => a.id).toList();
    return repo.watchObjectivesForAssignments(ids).asyncExpand((objectives) {
      return repo
          .watchMyProgress(userId: uid, circleId: circleId)
          .map(
            (logs) => buildCoinViews(
              assignments: assignments,
              objectives: objectives,
              logs: logs,
            ),
          );
    });
  });
});

class CoinRail extends ConsumerWidget {
  const CoinRail({
    super.key,
    required this.circleId,
    required this.isAdmin,
  });

  final String circleId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coinsAsync = ref.watch(coinViewsProvider(circleId));

    return Container(
      width: double.infinity,
      color: AppColors.accentSoft,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: coinsAsync.when(
        loading: () => const SizedBox(
          height: 40,
          child: Center(child: LinearProgressIndicator()),
        ),
        error: (e, _) => Text('$e'),
        data: (coins) {
          if (coins.isEmpty) {
            return Row(
              children: [
                const Expanded(
                  child: Text(
                    'No assignments yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isAdmin)
                  TextButton(
                    onPressed: () => showCreateAssignmentDialog(
                      context: context,
                      ref: ref,
                      circleId: circleId,
                    ),
                    child: const Text('Create'),
                  ),
              ],
            );
          }

          return SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: coins.length + (isAdmin ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (isAdmin && index == coins.length) {
                  return IconButton.filledTonal(
                    onPressed: () => showCreateAssignmentDialog(
                      context: context,
                      ref: ref,
                      circleId: circleId,
                    ),
                    icon: const Icon(Icons.add),
                    tooltip: 'New assignment',
                  );
                }
                final coin = coins[index];
                return _CoinChip(
                  coin: coin,
                  onTap: () => showAssignmentSheet(
                    context: context,
                    ref: ref,
                    circleId: circleId,
                    coin: coin,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CoinChip extends StatelessWidget {
  const _CoinChip({required this.coin, required this.onTap});

  final CoinView coin;
  final VoidCallback onTap;

  Color get _color {
    switch (coin.state) {
      case CoinState.pending:
        return AppColors.coinPending;
      case CoinState.inProgress:
        return AppColors.coinInProgress;
      case CoinState.completed:
        return AppColors.coinCompleted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _color,
            ),
            child: coin.state == CoinState.completed
                ? const Icon(Icons.check, size: 18, color: AppColors.gold)
                : Center(
                    child: Text(
                      '${coin.completedCount}/${coin.totalCount}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: 64,
            child: Text(
              coin.assignment.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}
