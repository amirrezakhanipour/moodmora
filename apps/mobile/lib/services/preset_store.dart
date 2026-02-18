import '../models/dating_preset.dart';

class PresetStore {
  PresetStore._();

  static DatingPreset? _selected;

  // V1: in-memory "first time this app run" auto-open
  static bool _didAutoPrompt = false;

  static DatingPreset? get selected => _selected;
  static bool get didAutoPrompt => _didAutoPrompt;

  static void markAutoPromptShown() {
    _didAutoPrompt = true;
  }

  static void setSelected(DatingPreset preset) {
    _selected = preset;
  }

  static void clear() {
    _selected = null;
  }

  static List<DatingPreset> presets() {
    return const [
      DatingPreset(
        id: 'chill',
        title: 'Chill & respectful',
        description: 'Low pressure. Warm, safe, normal tone.',
        flirtMode: 'subtle',
        starterVibe: 'Cute',
        replyGoal: 'Reply friendly',
        replyVibe: 'Calm',
      ),
      DatingPreset(
        id: 'playful',
        title: 'Playful tease',
        description: 'Light flirting, fun energy, not too forward.',
        flirtMode: 'playful',
        starterVibe: 'Funny',
        replyGoal: 'Flirt back',
        replyVibe: 'Playful',
      ),
      DatingPreset(
        id: 'direct',
        title: 'Confident & direct',
        description: 'Clear intent. Strong but not rude.',
        flirtMode: 'direct',
        starterVibe: 'Confident',
        replyGoal: 'Suggest plan',
        replyVibe: 'Direct',
      ),
    ];
  }
}
