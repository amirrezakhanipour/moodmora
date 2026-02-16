import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_config.dart';
import '../models/reply_response.dart';
import '../services/api_client.dart';

class ReplyScreen extends StatefulWidget {
  const ReplyScreen({super.key});

  @override
  State<ReplyScreen> createState() => _ReplyScreenState();
}

class _ReplyScreenState extends State<ReplyScreen> {
  final _controller = TextEditingController();
  bool _hardMode = false;
  String _variant = 'FINGLISH';

  bool _loading = false;
  ReplyResponse? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // UX: when user edits input, clear stale result/error
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

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    final api = ApiClient(baseUrl: AppConfig.apiBaseUrl);

    final body = {
      'input': {
        'received_text': _controller.text.trim(),
        'hard_mode': _hardMode,
        'output_variant': _variant,
      },
    };

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
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
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
            onChanged: (_) => setState(() {}), // <-- مهم: enable/disable button
          ),

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

          const SizedBox(height: 12),

          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Generate replies'),
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Error', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
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
