import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool get isDesktop => switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS =>
        true,
      _ => false,
    };

/// Keyboard shortcuts only on desktop; elsewhere the child is returned as is
/// (the touch equivalent is [NewTxButton]).
class DesktopShortcuts extends StatelessWidget {
  const DesktopShortcuts({super.key, required this.onNewTx, required this.child});

  final VoidCallback onNewTx;
  final Widget child;

  @override
  Widget build(BuildContext context) => isDesktop
      ? CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): onNewTx,
          },
          child: Focus(autofocus: true, child: child),
        )
      : child;
}

/// Touch equivalent of Ctrl+N: a floating button, shown only off-desktop.
class NewTxButton extends StatelessWidget {
  const NewTxButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => isDesktop
      ? const SizedBox.shrink()
      : FloatingActionButton(
          onPressed: onPressed, tooltip: 'تراکنش جدید', child: const Icon(Icons.add));
}
