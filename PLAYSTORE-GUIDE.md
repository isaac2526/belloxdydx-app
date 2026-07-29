# 🏪 BELLOXDYDX → GOOGLE PLAY · the complete ceremony

## PART 1 · One-time: forge the signing key (do this ONCE, guard it forever)
On the Dell (or any PC with Java, even a friend's):
```
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias belloxdydx
```
It asks for a password (invent a strong one, WRITE IT DOWN twice, losing it = losing update rights) and your name/city. You now have `upload-keystore.jks`.

Turn it to text: `base64 -w0 upload-keystore.jks > keystore.b64` (Windows: use an online-free method NEVER — instead `certutil -encode upload-keystore.jks keystore.b64` then remove the header/footer lines).

## PART 2 · Teach GitHub the key (secrets, once)
Repo → Settings → Secrets and variables → Actions → New repository secret, four times:
- `BX_KEYSTORE_B64` = the whole content of keystore.b64
- `BX_KEYSTORE_PASS` = the keystore password
- `BX_KEY_ALIAS` = `belloxdydx`
- `BX_KEY_PASS` = the key password (same as store pass if you pressed Enter)

From then on, every Actions run produces a **signed** `belloxdydx-playstore-aab` artifact. No secrets set = it still builds (unsigned/debug) so your direct-APK flow never breaks.

## PART 3 · First Play launch (the ladder)
1. Push this v3 code → Actions green → download **belloxdydx-playstore-aab** (the .aab file).
2. Play Console → Create app → name **Belloxdydx**, App, Free.
3. Fill the required forms (App content: privacy policy → use `https://www.belloxdydx.org/privacy` — create a simple page if absent; ads: No; target audience 18+; data safety: collects email/name for accounts, not shared).
4. **Testing → Internal testing** → Create release → upload the .aab → Google will offer **Play App Signing** → ACCEPT (Google guards the final key; your upload key is the one you forged).
5. Add yourself as internal tester → install from the internal link → confirm the app breathes.
6. **Closed testing** → create track → upload same .aab → add your **12 students' Gmail addresses** → they opt in via the link and keep it installed **14 straight days** (the law for new personal accounts).
7. After 14 days → **Apply for production** → review (~7 days) → LIVE 🎉

## PART 4 · Every future update (the ritual, forever)
1. Edit code → bump BOTH: `pubspec.yaml` version (e.g. `3.1.0+4`) AND `lib/config.dart` `appVersionCode = 4` (they must climb every release; Play rejects reused codes).
2. Push → Actions → download the new signed .aab.
3. Play Console → Production (or a testing track first) → **Create new release** → upload → release notes → **Roll out**. Students receive it automatically — the uninstall curse is dead.
4. The website's `apk_url_override` in Settings can point iOS/direct users wherever you wish; Android students now live on Play.

## PART 5 · Remember
- targetSdk is pinned to **36** in the workflow (Play's floor from Aug 31, 2026).
- FLAG_SECURE ships in `native/MainActivity.kt` — screenshots of the app are black glass.
- NEVER share or lose `upload-keystore.jks` + passwords. Back them up in two places tonight.
