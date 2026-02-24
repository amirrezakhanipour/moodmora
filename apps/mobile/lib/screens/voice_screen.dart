import 'dart:async';

import 'package:flutter/material.dart';

import '../models/voice_profile.dart';
import '../services/voice_store.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  final _store = VoiceStore();

  bool _loading = true;
  VoiceState _state = VoiceState.defaults();

  Timer? _saveDebounce;
  final _doNotUseCtrl = TextEditingController();

  static const _variants = <String>['AUTO', 'FA_SCRIPT', 'FINGLISH', 'EN'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await _store.load();
      if (!mounted) return;
      setState(() {
        _state = loaded;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = VoiceState.defaults();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _doNotUseCtrl.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        await _store.save(_state);
      } catch (_) {
        // ignore storage failures
      }
    });
  }

  void _setEnabled(bool v) {
    setState(() {
      _state = VoiceState(
        enabled: v,
        variant: _state.variant,
        profile: _state.profile,
      );
    });
    _scheduleSave();
  }

  void _setVariant(String v) {
    setState(() {
      _state = VoiceState(
        enabled: _state.enabled,
        variant: v,
        profile: _state.profile,
      );
    });
    _scheduleSave();
  }

  void _setProfile(VoiceProfile p) {
    setState(() {
      _state = VoiceState(
        enabled: _state.enabled,
        variant: _state.variant,
        profile: p,
      );
    });
    _scheduleSave();
  }

  void _reset() async {
    final next = VoiceState.defaults();
    setState(() {
      _state = next;
    });
    try {
      await _store.save(next);
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Voice profile reset')));
  }

  void _addDoNotUse() {
    final raw = _doNotUseCtrl.text.trim();
    if (raw.isEmpty) return;

    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) return;

    final existing = _state.profile.doNotUse.toList();
    for (final p in parts) {
      if (!existing.contains(p)) existing.add(p);
    }

    _doNotUseCtrl.clear();
    _setProfile(_state.profile.copyWith(doNotUse: existing));
  }

  void _removeDoNotUse(String item) {
    final next = _state.profile.doNotUse.where((x) => x != item).toList();
    _setProfile(_state.profile.copyWith(doNotUse: next));
  }

  Widget _slider({
    required String title,
    required double value,
    required ValueChanged<double> onChanged,
    String? hint,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(value.toStringAsFixed(2)),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            Slider(
              value: value.clamp(0, 1),
              min: 0,
              max: 1,
              divisions: 100,
              onChanged: _state.enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _state.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Build My Voice'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _reset,
            child: const Text('Reset'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Voice',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: _state.enabled,
                          onChanged: _setEnabled,
                          title: const Text('Enable voice'),
                          subtitle: Text(
                            _state.enabled
                                ? 'We will try to match your style.'
                                : 'Off: default assistant voice.',
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: _state.variant,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Variant',
                          ),
                          items: _variants
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: _state.enabled
                              ? (v) {
                                  if (v == null) return;
                                  _setVariant(v);
                                }
                              : null,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tip: even if you choose AUTO, the app may still send your preferred variant when voice is enabled.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                _slider(
                  title: 'Warmth',
                  value: p.warmth,
                  hint: '0 = colder, 1 = warmer',
                  onChanged: (v) => _setProfile(p.copyWith(warmth: v)),
                ),
                _slider(
                  title: 'Directness',
                  value: p.directness,
                  hint: '0 = softer, 1 = more direct',
                  onChanged: (v) => _setProfile(p.copyWith(directness: v)),
                ),
                _slider(
                  title: 'Brevity',
                  value: p.brevity,
                  hint: '0 = more detailed, 1 = shorter',
                  onChanged: (v) => _setProfile(p.copyWith(brevity: v)),
                ),
                _slider(
                  title: 'Formality',
                  value: p.formality,
                  hint: '0 = casual, 1 = formal',
                  onChanged: (v) => _setProfile(p.copyWith(formality: v)),
                ),
                _slider(
                  title: 'Emoji rate',
                  value: p.emojiRate,
                  hint: '0 = no emoji, 1 = lots of emoji',
                  onChanged: (v) => _setProfile(p.copyWith(emojiRate: v)),
                ),

                const SizedBox(height: 12),

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Do not use',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add words/phrases you dislike. Separate by commas.',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _doNotUseCtrl,
                                enabled: _state.enabled,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'e.g., lotfan, ba ehteram',
                                ),
                                onSubmitted: (_) => _addDoNotUse(),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: _state.enabled ? _addDoNotUse : null,
                              child: const Text('Add'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (p.doNotUse.isEmpty)
                          Text(
                            'No items yet.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final item in p.doNotUse)
                                InputChip(
                                  label: Text(item),
                                  onDeleted: _state.enabled
                                      ? () => _removeDoNotUse(item)
                                      : null,
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
    );
  }
}
