// lib/models/contact.dart
class ContactStyleOffsets {
  final int warmthOffset; // -30..+30
  final int directnessOffset; // -30..+30
  final int brevityOffset; // -30..+30
  final int formalityOffset; // -30..+30
  final int emojiRateOffset; // -30..+30

  const ContactStyleOffsets({
    required this.warmthOffset,
    required this.directnessOffset,
    required this.brevityOffset,
    required this.formalityOffset,
    required this.emojiRateOffset,
  });

  factory ContactStyleOffsets.defaults() => const ContactStyleOffsets(
    warmthOffset: 0,
    directnessOffset: 0,
    brevityOffset: 0,
    formalityOffset: 0,
    emojiRateOffset: 0,
  );

  Map<String, dynamic> toJson() => {
    "warmth_offset": warmthOffset,
    "directness_offset": directnessOffset,
    "brevity_offset": brevityOffset,
    "formality_offset": formalityOffset,
    "emoji_rate_offset": emojiRateOffset,
  };

  factory ContactStyleOffsets.fromJson(Map<String, dynamic> json) =>
      ContactStyleOffsets(
        warmthOffset: _asInt(json["warmth_offset"], 0),
        directnessOffset: _asInt(json["directness_offset"], 0),
        brevityOffset: _asInt(json["brevity_offset"], 0),
        formalityOffset: _asInt(json["formality_offset"], 0),
        emojiRateOffset: _asInt(json["emoji_rate_offset"], 0),
      );

  static int _asInt(dynamic v, int fallback) {
    if (v is int) return _clampOffset(v);
    if (v is num) return _clampOffset(v.round());
    if (v is String) return _clampOffset(int.tryParse(v) ?? fallback);
    return fallback;
  }

  static int _clampOffset(int n) {
    if (n < -30) return -30;
    if (n > 30) return 30;
    return n;
  }

  ContactStyleOffsets copyWith({
    int? warmthOffset,
    int? directnessOffset,
    int? brevityOffset,
    int? formalityOffset,
    int? emojiRateOffset,
  }) {
    return ContactStyleOffsets(
      warmthOffset: warmthOffset ?? this.warmthOffset,
      directnessOffset: directnessOffset ?? this.directnessOffset,
      brevityOffset: brevityOffset ?? this.brevityOffset,
      formalityOffset: formalityOffset ?? this.formalityOffset,
      emojiRateOffset: emojiRateOffset ?? this.emojiRateOffset,
    );
  }
}

class ContactSensitivities {
  final bool hatesSarcasm;
  final bool hatesCommands;
  final bool sensitiveToAlwaysNever;
  final bool conflictSensitive;

  const ContactSensitivities({
    required this.hatesSarcasm,
    required this.hatesCommands,
    required this.sensitiveToAlwaysNever,
    required this.conflictSensitive,
  });

  factory ContactSensitivities.defaults() => const ContactSensitivities(
    hatesSarcasm: false,
    hatesCommands: false,
    sensitiveToAlwaysNever: false,
    conflictSensitive: false,
  );

  Map<String, dynamic> toJson() => {
    "hates_sarcasm": hatesSarcasm,
    "hates_commands": hatesCommands,
    "sensitive_to_always_never": sensitiveToAlwaysNever,
    "conflict_sensitive": conflictSensitive,
  };

  factory ContactSensitivities.fromJson(Map<String, dynamic> json) =>
      ContactSensitivities(
        hatesSarcasm: json["hates_sarcasm"] == true,
        hatesCommands: json["hates_commands"] == true,
        sensitiveToAlwaysNever: json["sensitive_to_always_never"] == true,
        conflictSensitive: json["conflict_sensitive"] == true,
      );

  ContactSensitivities copyWith({
    bool? hatesSarcasm,
    bool? hatesCommands,
    bool? sensitiveToAlwaysNever,
    bool? conflictSensitive,
  }) {
    return ContactSensitivities(
      hatesSarcasm: hatesSarcasm ?? this.hatesSarcasm,
      hatesCommands: hatesCommands ?? this.hatesCommands,
      sensitiveToAlwaysNever:
          sensitiveToAlwaysNever ?? this.sensitiveToAlwaysNever,
      conflictSensitive: conflictSensitive ?? this.conflictSensitive,
    );
  }
}

class Contact {
  final String id;
  final String displayName;
  final String relationTag; // boss|coworker|friend|family|partner|client|other

  final ContactStyleOffsets styleOffsets;
  final ContactSensitivities sensitivities;
  final List<String> forbiddenWords;

  const Contact({
    required this.id,
    required this.displayName,
    required this.relationTag,
    required this.styleOffsets,
    required this.sensitivities,
    required this.forbiddenWords,
  });

  Map<String, dynamic> toJson() => {
    "id": id,
    "display_name": displayName,
    "relation_tag": relationTag,
    "style_offsets": styleOffsets.toJson(),
    "sensitivities": sensitivities.toJson(),
    "forbidden_words": forbiddenWords,
  };

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
    id: _asString(json["id"]),
    displayName: _asString(json["display_name"]),
    relationTag: _asString(json["relation_tag"], fallback: "other"),
    styleOffsets: (json["style_offsets"] is Map<String, dynamic>)
        ? ContactStyleOffsets.fromJson(
            json["style_offsets"] as Map<String, dynamic>,
          )
        : ContactStyleOffsets.defaults(),
    sensitivities: (json["sensitivities"] is Map<String, dynamic>)
        ? ContactSensitivities.fromJson(
            json["sensitivities"] as Map<String, dynamic>,
          )
        : ContactSensitivities.defaults(),
    forbiddenWords: _asStringList(json["forbidden_words"]),
  );

  static String _asString(dynamic v, {String fallback = ""}) {
    if (v is String) return v.trim();
    return fallback;
  }

  static List<String> _asStringList(dynamic v) {
    if (v is List) {
      return v
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .take(50)
          .toList();
    }
    return const [];
  }

  Contact copyWith({
    String? id,
    String? displayName,
    String? relationTag,
    ContactStyleOffsets? styleOffsets,
    ContactSensitivities? sensitivities,
    List<String>? forbiddenWords,
  }) {
    return Contact(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      relationTag: relationTag ?? this.relationTag,
      styleOffsets: styleOffsets ?? this.styleOffsets,
      sensitivities: sensitivities ?? this.sensitivities,
      forbiddenWords: forbiddenWords ?? this.forbiddenWords,
    );
  }
}
