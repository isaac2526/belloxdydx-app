BELLOXDYDX · THE REAL APP · how to get your APK
GitHub is your builder. No Android Studio. No laptop tools.

ONE-TIME SETUP (10 minutes)
..............................................
1. Supabase -> Settings -> API. Copy two things:
   Project URL and the anon public key.
2. Open lib/config.dart in this folder (any text editor,
   or edit later on GitHub with the pencil) and paste them
   into the two PASTE_YOUR lines. Save.
3. GitHub -> New repository -> name: belloxdydx-app ->
   set it PRIVATE -> Create.
4. Upload EVERYTHING in this folder to that repo
   (drag all files and folders together; make sure the
   .github folder goes in too, it is the builder).
5. The moment you commit, GitHub starts building. Watch:
   repo -> Actions tab -> the running job.
6. When it turns green (first run takes ~10 minutes):
   open the run -> Artifacts -> download belloxdydx-apk ->
   inside is app-release.apk. THAT is your real app.
7. Share the APK anywhere: WhatsApp, Drive, your website.
   Installing asks "allow unknown apps" once. Normal.

IF THE BUILD IS RED: open the failed step, copy the log,
send it to Isaac's assistant. Same dance as Vercel.

EVERY FUTURE UPDATE: change files on GitHub -> commit ->
Actions builds a fresh APK automatically.

PLAY STORE (whenever you're ready): the same green run also
produces belloxdydx-playstore-aab. Create a Google Play
developer account (one-time 25 dollars), upload that .aab,
fill the store listing, submit. Done.

WHAT THIS APP DOES
..............................................
Screenshots and screen recordings ... BLACK, app-wide,
  enforced by Android itself (FLAG_SECURE). The wise guys
  in Faculty of Education just met their match.
Offline vault ....................... students tap the
  download icon on any note or slide; it saves INSIDE the
  app only, readable with zero network, invisible to file
  managers, never in Downloads, never shareable.
Same account, same laws ............. login, merciful
  device lock, one live session with instant judgement on
  reconnect, activation with keys, streaks, referral code,
  leaderboard, announcements, practice questions.
0 to 100 loader ..................... tied to real loading.
Timed CBT exams ..................... on the website for
  v1; app v1.1 brings them in.
iPhone .............................. same code builds for
  iOS later; needs Apple's 99 dollars/year and their
  review. Android conquers first.
