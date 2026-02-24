import 'suggestion.dart';

class ReplyRisk {
  ReplyRisk({required this.level, required this.score, required this.reasons});

  final String level;
  final int score;
  final List<String> reasons;

  factory ReplyRisk.fromJson(Map<String, dynamic> json) {
    final level = json['level'];
    final score = json['score'];
    final reasonsRaw = json['reasons'];

    if (level is! String) {
      throw FormatException('risk.level missing');
    }
    if (score is! int) {
      throw FormatException('risk.score missing');
    }

    final reasons = (reasonsRaw is List)
        ? reasonsRaw.whereType<String>().toList()
        : <String>[];

    return ReplyRisk(level: level, score: score, reasons: reasons);
  }
}

class ReplyResponse {
  ReplyResponse({
    required this.mode,
    required this.voiceMatchScore,
    required this.risk,
    required this.suggestions,
    required this.hardModeApplied,
    required this.safetyLine,
    required this.bestQuestion,
  });

  final String mode;
  final int voiceMatchScore;
  final ReplyRisk risk;
  final List<Suggestion> suggestions;

  // Phase 4 (Hard Mode) — optional/additive
  final bool hardModeApplied;
  final String? safetyLine;
  final String? bestQuestion;

  factory ReplyResponse.fromJson(Map<String, dynamic> json) {
    final mode = json['mode'];
    final vms = json['voice_match_score'];
    final riskJson = json['risk'];
    final suggestionsJson = json['suggestions'];

    if (mode is! String) {
      throw FormatException('mode missing');
    }
    if (vms is! int) {
      throw FormatException('voice_match_score missing');
    }
    if (riskJson is! Map<String, dynamic>) {
      throw FormatException('risk missing');
    }

    final risk = ReplyRisk.fromJson(riskJson);

    final List<Suggestion> suggestions = (suggestionsJson is List)
        ? suggestionsJson
              .whereType<Map<String, dynamic>>()
              .map(Suggestion.fromJson)
              .toList()
        : <Suggestion>[];

    // Optional fields (safe defaults)
    final hmaRaw = json['hard_mode_applied'];
    final hardModeApplied = (hmaRaw is bool) ? hmaRaw : false;

    final slRaw = json['safety_line'];
    final safetyLine = (slRaw is String && slRaw.trim().isNotEmpty)
        ? slRaw
        : null;

    final bqRaw = json['best_question'];
    final bestQuestion = (bqRaw is String && bqRaw.trim().isNotEmpty)
        ? bqRaw
        : null;

    return ReplyResponse(
      mode: mode,
      voiceMatchScore: vms,
      risk: risk,
      suggestions: suggestions,
      hardModeApplied: hardModeApplied,
      safetyLine: safetyLine,
      bestQuestion: bestQuestion,
    );
  }
}
