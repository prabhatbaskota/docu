import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../branding/docu_logo.dart';
import '../documents/providers.dart';
import '../../core/database.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Center(child: DocuLogo(size: 72)),
          ),
          Center(
            child: Text('docu',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Appearance',
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                    label: Text('System')),
                ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode_outlined),
                    label: Text('Light')),
                ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode_outlined),
                    label: Text('Dark')),
              ],
              selected: {mode},
              onSelectionChanged: (s) =>
                  ref.read(themeProvider.notifier).setMode(s.first),
            ),
          ),
          const SizedBox(height: 16),
          _OcrLanguage(store: ref.read(settingsStoreProvider)),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Private by default'),
            subtitle:
                Text('Documents stay on this device unless you share them.'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('0.1.1'),
          ),
        ],
      ),
    );
  }
}

class _OcrLanguage extends StatefulWidget {
  final SettingsStore store;
  const _OcrLanguage({required this.store});
  @override
  State<_OcrLanguage> createState() => _OcrLanguageState();
}

class _OcrLanguageState extends State<_OcrLanguage> {
  String value = 'auto';
  @override
  void initState() {
    super.initState();
    widget.store.get('ocr_language').then((v) {
      if (mounted) setState(() => value = v ?? 'auto');
    });
  }

  @override
  Widget build(BuildContext context) => ListTile(
      title: const Text('Text recognition'),
      trailing: DropdownButton<String>(
          value: value,
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('Auto')),
            DropdownMenuItem(value: 'english', child: Text('English')),
            DropdownMenuItem(value: 'devanagari', child: Text('Devanagari'))
          ],
          onChanged: (v) {
            setState(() => value = v!);
            widget.store.set('ocr_language', v!);
          }));
}
