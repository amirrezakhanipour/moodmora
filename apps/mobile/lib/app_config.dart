import 'package:flutter/foundation.dart';

class AppConfig {
  // Android Emulator -> host machine localhost
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8787',
  );

  /// Phase 3.5 kill-switch (Dating Add-on v1)
  /// flutter run --dart-define=DATING_ADDON_ENABLED=true
  static const bool datingAddonEnabled = bool.fromEnvironment(
    'DATING_ADDON_ENABLED',
    defaultValue: kDebugMode, // ✅ debug: on, release: off
  );

  /// Phase 3.5 kill-switch (Starter Kit v1)
  /// flutter run --dart-define=STARTER_KIT_ENABLED=true
  static const bool starterKitEnabled = bool.fromEnvironment(
    'STARTER_KIT_ENABLED',
    defaultValue: kDebugMode,
  );

  /// Phase 3.5 kill-switch (I'm stuck flow v1)
  /// flutter run --dart-define=I_STUCK_ENABLED=true
  static const bool iStuckEnabled = bool.fromEnvironment(
    'I_STUCK_ENABLED',
    defaultValue: kDebugMode,
  );

  /// Phase 3.5 kill-switch (Dating presets + micro-onboarding v1)
  /// flutter run --dart-define=DATING_PRESETS_ENABLED=true
  static const bool datingPresetsEnabled = bool.fromEnvironment(
    'DATING_PRESETS_ENABLED',
    defaultValue: kDebugMode,
  );
}
