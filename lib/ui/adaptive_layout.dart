import 'package:flutter/material.dart';

/// Switches between a wide table layout and a narrow card-list layout by the
/// available width (not by platform: a narrow Linux window gets cards too).
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({super.key, required this.wide, required this.narrow});

  static const breakpoint = 720.0;

  final WidgetBuilder wide;
  final WidgetBuilder narrow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) =>
            c.maxWidth >= breakpoint ? wide(context) : narrow(context),
      );
}
