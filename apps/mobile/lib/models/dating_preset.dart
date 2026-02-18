class DatingPreset {
  final String id;
  final String title;
  final String description;

  /// off | subtle | playful | direct
  final String flirtMode;

  /// Improve Starter defaults (Cute/Funny/Confident)
  final String starterVibe;

  /// Reply "I'm stuck" defaults
  final String replyGoal; // Reply friendly | Set boundary | Flirt back | Suggest plan
  final String replyVibe; // Calm | Playful | Direct

  const DatingPreset({
    required this.id,
    required this.title,
    required this.description,
    required this.flirtMode,
    required this.starterVibe,
    required this.replyGoal,
    required this.replyVibe,
  });
}
