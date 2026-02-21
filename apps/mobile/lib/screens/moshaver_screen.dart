import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_config.dart';
import '../services/api_client.dart';
import '../services/screenshot_ocr_service.dart';

enum _ChatRole { user, assistant, system }

class _ChatMsg {
  final _ChatRole role;
  final String text;
  _ChatMsg(this.role, this.text);
}

enum _CharState {
  idle,
  listening,
  thinking,
  happy,
  concerned,
  protective,
  oops,
}

class MoshaverScreen extends StatefulWidget {
  const MoshaverScreen({super.key});

  @override
  State<MoshaverScreen> createState() => _MoshaverScreenState();
}

class _MoshaverScreenState extends State<MoshaverScreen>
    with SingleTickerProviderStateMixin {
  // ✅ This is TRUE in widget tests.
  static const bool _isTest = bool.fromEnvironment('FLUTTER_TEST');

  final _goalCtrl = TextEditingController();
  final _situationCtrl = TextEditingController();
  final _composerCtrl = TextEditingController();

  // Phase 3.6.4 — context from screenshots
  List<XFile> _ctxImages = [];
  String _ctxText = '';
  bool _ctxRedact = true;

  bool _sending = false;

  // Phase 3.6.5 — character state
  _CharState _char = _CharState.idle;

  late final AnimationController _idleAnim;

  final List<_ChatMsg> _messages = [
    _ChatMsg(
      _ChatRole.assistant,
      'Salam :) Goal-et chie? Age screenshot az chat-haye ghabli dari, mitooni add koni.',
    ),
  ];

  bool _contextExpanded = true;

  @override
  void initState() {
    super.initState();

    _idleAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    // ✅ Never start infinite animation during widget tests (pumpAndSettle will timeout)
    if (!_isTest) {
      _idleAnim.repeat(reverse: true);
    }

    _composerCtrl.addListener(() {
      if (!mounted) return;

      final hasText = _composerCtrl.text.trim().isNotEmpty;
      if (_sending) return;

      if (hasText && (_char == _CharState.idle || _char == _CharState.happy)) {
        _setChar(_CharState.listening);
      } else if (!hasText && _char == _CharState.listening) {
        _setChar(_CharState.idle);
      }
    });
  }

  @override
  void dispose() {
    _idleAnim.dispose();
    _goalCtrl.dispose();
    _situationCtrl.dispose();
    _composerCtrl.dispose();
    super.dispose();
  }

  void _setChar(_CharState s) {
    if (_char == s) return;
    setState(() => _char = s);
  }

  void _flashChar(
    _CharState s, {
    Duration d = const Duration(milliseconds: 1200),
  }) {
    _setChar(s);
    Future.delayed(d, () {
      if (!mounted) return;
      if (_char == s)
        _setChar(_sending ? _CharState.thinking : _CharState.idle);
    });
  }

  void _clearChat() {
    setState(() {
      _messages
        ..clear()
        ..add(
          _ChatMsg(
            _ChatRole.assistant,
            'Ok. Chat pak shod. Alan goal-et chie?',
          ),
        );
    });
    _setChar(_CharState.idle);
  }

  void _removeScreenshots() {
    setState(() {
      _ctxImages = [];
      _ctxText = '';
      _ctxRedact = true;
      _messages.add(_ChatMsg(_ChatRole.system, 'Screenshots removed.'));
    });
    _flashChar(_CharState.happy);
  }

  void _resetAll() {
    setState(() {
      _goalCtrl.clear();
      _situationCtrl.clear();
      _composerCtrl.clear();
      _contextExpanded = true;

      _ctxImages = [];
      _ctxText = '';
      _ctxRedact = true;

      _messages
        ..clear()
        ..add(
          _ChatMsg(
            _ChatRole.assistant,
            'Ok. Reset all anjam shod. Goal-et chie?',
          ),
        );
    });
    _setChar(_CharState.idle);
  }

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required VoidCallback onConfirm,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(body),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Confirm'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (ok == true) onConfirm();
  }

  Future<void> _openContextSheet() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> pick() async {
              final res = await ScreenshotOcrService.pickAndExtract(
                maxImages: 3,
              );
              if (res == null) return;

              var text = res.extractedText;
              if (_ctxRedact && text.isNotEmpty) {
                text = ScreenshotOcrService.redactBasic(text);
              }

              setState(() {
                _ctxImages = res.images;
                _ctxText = text;
                _messages.add(
                  _ChatMsg(
                    _ChatRole.system,
                    '${_ctxImages.length} screenshot(s) added as context.',
                  ),
                );
              });
              setSheet(() {});
              _flashChar(_CharState.happy);
            }

            Future<void> editText() async {
              final controller = TextEditingController(text: _ctxText);
              final saved = await showModalBottomSheet<bool>(
                context: ctx,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (_) {
                  return Padding(
                    padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 12,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Edit extracted text',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: controller,
                          minLines: 6,
                          maxLines: 12,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Save'),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  );
                },
              );

              if (saved == true) {
                setState(() => _ctxText = controller.text.trim());
                setSheet(() {});
                _flashChar(_CharState.happy);
              }
            }

            void clearAll() {
              setState(() {
                _ctxImages = [];
                _ctxText = '';
                _messages.add(_ChatMsg(_ChatRole.system, 'Context cleared.'));
              });
              setSheet(() {});
              _flashChar(_CharState.happy);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Context (screenshots)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pick,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Pick screenshots (max 3)'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Remove all',
                          onPressed: _ctxImages.isEmpty && _ctxText.isEmpty
                              ? null
                              : clearAll,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _ctxRedact,
                      onChanged: (v) => setState(() => _ctxRedact = v),
                      title: const Text('Remove names/numbers (recommended)'),
                    ),
                    if (_ctxImages.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 74,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _ctxImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) {
                            final img = _ctxImages[i];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(img.path),
                                    width: 74,
                                    height: 74,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  right: 2,
                                  top: 2,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() {
                                        _ctxImages = List.of(_ctxImages)
                                          ..removeAt(i);
                                        if (_ctxImages.isEmpty) _ctxText = '';
                                      });
                                      setSheet(() {});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (_ctxText.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: editText,
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit extracted text'),
                      ),
                    if (_ctxText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Preview (optional)',
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(ctx).dividerColor),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _ctxText.length > 600
                              ? '${_ctxText.substring(0, 600)}…'
                              : _ctxText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Map<String, String>> _buildChatHistory() {
    final filtered = _messages
        .where((m) => m.role != _ChatRole.system)
        .toList();
    final last = filtered.length > 16
        ? filtered.sublist(filtered.length - 16)
        : filtered;

    return last
        .map(
          (m) => {
            'role': m.role == _ChatRole.user ? 'user' : 'assistant',
            'content': m.text,
          },
        )
        .toList(growable: false);
  }

  _CharState _mapRiskToChar(dynamic data) {
    if (data is! Map) return _CharState.idle;
    final risk = data['risk'];
    if (risk is! Map) return _CharState.idle;
    final level = (risk['level'] ?? '').toString().toLowerCase().trim();
    if (level == 'high') return _CharState.concerned;
    if (level == 'medium') return _CharState.concerned;
    return _CharState.idle;
  }

  Future<void> _send() async {
    final text = _composerCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _composerCtrl.clear();
      _messages.add(_ChatMsg(_ChatRole.user, text));
      _contextExpanded = false;
    });

    _setChar(_CharState.thinking);

    final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);

    final payload = <String, dynamic>{
      'goal_text': _goalCtrl.text.trim().isEmpty ? null : _goalCtrl.text.trim(),
      'situation_text': _situationCtrl.text.trim().isEmpty
          ? null
          : _situationCtrl.text.trim(),
      'user_message': text,
      'chat_history': _buildChatHistory(),
      'context_extracted_text': _ctxText.trim().isEmpty
          ? null
          : _ctxText.trim(),
      'output_variant': 'FINGLISH',
      'hard_mode_requested': false,
    }..removeWhere((k, v) => v == null);

    try {
      final env = await api.postJson('/v1/coach/message', body: payload);

      final status = (env['status'] ?? '').toString();
      if (status == 'blocked') {
        final msg = (env['error'] is Map)
            ? (env['error']['message']?.toString() ?? 'Blocked')
            : 'Blocked';
        setState(
          () => _messages.add(_ChatMsg(_ChatRole.assistant, 'Blocked: $msg')),
        );
        _setChar(_CharState.protective);
        return;
      }

      final data = env['data'];
      if (data is! Map)
        throw Exception('Invalid coach response (missing data).');

      final assistant = data['assistant_message']?.toString().trim() ?? '';
      final bestNext = data['best_next_message']?.toString().trim() ?? '';
      final steps = (data['action_steps'] is List)
          ? (data['action_steps'] as List).map((e) => e.toString()).toList()
          : <String>[];

      final buf = StringBuffer();
      if (assistant.isNotEmpty) buf.writeln(assistant);
      if (steps.length == 3) {
        buf.writeln('\nAction steps:');
        buf.writeln('1) ${steps[0]}');
        buf.writeln('2) ${steps[1]}');
        buf.writeln('3) ${steps[2]}');
      }
      if (bestNext.isNotEmpty) buf.writeln('\nBest next message:\n$bestNext');

      setState(
        () =>
            _messages.add(_ChatMsg(_ChatRole.assistant, buf.toString().trim())),
      );

      final riskChar = _mapRiskToChar(data);
      if (riskChar == _CharState.concerned) {
        _flashChar(_CharState.concerned, d: const Duration(milliseconds: 1600));
      } else {
        _flashChar(_CharState.happy);
      }
    } catch (e) {
      setState(
        () => _messages.add(
          _ChatMsg(_ChatRole.assistant, 'Error: ${e.toString()}'),
        ),
      );
      _setChar(_CharState.oops);
      _flashChar(_CharState.oops, d: const Duration(milliseconds: 1600));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        if (_char == _CharState.thinking) _setChar(_CharState.idle);
      }
    }
  }

  String _charLabel(_CharState s) {
    switch (s) {
      case _CharState.idle:
        return 'Ready';
      case _CharState.listening:
        return 'Listening…';
      case _CharState.thinking:
        return 'Thinking…';
      case _CharState.happy:
        return 'Nice 🙂';
      case _CharState.concerned:
        return 'Careful';
      case _CharState.protective:
        return 'Protective';
      case _CharState.oops:
        return 'Oops';
    }
  }

  IconData _charIcon(_CharState s) {
    switch (s) {
      case _CharState.idle:
        return Icons.spa;
      case _CharState.listening:
        return Icons.hearing;
      case _CharState.thinking:
        return Icons.psychology;
      case _CharState.happy:
        return Icons.sentiment_satisfied_alt;
      case _CharState.concerned:
        return Icons.report_gmailerrorred;
      case _CharState.protective:
        return Icons.shield;
      case _CharState.oops:
        return Icons.error_outline;
    }
  }

  Widget _characterStrip() {
    final cs = Theme.of(context).colorScheme;
    final label = _charLabel(_char);

    // In tests animation doesn't run; value stays at 0 → scale becomes 1.0 (good)
    final scale = (_char == _CharState.idle)
        ? (1.0 + (_idleAnim.value * 0.04))
        : 1.0;

    final iconBg = switch (_char) {
      _CharState.protective => cs.errorContainer,
      _CharState.concerned => cs.tertiaryContainer,
      _CharState.oops => cs.errorContainer,
      _ => cs.surface,
    };

    final iconFg = switch (_char) {
      _CharState.protective => cs.onErrorContainer,
      _CharState.oops => cs.onErrorContainer,
      _CharState.concerned => cs.onTertiaryContainer,
      _ => cs.onSurface,
    };

    final text = _sending
        ? 'Dar hal-e fekr...'
        : (_composerCtrl.text.trim().isNotEmpty
              ? 'Begu chi داری minevisi...'
              : 'Man inja-am. Har chi mikhay begu.');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _idleAnim,
            builder: (ctx, _) {
              return Transform.scale(
                scale: scale,
                child: CircleAvatar(
                  backgroundColor: iconBg,
                  foregroundColor: iconFg,
                  child: Icon(_charIcon(_char)),
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contextCard() {
    final goal = _goalCtrl.text.trim();
    final situation = _situationCtrl.text.trim();

    if (!_contextExpanded) {
      final pieces = <String>[];
      if (goal.isNotEmpty)
        pieces.add(
          'Goal: ${goal.length > 40 ? '${goal.substring(0, 40)}…' : goal}',
        );
      if (situation.isNotEmpty)
        pieces.add(
          'Situation: ${situation.length > 40 ? '${situation.substring(0, 40)}…' : situation}',
        );
      if (_ctxText.trim().isNotEmpty)
        pieces.add(
          'Context: ${_ctxImages.length} screenshot${_ctxImages.length == 1 ? '' : 's'}',
        );
      if (pieces.isEmpty) pieces.add('Tap to add goal/situation');

      return InkWell(
        onTap: () => setState(() => _contextExpanded = true),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.4),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  pieces.join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit, size: 18),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Goal', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _goalCtrl,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText:
                      'Goal-et chiye? (mesalan: mikham ba tarafam better harf bezanam…)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Situation (optional)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear',
                    onPressed: () => setState(() => _situationCtrl.clear()),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _situationCtrl,
                minLines: 3,
                maxLines: 10,
                decoration: const InputDecoration(
                  hintText: 'Age mikhay sharayet ro tozih bedi (optional)…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openContextSheet,
                icon: const Icon(Icons.add),
                label: Text(
                  _ctxText.trim().isEmpty
                      ? '+ Add chat screenshots'
                      : 'Edit screenshots context',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "We'll use these only to understand context. Only extracted text is sent.",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(_ChatMsg m) {
    final isUser = m.role == _ChatRole.user;

    final bg = m.role == _ChatRole.system
        ? Theme.of(context).colorScheme.surface
        : isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    final fg = m.role == _ChatRole.system
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isUser
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurface;

    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: m.role == _ChatRole.system
                ? Border.all(
                    color: Theme.of(context).dividerColor.withOpacity(0.5),
                  )
                : null,
          ),
          child: Text(m.text, style: TextStyle(color: fg)),
        ),
      ],
    );
  }

  Widget _composer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            IconButton(
              onPressed: _openContextSheet,
              icon: const Icon(Icons.add_circle_outline),
              tooltip: 'Attach screenshots',
            ),
            Expanded(
              child: TextField(
                controller: _composerCtrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Type your message…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moshaver'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'clear') {
                _confirmAndRun(
                  title: 'Clear chat',
                  body: 'In faqat timeline ro pak mikone.',
                  onConfirm: _clearChat,
                );
              } else if (v == 'remove_screens') {
                _confirmAndRun(
                  title: 'Remove screenshots',
                  body: 'Screenshot context hazf mishe (faghat text).',
                  onConfirm: _removeScreenshots,
                );
              } else if (v == 'reset') {
                _confirmAndRun(
                  title: 'Reset all',
                  body: 'Chat + goal + situation + screenshots reset mishe.',
                  onConfirm: _resetAll,
                );
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear chat')),
              PopupMenuItem(
                value: 'remove_screens',
                child: Text('Remove screenshots'),
              ),
              PopupMenuItem(value: 'reset', child: Text('Reset all')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _characterStrip(),
          _contextCard(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _bubble(_messages[i]),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }
}
