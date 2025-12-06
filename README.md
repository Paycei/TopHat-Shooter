# 🎩 TopHat Shooter

**Version 2.0** - A fast-paced, wave-based bullet hell shooter built with Nim and Raylib

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Nim](https://img.shields.io/badge/Nim-2.0.0+-blue.svg)](https://nim-lang.org/)
[![Tests](https://img.shields.io/badge/tests-92%20passing-brightgreen.svg)](tests/README.md)

---

## ✨ Features

### 🎯 Game Modes
- **Wave-Based Mode** - Fight through progressive waves, earn upgrades between waves, and face boss battles every 5 waves
- **Time Survival Mode** - Classic endless survival with continuous enemy spawning and difficulty scaling

### 👾 Enemy Variety
**11 unique enemy types** with distinct AI behaviors and attack patterns:

| Enemy Type | Behavior | Special Ability | Difficulty |
|------------|----------|-----------------|------------|
| **Circle** | Chases player | Basic melee | ⭐ Easy |
| **Cube** | Stationary shooter | Ranged bullets | ⭐⭐ Medium |
| **Triangle** | Fast dasher | Aggressive charges | ⭐⭐ Medium |
| **Star** | Tank enemy | Explosion on death | ⭐⭐⭐ Hard |
| **Hexagon** | Teleporter | Chaos teleports | ⭐⭐⭐ Hard |
| **Cross** | Laser shooter | Cross-shaped attack | ⭐⭐⭐ Hard |
| **Diamond** | Orbital shooter | Shoots while dashing | ⭐⭐⭐ Hard |
| **Octagon** | Spray shooter | Multiple slow projectiles | ⭐⭐ Medium |
| **Pentagon** | Sniper | Single fast bullets | ⭐⭐ Medium |
| **Trickster** | Deceptive | Fake attack warnings | ⭐⭐⭐⭐ Very Hard |
| **Phantom** | Unpredictable | Teleports with clones | ⭐⭐⭐⭐ Very Hard |

**Progressive Enemy Unlock System**:
- **Waves 1-5**: Only Circles (tutorial phase)
- **Waves 6-10**: Pentagon introduced (ranged combat basics)
- **Waves 11-15**: Triangle added (dodge mechanics)
- **Waves 16-20**: Cube introduced (stationary threats)
- **Waves 21-25**: Star enemy unlocked (high HP tanks)
- **Waves 26-30**: Cross laser attacks
- **Waves 31-35**: Diamond orbital shooters
- **Waves 36-40**: Octagon spray attackers
- **Waves 41-45**: Hexagon teleporters
- **Waves 46-50**: Trickster deceptive enemies
- **Wave 51+**: Phantom chaos enemies + full roster

### 🐲 Boss Battles
**4 boss types** that shape-shift through multiple phases during battle:

Each boss cycles through **4 forms**: Circle → Cube → Triangle → Star

| Boss Type | Attack Pattern | Minions |
|-----------|----------------|---------|
| **Shooter Boss** | Spiral bullet patterns | None |
| **Summoner Boss** | Spawns waves of minions | Yes |
| **Charger Boss** | Aggressive dash attacks | None |
| **Orbit Boss** | Orbiting projectiles | None |

- Bosses appear **every 5 waves**
- Boss waves have **50% fewer regular enemies** to focus on the boss fight
- Bosses drop **special large coins** that must be collected to complete the wave
- Defeating bosses grants **Legendary Power-Up selection**

### 💪 Power-Up System
**30+ unique power-ups** across two rarity tiers:

#### Common Power-Ups (Earned every 2 waves)
**Offensive**:
- **Double Shot** - Fires rapid successive bursts (2-4 bullets)
- **Multi-Shot** - Shoots in spread patterns (2-4 directions)
- **Rapid Fire** - Increased fire rate
- **Piercing Shots** - Bullets pass through enemies
- **Explosive Bullets** - Area damage on impact
- **Homing Bullets** - Track nearest enemies
- **Bullet Ricochet** - Bounces off enemies
- **Bullet Split** - Splits into multiple projectiles on hit
- **Frost Shots** - Slows enemies on hit (25-60% slow)
- **Poison Damage** - Damage over time effect (4-6 DPS)
- **Chain Lightning** - Damage arcs between nearby enemies
- **Critical Hit** - Random critical damage (15-25% chance, 2-3x damage)
- **Bullet Damage** - Increases base bullet damage
- **Bullet Speed** - Faster projectile velocity
- **Bullet Size** - Larger projectiles (1.4-2.4x size)

**Defensive**:
- **Rotating Shield** - Orbiting protective barrier
- **Damage Zone** - Passive damage aura (50-150 radius, 2-10 DPS)
- **Dodge Chance** - Chance to evade damage
- **Thorns** - Reflects damage to attackers
- **Wall Master** - Places stronger defensive walls
- **Max Health** - Increases maximum HP
- **Regeneration** - Slowly restores HP (heals every 12-6 seconds)

**Utility**:
- **Speed Boost** - Permanent movement speed increase
- **Life Steal** - Gain HP from kills (every 20-10 kills)
- **Vampirism** - Lifesteal on hit
- **Lucky Coins** - Enemies drop more coins
- **Auto-Shoot** - Auto-targets nearest enemy (toggleable with F key)
- **Slow Field** - Enemies move slower nearby (120-200 radius, 30-55% slow)
- **Rage** - Damage increases at low HP
- **Berserker** - Attack speed increases at low HP

#### Legendary Power-Ups (Earned after defeating bosses)
- **Time Warp** - Slow down time globally (50% speed reduction, limited uses per wave)
- **Gravity Well** - Pull enemies toward you (extra effective on ranged enemies)
- **Phase Shift** - Teleport dash through enemies with invulnerability
- **Overcharge** - Bullets gain damage over distance (40-120% bonus)
- **Echo Shots** - Bullets leave damaging trails

### 🛡️ Additional Features
- **6 Consumable Types** - Health, Coins, Speed, Invincibility, Fire Rate, Magnet
- **Shop System** - Purchase permanent upgrades with coins (exponential cost scaling)
  - Damage upgrade (+0.5 base, scales 1.08x per purchase)
  - Fire Rate upgrade (0.95x per purchase, minimum 0.08s)
  - Move Speed upgrade (+12 per purchase)
  - Max Health upgrade (+2 HP per purchase)
  - Bullet Speed upgrade (+15 per purchase)
  - Walls (x4 deployable barriers, +15 coins per purchase)
- **Defensive Walls** - Place protective barriers with E key
- **Particle System** - Hundreds of dynamic particles for visual effects
- **Attack Warnings** - Visual indicators for enemy special attacks
- **Progressive Difficulty** - Enemies and bosses scale with wave number
- **Cheat/Debug Menu** - Developer tools for testing (CD+ hotkey, tester build only)

---

## 🎯 Controls

| Key | Action |
|-----|--------|
| **WASD** | Move |
| **Mouse / Space** | Shoot |
| **F** | Toggle Auto-Shoot on/off |
| **E** | Place Defensive Wall |
| **ESC** | Pause / Menu |
| **CD+** | Open Cheat Menu (tester build only) |

### Cheat Menu Controls (Tester Build)
| Key | Action |
|-----|--------|
| **1-5** | Switch tabs (Waves, Power-Ups, Stats, Permanent Power-Ups, Enemies) |
| **UP/DOWN** | Scroll through permanent power-ups list |
| **Mouse** | Click buttons and close menu (X button) |
| **ESC** | Close cheat menu |

---

## 🚀 Installation & Running

### Prerequisites
- [Nim](https://nim-lang.org/) >= 2.0.0
- [Raylib](https://www.raylib.com/) (via naylib >= 5.0.0)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/TopHat-Shooter.git
   cd TopHat-Shooter
   ```

2. **Install dependencies**
   ```bash
   nimble install
   ```

3. **Run the game**
   ```bash
   nimble run
   ```

### Building for Release

**Standard build:**
```bash
nimble build
```

**Optimized release build (recommended):**
```bash
nim c -d:release --opt:speed --passL:icono.res src/main.nim
```

**Windows icon (if rebuilding):**
```bash
# Icon resource is already compiled as icono.res
# The --passL:icono.res flag includes it in the build
```

The compiled executable will be available as `TopHatShooter.exe` (Windows) or equivalent for your platform.

---

## ⚡ Performance

Optimized for smooth gameplay even with:
- **50+ enemies** on screen simultaneously
- **200+ bullets** active at once
- **500+ particles** rendering
- **Multiple bosses** with phase transitions
- **Complex AI** behaviors and attack patterns
- **60+ FPS** on average hardware

**Performance optimizations include:**
- Efficient particle cleanup system
- Off-screen bullet culling
- Consumable auto-despawn after 15 seconds
- Optimized collision detection
- Smart enemy spawn management

---

## 🧪 Testing

The project includes a comprehensive test suite with **92 tests** covering:
- Player mechanics (damage, healing, power-ups)
- Enemy systems (spawning, types, difficulty scaling)
- Bullet physics (movement, special effects, types)
- Economy balance (coins, shop, scaling)
- Game logic (waves, bosses, progression)
- Edge cases and error handling

### Running Tests
```bash
# Run all tests
nim c -r tests/test_game.nim

# Verbose output
nim c -r --verbosity:2 tests/test_game.nim

# Optimized test run
nim c -d:release -r tests/test_game.nim
```

**Test Coverage**: ~87% of game logic

For detailed test documentation, see [tests/README.md](tests/README.md).

---

## 🛠️ Development

### Project Structure
```
TopHat-Shooter/
├── src/
│   ├── main.nim          # Entry point and game loop
│   ├── types.nim         # Core data structures
│   ├── game.nim          # Game state and logic (2000+ lines)
│   ├── player.nim        # Player mechanics
│   ├── enemy.nim         # Enemy AI and behaviors
│   ├── bullet.nim        # Projectile physics
│   ├── coin.nim          # Loot system
│   ├── consumable.nim    # Temporary power-ups
│   ├── powerup.nim       # Permanent upgrades
│   ├── particle.nim      # Visual effects
│   ├── wall.nim          # Defensive structures
│   ├── shop.nim          # Upgrade shop
│   ├── sound.nim         # Audio system
│   ├── settings.nim      # Game configuration
│   └── cheat.nim         # Debug/testing tools (750+ lines)
├── tests/
│   ├── test_game.nim     # Comprehensive test suite (1270+ lines)
│   └── README.md         # Test documentation (600+ lines)
├── TopHatShooter.nimble  # Package configuration
├── icono.res             # Windows icon resource
├── LICENSE               # MIT License
└── README.md             # This file
```

### Built With
- **Language**: [Nim](https://nim-lang.org/) 2.0.0+ - High-performance systems programming
- **Graphics**: [naylib](https://github.com/planetis-m/naylib) (Raylib bindings) - Game rendering
- **Testing**: Nim's built-in `unittest` module

### Code Statistics
- **Total Lines**: ~5,500+ lines of Nim code
- **Game Logic**: ~3,500 lines (game.nim, player.nim, enemy.nim, etc.)
- **Tests**: ~1,270 lines with 92 comprehensive tests
- **Documentation**: ~1,400 lines (READMEs, comments, test docs)

---

## 📝 Version History

### v2.0 (Current - Latest Release)
**Major Systems**:
- ✅ Complete wave-based game mode with power-up selection
- ✅ 11 unique enemy types with distinct behaviors
- ✅ Progressive enemy unlock system (new enemy every 5 waves)
- ✅ 4 boss types with 4-phase transformations (every 5 waves)
- ✅ 30+ power-ups (common and legendary tiers)
- ✅ Full shop and upgrade system with balanced economy
- ✅ 6 consumable types for tactical gameplay
- ✅ Comprehensive test suite (92 tests, 87% coverage)
- ✅ Developer cheat menu for testing (5 tabs, full control)

**Balance & Polish**:
- ✅ Particle effects and visual polish (500+ particles)
- ✅ Audio system integration (shoot, death, boss, wave complete sounds)
- ✅ Performance optimizations for smooth 60+ FPS
- ✅ Extensive balance adjustments based on playtesting
- ✅ Detailed documentation (README, test docs, code comments)

**Game Balance Highlights**:
- Boss waves spawn 50% fewer enemies to focus on boss fights
- Double Shot has 40% fire rate penalty to balance extra bullets
- Multi-shot damage reduced per bullet (67%, 55%, 45% by level)
- Shop costs scale exponentially (1.5x per purchase) to prevent farming
- Regeneration heals every 12-6 seconds depending on level
- Slow Field nerfed to 30-55% slow (from 50-75%) for balance
- Overcharge provides 40-120% damage bonus based on distance

**Technical Improvements**:
- Efficient memory management (particle cleanup, bullet culling)
- Smart enemy spawning (prevents screen clutter)
- Robust error handling (zero/null safe operations)
- Comprehensive test coverage (edge cases, balance, mechanics)

---

## 🎮 Gameplay Tips

### Early Game (Waves 1-10)
- Focus on **damage upgrades** from the shop
- Prioritize **Double Shot** or **Multi-Shot** for bullet coverage
- Save coins for **Max Health** upgrades
- Learn to dodge - invincibility frames are short

### Mid Game (Waves 11-30)
- Invest in **Regeneration** for sustained fights
- **Piercing Shots** become very valuable
- Use **Walls** strategically (E key) to create safe zones
- Boss fights every 5 waves - prepare before they spawn

### Late Game (Wave 31+)
- Stack **Legendary Power-Ups** from boss defeats
- **Slow Field** + **Frost Shots** creates powerful crowd control
- **Gravity Well** counters ranged enemies
- **Time Warp** for emergency situations
- Max out **Auto-Shoot** for consistent DPS

### Power-Up Synergies
- **Double Shot + Multi-Shot** = Massive bullet spread
- **Piercing + Ricochet** = Incredible multi-target damage
- **Explosive + Chain Lightning** = Screen-clearing combos
- **Frost + Slow Field** = Near-immobile enemies
- **Overcharge + Bullet Speed** = Maximum distance bonus damage

---

## 🏆 Achievements & Challenges

Try to achieve these self-imposed goals:
- ⭐ **Survivor**: Reach wave 20
- ⭐⭐ **Veteran**: Reach wave 50
- ⭐⭐⭐ **Master**: Reach wave 100
- 🎖️ **Pacifist Run**: Complete wave 10 with minimal kills (dodge-focused)
- 🎖️ **No Shop**: Beat 5 bosses without buying shop upgrades
- 🎖️ **Wall Master**: Place 50+ walls in a single run
- 🎖️ **Coin Collector**: Accumulate 1000+ coins
- 🎖️ **Power Build**: Collect 20+ power-ups in one run
- 🎖️ **Boss Rush**: Defeat 10 bosses in one run

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License - Copyright (c) 2025 Paycei

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

### How to Contribute
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Make your changes and **add tests**
4. Run the test suite (`nim c -r tests/test_game.nim`)
5. Commit your changes (`git commit -m 'Add AmazingFeature'`)
6. Push to the branch (`git push origin feature/AmazingFeature`)
7. Open a Pull Request

### Contribution Guidelines
- **Always add tests** for new features
- **Update documentation** when adding features
- **Follow existing code style** (2-space indentation, descriptive names)
- **Keep functions focused** (single responsibility principle)
- **Comment complex logic** (especially game balance formulas)

---

## 👨‍💻 Author

**Paycei**
- GitHub: [@Paycei](https://github.com/Paycei)

---

## 📊 Project Stats

![Lines of Code](https://img.shields.io/badge/lines%20of%20code-5500%2B-blue)
![Test Coverage](https://img.shields.io/badge/test%20coverage-87%25-brightgreen)
![Build Status](https://img.shields.io/badge/build-passing-success)

**Development Time**: ~3 months of active development
**Code Quality**: Heavily tested and documented
**Performance**: Optimized for 60+ FPS on average hardware

---

## 🙏 Acknowledgments

- **Raylib** - Amazing game development library
- **Nim Community** - Excellent programming language and ecosystem
- **Playtester Feedback** - Invaluable for balance and polish

---

**⭐ If you enjoy TopHat Shooter, please consider giving it a star on GitHub!**

---

**Last Updated**: Saturday, December 06, 2025  
**Version**: 2.0.0  
**Status**: Stable Release ✨
