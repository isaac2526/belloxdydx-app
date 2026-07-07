import 'package:flutter/material.dart';
import 'api.dart';

// Screenshot & screen-record protection on Android is enforced NATIVELY
// by FLAG_SECURE (see android MainActivity): every capture comes out
// black at the OS level, app-wide, and cannot be turned off from user
// space. That is the strongest guarantee the platform allows.
//
// The account-FREEZE machinery (server endpoint + admin Violations
// panel) is fully live and ready: any client that can detect a capture
// calls Api.reportViolation(kind) and the account freezes instantly.
// On Android there is nothing to detect because captures are blocked
// outright; this hook is where an iOS build (which cannot block) will
// plug its detection in later.
class Security {
  static Future<void> lockDown() async {
    // No-op on Android: FLAG_SECURE already active from app launch.
  }

  static Future<void> release() async {}

  static void watch(BuildContext Function() ctx) {
    // Reserved for platforms that expose capture events (future iOS).
  }

  // Manual freeze trigger, available if ever needed from the UI.
  static Future<void> reportCapture(String kind) => Api.reportViolation(kind);
}
