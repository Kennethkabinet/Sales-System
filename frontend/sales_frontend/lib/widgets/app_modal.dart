import 'package:flutter/material.dart';

class AppModal {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget>? actions,
    String buttonText = 'OK',
    bool barrierDismissible = true,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 360),
          child: SingleChildScrollView(child: content),
        ),
        actions: actions ??
            [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(buttonText),
              ),
            ],
      ),
    );
  }

  static Future<void> showText(
    BuildContext context, {
    required String title,
    required String message,
    String buttonText = 'OK',
    bool barrierDismissible = true,
  }) {
    return show(
      context,
      title: title,
      content: SelectableText(message),
      buttonText: buttonText,
      barrierDismissible: barrierDismissible,
    );
  }
}
