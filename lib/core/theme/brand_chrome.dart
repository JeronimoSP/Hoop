import 'package:flutter/material.dart';

/// Evocative World infinity mark — small chrome brand signal.
class EwBrandMark extends StatelessWidget {
  const EwBrandMark({super.key, this.size = 28});

  static const assetPath = 'assets/brand/ew_mark.jpg';

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => Icon(
        Icons.all_inclusive,
        size: size * 0.9,
        color: Theme.of(context).colorScheme.tertiary,
      ),
    );
  }
}

/// App bar with the EW mark near the top-left on every screen.
PreferredSizeWidget brandAppBar({
  required Widget title,
  List<Widget>? actions,
  bool automaticallyImplyLeading = true,
  Widget? leading,
}) {
  final markAsLeading = !automaticallyImplyLeading && leading == null;

  return AppBar(
    automaticallyImplyLeading: automaticallyImplyLeading,
    leadingWidth: markAsLeading ? 52 : null,
    leading: leading ??
        (markAsLeading
            ? const Center(child: EwBrandMark(size: 30))
            : null),
    titleSpacing: (automaticallyImplyLeading || leading != null || markAsLeading)
        ? 4
        : 16,
    title: markAsLeading
        ? title
        : Row(
            children: [
              const EwBrandMark(size: 28),
              const SizedBox(width: 10),
              Flexible(child: title),
            ],
          ),
    actions: actions,
  );
}
