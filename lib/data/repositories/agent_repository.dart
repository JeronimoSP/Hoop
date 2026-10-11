import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final agentRepositoryProvider = Provider<AgentRepository>((ref) {
  return AgentRepository(
    FirebaseFunctions.instanceFor(region: 'us-east1'),
  );
});

class AgentRepository {
  AgentRepository(this._functions);

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> agentAction({
    required String circleId,
    required String postId,
    required String actionId,
    String? followUp,
  }) async {
    final callable = _functions.httpsCallable(
      'agentAction',
      options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
    );
    final result = await callable.call(<String, dynamic>{
      'circleId': circleId,
      'postId': postId,
      'actionId': actionId,
      if (followUp != null && followUp.trim().isNotEmpty)
        'followUp': followUp.trim(),
    });
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {'ok': true};
  }

  Future<Map<String, dynamic>> bootstrapCircleAgent() async {
    final callable = _functions.httpsCallable('bootstrapCircleAgent');
    final result = await callable.call();
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return {};
  }
}
