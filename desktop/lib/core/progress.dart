import 'package:flutter/material.dart';

/// Modal progress dialog around [task]. The task reports (done, total) and
/// the bar fills; the dialog closes itself when the task ends (or throws).
Future<T> runWithProgress<T>(
  BuildContext context,
  String title,
  Future<T> Function(void Function(int done, int total) report) task,
) async {
  final progress = ValueNotifier<double?>(null);
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: v, minHeight: 8),
              ),
              const SizedBox(height: 12),
              Text(v == null ? 'Working...' : '${(v * 100).round()}%'),
            ],
          ),
        ),
      ),
    ),
  );
  try {
    return await task((done, total) {
      progress.value = total == 0 ? null : done / total;
    });
  } finally {
    nav.pop();
    // Not disposed: the closing dialog may rebuild once more; the notifier
    // is tiny and is garbage-collected with the route.
  }
}
