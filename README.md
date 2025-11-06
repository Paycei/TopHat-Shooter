# TopHat-Shooter

A 2D top-down shooter game written in Nim using raylib.

## Features

- **Player Movement**: Move with WASD keys
- **Shooting**: Aim and shoot toward mouse direction (Left Click or Space)
- **Auto-Shoot**: Toggle with F key to automatically shoot at nearby enemies
- **Health System**: Start with 3 HP, lose HP when enemies touch you
- **Progressive Difficulty**: Enemies get larger, faster, and stronger over time
- **Consumables**: 10% chance for enemies to drop HP packs or coin bundles
- **Shop System**: Press Tab to buy upgrades with coins
  - Damage increase
  - Fire rate increase
  - Move speed increase
  - Max health increase
  - Bullet speed increase
  - Deployable walls
- **Wall Placement**: Press E to place walls (if you have any purchased)
  - Enemies cannot pass through walls
  - Player bullets pass through walls
  - Enemy bullets are blocked by walls
- **Boss Enemies**: Spawn every minute with special abilities
  - Shoot projectiles
  - Spawn minions
- **Game Over**: When HP reaches 0, view your stats and restart

## Controls

- **WASD**: Move player
- **Left Mouse / Space**: Shoot
- **F**: Toggle auto-shoot
- **Tab**: Open/close shop
- **E**: Place wall (if available)
- **ESC**: Pause/unpause game
- **R**: Restart (on game over screen)

## Requirements

- Nim compiler (>= 2.0.0)
- naylib package (>= 5.0.0)

## Installation

1. Install Nim from https://nim-lang.org/
2. Install naylib:
   ```bash
   nimble install naylib
   ```

## Building and Running

### Run directly:
```bash
nimble run
```

### Build release version:
```bash
nimble build
./main
```

Or manually:
```bash
nim c -r src/main.nim
```

## Project Structure

```
TopHat-Shooter/
├── tophat_shooter.nimble    # Project configuration
├── README.md                # This file
└── src/
    ├── main.nim            # Entry point and main game loop
    ├── game.nim            # Game logic and state management
    ├── types.nim           # Type definitions and vector math
    ├── player.nim          # Player logic
    ├── enemy.nim           # Enemy logic and spawning
    ├── bullet.nim          # Bullet physics and collision
    ├── consumable.nim      # Health/coin pickups
    ├── wall.nim            # Wall placement and logic
    └── shop.nim            # Shop UI and upgrade system
```

## Gameplay Tips

1. **Use Auto-Shoot**: Toggle auto-shoot with F when overwhelmed
2. **Manage Resources**: Spend coins wisely in the shop
3. **Strategic Walls**: Place walls to create chokepoints
4. **Boss Preparation**: Save coins for upgrades before boss spawns
5. **Collect Consumables**: Don't forget to pick up health and coins
6. **Move Constantly**: Keep moving to avoid being surrounded

## Technical Details

- Fixed timestep game loop
- Circle-based collision detection
- Progressive difficulty scaling
- Dynamic enemy spawning system
- Persistent upgrade system per run
