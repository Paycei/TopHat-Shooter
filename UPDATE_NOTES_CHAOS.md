# TopHat Shooter - Chaos Edition Update

## Major Balance Changes

### Enemy Buffs & Nerfs

#### Triangles - HEAVILY BUFFED ⚠️
- **New Behavior**: No longer just dash attackers!
- Now have **free movement** between dashes
- Actively **chase and reposition** around the player
- Circle around player when close for unpredictable attacks
- Erratic movement patterns with slight randomization
- Increased HP: 1.0 → 1.2 * difficulty multiplier
- Faster base speed: 150 → 160 + difficulty scaling
- Still execute powerful dashes but remain dangerous between them

#### Stars - NERFED ✓
- **Required hits drastically reduced**: 15 + diff*8 → **8 + diff*3**
- Much easier to eliminate
- Slightly faster movement speed
- Still tanky but no longer tedious bullet sponges

#### Cubes - BUFFED (Ranged Specialists) 🎯
- **New Kiting AI**: Actively backs away when player gets too close
- Maintains optimal shooting distance (~250 units)
- Retreats when player is within 150 units
- Increased HP: 1.5 → 2.0 * difficulty multiplier
- Faster movement for repositioning: 30 → 55 + difficulty scaling
- Shoots **3-shot bursts** instead of single bullets
- Acts like true ranged enemy - dangerous at distance

#### Circles - SLIGHTLY BUFFED
- Faster base speed: 80 → 90 + difficulty scaling
- Remain as core chase enemies

### Boss Buffs - HEAVILY BUFFED 💀

#### Shape-Shifting Mechanic
Bosses now **transform between 4 phases** every 8 seconds:
1. **Circle Form** (Base) - Original boss behavior
2. **Cube Form** - Defensive, shoots 8-way spread
3. **Triangle Form** - Aggressive, 1.8x speed, rapid triple shots
4. **Star Form** - BULLET STORM - constant rapid fire

Each form changes visual appearance and behavior!

#### New Boss Abilities
- **Teleport Burst**: Short-range teleportation every 10-15 seconds
- **Shockwave Attack**: 360° bullet spread with particle effects every 5-8 seconds
- **Minion Spawning**: 3-4 minions per spawn (was 2-3)
- **Faster Attacks**: All boss types shoot/spawn more frequently
- **More HP**: 50+diff*30 → **80+diff*40** with stronger scaling
- **Higher Speed**: 50+diff*4 → **60+diff*5**

#### Enhanced Boss-Specific Attacks
- **Shooter**: 8→12 bullets, faster spiral (0.8s cooldown)
- **Summoner**: Spawns 4 minions every 3s (was 3 minions/4s)
- **Charger**: 4x speed dashes (was 3x), 2s cooldown
- **Orbit**: 6 bullets in orbit pattern (was 4), 0.2s cooldown

## Game-Wide Chaos Buffs 🔥

### Spawn System Overhaul
- **Faster Base Spawn Rate**: 1.8 → 1.2 seconds / (1 + diff*0.4)
- **Overlapping Wave System**: 
  - Continuous 15-second wave cycles
  - 40% of time is "wave mode" with extra fast spawns
  - 60% chance to spawn **double enemies** during waves
- **Boss Arrival Event**: 3 extra minions spawn with each boss
- Enemy variety increases faster with difficulty

### Combat Intensity
- **Faster Projectiles**: 
  - Player bullets: 400 → **480 speed** (1.2x)
  - Enemy bullets: **1.25x faster** than player
  - Boss bullets: 200-280 speed range
- **More Bullets On Screen**:
  - Cube enemies shoot 3-bullet bursts
  - Boss attacks spawn 12-16 bullets per volley
  - Bullet storms during Star phase
- **Bullet Lifetime**: 5 seconds before despawning

### Visual Chaos - Particle System
- **New Particle System** added to game
- **Death Explosions**: 15 particles per enemy, 50 for bosses
- **Impact Effects**: Particles on every bullet hit
- **Muzzle Flash**: Player shooting creates particles
- **Shockwave Visuals**: Boss shockwaves create particle rings
- **Teleport Effects**: 30 particles on boss teleport
- **Pickup Effects**: Particles when collecting items
- **Wall Destruction**: 20 particles when walls break

### Performance Optimizations
- Efficient particle pooling
- Bullet lifetime management
- All chaos handled in-memory
- Nim's performance handles 100+ entities smoothly

## UI Enhancements
- **Chaos Meter**: Shows escalating difficulty (0-100%)
- **Wave Indicator**: "*** WAVE ***" warning during spawn waves
- **Live Stats**: Enemy count, bullet count, particle count display
- **Enhanced Boss HP Bar**: Wider, more visible
- **Phase Indicators**: Boss color changes with form

## Player Experience
- **Pulsing Menu Title**: Animated main menu
- **"Chaos Edition" Subtitle**: Added to branding
- **Updated Help Screen**: Documents new enemy behaviors
- **Enhanced Visual Feedback**: Particles on all actions

## Technical Details
- All changes preserve code-only approach
- No external assets required
- Same project structure maintained
- Optimized for 60 FPS with heavy action
- Added `particle.nim` module
- Updated `types.nim` with new boss/particle types
- Enemy AI completely rewritten for new behaviors

## Difficulty Curve
- Early game (0-2 min): Manageable introduction
- Mid game (2-5 min): Chaos begins, all enemy types present
- Late game (5+ min): Maximum chaos, overlapping waves
- Boss fights: Now truly challenging multi-phase battles

## Balance Philosophy
The update shifts the game from "survive and shoot" to "survive the CHAOS":
- More threats on screen simultaneously
- Enemies require tactical positioning
- Bosses are epic multi-phase battles
- Visual feedback makes chaos readable
- Fast-paced action without being unfair

---

**Compile and run to experience the chaos! All systems operational.**
