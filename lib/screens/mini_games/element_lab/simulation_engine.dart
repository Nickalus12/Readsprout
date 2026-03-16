import 'dart:math';
import 'dart:typed_data';

import 'element_registry.dart';

// ---------------------------------------------------------------------------
// SimulationEngine — Core grid data, helpers, and main simulation loop
// ---------------------------------------------------------------------------

/// Data class for explosion events.
class Explosion {
  final int x;
  final int y;
  final int radius;
  const Explosion(this.x, this.y, this.radius);
}

/// Elements that must never settle (have ongoing time-based behaviors).
/// Indexed by element type — non-zero means never settle.
final Uint8List _neverSettle = () {
  final t = Uint8List(32);
  t[El.lava] = 1;     // cools into stone over time
  t[El.fire] = 1;     // burns out over time
  t[El.smoke] = 1;    // fades over time
  t[El.steam] = 1;    // condenses over time
  t[El.bubble] = 1;   // rises through water, pops
  t[El.acid] = 1;     // dissolves over time
  t[El.ash] = 1;      // slow-falling, interacts
  t[El.ant] = 1;      // AI-driven movement
  t[El.plant] = 1;    // grows over time
  t[El.dirt] = 1;     // moisture changes over time
  t[El.wood] = 1;     // burns, waterlogging
  t[El.metal] = 1;    // rusts
  t[El.oil] = 1;      // floats on water
  t[El.mud] = 1;      // viscous flow
  t[El.snow] = 1;     // slow fall, melting, compression
  t[El.rainbow] = 1;  // always rising and cycling
  return t;
}();

class SimulationEngine {
  // -- Grid dimensions -------------------------------------------------------
  int gridW = 160;
  int gridH = 240;

  // -- Grid data (typed arrays for performance) ------------------------------
  late Uint8List grid;    // element type per cell
  late Uint8List life;    // lifetime/state counter per cell
  late Uint8List flags;   // per-cell flags (updated-this-frame, direction, etc.)
  late Int8List velX;     // horizontal velocity (ants, etc.)
  late Int8List velY;     // vertical velocity

  // -- Dirty chunk system (Optimization 1) ------------------------------------
  int chunkCols = 0;
  int chunkRows = 0;
  late Uint8List dirtyChunks;
  late Uint8List nextDirtyChunks;

  // -- Clock bit for double-simulation prevention (Optimization 2) -----------
  bool simClock = false;

  // -- Pheromone grids (dual pheromone system for ant AI) ---------------------
  late Uint8List pheroFood;
  late Uint8List pheroHome;

  // -- Colony tracking -------------------------------------------------------
  int colonyX = -1;
  int colonyY = -1;

  // -- Random instance -------------------------------------------------------
  final Random rng = Random();

  // -- Frame counter ---------------------------------------------------------
  int frameCount = 0;

  // -- Physics manipulation --------------------------------------------------
  int gravityDir = 1; // 1 = down, -1 = up
  int windForce = 0;  // -3..+3

  // -- Explosion queue -------------------------------------------------------
  final List<Explosion> pendingExplosions = [];

  // -- Rainbow color cycling -------------------------------------------------
  int rainbowHue = 0;

  // -- Lightning flash -------------------------------------------------------
  int lightningFlashFrames = 0;

  // -- Day/Night system -------------------------------------------------------
  bool isNight = false;

  /// Initialize all grid arrays for the given dimensions.
  void init(int w, int h) {
    gridW = w;
    gridH = h;
    final totalCells = w * h;
    grid = Uint8List(totalCells);
    life = Uint8List(totalCells);
    flags = Uint8List(totalCells);
    velX = Int8List(totalCells);
    velY = Int8List(totalCells);

    // Initialize dirty chunk system (16x16 chunks)
    chunkCols = (w + 15) ~/ 16;
    chunkRows = (h + 15) ~/ 16;
    final totalChunks = chunkCols * chunkRows;
    dirtyChunks = Uint8List(totalChunks);
    nextDirtyChunks = Uint8List(totalChunks);
    // Mark all chunks dirty on first frame
    dirtyChunks.fillRange(0, totalChunks, 1);

    // Initialize pheromone grids for ant AI
    pheroFood = Uint8List(totalCells);
    pheroHome = Uint8List(totalCells);
    colonyX = -1;
    colonyY = -1;
  }

  /// Clear the entire grid and reset all state.
  void clear() {
    grid.fillRange(0, grid.length, El.empty);
    life.fillRange(0, life.length, 0);
    flags.fillRange(0, flags.length, 0);
    velX.fillRange(0, velX.length, 0);
    velY.fillRange(0, velY.length, 0);
    pheroFood.fillRange(0, pheroFood.length, 0);
    pheroHome.fillRange(0, pheroHome.length, 0);
    colonyX = -1;
    colonyY = -1;
    markAllDirty();
  }

  /// Capture a snapshot for undo (includes velX/velY for ant state fidelity).
  Map<String, dynamic> captureSnapshot() {
    return {
      'grid': Uint8List.fromList(grid),
      'life': Uint8List.fromList(life),
      'velX': Int8List.fromList(velX),
      'velY': Int8List.fromList(velY),
    };
  }

  /// Restore from an undo snapshot (supports both old and new snapshot formats).
  void restoreSnapshot(Map<String, dynamic> snapshot) {
    grid.setAll(0, snapshot['grid'] as Uint8List);
    life.setAll(0, snapshot['life'] as Uint8List);
    final savedVelX = snapshot['velX'];
    final savedVelY = snapshot['velY'];
    if (savedVelX is Int8List) {
      velX.setAll(0, savedVelX);
    } else {
      velX.fillRange(0, velX.length, 0);
    }
    if (savedVelY is Int8List) {
      velY.setAll(0, savedVelY);
    } else {
      velY.fillRange(0, velY.length, 0);
    }
    pheroFood.fillRange(0, pheroFood.length, 0);
    pheroHome.fillRange(0, pheroHome.length, 0);
    colonyX = -1;
    colonyY = -1;
    markAllDirty();
  }

  // ── Core helpers ─────────────────────────────────────────────────────────

  @pragma('vm:prefer-inline')
  void swap(int a, int b) {
    final tmpEl = grid[a];
    final tmpLife = life[a];
    final tmpVx = velX[a];
    final tmpVy = velY[a];

    grid[a] = grid[b];
    life[a] = life[b];
    velX[a] = velX[b];
    velY[a] = velY[b];

    grid[b] = tmpEl;
    life[b] = tmpLife;
    velX[b] = tmpVx;
    velY[b] = tmpVy;

    // Set clock bit to current simClock and clear settled bits for both cells
    final clockBit = simClock ? 0x80 : 0;
    flags[a] = clockBit;
    flags[b] = clockBit;

    // Mark both source and destination chunks dirty
    final w = gridW;
    markDirty(a % w, a ~/ w);
    markDirty(b % w, b ~/ w);
  }

  @pragma('vm:prefer-inline')
  bool inBounds(int x, int y) =>
      x >= 0 && x < gridW && y >= 0 && y < gridH;

  /// Mark the chunk containing (x,y) as dirty for the next frame.
  @pragma('vm:prefer-inline')
  void markDirty(int x, int y) {
    final cx = x >> 4;
    final cy = y >> 4;
    final cols = chunkCols;
    final nd = nextDirtyChunks;
    nd[cy * cols + cx] = 1;
    final lx = x & 15;
    final ly = y & 15;
    if (lx == 0 && cx > 0) nd[cy * cols + cx - 1] = 1;
    if (lx == 15 && cx < cols - 1) nd[cy * cols + cx + 1] = 1;
    final rows = chunkRows;
    if (ly == 0 && cy > 0) nd[(cy - 1) * cols + cx] = 1;
    if (ly == 15 && cy < rows - 1) nd[(cy + 1) * cols + cx] = 1;
    if (lx == 0 && ly == 0 && cx > 0 && cy > 0) nd[(cy - 1) * cols + cx - 1] = 1;
    if (lx == 15 && ly == 0 && cx < cols - 1 && cy > 0) nd[(cy - 1) * cols + cx + 1] = 1;
    if (lx == 0 && ly == 15 && cx > 0 && cy < rows - 1) nd[(cy + 1) * cols + cx - 1] = 1;
    if (lx == 15 && ly == 15 && cx < cols - 1 && cy < rows - 1) nd[(cy + 1) * cols + cx + 1] = 1;
  }

  /// Mark all chunks dirty (used on reset, clear, undo, etc.)
  void markAllDirty() {
    dirtyChunks.fillRange(0, dirtyChunks.length, 1);
    nextDirtyChunks.fillRange(0, nextDirtyChunks.length, 1);
  }

  /// Mark a cell as processed this frame.
  @pragma('vm:prefer-inline')
  void markProcessed(int idx) {
    flags[idx] = simClock ? 0x80 : 0;
    final w = gridW;
    markDirty(idx % w, idx ~/ w);
  }

  /// Clear settled flag on all 8 neighbors.
  @pragma('vm:prefer-inline')
  void unsettleNeighbors(int x, int y) {
    final w = gridW;
    final maxX = w - 1;
    final maxY = gridH - 1;
    if (y > 0) {
      final rowAbove = (y - 1) * w;
      if (x > 0)    flags[rowAbove + x - 1] &= 0x80;
                     flags[rowAbove + x]     &= 0x80;
      if (x < maxX) flags[rowAbove + x + 1] &= 0x80;
    }
    if (x > 0)    flags[y * w + x - 1] &= 0x80;
    if (x < maxX) flags[y * w + x + 1] &= 0x80;
    if (y < maxY) {
      final rowBelow = (y + 1) * w;
      if (x > 0)    flags[rowBelow + x - 1] &= 0x80;
                     flags[rowBelow + x]     &= 0x80;
      if (x < maxX) flags[rowBelow + x + 1] &= 0x80;
    }
  }

  /// Optimized 8-neighbor check. Unrolled for performance.
  @pragma('vm:prefer-inline')
  bool checkAdjacent(int x, int y, int elType) {
    final w = gridW;
    final g = grid;
    final maxX = w - 1;
    final maxY = gridH - 1;
    if (y > 0) {
      final rowAbove = (y - 1) * w;
      if (x > 0    && g[rowAbove + x - 1] == elType) return true;
                       if (g[rowAbove + x]     == elType) return true;
      if (x < maxX && g[rowAbove + x + 1] == elType) return true;
    }
    if (x > 0    && g[y * w + x - 1] == elType) return true;
    if (x < maxX && g[y * w + x + 1] == elType) return true;
    if (y < maxY) {
      final rowBelow = (y + 1) * w;
      if (x > 0    && g[rowBelow + x - 1] == elType) return true;
                       if (g[rowBelow + x]     == elType) return true;
      if (x < maxX && g[rowBelow + x + 1] == elType) return true;
    }
    return false;
  }

  void removeOneAdjacent(int x, int y, int elType) {
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (inBounds(nx, ny)) {
          final ni = ny * gridW + nx;
          if (grid[ni] == elType) {
            grid[ni] = El.empty;
            life[ni] = 0;
            markProcessed(ni);
            return;
          }
        }
      }
    }
  }

  void processExplosions() {
    if (pendingExplosions.isEmpty) return;
    for (final exp in pendingExplosions) {
      final r = exp.radius;
      for (int dy = -r; dy <= r; dy++) {
        for (int dx = -r; dx <= r; dx++) {
          if (dx * dx + dy * dy > r * r) continue;
          final nx = exp.x + dx;
          final ny = exp.y + dy;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] != El.stone && grid[ni] != El.glass && grid[ni] != El.metal) {
            grid[ni] = El.empty;
            life[ni] = 0;
            markDirty(nx, ny);
          }
        }
      }
      // Create some fire around the edges
      for (int i = 0; i < r * 4; i++) {
        final angle = rng.nextDouble() * 2 * pi;
        final dist = r * 0.6 + rng.nextDouble() * r * 0.5;
        final fx = exp.x + (cos(angle) * dist).round();
        final fy = exp.y + (sin(angle) * dist).round();
        if (inBounds(fx, fy)) {
          final fi = fy * gridW + fx;
          if (grid[fi] == El.empty) {
            grid[fi] = El.fire;
            life[fi] = 0;
            markDirty(fx, fy);
          }
        }
      }
    }
    pendingExplosions.clear();
  }

  void fallGranular(int x, int y, int idx, int elType) {
    final by = y + gravityDir;
    if (inBounds(x, by)) {
      final below = by * gridW + x;
      final belowEl = grid[below];
      if (belowEl == El.empty) {
        swap(idx, below);
        return;
      }
      // Sink through water
      if ((elType == El.sand || elType == El.dirt || elType == El.seed) && belowEl == El.water) {
        final sinkWaterMass = life[below];
        grid[idx] = El.water;
        life[idx] = sinkWaterMass < 20 ? 100 : sinkWaterMass;
        grid[below] = elType;
        markProcessed(idx);
        markProcessed(below);
        return;
      }
    }

    final goLeft = rng.nextBool();
    final x1 = goLeft ? x - 1 : x + 1;
    final x2 = goLeft ? x + 1 : x - 1;
    if (inBounds(x, by)) {
      if (inBounds(x1, by) &&
          grid[by * gridW + x1] == El.empty) {
        swap(idx, by * gridW + x1);
        return;
      }
      if (inBounds(x2, by) &&
          grid[by * gridW + x2] == El.empty) {
        swap(idx, by * gridW + x2);
        return;
      }
    }
  }

  /// Check if a water cell is trapped (surrounded, 0-1 water neighbors, no empty).
  bool isTrappedWater(int wx, int wy) {
    int waterN = 0, emptyN = 0;
    for (int dy2 = -1; dy2 <= 1; dy2++) {
      for (int dx2 = -1; dx2 <= 1; dx2++) {
        if (dx2 == 0 && dy2 == 0) continue;
        final nx = wx + dx2;
        final ny = wy + dy2;
        if (!inBounds(nx, ny)) continue;
        final n = grid[ny * gridW + nx];
        if (n == El.water) waterN++;
        if (n == El.empty) emptyN++;
      }
    }
    return emptyN == 0 && waterN <= 1;
  }

  /// Push a water cell to the nearest empty cell above or beside.
  void displaceWater(int wx, int wy) {
    final wi = wy * gridW + wx;
    final preservedMass = life[wi];
    for (int r = 1; r <= 10; r++) {
      final uy = wy - gravityDir * r;
      if (inBounds(wx, uy) && grid[uy * gridW + wx] == El.empty) {
        grid[uy * gridW + wx] = El.water;
        life[uy * gridW + wx] = preservedMass;
        markProcessed(uy * gridW + wx);
        grid[wi] = El.empty;
        life[wi] = 0;
        markProcessed(wi);
        return;
      }
      for (final dx in [r, -r]) {
        final nx = wx + dx;
        if (inBounds(nx, wy) && grid[wy * gridW + nx] == El.empty) {
          grid[wy * gridW + nx] = El.water;
          life[wy * gridW + nx] = preservedMass;
          markProcessed(wy * gridW + nx);
          grid[wi] = El.empty;
          life[wi] = 0;
          markProcessed(wi);
          return;
        }
        final uy2 = wy - gravityDir * r;
        if (inBounds(nx, uy2) && grid[uy2 * gridW + nx] == El.empty) {
          grid[uy2 * gridW + nx] = El.water;
          life[uy2 * gridW + nx] = preservedMass;
          markProcessed(uy2 * gridW + nx);
          grid[wi] = El.empty;
          life[wi] = 0;
          markProcessed(wi);
          return;
        }
      }
    }
  }

  /// Granular fall with water displacement (dirt pushes water up, not absorbs).
  void fallGranularDisplace(int x, int y, int idx, int elType) {
    final by = y + gravityDir;
    if (inBounds(x, by)) {
      final below = by * gridW + x;
      final belowEl = grid[below];
      if (belowEl == El.empty) {
        swap(idx, below);
        return;
      }
      if (belowEl == El.water) {
        if (isTrappedWater(x, by)) {
          grid[below] = elType;
          life[below] = (life[idx] + 1).clamp(0, 5);
          velY[below] = velY[idx];
          grid[idx] = El.empty;
          life[idx] = 0;
          velY[idx] = 0;
          markProcessed(idx);
          markProcessed(below);
        } else {
          displaceWater(x, by);
          if (grid[below] == El.empty) {
            grid[below] = elType;
            life[below] = life[idx];
            velY[below] = velY[idx];
            grid[idx] = El.empty;
            life[idx] = 0;
            velY[idx] = 0;
            markProcessed(idx);
            markProcessed(below);
          } else {
            grid[idx] = El.water;
            grid[below] = elType;
            life[below] = life[idx];
            life[idx] = 100;
            markProcessed(idx);
            markProcessed(below);
          }
        }
        return;
      }
    }
    final goLeft = rng.nextBool();
    final x1 = goLeft ? x - 1 : x + 1;
    final x2 = goLeft ? x + 1 : x - 1;
    if (inBounds(x, by)) {
      if (inBounds(x1, by) && grid[by * gridW + x1] == El.empty) {
        swap(idx, by * gridW + x1);
        return;
      }
      if (inBounds(x2, by) && grid[by * gridW + x2] == El.empty) {
        swap(idx, by * gridW + x2);
        return;
      }
    }
  }

  // ── Wind application ─────────────────────────────────────────────────────

  void applyWind() {
    if (windForce == 0) return;
    final absWind = windForce.abs();
    final dir = windForce > 0 ? 1 : -1;
    final w = gridW;
    final g = grid;

    final ashThresh = (absWind * 25).clamp(0, 100);
    final lightThresh = (absWind * 10).clamp(0, 100);
    final heavyThresh = (absWind * 3).clamp(0, 100);

    for (int y = 0; y < gridH; y++) {
      final startX = dir > 0 ? w - 1 : 0;
      final endX = dir > 0 ? -1 : w;
      final step = dir > 0 ? -1 : 1;
      final rowOff = y * w;
      for (int x = startX; x != endX; x += step) {
        final el = g[rowOff + x];
        if (el == El.empty) continue;
        final sens = el < 32 ? windSensitivity[el] : 0;
        if (sens == 0) continue;

        final thresh = sens == 3 ? ashThresh : (sens == 2 ? lightThresh : heavyThresh);
        if (rng.nextInt(100) < thresh) {
          final nx = x + dir;
          if (nx >= 0 && nx < w && g[rowOff + nx] == El.empty) {
            swap(rowOff + x, rowOff + nx);
          }
        }
      }
    }
  }

  // ── Shake ────────────────────────────────────────────────────────────────

  void doShake() {
    markAllDirty();
    for (int y = gridH - 1; y >= 0; y--) {
      for (int x = 0; x < gridW; x++) {
        final idx = y * gridW + x;
        final el = grid[idx];
        if (el == El.empty || staticElements.contains(el)) continue;
        if (rng.nextInt(100) < 30) {
          final dx = rng.nextInt(3) - 1;
          final dy = rng.nextInt(3) - 1;
          final nx = x + dx;
          final ny = y + dy;
          if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.empty) {
            swap(idx, ny * gridW + nx);
          }
        }
      }
    }
  }

  // ── Plant data encoding ─────────────────────────────────────────────────

  @pragma('vm:prefer-inline')
  int plantType(int idx) => velX[idx] & 0x0F;

  @pragma('vm:prefer-inline')
  int plantStage(int idx) => (velX[idx] >> 4) & 0x0F;

  @pragma('vm:prefer-inline')
  void setPlantData(int idx, int t, int s) => velX[idx] = ((s & 0xF) << 4) | (t & 0xF);

  // ── TNT radius calculation ──────────────────────────────────────────────

  int calculateTNTRadius(int cx, int cy) {
    int count = 0;
    final visited = <int>{};
    final queue = <int>[cy * gridW + cx];
    while (queue.isNotEmpty && count < 50) {
      final curIdx = queue.removeLast();
      if (visited.contains(curIdx)) continue;
      visited.add(curIdx);
      if (grid[curIdx] != El.tnt) continue;
      count++;
      final qx = curIdx % gridW;
      final qy = curIdx ~/ gridW;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = qx + dx;
          final ny = qy + dy;
          if (inBounds(nx, ny)) queue.add(ny * gridW + nx);
        }
      }
    }
    return (6 + (count - 1) * 2).clamp(6, 30);
  }

  // ── Electrical conduction ───────────────────────────────────────────────

  /// Flood-fill connected water body and electrify all cells.
  void electrifyWater(int startX, int startY) {
    final visited = <int>{};
    final queue = <int>[startY * gridW + startX];
    int count = 0;
    while (queue.isNotEmpty && count < 50) {
      final curIdx = queue.removeLast();
      if (visited.contains(curIdx)) continue;
      visited.add(curIdx);
      if (grid[curIdx] != El.water) continue;
      life[curIdx] = 200;
      markProcessed(curIdx);
      count++;
      final cx = curIdx % gridW;
      final cy = curIdx ~/ gridW;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] == El.water && !visited.contains(ni)) {
            queue.add(ni);
          } else if (grid[ni] == El.ant || grid[ni] == El.plant || grid[ni] == El.seed) {
            grid[ni] = El.empty;
            life[ni] = 0;
            markProcessed(ni);
          }
        }
      }
    }
    lightningFlashFrames = 5;
  }

  /// Flood-fill connected metal and electrify neighbors.
  void conductMetal(int startX, int startY) {
    final visited = <int>{};
    final queue = <int>[startY * gridW + startX];
    int sparks = 0;
    while (queue.isNotEmpty && sparks < 30) {
      final curIdx = queue.removeLast();
      if (visited.contains(curIdx)) continue;
      visited.add(curIdx);
      if (grid[curIdx] != El.metal) continue;
      life[curIdx] = 200;
      final cx = curIdx % gridW;
      final cy = curIdx ~/ gridW;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = cx + dx;
          final ny = cy + dy;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] == El.metal && !visited.contains(ni)) {
            queue.add(ni);
          } else if (grid[ni] == El.water) {
            life[ni] = 200;
            markProcessed(ni);
            sparks++;
          } else if (grid[ni] == El.tnt) {
            pendingExplosions.add(Explosion(nx, ny, calculateTNTRadius(nx, ny)));
            sparks++;
          } else if (rng.nextInt(100) < 30) {
            if (grid[ni] == El.sand) {
              grid[ni] = El.glass;
              life[ni] = 0;
              markProcessed(ni);
              sparks++;
            } else if (grid[ni] == El.ice) {
              grid[ni] = El.water;
              life[ni] = 150;
              markProcessed(ni);
              sparks++;
            } else if (grid[ni] == El.plant || grid[ni] == El.seed ||
                       grid[ni] == El.oil || grid[ni] == El.wood) {
              grid[ni] = El.fire;
              life[ni] = 0;
              markProcessed(ni);
              sparks++;
            }
          }
        }
      }
    }
    lightningFlashFrames = 3;
  }

  // ── AI Sensing API ─────────────────────────────────────────────────────
  // General-purpose spatial queries for entity AI (ants, future creatures).
  // Designed for zero-allocation hot paths — no Maps or Lists allocated
  // (except scanLine which returns a list by design).
  //
  // Extension point: future AI entities can use these sensing methods by
  // calling them from their behavior function passed to step(). The
  // simulateElement callback already receives the engine instance, so any
  // new entity type just needs a case in the dispatch switch and can call
  // engine.senseDanger(), engine.countNearby(), etc. No registration
  // system needed — the switch/case dispatch + sensing API is sufficient.

  /// Returns OR'd category bitmask of all elements within [radius] of (x,y).
  /// Does not allocate. O(radius^2) scan.
  @pragma('vm:prefer-inline')
  int senseCategories(int x, int y, int radius) {
    int result = 0;
    final g = grid;
    final w = gridW;
    final h = gridH;
    final cat = elCategory;
    const maxEl = El.count;
    final x0 = (x - radius).clamp(0, w - 1);
    final x1 = (x + radius).clamp(0, w - 1);
    final y0 = (y - radius).clamp(0, h - 1);
    final y1 = (y + radius).clamp(0, h - 1);
    final r2 = radius * radius;
    for (int sy = y0; sy <= y1; sy++) {
      final dy = sy - y;
      final dy2 = dy * dy;
      final rowOff = sy * w;
      for (int sx = x0; sx <= x1; sx++) {
        final dx = sx - x;
        if (dx * dx + dy2 > r2) continue;
        final el = g[rowOff + sx];
        if (el > 0 && el < maxEl) {
          result |= cat[el];
        }
      }
    }
    return result;
  }

  /// Fast danger check: returns true if any element with catDanger is within
  /// [radius] of (x,y). Short-circuits on first hit.
  @pragma('vm:prefer-inline')
  bool senseDanger(int x, int y, int radius) {
    final g = grid;
    final w = gridW;
    final h = gridH;
    final cat = elCategory;
    const maxEl = El.count;
    final x0 = (x - radius).clamp(0, w - 1);
    final x1 = (x + radius).clamp(0, w - 1);
    final y0 = (y - radius).clamp(0, h - 1);
    final y1 = (y + radius).clamp(0, h - 1);
    final r2 = radius * radius;
    for (int sy = y0; sy <= y1; sy++) {
      final dy = sy - y;
      final dy2 = dy * dy;
      final rowOff = sy * w;
      for (int sx = x0; sx <= x1; sx++) {
        final dx = sx - x;
        if (dx * dx + dy2 > r2) continue;
        final el = g[rowOff + sx];
        if (el > 0 && el < maxEl && (cat[el] & ElCat.danger) != 0) {
          return true;
        }
      }
    }
    return false;
  }

  /// Count occurrences of [elementType] within [radius] of (x,y).
  @pragma('vm:prefer-inline')
  int countNearby(int x, int y, int radius, int elementType) {
    int count = 0;
    final g = grid;
    final w = gridW;
    final h = gridH;
    final x0 = (x - radius).clamp(0, w - 1);
    final x1 = (x + radius).clamp(0, w - 1);
    final y0 = (y - radius).clamp(0, h - 1);
    final y1 = (y + radius).clamp(0, h - 1);
    final r2 = radius * radius;
    for (int sy = y0; sy <= y1; sy++) {
      final dy = sy - y;
      final dy2 = dy * dy;
      final rowOff = sy * w;
      for (int sx = x0; sx <= x1; sx++) {
        final dx = sx - x;
        if (dx * dx + dy2 > r2) continue;
        if (g[rowOff + sx] == elementType) count++;
      }
    }
    return count;
  }

  /// Count elements matching [categoryMask] within [radius] of (x,y).
  @pragma('vm:prefer-inline')
  int countNearbyByCategory(int x, int y, int radius, int categoryMask) {
    int count = 0;
    final g = grid;
    final w = gridW;
    final h = gridH;
    final cat = elCategory;
    const maxEl = El.count;
    final x0 = (x - radius).clamp(0, w - 1);
    final x1 = (x + radius).clamp(0, w - 1);
    final y0 = (y - radius).clamp(0, h - 1);
    final y1 = (y + radius).clamp(0, h - 1);
    final r2 = radius * radius;
    for (int sy = y0; sy <= y1; sy++) {
      final dy = sy - y;
      final dy2 = dy * dy;
      final rowOff = sy * w;
      for (int sx = x0; sx <= x1; sx++) {
        final dx = sx - x;
        if (dx * dx + dy2 > r2) continue;
        final el = g[rowOff + sx];
        if (el > 0 && el < maxEl && (cat[el] & categoryMask) != 0) {
          count++;
        }
      }
    }
    return count;
  }

  /// Find direction toward nearest element matching [categoryMask] within
  /// [radius]. Returns encoded value: (dx + 1) * 3 + (dy + 1), where
  /// dx,dy are each in {-1, 0, 1}. Returns -1 if nothing found.
  /// Caller decodes: dx = (result ~/ 3) - 1, dy = (result % 3) - 1.
  int findNearestDirection(int x, int y, int radius, int categoryMask) {
    final g = grid;
    final w = gridW;
    final h = gridH;
    final cat = elCategory;
    const maxEl = El.count;
    int bestDist = radius * radius + 1;
    int bestDx = 0;
    int bestDy = 0;
    bool found = false;
    final x0 = (x - radius).clamp(0, w - 1);
    final x1 = (x + radius).clamp(0, w - 1);
    final y0 = (y - radius).clamp(0, h - 1);
    final y1 = (y + radius).clamp(0, h - 1);
    final r2 = radius * radius;
    for (int sy = y0; sy <= y1; sy++) {
      final dy = sy - y;
      final dy2 = dy * dy;
      final rowOff = sy * w;
      for (int sx = x0; sx <= x1; sx++) {
        final dx = sx - x;
        final d2 = dx * dx + dy2;
        if (d2 > r2 || d2 == 0) continue;
        if (d2 >= bestDist) continue;
        final el = g[rowOff + sx];
        if (el > 0 && el < maxEl && (cat[el] & categoryMask) != 0) {
          bestDist = d2;
          bestDx = dx;
          bestDy = dy;
          found = true;
        }
      }
    }
    if (!found) return -1;
    // Normalize to {-1, 0, 1}
    final ndx = bestDx == 0 ? 0 : (bestDx > 0 ? 1 : -1);
    final ndy = bestDy == 0 ? 0 : (bestDy > 0 ? 1 : -1);
    return (ndx + 1) * 3 + (ndy + 1);
  }

  /// Scan along direction (dx,dy) from (x,y) for [distance] steps.
  /// Returns list of element types encountered (empty cells included).
  List<int> scanLine(int x, int y, int dx, int dy, int distance) {
    final result = <int>[];
    final g = grid;
    final w = gridW;
    final h = gridH;
    int cx = x + dx;
    int cy = y + dy;
    for (int i = 0; i < distance; i++) {
      if (cx < 0 || cx >= w || cy < 0 || cy >= h) break;
      result.add(g[cy * w + cx]);
      cx += dx;
      cy += dy;
    }
    return result;
  }

  // ── Main simulation step ─────────────────────────────────────────────────

  /// Run one frame of physics simulation. Element behaviors are dispatched
  /// via the provided callback.
  void step(void Function(SimulationEngine engine, int el, int x, int y, int idx) simulateElement) {
    // Toggle simulation clock
    simClock = !simClock;
    final currentClockBit = simClock ? 0x80 : 0;

    // Process pending explosions
    processExplosions();

    // Advance rainbow hue
    rainbowHue = (rainbowHue + 3) % 360;

    // Decrease lightning flash
    if (lightningFlashFrames > 0) lightningFlashFrames--;

    // Cache dirty chunks for read, nextDirty for write
    final dc = dirtyChunks;
    final cols = chunkCols;
    final w = gridW;

    // Scan from gravity-bottom to top, left-right alternating
    final leftToRight = frameCount.isEven;
    final yStart = gravityDir == 1 ? gridH - 2 : 1;
    final yEnd = gravityDir == 1 ? -1 : gridH;
    final yStep = gravityDir == 1 ? -1 : 1;
    for (int y = yStart; y != yEnd; y += yStep) {
      final chunkY = y >> 4;
      final startX = leftToRight ? 0 : gridW - 1;
      final endX = leftToRight ? gridW : -1;
      final dx = leftToRight ? 1 : -1;
      for (int x = startX; x != endX; x += dx) {
        final chunkIdx = chunkY * cols + (x >> 4);
        if (dc[chunkIdx] == 0) continue;

        final idx = y * w + x;

        final flagVal = flags[idx];
        if ((flagVal & 0x80) == currentClockBit) continue;

        final el = grid[idx];
        if (el == El.empty) continue;

        // Elements with ongoing behaviors (cooling, rising, flowing) must
        // never be settled — force them to always simulate.
        if ((flagVal & 0x40) != 0) {
          if (_neverSettle[el] != 0) {
            // Unsettle: clear bits 4-6 so this cell re-enters simulation
            flags[idx] = flagVal & 0x80;
          } else {
            continue;
          }
        }

        final preEl = el;
        final preIdx = idx;
        final preLife = life[idx];

        // Dispatch to element behavior
        simulateElement(this, el, x, y, idx);

        // Static cell detection — also check if life changed (e.g. lava
        // cooling, dirt moisture, bubble rising) to prevent premature settling
        if (grid[preIdx] == preEl && (flags[preIdx] & 0x80) != currentClockBit) {
          if (life[preIdx] != preLife) {
            // Life changed without moving — reset stable counter, don't settle
            flags[preIdx] = flags[preIdx] & 0x80;
            markDirty(x, y);
          } else {
            final oldStable = (flagVal >> 4) & 0x03;
            final newStable = (oldStable + 1).clamp(0, 3);
            if (newStable >= 3) {
              flags[preIdx] = (flags[preIdx] & 0x80) | 0x70;
            } else {
              flags[preIdx] = (flags[preIdx] & 0x80) | (newStable << 4);
            }
            markDirty(x, y);
          }
        } else if (grid[preIdx] != preEl) {
          markDirty(x, y);
          unsettleNeighbors(x, y);
        }
      }
    }

    // Swap dirty chunk buffers for next frame
    final tmp = dirtyChunks;
    dirtyChunks = nextDirtyChunks;
    nextDirtyChunks = tmp;
    nextDirtyChunks.fillRange(0, nextDirtyChunks.length, 0);
  }
}
