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

class MoshaverScreen extends StatefulWidget {
  const MoshaverScreen({super.key});

  @override
  State<MoshaverScreen> createState() => _MoshaverScreenState();
}

class _MoshaverScreenState extends State<MoshaverScreen> {
  final _goalCtrl = TextEditingController();
  final _situationCtrl = TextEditingController();
  final _composerCtrl = TextEditingController();

  // Phase 3.6.4 — context from screenshots
  List<XFile> _ctxImages = [];
  String _ctxText = '';
  bool _ctxRedact = true;

  bool _sending = false;

  final List<_ChatMsg> _messages = [
    _ChatMsg(
      _ChatRole.assistant,
      'Salam :) Goal-et chie? Age screenshot az chat-haye ghabli dari, mitooni add koni.',
    ),
  ];

  bool _contextExpanded = true;

  @override
  void dispose() {
    _goalCtrl.dispose();
    _situationCtrl.dispose();
    _composerCtrl.dispose();
    super.dispose();
  }

  void _clearChat() {
    setState(() {
      _messages
        ..clear()
        ..add(
          _ChatMsg(_ChatRole.assistant, 'Ok. Chat پاک شد. Alan goal-et chie?'),
        );
    });
  }

  void _removeScreenshots() {
    setState(() {
      _ctxImages = [];
      _ctxText = '';
      _ctxRedact = true;
      _messages.add(_ChatMsg(_ChatRole.system, 'Screenshots removed.'));
    });
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
            'Ok. Reset all انجام شد. Goal-et chie?',
          ),
        );
    });
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
              }
            }

            void clearAll() {
              setState(() {
                _ctxImages = [];
                _ctxText = '';
                _messages.add(_ChatMsg(_ChatRole.system, 'Context cleared.'));
              });
              setSheet(() {});
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
    // Take last 16 user/assistant messages, ignore system
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

  Future<void> _send() async {
    final text = _composerCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _composerCtrl.clear();
      _messages.add(_ChatMsg(_ChatRole.user, text));
    });

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
    };

    // Remove null keys
    payload.removeWhere((k, v) => v == null);

    try {
      final env = await api.postJson('/v1/coach/message', body: payload);

      // Expect envelope-like shape: {status, data, error, meta}
      final status = (env['status'] ?? '').toString();
      if (status == 'blocked') {
        final msg = (env['error'] is Map)
            ? (env['error']['message']?.toString() ?? 'Blocked')
            : 'Blocked';
        setState(() {
          _messages.add(_ChatMsg(_ChatRole.assistant, 'Blocked: $msg'));
          _contextExpanded = false;
        });
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
      if (bestNext.isNotEmpty) {
        buf.writeln('\nBest next message:\n$bestNext');
      }

      setState(() {
        _messages.add(_ChatMsg(_ChatRole.assistant, buf.toString().trim()));
        _contextExpanded = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMsg(_ChatRole.assistant, 'Error: ${e.toString()}'));
        _contextExpanded = false;
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Widget _characterStrip() {
    // Placeholder for Step 3.6.5 (Character state machine)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.spa)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _sending
                  ? 'Dar hal-e fekr...'
                  : 'Man inja-am. Har chi mikhay begu.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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
      if (goal.isNotEmpty) {
        pieces.add(
          'Goal: ${goal.length > 40 ? '${goal.substring(0, 40)}…' : goal}',
        );
      }
      if (situation.isNotEmpty) {
        pieces.add(
          'Situation: ${situation.length > 40 ? '${situation.substring(0, 40)}…' : situation}',
        );
      }
      if (_ctxText.trim().isNotEmpty) {
        pieces.add(
          'Context: ${_ctxImages.length} screenshot${_ctxImages.length == 1 ? '' : 's'}',
        );
      }
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
                  body: 'In faqat timeline ro پاک mikone.',
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
