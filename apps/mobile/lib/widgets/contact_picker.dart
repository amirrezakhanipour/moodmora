// lib/widgets/contact_picker.dart
import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/contact_store.dart';

class ContactPicker {
  static Future<Contact?> pick(
    BuildContext context, {
    required List<Contact> contacts,
    Contact? selected,
    required VoidCallback onClear,
  }) async {
    String query = '';
    Contact? picked = selected;

    final result = await showModalBottomSheet<Contact?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? contacts
                : contacts.where((c) {
                    final name = c.displayName.toLowerCase();
                    final rel = c.relationTag.toLowerCase();
                    return name.contains(q) || rel.contains(q);
                  }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Pick a contact',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (picked != null)
                          TextButton(
                            onPressed: () {
                              picked = null;
                              onClear();
                              Navigator.of(ctx).pop(null);
                            },
                            child: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                    const SizedBox(height: 12),

                    if (contacts.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'No contacts yet. Add one from Home → Contacts.',
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 420),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            final isSel = (picked?.id == c.id);
                            return Card(
                              child: ListTile(
                                title: Text(
                                  c.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  c.relationTag.isEmpty
                                      ? 'other'
                                      : c.relationTag,
                                ),
                                trailing: isSel
                                    ? const Icon(Icons.check_circle)
                                    : const Icon(Icons.circle_outlined),
                                onTap: () => Navigator.of(ctx).pop(c),
                              ),
                            );
                          },
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

    return result;
  }

  static Future<Contact?> loadSelected({required ContactStore store}) async {
    final all = await store.loadAll();
    final lastId = await store.loadLastSelectedId();
    if (lastId == null) return null;
    for (final c in all) {
      if (c.id == lastId) return c;
    }
    return null;
  }
}
