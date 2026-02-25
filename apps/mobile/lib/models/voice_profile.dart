// lib/models/voice_profile.dart
class VoiceProfile {
  final double warmth; // 0..1
  final double directness; // 0..1
  final double brevity; // 0..1
  final double formality; // 0..1
  final double emojiRate; // 0..1
  final List<String> doNotUse;

  const VoiceProfile({
    required this.warmth,
    required this.directness,
    required this.brevity,
    required this.formality,
    required this.emojiRate,
    required this.doNotUse,
  });

  factory VoiceProfile.defaults() => const VoiceProfile(
    warmth: 0.7,
    directness: 0.55,
    brevity: 0.6,
    formality: 0.35,
    emojiRate: 0.15,
    doNotUse: [],
  );

  Map<String, dynamic> toJson() => {
    "warmth": warmth,
    "directness": directness,
    "brevity": brevity,
    "formality": formality,
    "emoji_rate": emojiRate,
    "do_not_use": doNotUse,
  };

  factory VoiceProfile.fromJson(Map<String, dynamic> json) => VoiceProfile(
    warmth: _asDouble(json["warmth"], 0.7),
    directness: _asDouble(json["directness"], 0.55),
    brevity: _asDouble(json["brevity"], 0.6),
    formality: _asDouble(json["formality"], 0.35),
    emojiRate: _asDouble(json["emoji_rate"], 0.15),
    doNotUse: _asStringList(json["do_not_use"]),
  );

  VoiceProfile copyWith({
    double? warmth,
    double? directness,
    double? brevity,
    double? formality,
    double? emojiRate,
    List<String>? doNotUse,
  }) {
    return VoiceProfile(
      warmth: warmth ?? this.warmth,
      directness: directness ?? this.directness,
      brevity: brevity ?? this.brevity,
      formality: formality ?? this.formality,
      emojiRate: emojiRate ?? this.emojiRate,
      doNotUse: doNotUse ?? this.doNotUse,
    );
  }

  static double _asDouble(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }
}

class VoiceState {
  final bool enabled;
  final String variant; // AUTO | FA_SCRIPT | FINGLISH | EN
  final VoiceProfile profile;

  const VoiceState({
    required this.enabled,
    required this.variant,
    required this.profile,
  });

  factory VoiceState.defaults() => VoiceState(
    enabled: false,
    variant: "FINGLISH",
    profile: VoiceProfile.defaults(),
  );

  Map<String, dynamic> toJson() => {
    "enabled": enabled,
    "variant": variant,
    "profile": profile.toJson(),
  };

  factory VoiceState.fromJson(Map<String, dynamic> json) => VoiceState(
    enabled: json["enabled"] == true,
    variant:
        (json["variant"] is String && (json["variant"] as String).isNotEmpty)
        ? (json["variant"] as String)
        : "FINGLISH",
    profile: (json["profile"] is Map<String, dynamic>)
        ? VoiceProfile.fromJson(json["profile"] as Map<String, dynamic>)
        : VoiceProfile.defaults(),
  );
}
