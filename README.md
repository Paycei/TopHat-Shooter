# TopHat Shooter - Chaos Edition

A chaotic top-down shooter built with Nim and Raylib featuring shape-shifting bosses, aggressive AI, and maximum on-screen action!

## What's New in Chaos Edition

### Heavily Buffed Enemies
- **Triangles**: Now chase freely between dashes with erratic movement
- **Cubes**: Back away from players while shooting - true ranged enemies
- **Stars**: Reduced required hits (nerfed for better pacing)

### Shape-Shifting Bosses
Bosses transform between Circle/Cube/Triangle/Star forms every 8 seconds with unique abilities:
- Teleport bursts
- 360° shockwave attacks  
- Bullet storms
- Minion spawning
- Phase-specific attack patterns

### Maximum Chaos
- Overlapping enemy waves
- 2x faster spawn rates
- 20% faster projectiles
- Particle effects on everything
- More bullets, more enemies, more action!

## Building

```bash
nim c -d:release --opt:speed src/main.nim
```

Or use nimble:
```bash
nimble build
```

## Controls

- **WASD** - Move
- **Mouse/Space** - Shoot
- **F** - Toggle Auto-Shoot
- **E** - Place Wall
- **TAB** - Shop
- **ESC** - Pause/Menu

## Features

- 4 unique enemy types with distinct AI behaviors
- 4 boss types that shape-shift during battle
- 6 powerup types
- Particle system with hundreds of particles
- Shop upgrade system
- Defensive walls
- Wave-based spawning with overlapping chaos

## Requirements

- Nim compiler
- Raylib library

## Performance

Optimized for 60 FPS even with:
- 50+ enemies on screen
- 200+ bullets active
- 500+ particles rendering
- Multiple bosses simultaneously

Nim's performance makes the chaos smooth!

## License

MIT License - See LICENSE file

---

**Can you survive the chaos?**
