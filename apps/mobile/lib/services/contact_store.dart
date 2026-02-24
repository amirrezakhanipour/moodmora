// lib/services/contact_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart';

class ContactStore {
  static const _contactsKey = 'moodmora_contacts_v1';
  static const _lastSelectedKey = 'moodmora_last_contact_id_v1';

  Future<List<Contact>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_contactsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final jsonVal = json.decode(raw);
      if (jsonVal is List) {
        final out = <Contact>[];
        for (final item in jsonVal) {
          if (item is Map<String, dynamic>) {
            final c = Contact.fromJson(item);
            // minimal sanity
            if (c.id.isNotEmpty && c.displayName.isNotEmpty) out.add(c);
          }
        }
        return out;
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAll(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final list = contacts.map((c) => c.toJson()).toList();
    await prefs.setString(_contactsKey, json.encode(list));
  }

  Future<String?> loadLastSelectedId() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_lastSelectedKey);
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }

  Future<void> saveLastSelectedId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null || id.trim().isEmpty) {
      await prefs.remove(_lastSelectedKey);
    } else {
      await prefs.setString(_lastSelectedKey, id.trim());
    }
  }

  Future<void> upsert(Contact contact) async {
    final all = await loadAll();
    final idx = all.indexWhere((c) => c.id == contact.id);
    if (idx >= 0) {
      all[idx] = contact;
    } else {
      all.add(contact);
    }
    await saveAll(all);
  }

  Future<void> deleteById(String id) async {
    final all = await loadAll();
    final next = all.where((c) => c.id != id).toList();
    await saveAll(next);

    final last = await loadLastSelectedId();
    if (last == id) {
      await saveLastSelectedId(null);
    }
  }

  Future<Contact?> findById(String id) async {
    final all = await loadAll();
    for (final c in all) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_contactsKey);
    await prefs.remove(_lastSelectedKey);
  }
}
