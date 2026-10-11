import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/brand_chrome.dart';
import 'challenges_providers.dart';
import 'session_media_screen.dart';
import 'session_quest_screen.dart';

/// Loads challenge + session and routes to media or quest UI.
class ChallengeSessionScreen extends ConsumerWidget {
  const ChallengeSessionScreen({
    super.key,
    required this.circleId,
    required this.challengeId,
    required this.sessionId,
    this.autoplay = false,
  });

  final String circleId;
  final String challengeId;
  final String sessionId;
  final bool autoplay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final challengeAsync = ref.watch(
      challengeProvider((circleId: circleId, challengeId: challengeId)),
    );
    final sessionAsync = ref.watch(challengeSessionProvider(sessionId));

    return challengeAsync.when(
      loading: () => Scaffold(
        appBar: brandAppBar(
          title: Text('Session', style: brandDisplay(fontWeight: FontWeight.w600)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: brandAppBar(
          title: Text('Session', style: brandDisplay(fontWeight: FontWeight.w600)),
        ),
        body: Center(child: Text('$e')),
      ),
      data: (challenge) {
        if (challenge == null) {
          return Scaffold(
            appBar: brandAppBar(
              title: Text(
                'Session',
                style: brandDisplay(fontWeight: FontWeight.w600),
              ),
            ),
            body: const Center(child: Text('Challenge not found')),
          );
        }
        return sessionAsync.when(
          loading: () => Scaffold(
            appBar: brandAppBar(
              title: Text(
                challenge.title,
                style: brandDisplay(fontWeight: FontWeight.w600),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            appBar: brandAppBar(
              title: Text(
                challenge.title,
                style: brandDisplay(fontWeight: FontWeight.w600),
              ),
            ),
            body: Center(child: Text('$e')),
          ),
          data: (session) {
            if (session == null) {
              return Scaffold(
                appBar: brandAppBar(
                  title: Text(
                    challenge.title,
                    style: brandDisplay(fontWeight: FontWeight.w600),
                  ),
                ),
                body: const Center(child: Text('Session not found')),
              );
            }
            if (challenge.isMedia) {
              return SessionMediaScreen(
                challenge: challenge,
                session: session,
                autoplay: autoplay,
              );
            }
            return SessionQuestScreen(
              challenge: challenge,
              session: session,
            );
          },
        );
      },
    );
  }
}
