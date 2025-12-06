# TopHat-Shooter Tests

## Running Tests

To run all tests:
```bash
cd D:\TopHat-Shooter
nim c -r tests/test_game.nim
```

To run tests with verbose output:
```bash
nim c -r --verbosity:2 tests/test_game.nim
```

## Test Coverage

### Player Tests (8 tests)
- Player creation and initialization
- Damage system
- Death mechanics
- Healing system
- Healing cap at max HP
- Power-up application
- Power-up detection
- Power-up level tracking

### Enemy Tests (2 tests)
- Enemy creation
- Enemy type property differences

### Bullet Tests (5 tests)
- Bullet creation
- Movement mechanics
- Lifetime system
- Off-screen detection
- Piercing bullet tracking

### Coin Tests (3 tests)
- Coin creation
- Boss coin size difference
- Value-based scaling

### Power-up Tests (5 tests)
- Name retrieval
- Level-based descriptions
- Legendary power-up generation
- Normal power-up generation
- Overcharge 3-level system

### Particle Tests (4 tests)
- Particle creation
- Movement
- Lifetime decay
- Death on timeout

### Wall Tests (3 tests)
- Wall creation
- Damage system
- Death detection

### Vector Math Tests (7 tests)
- Vector creation
- Length calculation
- Normalization
- Addition
- Subtraction
- Scalar multiplication
- Distance calculation

### Game Logic Tests (3 tests)
- Coin scaling mechanics
- Double Shot fire rate penalty
- Overcharge damage bonus levels

### Boss Mechanics Tests (2 tests)
- Boss coin collection requirement
- Wave completion logic

### Settings Tests (2 tests)
- FPS range validation
- Invalid FPS rejection

## Total: 44 Tests

All tests verify core game mechanics and ensure changes don't break existing functionality.
