import 'package:flutter/material.dart';


/// Shown while startup steps run. The first frame always renders: a slow
/// or stuck startup step can no longer leave the native splash (the logo)
/// up forever with no explanation.
class LookoutBootScreen extends StatelessWidget {
  final String step;

  const LookoutBootScreen({super.key, required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Lookout',
                style: theme.textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 16),
            Text(step, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Shown when a startup step actually failed: the exact step and the
/// redacted reason, selectable so it can be copied or screenshotted. The
/// data guidance matters: watches survive on the phone as long as the app
/// is not uninstalled or its data cleared.
class LookoutBootErrorScreen extends StatelessWidget {
  final String step;
  final Object error;
  final VoidCallback onRetry;

  const LookoutBootErrorScreen({
    super.key,
    required this.step,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final red = theme.colorScheme.error;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Text('Lookout could not start',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text('Startup failed while $step.',
                  style: theme.textTheme.bodyLarge?.copyWith(color: red)),
              const SizedBox(height: 12),
              SelectableText(_redactDiagnostic('$error'),
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 24),
              Text(
                'Your watches and history are still on this phone. Do not '
                'uninstall the app or clear its data - that would delete '
                'them. A screenshot of this screen tells us exactly what '
                'went wrong.',
                style: theme.textTheme.bodyMedium,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Redacts links and file paths from a diagnostic string before it is
/// shown: an error may contain a watched URL or a storage path, and a
/// screenshot of the screen must never leak those.
String _redactDiagnostic(String raw) {
  var out = raw.replaceAll(RegExp(r'https?://\S+'), '<link>');
  out = out.replaceAll(
      RegExp(r'(/[A-Za-z0-9_.-]+){2,}[A-Za-z0-9_/.-]*'), '<path>');
  return out.length > 300 ? '${out.substring(0, 300)}...' : out;
}
