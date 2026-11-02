import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import '../../data/repositories/assignment_repository.dart';
import '../../data/repositories/circle_repository.dart';
import '../../domain/models/assignment.dart';
import '../../domain/models/circle.dart';
import 'assignment_system_thread_screen.dart';

enum _RosterFilter { all, missing, submitted }

final _rosterMembersProvider =
    StreamProvider.autoDispose.family<List<Membership>, String>((ref, circleId) {
  return ref.watch(circleRepositoryProvider).watchMembers(circleId);
});

final _submissionsProvider = StreamProvider.autoDispose.family<
    List<AssignmentSubmission>,
    ({String circleId, String assignmentId})>((ref, key) {
  return ref.watch(assignmentRepositoryProvider).watchSubmissionsForAssignment(
        circleId: key.circleId,
        assignmentId: key.assignmentId,
      );
});

class AssignmentRosterScreen extends ConsumerStatefulWidget {
  const AssignmentRosterScreen({
    super.key,
    required this.circleId,
    required this.assignmentId,
  });

  final String circleId;
  final String assignmentId;

  @override
  ConsumerState<AssignmentRosterScreen> createState() =>
      _AssignmentRosterScreenState();
}

class _AssignmentRosterScreenState
    extends ConsumerState<AssignmentRosterScreen> {
  _RosterFilter _filter = _RosterFilter.all;

  @override
  Widget build(BuildContext context) {
    final assignmentAsync =
        ref.watch(assignmentDocProvider(widget.assignmentId));
    final membersAsync =
        ref.watch(_rosterMembersProvider(widget.circleId));
    final submissionsAsync = ref.watch(
      _submissionsProvider((
        circleId: widget.circleId,
        assignmentId: widget.assignmentId,
      )),
    );
    final blocksAsync = ref.watch(
      assignmentBlocksProvider((
        circleId: widget.circleId,
        assignmentId: widget.assignmentId,
      )),
    );

    return Scaffold(
      appBar: brandAppBar(
        title: Text(
          'Roster',
          style: brandDisplay(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: 'Open assignment',
            icon: const Icon(Icons.assignment_outlined),
            onPressed: () => context.push(
              '/circles/${widget.circleId}/assignments/${widget.assignmentId}',
            ),
          ),
        ],
      ),
      body: assignmentAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (assignment) {
          if (assignment == null) {
            return const Center(child: Text('Assignment not found'));
          }
          final members = membersAsync.asData?.value ?? const <Membership>[];
          final submissions = {
            for (final s
                in submissionsAsync.asData?.value ??
                    const <AssignmentSubmission>[])
              s.userId: s,
          };
          final requiredCount = (blocksAsync.asData?.value ?? const [])
              .where((b) => b.isInput && b.required)
              .length;

          var rows = members.map((m) {
            final s = submissions[m.userId];
            final status = s?.status ?? SubmissionStatus.notStarted;
            return (member: m, submission: s, status: status);
          }).toList();

          rows = rows.where((r) {
            switch (_filter) {
              case _RosterFilter.all:
                return true;
              case _RosterFilter.missing:
                return r.status == SubmissionStatus.notStarted ||
                    r.status == SubmissionStatus.inProgress;
              case _RosterFilter.submitted:
                return r.status == SubmissionStatus.submitted ||
                    r.status == SubmissionStatus.late;
            }
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    assignment.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SegmentedButton<_RosterFilter>(
                  segments: const [
                    ButtonSegment(
                      value: _RosterFilter.all,
                      label: Text('All'),
                    ),
                    ButtonSegment(
                      value: _RosterFilter.missing,
                      label: Text('Missing'),
                    ),
                    ButtonSegment(
                      value: _RosterFilter.submitted,
                      label: Text('Submitted'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) =>
                      setState(() => _filter = s.first),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: membersAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (_) {
                    if (rows.isEmpty) {
                      return const Center(child: Text('No participants'));
                    }
                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final answered =
                            row.submission?.answeredRequiredCount ?? 0;
                        final required =
                            row.submission?.requiredCount ?? requiredCount;
                        return ListTile(
                          title: Text(row.member.userId),
                          subtitle: Text(
                            _statusLabel(row.status) +
                                (required > 0
                                    ? ' · $answered/$required'
                                    : ''),
                          ),
                          trailing: _StatusChip(status: row.status),
                          onTap: () => context.push(
                            '/circles/${widget.circleId}/assignments/'
                            '${widget.assignmentId}/participant/${row.member.userId}',
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(SubmissionStatus status) {
    switch (status) {
      case SubmissionStatus.notStarted:
        return 'Not started';
      case SubmissionStatus.inProgress:
        return 'In progress';
      case SubmissionStatus.submitted:
        return 'Submitted';
      case SubmissionStatus.late:
        return 'Late';
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SubmissionStatus status;

  @override
  Widget build(BuildContext context) {
    final bg = switch (status) {
      SubmissionStatus.notStarted => AppColors.coinPending,
      SubmissionStatus.inProgress => AppColors.coinInProgress,
      SubmissionStatus.submitted => AppColors.coinCompleted,
      SubmissionStatus.late => Colors.orange.shade700,
    };
    final label = switch (status) {
      SubmissionStatus.notStarted => 'Not started',
      SubmissionStatus.inProgress => 'In progress',
      SubmissionStatus.submitted => 'Submitted',
      SubmissionStatus.late => 'Late',
    };
    return Chip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
      backgroundColor: bg,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}
