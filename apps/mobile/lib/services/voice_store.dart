// lib/services/voice_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/voice_profile.dart';

class VoiceStore {
  static const _key = 'moodmora_voice_state_v1';

  Future<VoiceState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return VoiceState.defaults();
    try {
      final jsonMap = json.decode(raw);
      if (jsonMap is Map<String, dynamic>) {
        return VoiceState.fromJson(jsonMap);
      }
      return VoiceState.defaults();
    } catch (_) {
      return VoiceState.defaults();
    }
  }

  Future<void> save(VoiceState state) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = json.encode(state.toJson());
    await prefs.setString(_key, raw);
  }

  Future<void> reset() async {
    await save(VoiceState.defaults());
  }
}
