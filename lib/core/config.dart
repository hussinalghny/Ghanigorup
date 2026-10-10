/// إعدادات ثابتة للتطبيق. يمكن تغيير الدومين وقت البناء:
/// flutter build ipa --dart-define=SITE_URL=https://staging.ghanigroup.online
class AppConfig {
  static const String siteUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://ghanigroup.online',
  );

  static String get apiBase => '$siteUrl/api/v1';

  static String get privacyUrl => '$siteUrl/privacy';
  static String get termsUrl => '$siteUrl/terms';
  static String get supportUrl => '$siteUrl/support';
  static String get deleteAccountUrl => '$siteUrl/delete-account';

  static const String fallbackWhatsapp = '9647844440005';
  static const String fallbackPhone = '+964 78 4444 000 5';
}
