import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../models/reply_response.dart';
import '../services/api_client.dart';
import '../services/preset_store.dart';

class ReplyScreen extends StatefulWidget {
  const ReplyScreen({super.key});

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  final _controller = TextEditingController();
  bool _hardMode = false;
  String _variant = 'FINGLISH';

  // Phase 3.5 (Dating Add-on) — UI state (guarded by feature flag)
  String _flirtMode = 'off'; // off | subtle | playful | direct

  // Phase 3.5 (I'm stuck) — UI state
  bool _iStuckActive = false;
  String _iStuckGoal = 'Reply friendly'; // Reply friendly | Set boundary | Flirt back | Suggest plan
  String _iStuckVibe = 'Calm'; // Calm | Playful | Direct
  String _iStuckDetail = '';

  bool _loading = false;
  ReplyResponse? _result;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Apply preset defaults once (V1 in-memory)
    if (AppConfig.datingPresetsEnabled &&
        AppConfig.datingAddonEnabled &&
        PresetStore.selected != null) {
      final p = PresetStore.selected!;
      _flirtMode = p.flirtMode;
      _iStuckGoal = p.replyGoal;
      _iStuckVibe = p.replyVibe;
    }

    _controller.addListener(() {
      if (_result != null || _error != null) {
        setState(() {
          _result = null;
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_loading && _controller.text.trim().isNotEmpty;

  void _clearAll() {
    setState(() {
      _controller.clear();
      _result = null;
      _error = null;
      _loading = false;

      _flirtMode = 'off';

      _iStuckActive = false;
      _iStuckGoal = 'Reply friendly';
      _iStuckVibe = 'Calm';
      _iStuckDetail = '';
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);

    final input = <String, dynamic>{
      'received_text': _controller.text.trim(),
      'hard_mode': _hardMode,
      'output_variant': _variant,
    };

    if (AppConfig.datingAddonEnabled) {
      input['flirt_mode'] = _flirtMode;
    }

    final body = {'input': input};

    try {
      final env = await api.postEnvelope(
        '/v1/reply',
        body: body,
        fromJson: ReplyResponse.fromJson,
      );

      setState(() {
        _result = env.data;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Widget _datingChipRow() {
    if (!AppConfig.datingAddonEnabled) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          'Flirt mode',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ModeChip(label: 'Off', value: 'off', groupValue: _flirtMode, onSelected: (v) => setState(() => _flirtMode = v)),
            _ModeChip(label: 'Subtle', value: 'subtle', groupValue: _flirtMode, onSelected: (v) => setState(() => _flirtMode = v)),
            _ModeChip(label: 'Playful', value: 'playful', groupValue: _flirtMode, onSelected: (v) => setState(() => _flirtMode = v)),
            _ModeChip(label: 'Direct', value: 'direct', groupValue: _flirtMode, onSelected: (v) => setState(() => _flirtMode = v)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _flirtMode == 'off' ? 'Normal tone (no flirting).' : 'Dating tone enabled: $_flirtMode',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // ---------- I'm stuck flow ----------
  Future<void> _openIStuckSheet() async {
    if (!AppConfig.iStuckEnabled) return;

    String goal = _iStuckGoal;
    String vibe = _iStuckVibe;
    final detailCtrl = TextEditingController(text: _iStuckDetail);

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("I'm stuck", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),

                  const Text('Goal', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(label: const Text('Reply friendly'), selected: goal == 'Reply friendly', onSelected: (_) => setSheetState(() => goal = 'Reply friendly')),
                      ChoiceChip(label: const Text('Set boundary'), selected: goal == 'Set boundary', onSelected: (_) => setSheetState(() => goal = 'Set boundary')),
                      ChoiceChip(label: const Text('Flirt back'), selected: goal == 'Flirt back', onSelected: (_) => setSheetState(() => goal = 'Flirt back')),
                      ChoiceChip(label: const Text('Suggest plan'), selected: goal == 'Suggest plan', onSelected: (_) => setSheetState(() => goal = 'Suggest plan')),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Text('Vibe', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(label: const Text('Calm'), selected: vibe == 'Calm', onSelected: (_) => setSheetState(() => vibe = 'Calm')),
                      ChoiceChip(label: const Text('Playful'), selected: vibe == 'Playful', onSelected: (_) => setSheetState(() => vibe = 'Playful')),
                      ChoiceChip(label: const Text('Direct'), selected: vibe == 'Direct', onSelected: (_) => setSheetState(() => vibe = 'Direct')),
                    ],
                  ),

                  const SizedBox(height: 12),
                  const Text('One detail (optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'e.g., they asked about weekend, they were cold, they joked…',
                    ),
                    maxLines: 2,
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(ctx).pop({
                              'goal': goal,
                              'vibe': vibe,
                              'detail': detailCtrl.text.trim(),
                            });
                          },
                          child: const Text('Generate reply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _iStuckGoal = result['goal'] ?? _iStuckGoal;
      _iStuckVibe = result['vibe'] ?? _iStuckVibe;
      _iStuckDetail = result['detail'] ?? _iStuckDetail;
      _iStuckActive = true;

      final detail = (_iStuckDetail.trim().isEmpty) ? '' : ', detail: ${_iStuckDetail.trim()}';
      _controller.text = "I'm stuck: goal: $_iStuckGoal, vibe: $_iStuckVibe$detail";
    });

    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );

    await _submit();
  }

  Widget _iStuckCTA() {
    if (!AppConfig.iStuckEnabled) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: _openIStuckSheet,
        child: const Text("I'm stuck"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _result?.suggestions ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Reply')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoBar(text: 'API: ${AppConfig.apiBaseUrl}'),
          const SizedBox(height: 12),

          const Text(
            'Paste the message you received',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _controller,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Received message...',
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 8),
          _iStuckCTA(),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_variant),
                  initialValue: _variant,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Output variant',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'FINGLISH', child: Text('Finglish')),
                    DropdownMenuItem(value: 'EN', child: Text('English')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _variant = v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  value: _hardMode,
                  onChanged: (v) => setState(() => _hardMode = v),
                  title: const Text('Hard mode'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),

          _datingChipRow(),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_iStuckActive ? 'Generate reply' : 'Generate replies'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _loading ? null : _clearAll,
                child: const Text('Clear'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (_error != null) ...[
            _ErrorCard(message: _error!, onRetry: _canSubmit ? _submit : null),
            const SizedBox(height: 12),
          ],

          if (_result != null) ...[
            _RiskCard(
              level: _result!.risk.level,
              score: _result!.risk.score,
              reasons: _result!.risk.reasons,
              voiceMatchScore: _result!.voiceMatchScore,
            ),
            const SizedBox(height: 12),
            const Text(
              'Suggestions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final s in suggestions) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(s.text),
                      const SizedBox(height: 8),
                      Text(
                        s.whyItWorks,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => _copy(s.text),
                            child: const Text('Copy'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onSelected,
  });

  final String label;
  final String value;
  final String groupValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _ErrorCard extends StatefulWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  State<_ErrorCard> createState() => _ErrorCardState();
}

class _ErrorCardState extends State<_ErrorCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final previewLen = 220;
    final canExpand = msg.length > previewLen;
    final shown = (!_expanded && canExpand) ? '${msg.substring(0, previewLen)}…' : msg;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Error', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectableText(shown, style: const TextStyle(color: Colors.red)),
            if (canExpand) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show more'),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton(
                  onPressed: widget.onRetry,
                  child: const Text('Retry'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: msg));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error copied')),
                    );
                  },
                  child: const Text('Copy error'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  const _RiskCard({
    required this.level,
    required this.score,
    required this.reasons,
    required this.voiceMatchScore,
  });

  final String level;
  final int score;
  final List<String> reasons;
  final int voiceMatchScore;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Risk: $level ($score) • Voice match: $voiceMatchScore',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final r in reasons) Text('• $r'),
          ],
        ),
      ),
    );
  }
}
