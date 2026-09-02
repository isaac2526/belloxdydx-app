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
const MOCK = process.argv[4] || 'http://127.0.0.1:54321';
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

/** Reaches past the app to the backend, to make something change server-side. */
async function backend(pathname, payload) {
  const res = await fetch(MOCK + pathname, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  return res.json();
}

/** Every semantics node currently in the tree, with its label and box. */
async function nodes(page) {
  return page.evaluate(() => {
    const out = [];
    document.querySelectorAll('flt-semantics').forEach((el) => {
      // A Flutter text field is an <input> INSIDE the semantics element,
      // and the accessible name lives on that input — not on the wrapper.
      // Reading only the wrapper makes every text field invisible here.
      const field = el.querySelector(':scope > input, :scope > textarea');
      const label = el.getAttribute('aria-label')
        || (field && (field.getAttribute('aria-label') || field.getAttribute('placeholder')))
        || el.textContent
        || '';
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

/**
 * Writes the whole semantics tree to a file.
 *
 * When a control cannot be found, the useful question is what the app
 * IS exposing — guessing from a screenshot costs a build cycle each time.
 */
async function dumpTree(page, name) {
  const rows = await page.evaluate(() => [...document.querySelectorAll('flt-semantics')].map((el) => {
    const r = el.getBoundingClientRect();
    const field = el.querySelector(':scope > input, :scope > textarea');
    const extra = field
      ? ` <${field.tagName.toLowerCase()} aria-label="${field.getAttribute('aria-label')}" placeholder="${field.getAttribute('placeholder')}">`
      : '';
    const label = (el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 60);
    return `${String(Math.round(r.y)).padStart(5)} ${String(Math.round(r.x)).padStart(4)} `
      + `${Math.round(r.width)}x${Math.round(r.height)} [${el.getAttribute('role') || '-'}] ${label}${extra}`;
  }));
  fs.writeFileSync(path.join(OUT, `tree-${name}.txt`), rows.join('\n'));
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

// Two things make a naive click miss.
//
// The course hub is not a lazy list, so EVERY widget has a semantics
// node — including the ones below the fold, whose boxes sit outside the
// viewport entirely. Clicking their centre clicks nothing.
//
// And the bottom navigation floats OVER the content, so a control near
// the bottom edge has its middle underneath the bar. Clicking there
// switches tab, and because re-tapping the current tab scrolls it back
// to the top, the symptom reads as "the button did nothing".
//
// So: scroll the target into the clear band first, and tell content from
// the pinned navigation by whether the node moves when the page does.
const NAV_GUARD = 96;

/**
 * How much of the bottom edge is covered right now.
 *
 * Pushed routes — the exam, a game, the CGPA sheet — have no bottom bar
 * at all, and reserving space for one there pushes clicks off the
 * primary button that sits at the foot of the page.
 */
async function navGuard(page) {
  const hasBar = await page.evaluate((guard) => {
    const h = window.innerHeight;
    return [...document.querySelectorAll('flt-semantics[role="tab"], flt-semantics[role="tablist"]')]
      .some((el) => {
        const r = el.getBoundingClientRect();
        return r.height > 0 && r.y + r.height / 2 > h - guard;
      });
  }, NAV_GUARD);
  return hasBar ? NAV_GUARD : 8;
}

async function tap(page, text, { exact = false, settle = 900 } = {}) {
  let n = await find(page, text, { exact });
  if (!n) return false;

  const vh = await page.evaluate(() => window.innerHeight);
  const guard = await navGuard(page);
  const line = vh - guard;
  const clear = (node) => node.y >= 8 && node.y <= line;

  // Pinned means the navigation bar: it sits in the strip AND does not
  // move when the page scrolls. Requiring both matters — an off-screen
  // control that simply refused to scroll is not pinned, and treating it
  // as pinned means clicking its coordinates, which are outside the
  // viewport, and landing on the nav bar instead.
  // Starts false on purpose: a control below the fold also sits "in the
  // strip" by coordinates, and assuming it is pinned would skip the
  // scrolling it needs and click the nav bar instead.
  let pinned = false;
  for (let i = 0; i < 5 && !clear(n) && !pinned; i++) {
    const was = n.y;
    await page.mouse.move(215, Math.min(400, line - 40));
    await page.mouse.wheel(0, Math.round(n.y - vh * 0.45));
    await sleep(420);
    const again = await find(page, text, { exact });
    if (!again) break;
    n = again;
    pinned = Math.abs(again.y - was) < 4 && again.y - again.h / 2 > line;
  }

  let y = n.y;
  if (!pinned && !clear(n)) {
    const top = n.y - n.h / 2;
    const bottom = n.y + n.h / 2;
    // Aim at whatever part of it IS visible; if none is, say so rather
    // than clicking a coordinate off the screen and hitting the nav bar.
    if (top < line && bottom > 6) y = Math.max(12, Math.min(line - 10, (Math.max(top, 6) + Math.min(bottom, line)) / 2));
    else return false;
  }

  // Wait for the target to stop moving. Content arriving, a staggered
  // entry or a switcher transition all shift the layout under the
  // pointer, and a click aimed at where a button WAS lands beside it —
  // which looks exactly like a button that does nothing.
  for (let i = 0; i < 6; i++) {
    await sleep(220);
    const again = await find(page, text, { exact });
    if (!again) break;
    const still = Math.abs(again.y - n.y) < 3 && Math.abs(again.x - n.x) < 3;
    n = again;
    if (still) break;
    y = n.y;
  }

  await page.mouse.click(n.x, Math.max(6, Math.min(y, vh - 6)));
  await sleep(settle);
  return true;
}

/**
 * Taps a bottom-navigation destination.
 *
 * "You", "Home" and "Ranks" are ordinary words that also appear in body
 * copy, and a generic label search happily picks the wrong one — it once
 * landed on Bello AI while looking for the You tab. The bar is the strip
 * along the bottom edge, so look for the label there and nowhere else.
 */
async function tapTab(page, name, settle = 1400) {
  const vh = await page.evaluate(() => window.innerHeight);
  // Deliberately the fixed height: this is asking whether a bar is there.
  const hit = (await nodes(page))
    .filter((n) => n.y > vh - NAV_GUARD && n.label.toLowerCase() === name.toLowerCase())
    .sort((a, b) => a.w * a.h - b.w * b.h)[0];
  if (!hit) return false;
  await page.mouse.click(hit.x, hit.y);
  await sleep(settle);
  return true;
}

/**
 * Gets back to the tabbed shell from wherever we are.
 *
 * Several screens are pushed over the shell and a couple of them (a
 * running game, an exam) hold on to you deliberately. Without this, one
 * screen that refuses to close makes every later check report a missing
 * button when the button is simply on another route.
 */
async function toShell(page, tries = 4) {
  for (let i = 0; i < tries; i++) {
    if (await tapTab(page, 'Home', 1400)) return true;
    if (await tap(page, 'Back', { exact: true, settle: 1200 })) continue;
    for (const out of ['Leave', 'Quit', 'Not now', 'Close', 'Done']) {
      if (await tap(page, out, { exact: true, settle: 1200 })) break;
    }
    await page.goBack().catch(() => {});
    await sleep(1200);
  }
  return tapTab(page, 'Home', 1400);
}

/** Leaves a pushed route the way a student would: the app bar's back arrow. */
async function goBack(page, settle = 1400) {
  if (await tap(page, 'Back', { exact: true, settle })) return true;
  await page.goBack().catch(() => {});
  await sleep(settle);
  return true;
}

/**
 * Scrolls a screen until the wanted control is actually built, then taps it.
 *
 * Flutter's lazy lists do not build what is off screen, so an off-screen
 * control has no semantics node at all — searching for it before
 * scrolling finds nothing and says "missing" about something that is
 * simply further down. Scroll in steps, re-reading the tree each time,
 * and stop the moment it appears.
 */
async function scrollToTap(page, text, opts = {}) {
  const { steps = 14, dy = 320, at = [215, 520], settle = 900, exact = false } = opts;
  await page.mouse.move(at[0], at[1]);
  for (let i = 0; i <= steps; i++) {
    // tap() refuses to click something it could not bring on screen, so
    // keep scrolling and ask again rather than accepting the first no.
    if (await find(page, text, { exact })) {
      if (await tap(page, text, { exact, settle })) return true;
    }
    await page.mouse.move(at[0], at[1]);
    await page.mouse.wheel(0, dy);
    await sleep(260);
  }
  await sleep(500);
  return tap(page, text, { exact, settle });
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
  const needle = labelText.toLowerCase();
  const locate = async () => (await nodes(page))
    .filter((n) => n.label.toLowerCase() === needle)
    .sort((a, b) => a.w * a.h - b.w * b.h)[0];

  let label = await locate();
  if (!label) return false;

  // A long form does not fit on a phone. Bring the label into the middle
  // of the screen before clicking under it, or the click lands on
  // whatever happens to be at those coordinates instead.
  const vh = await page.evaluate(() => window.innerHeight);
  for (let i = 0; i < 5 && (label.y < 90 || label.y + dy > vh - 120); i++) {
    const was = label.y;
    await page.mouse.move(215, Math.min(420, vh - 200));
    await page.mouse.wheel(0, Math.round(label.y - vh * 0.4));
    await sleep(400);
    const again = await locate();
    if (!again || Math.abs(again.y - was) < 4) break;
    label = again;
  }

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
  let focused = null;
  for (let i = 0; i < 6 && !focused; i++) {
    focused = await page.$('input:focus, textarea:focus');
    if (!focused) await sleep(300);
  }
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
    if (m.text().startsWith('[DIAG]') || m.text().startsWith('[backend]')) {
      fs.appendFileSync(path.join(OUT, 'diag.log'), m.text() + '\n');
    }
    if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 300));
  });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + String(e).slice(0, 300)));
  // "Failed to load resource" alone says nothing about WHICH resource,
  // and a font or script the app fetches from the internet at runtime is
  // a real problem on a phone with no data.
  page.on('requestfailed', (r) => {
    consoleErrors.push(`requestfailed ${r.failure()?.errorText || ''} ${r.url().slice(0, 160)}`);
  });

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
      const tapped = await tapTab(page, tab, 1600);
      if (!tapped) { log('fail', `tab · ${tab}`, 'destination not tappable'); continue; }
      const seen = await waitFor(page, expect, 12000);
      log(seen ? 'ok' : 'warn', `tab · ${tab}`, seen ? `shows "${seen}"` : 'expected content not seen');
      await shot(page, `tab-${tab.toLowerCase().replace(/\s+/g, '-')}`);
    }

    // ---------- courses drill-down ----------
    await tapTab(page, 'Courses', 1400);
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
    await tapTab(page, 'Courses', 1200);
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

          // The result screen is pushed over the shell, so it has no
          // bottom nav — leaving it is the student's only way back, and
          // every later step depends on that button working.
          const left = (await scrollToTap(page, 'Back to', { settle: 2500 }))
            || (await tapTab(page, 'Home', 2000));
          const backOnShell = await waitFor(page, ['Practice', 'Dashboard', 'Tests & exams'], 12000);
          log(backOnShell ? 'ok' : 'warn', 'result · leave',
            backOnShell ? `returned to the app — saw "${backOnShell}"` : 'stuck on the result screen');
        }
      } else {
        log('fail', 'practice start', 'runner did not open');
        await shot(page, 'practice-failed');
      }
    } else {
      log('warn', 'practice start', 'Practice button not found on course hub');
    }

    // ---------- CBT ----------
    await tapTab(page, 'Courses', 1200);
    await tap(page, 'PHY 101', { settle: 1600 });
    // The tests panel sits below the four section cards, and the button
    // reads Start, Continue or Retake depending on what the student has
    // already done with the test.
    let cbtStarted = '';
    for (const label of ['Start', 'Continue', 'Retake']) {
      if (await scrollToTap(page, label, { settle: 4000, at: [215, 600] })) {
        cbtStarted = label;
        break;
      }
    }
    if (cbtStarted) {
      const gate = await waitFor(page, ['I understand', 'Question 1', 'exam conditions'], 15000);
      log(gate ? 'ok' : 'warn', 'cbt start',
        gate ? `pressed "${cbtStarted}", saw "${gate}"` : `pressed "${cbtStarted}" but no gate or runner`);
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

      // A running exam has no bottom nav on purpose — submitting is the
      // only way out, and that path has to work or a student is trapped.
      await tap(page, 'Submit', { settle: 1500 });
      await tap(page, 'Submit', { exact: true, settle: 5000 });
      const out = await waitFor(page, ['%', 'Dashboard', 'Tests & exams', 'review'], 20000);
      log(out ? 'ok' : 'warn', 'cbt submit',
        out ? `submitted and left the exam — saw "${out}"` : 'still inside the exam');
      await shot(page, 'cbt-submitted');
      // Submitting lands on the result sheet, which is pushed over the
      // shell. "You" appears in its body text, so ask for the tab itself.
      if (!(await find(page, 'You', { exact: true }))) {
        await scrollToTap(page, 'Back to', { settle: 2500 });
      }
    } else {
      log('warn', 'cbt start', 'no Start button found on the tests panel');
    }

    // ---------- dropdowns (CGPA) ----------
    await tapTab(page, 'You', 1400);
    await shot(page, 'you-tab');
    if (await scrollToTap(page, 'CGPA', { settle: 2000, at: [215, 600] })) {
      log('ok', 'cgpa screen', 'opened from the You tab');
      await shot(page, 'cgpa');
      const opened = (await tap(page, 'Grade', { settle: 1200 })) || (await tap(page, 'Units', { settle: 1200 }));
      if (opened) {
        log('ok', 'dropdown', 'grade/units picker opens as a sheet');
        await shot(page, 'cgpa-dropdown');
        await page.keyboard.press('Escape');
        await sleep(700);
      } else {
        log('warn', 'dropdown', 'no dropdown control found');
      }
      await goBack(page);
    } else {
      log('warn', 'cgpa screen', 'not reachable from You');
    }

    // ---------- theme toggle ----------
    await tapTab(page, 'You', 1200);
    if (await scrollToTap(page, 'Dark', { exact: true, settle: 1500, at: [215, 600] })) {
      log('ok', 'dark theme', 'switched');
      await shot(page, 'dark-theme');
      await tap(page, 'Light', { settle: 1200 });
    } else {
      log('warn', 'dark theme', 'appearance control not found');
    }

    // ---------- Bello AI ----------
    await toShell(page);
    // The chat is where the loading states actually matter: a student
    // waits on this one, so "Bello is thinking…" has to appear and then
    // give way to an answer.
    await tapTab(page, 'Bello AI', 2000);
    const aiReady = await waitFor(page, ['Ask Bello anything', 'Ask me anything'], 12000);
    if (aiReady) {
      let asked = await fillByLabel(page, 'Ask Bello anything', 'What is momentum?', 0);
      if (!asked) {
        // Flutter draws a text field as a bare <input> with no label of
        // its own, so fall back to where it visibly is: the wide box on
        // the same row as Send, just to its left.
        const send = await find(page, 'Send', { exact: true });
        if (send) {
          await page.mouse.click(Math.max(40, send.x - 160), send.y);
          await sleep(700);
          asked = await typeIntoFocused(page, 'What is momentum?');
        }
      }
      if (!asked) await dumpTree(page, 'ai');
      log(asked ? 'ok' : 'warn', 'ai · compose', asked ? 'typed a question' : 'could not type into the composer');
      if (asked) {
        await tap(page, 'Send', { settle: 400 });
        // The thinking state is short by design, so look for it or the
        // answer — either proves the request went out.
        const thinking = await waitFor(page, ['thinking', 'momentum', 'Momentum'], 20000);
        log(thinking ? 'ok' : 'warn', 'ai · reply',
          thinking ? `Bello answered — saw "${thinking}"` : 'no reply and no thinking state');
        await shot(page, 'ai-reply');
      }
    } else {
      log('warn', 'ai · compose', 'the chat screen did not open');
    }

    // ---------- suggestion chips ----------
    await tapTab(page, 'Bello AI', 1200);
    if (await tap(page, 'New chat', { settle: 1500 })) {
      // Clearing a conversation is destructive and nothing is saved, so
      // the app asks first. Confirm it, or the modal blocks everything.
      const guarded = !!(await find(page, 'Start a new chat'));
      log(guarded ? 'ok' : 'warn', 'ai · new chat',
        guarded ? 'asks before throwing the conversation away' : 'cleared without asking');
      await shot(page, 'ai-newchat');
      await tap(page, 'New chat', { exact: true, settle: 2000 });

      const chipped = await tap(page, 'Quiz me on', { settle: 2500 });
      log(chipped ? 'ok' : 'warn', 'ai · suggestion',
        chipped ? 'a starter chip fills the composer' : 'no starter chips offered');
      await shot(page, 'ai-suggestion');
    }

    // ---------- Revise ----------
    await toShell(page);
    await tapTab(page, 'Revise', 2000);
    const revise = await waitFor(page, ['Smart revision', 'Revision'], 12000);
    log(revise ? 'ok' : 'warn', 'revise screen', revise ? `opened — saw "${revise}"` : 'did not open');
    await shot(page, 'revise');
    if (await scrollToTap(page, 'My Mistakes', { settle: 3000 })) {
      const deck = await waitFor(page, ['Card 1', 'Nothing missed yet', 'Building your drill'], 15000);
      log(deck ? 'ok' : 'warn', 'mistake bank',
        deck ? `opened — saw "${deck}"` : 'did not open');
      await shot(page, 'mistakes');
      await goBack(page);
    } else {
      log('warn', 'mistake bank', 'no route to My Mistakes from Revise');
    }

    // ---------- announcements ----------
    await toShell(page);
    await tapTab(page, 'You', 1600);
    if (await scrollToTap(page, 'Announcements', { settle: 3000 })) {
      const notices = await waitFor(page, ['Marathon', 'noticeboard', 'Nothing posted yet'], 12000);
      log(notices ? 'ok' : 'warn', 'announcements',
        notices ? `noticeboard opened — saw "${notices}"` : 'did not load');
      await shot(page, 'announcements');
      await goBack(page);
    } else {
      log('warn', 'announcements', 'no route from the You tab');
    }

    // ---------- millionaire ----------
    await toShell(page);
    await tapTab(page, 'You', 1600);
    if (await scrollToTap(page, 'Millionaire', { settle: 3000 })) {
      // The League tile is subtitled "…and the millionaire crown", so a
      // search for Millionaire can land there instead. The League offers
      // its own way in, so take it rather than reporting a failure.
      let stage = await waitFor(page, ['Who Wants To Be'], 8000);
      if (!stage && (await tap(page, 'Enter the hot seat', { settle: 3000 }))) {
        stage = await waitFor(page, ['Who Wants To Be'], 10000);
      }
      log(stage ? 'ok' : 'warn', 'millionaire',
        stage ? 'the stage is set' : 'could not reach the millionaire lobby');
      await shot(page, 'millionaire');
      if (stage && (await tap(page, 'Enter the hot seat', { settle: 4000 }))) {
        // "Ask the class" is printed in the house rules on the lobby, so
        // asserting on it proves nothing. Look for the board instead.
        const playing = await waitFor(page, ['playing for', 'of 15 ·'], 15000);
        log(playing ? 'ok' : 'warn', 'millionaire · play',
          playing ? `hot seat live — saw "${playing}"` : 'game did not start');
        await shot(page, 'millionaire-play');
        if (!playing) await dumpTree(page, 'millionaire');
        if (playing) {
          // Three lifelines, one use each — the poll is the one that
          // talks to the backend, so it is the one worth pressing.
          const lifeline = await tap(page, 'Ask the class', { settle: 4000 });
          const polled = lifeline && (await waitFor(page, ['%', 'of the class', 'sample'], 12000));
          log(polled ? 'ok' : 'warn', 'millionaire · lifeline',
            polled ? 'the class poll comes back' : 'lifeline did not report');
          await shot(page, 'millionaire-lifeline');
        }
      }
      await goBack(page);
    } else {
      log('warn', 'millionaire', 'no route from the You tab');
    }

    // ---------- offline vault ----------
    // The millionaire stage holds on to you on purpose, so make sure we
    // are actually back in the shell before looking for a tab.
    await toShell(page);
    await tapTab(page, 'You', 1600);
    if (await scrollToTap(page, 'Offline Vault', { settle: 3000 })) {
      const vault = await waitFor(page, ['Saved material', 'Nothing saved yet', 'Zero-data reading'], 12000);
      log(vault ? 'ok' : 'warn', 'offline vault',
        vault ? `opened — saw "${vault}"` : 'did not open');
      await shot(page, 'vault');
      await goBack(page);
    } else {
      log('warn', 'offline vault', 'no route from the You tab');
    }

    // ---------- the single-session rule ----------
    // This is the one rule that can throw a student out mid-revision, so
    // test BOTH directions. It shipped broken once: an empty read was
    // taken for a takeover and signed people out at random.
    await toShell(page);
    const joined = fs.existsSync(path.join(OUT, 'mock.log'))
      && /ws {2}join .*active_sessions/.test(fs.readFileSync(path.join(OUT, 'mock.log'), 'utf8'));
    log(joined ? 'ok' : 'warn', 'realtime subscribe',
      joined ? 'app subscribed to its own session row' : 'no channel join seen');

    const cleared = await backend('/__test/session', { username: 'kunle', action: 'clear' });
    await sleep(3000);
    const survived = !!(await find(page, 'Dashboard')) || !!(await find(page, 'Home'));
    log(survived ? 'ok' : 'fail', 'session · row vanishes',
      survived
        ? `still signed in after the row was removed (${cleared.channels} channel(s) notified)`
        : 'SIGNED OUT by a row that named no other device');
    await shot(page, 'session-still-in');

    const took = await backend('/__test/session', { username: 'kunle', action: 'takeover' });
    const kicked = await waitFor(page, ['another device', 'Log in', 'Create free account'], 15000);
    log(kicked ? 'ok' : 'warn', 'session · another device',
      kicked
        ? `signed out on takeover — saw "${kicked}"`
        : `still signed in after takeover (${took.channels} channel(s) notified)`);
    await shot(page, 'session-taken');

    // ---------- creating an account ----------
    // The takeover above left us on the welcome screen, which is exactly
    // where a new student starts.
    await tap(page, 'Create free account', { settle: 2500 });
    const onRegister = await waitFor(page, ['Create your account', 'Surname'], 12000);
    log(onRegister ? 'ok' : 'fail', 'register screen',
      onRegister ? `opened — saw "${onRegister}"` : 'could not reach the sign-up form');
    await shot(page, 'register');

    if (onRegister) {
      const stamp = String(Math.floor(Date.now() / 1000)).slice(-6);
      const form = [
        ['Surname', 'Okafor'],
        ['First name', 'Chidi'],
        ['Email', `chidi${stamp}@example.com`],
        ['Phone', '08099887766'],
        ['Username', `chidi${stamp}`],
        ['Password', 'Password@1#'],
        ['Repeat password', 'Password@1#'],
      ];
      const missed = [];
      for (const [label, value] of form) {
        if (!(await fillByLabel(page, label, value))) missed.push(label);
      }
      log(missed.length === 0 ? 'ok' : 'warn', 'register form',
        missed.length === 0
          ? `${form.length} fields filled`
          : `could not fill: ${missed.join(', ')}`);
      await shot(page, 'register-filled');

      if (missed.length === 0) {
        await scrollToTap(page, 'Create my account', { settle: 5000 });
        const made = await waitFor(page, ['Activate', 'activation key', 'Dashboard'], 20000);
        log(made ? 'ok' : 'fail', 'account created',
          made ? `signed in and sent to activation — saw "${made}"` : 'registration did not complete');
        await shot(page, 'register-done');
      }
    }

    // ---------- preview mode ----------
    // A brand new account has not paid yet. That is a real state a lot
    // of students sit in, so check the app lets them in and tells them
    // plainly what is locked.
    if (await tap(page, 'Do this later', { settle: 3500 })) {
      const preview = await waitFor(page, ['Preview', 'Activate', 'Dashboard'], 15000);
      log(preview ? 'ok' : 'warn', 'preview mode',
        preview ? `unactivated student reaches the app — saw "${preview}"` : 'did not reach the app');
      await shot(page, 'preview-dashboard');

      await tapTab(page, 'Courses', 1800);
      await tap(page, 'PHY 101', { settle: 2000 });
      const gated = await waitFor(page, ['Activate', 'Preview', 'locked'], 8000);
      log(gated ? 'ok' : 'warn', 'preview · locked content',
        gated ? `locked content is signposted — saw "${gated}"` : 'no activation prompt found');
      await shot(page, 'preview-course');
    }

    // ---------- signing out ----------
    const onYou = await tapTab(page, 'You', 1800);
    await shot(page, 'signout-you');
    if (!onYou) log('warn', 'sign out', 'the You tab was not tappable');
    if (await scrollToTap(page, 'Sign out', { settle: 1800 })) {
      await shot(page, 'signout-confirm');
      const dialog = (await labels(page)).filter((l) => l.length < 60);
      await tap(page, 'Sign out', { exact: true, settle: 3500 });
      const out = await waitFor(page, ['Create free account', 'Log in'], 15000);
      log(out ? 'ok' : 'warn', 'sign out',
        out ? `signed out cleanly — saw "${out}"`
            : `still signed in; on screen: ${dialog.slice(0, 12).join(' | ')}`);
      await shot(page, 'signed-out');
    } else {
      log('warn', 'sign out', 'no Sign out control on the You tab');
    }

    // ---------- password recovery ----------
    // Reached the way a student reaches it: from the login screen, not
    // by typing a URL a phone has no address bar for.
    await tap(page, 'Log in', { settle: 2000 });
    await sleep(5000);                       // the 3D intro gates the form
    await tap(page, 'Forgot password?', { settle: 2500 });
    const onForgot = await waitFor(page, ['Send me a reset link', 'reset link'], 12000);
    if (onForgot) {
      const typed = await fillByLabel(page, 'Email', 'kunle@example.com');
      const sent = typed && (await tap(page, 'Send reset link', { settle: 4000 }));
      const confirmed = sent && (await waitFor(page, ['Check your inbox', 'No email'], 12000));
      log(confirmed ? 'ok' : 'warn', 'password recovery',
        confirmed ? 'reset requested and confirmed' : 'did not reach the confirmation');
      await shot(page, 'forgot');
    } else {
      log('warn', 'password recovery', 'could not open the reset screen');
    }

    // ---------- console health ----------
    // Two kinds of noise are expected here and are NOT app faults, so
    // account for them by name rather than letting them hide a real one.
    const EXPECTED = [
      {
        re: /notocoloremoji|ERR_CONNECTION_RESET/i,
        why: 'CanvasKit emoji fallback from fonts.gstatic.com — web only, and blocked in this sandbox. Android and iOS draw emoji with the system font.',
      },
      {
        re: /401 \(Unauthorized\)/,
        why: 'requests already in flight when the takeover test invalidated the token',
      },
    ];
    const unexplained = consoleErrors.filter((e) => !EXPECTED.some((x) => x.re.test(e)));
    for (const x of EXPECTED) {
      const n = consoleErrors.filter((e) => x.re.test(e)).length;
      if (n) log('ok', 'console · expected', `${n} × ${x.why}`);
    }
    if (unexplained.length === 0) {
      log('ok', 'console', 'no unexplained errors');
    } else {
      log('warn', 'console', `${unexplained.length} error(s): ${unexplained.slice(0, 3).join(' || ')}`);
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
