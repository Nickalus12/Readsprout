import 'element_registry.dart';
import 'simulation_engine.dart';
import 'ant_colony_ai.dart';

// ---------------------------------------------------------------------------
// Element Behaviors — Per-element simulation methods (extension on engine)
// ---------------------------------------------------------------------------

extension ElementBehaviors on SimulationEngine {

  void simSand(int x, int y, int idx) {
    if (checkAdjacent(x, y, El.lightning)) {
      grid[idx] = El.glass;
      life[idx] = 0;
      markProcessed(idx);
      // Bright flash for glass formation
      queueReactionFlash(x, y, 200, 230, 255, 4);
      return;
    }
    if (checkAdjacent(x, y, El.water)) {
      grid[idx] = El.mud;
      removeOneAdjacent(x, y, El.water);
      markProcessed(idx);
      return;
    }
    fallGranular(x, y, idx, El.sand);
    // Angle of repose: sand avalanches off steep piles
    // If sand didn't move (still at same index), check for slope collapse
    if (grid[idx] == El.sand && rng.nextInt(3) == 0) {
      _avalancheGranular(x, y, idx);
    }
  }

  void simWater(int x, int y, int idx) {
    final g = gravityDir;
    final by = y + g;
    final uy = y - g;

    final lifeVal = life[idx];
    final bool isSpecialState = lifeVal >= 140;
    int mass = isSpecialState ? 100 : (lifeVal < 20 ? 100 : lifeVal);
    if (!isSpecialState && lifeVal < 20) {
      life[idx] = 100;
    }

    // Check for adjacent ice -> freeze
    if (rng.nextInt(60) == 0 && checkAdjacent(x, y, El.ice)) {
      grid[idx] = El.ice;
      markProcessed(idx);
      return;
    }

    // Evaporation near heat
    final evapChance = isNight ? 30 : 15;
    if (rng.nextInt(evapChance) == 0) {
      for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!inBounds(nx, ny)) continue;
          final neighbor = grid[ny * gridW + nx];
          if (neighbor == El.fire || neighbor == El.lava) {
            grid[idx] = El.steam;
            life[idx] = 0;
            markProcessed(idx);
            return;
          }
        }
      }
    }

    // Water + Oil: water sinks below oil (oil floats up)
    // Check if there's oil BELOW — if so, water displaces it downward
    if (inBounds(x, by) && grid[by * gridW + x] == El.oil && !((flags[by * gridW + x] & 0x80) == (simClock ? 0x80 : 0))) {
      final bi = by * gridW + x;
      final oilLife = life[bi];
      grid[bi] = El.water;
      life[bi] = mass;
      grid[idx] = El.oil;
      life[idx] = oilLife;
      markProcessed(idx);
      markProcessed(bi);
      return;
    }

    // Water neighbor reactions
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = ny * gridW + nx;
        final neighbor = grid[ni];
        if (neighbor == El.tnt && rng.nextInt(10) == 0) {
          grid[ni] = El.sand;
          life[ni] = 0;
          markProcessed(ni);
        }
        if (neighbor == El.smoke && rng.nextInt(10) == 0) {
          grid[ni] = El.empty;
          life[ni] = 0;
          markProcessed(ni);
        }
        if (neighbor == El.rainbow && rng.nextInt(40) == 0) {
          final rx = x + rng.nextInt(3) - 1;
          final ry = uy;
          if (inBounds(rx, ry) && grid[ry * gridW + rx] == El.empty) {
            grid[ry * gridW + rx] = El.rainbow;
            life[ry * gridW + rx] = 0;
            markProcessed(ry * gridW + rx);
          }
        }
        if (neighbor == El.plant && rng.nextInt(20) == 0) {
          if (life[ni] > 2) life[ni] -= 2;
        }
      }
    }

    // Pressure calculation
    int pressure = 0;
    for (int cy = y + g, depth = 0; depth < 8 && inBounds(x, cy); cy += g, depth++) {
      if (grid[cy * gridW + x] == El.water) {
        pressure += 10;
      } else {
        break;
      }
    }
    int colAbove = 0;
    for (int cy = y - g; inBounds(x, cy) && colAbove < 12; cy -= g) {
      final c = grid[cy * gridW + x];
      if (c == El.water || c == El.oil) {
        colAbove++;
      } else {
        break;
      }
    }
    final totalCol = (pressure ~/ 10) + 1 + colAbove;

    // Pressure-based mass compression
    if (!isSpecialState) {
      final targetMass = (100 + (pressure * 0.5).round()).clamp(20, 139);
      if (mass < targetMass) {
        mass = (mass + 3).clamp(20, 139);
      } else if (mass > targetMass) {
        mass = (mass - 3).clamp(20, 139);
      }
      life[idx] = mass;
    }

    // Bubble generation under high pressure
    if (mass > 130 && rng.nextInt(500) == 0) {
      final bubbleY = y - g;
      if (inBounds(x, bubbleY)) {
        final bubbleIdx = bubbleY * gridW + x;
        if (grid[bubbleIdx] == El.water) {
          grid[bubbleIdx] = El.bubble;
          life[bubbleIdx] = 0;
          markProcessed(bubbleIdx);
        }
      }
    }

    // High pressure pushes sand/dirt sideways (water eroding gaps)
    if (colAbove >= 4 && rng.nextInt(8) == 0) {
      for (final dir in [1, -1]) {
        final nx = x + dir;
        if (!inBounds(nx, y)) continue;
        final ni = y * gridW + nx;
        final neighbor = grid[ni];
        if (neighbor == El.sand || neighbor == El.dirt) {
          // Check if there's space to push the granular material
          final pushX = nx + dir;
          if (inBounds(pushX, y) && grid[y * gridW + pushX] == El.empty) {
            swap(ni, y * gridW + pushX);
            swap(idx, ni);
            return;
          }
        }
      }
    }

    // Pressure-based vertical mass transfer
    if (!isSpecialState && mass > 110 && inBounds(x, uy)) {
      final aboveI = uy * gridW + x;
      if (grid[aboveI] == El.water && life[aboveI] < 140) {
        final aboveMass = life[aboveI] < 20 ? 100 : life[aboveI];
        final diff = mass - aboveMass;
        if (diff > 8) {
          final transfer = (diff ~/ 4).clamp(1, 20);
          mass = (mass - transfer).clamp(20, 139);
          final newAbove = (aboveMass + transfer).clamp(20, 139);
          life[idx] = mass;
          life[aboveI] = newAbove;
        }
      }
    }

    // Fall in gravity direction
    if (inBounds(x, by) && grid[by * gridW + x] == El.empty) {
      velY[idx] = (velY[idx] + 1).clamp(0, 10).toInt();
      swap(idx, by * gridW + x);
      return;
    }

    // Splash with visual particles
    if (velY[idx] >= 3 && inBounds(x, by) && grid[by * gridW + x] != El.empty) {
      // Spawn splash droplet particles
      queueReactionFlash(x, y, 100, 180, 255, (velY[idx] ~/ 2).clamp(2, 4));
      for (int i = 0; i < (velY[idx] ~/ 2).clamp(1, 3); i++) {
        final sx = x + (rng.nextBool() ? 1 : -1) * (1 + rng.nextInt(2));
        final sy = y - g * rng.nextInt(2);
        if (inBounds(sx, sy) && grid[sy * gridW + sx] == El.empty) {
          final splashIdx = sy * gridW + sx;
          grid[splashIdx] = El.water;
          final splashMass = (mass ~/ 2).clamp(20, 139);
          life[splashIdx] = splashMass;
          markProcessed(splashIdx);
          grid[idx] = El.empty;
          life[idx] = 0;
          velY[idx] = 0;
          return;
        }
      }
    }
    velY[idx] = 0;

    // Momentum-based lateral flow
    final momentum = velX[idx];
    final frameBias = rng.nextBool();
    final dl = momentum != 0 ? (momentum > 0) : frameBias;
    final x1 = dl ? x + 1 : x - 1;
    final x2 = dl ? x - 1 : x + 1;

    if (inBounds(x1, by) && grid[by * gridW + x1] == El.empty) {
      velX[idx] = dl ? 1 : -1;
      swap(idx, by * gridW + x1);
      return;
    }
    if (inBounds(x2, by) && grid[by * gridW + x2] == El.empty) {
      velX[idx] = dl ? -1 : 1;
      swap(idx, by * gridW + x2);
      return;
    }

    // Pressure-driven lateral flow
    final flowDist = 2 + (pressure ~/ 15).clamp(0, 5);

    if (!isSpecialState) {
      for (final dir in dl ? [1, -1] : [-1, 1]) {
        final nx = x + dir;
        if (!inBounds(nx, y)) continue;
        final ni = y * gridW + nx;
        if (grid[ni] == El.water && life[ni] < 140) {
          final neighborMass = life[ni] < 20 ? 100 : life[ni];
          final diff = mass - neighborMass;
          if (diff > 5) {
            final transfer = (diff ~/ 3).clamp(1, 20);
            life[idx] = (mass - transfer).clamp(20, 139);
            life[ni] = (neighborMass + transfer).clamp(20, 139);
          }
        }
      }
    }

    for (int d = 1; d <= flowDist; d++) {
      final sx1 = dl ? x + d : x - d;
      final sx2 = dl ? x - d : x + d;
      if (inBounds(sx1, y) && grid[y * gridW + sx1] == El.empty) {
        velX[idx] = dl ? 1 : -1;
        swap(idx, y * gridW + sx1);
        return;
      }
      if (inBounds(sx2, y) && grid[y * gridW + sx2] == El.empty) {
        velX[idx] = dl ? -1 : 1;
        swap(idx, y * gridW + sx2);
        return;
      }
    }

    // Surface leveling
    final aboveEl = inBounds(x, uy) ? grid[uy * gridW + x] : -1;
    if (aboveEl == El.empty || aboveEl == -1) {
      for (final dir in [1, -1]) {
        final nx = x + dir;
        if (!inBounds(nx, y)) continue;
        final nIdx = y * gridW + nx;
        if (grid[nIdx] != El.empty) continue;
        final belowNx = y + g;
        if (!inBounds(nx, belowNx)) continue;
        final belowCell = grid[belowNx * gridW + nx];
        if (belowCell == El.empty) continue;
        int adjCol = 0;
        for (int cy = y + g; inBounds(nx, cy) && adjCol < 12; cy += g) {
          if (grid[cy * gridW + nx] == El.water) {
            adjCol++;
          } else {
            break;
          }
        }
        if (totalCol > adjCol + 1) {
          velX[idx] = dir;
          swap(idx, nIdx);
          return;
        }
      }
      // Extended surface leveling
      for (final dir in [1, -1]) {
        for (int d = 2; d <= 4; d++) {
          final nx = x + dir * d;
          if (!inBounds(nx, y)) continue;
          bool pathClear = true;
          for (int pd = 1; pd < d; pd++) {
            final px = x + dir * pd;
            if (!inBounds(px, y) || grid[y * gridW + px] != El.empty) {
              pathClear = false;
              break;
            }
          }
          if (!pathClear) continue;
          if (grid[y * gridW + nx] != El.empty) continue;
          final belowNx = y + g;
          if (!inBounds(nx, belowNx)) continue;
          if (grid[belowNx * gridW + nx] == El.empty) continue;

          int targetCol = 0;
          for (int cy = y + g; inBounds(nx, cy) && targetCol < 12; cy += g) {
            if (grid[cy * gridW + nx] == El.water) {
              targetCol++;
            } else {
              break;
            }
          }
          if (totalCol > targetCol + 1) {
            velX[idx] = dir;
            swap(idx, y * gridW + nx);
            return;
          }
        }
      }

      // Smooth mass-based surface leveling
      if (!isSpecialState) {
        for (final dir in [1, -1]) {
          for (int d = 1; d <= 4; d++) {
            final nx = x + dir * d;
            if (!inBounds(nx, y)) break;
            final ni = y * gridW + nx;
            if (grid[ni] != El.water) break;
            final naboveY = y - g;
            if (!inBounds(nx, naboveY)) continue;
            if (grid[naboveY * gridW + nx] != El.empty) continue;
            final nlife = life[ni];
            if (nlife >= 140) continue;
            final nMass = nlife < 20 ? 100 : nlife;
            final mDiff = mass - nMass;
            if (mDiff.abs() > 3) {
              final transfer = (mDiff ~/ 3).clamp(-5, 5);
              final newMass = (mass - transfer).clamp(20, 139);
              final newNMass = (nMass + transfer).clamp(20, 139);
              life[idx] = newMass;
              life[ni] = newNMass;
              mass = newMass;
            }
          }
        }
      }
    }

    // Stuck — decay momentum
    if (rng.nextInt(4) == 0) velX[idx] = 0;
  }

  void simFire(int x, int y, int idx) {
    life[idx]++;

    // Check if this fire is near oil — oil fires burn longer and hotter
    final nearOil = checkAdjacent(x, y, El.oil);
    final burnoutLife = nearOil ? 70 + rng.nextInt(50) : 40 + rng.nextInt(40);

    if (life[idx] > burnoutLife) {
      grid[idx] = El.ash;
      life[idx] = 0;
      markProcessed(idx);
      final uy = y - gravityDir;
      if (rng.nextBool() && inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
        grid[uy * gridW + x] = El.smoke;
        life[uy * gridW + x] = 0;
        markProcessed(uy * gridW + x);
      }
      return;
    }

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = ny * gridW + nx;
        final neighbor = grid[ni];
        if (neighbor == El.water) {
          grid[ni] = El.steam;
          life[ni] = 0;
          grid[idx] = El.empty;
          life[idx] = 0;
          markProcessed(ni);
          // Sizzle flash for fire+water
          queueReactionFlash(nx, ny, 200, 200, 240, 3);
          return;
        }
        if ((neighbor == El.plant || neighbor == El.seed) && rng.nextInt(2) == 0) {
          grid[ni] = El.fire;
          life[ni] = 0;
          markProcessed(ni);
        }
        if (neighbor == El.wood && rng.nextInt(4) == 0) {
          grid[ni] = El.fire;
          life[ni] = 0;
          markProcessed(ni);
        }
        if (neighbor == El.oil) {
          grid[ni] = El.fire;
          life[ni] = 0;
          markProcessed(ni);
          // Orange ignition flash
          queueReactionFlash(nx, ny, 255, 180, 50, 3);
          // Oil fire spreads to nearby oil within 2-cell radius
          for (int dy2 = -2; dy2 <= 2; dy2++) {
            for (int dx2 = -2; dx2 <= 2; dx2++) {
              if (dx2 == 0 && dy2 == 0) continue;
              final ox = nx + dx2;
              final oy = ny + dy2;
              if (!inBounds(ox, oy)) continue;
              final oi = oy * gridW + ox;
              if (grid[oi] == El.oil && rng.nextInt(3) == 0) {
                grid[oi] = El.fire;
                life[oi] = 0;
                markProcessed(oi);
              }
            }
          }
        }
        if (neighbor == El.ice) {
          grid[ni] = El.water;
          life[ni] = 150;
          markProcessed(ni);
        }
        if (neighbor == El.tnt) {
          pendingExplosions.add(Explosion(nx, ny, calculateTNTRadius(nx, ny)));
          grid[idx] = El.empty;
          life[idx] = 0;
          return;
        }
      }
    }

    final uy = y - gravityDir;
    if (inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
      swap(idx, uy * gridW + x);
      return;
    }
    final drift = rng.nextInt(3) - 1;
    final driftX = x + drift;
    if (inBounds(driftX, uy) &&
        grid[uy * gridW + driftX] == El.empty) {
      swap(idx, uy * gridW + driftX);
    }
  }

  void simIce(int x, int y, int idx) {
    if (checkAdjacent(x, y, El.fire) || checkAdjacent(x, y, El.lava)) {
      grid[idx] = El.water;
      life[idx] = 150;
      markProcessed(idx);
      return;
    }
    final ambientMeltChance = isNight ? 60 : 20;
    if (rng.nextInt(ambientMeltChance) == 0) {
      int waterCount = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.water) {
            waterCount++;
          }
        }
      }
      if (waterCount >= 3) {
        grid[idx] = El.water;
        life[idx] = 150;
        markProcessed(idx);
      }
    }
  }

  void simLightning(int x, int y, int idx) {
    life[idx]++;
    if (life[idx] > 8) {
      grid[idx] = El.empty;
      life[idx] = 0;
      return;
    }

    lightningFlashFrames = 3;

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = ny * gridW + nx;
        final neighbor = grid[ni];
        if (neighbor == El.tnt) {
          pendingExplosions.add(Explosion(nx, ny, calculateTNTRadius(nx, ny)));
        }
        if (neighbor == El.ice) {
          grid[ni] = El.water;
          life[ni] = 150;
          markProcessed(ni);
        }
        if (neighbor == El.water) {
          electrifyWater(nx, ny);
        }
        if (neighbor == El.sand) {
          grid[ni] = El.glass;
          life[ni] = 0;
          markProcessed(ni);
        }
        if (neighbor == El.metal) {
          conductMetal(nx, ny);
        }
      }
    }

    final dist = 2 + rng.nextInt(3);
    final ndx = rng.nextInt(3) - 1;
    final targetY = y + gravityDir * dist;
    final targetX = x + ndx;
    if (!inBounds(targetX, targetY)) {
      grid[idx] = El.empty;
      life[idx] = 0;
      return;
    }
    final ni = targetY * gridW + targetX;
    if (grid[ni] == El.empty) {
      grid[ni] = El.lightning;
      life[ni] = life[idx];
      markProcessed(ni);
      grid[idx] = El.empty;
      life[idx] = 0;
    }
  }

  void simSeed(int x, int y, int idx) {
    final sType = velX[idx].clamp(1, 5);
    life[idx]++;
    if (checkAdjacent(x, y, El.fire) || checkAdjacent(x, y, El.lava)) {
      grid[idx] = El.ash; life[idx] = 0; velX[idx] = 0; markProcessed(idx); return;
    }
    if (checkAdjacent(x, y, El.acid)) {
      grid[idx] = El.empty; life[idx] = 0; velX[idx] = 0; return;
    }
    final by = y + gravityDir;
    bool onDirt = inBounds(x, by) && grid[by * gridW + x] == El.dirt;
    if (onDirt) {
      final soilM = life[by * gridW + x];
      if (soilM >= plantMinMoist[sType]) {
        if (life[idx] > 30) {
          grid[idx] = El.plant; life[idx] = 50;
          setPlantData(idx, sType, kStSprout); velY[idx] = 1; markProcessed(idx); return;
        }
        return;
      } else if (life[idx] > 60) {
        grid[idx] = El.empty; life[idx] = 0; velX[idx] = 0; return;
      }
    } else {
      bool onSolid = inBounds(x, by) && grid[by * gridW + x] != El.empty;
      if (onSolid) { if (life[idx] > 60) { grid[idx] = El.empty; life[idx] = 0; velX[idx] = 0; return; } return; }
    }
    fallGranular(x, y, idx, El.seed);
  }

  void simDirt(int x, int y, int idx) {
    // Soil moisture: gain from adjacent water
    if (frameCount % 10 == 0 && life[idx] < 5 && checkAdjacent(x, y, El.water)) {
      life[idx]++;
    }

    // Moisture propagation
    if (frameCount % 20 == 0 && life[idx] < 4) {
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx = x + dx2;
          final ny = y + dy2;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] == El.dirt && life[ni] > life[idx] + 1) {
            life[idx]++;
            break;
          }
        }
      }
    }

    // Lose moisture
    if (frameCount % 30 == 0 && life[idx] > 0 && !checkAdjacent(x, y, El.water)) {
      bool nearWetDirt = false;
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx = x + dx2;
          final ny = y + dy2;
          if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.dirt &&
              life[ny * gridW + nx] > life[idx]) {
            nearWetDirt = true;
            break;
          }
        }
        if (nearWetDirt) break;
      }
      if (!nearWetDirt) life[idx]--;
    }

    // Saturated + lots of water -> mud
    if (life[idx] >= 5) {
      int wc = 0;
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          if (inBounds(x + dx2, y + dy2) &&
              grid[(y + dy2) * gridW + (x + dx2)] == El.water) {
            wc++;
          }
        }
      }
      if (wc >= 3) {
        grid[idx] = El.mud;
        life[idx] = 0;
        markProcessed(idx);
        return;
      }
    }

    // Ash fertilizer
    if (rng.nextInt(10) == 0) {
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx = x + dx2;
          final ny = y + dy2;
          if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.ash) {
            final ni = ny * gridW + nx;
            grid[ni] = El.empty;
            life[ni] = 0;
            markProcessed(ni);
            life[idx] = (life[idx] + 1).clamp(0, 5);
            break;
          }
        }
      }
    }

    fallGranularDisplace(x, y, idx, El.dirt);
  }

  void simPlant(int x, int y, int idx) {
    final pType = plantType(idx);
    final pStage = plantStage(idx);
    final hydration = life[idx];

    if (checkAdjacent(x, y, El.fire) || checkAdjacent(x, y, El.lava)) {
      grid[idx] = El.fire; life[idx] = 0; velX[idx] = 0; velY[idx] = 0;
      markProcessed(idx); return;
    }
    if (checkAdjacent(x, y, El.acid) && rng.nextInt(3) == 0) {
      grid[idx] = El.empty; life[idx] = 0; velX[idx] = 0; velY[idx] = 0;
      markProcessed(idx); return;
    }

    if (pStage == kStDead) {
      velY[idx] = (velY[idx] + 1).clamp(0, 127).toInt();
      if (velY[idx] > 120) {
        grid[idx] = El.dirt; life[idx] = 0; velX[idx] = 0; velY[idx] = 0;
        markProcessed(idx);
      }
      return;
    }

    // Hydration
    if (frameCount % 5 == 0) {
      bool hasMoisture = false;
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          final nx = x + dx2; final ny = y + dy2;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] == El.dirt && life[ni] >= plantMinMoist[pType.clamp(1, 5)]) {
            hasMoisture = true; break;
          }
          if (grid[ni] == El.water) { hasMoisture = true; break; }
        }
        if (hasMoisture) break;
      }
      if (hasMoisture) {
        life[idx] = (hydration + 2).clamp(0, 100);
      } else {
        life[idx] = (hydration - 1).clamp(0, 100);
      }
    }

    // Wilting / recovery
    if (life[idx] < 30 && pStage < kStWilting) {
      setPlantData(idx, pType, kStWilting);
    } else if (life[idx] >= 30 && pStage == kStWilting) {
      setPlantData(idx, pType, velY[idx] >= plantMaxH[pType.clamp(1, 5)] ? kStMature : kStGrowing);
    }
    if (life[idx] <= 0 && pStage == kStWilting) {
      setPlantData(idx, pType, kStDead);
      velY[idx] = 0;
      return;
    }

    if (pStage > kStMature) return;

    final maxH = plantMaxH[pType.clamp(1, 5)];
    final curSize = velY[idx].clamp(0, 127).toInt();
    if (curSize >= maxH) {
      if (pStage != kStMature) setPlantData(idx, pType, kStMature);
      return;
    }

    bool fertilized = checkAdjacent(x, y, El.ash);
    int growRate = plantGrowRate[pType.clamp(1, 5)];
    if (isNight && pType != kPlantMushroom) growRate = (growRate * 5);
    if (fertilized) growRate = (growRate * 2) ~/ 3;

    if (frameCount % growRate != 0) return;

    if (pStage == kStSprout) setPlantData(idx, pType, kStGrowing);

    switch (pType) {
      case kPlantGrass:
        _growGrass(x, y, idx, curSize);
      case kPlantFlower:
        _growFlower(x, y, idx, curSize);
      case kPlantTree:
        _growTree(x, y, idx, curSize);
      case kPlantMushroom:
        _growMushroom(x, y, idx, curSize);
      case kPlantVine:
        _growVine(x, y, idx, curSize);
    }
  }

  void _growGrass(int x, int y, int idx, int curSize) {
    if (curSize < 3) {
      final uy = y - gravityDir;
      if (inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
        final ni = uy * gridW + x;
        grid[ni] = El.plant; life[ni] = life[idx];
        setPlantData(ni, kPlantGrass, kStGrowing); velY[ni] = (curSize + 1);
        markProcessed(ni);
        velY[idx] = (curSize + 1);
      }
    }
    if (rng.nextInt(40) == 0) {
      final side = rng.nextBool() ? x - 1 : x + 1;
      final by = y + gravityDir;
      if (inBounds(side, y) && grid[y * gridW + side] == El.empty &&
          inBounds(side, by) && grid[by * gridW + side] == El.dirt) {
        final ni = y * gridW + side;
        grid[ni] = El.plant; life[ni] = life[idx];
        setPlantData(ni, kPlantGrass, kStSprout); velY[ni] = 1;
        markProcessed(ni);
      }
    }
  }

  void _growFlower(int x, int y, int idx, int curSize) {
    if (curSize < 6) {
      final uy = y - gravityDir;
      if (inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
        final ni = uy * gridW + x;
        grid[ni] = El.plant; life[ni] = life[idx];
        final newSize = curSize + 1;
        setPlantData(ni, kPlantFlower, newSize >= 4 ? kStMature : kStGrowing);
        velY[ni] = newSize;
        markProcessed(ni);
        velY[idx] = newSize;
      }
    }
  }

  void _growTree(int x, int y, int idx, int curSize) {
    if (curSize < 15) {
      final uy = y - gravityDir;
      if (inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
        final ni = uy * gridW + x;
        grid[ni] = El.plant; life[ni] = life[idx];
        final newSize = curSize + 1;
        final isTrunk = newSize < 7;
        setPlantData(ni, kPlantTree, isTrunk ? kStGrowing : kStMature);
        velY[ni] = newSize;
        markProcessed(ni);
        velY[idx] = newSize;
      }
      if (curSize >= 6) {
        for (final side in [x - 1, x + 1]) {
          if (rng.nextInt(2) == 0) continue;
          for (final sy in [y, y - gravityDir]) {
            if (inBounds(side, sy) && grid[sy * gridW + side] == El.empty) {
              final ni = sy * gridW + side;
              grid[ni] = El.plant; life[ni] = life[idx];
              setPlantData(ni, kPlantTree, kStMature); velY[ni] = curSize;
              markProcessed(ni);
              break;
            }
          }
        }
        if (curSize >= 10 && rng.nextInt(3) == 0) {
          for (final side in [x - 2, x + 2]) {
            if (inBounds(side, y) && grid[y * gridW + side] == El.empty) {
              final ni = y * gridW + side;
              grid[ni] = El.plant; life[ni] = life[idx];
              setPlantData(ni, kPlantTree, kStMature); velY[ni] = curSize;
              markProcessed(ni);
            }
          }
        }
      }
    }
  }

  void _growMushroom(int x, int y, int idx, int curSize) {
    if (curSize < 3) {
      final uy = y - gravityDir;
      if (inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
        final ni = uy * gridW + x;
        grid[ni] = El.plant; life[ni] = life[idx];
        final newSize = curSize + 1;
        setPlantData(ni, kPlantMushroom, newSize >= 2 ? kStMature : kStGrowing);
        velY[ni] = newSize;
        markProcessed(ni);
        velY[idx] = newSize;
      }
    }
    if (rng.nextInt(80) == 0) {
      for (int r = 1; r <= 3; r++) {
        final sx = x + (rng.nextBool() ? r : -r);
        final by = y + gravityDir;
        if (inBounds(sx, y) && grid[y * gridW + sx] == El.empty &&
            inBounds(sx, by) && grid[by * gridW + sx] == El.dirt &&
            life[by * gridW + sx] >= 4) {
          final ni = y * gridW + sx;
          grid[ni] = El.plant; life[ni] = life[idx];
          setPlantData(ni, kPlantMushroom, kStSprout); velY[ni] = 1;
          markProcessed(ni);
          break;
        }
      }
    }
  }

  void _growVine(int x, int y, int idx, int curSize) {
    if (curSize < 12) {
      final directions = <List<int>>[];
      for (final d in [[-1, -gravityDir], [1, -gravityDir], [-1, 0], [1, 0], [0, -gravityDir]]) {
        final nx = x + d[0]; final ny = y + d[1];
        if (!inBounds(nx, ny)) continue;
        if (grid[ny * gridW + nx] != El.empty) continue;
        bool nearSolid = false;
        for (int dy2 = -1; dy2 <= 1; dy2++) {
          for (int dx2 = -1; dx2 <= 1; dx2++) {
            final sx = nx + dx2; final sy = ny + dy2;
            if (!inBounds(sx, sy)) continue;
            final se = grid[sy * gridW + sx];
            if (se == El.dirt || se == El.stone || se == El.wood || se == El.metal) {
              nearSolid = true; break;
            }
          }
          if (nearSolid) break;
        }
        if (nearSolid) directions.add(d);
      }
      if (directions.isNotEmpty) {
        final d = directions[rng.nextInt(directions.length)];
        final nx = x + d[0]; final ny = y + d[1];
        final ni = ny * gridW + nx;
        grid[ni] = El.plant; life[ni] = life[idx];
        setPlantData(ni, kPlantVine, kStGrowing);
        velY[ni] = (curSize + 1); markProcessed(ni);
        velY[idx] = (curSize + 1);
      }
    }
  }

  void simLava(int x, int y, int idx) {
    life[idx]++;
    final g = gravityDir;

    if (life[idx] > 200 + rng.nextInt(50)) {
      grid[idx] = El.stone;
      life[idx] = 0;
      markProcessed(idx);
      return;
    }

    // --- Volcanic gas emission ---
    // Lava exposed to air above emits smoke/steam upward
    final uy = y - g;
    if (inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
      if (rng.nextInt(80) == 0) {
        // Volcanic smoke plume
        grid[uy * gridW + x] = El.smoke;
        life[uy * gridW + x] = 0;
        markProcessed(uy * gridW + x);
      } else if (rng.nextInt(120) == 0) {
        // Occasional steam vent
        grid[uy * gridW + x] = El.steam;
        life[uy * gridW + x] = 0;
        markProcessed(uy * gridW + x);
      }
    }

    // --- Eruption pressure: lava trapped under stone builds pressure ---
    // Count stone cells directly above this lava (cap check)
    if (rng.nextInt(60) == 0) {
      int capDepth = 0;
      for (int cy = y - g; inBounds(x, cy) && capDepth < 6; cy -= g) {
        if (grid[cy * gridW + x] == El.stone) {
          capDepth++;
        } else {
          break;
        }
      }
      // Count lava below (magma chamber pressure)
      int lavaBelow = 0;
      for (int cy = y + g; inBounds(x, cy) && lavaBelow < 8; cy += g) {
        if (grid[cy * gridW + x] == El.lava) {
          lavaBelow++;
        } else {
          break;
        }
      }
      // Eruption: if capped by stone and significant lava pressure, blast through
      if (capDepth >= 2 && lavaBelow >= 3 && rng.nextInt(20) == 0) {
        // Blast a hole in the cap — turn topmost stone to lava
        final blastY = y - g * capDepth;
        if (inBounds(x, blastY)) {
          final blastIdx = blastY * gridW + x;
          grid[blastIdx] = El.lava;
          life[blastIdx] = 0;
          markProcessed(blastIdx);
          // Eruption flash
          queueReactionFlash(x, blastY, 255, 200, 50, 8);
        }
        // Blast neighbors too for wider eruption
        for (final dx in [-1, 1]) {
          final bx = x + dx;
          final by2 = y - g * (capDepth - 1);
          if (inBounds(bx, by2) && grid[by2 * gridW + bx] == El.stone && rng.nextBool()) {
            grid[by2 * gridW + bx] = El.fire;
            life[by2 * gridW + bx] = 0;
            markProcessed(by2 * gridW + bx);
          }
        }
      }
    }

    // --- Lava spatter: surface lava ejects molten droplets upward ---
    if (rng.nextInt(100) == 0 && inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
      // Count lava neighbors to determine if this is a pool surface
      int lavaNeighbors = 0;
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.lava) {
            lavaNeighbors++;
          }
        }
      }
      if (lavaNeighbors >= 3) {
        // Spatter: eject a lava droplet upward
        final spatterH = 2 + rng.nextInt(4);
        final spatterDx = rng.nextInt(3) - 1;
        for (int d = 1; d <= spatterH; d++) {
          final sy = y - g * d;
          final sx = x + spatterDx * (d > 2 ? 1 : 0);
          if (inBounds(sx, sy) && grid[sy * gridW + sx] == El.empty) {
            if (d <= 2) {
              grid[sy * gridW + sx] = El.lava;
              life[sy * gridW + sx] = 150; // already partially cooled
              markProcessed(sy * gridW + sx);
            } else {
              grid[sy * gridW + sx] = El.fire;
              life[sy * gridW + sx] = 0;
              markProcessed(sy * gridW + sx);
            }
          } else {
            break;
          }
        }
        // Spatter particles
        queueReactionFlash(x, uy, 255, 180, 30, 5);
      }
    }

    // --- Heat stone: stone adjacent to lava gets heated (visual only via life) ---
    if (frameCount % 8 == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] == El.stone) {
            // Heat the stone — renderer will show warm glow
            // Use velX to store heat level (0-5) since stone doesn't use velX
            final heat = velX[ni].clamp(0, 5);
            if (heat < 5) velX[ni] = (heat + 1);
          }
        }
      }
    }

    // --- Element interactions ---
    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = ny * gridW + nx;
        final neighbor = grid[ni];
        if (neighbor == El.water) {
          grid[idx] = El.stone;
          life[idx] = 0;
          markProcessed(idx);
          grid[ni] = El.steam;
          life[ni] = 0;
          markProcessed(ni);
          // Dramatic steam burst with white-hot flash
          queueReactionFlash(x, y, 255, 255, 255, 8);
          queueReactionFlash(nx, ny, 200, 220, 255, 5);
          final extraSteam = 3 + rng.nextInt(3);
          for (int s = 0; s < extraSteam; s++) {
            final sx = x + rng.nextInt(7) - 3;
            final sy2 = y - g * (1 + rng.nextInt(3));
            if (inBounds(sx, sy2) && grid[sy2 * gridW + sx] == El.empty) {
              grid[sy2 * gridW + sx] = El.steam;
              life[sy2 * gridW + sx] = 0;
              markProcessed(sy2 * gridW + sx);
            }
          }
          return;
        }
        if (neighbor == El.ice) {
          grid[idx] = El.stone;
          life[idx] = 0;
          markProcessed(idx);
          grid[ni] = El.water;
          life[ni] = 0;
          markProcessed(ni);
          // Ice cracking flash
          queueReactionFlash(nx, ny, 180, 220, 255, 4);
          return;
        }
        if ((neighbor == El.plant || neighbor == El.seed ||
             neighbor == El.oil || neighbor == El.wood) &&
            rng.nextInt(2) == 0) {
          grid[ni] = El.fire;
          life[ni] = 0;
          markProcessed(ni);
        }
        if (neighbor == El.snow) {
          grid[ni] = El.water;
          life[ni] = 100;
          markProcessed(ni);
        }
        // Lava melts nearby sand into glass (volcanic glass / obsidian)
        if (neighbor == El.sand && rng.nextInt(40) == 0) {
          grid[ni] = El.glass;
          life[ni] = 0;
          markProcessed(ni);
          queueReactionFlash(nx, ny, 255, 200, 100, 3);
        }
      }
    }

    // --- Volcanic gas: surface lava emits smoke and steam ---
    final gasY = y - gravityDir;
    if (rng.nextInt(80) == 0 && inBounds(x, gasY) && grid[gasY * gridW + x] == El.empty) {
      // Emit smoke (2/3) or steam (1/3)
      final gasIdx = gasY * gridW + x;
      if (rng.nextInt(3) == 0) {
        grid[gasIdx] = El.steam;
      } else {
        grid[gasIdx] = El.smoke;
      }
      life[gasIdx] = 0;
      markProcessed(gasIdx);
    }

    // --- Eruption pressure: lava trapped under stone builds pressure ---
    if (rng.nextInt(60) == 0) {
      final g = gravityDir;
      int capDepth = 0;
      for (int cy = y - g; inBounds(x, cy) && capDepth < 6; cy -= g) {
        if (grid[cy * gridW + x] == El.stone) {
          capDepth++;
        } else {
          break;
        }
      }
      int lavaBelow = 0;
      for (int cy = y + g; inBounds(x, cy) && lavaBelow < 8; cy += g) {
        if (grid[cy * gridW + x] == El.lava) {
          lavaBelow++;
        } else {
          break;
        }
      }
      // Need at least 2 stone cap and 3 lava below to build pressure
      if (capDepth >= 2 && lavaBelow >= 3 && rng.nextInt(20) == 0) {
        // Blast through the stone cap
        final blastY = y - g * capDepth;
        if (inBounds(x, blastY)) {
          final blastIdx = blastY * gridW + x;
          grid[blastIdx] = El.lava;
          life[blastIdx] = 0;
          markProcessed(blastIdx);
          queueReactionFlash(x, blastY, 255, 200, 50, 8);
        }
        // Blast neighboring stone for wider eruption
        for (final dx in [-1, 1]) {
          final bx = x + dx;
          final by2 = y - g * (capDepth - 1);
          if (inBounds(bx, by2) &&
              grid[by2 * gridW + bx] == El.stone &&
              rng.nextBool()) {
            grid[by2 * gridW + bx] = El.fire;
            life[by2 * gridW + bx] = 0;
            markProcessed(by2 * gridW + bx);
          }
        }
      }
    }

    // --- Lava spatter: surface lava ejects molten droplets upward ---
    if (rng.nextInt(100) == 0 && inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
      int lavaNeighbors = 0;
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx2 = x + dx2;
          final ny2 = y + dy2;
          if (inBounds(nx2, ny2) && grid[ny2 * gridW + nx2] == El.lava) {
            lavaNeighbors++;
          }
        }
      }
      // Pools of lava (3+ neighbors) spatter more dramatically
      if (lavaNeighbors >= 3) {
        final spatterH = 2 + rng.nextInt(4);
        final spatterDx = rng.nextInt(3) - 1;
        for (int d = 1; d <= spatterH; d++) {
          final sy = y - gravityDir * d;
          final sx = x + (d > 1 ? spatterDx : 0);
          if (!inBounds(sx, sy)) break;
          final si = sy * gridW + sx;
          if (grid[si] != El.empty) break;
          if (d <= 2) {
            grid[si] = El.lava;
            life[si] = 0;
          } else {
            grid[si] = El.fire;
            life[si] = 0;
          }
          markProcessed(si);
        }
        queueReactionFlash(x, uy, 255, 180, 30, 5);
      }
    }

    // --- Heat stone: stone adjacent to lava gradually heats up ---
    if (frameCount % 8 == 0) {
      for (int dy2 = -1; dy2 <= 1; dy2++) {
        for (int dx2 = -1; dx2 <= 1; dx2++) {
          if (dx2 == 0 && dy2 == 0) continue;
          final nx2 = x + dx2;
          final ny2 = y + dy2;
          if (!inBounds(nx2, ny2)) continue;
          final ni = ny2 * gridW + nx2;
          if (grid[ni] == El.stone) {
            final heat = velX[ni].clamp(0, 5);
            velX[ni] = (heat + 1).clamp(0, 5);
          }
        }
      }
    }

    // Lava is very viscous — moves every 3rd frame (slower than water)
    if (frameCount % 3 != 0) return;

    final by = y + g;
    if (inBounds(x, by) && grid[by * gridW + x] == El.empty) {
      swap(idx, by * gridW + x);
      return;
    }

    // Lava sinks through water (heavier)
    if (inBounds(x, by) && grid[by * gridW + x] == El.water) {
      final bi = by * gridW + x;
      grid[bi] = El.lava;
      life[bi] = life[idx];
      grid[idx] = El.steam;
      life[idx] = 0;
      markProcessed(idx);
      markProcessed(bi);
      queueReactionFlash(x, y, 220, 220, 255, 4);
      return;
    }

    final dl = rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (inBounds(x1, by) && grid[by * gridW + x1] == El.empty) {
      swap(idx, by * gridW + x1);
      return;
    }
    if (inBounds(x2, by) && grid[by * gridW + x2] == El.empty) {
      swap(idx, by * gridW + x2);
      return;
    }

    // Lateral flow is very slow for lava — only every 6th frame
    if (frameCount % 6 == 0) {
      if (inBounds(x1, y) && grid[y * gridW + x1] == El.empty) {
        swap(idx, y * gridW + x1);
        return;
      }
      if (inBounds(x2, y) && grid[y * gridW + x2] == El.empty) {
        swap(idx, y * gridW + x2);
      }
    }
  }

  void simSnow(int x, int y, int idx) {
    // Melt near heat sources
    if (checkAdjacent(x, y, El.fire) || checkAdjacent(x, y, El.lava)) {
      if (!isNight || rng.nextBool()) {
        grid[idx] = El.water;
        life[idx] = 100;
        markProcessed(idx);
        // Melting particle drip effect
        queueReactionFlash(x, y, 150, 200, 255, 2);
        return;
      }
    }

    // Gradual ambient melting during daytime (not night)
    if (!isNight && rng.nextInt(200) == 0) {
      // Check if near any warm element within 3 cells
      for (int dy = -3; dy <= 3; dy++) {
        for (int dx = -3; dx <= 3; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!inBounds(nx, ny)) continue;
          final n = grid[ny * gridW + nx];
          if (n == El.fire || n == El.lava) {
            grid[idx] = El.water;
            life[idx] = 80;
            markProcessed(idx);
            return;
          }
        }
      }
    }

    if (rng.nextInt(30) == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.water) {
            grid[ny * gridW + nx] = El.ice;
            life[ny * gridW + nx] = 0;
            markProcessed(ny * gridW + nx);
            break;
          }
        }
      }
    }

    final ug = -gravityDir;
    int snowAbove = 0;
    for (int d = 1; d <= 4; d++) {
      final cy = y + ug * d;
      if (!inBounds(x, cy)) break;
      if (grid[cy * gridW + x] == El.snow) {
        snowAbove++;
      } else {
        break;
      }
    }
    if (snowAbove >= 3) {
      grid[idx] = El.ice;
      life[idx] = 0;
      markProcessed(idx);
      return;
    }

    if (frameCount.isOdd) return;

    final by = y + gravityDir;
    if (inBounds(x, by) && grid[by * gridW + x] == El.empty) {
      swap(idx, by * gridW + x);
      return;
    }

    final dl = rng.nextBool();
    for (int d = 1; d <= 2; d++) {
      final sx1 = dl ? x - d : x + d;
      final sx2 = dl ? x + d : x - d;
      if (inBounds(sx1, by) && grid[by * gridW + sx1] == El.empty) {
        swap(idx, by * gridW + sx1);
        return;
      }
      if (inBounds(sx2, by) && grid[by * gridW + sx2] == El.empty) {
        swap(idx, by * gridW + sx2);
        return;
      }
    }
    // Snow avalanches more easily than sand (softer)
    if (grid[idx] == El.snow && rng.nextInt(2) == 0) {
      _avalancheGranular(x, y, idx);
    }
  }

  void simWood(int x, int y, int idx) {
    if (life[idx] > 0) {
      life[idx]++;
      if (rng.nextInt(100) < 15) {
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx;
            final ny = y + dy;
            if (!inBounds(nx, ny)) continue;
            final ni = ny * gridW + nx;
            if (grid[ni] == El.wood && life[ni] == 0) {
              life[ni] = 1;
              break;
            }
          }
        }
      }
      if (life[idx] > 40 + rng.nextInt(20)) {
        grid[idx] = El.ash;
        life[idx] = 0;
        velY[idx] = 0;
        markProcessed(idx);
        final uy = y - gravityDir;
        if (inBounds(x, uy) && grid[uy * gridW + x] == El.empty) {
          grid[uy * gridW + x] = El.smoke;
          life[uy * gridW + x] = 0;
          markProcessed(uy * gridW + x);
        }
      }
      return;
    }

    if (checkAdjacent(x, y, El.water) && velY[idx] < 3) {
      if (rng.nextInt(30) == 0) {
        velY[idx] = (velY[idx] + 1).clamp(0, 3).toInt();
        removeOneAdjacent(x, y, El.water);
      }
    }

    if (velY[idx] >= 3) {
      final by = y + gravityDir;
      if (inBounds(x, by)) {
        final bi = by * gridW + x;
        if (grid[bi] == El.water) {
          final waterMass = life[bi];
          grid[idx] = El.water;
          life[idx] = waterMass < 20 ? 100 : waterMass;
          grid[bi] = El.wood;
          life[bi] = 0;
          velY[bi] = 3;
          markProcessed(idx);
          markProcessed(bi);
          return;
        }
      }
    }

    if (checkAdjacent(x, y, El.fire) || checkAdjacent(x, y, El.lava)) {
      if (velY[idx] < 3 || rng.nextInt(5) == 0) {
        life[idx] = 1;
        velY[idx] = 0;
        // Wood ignition flash
        queueReactionFlash(x, y, 255, 150, 30, 3);
      }
    }
  }

  void simMetal(int x, int y, int idx) {
    if (life[idx] >= 200) return;

    if (checkAdjacent(x, y, El.water)) {
      life[idx]++;
      if (life[idx] > 120) {
        grid[idx] = El.dirt;
        life[idx] = 0;
        markProcessed(idx);
        return;
      }
    }

    if (rng.nextInt(100) == 0) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] == El.empty && checkAdjacent(nx, ny, El.water)) {
            grid[ni] = El.water;
            life[ni] = 100;
            markProcessed(ni);
            return;
          }
        }
      }
    }
  }

  void simSmoke(int x, int y, int idx) {
    life[idx]++;
    if (life[idx] > 60) {
      grid[idx] = El.empty;
      life[idx] = 0;
      return;
    }

    final uy = y - gravityDir;
    // Wind-responsive drift: smoke drifts more in wind direction
    int drift = rng.nextInt(3) - 1;
    if (windForce != 0) {
      // Smoke is very wind-responsive — bias drift toward wind
      final windBias = windForce > 0 ? 1 : -1;
      if (rng.nextInt(3) < 2) drift = windBias;
    }

    if (inBounds(x, uy)) {
      final nx = x + drift;
      if (inBounds(nx, uy) && grid[uy * gridW + nx] == El.empty) {
        swap(idx, uy * gridW + nx);
        return;
      }
      if (grid[uy * gridW + x] == El.empty) {
        swap(idx, uy * gridW + x);
        return;
      }
    }
    // Lateral spread — more in wind direction
    final side = windForce != 0
        ? x + (windForce > 0 ? 1 : -1)
        : (rng.nextBool() ? x - 1 : x + 1);
    if (inBounds(side, y) && grid[y * gridW + side] == El.empty) {
      swap(idx, y * gridW + side);
    }
  }

  void simBubble(int x, int y, int idx) {
    life[idx]++;

    final inWater = checkAdjacent(x, y, El.water);
    final uy = y - gravityDir;

    if (inWater) {
      if (life[idx] % 3 == 0 && inBounds(x, uy)) {
        // Wobble sideways while rising for realistic bubble movement
        final wobble = rng.nextInt(3) - 1;
        final riseX = (x + wobble).clamp(0, gridW - 1);

        final ai = uy * gridW + riseX;
        if (grid[ai] == El.water) {
          grid[ai] = El.bubble;
          life[ai] = life[idx];
          grid[idx] = El.water;
          life[idx] = 100;
          markProcessed(ai);
          markProcessed(idx);
          return;
        }
        // Try straight up if wobble failed
        if (wobble != 0) {
          final straightUp = uy * gridW + x;
          if (grid[straightUp] == El.water) {
            grid[straightUp] = El.bubble;
            life[straightUp] = life[idx];
            grid[idx] = El.water;
            life[idx] = 100;
            markProcessed(straightUp);
            markProcessed(idx);
            return;
          }
        }
        // Pop at surface — create water droplet splash
        final surfaceIdx = uy * gridW + x;
        if (inBounds(x, uy) && grid[surfaceIdx] == El.empty) {
          grid[idx] = El.empty;
          life[idx] = 0;
          // Pop splash: scatter water droplets upward
          final droplets = 2 + rng.nextInt(3);
          for (int i = 0; i < droplets; i++) {
            final dx = rng.nextInt(5) - 2;
            final dy = -gravityDir * (rng.nextInt(3) + 1);
            final nx = x + dx;
            final ny = y + dy;
            if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.empty) {
              grid[ny * gridW + nx] = El.water;
              life[ny * gridW + nx] = 60;
              markProcessed(ny * gridW + nx);
            }
          }
          // Pop visual effect
          queueReactionFlash(x, uy, 150, 210, 255, 3);
          return;
        }
      }
    } else {
      // Bubble outside water pops quickly
      if (life[idx] > 20) {
        grid[idx] = El.empty;
        life[idx] = 0;
        queueReactionFlash(x, y, 130, 200, 240, 2);
      }
    }
  }

  void simAsh(int x, int y, int idx) {
    life[idx]++;
    final g = gravityDir;
    final by = y + g;

    // Ash on dirt = fertilizer
    if (checkAdjacent(x, y, El.dirt)) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (!inBounds(nx, ny)) continue;
          final ni = ny * gridW + nx;
          if (grid[ni] == El.dirt) {
            life[ni] = (life[ni] + 1).clamp(0, 4);
            grid[idx] = El.empty;
            life[idx] = 0;
            markProcessed(idx);
            return;
          }
        }
      }
    }

    // Ash in water
    final inWaterCheck = checkAdjacent(x, y, El.water);
    if (inWaterCheck) {
      velX[idx] = (velX[idx] + 1).clamp(0, 127).toInt();

      int waterCount = 0;
      for (int dy2 = -3; dy2 <= 3; dy2++) {
        for (int dx2 = -3; dx2 <= 3; dx2++) {
          final nx = x + dx2;
          final ny = y + dy2;
          if (inBounds(nx, ny) && grid[ny * gridW + nx] == El.water) {
            waterCount++;
          }
        }
      }

      final isLargeBody = waterCount > 20;

      if (isLargeBody) {
        if (velX[idx] > 15) {
          grid[idx] = El.empty;
          life[idx] = 0;
          velX[idx] = 0;
          return;
        }
      } else {
        if (velX[idx] < 30) {
          if (rng.nextInt(3) == 0) {
            final side = rng.nextBool() ? x - 1 : x + 1;
            if (inBounds(side, y) && grid[y * gridW + side] == El.empty) {
              swap(idx, y * gridW + side);
            }
          }
          return;
        }
        if (life[idx] % 3 == 0 && inBounds(x, by)) {
          final bi = by * gridW + x;
          if (grid[bi] == El.water) {
            final waterMass2 = life[bi];
            grid[idx] = El.water;
            grid[bi] = El.ash;
            life[bi] = life[idx];
            velX[bi] = velX[idx];
            life[idx] = waterMass2 < 20 ? 100 : waterMass2;
            velX[idx] = 0;
            markProcessed(idx);
            markProcessed(bi);
            return;
          }
        }
      }
      return;
    } else {
      velX[idx] = 0;
    }

    // Very slow fall
    if (life[idx] % 3 != 0) return;

    if (inBounds(x, by)) {
      final below = by * gridW + x;
      if (grid[below] == El.empty) {
        swap(idx, below);
        return;
      }
      if (grid[below] == El.water) {
        return;
      }
    }

    final dl = rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (inBounds(x1, by) && grid[by * gridW + x1] == El.empty) {
      swap(idx, by * gridW + x1);
      return;
    }
    if (inBounds(x2, by) && grid[by * gridW + x2] == El.empty) {
      swap(idx, by * gridW + x2);
      return;
    }

    if (rng.nextInt(3) == 0) {
      final sx = rng.nextBool() ? x - 1 : x + 1;
      if (inBounds(sx, y) && grid[y * gridW + sx] == El.empty) {
        swap(idx, y * gridW + sx);
      }
    }
  }

  void simTNT(int x, int y, int idx) {
    fallGranular(x, y, idx, El.tnt);
  }

  void simRainbow(int x, int y, int idx) {
    final uy = y - gravityDir;
    if (rng.nextInt(3) == 0 && inBounds(x, uy)) {
      if (grid[uy * gridW + x] == El.empty) {
        swap(idx, uy * gridW + x);
        life[idx] = (life[idx] + 1) % 255;
        return;
      }
      final side = rng.nextBool() ? x - 1 : x + 1;
      if (inBounds(side, uy) &&
          grid[uy * gridW + side] == El.empty) {
        swap(idx, uy * gridW + side);
      }
    }
    life[idx] = (life[idx] + 1) % 255;
  }

  void simMud(int x, int y, int idx) {
    // Mud dries out near fire or lava, becoming dirt
    if (rng.nextInt(20) == 0 && (checkAdjacent(x, y, El.fire) || checkAdjacent(x, y, El.lava))) {
      grid[idx] = El.dirt;
      life[idx] = 0;
      markProcessed(idx);
      queueReactionFlash(x, y, 180, 180, 200, 2);
      return;
    }

    final g = gravityDir;
    final by = y + g;

    // Mud is a viscous liquid: falls 2 out of 3 frames (slower than water, faster than sand)
    if (frameCount % 3 == 0) {
      // Rest frame — only do sideways spread
      final dl = rng.nextBool();
      final x1 = dl ? x - 1 : x + 1;
      final x2 = dl ? x + 1 : x - 1;
      if (inBounds(x1, y) && grid[y * gridW + x1] == El.empty) {
        swap(idx, y * gridW + x1);
      } else if (inBounds(x2, y) && grid[y * gridW + x2] == El.empty) {
        swap(idx, y * gridW + x2);
      }
      return;
    }

    // Fall straight down
    if (inBounds(x, by) && grid[by * gridW + x] == El.empty) {
      swap(idx, by * gridW + x);
      return;
    }
    // Sink through water (heavier than water)
    if (inBounds(x, by) && grid[by * gridW + x] == El.water) {
      final bi = by * gridW + x;
      final waterMass = life[bi];
      grid[idx] = El.water;
      life[idx] = waterMass < 20 ? 100 : waterMass;
      grid[bi] = El.mud;
      life[bi] = 0;
      markProcessed(idx);
      markProcessed(bi);
      return;
    }
    // Diagonal fall
    final dl = rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (inBounds(x1, by) && grid[by * gridW + x1] == El.empty) {
      swap(idx, by * gridW + x1);
      return;
    }
    if (inBounds(x2, by) && grid[by * gridW + x2] == El.empty) {
      swap(idx, by * gridW + x2);
      return;
    }
    // Sideways spread when blocked below
    if (inBounds(x1, y) && grid[y * gridW + x1] == El.empty) {
      swap(idx, y * gridW + x1);
      return;
    }
    if (inBounds(x2, y) && grid[y * gridW + x2] == El.empty) {
      swap(idx, y * gridW + x2);
    }
  }

  void simSteam(int x, int y, int idx) {
    final lifeVal = life[idx];
    // Prevent Uint8 overflow (wraps at 255 -> 0, making steam immortal)
    if (lifeVal < 250) life[idx] = lifeVal + 1;
    final uy = y - gravityDir;
    final atEdge = gravityDir == 1 ? y <= 2 : y >= gridH - 3;
    final steamLife = isNight ? 40 + rng.nextInt(20) : 80 + rng.nextInt(40);
    if (life[idx] > steamLife) {
      // Expired steam: condense to water only if not at edge (ceiling water stays forever)
      if (!atEdge && rng.nextInt(isNight ? 2 : 3) == 0) {
        grid[idx] = El.water;
        life[idx] = 100;
      } else {
        grid[idx] = El.empty;
        life[idx] = 0;
      }
      markProcessed(idx);
      return;
    }
    if (atEdge) {
      // At ceiling/floor edge: always dissipate (never condense to water here)
      grid[idx] = El.empty;
      life[idx] = 0;
      markProcessed(idx);
      return;
    }

    final condenseChance = isNight ? 15 : 30;
    if (rng.nextInt(condenseChance) == 0 && checkAdjacent(x, y, El.water)) {
      grid[idx] = El.water;
      life[idx] = 100;
      markProcessed(idx);
      return;
    }

    if (inBounds(x, uy)) {
      final drift = rng.nextInt(3) - 1;
      final nx = x + drift;
      if (inBounds(nx, uy) && grid[uy * gridW + nx] == El.empty) {
        swap(idx, uy * gridW + nx);
        return;
      }
      if (grid[uy * gridW + x] == El.empty) {
        swap(idx, uy * gridW + x);
        return;
      }
    }
    final side = rng.nextBool() ? x - 1 : x + 1;
    if (inBounds(side, y) && grid[y * gridW + side] == El.empty) {
      swap(idx, y * gridW + side);
    }
  }

  void simOil(int x, int y, int idx) {
    if (checkAdjacent(x, y, El.fire)) {
      grid[idx] = El.fire;
      life[idx] = 0;
      markProcessed(idx);
      return;
    }

    final by = y + gravityDir;
    final uy = y - gravityDir;
    final notProcessed = (simClock ? 0x80 : 0);

    // Oil is lighter than water — always float upward through water
    // Check below: if water is below, swap (oil rises, water sinks)
    if (inBounds(x, by) && grid[by * gridW + x] == El.water &&
        (flags[by * gridW + x] & 0x80) != notProcessed) {
      final bi = by * gridW + x;
      final waterMass = life[bi];
      grid[bi] = El.oil;
      life[bi] = life[idx];
      grid[idx] = El.water;
      life[idx] = waterMass < 20 ? 100 : waterMass;
      markProcessed(bi);
      markProcessed(idx);
      return;
    }

    // Fall through empty space
    if (inBounds(x, by) && grid[by * gridW + x] == El.empty) {
      swap(idx, by * gridW + x);
      return;
    }

    // Buoyancy: swap with water above (oil pushes up past water on top)
    if (inBounds(x, uy) && grid[uy * gridW + x] == El.water &&
        (flags[uy * gridW + x] & 0x80) != notProcessed) {
      final ui = uy * gridW + x;
      final waterMass = life[ui];
      grid[ui] = El.oil;
      life[ui] = life[idx];
      grid[idx] = El.water;
      life[idx] = waterMass < 20 ? 100 : waterMass;
      markProcessed(ui);
      markProcessed(idx);
      return;
    }

    // Diagonal buoyancy: swap with water diagonally below
    final dl = rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;

    for (final sx in [x1, x2]) {
      if (inBounds(sx, by) && grid[by * gridW + sx] == El.water &&
          (flags[by * gridW + sx] & 0x80) != notProcessed) {
        final si = by * gridW + sx;
        final waterMass = life[si];
        grid[si] = El.oil;
        life[si] = life[idx];
        grid[idx] = El.water;
        life[idx] = waterMass < 20 ? 100 : waterMass;
        markProcessed(si);
        markProcessed(idx);
        return;
      }
    }

    // Diagonal fall through empty
    if (inBounds(x1, by) && grid[by * gridW + x1] == El.empty) {
      swap(idx, by * gridW + x1);
      return;
    }
    if (inBounds(x2, by) && grid[by * gridW + x2] == El.empty) {
      swap(idx, by * gridW + x2);
      return;
    }

    // Lateral spread (slower than water)
    if (frameCount.isEven) {
      if (inBounds(x1, y) && grid[y * gridW + x1] == El.empty) {
        swap(idx, y * gridW + x1);
        return;
      }
      if (inBounds(x2, y) && grid[y * gridW + x2] == El.empty) {
        swap(idx, y * gridW + x2);
      }
    }
  }

  void simAcid(int x, int y, int idx) {
    life[idx]++;

    if (life[idx] > 120 + rng.nextInt(60)) {
      grid[idx] = El.empty;
      life[idx] = 0;
      return;
    }

    for (int dy = -1; dy <= 1; dy++) {
      for (int dx = -1; dx <= 1; dx++) {
        if (dx == 0 && dy == 0) continue;
        final nx = x + dx;
        final ny = y + dy;
        if (!inBounds(nx, ny)) continue;
        final ni = ny * gridW + nx;
        final neighbor = grid[ni];

        if (neighbor == El.stone && rng.nextInt(15) == 0) {
          grid[ni] = El.empty;
          life[ni] = 0;
          markProcessed(ni);
          grid[idx] = El.empty;
          life[idx] = 0;
          // Toxic green corrosion bubbles
          queueReactionFlash(nx, ny, 50, 255, 50, 5);
          return;
        }
        if (neighbor == El.glass && rng.nextInt(10) == 0) {
          grid[ni] = El.empty;
          life[ni] = 0;
          markProcessed(ni);
          grid[idx] = El.empty;
          life[idx] = 0;
          queueReactionFlash(nx, ny, 100, 255, 100, 4);
          return;
        }
        if (neighbor == El.metal && rng.nextInt(20) == 0) {
          // Acid corrodes metal slowly — eats through eventually
          life[ni] = (life[ni] + 15).clamp(0, 255);
          if (life[ni] > 120) {
            grid[ni] = El.empty;
            life[ni] = 0;
            markProcessed(ni);
            grid[idx] = El.empty;
            life[idx] = 0;
            queueReactionFlash(nx, ny, 80, 200, 80, 6);
            return;
          }
          // Sizzle particles as acid works on metal
          queueReactionFlash(nx, ny, 60, 230, 60, 2);
        }
        if (neighbor == El.ant) {
          grid[ni] = El.empty;
          life[ni] = 0;
          markProcessed(ni);
        }
        if (neighbor == El.water && rng.nextInt(8) == 0) {
          grid[idx] = El.water;
          life[idx] = 100;
          markProcessed(idx);
          return;
        }
        if ((neighbor == El.plant || neighbor == El.seed) && rng.nextInt(3) == 0) {
          grid[ni] = El.empty;
          life[ni] = 0;
          markProcessed(ni);
          queueReactionFlash(nx, ny, 40, 200, 40, 2);
        }
        if (neighbor == El.wood && rng.nextInt(12) == 0) {
          grid[ni] = El.empty;
          life[ni] = 0;
          markProcessed(ni);
          grid[idx] = El.empty;
          life[idx] = 0;
          queueReactionFlash(nx, ny, 60, 220, 40, 4);
          return;
        }
        if (neighbor == El.water && rng.nextInt(20) == 0) {
          grid[ni] = El.bubble;
          life[ni] = 0;
          markProcessed(ni);
        }
      }
    }

    final by = y + gravityDir;
    if (inBounds(x, by) && grid[by * gridW + x] == El.empty) {
      swap(idx, by * gridW + x);
      return;
    }

    final dl = rng.nextBool();
    final x1 = dl ? x - 1 : x + 1;
    final x2 = dl ? x + 1 : x - 1;
    if (inBounds(x1, by) && grid[by * gridW + x1] == El.empty) {
      swap(idx, by * gridW + x1);
      return;
    }
    if (inBounds(x2, by) && grid[by * gridW + x2] == El.empty) {
      swap(idx, by * gridW + x2);
      return;
    }

    if (inBounds(x1, y) && grid[y * gridW + x1] == El.empty) {
      swap(idx, y * gridW + x1);
      return;
    }
    if (inBounds(x2, y) && grid[y * gridW + x2] == El.empty) {
      swap(idx, y * gridW + x2);
    }
  }

  /// Avalanche check for granular materials (angle of repose).
  /// If a grain is sitting on a pile with steep sides, it slides down.
  void _avalancheGranular(int x, int y, int idx) {
    final g = gravityDir;
    final by = y + g;
    // Only avalanche if resting on something solid
    if (!inBounds(x, by) || grid[by * gridW + x] == El.empty) return;

    final goLeft = rng.nextBool();
    final dir1 = goLeft ? -1 : 1;
    final dir2 = goLeft ? 1 : -1;

    for (final dir in [dir1, dir2]) {
      final sx = x + dir;
      final sy = y;
      final sx2 = x + dir * 2;
      final sy2 = y + g;
      // Check: side is empty AND two-below-diagonal is empty (steep slope)
      if (inBounds(sx, sy) && grid[sy * gridW + sx] == El.empty &&
          inBounds(sx, sy2) && grid[sy2 * gridW + sx] == El.empty) {
        // Slide to the diagonal-below position
        swap(idx, sy2 * gridW + sx);
        return;
      }
      // Extended avalanche: check 2 cells out for very steep piles
      if (inBounds(sx, sy) && grid[sy * gridW + sx] == El.empty &&
          inBounds(sx2, sy2) && grid[sy2 * gridW + sx2] == El.empty &&
          inBounds(sx2, sy) && grid[sy * gridW + sx2] == El.empty) {
        swap(idx, sy * gridW + sx);
        return;
      }
    }
  }
}

/// Top-level dispatch function for element simulation.
/// Used as the callback for SimulationEngine.step().
void simulateElement(SimulationEngine e, int el, int x, int y, int idx) {
  switch (el) {
    case El.sand:      e.simSand(x, y, idx);
    case El.water:     e.simWater(x, y, idx);
    case El.fire:      e.simFire(x, y, idx);
    case El.ice:       e.simIce(x, y, idx);
    case El.lightning:  e.simLightning(x, y, idx);
    case El.seed:      e.simSeed(x, y, idx);
    case El.tnt:       e.simTNT(x, y, idx);
    case El.rainbow:   e.simRainbow(x, y, idx);
    case El.mud:       e.simMud(x, y, idx);
    case El.steam:     e.simSteam(x, y, idx);
    case El.ant:       e.simAnt(x, y, idx);
    case El.oil:       e.simOil(x, y, idx);
    case El.acid:      e.simAcid(x, y, idx);
    case El.dirt:      e.simDirt(x, y, idx);
    case El.plant:     e.simPlant(x, y, idx);
    case El.lava:      e.simLava(x, y, idx);
    case El.snow:      e.simSnow(x, y, idx);
    case El.wood:      e.simWood(x, y, idx);
    case El.metal:     e.simMetal(x, y, idx);
    case El.smoke:     e.simSmoke(x, y, idx);
    case El.bubble:    e.simBubble(x, y, idx);
    case El.ash:       e.simAsh(x, y, idx);
    // stone and glass do nothing (immovable)
  }
}
