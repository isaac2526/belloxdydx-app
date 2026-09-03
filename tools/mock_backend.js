#!/usr/bin/env node
/* ============================================================
 * BELLOXDYDX MOCK BACKEND
 *
 * A local stand-in for Supabase (auth + REST + RPC) and for the few
 * website endpoints the app still calls. It speaks the real wire
 * formats, so the app runs its ACTUAL code paths against it — no
 * test-only branches inside the app itself.
 *
 * Used to drive the app in a browser for interaction testing, and
 * useful afterwards for offline development.
 *
 *   node tools/mock_backend.js [port]
 *
 * Sign in with any of the seeded students:
 *   kunle  / Password@1#   (activated)
 *   amaka  / Password@1#   (activated)
 *   preview/ Password@1#   (NOT activated — exercises the gates)
 * ============================================================ */

const http = require('http');
const { randomUUID } = require('crypto');

const PORT = Number(process.argv[2] || 54321);

// ------------------------------------------------------------
// Seed data
// ------------------------------------------------------------

const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const USERS = {
  kunle: {
    id: uid(1), email: 'kunle@example.com', password: 'Password@1#',
    surname: 'Adeyemi', first_name: 'Kunle', username: 'kunle',
    matric_no: '235019', phone: '08012345678', is_activated: true,
    referral_code: 'K7M2P9X', current_level: '100', is_frozen: false,
    frozen_reason: null,
  },
  amaka: {
    id: uid(2), email: 'amaka@example.com', password: 'Password@1#',
    surname: 'Okonkwo', first_name: 'Amaka', username: 'amaka_o',
    matric_no: '235044', phone: '08087654321', is_activated: true,
    referral_code: 'A3F8Q2R', current_level: '100', is_frozen: false,
    frozen_reason: null,
  },
  preview: {
    id: uid(3), email: 'preview@example.com', password: 'Password@1#',
    surname: 'Bello', first_name: 'Tunde', username: 'preview',
    matric_no: '', phone: '08099887766', is_activated: false,
    referral_code: 'P1V2W3X', current_level: '100', is_frozen: false,
    frozen_reason: null,
  },
};

const byId = (id) => Object.values(USERS).find((u) => u.id === id);
const byLogin = (v) => {
  const s = String(v || '').toLowerCase();
  return Object.values(USERS).find(
    (u) => u.email.toLowerCase() === s || u.username.toLowerCase() === s,
  );
};

const COURSES = [
  { id: uid(101), code: 'PHY 101', title: 'General Physics I', semester: 1, sort_order: 1, level_code: '100' },
  { id: uid(102), code: 'MTH 101', title: 'Elementary Mathematics I', semester: 1, sort_order: 2, level_code: '100' },
  { id: uid(103), code: 'CHM 101', title: 'General Chemistry I', semester: 1, sort_order: 3, level_code: '100' },
  { id: uid(104), code: 'BIO 101', title: 'General Biology I', semester: 1, sort_order: 4, level_code: '100' },
  { id: uid(105), code: 'STA 111', title: 'Descriptive Statistics', semester: 1, sort_order: 5, level_code: '100' },
  { id: uid(106), code: 'PHY 102', title: 'General Physics II', semester: 2, sort_order: 1, level_code: '100' },
  { id: uid(107), code: 'MTH 103', title: 'Elementary Mathematics III', semester: 2, sort_order: 2, level_code: '100' },
  { id: uid(108), code: 'GST 111', title: 'Communication in English', semester: 2, sort_order: 3, level_code: '100' },
];

// The storage origin the app's shield recognises. Served for real by
// this mock (see /storage/v1/object/public below) so a sync downloads
// actual bytes and an offline reader has something to draw.
const STORAGE = `http://127.0.0.1:${PORT}/storage/v1/object/public`;

const NOTE_BODY = `
<h2>Newton's Laws of Motion</h2>
<figure>
  <img src="${STORAGE}/materials/images/newton-diagram.png"
       alt="A free body diagram">
  <figcaption>A free body diagram</figcaption>
</figure>
<audio controls src="${STORAGE}/materials/audio/tutor-note.mp3"
       title="Tutor Bello walks through this"></audio>
<p>Momentum is the product of an object's <strong>mass</strong> and its
<strong>velocity</strong>. It is a vector quantity, so direction matters.</p>
<h3>First law</h3>
<p>A body remains at rest, or in uniform motion in a straight line, unless acted
upon by a resultant external force. This is sometimes called the law of inertia.</p>
<ul>
  <li>A book on a table stays there until pushed.</li>
  <li>A passenger lurches forward when a bus brakes sharply.</li>
</ul>
<h3>Second law</h3>
<p>The rate of change of momentum is proportional to the applied force:</p>
<p><em>F = ma</em></p>
<table>
  <tr><th>Quantity</th><th>Symbol</th><th>SI unit</th></tr>
  <tr><td>Force</td><td>F</td><td>newton (N)</td></tr>
  <tr><td>Mass</td><td>m</td><td>kilogram (kg)</td></tr>
  <tr><td>Momentum</td><td>p</td><td>kg&middot;m/s</td></tr>
</table>
<h3>Third law</h3>
<p>For every action there is an equal and opposite reaction. Remember: the two
forces act on <strong>different bodies</strong>, which is why they never cancel.</p>
<p>Read this one twice before the CBT. It shows up every single year.</p>
`;

let materialSeq = 200;
const MATERIALS = [];
for (const c of COURSES) {
  const mk = (type, title, extra = {}) => {
    const m = {
      id: uid(materialSeq++),
      course_id: c.id,
      type,
      title,
      topic: extra.topic || '',
      url: extra.url || '',
      content_html: type === 'note' ? NOTE_BODY : '',
      duration_label: extra.duration || '',
      sort_order: MATERIALS.length,
      attachments: extra.attachments || [],
      created_at: new Date(Date.now() - MATERIALS.length * 86400000).toISOString(),
      updated_at: new Date(Date.now() - MATERIALS.length * 3600000).toISOString(),
    };
    MATERIALS.push(m);
    return m;
  };
  mk('note', `${c.code} · Introduction and key laws`, { topic: 'Foundations' });
  mk('note', `${c.code} · Worked examples`, { topic: 'Practice' });
  mk('note', `${c.code} · Exam focus areas`, { topic: 'Revision' });
  // A fourth note so the "search appears above three items" rule is
  // actually exercised by the interaction test.
  mk('note', `${c.code} · Common mistakes`, { topic: 'Revision' });
  mk('slide', `${c.code} · Lecture 1 slides`, {
    topic: 'Week 1',
    url: `${STORAGE}/materials/lecture1.pdf`,
  });
  mk('slide', `${c.code} · Lecture 2 slides`, {
    topic: 'Week 2',
    url: `${STORAGE}/materials/lecture2.pdf`,
  });
  mk('video', `${c.code} · Tutor Bello explains the basics`, {
    duration: '24 min',
    url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  });
  mk('pq', `${c.code} · 2023 past questions`, {
    topic: 'Past questions',
    url: `${STORAGE}/materials/pq2023.pdf`,
  });
}

const QUESTION_BANK = [
  {
    html: 'The SI unit of <strong>momentum</strong> is:',
    image: `${STORAGE}/questions/momentum.png`,
    audio: `${STORAGE}/questions/momentum.mp3`,
    options: [['A', 'Newton'], ['B', 'kg&middot;m/s'], ['C', 'Joule'], ['D', 'Watt']],
    correct: 'B',
    why: '<p>Momentum is mass &times; velocity, so its unit is kg&middot;m/s. A newton is the unit of <em>force</em>, which is the rate of change of momentum.</p>',
  },
  {
    html: 'Which of these is a <strong>vector</strong> quantity?',
    image: `${STORAGE}/questions/vector.png`,
    options: [['A', 'Speed'], ['B', 'Mass'], ['C', 'Velocity'], ['D', 'Temperature']],
    correct: 'C',
    why: '<p>Velocity carries a direction; speed is only its magnitude.</p>',
  },
  {
    html: 'A body of mass 2 kg accelerates at 3 m/s&sup2;. What resultant force acts on it?',
    options: [['A', '1.5 N'], ['B', '5 N'], ['C', '6 N'], ['D', '9 N']],
    correct: 'C',
    why: '<p>F = ma = 2 &times; 3 = 6 N.</p>',
  },
  {
    html: 'Newton&rsquo;s third law pairs act on:',
    options: [['A', 'the same body'], ['B', 'different bodies'], ['C', 'the ground only'], ['D', 'nothing']],
    correct: 'B',
    why: '<p>They act on <strong>different</strong> bodies, which is exactly why they do not cancel out.</p>',
  },
  {
    html: 'The gradient of a velocity&ndash;time graph gives:',
    options: [['A', 'Distance'], ['B', 'Acceleration'], ['C', 'Momentum'], ['D', 'Force']],
    correct: 'B',
    why: '<p>Gradient is change in velocity over change in time, which is acceleration.</p>',
  },
  {
    html: 'Which quantity is conserved in <em>every</em> collision?',
    options: [['A', 'Kinetic energy'], ['B', 'Momentum'], ['C', 'Velocity'], ['D', 'Height']],
    correct: 'B',
    why: '<p>Momentum is conserved in all collisions. Kinetic energy is conserved only in elastic ones.</p>',
  },
];

let qSeq = 1000;
const QUESTIONS = [];
for (const c of COURSES) {
  for (let i = 0; i < 24; i++) {
    const t = QUESTION_BANK[i % QUESTION_BANK.length];
    const isTF = i % 11 === 5;
    const isShort = i % 13 === 7;
    QUESTIONS.push({
      id: uid(qSeq++),
      course_id: c.id,
      question_html: isShort
        ? `State the SI unit of momentum. <em>(${c.code}, question ${i + 1})</em>`
        : `${t.html} <em>(${c.code}, question ${i + 1})</em>`,
      question_image_url: isShort ? null : (t.image || null),
      question_audio_url: isShort ? null : (t.audio || null),
      options: isTF
        ? []
        : isShort
          ? []
          : t.options.map(([key, text]) => ({ key, text, image_url: null })),
      question_type: isTF ? 'true_false' : isShort ? 'short_answer' : 'mcq',
      correct_key: isTF ? 'T' : isShort ? '' : t.correct,
      answer_text: isShort ? 'kgm/s|kg m/s|kilogram metre per second' : null,
      explanation_html: t.why,
      explanation_image_url: t.image ? `${STORAGE}/questions/why-${i % 3}.png` : null,
      explanation_audio_url: `${STORAGE}/questions/why-${i % 3}.mp3`,
      marks: 1,
      course: c.code,
      created_at: new Date(Date.now() - (i + 1) * 86400000).toISOString(),
      // Stamped, because the per-course manifest compares stamps and a
      // bank with no updated_at would report "nothing has ever changed"
      // forever.
      updated_at: new Date(Date.now() - (i + 1) * 3600000).toISOString(),
    });
  }
}
const questionsFor = (courseId) => QUESTIONS.filter((q) => q.course_id === courseId);

let tSeq = 5000;
const TESTS = [];
for (const c of COURSES.slice(0, 5)) {
  TESTS.push({
    id: uid(tSeq++), course_id: c.id, title: `${c.code} Weekly Test`,
    mode: 'test', duration_minutes: 20, question_count: 10,
  });
  TESTS.push({
    id: uid(tSeq++), course_id: c.id, title: `${c.code} Mock Exam`,
    mode: 'exam', duration_minutes: 45, question_count: 20,
  });
}

// The questions a published test claims by hand. The per-course
// download must never hand these over, however offline the phone is —
// that is the one part of the answer-key trade that is enforceable.
const TEST_PINNED = new Set();
for (const c of COURSES.slice(0, 2)) {
  const mine = QUESTIONS.filter((q) => q.course_id === c.id).slice(0, 2);
  for (const q of mine) TEST_PINNED.add(q.id);
}

const ANNOUNCEMENTS = [
  { id: uid(9001), title: 'Marathon countdown is live', body: 'The 168-hour Lecture Marathon starts in December. Countdown is on your dashboard — see you there.', created_at: new Date(Date.now() - 3600e3).toISOString(), is_active: true },
  { id: uid(9002), title: 'New PHY 101 past questions added', body: 'The 2023 paper is now in PHY 101 → Past Questions. Practise it before Friday.', created_at: new Date(Date.now() - 86400e3).toISOString(), is_active: true },
  { id: uid(9003), title: 'Weekend tutorial moved', body: 'Saturday tutorial now holds at 10am instead of 9am. Same venue.', created_at: new Date(Date.now() - 5 * 86400e3).toISOString(), is_active: false },
];

// mutable per-user state
const state = {
  sessions: {},       // access_token -> user id
  attempts: {},       // attempt id -> attempt
  answers: {},        // attempt id -> { qid: {choice, answer_text, is_correct} }
  bookmarks: {},      // user id -> Set(qid)
  reads: {},          // user id -> Set(announcement id)
  streaks: {},        // user id -> {current, best}
  points: {},         // user id -> number
  plays: [],          // millionaire
  devices: {},        // user id -> device id (the single-session rule)
  // The estate-wide switch. Flipped by the driver through
  // /__test/settings so a test can prove the app says something
  // truthful when Tutor Bello turns the offline bank off.
  offlineQuestions: true,
};

for (const u of Object.values(USERS)) {
  state.bookmarks[u.id] = new Set([QUESTIONS[2].id, QUESTIONS[7].id]);
  state.reads[u.id] = new Set([ANNOUNCEMENTS[2].id]);
  state.streaks[u.id] = { current: u.username === 'kunle' ? 12 : 4, best: 21 };
  state.points[u.id] = u.username === 'kunle' ? 1840 : u.username === 'amaka_o' ? 2310 : 90;
}

// A little submitted history for kunle so the dashboard has real shape.
(function seedHistory() {
  const u = USERS.kunle;
  const shape = [
    [COURSES[0], 'PHY 101 Weekly Test', 8, 10],
    [COURSES[1], 'MTH 101 Weekly Test', 7, 10],
    [COURSES[2], null, 14, 20],
    [COURSES[0], null, 16, 20],
    [COURSES[3], 'BIO 101 Mock Exam', 11, 20],
  ];
  shape.forEach(([course, testTitle, score, total], i) => {
    const id = uid(7000 + i);
    const qs = questionsFor(course.id).slice(0, total).map((q) => q.id);
    state.attempts[id] = {
      id, user_id: u.id, course_id: course.id,
      test_id: testTitle ? (TESTS.find((t) => t.title === testTitle) || {}).id || null : null,
      mode: testTitle ? (testTitle.includes('Exam') ? 'exam' : 'test') : 'practice',
      status: 'submitted', score, total, question_ids: qs,
      started_at: new Date(Date.now() - (i + 1) * 86400e3).toISOString(),
      submitted_at: new Date(Date.now() - (i + 1) * 86400e3 + 900e3).toISOString(),
      ends_at: null, violations: i === 4 ? 2 : 0,
    };
    const a = {};
    qs.forEach((qid, n) => {
      const q = QUESTIONS.find((x) => x.id === qid);
      const right = n < score;
      a[qid] = {
        choice: right ? q.correct_key : (q.correct_key === 'A' ? 'B' : 'A'),
        answer_text: null,
        is_correct: right,
      };
    });
    state.answers[id] = a;
  });
})();

// ------------------------------------------------------------
// helpers
// ------------------------------------------------------------

const pct = (s, t) => (t > 0 ? Math.round((s / t) * 100) : 0);
const shuffled = (arr) => arr.map((v) => [Math.random(), v]).sort((a, b) => a[0] - b[0]).map((p) => p[1]);
const norm = (s) => String(s || '').toLowerCase().replace(/\s+/g, '');

function authUser(req) {
  const h = req.headers.authorization || '';
  if (!h.toLowerCase().startsWith('bearer ')) return null;
  const token = h.slice(7).trim();
  const id = state.sessions[token];
  return id ? byId(id) : null;
}

function sessionFor(u) {
  const token = randomUUID().replace(/-/g, '');
  state.sessions[token] = u.id;
  return {
    access_token: token,
    token_type: 'bearer',
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    refresh_token: randomUUID(),
    user: {
      id: u.id, aud: 'authenticated', role: 'authenticated', email: u.email,
      email_confirmed_at: new Date().toISOString(),
      phone: '', confirmed_at: new Date().toISOString(),
      last_sign_in_at: new Date().toISOString(),
      app_metadata: { provider: 'email', providers: ['email'] },
      user_metadata: { username: u.username },
      identities: [], created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(), is_anonymous: false,
    },
  };
}

const profileOf = (u) => ({
  id: u.id, surname: u.surname, first_name: u.first_name, username: u.username,
  email: u.email, phone: u.phone, matric_no: u.matric_no,
  is_activated: u.is_activated, referral_code: u.referral_code,
  current_level: u.current_level, is_frozen: u.is_frozen,
  frozen_reason: u.frozen_reason, role: 'student',
});

const publicQuestion = (q, { withAnswer = false } = {}) => {
  const base = {
    id: q.id, course_id: q.course_id, question_html: q.question_html,
    question_image_url: q.question_image_url, question_audio_url: q.question_audio_url,
    options: q.options, question_type: q.question_type, marks: q.marks, course: q.course,
  };
  if (!withAnswer) return base;
  return {
    ...base,
    correct_key: q.correct_key, answer_text: q.answer_text,
    explanation_html: q.explanation_html,
    explanation_image_url: q.explanation_image_url,
    explanation_audio_url: q.explanation_audio_url,
  };
};

function gradeOne(q, choice, answerText) {
  if (q.question_type === 'short_answer') {
    return String(q.answer_text || '').split('|').some((a) => norm(a) && norm(a) === norm(answerText));
  }
  return String(choice || '').toUpperCase() === String(q.correct_key || '').toUpperCase();
}

// ------------------------------------------------------------
// RPC implementations
// ------------------------------------------------------------

// The device register, exactly as 0011_app_security.sql defines it:
// the FIRST device a student signs in from is trusted on sight, every
// one after it must prove itself.
const DEVICES = [];

// Flipped at runtime by the driver through /__test/settings, which is
// how the "no new build" claim gets exercised rather than asserted.
const MOCK_SETTINGS = {
  allowScreenshots: false,
  deviceVerification: true,
  lockMinutes: 5,
};

const RPC = {
  bx_app_settings: () => ({
    allowScreenshots: MOCK_SETTINGS.allowScreenshots,
    deviceVerification: MOCK_SETTINGS.deviceVerification,
    lockMinutes: MOCK_SETTINGS.lockMinutes,
  }),

  bx_device_seen: (u, p) => {
    const id = String(p.p_device_id || '');
    if (id.length < 8) return { error: 'bad_device' };
    const mine = DEVICES.filter((d) => d.user_id === u.id);
    const found = mine.find((d) => d.device_id === id);
    const now = new Date().toISOString();
    if (found) {
      found.last_seen_at = now;
      if (!found.trusted_at && p.p_verified) found.trusted_at = now;
      return { known: true, trusted: !!found.trusted_at, total: mine.length };
    }
    const isFirst = mine.length === 0;
    const trusted = isFirst || !!p.p_verified;
    DEVICES.push({
      user_id: u.id,
      device_id: id,
      platform: p.p_platform || 'unknown',
      label: p.p_label || '',
      first_seen_at: now,
      last_seen_at: now,
      trusted_at: trusted ? now : null,
    });
    return { known: false, trusted, first: isFirst, total: mine.length + 1 };
  },

  bx_capabilities: () => ({ version: 1, direct: true, features: ['content', 'attempts', 'grading'] }),

  bx_email_for_username: (_u, p) => {
    const found = byLogin(p.p_username);
    return { email: found ? found.email : null };
  },

  bx_username_available: (_u, p) => ({ available: !byLogin(p.p_username) }),

  bx_bind_device: (u, p) => {
    state.devices[u.id] = p.p_device_id || 'unknown-device';
    return { ok: true, activated: u.is_activated, level: u.current_level };
  },

  bx_end_session: (u) => { delete state.devices[u.id]; return { ok: true }; },

  bx_set_level: (u, p) => { u.current_level = p.p_level; return { ok: true, level: p.p_level }; },

  bx_update_profile: (u, p) => {
    if (p.p_first_name) u.first_name = p.p_first_name;
    if (p.p_surname) u.surname = p.p_surname;
    if (p.p_phone) u.phone = p.p_phone;
    if (p.p_matric) u.matric_no = p.p_matric;
    return { ok: true };
  },

  bx_activate_key: (u, p) => {
    const clean = String(p.p_key || '').replace(/\D/g, '');
    if (!/^\d{9}$/.test(clean)) return { error: 'invalid_key' };
    if (clean === '000000000') return { error: 'key_used' };
    if (clean === '111111111') return { error: 'not_your_key' };
    u.is_activated = true;
    return { ok: true, level: '100' };
  },

  bx_content: (u, p) => {
    const level = p.p_level || u.current_level || '100';
    return {
      courses: COURSES.filter((c) => c.level_code === level),
      materials: MATERIALS.map(({ content_html, ...rest }) => rest),
      levels: [
        { code: '100', title: '100 Level', owned: true },
        { code: '200', title: '200 Level', owned: false },
      ],
      level,
      // Carried on the bootstrap, exactly as the real route does.
      settings: RPC.bx_app_settings(u, {}),
    };
  },

  // ---- the per-course download ----------------------------------
  //
  // Mirrors bx_manifest() and bx_course_bundle() in migration 0013 and
  // the two /api/mobile routes that shadow them. The pinned-question
  // rule is modelled too: TEST_PINNED holds the questions a published
  // test claims, and the bundle must never hand those over.
  bx_manifest: (u) => {
    const level = u.current_level || '100';
    return {
      courses: COURSES.filter((c) => c.level_code === level).map((c) => {
        const mats = MATERIALS.filter((m) => m.course_id === c.id);
        const qs = QUESTIONS.filter((q) => q.course_id === c.id);
        const newest = (rows, key) =>
          rows.map((r) => r[key] || '').sort().reverse()[0] || '';
        const ms = newest(mats, 'updated_at');
        const qsStamp = newest(qs, 'updated_at');
        return {
          id: c.id,
          code: c.code,
          title: c.title,
          materials: mats.length,
          questions: qs.length,
          material_stamp: ms,
          question_stamp: qsStamp,
          stamp: [ms, qsStamp].sort().reverse()[0] || '',
        };
      }),
    };
  },

  bx_course_bundle: (u, p) => {
    const course = COURSES.find((c) => c.id === p.p_course_id);
    if (!course) return { error: 'not_found' };
    if (!u.is_activated) return { error: 'not_activated' };
    const part = p.p_part || 'all';
    const off = Math.max(0, p.p_offset | 0);
    const lim = Math.min(Math.max(p.p_limit | 0 || 200, 1), 400);

    const allMats = MATERIALS.filter((m) => m.course_id === course.id);
    const allQs = QUESTIONS.filter(
      (q) => q.course_id === course.id && !TEST_PINNED.has(q.id)
    );

    const mats = part === 'all' || part === 'materials'
      ? allMats.slice(off, off + lim)
      : [];
    const qs = state.offlineQuestions !== false &&
        (part === 'all' || part === 'questions')
      ? allQs.slice(off, off + lim)
      : [];

    const mTotal = part === 'all' || part === 'materials' ? allMats.length : 0;
    const qTotal = state.offlineQuestions !== false &&
        (part === 'all' || part === 'questions')
      ? QUESTIONS.filter((q) => q.course_id === course.id).length
      : 0;

    return {
      course: {
        id: course.id,
        code: course.code,
        title: course.title,
        semester: course.semester,
      },
      materials: mats,
      questions: qs.map((q) => ({ ...q, course_code: course.code })),
      counts: {
        materials: mTotal,
        questions: qTotal,
        materialsInPage: mats.length,
        questionsInPage: qs.length,
        withheld: QUESTIONS.filter(
          (q) => q.course_id === course.id && TEST_PINNED.has(q.id)
        ).length,
      },
      questionsIncluded: state.offlineQuestions !== false,
      nextOffset: off + lim < Math.max(mTotal, qTotal) ? off + lim : null,
      stamp: [...mats, ...qs]
        .map((r) => r.updated_at || '')
        .sort()
        .reverse()[0] || '',
    };
  },

  bx_material: (u, p) => {
    const m = MATERIALS.find((x) => x.id === p.p_id);
    if (!m) return { error: 'not_found' };
    if (!u.is_activated) {
      const { content_html, url, attachments, ...cover } = m;
      return { error: 'not_activated', material: cover };
    }
    return { material: m };
  },

  bx_material_opened: (u, p) => { state.points[u.id] = (state.points[u.id] || 0) + 5; return { ok: true }; },

  bx_tests: (u, p) => TESTS
    .filter((t) => !p.p_course_id || t.course_id === p.p_course_id)
    .map((t) => {
      const mine = Object.values(state.attempts)
        .filter((a) => a.user_id === u.id && a.test_id === t.id);
      const done = mine.filter((a) => a.status === 'submitted');
      const live = mine.find((a) => a.status === 'in_progress');
      return {
        ...t,
        best: done.length ? Math.max(...done.map((a) => pct(a.score, a.total))) : null,
        in_progress_id: live ? live.id : null,
      };
    }),

  bx_start_attempt: (u, p) => {
    if (!u.is_activated) return { error: 'not_activated' };
    let courseId = p.p_course_id;
    let ids = [];
    let endsAt = null;
    let mode = p.p_mode || 'practice';

    if (p.p_test_id || p.p_share_code) {
      const t = p.p_test_id
        ? TESTS.find((x) => x.id === p.p_test_id)
        : TESTS[0];
      if (!t) return { error: 'not_found' };
      courseId = t.course_id;
      mode = t.mode;
      ids = shuffled(questionsFor(t.course_id)).slice(0, t.question_count).map((q) => q.id);
      endsAt = new Date(Date.now() + t.duration_minutes * 60000).toISOString();
    } else if (mode === 'bookmarks') {
      const set = state.bookmarks[u.id] || new Set();
      ids = [...set];
      if (!ids.length) return { error: 'no_bookmarks' };
      courseId = (QUESTIONS.find((q) => q.id === ids[0]) || {}).course_id;
    } else if (mode === 'smart') {
      const wrong = new Set();
      Object.entries(state.answers).forEach(([aid, m]) => {
        const at = state.attempts[aid];
        if (!at || at.user_id !== u.id) return;
        Object.entries(m).forEach(([qid, a]) => { if (a.is_correct === false) wrong.add(qid); });
      });
      ids = [...wrong];
      if (!ids.length) return { error: 'nothing_missed' };
      courseId = courseId || (QUESTIONS.find((q) => q.id === ids[0]) || {}).course_id;
      ids = ids.filter((id) => (QUESTIONS.find((q) => q.id === id) || {}).course_id === courseId);
    } else {
      if (!courseId) return { error: 'not_found' };
      ids = shuffled(questionsFor(courseId)).slice(0, p.p_count || 20).map((q) => q.id);
    }

    if (!ids.length) return { error: 'no_questions' };

    const id = randomUUID();
    state.attempts[id] = {
      id, user_id: u.id, course_id: courseId, test_id: p.p_test_id || null,
      mode, status: 'in_progress', score: null, total: null,
      question_ids: ids, started_at: new Date().toISOString(),
      submitted_at: null, ends_at: endsAt, violations: 0,
    };
    state.answers[id] = {};
    return { attemptId: id, endsAt };
  },

  bx_open_attempt: (u, p) => {
    const a = state.attempts[p.p_attempt_id];
    if (!a || a.user_id !== u.id) return { error: 'not_found' };
    if (a.status === 'submitted') return { error: 'submitted' };
    const timed = a.mode === 'test' || a.mode === 'exam';
    const given = state.answers[a.id] || {};
    const course = COURSES.find((c) => c.id === a.course_id) || {};
    const test = TESTS.find((t) => t.id === a.test_id);

    return {
      id: a.id,
      attempt: { id: a.id, mode: a.mode, status: a.status, violations: a.violations },
      mode: a.mode,
      status: a.status,
      questions: a.question_ids.map((qid) => {
        const q = QUESTIONS.find((x) => x.id === qid);
        return publicQuestion(q, { withAnswer: !timed && !!given[qid] });
      }),
      answers: Object.fromEntries(Object.entries(given).map(([qid, v]) => [
        qid, { choice: v.choice || '', answer_text: v.answer_text, is_correct: timed ? null : v.is_correct },
      ])),
      bookmarks: [...(state.bookmarks[u.id] || [])],
      endsAt: a.ends_at,
      serverNow: new Date().toISOString(),
      title: test ? test.title : (a.mode[0].toUpperCase() + a.mode.slice(1)),
      course: { id: course.id, code: course.code, title: course.title },
    };
  },

  bx_answer: (u, p) => {
    const a = state.attempts[p.p_attempt_id];
    if (!a || a.user_id !== u.id) return { error: 'not_found' };
    if (a.status !== 'in_progress') return { error: 'already_submitted' };
    if (!a.question_ids.includes(p.p_question_id)) return { error: 'bad_request' };

    const timed = a.mode === 'test' || a.mode === 'exam';
    if (timed && a.ends_at && Date.now() > new Date(a.ends_at).getTime() + 5000) {
      return { error: 'time_up', endsAt: a.ends_at, serverNow: new Date().toISOString() };
    }

    const q = QUESTIONS.find((x) => x.id === p.p_question_id);
    const correct = gradeOne(q, p.p_choice, p.p_answer_text);
    state.answers[a.id] = state.answers[a.id] || {};
    state.answers[a.id][q.id] = {
      choice: (p.p_choice || '').toUpperCase(),
      answer_text: p.p_answer_text || null,
      is_correct: timed ? null : correct,
    };

    if (timed) return { ok: true, endsAt: a.ends_at, serverNow: new Date().toISOString() };
    if (correct) state.points[u.id] = (state.points[u.id] || 0) + 2;
    return {
      correct,
      correctKey: q.correct_key,
      acceptedAnswer: String(q.answer_text || '').split('|')[0],
      explanationHtml: q.explanation_html,
      explanationImageUrl: q.explanation_image_url,
      explanationAudioUrl: q.explanation_audio_url,
    };
  },

  bx_submit_attempt: (u, p) => {
    const a = state.attempts[p.p_attempt_id];
    if (!a || a.user_id !== u.id) return { error: 'not_found' };
    if (a.status === 'submitted') return { ok: true, score: a.score, total: a.total };
    const given = state.answers[a.id] || {};
    let got = 0;
    a.question_ids.forEach((qid) => {
      const q = QUESTIONS.find((x) => x.id === qid);
      const ans = given[qid];
      if (!ans) return;
      const right = ans.is_correct === null || ans.is_correct === undefined
        ? gradeOne(q, ans.choice, ans.answer_text)
        : ans.is_correct;
      given[qid].is_correct = right;
      if (right) got += 1;
    });
    a.status = 'submitted';
    a.submitted_at = new Date().toISOString();
    a.score = got;
    a.total = a.question_ids.length;
    return { ok: true, score: got, total: a.total, percent: pct(got, a.total) };
  },

  bx_attempt_result: (u, p) => {
    const a = state.attempts[p.p_attempt_id];
    if (!a || a.user_id !== u.id) return { error: 'not_found' };
    if (a.status !== 'submitted') return { error: 'not_submitted' };
    const given = state.answers[a.id] || {};
    const course = COURSES.find((c) => c.id === a.course_id) || {};
    const test = TESTS.find((t) => t.id === a.test_id);
    return {
      attemptId: a.id, score: a.score, total: a.total, mode: a.mode,
      title: test ? test.title : (a.mode[0].toUpperCase() + a.mode.slice(1)),
      courseCode: course.code, courseId: course.id,
      violations: a.violations,
      timeUsedSeconds: a.submitted_at
        ? Math.round((new Date(a.submitted_at) - new Date(a.started_at)) / 1000) : null,
      beat: a.test_id ? 68 : null,
      items: a.question_ids.map((qid, i) => {
        const q = QUESTIONS.find((x) => x.id === qid);
        const ans = given[qid] || {};
        return {
          n: i + 1,
          ...publicQuestion(q, { withAnswer: true }),
          your_key: ans.choice || null,
          your_text: ans.answer_text || null,
          is_correct: !!ans.is_correct,
          bookmarked: (state.bookmarks[u.id] || new Set()).has(qid),
        };
      }),
    };
  },

  bx_log_violation: (u, p) => {
    const a = state.attempts[p.p_attempt_id];
    if (a) a.violations += 1;
    return { ok: true, violations: a ? a.violations : 0 };
  },

  bx_toggle_bookmark: (u, p) => {
    const set = state.bookmarks[u.id] || (state.bookmarks[u.id] = new Set());
    if (set.has(p.p_question_id)) { set.delete(p.p_question_id); return { saved: false }; }
    set.add(p.p_question_id);
    return { saved: true };
  },

  bx_bookmark_count: (u) => ({ count: (state.bookmarks[u.id] || new Set()).size }),

  bx_report_question: () => ({ ok: true }),

  bx_weak_spots: (u) => {
    const per = {};
    Object.entries(state.answers).forEach(([aid, m]) => {
      const at = state.attempts[aid];
      if (!at || at.user_id !== u.id) return;
      Object.entries(m).forEach(([qid, a]) => {
        if (a.is_correct !== false) return;
        const q = QUESTIONS.find((x) => x.id === qid);
        if (!q) return;
        (per[q.course_id] = per[q.course_id] || new Set()).add(qid);
      });
    });
    return Object.entries(per).map(([courseId, set]) => {
      const c = COURSES.find((x) => x.id === courseId) || {};
      return { course_id: courseId, code: c.code, title: c.title, missed: set.size };
    }).sort((a, b) => b.missed - a.missed);
  },

  bx_mistakes: (u) => {
    const out = [];
    const seen = new Set();
    Object.entries(state.answers).forEach(([aid, m]) => {
      const at = state.attempts[aid];
      if (!at || at.user_id !== u.id) return;
      Object.entries(m).forEach(([qid, a]) => {
        if (a.is_correct !== false || seen.has(qid)) return;
        seen.add(qid);
        const q = QUESTIONS.find((x) => x.id === qid);
        if (q) out.push(publicQuestion(q, { withAnswer: true }));
      });
    });
    return out;
  },

  bx_recent_results: (u, p) => Object.values(state.attempts)
    .filter((a) => a.user_id === u.id && a.status === 'submitted')
    .sort((a, b) => new Date(b.submitted_at) - new Date(a.submitted_at))
    .slice(0, (p && p.p_limit) || 10)
    .map((a) => {
      const c = COURSES.find((x) => x.id === a.course_id) || {};
      const t = TESTS.find((x) => x.id === a.test_id);
      return {
        id: a.id, mode: a.mode, status: a.status, score: a.score, total: a.total,
        submitted_at: a.submitted_at, violations: a.violations,
        course_code: c.code, course_title: c.title, test_title: t ? t.title : null,
      };
    }),

  bx_touch_streak: (u) => state.streaks[u.id] || { current: 1, best: 1 },

  bx_dashboard: (u) => {
    const mine = Object.values(state.attempts).filter((a) => a.user_id === u.id && a.status === 'submitted');
    const answered = Object.entries(state.answers)
      .filter(([aid]) => state.attempts[aid] && state.attempts[aid].user_id === u.id)
      .flatMap(([, m]) => Object.values(m));
    const correct = answered.filter((a) => a.is_correct).length;
    const live = Object.values(state.attempts).find((a) => a.user_id === u.id && a.status === 'in_progress');
    const perCourse = {};
    mine.forEach((a) => {
      const c = COURSES.find((x) => x.id === a.course_id) || {};
      (perCourse[c.code] = perCourse[c.code] || []).push(pct(a.score, a.total));
    });
    const ranked = Object.values(USERS).sort((a, b) => (state.points[b.id] || 0) - (state.points[a.id] || 0));
    return {
      firstName: u.first_name,
      streak: state.streaks[u.id] || { current: 0, best: 0 },
      quote: { content: 'Small daily reading beats midnight panic.', author: 'Tutor Bello' },
      marathonIso: '2026-12-01T09:00:00+01:00',
      resume: live ? {
        id: live.id,
        kind: live.mode === 'test' || live.mode === 'exam' ? 'cbt' : 'practice',
        mode: live.mode,
        courseCode: (COURSES.find((c) => c.id === live.course_id) || {}).code,
      } : null,
      rank: ranked.findIndex((x) => x.id === u.id) + 1,
      points: state.points[u.id] || 0,
      unreadAnnouncements: ANNOUNCEMENTS.filter((a) => !(state.reads[u.id] || new Set()).has(a.id)).length,
      stats: {
        attemptsSubmitted: mine.length,
        averagePercent: mine.length ? Math.round(mine.reduce((s, a) => s + pct(a.score, a.total), 0) / mine.length) : 0,
        questionsAnswered: answered.length,
        correctCount: correct,
        wrongCount: Math.max(0, answered.length - correct),
      },
      courseAverages: Object.entries(perCourse).map(([code, list]) => ({
        code, average: Math.round(list.reduce((a, b) => a + b, 0) / list.length),
      })),
      recent: RPC.bx_recent_results(u, { p_limit: 5 }),
      wallOfFame: [
        { username: 'amaka_o', percent: 95 },
        { username: 'tobi.james', percent: 92 },
        { username: u.username, percent: 90 },
      ],
    };
  },

  bx_leaderboard: (u) => {
    const ranked = Object.values(USERS)
      .sort((a, b) => (state.points[b.id] || 0) - (state.points[a.id] || 0));
    return {
      top: ranked.map((x, i) => ({
        rank: i + 1, username: x.username,
        name: `${x.first_name} ${x.surname}`,
        total: state.points[x.id] || 0, user_id: x.id,
      })),
      me: {
        rank: ranked.findIndex((x) => x.id === u.id) + 1,
        total: state.points[u.id] || 0, username: u.username, user_id: u.id,
      },
    };
  },

  bx_test_rankings: () => Object.values(USERS).map((x, i) => ({
    rank: i + 1, username: x.username, score: 18 - i * 2, total: 20,
    percent: 90 - i * 10, submitted_at: new Date().toISOString(), user_id: x.id,
  })),

  bx_league: (u) => ({
    table: Object.values(USERS).map((x, i) => ({
      rank: i + 1, username: x.username, points: 120 - i * 30,
      attempts: 6 - i, user_id: x.id,
    })),
    winners: state.plays.length
      ? state.plays.slice(-5).reverse().map((p) => ({ username: p.username, won: p.won, crowned: p.crowned }))
      : [{ username: 'amaka_o', won: 500000, crowned: false },
         { username: 'kunle', won: 125000, crowned: false }],
  }),

  // The hot seat needs fifteen playable multiple-choice questions, and
  // it must never be handed the key: the board is scored server-side.
  bx_millionaire_deal: (u, p) => {
    if (!u.is_activated) return { error: 'not_activated' };
    const wanted = (p.p_course_ids || []).length
      ? QUESTIONS.filter((q) => p.p_course_ids.includes(q.course_id))
      : QUESTIONS;
    return wanted
      .filter((q) => q.question_type === 'mcq' && q.options.length >= 2)
      .slice(0, 15)
      .map((q) => {
        const { correct_key, answer_text, explanation_html, ...safe } = q;
        return safe;
      });
  },

  bx_millionaire_poll: (u, p) => {
    const q = QUESTIONS.find((x) => x.id === p.p_question_id);
    const keys = (q && q.options.length ? q.options : [{ key: 'A' }, { key: 'B' }])
      .map((o) => o.key);
    // The class leans the right way, but not unanimously.
    const spread = {};
    let left = 100;
    keys.forEach((k, i) => {
      const share = i === 0 ? 54 : Math.max(0, Math.round(left / (keys.length - i)));
      spread[k] = i === keys.length - 1 ? left : share;
      left -= spread[k];
    });
    return { sample: 128, spread };
  },

  bx_millionaire_report: (u, p) => {
    state.plays.push({
      username: u.username,
      won: p.p_won || 0,
      crowned: !!p.p_crowned,
    });
    return { ok: true };
  },

  bx_daily: (u) => {
    if (!u.is_activated) return { error: 'not_activated' };
    const q = QUESTIONS.filter((x) => x.question_type === 'mcq')[new Date().getDate() % 20];
    return {
      id: q.id, day: new Date().toISOString().slice(0, 10), course: q.course,
      question_html: q.question_html, question_image_url: null,
      options: q.options, question_type: q.question_type,
      correct_key: q.correct_key, explanation_html: q.explanation_html,
    };
  },

  bx_millionaire_deal: (u, p) => {
    const pool = (p.p_course_ids && p.p_course_ids.length)
      ? QUESTIONS.filter((q) => p.p_course_ids.includes(q.course_id))
      : QUESTIONS;
    return shuffled(pool.filter((q) => q.question_type === 'mcq'))
      .slice(0, 18)
      .map((q) => publicQuestion(q, { withAnswer: true }));
  },

  bx_millionaire_poll: (_u, p) => {
    const q = QUESTIONS.find((x) => x.id === p.p_question_id);
    const spread = {};
    (q ? q.options : []).forEach((o, i) => {
      spread[o.key] = o.key === (q && q.correct_key) ? 54 : [18, 16, 12][i % 3];
    });
    return { sample: 96, spread };
  },

  bx_millionaire_report: (u, p) => {
    state.plays.push({ username: u.username, won: p.p_won || 0, crowned: !!p.p_crowned });
    return { ok: true };
  },

  bx_announcements: (u) => ANNOUNCEMENTS.map((a) => ({
    ...a, unread: !(state.reads[u.id] || new Set()).has(a.id),
  })),

  bx_ack_announcement: (u, p) => {
    (state.reads[u.id] = state.reads[u.id] || new Set()).add(p.p_id);
    return { ok: true };
  },

  bx_ack_all_announcements: (u) => {
    state.reads[u.id] = new Set(ANNOUNCEMENTS.map((a) => a.id));
    return { ok: true };
  },
};

// ------------------------------------------------------------
// HTTP
// ------------------------------------------------------------

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Expose-Headers': '*',
  'Access-Control-Max-Age': '86400',
};

let LOG_PATH = '';
const send = (res, code, body) => {
  const payload = body === undefined ? '' : JSON.stringify(body);
  if (LOG_PATH) {
    const line = `${code} ${LOG_PATH}${code >= 400 ? '  <- ' + payload.slice(0, 160) : ''}\n`;
    process.stdout.write(line);
  }
  res.writeHead(code, { ...CORS, 'Content-Type': 'application/json' });
  res.end(payload);
};

function readBody(req) {
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', (d) => { raw += d; });
    req.on('end', () => {
      try { resolve(raw ? JSON.parse(raw) : {}); } catch { resolve({}); }
    });
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') { res.writeHead(204, CORS); return res.end(); }

  const url = new URL(req.url, `http://localhost:${PORT}`);
  const path = url.pathname;
  const body = await readBody(req);
  LOG_PATH = `${req.method} ${path}${url.search}`;

  if (path === '/__test/settings') {
    if (req.method === 'POST') {
      Object.assign(MOCK_SETTINGS, body);
      if (typeof body.offlineQuestions === 'boolean') {
        state.offlineQuestions = body.offlineQuestions;
      }
    }
    return send(res, 200, { ...MOCK_SETTINGS,
      offlineQuestions: state.offlineQuestions });
  }

  // Tutor Bello adding a question, from a test. The manifest must move
  // and the app must raise "there's a change in this course".
  if (path === '/__test/publish') {
    const courseId = body.courseId || COURSES[0].id;
    const course = COURSES.find((c) => c.id === courseId) || COURSES[0];
    const now = new Date().toISOString();
    QUESTIONS.push({
      id: uid(qSeq++),
      course_id: course.id,
      question_html: `A question Tutor Bello added at ${now}`,
      question_image_url: null,
      question_audio_url: null,
      options: [
        { key: 'A', text: 'Yes', image_url: null },
        { key: 'B', text: 'No', image_url: null },
      ],
      question_type: 'mcq',
      correct_key: 'A',
      answer_text: null,
      explanation_html: '<p>Because it is.</p>',
      explanation_image_url: null,
      explanation_audio_url: null,
      marks: 1,
      course: course.code,
      created_at: now,
      updated_at: now,
    });
    return send(res, 200, { ok: true, courseId: course.id,
      questions: QUESTIONS.filter((q) => q.course_id === course.id).length });
  }

  // ---- real bytes for the offline sync -----------------------
  // A 1x1 PNG and a silent MP3 frame. The point is not the content:
  // it is that the sync fetches, stores and re-reads REAL files, and
  // that an offline reader draws from disk instead of the network.
  if (path.startsWith('/storage/v1/object/public/')) {
    const png = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      'base64',
    );
    const mp3 = Buffer.from('SUQzBAAAAAAAI1RTU0UAAAAPAAADTGF2ZjU4Ljc2LjEwMAAAAAAAAAAAAAAA', 'base64');
    // A real, openable one-page PDF. The per-course download fetches
    // whole documents, so the harness has to serve bytes a PDF reader
    // would accept rather than a PNG with a .pdf name.
    const pdf = Buffer.from(
      '%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n' +
      '2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n' +
      '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\n' +
      'trailer<</Root 1 0 R>>\n%%EOF\n',
      'latin1',
    );
    const isAudio = /\.mp3$/.test(path);
    const isPdf = /\.pdf$/.test(path);
    const body = isPdf ? pdf : isAudio ? mp3 : png;
    res.writeHead(200, {
      'content-type': isPdf
        ? 'application/pdf'
        : isAudio ? 'audio/mpeg' : 'image/png',
      'content-length': body.length,
      'cache-control': 'public, max-age=86400',
    });
    process.stdout.write(`200 ${req.method} ${path}  (${body.length} bytes)\n`);
    return res.end(req.method === 'HEAD' ? undefined : body);
  }



  // ---------- Supabase Auth ----------
  if (path === '/auth/v1/token') {
    const grant = url.searchParams.get('grant_type');
    if (grant === 'password') {
      const u = byLogin(body.email);
      if (!u || u.password !== body.password) {
        return send(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials' });
      }
      return send(res, 200, sessionFor(u));
    }
    if (grant === 'refresh_token') {
      const u = Object.values(USERS)[0];
      return send(res, 200, sessionFor(u));
    }
    return send(res, 400, { error: 'unsupported_grant_type' });
  }

  if (path === '/auth/v1/signup') {
    return send(res, 200, sessionFor(Object.values(USERS)[0]));
  }

  if (path === '/auth/v1/user') {
    const u = authUser(req);
    if (!u) return send(res, 401, { message: 'invalid claim' });
    if (req.method === 'PUT') {
      if (body.password) u.password = body.password;
      return send(res, 200, sessionFor(u).user);
    }
    return send(res, 200, sessionFor(u).user);
  }

  if (path === '/auth/v1/logout') { return send(res, 204); }
  if (path === '/auth/v1/recover') { return send(res, 200, {}); }

  // ---------- Supabase REST ----------
  // ---------- Production simulation ----------
  // Production has NOT had the bx_* migration applied, so the app there
  // falls back to the website API — a path the drive had never once
  // exercised. BX_PROD_SIM makes this mock behave the same way: no RPC
  // layer, and a profiles table that RLS keeps to itself.
  if (process.env.BX_PROD_SIM && path.startsWith('/rest/v1/rpc/')) {
    const fn = path.replace('/rest/v1/rpc/', '');
    return send(res, 404, {
      code: 'PGRST202',
      message: `Could not find the function public.${fn}(...) in the schema cache`,
    });
  }

  if (process.env.BX_PROD_SIM && path === '/rest/v1/profiles') {
    // RLS with no SELECT policy does not error — it returns nothing.
    return send(res, 200, []);
  }

  // The legacy endpoints the app falls back to. These all exist on the
  // real website; they are here so the fallback can be tested.
  if (process.env.BX_PROD_SIM) {
    const u = authUser(req);
    if (path === '/api/auth/login') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      state.devices[u.id] = body.deviceId || 'unknown-device';
      return send(res, 200, { ok: true, mobileToken: `mob-${u.id}` });
    }
    if (path === '/api/profile' && req.method === 'GET') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, { profile: profileOf(u) });
    }
    if (path === '/api/auth/heartbeat') {
      return u ? send(res, 200, { ok: true }) : send(res, 401, { error: 'unauthenticated' });
    }
    if (path === '/api/mobile/home2') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_dashboard(u, {}));
    }
    if (path === '/api/me/summary') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_dashboard(u, {}));
    }
    if (path === '/api/mobile/settings') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_app_settings(u, {}));
    }
    if (path === '/api/mobile/device') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      if (req.method === 'GET') {
        const id = url.searchParams.get('deviceId') || '';
        const rows = DEVICES.filter((d) => d.user_id === u.id);
        const mine = rows.find((d) => d.device_id === id);
        return send(res, 200, {
          known: !!mine,
          trusted: !!(mine && mine.trusted_at),
          total: rows.length,
          devices: rows,
        });
      }
      return send(res, 200, RPC.bx_device_seen(u, {
        p_device_id: body.deviceId,
        p_platform: body.platform,
        p_label: body.label,
        p_verified: body.verified === true,
      }));
    }

    if (path === '/api/mobile/content') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_content(u, {}));
    }
    if (path === '/api/mobile/manifest') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_manifest(u, {}));
    }
    if (path === '/api/mobile/course-bundle') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      const r = RPC.bx_course_bundle(u, {
        p_course_id: url.searchParams.get('courseId') || '',
        p_offset: Number(url.searchParams.get('offset') || 0),
        p_limit: Number(url.searchParams.get('limit') || 200),
        p_part: url.searchParams.get('part') || 'all',
      });
      if (r.error === 'not_found') return send(res, 404, r);
      if (r.error === 'not_activated') return send(res, 403, r);
      return send(res, 200, r);
    }
    if (path === '/api/mobile/tests') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, { tests: RPC.bx_tests(u, {}) });
    }
    if (path === '/api/mobile/leaderboard') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, { rows: RPC.bx_leaderboard(u, {}) });
    }
    if (path === '/api/daily') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_daily(u, {}));
    }
    if (path === '/api/league') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_league(u, {}));
    }
    if (path === '/api/mistakes') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, { questions: RPC.bx_mistakes(u, {}) });
    }
    if (path === '/api/streak/touch') {
      return send(res, 200, { ok: true });
    }
    if (path === '/api/auth/logout') return send(res, 200, { ok: true });
    if (path === '/api/auth/check-username') {
      const name = (url.searchParams.get('u') || '').toLowerCase();
      return send(res, 200, { available: !byLogin(name) });
    }
    if (path.startsWith('/api/mobile/material/')) {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      const id = path.split('/').pop();
      return send(res, 200, RPC.bx_material(u, { p_id: id }));
    }
    if (path === '/api/practice/start') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_start_attempt(u, {
        p_course_id: body.courseId, p_mode: 'practice', p_count: body.count,
      }));
    }
    if (path === '/api/cbt/start') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_start_attempt(u, { p_test_id: body.testId }));
    }
    if (path.startsWith('/api/practice/') || path.startsWith('/api/cbt/')) {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      const tail = path.split('/').pop();
      if (tail === 'answer') {
        return send(res, 200, RPC.bx_answer(u, {
          p_attempt_id: body.attemptId, p_question_id: body.questionId,
          p_choice: body.choice, p_answer_text: body.answerText,
        }));
      }
      if (tail === 'submit') {
        return send(res, 200, RPC.bx_submit_attempt(u, { p_attempt_id: body.attemptId }));
      }
      if (req.method === 'GET') {
        const opened = RPC.bx_open_attempt(u, { p_attempt_id: tail });
        // The website's own /api/practice/[id] does `select("*")` and
        // ships the questions WHOLE for untimed modes -- key, accepted
        // answers, explanation and all -- while the direct RPC withholds
        // the key until a question has been answered. That difference is
        // real and the app has to cope with both, so the mock reproduces
        // it rather than smoothing it over. Exams stay sealed on both.
        if (!opened.error && path.startsWith('/api/practice/')) {
          const a = state.attempts[tail];
          if (a && a.mode !== 'test' && a.mode !== 'exam') {
            opened.questions = a.question_ids.map((qid) => {
              const q = QUESTIONS.find((x) => x.id === qid);
              return publicQuestion(q, { withAnswer: true });
            });
          }
        }
        return send(res, 200, opened);
      }
      return send(res, 200, RPC.bx_submit_attempt(u, { p_attempt_id: tail }));
    }
    if (path === '/api/millionaire' && req.method !== 'GET') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      if (body.won !== undefined || body.crowned !== undefined) {
        return send(res, 200, RPC.bx_millionaire_report(u, {
          p_won: body.won, p_crowned: body.crowned,
        }));
      }
      return send(res, 200, {
        questions: RPC.bx_millionaire_deal(u, { p_course_ids: body.courseIds }),
      });
    }
    if (path === '/api/millionaire/poll') {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_millionaire_poll(u, {
        p_question_id: url.searchParams.get('qid'),
      }));
    }
    if (path.startsWith('/api/mobile/cbt-result/')) {
      if (!u) return send(res, 401, { error: 'unauthenticated' });
      return send(res, 200, RPC.bx_attempt_result(u, {
        p_attempt_id: path.split('/').pop(),
      }));
    }
  }

  if (path.startsWith('/rest/v1/rpc/')) {
    const fn = path.replace('/rest/v1/rpc/', '');
    const impl = RPC[fn];
    if (!impl) {
      return send(res, 404, {
        code: 'PGRST202',
        message: `Could not find the function public.${fn}`,
      });
    }
    const needsAuth = fn !== 'bx_capabilities'
      && fn !== 'bx_email_for_username'
      && fn !== 'bx_username_available';
    const u = authUser(req);
    if (needsAuth && !u) return send(res, 401, { message: 'JWT expired' });
    try {
      return send(res, 200, impl(u, body || {}));
    } catch (e) {
      return send(res, 500, { message: String(e && e.message) });
    }
  }

  if (path === '/rest/v1/profiles') {
    const u = authUser(req);
    if (!u) return send(res, 401, { message: 'JWT expired' });
    return send(res, 200, [profileOf(u)]);
  }

  if (path === '/rest/v1/active_sessions') {
    const u = authUser(req);
    if (!u) return send(res, 401, { message: 'JWT expired' });
    const device = state.devices[u.id];
    if (!device) return send(res, 200, []);
    return send(res, 200, [{
      user_id: u.id,
      device_id: device,
      session_token: 'mock-session-token',
      last_seen_at: new Date().toISOString(),
    }]);
  }

  if (path.startsWith('/rest/v1/')) {
    return send(res, 200, []);
  }

  // ---------- Website endpoints the app still uses ----------
  if (path === '/api/ai/chat') {
    const msgs = body.messages || [];
    const last = msgs.length ? msgs[msgs.length - 1].text : '';
    return send(res, 200, {
      reply: `<p>Good question. Here is the short version of <strong>${String(last).slice(0, 60)}</strong>:</p>
<p>Momentum is mass &times; velocity, so its SI unit is kg&middot;m/s. Force is the
<em>rate of change</em> of momentum, which is why F = ma falls out of the same idea.</p>
<p>Try one past question on it now — that is what makes it stick.</p>`,
    });
  }

  if (path === '/api/mobile/version') {
    return send(res, 200, {
      versionCode: 6, minVersionCode: 4, versionName: '6.0.0',
      notes: 'A real native app. Faster, works offline, blocks screenshots.',
      apkUrl: 'https://www.belloxdydx.org/download',
    });
  }

  if (path === '/api/auth/register') {
    if (byLogin(body.username)) return send(res, 400, { error: 'username_taken' });
    if (byLogin(body.email)) return send(res, 400, { error: 'email_taken' });
    const id = uid(500 + Object.keys(USERS).length);
    USERS[body.username] = {
      id, email: body.email, password: body.password,
      surname: body.surname, first_name: body.firstName, username: body.username,
      matric_no: body.matric || '', phone: body.phone, is_activated: false,
      referral_code: 'NEW1234', current_level: '100', is_frozen: false, frozen_reason: null,
    };
    state.bookmarks[id] = new Set();
    state.reads[id] = new Set();
    state.streaks[id] = { current: 0, best: 0 };
    state.points[id] = 0;
    return send(res, 200, { ok: true });
  }

  if (path === '/api/auth/resolve-username') {
    const u = byLogin(body.username);
    return send(res, 200, { email: u ? u.email : null });
  }

  // ---------- Test hooks ----------
  // The single-session rule is the one piece of this app that can throw a
  // student out mid-revision, so the driver needs to provoke both cases:
  // a change that is NOT a takeover (must be ignored) and one that is.
  if (path === '/__test/session') {
    const u = byLogin(body.username || 'kunle');
    if (!u) return send(res, 404, { error: 'no_such_user' });
    const before = state.devices[u.id] || null;

    if (body.action === 'takeover') {
      state.devices[u.id] = 'some-other-phone';
    } else if (body.action === 'clear') {
      delete state.devices[u.id];
    }

    const after = state.devices[u.id] || null;
    const row = (d) => (d == null ? null : {
      user_id: u.id, device_id: d,
      session_token: 'mock-session-token',
      last_seen_at: new Date().toISOString(),
    });
    const channels = broadcastChange(
      'active_sessions',
      after == null ? 'DELETE' : 'UPDATE',
      row(after) || {},
      row(before) || { user_id: u.id },
    );
    return send(res, 200, { ok: true, before, after, channels });
  }

  if (path === '/api/ping') return send(res, 200, { ok: true, t: Date.now() });

  return send(res, 404, { error: 'not_found', path });
});


// ============================================================
// REALTIME
//
// Not decoration. `supabase.from(...).stream()` only emits its first
// snapshot once the channel reports SUBSCRIBED, so with no websocket
// here the app's single-session watcher never runs at all — and that
// watcher is the code that can sign a student out. Speaking enough of
// Phoenix to get a real subscription is the only way to test it.
// ============================================================
const crypto = require('crypto');

const sockets = new Set();

function wsFrame(text) {
  const data = Buffer.from(text, 'utf8');
  const n = data.length;
  let head;
  if (n < 126) {
    head = Buffer.alloc(2);
    head[1] = n;
  } else if (n < 65536) {
    head = Buffer.alloc(4);
    head[1] = 126;
    head.writeUInt16BE(n, 2);
  } else {
    head = Buffer.alloc(10);
    head[1] = 127;
    head.writeUInt32BE(0, 2);
    head.writeUInt32BE(n, 6);
  }
  head[0] = 0x81; // FIN + text
  return Buffer.concat([head, data]);
}

/** Phoenix V2 puts the envelope in a positional array; V1 in an object. */
function encode(v2, { joinRef, ref, topic, event, payload }) {
  return v2
    ? [joinRef ?? null, ref ?? null, topic, event, payload]
    : { topic, event, payload, ref: ref ?? null };
}

/** Reads client frames, which are always masked. */
function wsReader(onText, onClose, onPong) {
  let buf = Buffer.alloc(0);
  return (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      const fin = (buf[0] & 0x80) !== 0;
      const opcode = buf[0] & 0x0f;
      const masked = (buf[1] & 0x80) !== 0;
      let len = buf[1] & 0x7f;
      let off = 2;
      if (len === 126) {
        if (buf.length < 4) return;
        len = buf.readUInt16BE(2); off = 4;
      } else if (len === 127) {
        if (buf.length < 10) return;
        len = Number(buf.readBigUInt64BE(2)); off = 10;
      }
      let mask = null;
      if (masked) {
        if (buf.length < off + 4) return;
        mask = buf.subarray(off, off + 4); off += 4;
      }
      if (buf.length < off + len) return;
      const payload = Buffer.from(buf.subarray(off, off + len));
      if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      buf = buf.subarray(off + len);
      if (process.env.WS_TRACE) {
        process.stdout.write(`  ws  frame op=${opcode} fin=${fin} len=${len}\n`);
      }
      if (opcode === 0x8) return onClose();
      if (opcode === 0x9) { // ping -> pong, or the client gives up on us
        const pong = Buffer.concat([Buffer.from([0x8a, payload.length]), payload]);
        return onPong(pong);
      }
      if (opcode === 0x1 && fin) onText(payload.toString('utf8'));
    }
  };
}

server.on('upgrade', (req, socket) => {
  if (!req.url.startsWith('/realtime/v1/websocket')) {
    socket.destroy();
    return;
  }
  const key = req.headers['sec-websocket-key'] || '';
  const accept = crypto
    .createHash('sha1')
    .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
    .digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
  );
  socket.setNoDelay(true);

  // Phoenix has two wire formats. realtime-dart uses V2, which is a
  // positional array — [join_ref, ref, topic, event, payload] — not the
  // object form. Reply in whichever one the client is speaking.
  const conn = { socket, topics: new Map(), v2: true };
  sockets.add(conn);
  process.stdout.write('  ws  connected\n');

  const push = (msg) => {
    try { socket.write(wsFrame(JSON.stringify(msg))); } catch (_) {}
  };

  const close = () => { sockets.delete(conn); socket.destroy(); };
  socket.on('error', (e) => {
    process.stdout.write(`  ws  socket error: ${e.message}\n`);
    close();
  });
  socket.on('close', () => sockets.delete(conn));

  socket.on('data', wsReader((text) => {
    if (process.env.WS_TRACE) process.stdout.write(`  ws  <- ${text.slice(0, 200)}\n`);
    let raw;
    try { raw = JSON.parse(text); } catch (_) { return; }

    let joinRef, ref, topic, event, payload;
    if (Array.isArray(raw)) {
      [joinRef, ref, topic, event, payload] = raw;
      conn.v2 = true;
    } else {
      ({ topic, event, ref, payload } = raw);
      joinRef = raw.join_ref;
      conn.v2 = false;
    }

    const reply = (response, status = 'ok') => push(encode(conn.v2, {
      joinRef, ref, topic, event: 'phx_reply', payload: { status, response },
    }));

    if (event === 'heartbeat') return reply({});

    if (event === 'phx_join') {
      // Echo the client's own postgres_changes config straight back.
      // realtime-dart compares what it asked for against what it is
      // given and errors the channel on any difference, so inventing a
      // filter here would fail the subscription instead of testing it.
      const asked = ((payload || {}).config || {}).postgres_changes || [];
      const granted = asked.map((c, i) => ({ ...c, id: 90000 + i }));
      conn.topics.set(topic, { joinRef, bindings: granted });
      process.stdout.write(`  ws  join ${topic}\n`);
      return reply({ postgres_changes: granted });
    }

    if (event === 'phx_leave') {
      conn.topics.delete(topic);
      return reply({});
    }

    if (event === 'access_token') return reply({});
  }, close, (pong) => { try { socket.write(pong); } catch (_) {} }));
});

/** Pushes a row change to everyone subscribed to that table. */
function broadcastChange(table, type, record, oldRecord) {
  const shape = Object.keys(record || {}).length
    ? record
    : (oldRecord || {});
  const columns = Object.keys(shape).map((name) => ({ name, type: 'text' }));
  let sent = 0;
  for (const conn of sockets) {
    for (const [topic, sub] of conn.topics) {
      const ids = sub.bindings.filter((b) => b.table === table).map((b) => b.id);
      if (ids.length === 0) continue;
      const msg = encode(conn.v2, {
        joinRef: sub.joinRef, ref: null, topic, event: 'postgres_changes',
        payload: {
          ids,
          data: {
            schema: 'public', table, type, columns,
            commit_timestamp: new Date().toISOString(),
            record: record || {},
            old_record: oldRecord || {},
            errors: null,
          },
        },
      });
      try {
        conn.socket.write(wsFrame(JSON.stringify(msg)));
        sent++;
      } catch (_) {}
    }
  }
  process.stdout.write(`  ws  pushed ${type} on ${table} to ${sent} channel(s)\n`);
  return sent;
}

server.listen(PORT, '127.0.0.1', () => {
  process.stdout.write(`mock backend listening on http://127.0.0.1:${PORT}\n`);
  process.stdout.write(`students: kunle / amaka / preview  ·  password: Password@1#\n`);
});
