import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/preset_store.dart';
import 'improve_screen.dart';
import 'reply_screen.dart';
import 'moshaver_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  // Phase 3.6: mobile kill-switch (simple, local)
  // TODO: later wire this to remote config / AppConfig if you want
  static const bool _moshaverEnabled = true;

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
    if (!AppConfig.datingPresetsEnabled || !AppConfig.datingAddonEnabled)
      return;

    final presets = PresetStore.presets();
    final selected = PresetStore.selected;

    final chosen = await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auto ? 'Quick dating setup' : 'Dating presets',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Pick one vibe. You can change it anytime.',
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final p in presets) ...[
                    Card(
                      child: ListTile(
                        title: Text(
                          p.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
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

  void _onTap(int next) {
    if (next == 2 && !_moshaverEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moshaver is disabled (feature flag off).'),
        ),
      );
      return;
    }
    setState(() => _index = next);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ImproveScreen(),
      const ReplyScreen(),
      const MoshaverScreen(),
    ];

    return Scaffold(
      // No AppBar here; Improve/Reply already have their own Scaffold/AppBar.
      body: IndexedStack(
        index: _index.clamp(0, pages.length - 1),
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_fix_high),
            label: 'Improve',
          ),
          NavigationDestination(icon: Icon(Icons.reply), label: 'Reply'),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'Moshaver',
          ),
        ],
      ),
    );
  }
}
