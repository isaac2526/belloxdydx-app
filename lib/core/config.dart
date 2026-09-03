/// ============================================================
/// APP CONFIGURATION
///
/// The Supabase URL and anon key are compile-time constants. That is
/// correct and expected — an anon key is designed to be public — and it
/// is safe here precisely because Row Level Security governs what it can
/// reach. The service role key never appears in this app.
///
/// Values can be overridden at build time without touching source:
///   flutter build apk --dart-define=BX_SUPABASE_URL=... \
///                     --dart-define=BX_SUPABASE_ANON_KEY=... \
///                     --dart-define=BX_SITE_URL=...
/// ============================================================
library;

abstract final class BxConfig {
  static const supabaseUrl = String.fromEnvironment(
    'BX_SUPABASE_URL',
    defaultValue: 'https://ziprpmqnxeylxywmesbb.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'BX_SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InppcHJwbXFueGV5bHh5d21lc2JiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxMTYxMDEsImV4cCI6MjA5ODY5MjEwMX0.sLih7P5u6bPxsPAemMTsknoT8xGDGEHe8jHn23jBZVE',
  );

  /// The website. After the migration this is used only for the handful
  /// of endpoints that must stay server-side (currently: the AI proxy),
  /// plus support and download links.
  static const siteUrl = String.fromEnvironment(
    'BX_SITE_URL',
    defaultValue: 'https://www.belloxdydx.org',
  );

  /// Forces the legacy path (everything through the website API) even
  /// when the Supabase RPC layer is present. Useful for debugging.
  static const forceLegacyApi =
      bool.fromEnvironment('BX_FORCE_LEGACY_API', defaultValue: false);

  static const appVersionCode = 6;
  static const appVersionName = '6.0.0';

  // ---- business constants, mirrored from the website ----
  static const whatsappNumber = '2347025284904';
  static const priceNgn = 3000;
  static const referralRewardNgn = 250;
  static const paymentBank = 'Opay';
  static const paymentAccount = '7025284904';
  static const paymentName = 'Bello Oluwapelumi Ayomide';
  static const university = 'University of Ibadan';
  static const youtubeUrl =
      'https://youtube.com/@bellooluwapelumiayomide210';
  static const brandFooter =
      'Designed with excellence for academic distinction — Isaac Arinola Tech';

  static const supportUrl = '$siteUrl/about';
  static const downloadUrl = '$siteUrl/download';

  /// Pre-written WhatsApp messages, exactly as the website composes them.
  static String waActivation(String fullName, String username) => _wa(
      "Hi Tutor Bello, I just paid ₦$priceNgn for my Belloxdydx activation. "
      "My name is $fullName and my username is $username. "
      "Here is my proof of payment.");

  static String waPasswordReset(String username) => _wa(
      "Hi Tutor Bello, I forgot my password. My username is $username");

  static String waDeviceReset(String username) => _wa(
      "Hi Tutor Bello, I changed my device. Please reset my device lock. "
      "My username is $username");

  static String waFrozen(String username) => _wa(
      "Hi Tutor Bello, my account is frozen. My username is $username");

  static String waHelp(String topic) =>
      _wa("Hi Tutor Bello, I need help with $topic on Belloxdydx.");

  static String _wa(String message) =>
      'https://wa.me/$whatsappNumber?text=${Uri.encodeComponent(message)}';
}

/// Points values, mirrored from lib/points.ts so the app can show the
/// same rules on the leaderboard without a round trip.
abstract final class BxPoints {
  static const streakDay = 10;
  static const materialOpen = 5;
  static const practiceCorrect = 2;
  static const testSubmitBase = 15;
  static const referralActivated = 50;

  static const rules = <String>[
    'Show up daily · +$streakDay',
    'Open a note, slide, video or PQ · +$materialOpen',
    'Correct practice answer · +$practiceCorrect',
    'Finish a test · +$testSubmitBase plus your percent',
    'Invite a coursemate who activates · +$referralActivated',
  ];
}
