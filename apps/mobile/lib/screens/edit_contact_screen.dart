import 'dart:math';
import 'package:flutter/material.dart';
import '../models/contact.dart';

class EditContactScreen extends StatefulWidget {
  final Contact? contact;

  const EditContactScreen({super.key, this.contact});

  @override
  State<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends State<EditContactScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _id;
  late TextEditingController _nameCtrl;
  String _relation = 'other';

  ContactStyleOffsets _offsets = ContactStyleOffsets.defaults();
  ContactSensitivities _sens = ContactSensitivities.defaults();

  late TextEditingController _forbiddenCtrl;

  @override
  void initState() {
    super.initState();

    final c = widget.contact;
    _id = c?.id ?? _newId();
    _nameCtrl = TextEditingController(text: c?.displayName ?? '');
    _relation = (c?.relationTag ?? '').trim().isNotEmpty
        ? c!.relationTag
        : 'other';
    _offsets = c?.styleOffsets ?? ContactStyleOffsets.defaults();
    _sens = c?.sensitivities ?? ContactSensitivities.defaults();
    _forbiddenCtrl = TextEditingController(
      text: (c?.forbiddenWords ?? const []).join(', '),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _forbiddenCtrl.dispose();
    super.dispose();
  }

  String _newId() {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final r = Random().nextInt(9000) + 1000;
    return 'c_${ms}_$r';
  }

  List<String> _parseForbidden(String raw) {
    final parts = raw.split(',');
    final out = <String>[];
    for (final p in parts) {
      final s = p.trim();
      if (s.isEmpty) continue;
      out.add(s);
      if (out.length >= 50) break;
    }
    return out;
  }

  Widget _offsetSlider({
    required String label,
    required int value,
    required void Function(int) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: $value',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Slider(
          value: value.toDouble(),
          min: -30,
          max: 30,
          divisions: 60,
          label: value.toString(),
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }

  void _save() {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final name = _nameCtrl.text.trim();
    final forbidden = _parseForbidden(_forbiddenCtrl.text);

    final c = Contact(
      id: _id.trim(),
      displayName: name,
      relationTag: _relation,
      styleOffsets: _offsets,
      sensitivities: _sens,
      forbiddenWords: forbidden,
    );

    if (!mounted) return;
    Navigator.of(context).pop(c);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.contact != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit contact' : 'New contact'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Name is required';
                  if (s.length < 2) return 'Too short';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _relation,
                decoration: const InputDecoration(
                  labelText: 'Relation',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'boss', child: Text('boss')),
                  DropdownMenuItem(value: 'coworker', child: Text('coworker')),
                  DropdownMenuItem(value: 'friend', child: Text('friend')),
                  DropdownMenuItem(value: 'family', child: Text('family')),
                  DropdownMenuItem(value: 'partner', child: Text('partner')),
                  DropdownMenuItem(value: 'client', child: Text('client')),
                  DropdownMenuItem(value: 'other', child: Text('other')),
                ],
                onChanged: (v) => setState(() => _relation = v ?? 'other'),
              ),

              const SizedBox(height: 16),
              const Text(
                'Style offsets',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'These tweak your base voice per person. Range: -30..+30',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),

              _offsetSlider(
                label: 'Warmth',
                value: _offsets.warmthOffset,
                onChanged: (v) => setState(
                  () => _offsets = _offsets.copyWith(warmthOffset: v),
                ),
              ),
              _offsetSlider(
                label: 'Directness',
                value: _offsets.directnessOffset,
                onChanged: (v) => setState(
                  () => _offsets = _offsets.copyWith(directnessOffset: v),
                ),
              ),
              _offsetSlider(
                label: 'Brevity',
                value: _offsets.brevityOffset,
                onChanged: (v) => setState(
                  () => _offsets = _offsets.copyWith(brevityOffset: v),
                ),
              ),
              _offsetSlider(
                label: 'Formality',
                value: _offsets.formalityOffset,
                onChanged: (v) => setState(
                  () => _offsets = _offsets.copyWith(formalityOffset: v),
                ),
              ),
              _offsetSlider(
                label: 'Emoji rate',
                value: _offsets.emojiRateOffset,
                onChanged: (v) => setState(
                  () => _offsets = _offsets.copyWith(emojiRateOffset: v),
                ),
              ),

              const SizedBox(height: 16),
              const Text(
                'Sensitivities',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              SwitchListTile(
                value: _sens.hatesSarcasm,
                onChanged: (v) =>
                    setState(() => _sens = _sens.copyWith(hatesSarcasm: v)),
                title: const Text('Hates sarcasm'),
              ),
              SwitchListTile(
                value: _sens.hatesCommands,
                onChanged: (v) =>
                    setState(() => _sens = _sens.copyWith(hatesCommands: v)),
                title: const Text('Hates commands'),
              ),
              SwitchListTile(
                value: _sens.sensitiveToAlwaysNever,
                onChanged: (v) => setState(
                  () => _sens = _sens.copyWith(sensitiveToAlwaysNever: v),
                ),
                title: const Text('Sensitive to "always/never"'),
              ),
              SwitchListTile(
                value: _sens.conflictSensitive,
                onChanged: (v) => setState(
                  () => _sens = _sens.copyWith(conflictSensitive: v),
                ),
                title: const Text('Conflict sensitive'),
              ),

              const SizedBox(height: 16),
              const Text(
                'Forbidden words',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _forbiddenCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Comma-separated',
                  hintText: 'e.g. ba ehteram, lotfan',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: const Text('Save contact')),
            ],
          ),
        ),
      ),
    );
  }
}
