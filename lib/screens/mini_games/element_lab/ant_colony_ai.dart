import 'dart:typed_data';

import 'element_registry.dart';
import 'simulation_engine.dart';

// ---------------------------------------------------------------------------
// Ant Colony AI — Ant behavior, pheromone system, colony tracking
// Uses the general-purpose AI sensing API for element awareness.
// ---------------------------------------------------------------------------

/// Ant bridge state encoded in flags: bit 0x01 = bridge ant, bit 0x02 = alarmed.
const int _antBridgeFlag = 0x01;
const int _antAlarmFlag = 0x02;

extension AntColonyAI on SimulationEngine {

  // ── Pheromone system ──────────────────────────────────────────────────────

  /// Evaporate both pheromone grids — decay each cell by 1 (called every 8 frames).
  void evaporatePheromones() {
    final total = gridW * gridH;
    final pf = pheroFood;
    final ph = pheroHome;
    for (int i = 0; i < total; i++) {
      if (pf[i] > 0) pf[i] = pf[i] - 1;
      if (ph[i] > 0) ph[i] = ph[i] - 1;
    }
  }

  /// Diffuse pheromones to cardinal neighbors — restricted to dirty chunks.
  void diffusePheromones() {
    final w = gridW;
    final h = gridH;
    final g = grid;
    final pf = pheroFood;
    final ph = pheroHome;
    final dc = dirtyChunks;
    final cols = chunkCols;
    final rows = chunkRows;

    for (int cy = 0; cy < rows; cy++) {
      final chunkRowBase = cy * cols;
      final yStart = (cy * 16).clamp(1, h - 1);
      final yEnd = ((cy + 1) * 16).clamp(1, h - 1);

      for (int cx = 0; cx < cols; cx++) {
        if (dc[chunkRowBase + cx] == 0) continue;

        final xStart = (cx * 16).clamp(1, w - 1);
        final xEnd = ((cx + 1) * 16).clamp(1, w - 1);

        for (int y = yStart; y < yEnd; y++) {
          final row = y * w;
          for (int x = xStart; x < xEnd; x++) {
            final i = row + x;
            final fv = pf[i];
            if (fv > 2) {
              final spread = fv >> 3;
              if (spread > 0) {
                if (g[i - 1] == El.empty) pf[i - 1] = (pf[i - 1] + spread).clamp(0, 255);
                if (g[i + 1] == El.empty) pf[i + 1] = (pf[i + 1] + spread).clamp(0, 255);
                if (g[i - w] == El.empty) pf[i - w] = (pf[i - w] + spread).clamp(0, 255);
                if (g[i + w] == El.empty) pf[i + w] = (pf[i + w] + spread).clamp(0, 255);
              }
            }
            final hv = ph[i];
            if (hv > 2) {
              final spread = hv >> 3;
              if (spread > 0) {
                if (g[i - 1] == El.empty) ph[i - 1] = (ph[i - 1] + spread).clamp(0, 255);
                if (g[i + 1] == El.empty) ph[i + 1] = (ph[i + 1] + spread).clamp(0, 255);
                if (g[i - w] == El.empty) ph[i - w] = (ph[i - w] + spread).clamp(0, 255);
                if (g[i + w] == El.empty) ph[i + w] = (ph[i + w] + spread).clamp(0, 255);
              }
            }
          }
        }
      }
    }
  }

  /// Update colony centroid — only scan dirty chunks for ~60% savings.
  void updateColonyCentroid() {
    int sumX = 0, sumY = 0, count = 0;
    final w = gridW;
    final h = gridH;
    final dc = dirtyChunks;
    final cols = chunkCols;
    final rows = chunkRows;

    for (int cy = 0; cy < rows; cy++) {
      final chunkRowBase = cy * cols;
      final yStart = cy * 16;
      final yEnd = (yStart + 16).clamp(0, h);

      for (int cx = 0; cx < cols; cx++) {
        if (dc[chunkRowBase + cx] == 0) continue;

        final xStart = cx * 16;
        final xEnd = (xStart + 16).clamp(0, w);

        for (int y = yStart; y < yEnd; y++) {
          final rowOff = y * w;
          for (int x = xStart; x < xEnd; x++) {
            if (grid[rowOff + x] == El.ant) {
              sumX += x;
              sumY += y;
              count++;
            }
          }
        }
      }
    }
    if (count > 0) {
      colonyX = sumX ~/ count;
      colonyY = sumY ~/ count;
    }
  }

  // ── Ant helpers ────────────────────────────────────────────────────────────

  /// Check if a cell is "underground" (has solid above it, toward surface).
  bool _isUnderground(int x, int y) {
    final g = gravityDir;
    final aboveY = y - g;
    if (!inBounds(x, aboveY)) return false;
    final above = grid[aboveY * gridW + x];
    return above == El.dirt || above == El.mud || above == El.stone ||
           above == El.sand || above == El.ant;
  }

  /// Choose direction using weighted pheromone sampling.
  int _antPheromoneDir(int x, int y, int dir, Uint8List pheroGrid) {
    final w = gridW;
    if (rng.nextInt(20) == 0) return rng.nextBool() ? 1 : -1;

    final candidates = <int, int>{};
    final fwdX = x + dir;
    if (inBounds(fwdX, y)) {
      final fi = y * w + fwdX;
      candidates[dir] = pheroGrid[fi] + rng.nextInt(10);
    }
    final uy = y - gravityDir;
    if (inBounds(fwdX, uy)) {
      final fi = uy * w + fwdX;
      final score = pheroGrid[fi] + rng.nextInt(10);
      if (!candidates.containsKey(dir) || score > candidates[dir]!) {
        candidates[dir] = score;
      }
    }
    final bwdX = x - dir;
    if (inBounds(bwdX, y)) {
      final fi = y * w + bwdX;
      candidates[-dir] = pheroGrid[fi] + rng.nextInt(10);
    }

    if (candidates.isEmpty) return dir;

    int bestDir = dir;
    int bestScore = -1;
    for (final entry in candidates.entries) {
      if (entry.value > bestScore) {
        bestScore = entry.value;
        bestDir = entry.key;
      }
    }
    return bestScore > 5 ? bestDir : dir;
  }

  /// Trigger fire evacuation alarm: nearby ants flee away from danger.
  void _fireAlarm(int x, int y) {
    final w = gridW;
    for (int dy = -4; dy <= 4; dy++) {
      for (int dx = -4; dx <= 4; dx++) {
        final nx = x + dx, ny = y + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = ny * w + nx;
        if (grid[ni] == El.ant) {
          // Set alarm flag and flee direction (away from danger source)
          final fleeDir = dx >= 0 ? 1 : -1;
          velX[ni] = fleeDir;
          // Force ant into explorer state to trigger movement away
          if (velY[ni] != antDrowningBase && velY[ni] < antDrowningBase) {
            flags[ni] = (flags[ni] & 0xF0) | _antAlarmFlag;
          }
        }
      }
    }
  }

  // ── Main ant simulation ─────────────────────────────────────────────────

  void simAnt(int x, int y, int idx) {
    int state = velY[idx];

    final isCarrying = (state == antCarrierState);
    if (!isCarrying && frameCount % 2 != 0) return;

    final g = gravityDir;
    final by = y + g;
    final uy = y - g;
    final homeX = life[idx];
    final w = gridW;

    // ── Hazard detection using sensing API ──────────────────────────────
    // Use senseDanger() to detect ALL danger elements (fire, lava, acid,
    // lightning, tnt) in one call instead of individual checkAdjacent calls.

    // Acid dissolves ants instantly
    if (checkAdjacent(x, y, El.acid)) {
      grid[idx] = El.empty; life[idx] = 0; velY[idx] = 0;
      return;
    }

    // Fire/lava: flee and trigger alarm cascade
    if (senseDanger(x, y, 1)) {
      // Check for immediate fire/lava contact
      final hasFire = checkAdjacent(x, y, El.fire) || checkAdjacent(x, y, El.lava);
      if (hasFire) {
        // Trigger alarm cascade — nearby ants also flee
        _fireAlarm(x, y);

        // Try to find safe adjacent cell (no danger nearby)
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx2 = x + dx, ny2 = y + dy;
            if (!inBounds(nx2, ny2)) continue;
            if (grid[ny2 * w + nx2] == El.empty && !senseDanger(nx2, ny2, 1)) {
              swap(idx, ny2 * w + nx2);
              return;
            }
          }
        }
        // No safe cell — ant dies
        grid[idx] = El.empty; life[idx] = 0; velY[idx] = 0;
        return;
      }

      // TNT or lightning nearby but not adjacent fire — just flee
      if (flags[idx] & _antAlarmFlag == 0) {
        _fireAlarm(x, y);
      }
    }

    // Alarmed ant: prioritize fleeing for a few frames
    if ((flags[idx] & _antAlarmFlag) != 0) {
      // Clear alarm after fleeing
      flags[idx] = flags[idx] & ~_antAlarmFlag;
      final fleeDir = velX[idx];
      final nx = x + fleeDir;
      if (inBounds(nx, y) && grid[y * w + nx] == El.empty) {
        swap(idx, y * w + nx);
        return;
      }
      if (inBounds(nx, uy) && grid[uy * w + nx] == El.empty) {
        swap(idx, uy * w + nx);
        return;
      }
    }

    // Drowning
    if (checkAdjacent(x, y, El.water)) {
      if (state < antDrowningBase) {
        velY[idx] = antDrowningBase;
        state = antDrowningBase;
      }
      if (inBounds(x, uy) && rng.nextInt(3) == 0) {
        final ac = grid[uy * w + x];
        if (ac == El.empty || ac == El.water) { swap(idx, uy * w + x); return; }
      }
      for (final dir in [1, -1]) {
        final sx = x + dir;
        if (inBounds(sx, y) && grid[y * w + sx] == El.empty) {
          swap(idx, y * w + sx); return;
        }
      }
      velY[idx] = (state + 1);
      if (velY[idx] > 100) {
        grid[idx] = El.empty; life[idx] = 0; velY[idx] = 0;
      }
      return;
    }
    if (state >= antDrowningBase) { velY[idx] = 0; state = 0; }

    // ── Bridge ant: stay still as bridge, release after timeout ─────────
    if ((flags[idx] & _antBridgeFlag) != 0) {
      // Bridge ants hold position; life counter tracks bridge duration
      // They release after 200 frames or if no ants cross in a while
      if (frameCount % 4 == 0) {
        // Check if any ants are walking on top of us
        if (inBounds(x, uy) && grid[uy * w + x] != El.ant) {
          // Increment a decay counter via life bits
          final bridgeAge = (life[idx] >> 4) & 0x0F;
          if (bridgeAge > 8) {
            // Release bridge
            flags[idx] = flags[idx] & ~_antBridgeFlag;
            velY[idx] = antExplorerState;
          } else {
            life[idx] = (life[idx] & 0x0F) | ((bridgeAge + 1) << 4);
          }
        }
      }
      return;
    }

    // Initialize home position
    if (life[idx] == 0) {
      life[idx] = x.clamp(1, 255);
      if (colonyX < 0) { colonyX = x; colonyY = y; }
    }
    if (velX[idx] == 0) velX[idx] = rng.nextBool() ? 1 : -1;

    // Gravity
    if (inBounds(x, by) && grid[by * w + x] == El.empty) {
      swap(idx, by * w + x);
      return;
    }

    // Pheromone deposit
    if (state == antExplorerState || state == antForagerState) {
      if (pheroHome[idx] < 120) pheroHome[idx] = 120;
    }
    if (state == antCarrierState || state == antReturningState) {
      if (pheroFood[idx] < 120) pheroFood[idx] = 120;
    }

    // Colony distance check
    if (colonyX >= 0 && state == antExplorerState) {
      final dist = (x - colonyX).abs() + (y - colonyY).abs();
      if (dist > 60 && rng.nextInt(8) == 0) {
        velY[idx] = antReturningState;
        state = antReturningState;
      }
    }

    // Recruitment
    if (state == antExplorerState && frameCount % 4 == 0) {
      int bestPhero = 0;
      for (int dy = -5; dy <= 5; dy++) {
        for (int dx = -5; dx <= 5; dx++) {
          final nx2 = x + dx, ny2 = y + dy;
          if (!inBounds(nx2, ny2)) continue;
          final ni = ny2 * w + nx2;
          if (pheroFood[ni] > bestPhero) bestPhero = pheroFood[ni];
        }
      }
      if (bestPhero > 100 && rng.nextInt(3) == 0) {
        velY[idx] = antForagerState;
        state = antForagerState;
      }
    }

    // State machine
    final underground = _isUnderground(x, y);
    final nearDirt = checkAdjacent(x, y, El.dirt);

    switch (state) {
      case antExplorerState:
        _antExplore(x, y, idx, homeX, nearDirt, underground);
      case antDiggerState:
        _antDig(x, y, idx, underground);
      case antCarrierState:
        _antCarry(x, y, idx, homeX);
      case antReturningState:
        _antReturn(x, y, idx, homeX);
      case antForagerState:
        _antForage(x, y, idx, homeX, nearDirt);
    }
  }

  void _antExplore(int x, int y, int idx, int homeX, bool nearDirt, bool underground) {
    int dir = velX[idx];

    // Sense organic material (food sources: plant, seed, dirt, etc.)
    final nearbyCategories = senseCategories(x, y, 3);

    if (nearDirt && rng.nextInt(4) == 0) {
      final nearbyAnts = countNearby(x, y, 2, El.ant);
      if (nearbyAnts < 5) {
        velY[idx] = antDiggerState;
        return;
      }
    }

    // Attracted to organic food sources (plant, seed)
    if ((nearbyCategories & ElCat.organic) != 0 && rng.nextInt(6) == 0) {
      final organicDir = findNearestDirection(x, y, 5, ElCat.organic);
      if (organicDir >= 0) {
        final odx = (organicDir ~/ 3) - 1;
        if (odx != 0) dir = odx;
      }
    }

    dir = _antPheromoneDir(x, y, dir, pheroFood);

    int targetDir = dir;
    bool foundTarget = false;
    for (int scanD = 1; scanD <= 8; scanD++) {
      for (final sd in [dir, -dir]) {
        final sx = x + sd * scanD;
        if (!inBounds(sx, y)) continue;
        final sc = grid[y * gridW + sx];
        if (sc == El.dirt || sc == El.mud || sc == El.plant || sc == El.seed) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        if (sc == El.ant && rng.nextInt(3) == 0) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        // Use category check for danger avoidance — covers fire, lava, acid,
        // lightning, tnt, and any future danger elements
        if (sc < El.count && (elCategory[sc] & (ElCat.danger | ElCat.liquid)) != 0) {
          // Avoid oil (flammable) and all danger/liquid elements
          if (sc == El.water || sc == El.oil || (elCategory[sc] & ElCat.danger) != 0) {
            if (sd == dir) targetDir = -dir;
            break;
          }
        }
      }
      if (foundTarget) break;
    }

    if (!foundTarget && colonyX >= 0) {
      final dist = (x - colonyX).abs() + (y - colonyY).abs();
      if (dist < 10 && rng.nextInt(3) == 0) {
        targetDir = (x >= colonyX) ? 1 : -1;
      }
    }

    _antMove(x, y, idx, targetDir);
  }

  void _antForage(int x, int y, int idx, int homeX, bool nearDirt) {
    int dir = velX[idx];

    // Check for organic food sources (dirt, plant, seed)
    if (nearDirt || checkAdjacent(x, y, El.plant) || checkAdjacent(x, y, El.seed)) {
      pheroFood[idx] = 200;
      _antRecruitNearby(x, y);
      if (nearDirt) {
        velY[idx] = antDiggerState;
      } else {
        // Harvest plant/seed: pick it up and carry
        velY[idx] = antCarrierState;
      }
      return;
    }

    dir = _antPheromoneDir(x, y, dir, pheroFood);

    int targetDir = dir;
    bool foundTarget = false;
    for (int scanD = 1; scanD <= 12; scanD++) {
      for (final sd in [dir, -dir]) {
        final sx = x + sd * scanD;
        if (!inBounds(sx, y)) continue;
        final sc = grid[y * gridW + sx];
        // Attracted to organic matter (dirt, mud, plant, seed)
        if (sc == El.dirt || sc == El.mud || sc == El.plant || sc == El.seed) {
          targetDir = sd;
          foundTarget = true;
          break;
        }
        // Avoid danger and hazardous liquids
        if (sc < El.count && (elCategory[sc] & ElCat.danger) != 0) {
          if (sd == dir) targetDir = -dir;
          break;
        }
        if (sc == El.water || sc == El.oil) {
          if (sd == dir) targetDir = -dir;
          break;
        }
      }
      if (foundTarget) break;
    }

    if (!foundTarget && rng.nextInt(60) == 0) {
      velY[idx] = antExplorerState;
    }

    _antMove(x, y, idx, targetDir);
  }

  void _antRecruitNearby(int x, int y) {
    final w = gridW;
    for (int dy = -5; dy <= 5; dy++) {
      for (int dx = -5; dx <= 5; dx++) {
        final nx2 = x + dx, ny2 = y + dy;
        if (!inBounds(nx2, ny2)) continue;
        final ni = ny2 * w + nx2;
        if (grid[ni] == El.ant && velY[ni] == antExplorerState) {
          if (rng.nextInt(2) == 0) {
            velY[ni] = antForagerState;
            velX[ni] = dx >= 0 ? 1 : -1;
          }
        }
      }
    }
  }

  void _antDig(int x, int y, int idx, bool underground) {
    final g = gravityDir;
    final by = y + g;
    final dir = velX[idx];
    final w = gridW;

    // Dig through sand faster than dirt (sand is looser)
    bool tryDig(int tx, int ty) {
      if (!inBounds(tx, ty)) return false;
      final ti = ty * w + tx;
      final el = grid[ti];
      if (el == El.dirt) {
        if (rng.nextInt(4) == 0) {
          grid[ti] = El.empty;
          life[ti] = 0;
          swap(idx, ti);
          velY[idx] = antCarrierState;
          pheroFood[ti] = 200;
          return true;
        }
      } else if (el == El.sand) {
        // Sand is easier to dig through
        if (rng.nextInt(2) == 0) {
          grid[ti] = El.empty;
          life[ti] = 0;
          swap(idx, ti);
          velY[idx] = antCarrierState;
          pheroFood[ti] = 200;
          return true;
        }
      }
      return false;
    }

    if (tryDig(x, by)) return;
    if (tryDig(x + dir, y)) return;
    if (inBounds(x + dir, by) && rng.nextInt(5) == 0) {
      if (tryDig(x + dir, by)) return;
    }

    if (underground && rng.nextInt(12) == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final cx = x + dx, cy = y + dy;
          if (inBounds(cx, cy) && grid[cy * w + cx] == El.dirt) {
            grid[cy * w + cx] = El.empty;
            life[cy * w + cx] = 0;
            markDirty(cx, cy);
          }
        }
      }
    }

    if (!checkAdjacent(x, y, El.dirt) && !checkAdjacent(x, y, El.sand)) {
      velY[idx] = antExplorerState;
    }

    _antMove(x, y, idx, dir);
  }

  void _antCarry(int x, int y, int idx, int homeX) {
    final g = gravityDir;
    final uy = y - g;
    final w = gridW;

    if (pheroFood[idx] < 80) pheroFood[idx] = 80;

    if (inBounds(x, uy)) {
      final aboveCell = grid[uy * w + x];
      if (aboveCell == El.empty) {
        swap(idx, uy * w + x);
        return;
      }
    }

    final atSurface = !inBounds(x, uy) ||
        (grid[uy * w + x] == El.empty && !_isUnderground(x, y));

    if (atSurface || !inBounds(x, uy)) {
      final depositY = uy;
      final toHome = (homeX - x).sign;

      // Shelter building: deposit sand/snow near colony entrance
      final nearColony = colonyX >= 0 && (x - colonyX).abs() < 8;
      int depositEl = El.dirt;

      // If near colony and sand/snow available nearby, fortify with it
      if (nearColony && rng.nextInt(3) == 0) {
        final sandCount = countNearby(x, y, 3, El.sand);
        final snowCount = countNearby(x, y, 3, El.snow);
        if (sandCount > 2) {
          depositEl = El.sand;
        } else if (snowCount > 2) {
          depositEl = El.snow;
        }
      }

      for (final depositX in [x + toHome, x, x - toHome]) {
        if (inBounds(depositX, depositY) && grid[depositY * w + depositX] == El.empty) {
          grid[depositY * w + depositX] = depositEl;
          life[depositY * w + depositX] = 0;
          markDirty(depositX, depositY);
          velY[idx] = antReturningState;
          return;
        }
      }
      for (final dx in [1, -1]) {
        final sx = x + dx;
        if (inBounds(sx, y) && grid[y * w + sx] == El.empty) {
          grid[y * w + sx] = depositEl;
          life[y * w + sx] = 0;
          markDirty(sx, y);
          velY[idx] = antReturningState;
          return;
        }
      }
      velY[idx] = antExplorerState;
      return;
    }

    final pheroDir = _antPheromoneDir(x, y, velX[idx], pheroHome);
    final toHome = (homeX - x).sign;
    final moveDir = toHome != 0 ? toHome : pheroDir;
    _antMove(x, y, idx, moveDir);
  }

  void _antReturn(int x, int y, int idx, int homeX) {
    final g = gravityDir;
    final by = y + g;
    final w = gridW;

    final toHome = (homeX - x).sign;

    if ((x - homeX).abs() <= 2) {
      if (inBounds(x, by) && grid[by * w + x] == El.empty) {
        swap(idx, by * w + x);
        velY[idx] = antExplorerState;
        return;
      }
      for (final dx in [0, 1, -1, 2, -2]) {
        final tx = x + dx;
        if (inBounds(tx, by) && grid[by * w + tx] == El.empty) {
          if (inBounds(tx, y) && grid[y * w + tx] == El.empty) {
            swap(idx, y * w + tx);
            return;
          }
        }
      }
      velY[idx] = antExplorerState;
      return;
    }

    // Plant farming: if carrying seed and near moist dirt by colony, plant it
    if (colonyX >= 0 && (x - colonyX).abs() < 12) {
      final moistDirtDir = findNearestDirection(x, y, 4, ElCat.organic);
      if (moistDirtDir >= 0 && rng.nextInt(8) == 0) {
        // Check for nearby seed to plant in moist dirt
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (!inBounds(nx, ny)) continue;
            final ni = ny * w + nx;
            if (grid[ni] == El.empty) {
              // Look for dirt below to plant a seed
              final belowY = ny + gravityDir;
              if (inBounds(nx, belowY) && grid[belowY * w + nx] == El.dirt) {
                if (countNearby(nx, ny, 2, El.water) > 0) {
                  grid[ni] = El.seed;
                  life[ni] = 0;
                  markDirty(nx, ny);
                  velY[idx] = antExplorerState;
                  return;
                }
              }
            }
          }
        }
      }
    }

    final pheroDir = _antPheromoneDir(x, y, velX[idx], pheroHome);
    final moveDir = toHome != 0 ? toHome : pheroDir;
    _antMove(x, y, idx, moveDir);
  }

  /// Shared ant movement: walk, climb, bridge over water, reverse.
  void _antMove(int x, int y, int idx, int moveDir) {
    final g = gravityDir;
    final uy = y - g;
    final w = gridW;
    final nx = x + moveDir;

    if (inBounds(nx, y) && grid[y * w + nx] == El.empty) {
      velX[idx] = moveDir;
      swap(idx, y * w + nx);
      return;
    }

    if (inBounds(nx, uy) && grid[uy * w + nx] == El.empty) {
      velX[idx] = moveDir;
      swap(idx, uy * w + nx);
      return;
    }

    // ── Ant bridge over water ──────────────────────────────────────────
    // If path blocked by water, attempt to form a living bridge.
    // An ant becomes a bridge cell that other ants can walk across.
    if (inBounds(nx, y) && grid[y * w + nx] == El.water) {
      // Check: is there land on the other side within 4 cells?
      bool landAhead = false;
      for (int d = 2; d <= 4; d++) {
        final fx = x + moveDir * d;
        if (!inBounds(fx, y)) break;
        final fe = grid[y * w + fx];
        if (fe != El.water && fe != El.empty) { landAhead = true; break; }
        if (fe == El.empty) { landAhead = true; break; }
      }
      if (landAhead && rng.nextInt(3) == 0) {
        // This ant becomes a bridge: swap into the water cell, replacing it
        final wi = y * w + nx;
        grid[wi] = El.ant;
        life[wi] = life[idx];
        velX[wi] = moveDir;
        velY[wi] = antExplorerState;
        flags[wi] = (flags[wi] & 0xF0) | _antBridgeFlag;
        // Original ant stays and continues
        grid[idx] = El.empty;
        life[idx] = 0;
        velX[idx] = 0;
        velY[idx] = 0;
        markProcessed(wi);
        markProcessed(idx);
        return;
      }
    }

    // Walk on top of bridge ants
    if (inBounds(nx, y) && grid[y * w + nx] == El.ant &&
        (flags[y * w + nx] & _antBridgeFlag) != 0) {
      // Try to step onto the bridge ant (walk on top of it)
      if (inBounds(nx, uy) && grid[uy * w + nx] == El.empty) {
        velX[idx] = moveDir;
        swap(idx, uy * w + nx);
        return;
      }
    }

    if (inBounds(x, uy) && grid[uy * w + x] == El.empty) {
      if (!inBounds(nx, y) || grid[y * w + nx] != El.empty) {
        swap(idx, uy * w + x);
        return;
      }
    }

    // Snow slows ants down
    if (inBounds(nx, y) && grid[y * w + nx] == El.snow) {
      if (rng.nextInt(3) == 0) {
        // Push through snow slowly
        velX[idx] = moveDir;
        return; // Skip movement this frame
      }
    }

    velX[idx] = -moveDir;
    if (rng.nextInt(6) == 0) velX[idx] = rng.nextBool() ? 1 : -1;
  }
}
