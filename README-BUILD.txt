BELLOXDYDX APP v1.2 · FINAL UPDATE · how to get your APK
GitHub builds it. No laptop tools.

⚠️ REMINDER: DO NOT UPLOAD config.dart THIS TIME.
Keep the config.dart already on GitHub (it has your keys). If you
overwrite it you must paste your two Supabase keys again. Easiest:
when uploading, just skip/deselect lib/config.dart.

WHAT IS NEW IN v1.2
..............................................
- 🤖 Bello AI: a study tutor built into the app (middle tab). It talks
  to the website's AI, so the AI key lives ONLY on the website, never
  in the app. Strictly academic, it refuses gist and LiveScores.
- 🎨 Theme now follows YOUR PHONE by default (dark/light). Toggle on
  Home (top right) or in Profile.
- 📶 Strong data affinity: the app now retries, waits properly, and
  SAVES your courses so it OPENS OFFLINE after the first sign-in
  (no more false "no internet"). Turn on fingerprint unlock to enter
  offline with no data.
- 📥 Offline vault now saves PDFs, notes, SLIDES, AUDIO/voice notes AND
  IMAGES. Everything you download reads with zero network.
- 🔤 Sharper fonts (Inter + Space Grotesk) and a cleaner look.
- 🧯 Errors now speak plain English instead of raw website text.

HOW TO UPDATE (same as always)
..............................................
1. In belloxdydx-app repo, upload the new lib folder, pubspec.yaml,
   native folder, and .github folder from this zip. OVERWRITE when
   asked. DO NOT upload config.dart (keep your existing one).
2. Commit. Actions builds. Wait for green (~12-15 min).
3. Green run -> Artifacts -> belloxdydx-apk -> app-release.apk.
   Install over the old app.

THE WEBSITE MUST BE UPDATED TOO (for the AI + watermark flood)
..............................................
Drag the belloxdydx-everything zip into your WEBSITE repo, and run
0005_drop7.sql in Supabase if you have not yet.
Then paste your free Gemini key into src/lib/ai-config.ts (one line)
so Bello AI comes alive on BOTH web and app.
