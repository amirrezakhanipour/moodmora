import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/preset_store.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Micro-onboarding V1: auto-prompt once per app run (in-memory)
    if (AppConfig.datingPresetsEnabled &&
        AppConfig.datingAddonEnabled &&
        !PresetStore.didAutoPrompt) {
      PresetStore.markAutoPromptShown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openPresetsSheet(auto: true);
      });
    }
  }

  Future<void> _openPresetsSheet({bool auto = false}) async {
    if (!AppConfig.datingPresetsEnabled || !AppConfig.datingAddonEnabled) return;

    final presets = PresetStore.presets();
    final selected = PresetStore.selected;

    final chosen = await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true, // ✅ allow taller + scroll behavior
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            // ✅ prevent RenderFlex overflow in small heights (tests, small screens)
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auto ? 'Quick dating setup' : 'Dating presets',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pick one vibe. You can change it anytime.',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),

                  for (final p in presets) ...[
                    Card(
                      child: ListTile(
                        title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(p.description),
                        trailing: (selected?.id == p.id)
                            ? const Icon(Icons.check_circle)
                            : const Icon(Icons.circle_outlined),
                        onTap: () => Navigator.of(ctx).pop(p),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (selected != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop('CLEAR'),
                      child: const Text('Clear preset'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || chosen == null) return;

    if (chosen == 'CLEAR') {
      setState(() => PresetStore.clear());
      return;
    }

    setState(() {
      PresetStore.setSelected(chosen);
    });
  }

  Widget _presetsCard() {
    if (!AppConfig.datingPresetsEnabled || !AppConfig.datingAddonEnabled) {
      return const SizedBox.shrink();
    }

    final p = PresetStore.selected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dating presets',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              p == null ? 'No preset selected' : '${p.title} — ${p.description}',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  onPressed: () => _openPresetsSheet(),
                  child: Text(p == null ? 'Choose preset' : 'Change preset'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MoodMora')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose a mode',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Micro-onboarding/presets card
            _presetsCard(),
            const SizedBox(height: 12),

            FilledButton(
              onPressed: () => Navigator.pushNamed(context, '/improve'),
              child: const Text('Improve a message'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pushNamed(context, '/reply'),
              child: const Text('Write a reply'),
            ),
          ],
        ),
      ),
    );
  }
}
