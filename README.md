# Belloxdydx — the student app

A **real Flutter application**. Not a WebView, not a PWA wrapper, not the
website embedded in a shell. Every screen is built natively against the same
backend the website uses.

> The previous release shipped `CloneShell` — a WebView pointed at
> belloxdydx.org — while 24 finished native screens sat unreachable in this
> repo. That shell has been deleted. The native app is the app.

---

## What is inside

| Area | Screens |
| --- | --- |
| Auth | welcome, login (with the 3D intro), register, forgot password, reset, activate, frozen |
| Study | dashboard, courses, course hub, section lists, note reader, document viewer, video |
| Assessment | practice runner, CBT/exam runner, question navigator, calculator, results review |
| Revision | revision hub, weakness radar, saved questions, My Mistakes deck |
| Competition | leaderboard, The League, Millionaire |
| Other | Bello AI, announcements, offline vault, CGPA calculator, profile & settings |

Native capabilities the website cannot offer: real screenshot blocking
(`FLAG_SECURE`), an offline vault of actual files on disk, OS-enforced exam
lockdown, reliable violation detection through app lifecycle, swipe gestures,
haptics, and push-ready deep links.

---

## Architecture

```
Flutter app
   │
   ├─ DIRECT path  ──►  Supabase  (Postgres RPC + RLS + Storage + Realtime)
   │                    grading happens inside the database
   │
   └─ LEGACY path  ──►  Vercel / Next.js API  ──►  Supabase
                        the path the app used before; kept as a fallback
```

`lib/data/backend.dart` probes `bx_capabilities()` once at launch. If the SQL
migration `supabase/migrations/0010_app_direct.sql` (in the **belloxdydxui**
repo) has been applied, the app switches to the direct path and **Vercel leaves
the student hot path entirely**. If it has not, the app works exactly as before.
Nothing breaks either way, and the Profile screen shows which path is live.

Why it matters: the audit found every student action — every page, every
question, every answer, every file byte — passing through a Vercel function,
because RLS was enabled with almost no policies. The migration adds the missing
policies, a `public_questions` view that does not contain the answer key, and
`SECURITY DEFINER` functions that grade answers in Postgres. The answer key
never reaches the device before the student commits.

Two things deliberately stay on the website:
- **Registration** — creates the auth user, profile and activation key in one
  service-role transaction. Trust-critical, belongs server-side.
- **Bello AI** — the Gemini key must not ship inside an app binary.

### Layout

```
lib/
  core/
    config.dart          endpoints, business constants, dart-define overrides
    providers.dart       riverpod wiring, session state
    router.dart          go_router + deep links
    theme/               tokens, typography, ThemeData
  data/
    backend.dart         the dual-path gateway
    models.dart          domain models (parse both wire shapes)
    repositories.dart    auth / content / assessment / engagement
    local_store.dart     JSON cache + the offline vault
  ui/                    the design system (BxCard, BxButton, charts, motion…)
  features/<area>/       one folder per feature
```

Every colour comes from `context.bx`, every text style from `BxType`, every gap
from `BxSpace`. There are no literal hex values in feature code.

---

## Running it

```bash
flutter pub get
flutter run
```

### Against the local mock backend

No Supabase project needed. The mock speaks the real Supabase auth/REST/RPC wire
format, so the app runs its actual code paths:

```bash
node tools/mock_backend.js 54321 &

flutter run \
  --dart-define=BX_SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=BX_SUPABASE_ANON_KEY=mock \
  --dart-define=BX_SITE_URL=http://127.0.0.1:54321
```

Seeded students (password `Password@1#`): `kunle` and `amaka` are activated,
`preview` is not — use it to exercise the activation gates.

### Driving it in a browser

```bash
./tools/test_app.sh
```

Builds for web, serves it, and drives it through Chromium with Playwright:
signs in, walks every tab, opens a course, searches materials, reads a note,
runs a practice round, starts a CBT, opens the navigator and calculator, uses a
dropdown, toggles the theme. Screenshots and a pass/fail report land in
`build/uitest/`.

---

## Builds

`dl.google.com` is blocked on some managed networks, and an iOS `.ipa` needs
Xcode, so releases are produced by CI rather than locally:

| Artefact | Job | Runner |
| --- | --- | --- |
| `app-release.apk` | `android` | ubuntu |
| `app-release.aab` (Play Store) | `android` | ubuntu |
| `belloxdydx-unsigned.ipa` | `ios` | macos-14 |

Push to any branch, or run **Build Belloxdydx** manually from the Actions tab.
`analyze` (flutter analyze + tests) gates both build jobs, so a broken commit
fails in about two minutes instead of after a full toolchain download.

The iOS IPA is intentionally **unsigned** — for testing. Signing it for the App
Store needs an Apple developer account.

### Configuration at build time

```bash
flutter build apk --release \
  --dart-define=BX_SUPABASE_URL=https://<project>.supabase.co \
  --dart-define=BX_SUPABASE_ANON_KEY=<anon key> \
  --dart-define=BX_SITE_URL=https://www.belloxdydx.org
```

The anon key is public by design; RLS is what protects the data. The service
role key never appears in this app.

---

## Access rules, unchanged

One account per device. One live session at a time — on the direct path the app
subscribes to its own `active_sessions` row over Realtime, so a second sign-in
signs the first device out instantly instead of polling every 45 seconds.
Device and password resets still go through Tutor Bello on WhatsApp.
