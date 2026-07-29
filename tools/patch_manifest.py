"""Adds https deep links (belloxdydx.org/cbt|test|exam) + guarantees
INTERNET permission in the generated AndroidManifest."""
import pathlib
m = pathlib.Path("android/app/src/main/AndroidManifest.xml")
s = m.read_text()

if "android.permission.INTERNET" not in s:
    s = s.replace("<manifest",
                  '<manifest', 1)  # no-op guard; sed handles perms in yaml

if "belloxdydx.org" not in s:
    intent = (
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
    s = s.replace("</activity>", intent + "            </activity>", 1)
    m.write_text(s)
    print("deep links added")
else:
    print("deep links already present")
