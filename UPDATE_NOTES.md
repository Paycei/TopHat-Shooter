# TopHat Shooter - Update Summary

## Major Changes

### 1. **Player Nerfs** (Difficulty Increased)
- Base HP: 3 → 2
- Move Speed: 200 → 180
- Fire Rate: 0.3s → 0.4s (slower shooting)
- Player size now scales with max HP (grows as you upgrade health)

### 2. **Coin System**
- Enemies no longer give coins instantly
- Coins drop on the ground and must be collected by touching them
- Boss coins are worth 15, Star enemies 5, normal enemies 1
- New `coin.nim` file handles coin drops
- Coin magnet powerup pulls coins toward player

### 3. **Enemy Types**
- **Circles** (Red/Orange/Maroon): Normal chasers, most common
- **Cubes** (Purple): Stationary/slow enemies that shoot at you
- **Triangles** (Pink): Fast dash attackers, higher damage
- **Stars** (Gold): Rare, slow, require specific number of HITS (not damage)
  - Display hit counter on the enemy
  - Spawn more frequently in late game

### 4. **Boss System**
- New boss appears every 60 seconds
- 4 Different boss types that cycle:
  - **Shooter** (Dark Purple): Shoots spiral patterns of bullets
  - **Summoner** (Dark Green): Spawns multiple minions
  - **Charger** (Dark Blue): Performs fast dash attacks
  - **Orbit** (Violet): Creates orbiting projectiles
- Bosses deal **continuous damage** on contact (starts at 2 HP/0.5s)
- Boss damage scales with difficulty
- Bosses have health bars

### 5. **Consumable System Expanded**
New consumable types (dropped by enemies at 15% chance, higher for bosses/stars):
- **+ (Green)**: Health restore
- **$ (Gold)**: 5 bonus coins
- **S (Cyan)**: Speed boost for 5 seconds (50% faster)
- **! (Magenta)**: Invincibility for 3 seconds
- **F (Orange)**: Fire rate boost for 8 seconds (50% faster shooting)
- **M (Purple)**: Coin magnet for 10 seconds (pulls coins from far away)

### 6. **Exponential Scaling**
- **Enemy stats**: Scale exponentially with time (difficulty = time/10)
  - HP: base * 1.15^difficulty
  - Speed: increases linearly
  - Size: grows with difficulty
- **Shop prices**: base_cost * 1.4^times_bought
- **Damage upgrades**: Exponential scaling (0.3 * 1.1^bought)
- Enemy spawn rate increases exponentially

### 7. **Main Menu**
- New main menu with:
  - Start Game
  - Help (instructions)
  - Quit
- Help screen explains all controls, enemy types, and powerups
- Press ESC from game over to return to menu

### 8. **Visual Improvements**
- Player flashes during invincibility
- Player has green ring during speed boost
- Coins pulse for visibility
- Stars drawn as actual star shapes
- Cubes drawn as squares
- Triangles drawn as triangles
- Active powerup timers shown in UI
- Hit counter displayed on Star enemies

## Files Modified
- `types.nim`: Added new types for enemies, bosses, consumables, coins
- `player.nim`: Nerfed stats, added powerup timers and effects, size scaling
- `enemy.nim`: Complete rewrite with enemy types and boss behaviors
- `game.nim`: Updated game loop with new mechanics
- `consumable.nim`: Expanded with multiple powerup types
- `shop.nim`: Exponential cost scaling
- `main.nim`: Added menu system
- `bullet.nim`: Minor updates for compatibility
- `coin.nim`: NEW FILE - handles dropped coins

## Compilation
No changes to compilation process. Use your existing build setup:
```
nim c -r src/main.nim
```

## Balance Notes
- Early game is harder due to player nerfs
- Mid-late game scaling is smoother and more challenging
- Multiple enemy types require different strategies
- Powerups provide meaningful temporary boosts
- Shop upgrades feel more impactful with exponential scaling
- Boss fights are more engaging with continuous damage
