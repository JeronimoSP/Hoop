import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/auth_repository.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
    } catch (e) {
      setState(() => _error = _friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyAuthError(Object e) {
    final raw = e.toString();
    final code = e is FirebaseAuthException ? e.code : null;
    if (code == 'configuration-not-found' ||
        raw.contains('configuration-not-found')) {
      return 'We could not connect to sign-in.\n'
          'Ask your facilitator for help, or try again later.';
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'operation-not-allowed':
          return 'Google sign-in is not available right now.';
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
          return 'Sign-in cancelled.';
        default:
          return 'Could not sign in. Please try again.';
      }
    }
    return 'Could not sign in. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.authGradientTop,
              AppColors.authGradientMid,
              AppColors.authGradientBottom,
            ],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 168,
                        height: 168,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.center,
                        child: Image.asset(
                          'assets/brand/evocative_world_logo.png',
                          width: 148,
                          height: 148,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.all_inclusive,
                            size: 72,
                            color: AppColors.gold.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Hoop',
                        style: brandDisplay(
                          fontSize: 44,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textInverse,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 48,
                        height: 2,
                        color: AppColors.gold,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Learning in community',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          color: AppColors.textInverse.withValues(alpha: 0.88),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Evocative World',
                        textAlign: TextAlign.center,
                        style: brandDisplay(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.gold.withValues(alpha: 0.95),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x33B42318),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFB4A8)),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFFFB4A8),
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _signIn,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.bgElevated,
                      foregroundColor: AppColors.textPrimary,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue with Google'),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
