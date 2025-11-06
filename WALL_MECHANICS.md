# Wall Mechanics Reference

## Wall Properties
- **HP**: 10
- **Radius**: 25
- **Duration**: 30 seconds
- **Cost**: Purchased in shop (3 walls for 25 coins)
- **Placement**: Press E at mouse position

## Interaction Matrix

| Entity Type | Wall Collision | Bullet Through Wall | Damage to Wall | Damage to Entity |
|-------------|---------------|---------------------|----------------|------------------|
| **Player** | BLOCKED ❌ | YES ✓ | None | None |
| **Player Bullets** | Pass Through ✓ | N/A | None | N/A |
| **Enemies (All)** | BLOCKED ❌ | NO ❌ | 1 HP/sec | 1 HP/sec |
| **Enemy Bullets** | BLOCKED ❌ | NO ❌ | Full Bullet Damage | N/A |
| **Bosses** | BLOCKED ❌ | NO ❌ | 1 HP/sec | 1 HP/sec |

## Strategic Use Cases

### Defensive Positioning
```
    [Enemy]
       |
   [WALL] <-- Blocks bullets
       |
   [Player] <-- Safe zone
```
Player can shoot through wall, enemy bullets are blocked.

### Kiting Enemies
```
[Enemy] --> [WALL]
              /
         [Player]
```
Enemy takes 1 HP/sec trying to path through wall.

### Funnel Tactics
```
[WALL]     [WALL]
    \       /
     [Player]
        ^
     [Enemies]
```
Force enemies through narrow gap.

### Cube Counter
```
  [Player] ---> [Cube Enemy]
                   |
                [WALL] <-- Cube can't retreat
```
Pin kiting cubes against walls.

## Visual Feedback

- **Wall HP Bar**: Green/red indicator above wall
- **Collision Particles**: Brown particles when damaged
- **Transparency**: Walls fade as HP decreases (alpha channel)
- **Duration**: 30 second lifetime even if not damaged

## Tactical Notes

1. **Placement Matters**: Can't place too close to player or overlapping
2. **Finite Resource**: Must buy more walls in shop
3. **Enemies Pathfind**: Will go around if possible
4. **Bullet Sponge**: Each enemy bullet does 1 damage to wall
5. **Boss Shredder**: Bosses can destroy walls quickly with bullet storms
6. **Emergency Exits**: Don't trap yourself!

## Advanced Tactics

### The Bunker
Build walls in a square around yourself when overwhelmed. Enemy bullets blocked, you shoot out.

### The Corridor
Two parallel walls create a killzone. Enemies funnel through taking constant wall damage.

### The Shield
Place wall between you and boss during bullet storm phase. Buys time to reposition.

### The Maze
Multiple walls scattered create complex pathing. Enemies take longer to reach you.

## Particle Effects

- **Wall Placement**: 15 brown particles
- **Enemy Contact**: Small particles per second
- **Bullet Impact**: 4 particles per hit
- **Wall Destruction**: 20 brown particles

---

**Remember**: Player bullets IGNORE walls. You can always shoot out!
