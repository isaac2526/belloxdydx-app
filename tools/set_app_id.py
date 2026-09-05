"""Sets the application id on the shells `flutter create` generates.

WHY THIS EXISTS

`flutter create --org X --project-name Y` can only ever produce the id
`X.Y`. The id this app needs is `isaacarinola.belloxdydx.app`, which is
not that shape — and Google Play will not register a package name that
is already in use on Android by a key you cannot produce. Every build
before the permanent keystore was signed by a throwaway debug key that
GitHub generated inside a runner and then destroyed, so the old id
`tech.isaacarinola.belloxdydx` is unregisterable for ever.

So the shell is generated as before and the id is set here, in one
place, for both platforms:

  * android/app/build.gradle.kts   namespace and applicationId
  * MainActivity.kt                its package, and the directory it
                                   has to live in to match
  * ios .../project.pbxproj        PRODUCT_BUNDLE_IDENTIFIER

Idempotent, and it prints what it changed so a build log says plainly
which id shipped.
"""
import pathlib
import re
import shutil
import sys

DEFAULT_ID = 'isaacarinola.belloxdydx.app'

VALID = re.compile(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$')


def android(app_id: str) -> None:
    gradle = pathlib.Path('android/app/build.gradle.kts')
    if not gradle.exists():
        print('android: no shell here, skipping')
        return

    text = gradle.read_text()
    for key in ('namespace', 'applicationId'):
        text, n = re.subn(
            r'%s\s*=\s*"[^"]*"' % key, '%s = "%s"' % (key, app_id), text)
        if n == 0:
            raise SystemExit('android: could not find %s in %s' % (key, gradle))
        print('android: %s = %s' % (key, app_id))
    gradle.write_text(text)

    # MainActivity has to sit in the directory its package names, or
    # Android cannot find the Activity the manifest points at and the
    # app dies on launch with a ClassNotFoundException.
    source = pathlib.Path('native/MainActivity.kt')
    if not source.exists():
        raise SystemExit('android: native/MainActivity.kt is missing')
    kotlin = pathlib.Path('android/app/src/main/kotlin')
    if kotlin.exists():
        shutil.rmtree(kotlin)
    target = kotlin.joinpath(*app_id.split('.'))
    target.mkdir(parents=True, exist_ok=True)
    body = re.sub(r'^package\s+[\w.]+',
                  'package %s' % app_id, source.read_text(), count=1,
                  flags=re.MULTILINE)
    if not body.startswith('package %s' % app_id):
        raise SystemExit('android: MainActivity.kt has no package line')
    (target / 'MainActivity.kt').write_text(body)
    print('android: MainActivity -> %s/MainActivity.kt' % target)


def ios(app_id: str) -> None:
    pbx = pathlib.Path('ios/Runner.xcodeproj/project.pbxproj')
    if not pbx.exists():
        print('ios: no shell here, skipping')
        return
    text = pbx.read_text()

    # The test target's id is the app's with a suffix; keep that shape.
    def swap(m):
        old = m.group(1)
        suffix = ''
        for tail in ('.RunnerTests', '.RunnerUITests'):
            if old.endswith(tail):
                suffix = tail
        return 'PRODUCT_BUNDLE_IDENTIFIER = %s%s;' % (app_id, suffix)

    text, n = re.subn(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);', swap, text)
    if n == 0:
        raise SystemExit('ios: no PRODUCT_BUNDLE_IDENTIFIER in %s' % pbx)
    pbx.write_text(text)
    print('ios: PRODUCT_BUNDLE_IDENTIFIER = %s (%d targets)' % (app_id, n))


def main() -> None:
    app_id = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ID
    if not VALID.match(app_id):
        raise SystemExit('not a usable application id: %r' % app_id)
    print('application id: %s' % app_id)
    android(app_id)
    ios(app_id)


if __name__ == '__main__':
    main()
