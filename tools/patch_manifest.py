"""Patches the AndroidManifest that `flutter create` generates.

There is no checked-in android/ directory: CI generates the shell on
every build, so anything the app needs in its manifest has to be put
back here.

Three things:

  1. USE_BIOMETRIC. Without it local_auth cannot use the fingerprint or
     face sensor at all, isDeviceSupported() reports the phone as
     incapable, and the app lock quietly marks itself unavailable and
     never fires. That is why the lock "wasn't working": there was
     nothing wrong with the lock.
  2. The https deep links for /cbt, /test and /exam.
  3. A check that the Activity really does declare the configChanges
     Flutter needs. If it does not, Android destroys and recreates the
     Activity on a rotation or a font-size change, and the student loses
     whatever they were in the middle of.

Every step is idempotent and prints what it did, so a CI log says
plainly whether the manifest that shipped had these in it.
"""
import pathlib
import re
import sys

MANIFEST = pathlib.Path("android/app/src/main/AndroidManifest.xml")

# USE_FINGERPRINT is the pre-Android-9 spelling. local_auth's Android
# implementation still looks for it on old API levels, and a Tecno or
# Infinix running Android 8 is squarely inside this app's audience.
PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.USE_BIOMETRIC",
    "android.permission.USE_FINGERPRINT",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.VIBRATE",
]

DEEP_LINK = (
    "\n                <intent-filter android:autoVerify=\"true\">\n"
    "                    <action android:name=\"android.intent.action.VIEW\"/>\n"
    "                    <category android:name=\"android.intent.category.DEFAULT\"/>\n"
    "                    <category android:name=\"android.intent.category.BROWSABLE\"/>\n"
    "                    <data android:scheme=\"https\" android:host=\"belloxdydx.org\"/>\n"
    "                    <data android:scheme=\"https\" android:host=\"www.belloxdydx.org\"/>\n"
    "                    <data android:pathPrefix=\"/cbt\"/>\n"
    "                    <data android:pathPrefix=\"/test\"/>\n"
    "                    <data android:pathPrefix=\"/exam\"/>\n"
    "                </intent-filter>\n"
)

# What Flutter needs the Activity to absorb itself. Anything missing
# here is a config change Android answers by destroying the Activity.
NEEDED_CONFIG_CHANGES = [
    "orientation",
    "screenSize",
    "smallestScreenSize",
    "keyboardHidden",
    "keyboard",
    "locale",
    "layoutDirection",
    "fontScale",
    "screenLayout",
    "density",
    "uiMode",
]


def main() -> int:
    if not MANIFEST.exists():
        print(f"!! {MANIFEST} not found — did flutter create run?", file=sys.stderr)
        return 1

    s = MANIFEST.read_text()
    changed = False

    # ---- permissions -------------------------------------------------
    missing = [p for p in PERMISSIONS if f'android:name="{p}"' not in s]
    if missing:
        block = "".join(
            f'    <uses-permission android:name="{p}"/>\n' for p in missing
        )
        s = s.replace("<application", block + "    <application", 1)
        changed = True
        print("permissions added: " + ", ".join(p.split(".")[-1] for p in missing))
    else:
        print("permissions already present")

    # The fingerprint hardware is not REQUIRED — a phone with only a PIN
    # must still install and still lock. Declared explicitly, because
    # some app stores infer a hardware requirement from the permission
    # and would hide the app from phones that can run it perfectly well.
    for feature in ("android.hardware.fingerprint", "android.hardware.camera"):
        if f'android:name="{feature}"' not in s:
            s = s.replace(
                "<application",
                f'    <uses-feature android:name="{feature}" '
                'android:required="false"/>\n    <application',
                1,
            )
            changed = True
    print("hardware declared optional")

    # ---- deep links --------------------------------------------------
    if "belloxdydx.org" not in s:
        s = s.replace("</activity>", DEEP_LINK + "            </activity>", 1)
        changed = True
        print("deep links added")
    else:
        print("deep links already present")

    # ---- the Activity must not be recreated --------------------------
    match = re.search(r'android:configChanges="([^"]*)"', s)
    if not match:
        print("!! no android:configChanges on the Activity — Android will "
              "destroy it on every rotation", file=sys.stderr)
        return 1
    have = set(match.group(1).split("|"))
    absent = [c for c in NEEDED_CONFIG_CHANGES if c not in have]
    if absent:
        merged = "|".join(sorted(have | set(NEEDED_CONFIG_CHANGES)))
        s = s[: match.start()] + f'android:configChanges="{merged}"' + s[match.end():]
        changed = True
        print("configChanges widened with: " + ", ".join(absent))
    else:
        print("configChanges complete")

    if changed:
        MANIFEST.write_text(s)
    print("manifest ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
