import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/contact_store.dart';
import 'edit_contact_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _store = ContactStore();

  List<Contact> _all = const [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final contacts = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _all = contacts;
      _loading = false;
    });
  }

  List<Contact> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((c) {
      final name = c.displayName.toLowerCase();
      final rel = c.relationTag.toLowerCase();
      return name.contains(q) || rel.contains(q);
    }).toList();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openEditor({Contact? contact}) async {
    final result = await Navigator.of(context).push<Contact?>(
      MaterialPageRoute(builder: (_) => EditContactScreen(contact: contact)),
    );

    if (!mounted) return;

    // result null => cancelled
    if (result != null) {
      try {
        await _store.upsert(result);
        _toast('Saved');
      } catch (e) {
        _toast('Save failed: $e');
      }
    }

    await _load();
  }

  Future<void> _confirmDelete(Contact c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete contact?'),
        content: Text('Delete "${c.displayName}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (ok == true) {
      try {
        await _store.deleteById(c.id);
        _toast('Deleted');
      } catch (e) {
        _toast('Delete failed: $e');
      }
      await _load();
    }
  }

  String _subtitle(Contact c) {
    final bits = <String>[];
    if (c.relationTag.isNotEmpty) bits.add(c.relationTag);
    final forb = c.forbiddenWords.length;
    if (forb > 0) bits.add('$forb forbidden');
    return bits.isEmpty ? '-' : bits.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            tooltip: 'Add',
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Search',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_all.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'No contacts yet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add a contact to tune tone per person.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => _openEditor(),
                        child: const Text('Add contact'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    return Card(
                      child: ListTile(
                        title: Text(
                          c.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(_subtitle(c)),
                        onTap: () => _openEditor(contact: c),
                        trailing: IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(c),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
