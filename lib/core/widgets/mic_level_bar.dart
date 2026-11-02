import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Compact horizontal mic level meter (0–1).
class MicLevelBar extends StatelessWidget {
  const MicLevelBar({
    super.key,
    required this.level,
    this.width = 100,
    this.height = 6,
  });

  final double level;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = level.clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x331C1814)),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: t,
                heightFactor: 1,
                child: ColoredBox(
                  color: t > 0.85 ? AppColors.danger : AppColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
