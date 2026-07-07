import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The app's own passkey: the phone's fingerprint or face. After the
// first password login the student can turn this on; from then on the
// app asks for their body, not a typed password. The secret never
// leaves the phone's secure hardware, exactly like a real passkey.
class Biometric {
  static final _auth = LocalAuthentication();
  static const _key = "bx_biometric_on";

  static Future<bool> available() async {
    try {
      final can = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      return can;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_key, v);
  }

  static Future<bool> prompt(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
