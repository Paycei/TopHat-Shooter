# 🎩 TopHat Shooter

**Version 2.0** - A fast-paced, wave-based bullet hell shooter built with Nim and Raylib

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Nim](https://img.shields.io/badge/Nim-2.0.0+-blue.svg)](https://nim-lang.org/)

---

## ✨ Features

### 🎯 Game Modes
- **Wave-Based Mode** - Fight through progressive waves, earn upgrades, and face boss battles
- **Time Survival Mode** - Classic endless survival with continuous spawning

### 👾 Enemy Variety
11 unique enemy types with distinct AI behaviors and attack patterns:
- **Circle** - Standard chasers- **Cube** - Stationary shooters
- **Triangle** - Fast dash attackers
- **Star** - High HP tanks with dash attacks
- **Hexagon** - Teleporting chaos enemies
- **Cross** - Cross-shaped attack with visual warnings
- **Diamond** - Shoots projectiles while dashing
- **Octagon** - Ranged attackers with slow projectiles
- **Pentagon** - Single fast bullets, low fire rate
- **Trickster** - Fake warnings, unpredictable attacks
- **Phantom** - Teleports with fake clones

### 🐲 Boss Battles
4 boss types that shape-shift through multiple phases during battle:
- **Shooter Boss** - Shoots spirals of bullets
- **Summoner Boss** - Spawns waves of minions
- **Charger Boss** - Aggressive dashing attacks
- **Orbit Boss** - Fires orbiting projectiles

Each boss cycles through 4 forms: Circle → Cube → Triangle → Star

### 💪 Power-Up System
30+ unique power-ups across two rarity tiers:

**Common Power-Ups** (earned after waves):
- Double Shot, Multi-Shot, Rapid Fire
- Piercing Shots, Explosive Bullets, Homing Bullets
- Bullet Ricochet, Bullet Split
- Rotating Shield, Damage Zone
- Life Steal, Vampirism, Regeneration
- Speed Boost, Dodge Chance, Critical Hit
- Max Health, Bullet Damage, Bullet Speed, Bullet Size
- Lucky Coins, Wall Master
- Slow Field, Frost Shots, Poison Damage
- Chain Lightning, Thorns
- Rage, Berserker
- Auto-Shoot

**Legendary Power-Ups** (earned after boss defeats):
- Special high-tier upgrades unlocked only after defeating bosses

### 🛡️ Additional Features
- **6 Consumable Types** - Health, Coins, Speed, Invincibility, Fire Rate, Magnet
- **Shop System** - Purchase permanent upgrades with coins
- **Defensive Walls** - Place protective barriers (E key)
- **Particle System** - Hundreds of dynamic particles for visual effects- **Attack Warnings** - Visual indicators for enemy special attacks
- **Progressive Difficulty** - Enemies and bosses scale with your progress

---

## 🎯 Controls

| Key | Action |
|-----|--------|
| **WASD** | Move |
| **Mouse / Space** | Shoot |
| **F** | Toggle Auto-Shoot |
| **E** | Place Wall |
| **ESC** | Pause / Menu |

---

## 🚀 Installation & Running

### Prerequisites
- [Nim](https://nim-lang.org/) >= 2.0.0
- [Raylib](https://www.raylib.com/) (via naylib >= 5.0.0)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/TopHat-Shooter.git
   cd TopHat-Shooter   ```

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

**Optimized release build:**
```bash
nim c -d:release --opt:speed --passL:icono.res src/main.nim
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

---

## 🛠️ Development

Built with:
- **Language**: [Nim](https://nim-lang.org/) 2.0.0+
- **Graphics Library**: [naylib](https://github.com/planetis-m/naylib) (Raylib bindings)

---

## 📝 Version History

### v2.0 (Latest Release)
- ✅ Complete wave-based game mode
- ✅ 11 unique enemy types with distinct behaviors
- ✅ 4 boss types with 4-phase transformations
- ✅ 30+ power-ups (common and legendary tiers)
- ✅ Full shop and upgrade system
- ✅ Particle effects and visual polish
- ✅ Audio system integration
- ✅ Performance optimizations for smooth 60 FPS
- ✅ Comprehensive balance adjustments

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License - Copyright (c) 2025 Paycei
```

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!

---

## 👨‍💻 Author

**Paycei**

---

Experience intense bullet hell action, strategic upgrades, and epic boss battles. Every run is different with procedural wave generation and randomized power-ups. Test your skills and see how long you can survive!

---

**⭐ If you enjoy TopHat Shooter, please consider giving it a star!**
