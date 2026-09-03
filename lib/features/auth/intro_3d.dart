import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4, Vector3;

import '../../ui/ui.dart';

/// ============================================================
/// THE BELLOXDYDX DOOR — native 3D
///
/// A procedural low-poly scholar walks in with a briefcase, sets it
/// down, the case bursts open on spring physics with gold light, and
/// the real login form rises out of it.
///
/// The website builds this with Three.js and needs a fallback ladder:
/// detect WebGL, detect reduced motion, dispose contexts, handle
/// context loss. Flutter needs none of that — this is a small software
/// renderer over Canvas: flat-shaded quads, painter's-algorithm depth
/// sort, and the same spring integrator the web version uses.
///
/// Roughly 60 quads a frame. It runs on every phone that can run the
/// app at all, which is exactly why it is easier here than on the web.
///
/// It plays once per launch, skips itself for reduced-motion, and can
/// be skipped or replayed by hand.
/// ============================================================

/// Identifies the gate that keeps the form inert until it has risen out
/// of the case. Named so tests can assert on it directly rather than
/// guessing which IgnorePointer in the tree is the right one.
const introFormGateKey = ValueKey<String>('bx-intro-form-gate');

class Intro3D extends StatefulWidget {
  /// The content that rises out of the case.
  final Widget child;

  /// Set false to skip straight to the form (used on the second visit).
  final bool play;

  const Intro3D({super.key, required this.child, this.play = true});

  @override
  State<Intro3D> createState() => _Intro3DState();
}

class _Intro3DState extends State<Intro3D>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 7000),
  );

  final _springs = <String, _Spring>{};
  final _sparks = <_Spark>[];
  bool _risen = false;
  bool _skipped = false;
  bool _finished = false;

  static const _riseAt = 4.3;
  static const _endAt = 6.6;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 90; i++) {
      _sparks.add(_Spark.seeded(i));
    }
    _c.addListener(_onTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.play || reduceMotion(context)) {
        _reveal(immediate: true);
      } else {
        _c.forward();
      }
    });
  }

  void _onTick() {
    final t = _c.value * 7.0;
    if (!_risen && t >= _riseAt) {
      setState(() => _risen = true);
    }
    if (!_finished && t >= _endAt) {
      _finished = true;
      _c.stop();
      setState(() {});
    }
  }

  void _reveal({bool immediate = false}) {
    setState(() {
      _risen = true;
      _finished = true;
      _skipped = true;
    });
    _c.stop();
  }

  void _replay() {
    setState(() {
      _risen = false;
      _finished = false;
      _skipped = false;
      _springs.clear();
    });
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.removeListener(_onTick);
    _c.dispose();
    super.dispose();
  }

  double _spring(String key, double target, double dt,
      {double k = 170, double d = 13}) {
    final s = _springs.putIfAbsent(key, () => _Spring());
    return s.step(target, dt, k, d);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.bx;
    final showStage = !_skipped && !_finished;

    return Stack(
      children: [
        // ---- the 3D stage ----
        if (showStage)
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, __) => CustomPaint(
                  painter: _StagePainter(
                    t: _c.value * 7.0,
                    spring: _spring,
                    sparks: _sparks,
                    gold: c.gold,
                    goldBright: c.goldBright,
                    navy: const Color(0xFF1C2A4A),
                    skin: const Color(0xFF8D5A3B),
                    blue: c.info,
                    ground: c.ground,
                  ),
                ),
              ),
            ),
          ),

        // ---- the form, rising out of the case ----
        Positioned.fill(
          child: IgnorePointer(
            key: introFormGateKey,
            ignoring: !_risen,
            child: AnimatedOpacity(
              opacity: _risen ? 1 : 0,
              duration: const Duration(milliseconds: 620),
              curve: BxCurves.enter,
              child: AnimatedSlide(
                offset: _risen ? Offset.zero : const Offset(0, 0.16),
                duration: const Duration(milliseconds: 700),
                curve: BxCurves.spring,
                child: AnimatedScale(
                  scale: _risen ? 1 : 0.92,
                  duration: const Duration(milliseconds: 700),
                  curve: BxCurves.spring,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),

        // ---- skip / replay ----
        if (showStage && !_risen)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 12,
            child: TextButton(
              onPressed: () => _reveal(),
              style: TextButton.styleFrom(foregroundColor: c.muted),
              child: Text('Skip intro', style: BxType.tiny(c.muted)),
            ),
          ),
        if (_finished && !reduceMotion(context))
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + 6,
            right: 10,
            child: Opacity(
              opacity: 0.7,
              child: TextButton(
                onPressed: _replay,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: Text('Replay intro', style: BxType.tiny(c.muted)),
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// A tiny spring integrator — the same one the web version uses.
// ============================================================
class _Spring {
  double x = 0;
  double v = 0;
  double step(double target, double dt, double k, double d) {
    final a = -k * (x - target) - d * v;
    v += a * dt;
    x += v * dt;
    return x;
  }
}

class _Spark {
  final double vx, vy, vz;
  _Spark(this.vx, this.vy, this.vz);

  /// Deterministic per index so the burst looks identical on a replay
  /// and never depends on a random source during paint.
  factory _Spark.seeded(int i) {
    final a = (i * 2.399963).remainder(math.pi * 2);
    final r = 0.35 + ((i * 37) % 100) / 100 * 1.15;
    final up = 1.7 + ((i * 61) % 100) / 100 * 2.1;
    return _Spark(math.cos(a) * r, up, math.sin(a) * r);
  }
}

// ============================================================
// THE RENDERER
// Flat-shaded quads, sorted back to front. No library, no shaders.
// ============================================================

class _Quad {
  final List<Vector3> pts;
  final Color color;
  final double depth;
  const _Quad(this.pts, this.color, this.depth);
}

class _StagePainter extends CustomPainter {
  final double t;
  final double Function(String, double, double, {double k, double d}) spring;
  final List<_Spark> sparks;
  final Color gold, goldBright, navy, skin, blue, ground;

  _StagePainter({
    required this.t,
    required this.spring,
    required this.sparks,
    required this.gold,
    required this.goldBright,
    required this.navy,
    required this.skin,
    required this.blue,
    required this.ground,
  });

  static const _dt = 1 / 60;
  static final _light = Vector3(0.42, 0.82, 0.4)..normalize();

  double _clamp01(double v) => v.clamp(0.0, 1.0);
  double _ease(double v) => v * v * (3 - 2 * v);

  @override
  void paint(Canvas canvas, Size size) {
    final quads = <_Quad>[];

    // ---------- camera ----------
    final aspect = size.width / size.height;
    final camZ = aspect < 0.75 ? 10.5 : 7.6;
    final camera = _Camera.lookAt(Vector3(0, 1.6, camZ), Vector3(0, 1.05, 0));
    final fov = 42 * math.pi / 180;
    final focal = (size.height / 2) / math.tan(fov / 2);

    Offset project(Vector3 world) {
      final v = camera.toCamera(world);
      final z = v.z <= 0.05 ? 0.05 : v.z;
      return Offset(
        size.width / 2 + (v.x / z) * focal,
        size.height / 2 - (v.y / z) * focal,
      );
    }

    double depthOf(Vector3 world) => camera.toCamera(world).z;

    // ---------- timeline ----------
    const stopX = -1.75, backX = -2.7, caseX = 0.35;

    final walkT = _clamp01(t / 2.2);
    final walking = t < 2.2;
    var studentX = -6.4 + (stopX + 6.4) * _ease(walkT);
    var hipY = 0.92;
    var hipRoll = 0.0;
    var torsoPitch = 0.0;
    var legLA = 0.0, legLB = 0.0, legRA = 0.0, legRB = 0.0;
    var armLA = 0.0, armRA = 0.0, armRB = 0.0;
    var bodyYaw = 0.0;
    var headYaw = 0.0;

    if (walking) {
      final cyc = t * 8.6;
      legLA = math.sin(cyc) * 0.62;
      legRA = math.sin(cyc + math.pi) * 0.62;
      legLB = math.max(0, -math.sin(cyc)) * 0.8;
      legRB = math.max(0, -math.sin(cyc + math.pi)) * 0.8;
      armLA = math.sin(cyc + math.pi) * 0.42;
      armRA = 0.5;
      armRB = 0.35;
      hipY = 0.92 + math.sin(cyc).abs() * 0.045;
      hipRoll = math.sin(cyc) * 0.05;
      headYaw = math.sin(t * 3) * 0.12;
    }

    // crouch and set the case down
    final crouchT = _clamp01((t - 2.2) / 1.1);
    if (t >= 2.2 && t < 3.6) {
      final dip = math.sin(_ease(crouchT) * math.pi);
      hipY = 0.92 - dip * 0.34;
      legLA = -dip * 1.0;
      legLB = dip * 1.5;
      legRA = -dip * 0.7;
      legRB = dip * 1.2;
      armRA = 0.5 + dip * 0.75;
      armLA = -dip * 0.25;
      torsoPitch = dip * 0.3;
    }

    // rise and step back
    if (t >= 3.3) {
      final b = _clamp01((t - 3.3) / 0.7);
      studentX = stopX + (backX - stopX) * _ease(b);
      torsoPitch *= 1 - b;
      legLA *= 1 - b;
      legLB *= 1 - b;
      legRA *= 1 - b;
      legRB *= 1 - b;
      bodyYaw = _ease(b) * 0.35;
      if (t >= 3.6) hipY = 0.92;
    }

    // presenting idle
    if (t >= 4.0) {
      armRA = spring('prA', -1.9, _dt, k: 90, d: 10);
      armRB = spring('prE', -0.4, _dt, k: 90, d: 10);
      armLA = math.sin(t * 2.3) * 0.06;
      hipY = 0.92 + math.sin(t * 2.3) * 0.015;
      headYaw = 0.25 + math.sin(t * 1.4) * 0.06;
    }

    // ---------- the scholar ----------
    final root = Matrix4.identity()
      ..translateByDouble(studentX, 0.0, 0.0, 1.0)
      ..rotateY(bodyYaw);
    final hips = root.clone()
      ..translateByDouble(0.0, hipY, 0.0, 1.0)
      ..rotateZ(hipRoll);

    final torso = hips.clone()
      ..translateByDouble(0.0, 0.34, 0.0, 1.0)
      ..rotateX(torsoPitch);
    _box(quads, torso, 0.5, 0.62, 0.3, blue, project, depthOf);

    final head = hips.clone()..translateByDouble(0.0, 0.82, 0.0, 1.0)..rotateY(headYaw);
    _box(quads, head, 0.38, 0.38, 0.36, skin, project, depthOf);

    // graduation cap
    final cap = hips.clone()..translateByDouble(0.0, 1.0, 0.0, 1.0)..rotateY(headYaw);
    _box(quads, cap, 0.44, 0.07, 0.44, gold, project, depthOf);
    final brim = hips.clone()
      ..translateByDouble(0.0, 0.955, 0.2, 1.0)
      ..rotateY(headYaw);
    _box(quads, brim, 0.3, 0.03, 0.2, gold, project, depthOf);

    // backpack
    final bag = hips.clone()..translateByDouble(0.0, 0.36, -0.26, 1.0);
    _box(quads, bag, 0.42, 0.5, 0.16, goldBright, project, depthOf);

    // limbs
    Matrix4 limb(double x, double y, double rot) => hips.clone()
      ..translateByDouble(x, y, 0.0, 1.0)
      ..rotateX(rot);

    void arm(double x, double a, double b, {Matrix4Callback? hand}) {
      final upper = limb(x, 0.58, a);
      final upperBox = upper.clone()..translateByDouble(0.0, -0.17, 0.0, 1.0);
      _box(quads, upperBox, 0.14, 0.34, 0.14, blue, project, depthOf);
      final joint = upper.clone()
        ..translateByDouble(0.0, -0.34, 0.0, 1.0)
        ..rotateX(b);
      final lowerBox = joint.clone()..translateByDouble(0.0, -0.15, 0.0, 1.0);
      _box(quads, lowerBox, 0.12, 0.3, 0.12, skin, project, depthOf);
      if (hand != null) hand(joint.clone()..translateByDouble(0.0, -0.34, 0.0, 1.0));
    }

    void leg(double x, double a, double b) {
      final upper = limb(x, 0.02, a);
      final upperBox = upper.clone()..translateByDouble(0.0, -0.21, 0.0, 1.0);
      _box(quads, upperBox, 0.14, 0.42, 0.14, navy, project, depthOf);
      final joint = upper.clone()
        ..translateByDouble(0.0, -0.42, 0.0, 1.0)
        ..rotateX(b);
      final lowerBox = joint.clone()..translateByDouble(0.0, -0.2, 0.0, 1.0);
      _box(quads, lowerBox, 0.12, 0.4, 0.12, navy, project, depthOf);
      final foot = joint.clone()..translateByDouble(0.0, -0.42, 0.06, 1.0);
      _box(quads, foot, 0.14, 0.08, 0.26, navy, project, depthOf);
    }

    leg(-0.15, legLA, legLB);
    leg(0.15, legRA, legRB);
    arm(-0.34, armLA, 0);

    Matrix4? handWorld;
    arm(0.34, armRA, armRB, hand: (m) => handWorld = m);

    // ---------- the briefcase ----------
    Matrix4 caseRoot;
    if (t < 2.86 && handWorld != null) {
      final hp = handWorld!.getTranslation();
      caseRoot = Matrix4.identity()
        ..translateByDouble(
            hp.x + 0.1, math.max(hp.y - 0.55, 0.0), hp.z + 0.05, 1.0);
      if (walking) caseRoot.rotateZ(math.sin(t * 8.6) * 0.06);
    } else {
      final r = _clamp01((t - 2.86) / 0.36);
      final hp = handWorld?.getTranslation() ?? Vector3(studentX, 0.5, 0);
      final fromX = hp.x + 0.1, fromY = math.max(hp.y - 0.55, 0.0);
      caseRoot = Matrix4.identity()
        ..translateByDouble(
          fromX + (caseX - fromX) * _ease(r),
          fromY + (0 - fromY) * _ease(r),
          0.2 * _ease(r),
          1.0,
        );
    }

    _box(quads, caseRoot.clone()..translateByDouble(0.0, 0.25, 0.0, 1.0), 0.95, 0.5, 0.62,
        navy, project, depthOf);

    // latches
    final laL = t >= 3.35 ? spring('laL', -1.5, _dt, k: 320, d: 9) : 0.0;
    final laR = t >= 3.45 ? spring('laR', -1.5, _dt, k: 320, d: 9) : 0.0;
    _box(
        quads,
        caseRoot.clone()
          ..translateByDouble(-0.28, 0.5, 0.31, 1.0)
          ..rotateX(laL)
          ..translateByDouble(0.0, -0.02, 0.0, 1.0),
        0.1,
        0.09,
        0.05,
        goldBright,
        project,
        depthOf);
    _box(
        quads,
        caseRoot.clone()
          ..translateByDouble(0.28, 0.5, 0.31, 1.0)
          ..rotateX(laR)
          ..translateByDouble(0.0, -0.02, 0.0, 1.0),
        0.1,
        0.09,
        0.05,
        goldBright,
        project,
        depthOf);

    // handle
    _box(quads, caseRoot.clone()..translateByDouble(0.0, 0.62, 0.0, 1.0), 0.34, 0.05, 0.06,
        goldBright, project, depthOf);

    // lid, hinged at the back
    final lidRot = t >= 3.62 ? spring('lid', -1.95, _dt, k: 150, d: 9.5) : 0.0;
    final lidHinge = caseRoot.clone()
      ..translateByDouble(0.0, 0.5, -0.31, 1.0)
      ..rotateX(lidRot);
    _box(quads, lidHinge.clone()..translateByDouble(0.0, 0.05, 0.31, 1.0), 0.95, 0.1, 0.62,
        navy, project, depthOf);

    // four gold panels unfolding outward
    const panelDefs = [
      [-0.475, 0.5, 0.0, 0.62, 0.0, 1.0], // x hinge, z axis
      [0.475, 0.5, 0.0, 0.62, 0.0, -1.0],
      [0.0, 0.5, 0.31, 0.95, 1.0, -1.0], // z hinge, x axis
      [0.0, 0.5, -0.31, 0.95, 1.0, 1.0],
    ];
    for (var i = 0; i < panelDefs.length; i++) {
      final d = panelDefs[i];
      final open = t >= 3.85 + i * 0.09
          ? spring('pn$i', d[5] * 1.35, _dt, k: 200, d: 10)
          : 0.0;
      final m = caseRoot.clone()..translateByDouble(d[0], d[1], d[2], 1.0);
      if (d[4] == 0.0) {
        m.rotateZ(open);
        m.translateByDouble(0.0, 0.01, 0.0, 1.0);
        _box(quads, m, 0.045, 0.02, d[3], gold, project, depthOf);
      } else {
        m.rotateX(open);
        m.translateByDouble(0.0, 0.01, 0.0, 1.0);
        _box(quads, m, d[3], 0.02, 0.045, gold, project, depthOf);
      }
    }

    // ---------- paint ----------
    quads.sort((a, b) => b.depth.compareTo(a.depth));

    // soft contact shadows
    final shadowPaint = Paint()..color = const Color(0x22000000);
    canvas.drawOval(
      Rect.fromCenter(
        center: project(Vector3(studentX, 0.01, 0)),
        width: 74,
        height: 20,
      ),
      shadowPaint,
    );
    final casePos = caseRoot.getTranslation();
    canvas.drawOval(
      Rect.fromCenter(
        center: project(Vector3(casePos.x, 0.01, casePos.z)),
        width: 92,
        height: 24,
      ),
      shadowPaint,
    );

    final p = Paint()..style = PaintingStyle.fill;
    for (final q in quads) {
      final path = Path()..moveTo(q.pts[0].x, q.pts[0].y);
      for (var i = 1; i < q.pts.length; i++) {
        path.lineTo(q.pts[i].x, q.pts[i].y);
      }
      path.close();
      p.color = q.color;
      canvas.drawPath(path, p);
    }

    // ---------- gold light out of the case ----------
    if (t >= 3.8) {
      final glow = _clamp01((t - 3.8) / 0.5) * (1 - _clamp01((t - 5.4) / 0.9));
      if (glow > 0.01) {
        final centre = project(Vector3(casePos.x, 0.55, casePos.z));
        final pulse = 0.85 + math.sin(t * 14) * 0.15;
        canvas.drawCircle(
          centre,
          130,
          Paint()
            ..shader = RadialGradient(colors: [
              goldBright.withValues(alpha: 0.55 * glow * pulse),
              goldBright.withValues(alpha: 0.0),
            ]).createShader(Rect.fromCircle(center: centre, radius: 130)),
        );
      }
    }

    // ---------- particles ----------
    if (t >= 3.95) {
      final life = t - 3.95;
      final fade = life < 0.15
          ? life / 0.15
          : math.max(0.0, 1 - (life - 0.15) / 1.6);
      if (fade > 0.01) {
        final sp = Paint()..color = goldBright.withValues(alpha: fade);
        for (final s in sparks) {
          final y = 0.45 + s.vy * life - 2.6 * life * life * 0.5;
          if (y < 0) continue;
          final pos = project(Vector3(
            casePos.x + s.vx * life,
            y,
            casePos.z + s.vz * life,
          ));
          canvas.drawCircle(pos, 2.4, sp);
        }
      }
    }
  }

  /// Emits the six faces of a box, each flat-shaded by its normal.
  void _box(
    List<_Quad> out,
    Matrix4 m,
    double w,
    double h,
    double d,
    Color base,
    Offset Function(Vector3) project,
    double Function(Vector3) depthOf,
  ) {
    final hx = w / 2, hy = h / 2, hz = d / 2;
    const faces = [
      [0, 1, 2, 3], // front
      [5, 4, 7, 6], // back
      [4, 0, 3, 7], // left
      [1, 5, 6, 2], // right
      [4, 5, 1, 0], // top
      [3, 2, 6, 7], // bottom
    ];
    final local = [
      Vector3(-hx, hy, hz),
      Vector3(hx, hy, hz),
      Vector3(hx, -hy, hz),
      Vector3(-hx, -hy, hz),
      Vector3(-hx, hy, -hz),
      Vector3(hx, hy, -hz),
      Vector3(hx, -hy, -hz),
      Vector3(-hx, -hy, -hz),
    ];
    final world = local.map((v) => m.transformed3(v)).toList();

    for (final f in faces) {
      final a = world[f[0]], b = world[f[1]], cc = world[f[2]];
      final normal = (b - a).cross(cc - a)..normalize();
      final lambert = math.max(0.0, normal.dot(_light));
      final shade = 0.42 + lambert * 0.58;

      final centre = (world[f[0]] + world[f[1]] + world[f[2]] + world[f[3]])
        ..scale(0.25);
      final depth = depthOf(centre);
      if (depth <= 0.05) continue;

      final pts = f.map((i) {
        final o = project(world[i]);
        return Vector3(o.dx, o.dy, 0);
      }).toList();

      out.add(_Quad(
        pts,
        Color.from(
          alpha: 1,
          red: (base.r * shade).clamp(0.0, 1.0),
          green: (base.g * shade).clamp(0.0, 1.0),
          blue: (base.b * shade).clamp(0.0, 1.0),
        ),
        depth,
      ));
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => old.t != t;
}

typedef Matrix4Callback = void Function(Matrix4 m);

/// Camera space for a right-handed look-at, with positive z running AWAY
/// from the eye so a larger value simply means further back.
class _Camera {
  final Vector3 eye, right, up, forward;
  _Camera(this.eye, this.right, this.up, this.forward);

  factory _Camera.lookAt(Vector3 eye, Vector3 target) {
    final f = (target - eye)..normalize();
    final r = f.cross(Vector3(0, 1, 0))..normalize();
    final u = r.cross(f);
    return _Camera(eye, r, u, f);
  }

  /// Returns (x right, y up, z depth) relative to the camera.
  Vector3 toCamera(Vector3 world) {
    final d = world - eye;
    return Vector3(d.dot(right), d.dot(up), d.dot(forward));
  }
}
