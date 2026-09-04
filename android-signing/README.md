# The Belloxdydx release key

`bx-release.jks.enc` is the app's permanent signing key, encrypted with
AES-256 (PBKDF2, 300,000 iterations).

**This file is safe in a public repository.** Without the passphrase it
is 4 KB of noise. The passphrase lives only in the repository secret
`ANDROID_KEYSTORE_PASSPHRASE`, and GitHub never exposes a secret to a
pull request from a fork.

## Why it is committed rather than pasted

It was a base64 repository secret first. That failed twice, for the same
reason both times: 5,912 characters cannot be reliably copied out of a
text viewer on a phone — the value arrives soft-wrapped, or cut short —
and it fails at exactly the step that exists to guarantee the signature.
A build that depends on a person transcribing six thousand characters by
hand is a broken build.

Committing the encrypted key moves the human part down to a
40-character passphrase.

## The two secrets

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_PASSPHRASE` | 40 chars. Decrypts this file. |
| `ANDROID_KEYSTORE_PASSWORD` | Opens the keystore once decrypted. |

Both must be set or the build falls back to a throwaway debug key and
says so loudly in the run summary.

## Why any of this matters

Android refuses to install an update signed by a different key. Before
this, every build fell back to a debug keystore that GitHub regenerates
on each runner, so every APK had a different signature — which is why a
new build meant "uninstall the old one first", and uninstalling takes
every course the student had downloaded with it.

## If the key is ever lost

Take **Play App Signing** in the Play Console. Google then holds the
real signing key and this becomes only an upload key, which Google can
reset. Without that, losing this key means the app can never be updated
on the Play Store again.

## Rotating it

Only before the first Play Store upload — after that the key is fixed
for the life of the listing. Generate a new keystore, encrypt it with a
new passphrase, replace this file, update both secrets.
