class Suggestion {
  Suggestion({
    required this.label,
    required this.text,
    required this.whyItWorks,
    required this.emotionPreview,
  });

  final String label;
  final String text;
  final String whyItWorks;
  final List<String> emotionPreview;

  factory Suggestion.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final text = json['text'];
    final why = json['why_it_works'];
    final emotions = json['emotion_preview'];

    if (label is! String) {
      throw FormatException('suggestions[].label missing');
    }
    if (text is! String) {
      throw FormatException('suggestions[].text missing');
    }
    if (why is! String) {
      throw FormatException('suggestions[].why_it_works missing');
    }

    final List<String> emotionPreview = (emotions is List)
        ? emotions.whereType<String>().toList()
        : <String>[];

    return Suggestion(
      label: label,
      text: text,
      whyItWorks: why,
      emotionPreview: emotionPreview,
    );
  }
}
