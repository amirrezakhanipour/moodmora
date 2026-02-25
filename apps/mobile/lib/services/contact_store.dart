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

    // ✅ IMPORTANT: return a mutable list (NOT const [])
    if (raw == null || raw.trim().isEmpty) return <Contact>[];

    try {
      final jsonVal = json.decode(raw);
      if (jsonVal is! List) return <Contact>[];

      final out = <Contact>[];
      for (final item in jsonVal) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          final c = Contact.fromJson(map);

          if (c.id.trim().isNotEmpty && c.displayName.trim().isNotEmpty) {
            out.add(c);
          }
        }
      }

      out.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return out;
    } catch (_) {
      // ✅ mutable list
      return <Contact>[];
    }
  }

  Future<void> saveAll(List<Contact> contacts) async {
    final prefs = await SharedPreferences.getInstance();

    final cleaned = contacts
        .where((c) => c.id.trim().isNotEmpty && c.displayName.trim().isNotEmpty)
        .toList();

    cleaned.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    final list = cleaned.map((c) => c.toJson()).toList();
    final raw = json.encode(list);

    final ok = await prefs.setString(_contactsKey, raw);
    if (!ok) {
      throw Exception('SharedPreferences.setString failed for $_contactsKey');
    }
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
      final ok = await prefs.setString(_lastSelectedKey, id.trim());
      if (!ok) {
        throw Exception(
          'SharedPreferences.setString failed for $_lastSelectedKey',
        );
      }
    }
  }

  Future<void> upsert(Contact contact) async {
    // ✅ Always work on a mutable copy, even if caller returns an unmodifiable list
    final all = List<Contact>.from(await loadAll());

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
