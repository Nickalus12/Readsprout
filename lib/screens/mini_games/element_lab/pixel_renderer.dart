import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'element_registry.dart';
import 'simulation_engine.dart';

// ---------------------------------------------------------------------------
// PixelRenderer — Pixel buffer rendering, glow maps, micro-particles, colors
// ---------------------------------------------------------------------------

class PixelRenderer {
  final SimulationEngine engine;

  late Uint8List _pixels;

  // -- Micro-particle effects ------------------------------------------------
  final List<Int32List> _microParticles = [];
  static const int _maxMicroParticles = 120;

  // -- Pre-allocated glow buffers (Fix 2) ------------------------------------
  late Uint8List _glowR;
  late Uint8List _glowG;
  late Uint8List _glowB;
  bool _glowBuffersValid = false;

  // -- Star positions --------------------------------------------------------
  late List<int> _starPositions;
  late Set<int> _starSet; // cached Set (Fix 3)
  bool _starsGenerated = false;

  // -- Previous dayNightT for detecting transitions (Fix 1) ------------------
  double _prevDayNightT = 0.0;

  PixelRenderer(this.engine);

  Uint8List get pixels => _pixels;
  List<Int32List> get microParticles => _microParticles;

  void init() {
    final total = engine.gridW * engine.gridH;
    _pixels = Uint8List(total * 4);
    // Pre-allocate glow buffers (Fix 2)
    _glowR = Uint8List(total);
    _glowG = Uint8List(total);
    _glowB = Uint8List(total);
  }

  void generateStars() {
    if (_starsGenerated) return;
    _starsGenerated = true;
    final topRows = (engine.gridH * 0.10).floor().clamp(3, 30);
    _starPositions = [];
    for (int i = 0; i < 30; i++) {
      final sx = engine.rng.nextInt(engine.gridW);
      final sy = engine.rng.nextInt(topRows);
      _starPositions.add(sy * engine.gridW + sx);
    }
    // Build cached star set once (Fix 3)
    _starSet = Set<int>.from(_starPositions);
  }

  void clearParticles() {
    _microParticles.clear();
  }

  /// Spawn a micro-particle (rendered in pixel buffer only, not in grid).
  void spawnParticle(int x, int y, int r, int g, int b, int frames) {
    if (_microParticles.length >= _maxMicroParticles) return;
    _microParticles.add(Int32List.fromList([x, y, r, g, b, frames]));
  }

  /// Advance micro-particles: move upward, fade, remove expired.
  void tickMicroParticles() {
    for (int i = _microParticles.length - 1; i >= 0; i--) {
      final p = _microParticles[i];
      p[5]--;
      if (p[5] <= 0) {
        _microParticles.removeAt(i);
        continue;
      }
      p[1] -= 1;
      if (engine.rng.nextInt(3) == 0) p[0] += engine.rng.nextInt(3) - 1;
      p[2] = (p[2] * 220) ~/ 256;
      p[3] = (p[3] * 220) ~/ 256;
      p[4] = (p[4] * 220) ~/ 256;
    }

    // Spawn reaction flash particles
    for (final rf in engine.reactionFlashes) {
      final rx = rf[0], ry = rf[1];
      final rr = rf[2], rg = rf[3], rb = rf[4];
      final count = rf[5];
      for (int i = 0; i < count; i++) {
        final dx = engine.rng.nextInt(5) - 2;
        final dy = -(1 + engine.rng.nextInt(3));
        spawnParticle(rx + dx, ry + dy, rr, rg, rb, 4 + engine.rng.nextInt(3));
      }
    }
    engine.reactionFlashes.clear();

    // Spawn explosion micro-particles from recent explosions
    for (final exp in engine.recentExplosions) {
      final count = (exp.radius * 3).clamp(6, 30);
      for (int i = 0; i < count; i++) {
        final angle = engine.rng.nextDouble() * 6.2832;
        final dist = exp.radius * 0.3 + engine.rng.nextDouble() * exp.radius * 0.8;
        final px = exp.x + (dist * math.cos(angle)).round();
        final py = exp.y + (dist * math.sin(angle)).round();
        // Hot debris particles: orange-white
        const pr = 255;
        final pg = 150 + engine.rng.nextInt(105);
        final pb = engine.rng.nextInt(100);
        spawnParticle(px, py, pr, pg, pb, 5 + engine.rng.nextInt(6));
      }
    }
    engine.recentExplosions.clear();
  }


  /// Linearly interpolate between two RGB colors. [t] ranges 0..255.
  static int _lerpC(int a, int b, int t) => (a + ((b - a) * t) ~/ 255).clamp(0, 255);

  // ── Main render pass ─────────────────────────────────────────────────────

  void renderPixels() {
    final total = engine.gridW * engine.gridH;
    final w = engine.gridW;
    final h = engine.gridH;
    final g = engine.grid;
    final t = engine.isNight ? _getDayNightT() : 0.0;
    final fc = engine.frameCount;

    final baseBgR = (12 - t * 6).round().clamp(0, 255);
    final baseBgG = (12 - t * 6).round().clamp(0, 255);
    final baseBgB = (28 - t * 10).round().clamp(0, 255);

    final glowMul = 1.0 + t * 2.0;
    final glow1R = (18 * glowMul).round();
    final glow1G = (7 * glowMul).round();
    final glow2R = (10 * glowMul).round();
    final glow2G = (3 * glowMul).round();
    final lGlow1 = (30 * glowMul).round();
    final lGlow2 = (18 * glowMul).round();
    final lGlow3 = (8 * glowMul).round();

    // Use cached star set (Fix 3) instead of rebuilding every frame
    final starSet = t > 0.05 ? _starSet : const <int>{};

    final doGlow = fc % 3 == 0;

    final nightBoost = (t * 30).round();
    final nightBoostG = (nightBoost * 0.2).round();
    final nightShimmer = (t * 50).round();
    final nightSmokeBoost = (t * 20).round();
    final nightDimWater = (256 * (1.0 - t * 0.15)).round();
    final nightDimGeneral = (256 * (1.0 - t * 0.2)).round();

    // Detect day/night transition (Fix 1)
    final dayNightTransitioning = (t - _prevDayNightT).abs() > 0.001;
    _prevDayNightT = t;

    // Determine if we need full render or can use dirty chunks (Fix 1)
    bool forceFullRender = dayNightTransitioning;

    Uint8List glowR8 = _glowR;
    Uint8List glowG8 = _glowG;
    Uint8List glowB8 = _glowB;

    if (doGlow) {
      // Zero pre-allocated buffers instead of allocating new ones (Fix 2)
      glowR8.fillRange(0, total, 0);
      glowG8.fillRange(0, total, 0);
      glowB8.fillRange(0, total, 0);

      bool hasEmissive = false;
      for (int i = 0; i < total; i++) {
        final el = g[i];
        if (el != El.fire && el != El.lava && el != El.lightning) continue;
        hasEmissive = true;
        final ex = i % w;
        final ey = i ~/ w;
        if (el == El.lightning) {
          for (int dy = -3; dy <= 3; dy++) {
            final ny = ey + dy;
            if (ny < 0 || ny >= h) continue;
            for (int dx = -3; dx <= 3; dx++) {
              final nx = ex + dx;
              if (nx < 0 || nx >= w) continue;
              final dist = dx.abs() + dy.abs();
              if (dist == 0) continue;
              final ni = ny * w + nx;
              if (g[ni] != El.empty) continue;
              int intensity;
              if (dist <= 1) {
                intensity = lGlow1;
              } else if (dist <= 2) {
                intensity = lGlow2;
              } else {
                intensity = lGlow3;
              }
              glowR8[ni] = (glowR8[ni] + intensity).clamp(0, 255);
              glowG8[ni] = (glowG8[ni] + intensity).clamp(0, 255);
              glowB8[ni] = (glowB8[ni] + (intensity * 2 ~/ 3)).clamp(0, 255);
            }
          }
        } else {
          final isFire = el == El.fire;
          final glowRadius = el == El.lava ? 3 : 2;
          for (int dy = -glowRadius; dy <= glowRadius; dy++) {
            final ny = ey + dy;
            if (ny < 0 || ny >= h) continue;
            for (int dx = -glowRadius; dx <= glowRadius; dx++) {
              final nx = ex + dx;
              if (nx < 0 || nx >= w) continue;
              final dist = dx.abs() + dy.abs();
              if (dist == 0) continue;
              final ni = ny * w + nx;
              if (g[ni] != El.empty) continue;
              if (dist <= 1) {
                glowR8[ni] = (glowR8[ni] + glow1R).clamp(0, 255);
                if (isFire) {
                  glowG8[ni] = (glowG8[ni] + glow1G).clamp(0, 255);
                } else {
                  // Lava: warmer orange glow
                  glowG8[ni] = (glowG8[ni] + glow1G ~/ 2).clamp(0, 255);
                }
              } else if (dist <= 2) {
                glowR8[ni] = (glowR8[ni] + glow2R).clamp(0, 255);
                if (isFire) {
                  glowG8[ni] = (glowG8[ni] + glow2G).clamp(0, 255);
                }
              } else {
                // Outer lava glow (radius 3 only)
                glowR8[ni] = (glowR8[ni] + glow2R ~/ 2).clamp(0, 255);
              }
            }
          }
        }
      }
      _glowBuffersValid = true;
      // Force full render on glow frames with emissive cells to update glow halos
      if (hasEmissive) forceFullRender = true;
    } else if (!_glowBuffersValid) {
      // No valid glow data yet — treat as no glow
      glowR8 = _glowR;
      glowG8 = _glowG;
      glowB8 = _glowB;
    }
    // When !doGlow, reuse the pre-allocated buffers from last glow frame

    // Dirty chunk data for selective rendering (Fix 1)
    final dc = engine.dirtyChunks;
    final chunkCols = engine.chunkCols;
    final chunkRows = engine.chunkRows;

    // Life and grid refs for inline color (Fix 4)
    final life = engine.life;
    final velX = engine.velX;
    final velY = engine.velY;
    final pheroFood = engine.pheroFood;
    final pheroHome = engine.pheroHome;
    final rng = engine.rng;
    final pxBuf = _pixels;

    for (int cy = 0; cy < chunkRows; cy++) {
      final chunkRowBase = cy * chunkCols;
      final yStart = cy * 16;
      final yEnd = (yStart + 16).clamp(0, h);

      for (int cx = 0; cx < chunkCols; cx++) {
        // Skip clean chunks unless forced (Fix 1)
        if (!forceFullRender && dc[chunkRowBase + cx] == 0) continue;

        final xStart = cx * 16;
        final xEnd = (xStart + 16).clamp(0, w);

        for (int y = yStart; y < yEnd; y++) {
          final rowOff = y * w;
          for (int x = xStart; x < xEnd; x++) {
            final i = rowOff + x;
            final el = g[i];
            final pi4 = i * 4;

            if (el == El.empty) {
              final gradientShift = (4 - (y * 6) ~/ h).clamp(0, 6);
              int emptyR = (baseBgR + gradientShift).clamp(0, 30);
              int emptyG = (baseBgG + gradientShift).clamp(0, 30);
              int emptyB = (baseBgB + gradientShift + 2).clamp(0, 40);

              if (_glowBuffersValid) {
                final gr = glowR8[i];
                final gg = glowG8[i];
                final gb = glowB8[i];
                if (gr > 0 || gg > 0 || gb > 0) {
                  emptyR = (emptyR + gr).clamp(0, 255);
                  emptyG = (emptyG + gg).clamp(0, 255);
                  emptyB = (emptyB + gb).clamp(0, 255);
                }
              }

              final foodP = pheroFood[i];
              final homeP = pheroHome[i];
              if (foodP > 8 || homeP > 8) {
                final foodR = foodP > 8 ? (foodP >> 4) : 0;
                final foodG2 = foodP > 8 ? (foodP >> 3) : 0;
                final homeB = homeP > 8 ? (homeP >> 4) : 0;
                emptyR = (emptyR + foodR).clamp(0, 255);
                emptyG = (emptyG + foodG2).clamp(0, 255);
                emptyB = (emptyB + homeB).clamp(0, 255);
              }

              if (starSet.contains(i)) {
                final twinkle = ((fc + i * 17) % 40);
                if (twinkle < 6) {
                  final brightness = twinkle < 3 ? 200 : 140;
                  final starBright = (brightness * t).round();
                  emptyR = (emptyR + starBright).clamp(0, 255);
                  emptyG = (emptyG + starBright).clamp(0, 255);
                  emptyB = (emptyB + starBright).clamp(0, 255);
                }
              }

              pxBuf[pi4] = emptyR;
              pxBuf[pi4 + 1] = emptyG;
              pxBuf[pi4 + 2] = emptyB;
              pxBuf[pi4 + 3] = 255;
              continue;
            }

            // Spawn micro-particles from active elements
            if (fc % 2 == 0) {
              if (el == El.fire) {
                if (rng.nextInt(120) < 2 && y > 1) {
                  // Brighter, more varied fire sparks
                  const sparkR = 255;
                  final sparkG = 180 + rng.nextInt(75);
                  final sparkB = rng.nextInt(120);
                  spawnParticle(x + rng.nextInt(3) - 1, y - 1, sparkR, sparkG, sparkB, 4 + rng.nextInt(4));
                }
              } else if (el == El.lava) {
                if (rng.nextInt(150) < 2 && y > 1) {
                  spawnParticle(x + rng.nextInt(3) - 1, y - 1, 255, 140 + rng.nextInt(60), 20 + rng.nextInt(30), 5 + rng.nextInt(3));
                }
              } else if (el == El.lightning) {
                // Electric sparks from lightning
                if (rng.nextInt(60) < 3 && y > 1) {
                  spawnParticle(x + rng.nextInt(5) - 2, y + rng.nextInt(3) - 1, 255, 255, 100 + rng.nextInt(155), 3 + rng.nextInt(2));
                }
              } else if (el == El.sand) {
                if (rng.nextInt(400) < 1 && y > 1 && y < h - 1 && g[(y + 1) * w + x] == El.empty) {
                  spawnParticle(x, y - 1, 194, 178, 128, 3);
                }
              }
            }

            // Inline element color computation (Fix 4)
            // Write r, g, b, a directly instead of creating Color objects
            int r, g2, b, a = 255;
            _writeElementColor(el, i, x, y, w, h, g, life, velX, velY, fc, rng);
            r = _inlineR;
            g2 = _inlineG;
            b = _inlineB;
            a = _inlineA;

            if (nightBoost > 0) {
              if (el == El.fire || el == El.lava) {
                r = (r + nightBoost).clamp(0, 255);
                g2 = (g2 + nightBoostG).clamp(0, 255);
              } else if (el == El.lightning) {
                // stays bright
              } else if (el == El.water) {
                final isTop = i >= w && g[i - w] != El.water;
                if (isTop && ((fc + x * 3) % 12 < 3)) {
                  r = (r + nightShimmer).clamp(0, 255);
                  g2 = (g2 + nightShimmer).clamp(0, 255);
                  b = (b + nightShimmer).clamp(0, 255);
                } else {
                  r = (r * nightDimWater) >> 8;
                  g2 = (g2 * nightDimWater) >> 8;
                }
              } else if (el == El.smoke) {
                r = (r + nightSmokeBoost).clamp(0, 255);
                g2 = (g2 + nightSmokeBoost).clamp(0, 255);
                b = (b + nightSmokeBoost).clamp(0, 255);
              } else {
                r = (r * nightDimGeneral) >> 8;
                g2 = (g2 * nightDimGeneral) >> 8;
                b = (b * nightDimGeneral) >> 8;
              }
            }

            pxBuf[pi4] = r.clamp(0, 255);
            pxBuf[pi4 + 1] = g2.clamp(0, 255);
            pxBuf[pi4 + 2] = b.clamp(0, 255);
            pxBuf[pi4 + 3] = a;
          }
        }
      }
    }

    // Render micro-particles on top (additive blend)
    for (final p in _microParticles) {
      final px = p[0];
      final py = p[1];
      if (px < 0 || px >= w || py < 0 || py >= h) continue;
      final pi4 = (py * w + px) * 4;
      pxBuf[pi4] = (pxBuf[pi4] + p[2]).clamp(0, 255);
      pxBuf[pi4 + 1] = (pxBuf[pi4 + 1] + p[3]).clamp(0, 255);
      pxBuf[pi4 + 2] = (pxBuf[pi4 + 2] + p[4]).clamp(0, 255);
    }
  }

  // The day/night transition value is managed by the widget. We expose a setter.
  double _dayNightT = 0.0;
  double _getDayNightT() => _dayNightT;
  set dayNightT(double value) => _dayNightT = value;

  /// Build a ui.Image from the pixel buffer.
  ///
  /// Copies the pixel buffer before async decode so the next tick can safely
  /// mutate [_pixels] without corrupting the in-flight image.
  Future<ui.Image> buildImage() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(_pixels),
      engine.gridW,
      engine.gridH,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    return completer.future;
  }

  // ── Inline element color output (Fix 4) ──────────────────────────────────
  // Instead of returning a Color object, we write to these fields directly.
  int _inlineR = 0;
  int _inlineG = 0;
  int _inlineB = 0;
  int _inlineA = 255;

  /// Compute element color and write to _inlineR/G/B/A fields.
  /// Avoids creating Color objects in the hot path (Fix 4).
  void _writeElementColor(int el, int idx, int x, int y, int w, int h,
      Uint8List grid, Uint8List life, Int8List velX, Int8List velY,
      int frameCount, dynamic rng) {
    final variation = ((idx * 7 + y * 3) % 11) - 5;

    switch (el) {
      case El.fire:
        final fireLife = life[idx];
        // Multi-frequency flicker for organic, alive-looking fire
        final flicker1 = (frameCount + idx * 3) % 6;       // fast flicker
        final flicker2 = (frameCount * 2 + idx * 7) % 10;  // medium pulse
        final flicker3 = (frameCount + idx * 13) % 17;     // slow wave
        final flickerSum = (flicker1 < 3 ? 20 : 0) + (flicker2 < 4 ? 15 : 0) + (flicker3 < 6 ? 10 : 0);
        if (fireLife < 8) {
          _inlineR = 255;
          _inlineG = (230 + flickerSum ~/ 2 + variation).clamp(210, 255);
          _inlineB = (120 + flickerSum).clamp(100, 180);
          _inlineA = 255;
        } else if (fireLife < 20) {
          _inlineR = (245 + flickerSum ~/ 4 + variation).clamp(230, 255);
          _inlineG = (120 + variation + flickerSum ~/ 2).clamp(80, 180);
          _inlineB = (flickerSum ~/ 3).clamp(0, 30);
          _inlineA = 255;
        } else if (fireLife < 35) {
          _inlineR = (230 + flickerSum ~/ 4 + variation).clamp(200, 255);
          _inlineG = (50 + variation + flickerSum ~/ 3).clamp(20, 100);
          _inlineB = (flickerSum ~/ 5).clamp(0, 15);
          _inlineA = 255;
        } else {
          final remaining = (80 - fireLife).clamp(1, 45);
          _inlineA = (remaining * 5 + 55).clamp(55, 255);
          _inlineR = (170 + flickerSum ~/ 3 + variation).clamp(140, 220);
          _inlineG = (15 + variation + flickerSum ~/ 5).clamp(0, 50);
          _inlineB = 0;
        }

      case El.lightning:
        if (frameCount.isEven) {
          _inlineR = 255; _inlineG = 255; _inlineB = 102; _inlineA = 255;
        } else {
          _inlineR = 255; _inlineG = 255; _inlineB = 255; _inlineA = 255;
        }

      case El.rainbow:
        final hue = ((engine.rainbowHue + life[idx] * 7) % 360).toDouble();
        final h6 = hue / 60.0;
        final hi = h6.floor() % 6;
        final f = h6 - h6.floor();
        const v = 255;
        const p = 51;
        final q = (v * (1.0 - 0.8 * f)).round();
        final t2 = (v * (1.0 - 0.8 * (1.0 - f))).round();
        _inlineA = 255;
        switch (hi) {
          case 0: _inlineR = v; _inlineG = t2; _inlineB = p;
          case 1: _inlineR = q; _inlineG = v; _inlineB = p;
          case 2: _inlineR = p; _inlineG = v; _inlineB = t2;
          case 3: _inlineR = p; _inlineG = q; _inlineB = v;
          case 4: _inlineR = t2; _inlineG = p; _inlineB = v;
          default: _inlineR = v; _inlineG = p; _inlineB = q;
        }

      case El.steam:
        final steamLife = life[idx];
        _inlineA = (180 - steamLife * 2).clamp(60, 180);
        // Multi-wave wisp for billowing steam effect
        final wisp1 = (frameCount + idx * 5) % 8 < 2 ? 18 : 0;
        final wisp2 = (frameCount * 2 + idx * 11) % 13 < 3 ? 12 : 0;
        final steamWisp = wisp1 + wisp2;
        // Fresh steam is brighter, old steam fades to gray
        final steamBase = steamLife < 30 ? 225 : 210;
        _inlineR = (steamBase + variation + steamWisp).clamp(200, 255);
        _inlineG = (steamBase + variation + steamWisp).clamp(200, 255);
        _inlineB = (240 + steamWisp ~/ 2).clamp(230, 255);

      case El.water:
        if (life[idx] >= 200) {
          life[idx]--;
          if (life[idx] < 200) life[idx] = 0;
          _inlineR = 255; _inlineG = 255; _inlineB = 102; _inlineA = 255;
        } else if (life[idx] >= 140 && life[idx] < 200) {
          life[idx]--;
          final tFrac = ((life[idx] - 140) * 255 ~/ 60).clamp(0, 255);
          _inlineR = _lerpC(30, 170, tFrac);
          _inlineG = _lerpC(100, 220, tFrac);
          _inlineB = 255;
          _inlineA = 255;
        } else {
          final isTop = y > 0 && grid[(y - 1) * w + x] != El.water &&
              grid[(y - 1) * w + x] != El.oil;
          if (isTop) {
            // Multi-wave shimmer for realistic water surface
            final wave1 = ((frameCount + x * 3) % 10 < 2) ? 18 : 0;
            final wave2 = ((frameCount * 2 + x * 7 + 5) % 14 < 3) ? 12 : 0;
            final wave3 = ((frameCount + x * 11) % 20 < 2) ? 25 : 0;
            final shimmer = wave1 + wave2 + wave3;
            _inlineR = (75 + shimmer).clamp(50, 130);
            _inlineG = (185 + shimmer).clamp(170, 230);
            _inlineB = 255;
            _inlineA = 255;
          } else {
            int depth = 0;
            for (int cy = y - 1; cy >= 0 && depth < 8; cy--) {
              if (grid[cy * w + x] == El.water) {
                depth++;
              } else {
                break;
              }
            }
            if (depth < 2) {
              _inlineR = (50 + variation).clamp(30, 70);
              _inlineG = (140 + variation).clamp(120, 160);
              _inlineB = 255;
            } else if (depth < 5) {
              _inlineR = (30 + variation).clamp(10, 50);
              _inlineG = (100 + variation).clamp(80, 120);
              _inlineB = 240;
            } else {
              _inlineR = (15 + variation).clamp(5, 30);
              _inlineG = (70 + variation).clamp(50, 90);
              _inlineB = 210;
            }
            _inlineA = 255;
          }
        }

      case El.sand:
        _inlineA = 255;
        switch ((x + y) % 4) {
          case 0: _inlineR = 194; _inlineG = 178; _inlineB = 128;
          case 1: _inlineR = 210; _inlineG = 190; _inlineB = 138;
          case 2: _inlineR = 182; _inlineG = 162; _inlineB = 112;
          default: _inlineR = 200; _inlineG = 172; _inlineB = 120;
        }

      case El.tnt:
        _inlineA = 255;
        if ((x + y) % 4 == 0) {
          _inlineR = 68; _inlineG = 0; _inlineB = 0;
        } else {
          _inlineR = (204 + variation).clamp(180, 230);
          _inlineG = (34 + variation).clamp(10, 60);
          _inlineB = (34 + variation).clamp(10, 60);
        }

      case El.ant:
        _inlineA = 255;
        final antState = velY[idx];
        if (antState == antCarrierState) {
          final aboveIdx = idx - w;
          if (y > 0 && grid[aboveIdx] != El.ant) {
            _inlineR = 139; _inlineG = 105; _inlineB = 20;
          } else {
            _inlineR = 61; _inlineG = 43; _inlineB = 31;
          }
        } else if (antState == antDiggerState) {
          _inlineR = 42; _inlineG = 17; _inlineB = 17;
        } else if (antState == antForagerState) {
          _inlineR = 26; _inlineG = 42; _inlineB = 17;
        } else if (antState == antReturningState) {
          _inlineR = 17; _inlineG = 17; _inlineB = 34;
        } else {
          if (idx % 3 == 0) {
            _inlineR = 51; _inlineG = 51; _inlineB = 51;
          } else {
            _inlineR = 17; _inlineG = 17; _inlineB = 17;
          }
        }

      case El.seed:
        final v = ((idx % 5) * 4 + variation).clamp(0, 25);
        _inlineR = (139 - v).clamp(100, 150);
        _inlineG = (115 - v).clamp(80, 130);
        _inlineB = (85 - v).clamp(50, 100);
        _inlineA = 255;

      case El.dirt:
        final moisture = life[idx].clamp(0, 5);
        final mFrac = moisture / 5.0;
        // Use a hash-like pattern to avoid visible stripes
        final dirtHash = ((x * 2654435761) ^ (y * 2246822519)) & 0x7FFFFFFF;
        final dirtVar = dirtHash % 5;
        int baseR, baseG, baseB;
        switch (dirtVar) {
          case 0: baseR = 139; baseG = 105; baseB = 20;
          case 1: baseR = 120; baseG = 85;  baseB = 18;
          case 2: baseR = 145; baseG = 95;  baseB = 25;
          case 3: baseR = 130; baseG = 98;  baseB = 22;
          default: baseR = 135; baseG = 90;  baseB = 16;
        }
        // Add per-pixel noise from hash to break up remaining patterns
        final dirtNoise = ((dirtHash >> 8) % 13) - 6;
        _inlineR = (baseR + dirtNoise - mFrac * 59).round().clamp(60, 150);
        _inlineG = (baseG + dirtNoise ~/ 2 - mFrac * 50).round().clamp(40, 120);
        _inlineB = (baseB - mFrac * 5).round().clamp(10, 50);
        _inlineA = 255;

      case El.plant:
        final pType = engine.plantType(idx);
        final pStage = engine.plantStage(idx);
        if (pStage == kStDead) {
          _inlineR = (80 + variation).clamp(60, 100);
          _inlineG = (50 + variation).clamp(30, 70);
          _inlineB = 20;
          _inlineA = 255;
        } else if (pStage == kStWilting) {
          _inlineR = (120 + variation).clamp(100, 150);
          _inlineG = (130 + variation).clamp(110, 160);
          _inlineB = (40 + variation).clamp(20, 60);
          _inlineA = 255;
        } else {
          final shade = ((idx % 5) * 8 + variation).clamp(0, 50);
          _inlineA = 255;
          switch (pType) {
            case kPlantGrass:
              _inlineR = 30 + shade; _inlineG = 170 + shade ~/ 2; _inlineB = 30 + shade;
            case kPlantFlower:
              if (pStage == kStMature) {
                final hue2 = ((idx * 37) % 5);
                switch (hue2) {
                  case 0: _inlineR = 255; _inlineG = 68; _inlineB = 136;
                  case 1: _inlineR = 255; _inlineG = 221; _inlineB = 68;
                  case 2: _inlineR = 255; _inlineG = 136; _inlineB = 204;
                  case 3: _inlineR = 153; _inlineG = 68; _inlineB = 255;
                  default: _inlineR = 68; _inlineG = 136; _inlineB = 255;
                }
              } else {
                _inlineR = 20 + shade; _inlineG = 160 + shade; _inlineB = 20 + shade;
              }
            case kPlantTree:
              if (pStage == kStGrowing) {
                _inlineR = (100 + variation).clamp(80, 120);
                _inlineG = (60 + variation).clamp(40, 80);
                _inlineB = (25 + variation).clamp(10, 40);
              } else {
                _inlineR = 15 + shade ~/ 2; _inlineG = 120 + shade; _inlineB = 15 + shade ~/ 2;
              }
            case kPlantMushroom:
              if (pStage == kStMature) {
                final spot = (idx * 13) % 7 == 0;
                if (spot) {
                  _inlineR = 240; _inlineG = 240; _inlineB = 224;
                } else {
                  _inlineR = (180 + variation).clamp(160, 210);
                  _inlineG = (50 + variation).clamp(30, 70);
                  _inlineB = (30 + variation).clamp(10, 50);
                }
              } else {
                _inlineR = (220 + variation).clamp(200, 240);
                _inlineG = (210 + variation).clamp(190, 230);
                _inlineB = (180 + variation).clamp(160, 200);
              }
            case kPlantVine:
              final isLeaf = velY[idx] % 4 == 0;
              if (isLeaf) {
                _inlineR = 10 + shade; _inlineG = 180 + shade ~/ 2; _inlineB = 10 + shade;
              } else {
                _inlineR = 30 + shade; _inlineG = 140 + shade; _inlineB = 30 + shade;
              }
            default:
              _inlineR = 20 + shade; _inlineG = 160 + shade; _inlineB = 20 + shade;
          }
        }

      case El.ice:
        _inlineA = 255;
        // Occasional bright glint on ice facets
        final iceGlint = (frameCount + idx * 13) % 30 < 2 ? 20 : 0;
        if ((x + y) % 3 == 0) {
          _inlineR = (230 + iceGlint).clamp(230, 255);
          _inlineG = (240 + iceGlint).clamp(240, 255);
          _inlineB = 255;
        } else {
          final facet = (x * 5 + y * 9) % 3;
          switch (facet) {
            case 0: _inlineR = (175 + variation + iceGlint).clamp(155, 210); _inlineG = (225 + variation + iceGlint).clamp(205, 255); _inlineB = 255;
            case 1: _inlineR = (160 + variation + iceGlint).clamp(140, 195); _inlineG = (210 + variation + iceGlint).clamp(190, 240); _inlineB = 248;
            default: _inlineR = (185 + variation + iceGlint).clamp(165, 220); _inlineG = (230 + variation + iceGlint).clamp(210, 255); _inlineB = 255;
          }
        }

      case El.stone:
        _inlineA = 255;
        switch ((x * 7 + y * 13) % 4) {
          case 0: _inlineR = 140; _inlineG = 140; _inlineB = 140;
          case 1: _inlineR = 118; _inlineG = 118; _inlineB = 118;
          case 2: _inlineR = 100; _inlineG = 100; _inlineB = 105;
          default: _inlineR = 125; _inlineG = 128; _inlineB = 135;
        }

      case El.mud:
        final v = ((idx % 5) * 5 + variation).clamp(0, 30);
        _inlineR = (139 - v).clamp(100, 150);
        _inlineG = (105 - v).clamp(70, 120);
        _inlineB = 20;
        _inlineA = 255;

      case El.oil:
        _inlineA = 255;
        final isTop = y > 0 && grid[(y - 1) * w + x] != El.oil;
        if (isTop) {
          final shimmer = (frameCount + x) % 8 < 2 ? 20 : 0;
          _inlineR = 74 + shimmer; _inlineG = 55 + shimmer; _inlineB = 40 + shimmer;
        } else {
          _inlineR = (50 + variation).clamp(30, 70);
          _inlineG = (37 + variation).clamp(20, 55);
          _inlineB = (28 + variation).clamp(10, 45);
        }

      case El.acid:
        // Acid with multi-frequency bubbling and toxic glow
        final acidBubble1 = (frameCount + idx) % 12 < 3 ? 35 : 0;
        final acidBubble2 = (frameCount * 3 + idx * 7) % 17 < 3 ? 20 : 0;
        final acidGlow = acidBubble1 + acidBubble2;
        _inlineR = (25 + variation + acidGlow ~/ 2).clamp(0, 100);
        _inlineG = (245 + variation + acidGlow ~/ 3).clamp(200, 255);
        _inlineB = (25 + variation + acidGlow ~/ 4).clamp(0, 80);
        _inlineA = 255;

      case El.glass:
        final sparkle = (frameCount + idx * 3) % 20 < 2 ? 30 : 0;
        _inlineR = (210 + variation + sparkle).clamp(180, 255);
        _inlineG = (225 + variation + sparkle).clamp(200, 255);
        _inlineB = 255;
        _inlineA = 200;

      case El.lava:
        final lavaLife = life[idx];
        // Multi-frequency lava pulsing for molten look
        final lFlick1 = (frameCount + idx) % 6;
        final lFlick2 = (frameCount * 3 + idx * 5) % 11;
        final lFlick3 = (frameCount + idx * 19) % 23;
        final lavaFlicker = (lFlick1 < 3 ? 18 : 0) + (lFlick2 < 4 ? 12 : 0) + (lFlick3 < 8 ? 8 : 0);
        final isBrightSpot = (idx * 17 + frameCount) % 30 == 0;
        final isSuperBright = (idx * 31 + frameCount * 2) % 80 == 0;
        if ((isBrightSpot || isSuperBright) && lavaLife < 150) {
          final spotB = isSuperBright ? 220 : 180;
          _inlineR = 255; _inlineG = 255; _inlineB = spotB; _inlineA = 255;
        } else if (lavaLife < 40) {
          _inlineR = 255;
          _inlineG = (210 + lavaFlicker ~/ 2).clamp(200, 255);
          _inlineB = (90 + lavaFlicker).clamp(80, 150);
          _inlineA = 255;
        } else if (lavaLife < 120) {
          final t2 = ((lavaLife - 40) * 255 ~/ 80).clamp(0, 255);
          _inlineR = 255;
          _inlineG = (_lerpC(180, 69, t2) + lavaFlicker ~/ 2).clamp(0, 255);
          _inlineB = (lavaFlicker ~/ 2).clamp(0, 40);
          _inlineA = 255;
        } else {
          final t2 = ((lavaLife - 120) * 255 ~/ 80).clamp(0, 255);
          _inlineR = _lerpC(255, 140, t2);
          _inlineG = (_lerpC(69, 30, t2) + lavaFlicker ~/ 3).clamp(0, 100);
          _inlineB = 0;
          _inlineA = 255;
        }

      case El.snow:
        _inlineA = 255;
        final isShadow = (x * 7 + y * 11) % 5 == 0;
        // Multi-frequency sparkle for glittering snow
        final snowSparkle1 = (frameCount + idx * 5) % 15 < 2 ? 12 : 0;
        final snowSparkle2 = (frameCount * 3 + idx * 11) % 23 < 2 ? 8 : 0;
        final snowSparkle = snowSparkle1 + snowSparkle2;
        if (isShadow) {
          _inlineR = (220 + snowSparkle).clamp(215, 245);
          _inlineG = (225 + snowSparkle).clamp(220, 250);
          _inlineB = (240 + snowSparkle ~/ 2).clamp(238, 255);
        } else {
          _inlineR = (240 + snowSparkle).clamp(235, 255);
          _inlineG = (243 + snowSparkle).clamp(238, 255);
          _inlineB = 255;
        }

      case El.wood:
        _inlineA = 255;
        if (life[idx] > 0) {
          final burnPhase = (life[idx] + frameCount) % 6;
          final bright = burnPhase < 3 ? 40 : 0;
          _inlineR = (200 + bright).clamp(180, 255);
          _inlineG = (80 + bright - life[idx]).clamp(20, 120);
          _inlineB = 10;
        } else {
          final grainDark = y % 2 == 0;
          final isKnot = (x * 11 + y * 7) % 17 == 0;
          final waterlog = velY[idx].clamp(0, 3) * 20;
          if (isKnot) {
            _inlineR = (110 - waterlog).clamp(50, 130);
            _inlineG = (55 - waterlog).clamp(25, 75);
            _inlineB = (30 - waterlog).clamp(10, 50);
          } else if (grainDark) {
            _inlineR = (150 - waterlog + variation).clamp(60, 170);
            _inlineG = (76 - waterlog + variation).clamp(30, 100);
            _inlineB = (40 - waterlog + variation).clamp(10, 60);
          } else {
            _inlineR = (168 - waterlog + variation).clamp(70, 185);
            _inlineG = (88 - waterlog + variation).clamp(35, 115);
            _inlineB = (48 - waterlog + variation).clamp(15, 72);
          }
        }

      case El.metal:
        _inlineA = 255;
        if (life[idx] >= 200) {
          life[idx]--;
          if (life[idx] < 200) life[idx] = 0;
          _inlineR = 255; _inlineG = 255; _inlineB = 136;
        } else {
          final rustLevel = life[idx].clamp(0, 120);
          if (rustLevel > 0) {
            final rustFrac = rustLevel / 120.0;
            _inlineR = (168 - rustFrac * 29 + variation).round().clamp(100, 200);
            _inlineG = (168 - rustFrac * 78 + variation).round().clamp(60, 200);
            _inlineB = (176 - rustFrac * 133 + variation).round().clamp(30, 210);
          } else {
            final sheen = (frameCount + idx * 2) % 12 < 2 ? 20 : 0;
            _inlineR = (168 + sheen + variation).clamp(140, 200);
            _inlineG = (168 + sheen + variation).clamp(140, 200);
            _inlineB = (176 + sheen + variation).clamp(150, 210);
          }
        }

      case El.smoke:
        final smokeLife = life[idx];
        final fade = (60 - smokeLife).clamp(0, 60);
        // Wispy smoke animation - brightness varies with time
        final smokeWisp = ((frameCount + idx * 7) % 12 < 4) ? 15 : 0;
        final smokeWave = ((frameCount * 2 + idx * 3) % 18 < 5) ? 8 : 0;
        _inlineA = (fade * 3 + 60).clamp(60, 200);
        // Young smoke is lighter (hot), old smoke is darker
        final smokeBase = smokeLife < 20 ? 150 : (smokeLife < 40 ? 135 : 115);
        _inlineR = (smokeBase + variation + smokeWisp + smokeWave).clamp(90, 180);
        _inlineG = (smokeBase + variation + smokeWisp).clamp(90, 175);
        _inlineB = (smokeBase + variation + smokeWave).clamp(95, 180);

      case El.bubble:
        final bright = (frameCount + idx) % 8 < 3 ? 30 : 0;
        _inlineR = (173 + bright + variation).clamp(150, 220);
        _inlineG = (216 + bright + variation).clamp(190, 255);
        _inlineB = (230 + bright).clamp(210, 255);
        _inlineA = 180;

      case El.ash:
        final v = ((idx % 7) * 3 + variation).clamp(0, 20);
        _inlineR = (176 - v).clamp(150, 200);
        _inlineG = (176 - v).clamp(150, 200);
        _inlineB = (180 - v).clamp(155, 205);
        _inlineA = 220;

      default:
        final c = baseColors[el.clamp(0, baseColors.length - 1)];
        _inlineR = (c.r * 255.0).round();
        _inlineG = (c.g * 255.0).round();
        _inlineB = (c.b * 255.0).round();
        _inlineA = (c.a * 255.0).round();
    }
  }
}
