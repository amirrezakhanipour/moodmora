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
    defaultValue: false,
  );

  /// Phase 3.5 kill-switch (Starter Kit v1)
  /// flutter run --dart-define=STARTER_KIT_ENABLED=true
  static const bool starterKitEnabled = bool.fromEnvironment(
    'STARTER_KIT_ENABLED',
    defaultValue: false,
  );

  /// Phase 3.5 kill-switch (I'm stuck flow v1)
  /// flutter run --dart-define=I_STUCK_ENABLED=true
  static const bool iStuckEnabled = bool.fromEnvironment(
    'I_STUCK_ENABLED',
    defaultValue: false,
  );
}
