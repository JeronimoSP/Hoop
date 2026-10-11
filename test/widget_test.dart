import 'package:flutter_test/flutter_test.dart';

import 'package:circulo/domain/models/assignment.dart';

void main() {
  test('deriveCoinState from objectives and logs', () {
    const objs = [
      Objective(id: 'o1', assignmentId: 'a1', type: ObjectiveType.purpose, order: 0),
      Objective(
        id: 'o2',
        assignmentId: 'a1',
        type: ObjectiveType.morningPractice,
        order: 1,
      ),
    ];
    expect(deriveCoinState(objectives: objs, logs: const []), CoinState.pending);

    final oneDone = [
      ProgressLog(
        id: 'p1',
        assignmentId: 'a1',
        objectiveId: 'o1',
        userId: 'u1',
        status: ProgressStatus.completed,
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];
    expect(
      deriveCoinState(objectives: objs, logs: oneDone),
      CoinState.inProgress,
    );

    final allDone = [
      ...oneDone,
      ProgressLog(
        id: 'p2',
        assignmentId: 'a1',
        objectiveId: 'o2',
        userId: 'u1',
        status: ProgressStatus.completed,
        updatedAt: DateTime(2026, 1, 1),
      ),
    ];
    expect(
      deriveCoinState(objectives: objs, logs: allDone),
      CoinState.completed,
    );
  });
}
