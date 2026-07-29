"""Injects Play upload-key signing into the generated Android gradle.
Runs in CI after `flutter create`; safe to run when key.properties is
absent (leaves debug signing untouched)."""
import pathlib

kts = pathlib.Path("android/app/build.gradle.kts")
groovy = pathlib.Path("android/app/build.gradle")
g = kts if kts.exists() else groovy
s = g.read_text()

if "key.properties" in s:
    print("signing already wired")
elif g is kts:
    s = s.replace(
        "android {",
        'import java.util.Properties\n'
        'import java.io.FileInputStream\n'
        'val keystoreProperties = Properties().apply {\n'
        '    val f = rootProject.file("key.properties")\n'
        '    if (f.exists()) load(FileInputStream(f))\n'
        '}\n\n'
        "android {",
        1,
    )
    s = s.replace(
        "    buildTypes {",
        '    signingConfigs {\n'
        '        create("release") {\n'
        '            if (rootProject.file("key.properties").exists()) {\n'
        '                keyAlias = keystoreProperties["keyAlias"] as String\n'
        '                keyPassword = keystoreProperties["keyPassword"] as String\n'
        '                storeFile = file(keystoreProperties["storeFile"] as String)\n'
        '                storePassword = keystoreProperties["storePassword"] as String\n'
        '            }\n'
        '        }\n'
        '    }\n'
        "    buildTypes {",
        1,
    )
    s = s.replace(
        'signingConfig = signingConfigs.getByName("debug")',
        'signingConfig = if (rootProject.file("key.properties").exists()) '
        'signingConfigs.getByName("release") else signingConfigs.getByName("debug")',
    )
    g.write_text(s)
    print("kts signing wired")
else:
    s = s.replace(
        "android {",
        "def keystoreProperties = new Properties()\n"
        "def keystorePropertiesFile = rootProject.file('key.properties')\n"
        "if (keystorePropertiesFile.exists()) {\n"
        "    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))\n"
        "}\n\n"
        "android {",
        1,
    )
    s = s.replace(
        "    buildTypes {",
        "    signingConfigs {\n"
        "        release {\n"
        "            if (keystorePropertiesFile.exists()) {\n"
        "                keyAlias keystoreProperties['keyAlias']\n"
        "                keyPassword keystoreProperties['keyPassword']\n"
        "                storeFile file(keystoreProperties['storeFile'])\n"
        "                storePassword keystoreProperties['storePassword']\n"
        "            }\n"
        "        }\n"
        "    }\n"
        "    buildTypes {",
        1,
    )
    s = s.replace(
        "signingConfig signingConfigs.debug",
        "signingConfig keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug",
    )
    g.write_text(s)
    print("groovy signing wired")
