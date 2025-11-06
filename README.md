# TopHat Shooter

## Building

```bash
nim c -d:release --opt:speed --passL:icono.res src/main.nim
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

## License

MIT License - See LICENSE file

---

**Can you survive the chaos?**
