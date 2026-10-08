/// Determined at compile time by Flutter's Android product flavor.
class AppBuild {
  static const edition =
      String.fromEnvironment('FLUTTER_APP_FLAVOR', defaultValue: 'production');
  static const developerTools = edition == 'developer';
  static const appName = developerTools ? 'CheckMate Dev' : 'CheckMate';
}
