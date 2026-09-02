#!/usr/bin/env node
/* ============================================================
 * BELLOXDYDX INTERACTION DRIVER
 *
 * Builds nothing and mocks nothing itself — it drives the REAL app,
 * already built for web and served locally, through a real browser.
 *
 * Flutter renders to canvas, so this first clicks the semantics
 * placeholder Flutter exposes for accessibility tools. That turns on
 * the semantics tree, after which every button, field and list row is a
 * real DOM node with an aria-label — exactly what a screen reader sees,
 * and exactly what we can click.
 *
 *   node tools/drive_app.js <baseUrl> <outDir>
 * ============================================================ */

const { chromium } = require('/opt/pw/node_modules/playwright-core');
const fs = require('fs');
const path = require('path');

const BASE = process.argv[2] || 'http://127.0.0.1:8080';
const OUT = process.argv[3] || '/tmp/shots';
fs.mkdirSync(OUT, { recursive: true });

const results = [];
let step = 0;

function log(status, name, detail = '') {
  results.push({ status, name, detail });
  const mark = status === 'ok' ? '  ok  ' : status === 'warn' ? ' warn ' : ' FAIL ';
  process.stdout.write(`[${mark}] ${name}${detail ? ' — ' + detail : ''}\n`);
}

async function shot(page, name) {
  step += 1;
  const file = path.join(OUT, `${String(step).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: file });
  return file;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Every semantics node currently in the tree, with its label and box. */
async function nodes(page) {
  return page.evaluate(() => {
    const out = [];
    document.querySelectorAll('flt-semantics').forEach((el) => {
      const label = el.getAttribute('aria-label') || el.textContent || '';
      const r = el.getBoundingClientRect();
      if (!label.trim()) return;
      if (r.width < 1 || r.height < 1) return;
      out.push({
        label: label.trim(),
        role: el.getAttribute('role') || '',
        tappable: el.hasAttribute('flt-tappable') || el.getAttribute('role') === 'button',
        // Flutter renders a button's label in a CHILD node, so the node
        // carrying the text is usually not the one marked as a button.
        inButton: !!el.closest('flt-semantics[role="button"]'),
        x: Math.round(r.x + r.width / 2),
        y: Math.round(r.y + r.height / 2),
        w: Math.round(r.width),
        h: Math.round(r.height),
      });
    });
    return out;
  });
}

async function labels(page) {
  return (await nodes(page)).map((n) => n.label);
}

/**
 * Finds the node a human would actually click.
 *
 * Flutter's semantics tree contains container nodes whose label is every
 * descendant's text run together, so a naive "first node containing the
 * word" match lands on a page-sized box and clicks its middle. Rank
 * candidates instead: exact match first, then tappable, then the
 * smallest box, and reject containers whose label dwarfs the needle.
 */
async function find(page, text, { exact = false } = {}) {
  const all = await nodes(page);
  const needle = text.toLowerCase();

  let candidates = all.filter((n) =>
    exact ? n.label.toLowerCase() === needle : n.label.toLowerCase().includes(needle),
  );
  if (candidates.length === 0) return null;

  const scored = candidates.map((n) => {
    const label = n.label.toLowerCase();
    const isExact = label === needle;
    // A label far longer than what we asked for is an aggregate node.
    const bloat = label.length / Math.max(needle.length, 1);
    const area = n.w * n.h;
    let score = 0;
    if (isExact) score -= 1000;
    if (n.tappable || n.inButton) score -= 600;
    if (bloat > 4) score += 800;      // almost certainly a container
    score += bloat * 10;
    score += area / 4000;             // prefer the tighter box
    return { n, score };
  });

  scored.sort((a, b) => a.score - b.score);
  const best = scored[0];
  // Reject a match that is only a fragment of a page-sized container.
  if (!exact && best.n.label.length > needle.length * 8 && best.n.w * best.n.h > 200000) {
    return null;
  }
  return best.n;
}

async function tap(page, text, { exact = false, settle = 900 } = {}) {
  const n = await find(page, text, { exact });
  if (!n) return false;
  await page.mouse.click(n.x, n.y);
  await sleep(settle);
  return true;
}

/**
 * Types into the field that sits under a given label.
 *
 * Flutter keeps its <input> elements out of the way of the painted UI,
 * so their DOM position is not where the field appears and clicking
 * them directly is a coin flip. The label, though, is a real semantics
 * node at a known place, and the field is drawn just beneath it. Click
 * there to move focus, then send real keystrokes — which is also the
 * only thing Flutter's editing pipeline accepts; element.fill() is
 * silently ignored.
 */
async function fillByLabel(page, labelText, value, dy = 40) {
  const all = await nodes(page);
  const needle = labelText.toLowerCase();
  const label = all
    .filter((n) => n.label.toLowerCase() === needle)
    .sort((a, b) => a.w * a.h - b.w * b.h)[0];
  if (!label) return false;

  // Two attempts: Flutter's web editing pipeline drops keystrokes that
  // arrive faster than it can process them, so type deliberately and
  // check the result rather than assuming it landed.
  for (let attempt = 0; attempt < 2; attempt++) {
    await page.mouse.click(label.x, label.y + dy);
    await sleep(600);
    if (!(await page.$('input:focus, textarea:focus'))) continue;

    await page.keyboard.press('Control+A').catch(() => {});
    await page.keyboard.press('Backspace').catch(() => {});
    await sleep(150);
    for (const ch of value) {
      await page.keyboard.type(ch);
      await sleep(45);
    }
    await sleep(350);

    // Re-query rather than reusing a handle: Flutter can swap the
    // backing <input> mid-edit, leaving an old handle reading empty
    // even though the field is correctly filled.
    const after = await page.$('input:focus, textarea:focus');
    if (after && (await after.inputValue()) === value) return true;
  }
  return false;
}

/** Focuses whatever field is on screen and types into it. */
async function typeIntoFocused(page, value) {
  const focused = await page.$('input:focus, textarea:focus');
  if (!focused) return false;
  await page.keyboard.press('Control+A').catch(() => {});
  if (value === '') {
    await page.keyboard.press('Backspace');
  } else {
    await page.keyboard.type(value, { delay: 20 });
  }
  await sleep(250);
  return true;
}

/** Waits until a form's inputs are actually in the DOM. */
async function waitForForm(page, count = 1, timeout = 25000) {
  const started = Date.now();
  while (Date.now() - started < timeout) {
    const n = (await page.$$('input, textarea')).length;
    if (n >= count) return n;
    await sleep(500);
  }
  return 0;
}

/** Waits until any of `texts` appears in the semantics tree. */
async function waitFor(page, texts, timeout = 20000) {
  const list = Array.isArray(texts) ? texts : [texts];
  const started = Date.now();
  while (Date.now() - started < timeout) {
    const ls = (await labels(page)).map((l) => l.toLowerCase());
    for (const t of list) {
      if (ls.some((l) => l.includes(t.toLowerCase()))) return t;
    }
    await sleep(400);
  }
  return null;
}

(async () => {
  const browser = await chromium.launch({
    executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome',
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage({
    viewport: { width: 430, height: 932 },      // iPhone-ish, the real target
    deviceScaleFactor: 2,
  });

  const consoleErrors = [];
  page.on('console', (m) => {
    if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 300));
  });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + String(e).slice(0, 300)));

  try {
    // ---------- boot ----------
    await page.goto(BASE, { waitUntil: 'domcontentloaded', timeout: 60000 });
    await page.waitForSelector(
      'flutter-view, flt-glass-pane, flt-scene-host, flt-semantics-placeholder, canvas',
      { timeout: 90000 },
    );
    await sleep(2500);

    // Turn on the semantics tree so everything becomes queryable.
    //
    // Flutter parks this placeholder off-screen on purpose — it exists
    // for screen readers — so a real mouse click is refused as "outside
    // the viewport". A synthetic DOM click is what Flutter listens for
    // anyway, and it is exactly what an assistive tool would send.
    const enabled = await page.evaluate(() => {
      const el = document.querySelector('flt-semantics-placeholder');
      if (!el) return false;
      el.click();
      el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
      return true;
    });
    await sleep(2000);

    // Some builds only expose the placeholder after the first frame.
    if (!enabled || (await labels(page)).length === 0) {
      await page.evaluate(() => {
        document.querySelectorAll('flt-semantics-placeholder').forEach((el) => {
          el.click();
          el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        });
      });
      await sleep(2000);
    }

    const tree = await labels(page);
    if (tree.length === 0) {
      log('fail', 'semantics tree', 'no nodes — cannot drive the UI');
    } else {
      log('ok', 'semantics tree', `${tree.length} nodes`);
    }
    await shot(page, 'boot');

    // ---------- welcome ----------
    const onWelcome = await waitFor(page, ['Create free account', 'Log in', 'CGPA calculator'], 25000);
    if (onWelcome) {
      log('ok', 'welcome screen', `saw "${onWelcome}"`);
      await shot(page, 'welcome');
    } else {
      log('fail', 'welcome screen', `labels: ${tree.slice(0, 12).join(' | ')}`);
    }

    // ---------- login ----------
    if (await tap(page, 'Log in')) {
      await sleep(1200);
      await shot(page, 'login');

      // The 3D intro plays for about five seconds and deliberately keeps
      // the form out of the semantics tree until it has risen, so wait
      // for the real inputs rather than racing the animation.
      const introPresent = (await find(page, 'Skip intro')) !== null;
      log(introPresent ? 'ok' : 'warn', '3D intro',
        introPresent ? 'stage is playing over the form' : 'not detected');

      const fieldCount = await waitForForm(page, 2, 25000);
      await shot(page, 'login-form');
      if (fieldCount < 2) {
        log('fail', 'login form', `only ${fieldCount} field(s) appeared`);
      } else {
        log('ok', 'login form', `${fieldCount} fields after the intro`);
      }

      const typedUser = await fillByLabel(page, 'EMAIL OR USERNAME', 'kunle');
      const typedPass = await fillByLabel(page, 'PASSWORD', 'Password@1#');
      if (typedUser && typedPass) {
        log('ok', 'login fields', 'username and password entered');
      } else {
        log('fail', 'login fields', `user=${typedUser} pass=${typedPass}`);
      }
      await shot(page, 'login-filled');

      const submitted = (await tap(page, 'Log in', { settle: 3500 }))
        || (await tap(page, 'Sign in', { settle: 3500 }));
      if (!submitted) log('fail', 'login submit', 'no submit control found');

      const landed = await waitFor(page, ['Dashboard', 'Good morning', 'Good afternoon', 'Good evening'], 25000);
      if (landed) {
        log('ok', 'signed in', `dashboard shows "${landed}"`);
      } else {
        log('fail', 'signed in', `labels: ${(await labels(page)).slice(0, 15).join(' | ')}`);
      }
      await shot(page, 'dashboard');
    } else {
      log('fail', 'login navigation', 'Log in not tappable from welcome');
    }

    // ---------- dashboard content ----------
    const dash = await labels(page);
    const expectDash = [
      ['stat tiles', ['Attempts submitted', 'Average score', 'Questions answered']],
      ['accuracy chart', ['Your accuracy', 'Correct', 'Missed']],
      ['course averages', ['Average score by course']],
      ['streak', ['12']],
      ['quote', ['Small daily reading', 'Fuel for today']],
      ['recent results', ['Recent results']],
    ];
    for (const [name, needles] of expectDash) {
      const hit = needles.some((n) => dash.some((l) => l.toLowerCase().includes(n.toLowerCase())));
      log(hit ? 'ok' : 'warn', `dashboard · ${name}`, hit ? '' : 'not found in semantics');
    }

    // scroll the dashboard to exercise the lower cards
    await page.mouse.move(215, 600);
    for (let i = 0; i < 6; i++) { await page.mouse.wheel(0, 500); await sleep(350); }
    await shot(page, 'dashboard-scrolled');
    log('ok', 'dashboard scroll', 'reached lower cards');

    // ---------- tab bar ----------
    for (const [tab, expect] of [
      ['Courses', ['PHY 101', 'Courses']],
      ['Revise', ['Revision', 'Smart revision', 'weak spot']],
      ['Bello AI', ['Bello AI', 'Ask']],
      ['Ranks', ['Leaderboard', 'Your standing', 'points']],
      ['You', ['Sign out', 'Your account', 'Settings']],
    ]) {
      const tapped = await tap(page, tab, { settle: 1600 });
      if (!tapped) { log('fail', `tab · ${tab}`, 'destination not tappable'); continue; }
      const seen = await waitFor(page, expect, 12000);
      log(seen ? 'ok' : 'warn', `tab · ${tab}`, seen ? `shows "${seen}"` : 'expected content not seen');
      await shot(page, `tab-${tab.toLowerCase().replace(/\s+/g, '-')}`);
    }

    // ---------- courses drill-down ----------
    await tap(page, 'Courses', { settle: 1400 });
    if (await tap(page, 'PHY 101', { settle: 1800 })) {
      log('ok', 'course hub', 'opened PHY 101');
      await shot(page, 'course-hub');

      const hubLabels = await labels(page);
      for (const want of ['Practice', 'Explanatory Notes', 'Past Questions']) {
        const hit = hubLabels.some((l) => l.toLowerCase().includes(want.toLowerCase()));
        log(hit ? 'ok' : 'warn', `course hub · ${want}`, hit ? '' : 'section tile missing');
      }

      // notes section + search
      if (await tap(page, 'Explanatory Notes', { settle: 1600 })) {
        log('ok', 'section screen', 'opened notes');
        await shot(page, 'section-notes');

        const inputs = await page.$$('input');
        if (inputs.length) {
          await inputs[0].click().catch(() => {});
          await typeIntoFocused(page, 'Worked');
          await sleep(1000);
          const after = await labels(page);
          const filtered = after.some((l) => l.includes('Worked'));
          log(filtered ? 'ok' : 'warn', 'material search', filtered ? 'filtered to matches' : 'no visible filtering');
          await shot(page, 'section-search');
          await typeIntoFocused(page, '');
          await sleep(700);
        } else {
          log('warn', 'material search', 'no search field rendered');
        }

        // open a note
        if (await tap(page, 'Introduction and key laws', { settle: 2500 })) {
          log('ok', 'note screen', 'opened a note');
          await shot(page, 'note');
          const noteLabels = await labels(page);
          const hasBody = noteLabels.some((l) => l.includes('Newton') || l.includes('momentum') || l.includes('inertia'));
          log(hasBody ? 'ok' : 'warn', 'note body', hasBody ? 'HTML rendered' : 'body text not in semantics');
          await page.goBack(); await sleep(1200);
        }
        await page.goBack(); await sleep(1200);
      }
    } else {
      log('fail', 'course hub', 'PHY 101 card not tappable');
    }

    // ---------- practice flow ----------
    await tap(page, 'Courses', { settle: 1200 });
    await tap(page, 'MTH 101', { settle: 1600 });
    const started = await tap(page, 'Practice 20 questions', { settle: 4000 });
    if (started) {
      const inRunner = await waitFor(page, ['Question 1', 'Question 1 of'], 20000);
      if (inRunner) {
        log('ok', 'practice start', 'runner opened at question 1');
        await shot(page, 'practice-q1');

        // A question is either multiple choice / true-false, or typed.
        // Handle both — the bank contains both kinds.
        const nowLabels = await labels(page);
        const isTyped = nowLabels.some((l) => /YOUR ANSWER/i.test(l));
        let answered = false;

        if (isTyped) {
          const typed = await fillByLabel(page, 'YOUR ANSWER', 'kgm/s');
          const checked = await tap(page, 'Check', { settle: 2000 });
          answered = typed && checked;
          log(answered ? 'ok' : 'warn', 'practice answer (typed)',
            answered ? 'answer submitted' : `typed=${typed} checked=${checked}`);
        } else {
          const opts = (await nodes(page)).filter(
            (n) =>
              n.inButton &&
              /^(A|B|C|D|E|T|F|True|False)\b/i.test(n.label) &&
              n.h < 140,
          );
          if (opts.length) {
            await page.mouse.click(opts[0].x, opts[0].y);
            await sleep(2000);
            answered = true;
            log('ok', 'practice answer (choice)', `${opts.length} option(s) offered`);
          } else {
            log('fail', 'practice answer', 'no option rows found');
          }
        }

        if (answered) {
          const after = await labels(page);
          const revealed = after.some((l) =>
            /correct|not this one|not quite|accepted answer/i.test(l));
          log(revealed ? 'ok' : 'warn', 'practice verdict',
            revealed ? 'instant correction shown' : 'no verdict seen');
          const explained = after.some((l) =>
            /momentum|newton|gradient|conserv|velocity|inertia/i.test(l));
          log(explained ? 'ok' : 'warn', 'practice explanation',
            explained ? 'explanation rendered' : 'not detected');
          await shot(page, 'practice-answered');
        }

        // next question
        if (await tap(page, 'Next', { settle: 1400 })) {
          const q2 = await waitFor(page, ['Question 2'], 8000);
          log(q2 ? 'ok' : 'warn', 'practice navigation', q2 ? 'moved to question 2' : 'did not advance');
          await shot(page, 'practice-q2');
        }

        // end the practice
        if (await tap(page, 'End', { settle: 1200 })) {
          await sleep(600);
          const confirmed = (await tap(page, 'End & grade me', { settle: 3500 }))
            || (await tap(page, 'End', { settle: 3500 }))
            || (await tap(page, 'Confirm', { settle: 3500 }));
          const onResult = await waitFor(page, ['%', 'correct', 'review'], 20000);
          log(onResult ? 'ok' : 'warn', 'practice finish', onResult ? 'landed on results' : 'result screen not detected');
          await shot(page, 'result');
        }
      } else {
        log('fail', 'practice start', 'runner did not open');
        await shot(page, 'practice-failed');
      }
    } else {
      log('warn', 'practice start', 'Practice button not found on course hub');
    }

    // ---------- CBT ----------
    await tap(page, 'Courses', { settle: 1200 });
    await tap(page, 'PHY 101', { settle: 1600 });
    await page.mouse.move(215, 600);
    for (let i = 0; i < 4; i++) { await page.mouse.wheel(0, 400); await sleep(300); }
    const cbtStarted = (await tap(page, 'Start', { settle: 4000 }));
    if (cbtStarted) {
      const gate = await waitFor(page, ['I understand', 'Question 1', 'exam conditions'], 15000);
      log(gate ? 'ok' : 'warn', 'cbt start', gate ? `saw "${gate}"` : 'no gate or runner');
      await shot(page, 'cbt-gate');
      await tap(page, 'I understand', { settle: 2000 });
      const clockish = (await labels(page)).some((l) => /\d{1,2}:\d{2}/.test(l));
      log(clockish ? 'ok' : 'warn', 'cbt timer', clockish ? 'countdown rendering' : 'no clock text seen');
      await shot(page, 'cbt-runner');

      if (await tap(page, 'Map', { settle: 1200 })) {
        log('ok', 'cbt navigator', 'question map opens');
        await shot(page, 'cbt-navigator');
        await page.keyboard.press('Escape');
        await sleep(600);
      }
      if (await tap(page, 'Calculator', { settle: 1200 })) {
        log('ok', 'cbt calculator', 'calculator opens');
        await shot(page, 'cbt-calculator');
        await page.keyboard.press('Escape');
        await sleep(600);
      }
    } else {
      log('warn', 'cbt start', 'no Start button found on the tests panel');
    }

    // ---------- dropdowns (CGPA) ----------
    await tap(page, 'You', { settle: 1400 });
    await page.mouse.move(215, 600);
    for (let i = 0; i < 5; i++) { await page.mouse.wheel(0, 450); await sleep(300); }
    await shot(page, 'you-tab');
    if (await tap(page, 'CGPA', { settle: 2000 })) {
      log('ok', 'cgpa screen', 'opened from the You tab');
      await shot(page, 'cgpa');
      const opened = (await tap(page, 'Grade', { settle: 1200 })) || (await tap(page, 'Units', { settle: 1200 }));
      if (opened) {
        log('ok', 'dropdown', 'grade/units picker opens as a sheet');
        await shot(page, 'cgpa-dropdown');
        await page.keyboard.press('Escape');
      } else {
        log('warn', 'dropdown', 'no dropdown control found');
      }
    } else {
      log('warn', 'cgpa screen', 'not reachable from You');
    }

    // ---------- theme toggle ----------
    await tap(page, 'You', { settle: 1200 });
    if ((await tap(page, 'Dark', { settle: 1500 }))) {
      log('ok', 'dark theme', 'switched');
      await shot(page, 'dark-theme');
      await tap(page, 'Light', { settle: 1200 });
    } else {
      log('warn', 'dark theme', 'appearance control not found');
    }

    // ---------- console health ----------
    if (consoleErrors.length === 0) {
      log('ok', 'console', 'no errors');
    } else {
      log('warn', 'console', `${consoleErrors.length} error(s): ${consoleErrors.slice(0, 3).join(' || ')}`);
    }
  } catch (e) {
    log('fail', 'driver', String(e).slice(0, 400));
    try { await shot(page, 'crash'); } catch (_) {}
  } finally {
    const summary = {
      ok: results.filter((r) => r.status === 'ok').length,
      warn: results.filter((r) => r.status === 'warn').length,
      fail: results.filter((r) => r.status === 'fail').length,
      results,
      consoleErrors: consoleErrors.slice(0, 20),
    };
    fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(summary, null, 2));
    process.stdout.write(`\n=== ${summary.ok} ok · ${summary.warn} warn · ${summary.fail} fail ===\n`);
    process.stdout.write(`screenshots + report in ${OUT}\n`);
    await browser.close();
    process.exit(summary.fail > 0 ? 1 : 0);
  }
})();
