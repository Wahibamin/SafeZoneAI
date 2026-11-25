class AppConstants {
  AppConstants._();

  static const String appName = 'SafeZone AI Mobile';
  static const String appSlug = 'safezone_mobile';
  static const String appId = 'com.safezone.ai.mobile';
  static const String appVersion = '1.0.0';
  static const String targetDevice = 'Samsung Galaxy Z Flip3';
  static const String dbFileName = 'safezone_mobile.db';
  static const int dbVersion = 3;

  // Settings keys in app_settings table
  static const String settingActiveModelId = 'active_model_id';
  static const String settingActiveProfileId = 'active_profile_id';
  static const String settingEventLoggingEnabled = 'event_logging_enabled';
  static const String settingDefaultCameraLens = 'default_camera_lens';
  static const String settingPreferredAccelerator = 'preferred_accelerator';
  static const String settingRetentionDays = 'retention_days';

  // Supported format & task in MVP (ADR-004)
  static const String supportedFormat = 'tflite';
  static const String supportedTask = 'detect';
}
