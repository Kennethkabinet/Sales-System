import 'package:flutter/material.dart';

class BlockingLoader extends StatelessWidget {
  final String message;

  const BlockingLoader({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onSurface = Color(0xFF111827);
    const bg = Color(0xFFFEFEFE);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 240,
              height: 240,
              child: ColorFiltered(
                // The GIF has a pure white background (#FFFFFF), which can look
                // like a different "square" against #FEFEFE. This tiny shift
                // makes the GIF's whites match #FEFEFE while keeping colors
                // visually identical.
                colorFilter: const ColorFilter.matrix(<double>[
                  1,
                  0,
                  0,
                  0,
                  -1,
                  0,
                  1,
                  0,
                  0,
                  -1,
                  0,
                  0,
                  1,
                  0,
                  -1,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: bg),
                  child: Image.asset(
                    'assets/images/loader.gif',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: CircularProgressIndicator(strokeWidth: 4),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BlockingLoaderOverlay extends StatelessWidget {
  final bool show;
  final String message;
  final Widget child;

  const BlockingLoaderOverlay({
    super.key,
    required this.show,
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return child;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ColoredBox(
            color: const Color(0xFFFEFEFE),
            child: IgnorePointer(
              ignoring: !show,
              child: BlockingLoader(message: message),
            ),
          ),
        ),
      ],
    );
  }
}
