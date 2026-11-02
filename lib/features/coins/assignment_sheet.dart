import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/assignment.dart';

/// Legacy entry — opens system-chat assignment thread.
Future<void> showAssignmentSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String circleId,
  required CoinView coin,
}) {
  return Future<void>.microtask(() {
    if (!context.mounted) return;
    context.push('/circles/$circleId/assignments/${coin.assignment.id}');
  });
}

/// Legacy create — opens system-chat draft.
Future<void> showCreateAssignmentDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String circleId,
}) {
  return Future<void>.microtask(() {
    if (!context.mounted) return;
    context.push('/circles/$circleId/assignments/new');
  });
}
