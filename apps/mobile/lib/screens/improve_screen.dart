import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../models/improve_response.dart';
import '../models/voice_profile.dart';
import '../services/api_client.dart';
import '../services/preset_store.dart';
import '../services/voice_store.dart';

class ImproveScreen extends StatefulWidget {
  const ImproveScreen({super.key});

  @override
  State<ImproveScreen> createState() => _ImproveScreenState();
}

class _ImproveScreenState extends State<ImproveScreen> {
  final _controller = TextEditingController();
  bool _hardMode = false;
  String _variant = 'FINGLISH';

  // Phase 3.5 (Dating Add-on) — UI state (guarded by feature flag)
  String _flirtMode = 'off'; // off | subtle | playful | direct

  // Phase 3.5 (Starter Kit) — UI state
  bool _starterFlowActive = false;
  String _starterStage = 'First message';
  String _starterVibe = 'Funny';
  String _starterDetail = '';

  bool _loading = false;
  ImproveResponse? _result;
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
      _starterVibe = p.starterVibe;
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

  bool get _isEmptyState =>
      _controller.text.trim().isEmpty &&
      _result == null &&
      _error == null &&
      !_loading;

  void _clearAll() {
    setState(() {
      _controller.clear();
      _result = null;
      _error = null;
      _loading = false;

      _flirtMode = 'off';

      _starterFlowActive = false;
      _starterStage = 'First message';
      _starterVibe = 'Funny';
      _starterDetail = '';
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
      'draft_text': _controller.text.trim(),
      'hard_mode': _hardMode,
      'output_variant': _variant,
    };

    if (AppConfig.datingAddonEnabled) {
      input['flirt_mode'] = _flirtMode;
    }

    final body = <String, dynamic>{'input': input};

    // Phase 5: Build My Voice (local-first)
    // If voice is enabled locally, attach root-level `voice` object to request.
    try {
      final voiceState = await VoiceStore().load();
      if (voiceState.enabled) {
        body['voice'] = voiceState.toJson();
      }
    } catch (_) {
      // Never block request if local storage fails.
    }

    try {
      final env = await api.postEnvelope(
        '/v1/improve',
        body: body,
        fromJson: ImproveResponse.fromJson,
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  // ---------- Dating chip row ----------
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
            _ModeChip(
              label: 'Off',
              value: 'off',
              groupValue: _flirtMode,
              onSelected: (v) => setState(() => _flirtMode = v),
            ),
            _ModeChip(
              label: 'Subtle',
              value: 'subtle',
              groupValue: _flirtMode,
              onSelected: (v) => setState(() => _flirtMode = v),
            ),
            _ModeChip(
              label: 'Playful',
              value: 'playful',
              groupValue: _flirtMode,
              onSelected: (v) => setState(() => _flirtMode = v),
            ),
            _ModeChip(
              label: 'Direct',
              value: 'direct',
              groupValue: _flirtMode,
              onSelected: (v) => setState(() => _flirtMode = v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _flirtMode == 'off'
              ? 'Normal tone (no flirting).'
              : 'Dating tone enabled: $_flirtMode',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // ---------- Starter Kit (Layer A) ----------
  void _applyStarterTemplate(String template) {
    setState(() {
      _starterFlowActive = false;
      _controller.text = template;
    });
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
  }

  Widget _starterTemplatesRow() {
    if (!AppConfig.starterKitEnabled) return const SizedBox.shrink();
    if (!_isEmptyState) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Starter templates',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Compliment + Question'),
              selected: false,
              onSelected: (_) => _applyStarterTemplate(
                "Hey! I really liked [something specific about you]. Quick question: what's your favorite [topic] these days?",
              ),
            ),
            ChoiceChip(
              label: const Text('Funny opener'),
              selected: false,
              onSelected: (_) => _applyStarterTemplate(
                "Serious question: are you more of a [A] person or a [B] person? (I'm judging politely.)",
              ),
            ),
            ChoiceChip(
              label: const Text('Shared interest'),
              selected: false,
              onSelected: (_) => _applyStarterTemplate(
                "I saw you're into [interest]—I'm curious, how did you get into it?",
              ),
            ),
            ChoiceChip(
              label: const Text('Simple hi + hook'),
              selected: false,
              onSelected: (_) => _applyStarterTemplate(
                "Hey :) How's your day going? What's one thing you're excited about this week?",
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- Starter Kit (Layer B) ----------
  Future<void> _openStartersSheet() async {
    if (!AppConfig.starterKitEnabled) return;

    String stage = _starterStage;
    String vibe = _starterVibe;
    final detailCtrl = TextEditingController(text: _starterDetail);

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
                  const Text(
                    'Give me 3 starters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Stage',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('First message'),
                        selected: stage == 'First message',
                        onSelected: (_) =>
                            setSheetState(() => stage = 'First message'),
                      ),
                      ChoiceChip(
                        label: const Text('After match'),
                        selected: stage == 'After match',
                        onSelected: (_) =>
                            setSheetState(() => stage = 'After match'),
                      ),
                      ChoiceChip(
                        label: const Text('Re-open chat'),
                        selected: stage == 'Re-open chat',
                        onSelected: (_) =>
                            setSheetState(() => stage = 'Re-open chat'),
                      ),
                      ChoiceChip(
                        label: const Text('After date'),
                        selected: stage == 'After date',
                        onSelected: (_) =>
                            setSheetState(() => stage = 'After date'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vibe',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Cute'),
                        selected: vibe == 'Cute',
                        onSelected: (_) => setSheetState(() => vibe = 'Cute'),
                      ),
                      ChoiceChip(
                        label: const Text('Funny'),
                        selected: vibe == 'Funny',
                        onSelected: (_) => setSheetState(() => vibe = 'Funny'),
                      ),
                      ChoiceChip(
                        label: const Text('Confident'),
                        selected: vibe == 'Confident',
                        onSelected: (_) =>
                            setSheetState(() => vibe = 'Confident'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'One detail about them (optional)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailCtrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          'e.g., loves hiking, works in design, has a dog...',
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
                              'stage': stage,
                              'vibe': vibe,
                              'detail': detailCtrl.text.trim(),
                            });
                          },
                          child: const Text('Generate starters'),
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
      _starterStage = result['stage'] ?? _starterStage;
      _starterVibe = result['vibe'] ?? _starterVibe;
      _starterDetail = result['detail'] ?? _starterDetail;
      _starterFlowActive = true;

      final detail = (_starterDetail.trim().isEmpty)
          ? ''
          : ', detail: ${_starterDetail.trim()}';
      _controller.text =
          'Starter request: stage: $_starterStage, vibe: $_starterVibe$detail';
    });

    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );

    await _submit();
  }

  Widget _starterCTA() {
    if (!AppConfig.starterKitEnabled) return const SizedBox.shrink();
    if (!_isEmptyState) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _openStartersSheet,
          child: const Text('Give me 3 starters'),
        ),
      ),
    );
  }

  String _starterLabelForIndex(int idx, String fallback) {
    if (!_starterFlowActive) return fallback;
    if (idx == 0) return 'Subtle';
    if (idx == 1) return 'Playful';
    if (idx == 2) return 'Direct';
    return fallback;
  }

  String _suggestionsTitle(ImproveResponse r) {
    if (r.hardModeApplied) return 'Hard Mode (2 options)';
    return _starterFlowActive ? 'Starters' : 'Suggestions';
  }

  // ---------- Phase 5.6: local voice feedback helpers ----------
  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  int _wordCount(String s) {
    final t = s.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((x) => x.trim().isNotEmpty).length;
  }

  int _emojiCount(String s) {
    // naive emoji detect; good enough for feedback loop
    final r = RegExp(r'[\u2600-\u27BF\uD83C-\uDBFF\uDC00-\uDFFF]');
    return r.allMatches(s).length;
  }

  double _measuredBrevity(String text) {
    final wc = _wordCount(text);
    if (wc <= 8) return 1.0;
    if (wc <= 14) return 0.7;
    if (wc <= 22) return 0.4;
    return 0.2;
  }

  double _measuredEmojiRate(String text) {
    final e = _emojiCount(text);
    // 0..2 per msg -> 0..1
    return _clamp01(e / 2.0);
  }

  bool _containsAny(String text, List<String> tokens) {
    final low = text.toLowerCase();
    return tokens.any((t) => low.contains(t));
  }

  double _measuredFormality(String text) {
    final tokens = [
      'please',
      'kindly',
      'regards',
      'sincerely',
      'dear',
      'with respect',
      'lotfan',
      'ba ehteram',
    ];
    return _containsAny(text, tokens) ? 0.8 : 0.3;
  }

  double _measuredDirectness(String text) {
    final hedge = [
      'maybe',
      'if you want',
      'up to you',
      'no worries if',
      'whenever you can',
      'age ok',
      'agar ok',
      'har vaght',
    ];
    return _containsAny(text, hedge) ? 0.35 : 0.7;
  }

  double _measuredWarmth(String text) {
    final warm = [
      'thanks',
      'thank you',
      'appreciate',
      'mersi',
      'mamnoon',
      'khoshal',
      '❤️',
      '😊',
      '🙂',
    ];
    return _containsAny(text, warm) ? 0.8 : 0.45;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Future<void> _applyVoiceUpdate(
    VoiceState Function(VoiceState) updater, {
    String toast = 'Saved to voice profile',
  }) async {
    try {
      final store = VoiceStore();
      final cur = await store.load();
      final next = updater(cur);
      await store.save(next);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(toast)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save voice profile')),
      );
    }
  }

  Future<void> _likeSuggestion(String text) async {
    await _applyVoiceUpdate((cur) {
      final p = cur.profile;

      final targetBrevity = _measuredBrevity(text);
      final targetEmoji = _measuredEmojiRate(text);
      final targetFormality = _measuredFormality(text);
      final targetDirectness = _measuredDirectness(text);
      final targetWarmth = _measuredWarmth(text);

      final nextProfile = p.copyWith(
        brevity: _clamp01(_lerp(p.brevity, targetBrevity, 0.18)),
        emojiRate: _clamp01(_lerp(p.emojiRate, targetEmoji, 0.18)),
        formality: _clamp01(_lerp(p.formality, targetFormality, 0.18)),
        directness: _clamp01(_lerp(p.directness, targetDirectness, 0.18)),
        warmth: _clamp01(_lerp(p.warmth, targetWarmth, 0.18)),
      );

      return VoiceState(
        enabled: true,
        variant: cur.variant,
        profile: nextProfile,
      );
    }, toast: 'Saved (more like this)');
  }

  Future<void> _dislikeSuggestion(String text) async {
    await _applyVoiceUpdate((cur) {
      final p = cur.profile;

      final targetBrevity = _measuredBrevity(text);
      final targetEmoji = _measuredEmojiRate(text);
      final targetFormality = _measuredFormality(text);
      final targetDirectness = _measuredDirectness(text);
      final targetWarmth = _measuredWarmth(text);

      // move away from target
      double away(double current, double target) {
        final dir = current >= target ? 1 : -1;
        return _clamp01(current + dir * 0.12);
      }

      final nextProfile = p.copyWith(
        brevity: away(p.brevity, targetBrevity),
        emojiRate: away(p.emojiRate, targetEmoji),
        formality: away(p.formality, targetFormality),
        directness: away(p.directness, targetDirectness),
        warmth: away(p.warmth, targetWarmth),
      );

      return VoiceState(
        enabled: true,
        variant: cur.variant,
        profile: nextProfile,
      );
    }, toast: 'Saved (less like this)');
  }

  Future<void> _adjustChip({
    required String label,
    required VoiceProfile Function(VoiceProfile) mutate,
  }) async {
    await _applyVoiceUpdate((cur) {
      final nextProfile = mutate(cur.profile);
      return VoiceState(
        enabled: true,
        variant: cur.variant,
        profile: nextProfile,
      );
    }, toast: 'Saved: $label');
  }

  Future<void> _avoidPhraseDialog() async {
    final ctrl = TextEditingController();
    final phrase = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Avoid phrase'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'e.g., lotfan',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    final p = (phrase ?? '').trim();
    if (p.isEmpty) return;

    await _applyVoiceUpdate((cur) {
      final list = cur.profile.doNotUse.toList();
      if (!list.contains(p)) list.add(p);
      final nextProfile = cur.profile.copyWith(doNotUse: list);
      return VoiceState(
        enabled: true,
        variant: cur.variant,
        profile: nextProfile,
      );
    }, toast: 'Saved: avoid "$p"');
  }

  Widget _voiceFeedbackRow(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'More like this',
              onPressed: () => _likeSuggestion(text),
              icon: const Icon(Icons.thumb_up_alt_outlined),
            ),
            IconButton(
              tooltip: 'Less like this',
              onPressed: () => _dislikeSuggestion(text),
              icon: const Icon(Icons.thumb_down_alt_outlined),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: () => _copy(text),
              child: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              label: const Text('Shorter'),
              onPressed: () => _adjustChip(
                label: 'Shorter',
                mutate: (p) => p.copyWith(brevity: _clamp01(p.brevity + 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('Longer'),
              onPressed: () => _adjustChip(
                label: 'Longer',
                mutate: (p) => p.copyWith(brevity: _clamp01(p.brevity - 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('Warmer'),
              onPressed: () => _adjustChip(
                label: 'Warmer',
                mutate: (p) => p.copyWith(warmth: _clamp01(p.warmth + 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('Colder'),
              onPressed: () => _adjustChip(
                label: 'Colder',
                mutate: (p) => p.copyWith(warmth: _clamp01(p.warmth - 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('More direct'),
              onPressed: () => _adjustChip(
                label: 'More direct',
                mutate: (p) =>
                    p.copyWith(directness: _clamp01(p.directness + 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('Softer'),
              onPressed: () => _adjustChip(
                label: 'Softer',
                mutate: (p) =>
                    p.copyWith(directness: _clamp01(p.directness - 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('More formal'),
              onPressed: () => _adjustChip(
                label: 'More formal',
                mutate: (p) =>
                    p.copyWith(formality: _clamp01(p.formality + 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('More casual'),
              onPressed: () => _adjustChip(
                label: 'More casual',
                mutate: (p) =>
                    p.copyWith(formality: _clamp01(p.formality - 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('More emoji'),
              onPressed: () => _adjustChip(
                label: 'More emoji',
                mutate: (p) =>
                    p.copyWith(emojiRate: _clamp01(p.emojiRate + 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('Less emoji'),
              onPressed: () => _adjustChip(
                label: 'Less emoji',
                mutate: (p) =>
                    p.copyWith(emojiRate: _clamp01(p.emojiRate - 0.08)),
              ),
            ),
            ActionChip(
              label: const Text('Avoid phrase...'),
              onPressed: _avoidPhraseDialog,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _result?.suggestions ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Improve')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoBar(text: 'API: ${AppConfig.apiBaseUrl}'),
          const SizedBox(height: 12),

          const Text(
            'Paste your draft message',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _controller,
            maxLines: 6,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Write your message here...',
            ),
            onChanged: (_) => setState(() {}),
          ),

          _starterTemplatesRow(),
          _starterCTA(),

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
                    DropdownMenuItem(
                      value: 'FINGLISH',
                      child: Text('Finglish'),
                    ),
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
                      : Text(
                          _starterFlowActive ? 'Generate starters' : 'Improve',
                        ),
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

            if (_result!.hardModeApplied) ...[
              _HardModeCard(
                safetyLine: _result!.safetyLine,
                bestQuestion: _result!.bestQuestion,
                onCopy: _copy,
              ),
              const SizedBox(height: 12),
            ],

            Text(
              _suggestionsTitle(_result!),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            for (int i = 0; i < suggestions.length; i++) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _starterLabelForIndex(i, suggestions[i].label),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(suggestions[i].text),
                      const SizedBox(height: 8),
                      Text(
                        suggestions[i].whyItWorks,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _voiceFeedbackRow(suggestions[i].text),
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

class _HardModeCard extends StatelessWidget {
  const _HardModeCard({
    required this.safetyLine,
    required this.bestQuestion,
    required this.onCopy,
  });

  final String? safetyLine;
  final String? bestQuestion;
  final Future<void> Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    final sl = (safetyLine ?? '').trim();
    final bq = (bestQuestion ?? '').trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Hard Mode',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (sl.isNotEmpty) ...[
              const Text(
                'Safety line',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(sl),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => onCopy(sl),
                child: const Text('Copy safety line'),
              ),
              const SizedBox(height: 12),
            ],
            if (bq.isNotEmpty) ...[
              const Text(
                'Best question',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(bq),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => onCopy(bq),
                child: const Text('Copy best question'),
              ),
            ],
          ],
        ),
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
    final shown = (!_expanded && canExpand)
        ? '${msg.substring(0, previewLen)}...'
        : msg;

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
