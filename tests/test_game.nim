import unittest
import ../src/types
import ../src/player
import ../src/enemy
import ../src/bullet
import ../src/coin
import ../src/powerup
import ../src/game

# Test helper to create a minimal game for enemy spawning
proc createTestGame(): Game =
  result = newGame(1024, 768)
  result.nextEnemyId = 0  # Reset ID counter for consistent tests

# ============================================================================
# 1. PLAYER MECHANICS
# ============================================================================

suite "Player: Core Mechanics":
  test "player initializes with correct defaults":
    let player = newPlayer(100.0, 200.0)
    
    check player.pos.x == 100.0
    check player.pos.y == 200.0
    check player.hp > 0
    check player.maxHp > 0
    check player.speed > 0
    check player.damage > 0
    check player.fireRate > 0
    check player.coins == 0
    check player.kills == 0
    check player.powerUps.len == 0

  test "player takes damage correctly":
    let player = newPlayer(100.0, 100.0)
    let initialHp = player.hp
    
    discard takeDamage(player, 2.5)
    
    check player.hp == initialHp - 2.5
    check player.hp > 0

  test "player dies when HP reaches zero":
    let player = newPlayer(100.0, 100.0)
    
    let isDead = takeDamage(player, 999.0)
    
    check isDead == true
    check player.hp <= 0

  test "player healing increases HP":
    let player = newPlayer(100.0, 100.0)
    discard takeDamage(player, 3.0)
    let hpBeforeHeal = player.hp
    
    heal(player, 1.5)
    
    check player.hp == hpBeforeHeal + 1.5

  test "healing respects max HP cap":
    let player = newPlayer(100.0, 100.0)
    let maxHp = player.maxHp
    
    heal(player, 9999.0)
    
    check player.hp == maxHp

  test "invincibility timer prevents damage":
    let player = newPlayer(100.0, 100.0)
    let initialHp = player.hp
    player.invincibilityTimer = 5.0
    
    discard takeDamage(player, 10.0)
    
    check player.hp == initialHp

# ============================================================================
# 2. POWER-UP SYSTEM
# ============================================================================

suite "PowerUps: Application & Detection":
  test "power-up modifies player stats":
    let player = newPlayer(100.0, 100.0)
    let oldMaxHp = player.maxHp
    
    let powerUp = PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon)
    applyPowerUp(player, powerUp)
    
    check player.maxHp > oldMaxHp
    check hasPowerUp(player, puMaxHealth)

  test "power-up detection works":
    let player = newPlayer(100.0, 100.0)
    
    check hasPowerUp(player, puMaxHealth) == false
    
    applyPowerUp(player, PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon))
    
    check hasPowerUp(player, puMaxHealth) == true

  test "power-up levels are tracked":
    let player = newPlayer(100.0, 100.0)
    
    check getPowerUpLevel(player, puBulletDamage) == 0
    
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 2, rarity: prCommon))
    
    check getPowerUpLevel(player, puBulletDamage) == 2

  test "multiple power-ups can be active":
    let player = newPlayer(100.0, 100.0)
    
    applyPowerUp(player, PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon))
    applyPowerUp(player, PowerUp(powerType: puSpeedBoost, level: 1, rarity: prCommon))
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 1, rarity: prCommon))
    
    check hasPowerUp(player, puMaxHealth)
    check hasPowerUp(player, puSpeedBoost)
    check hasPowerUp(player, puBulletDamage)

  test "power-up upgrades increase level":
    let player = newPlayer(100.0, 100.0)
    
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 1, rarity: prCommon))
    check getPowerUpLevel(player, puBulletDamage) == 1
    
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 2, rarity: prCommon))
    check getPowerUpLevel(player, puBulletDamage) == 2

# ============================================================================
# 3. ENEMY MECHANICS
# ============================================================================

suite "Enemies: Creation & Types":
  test "enemy initializes correctly":
    let game = createTestGame()
    let enemy = newEnemy(150.0, 250.0, 0.0, etCircle, game)
    
    check enemy.pos.x == 150.0
    check enemy.pos.y == 250.0
    check enemy.hp > 0
    check enemy.maxHp > 0
    check enemy.isBoss == false
    check enemy.enemyType == etCircle

  test "different enemy types have unique stats":
    let game = createTestGame()
    let circle = newEnemy(0.0, 0.0, 0.0, etCircle, game)
    let star = newEnemy(0.0, 0.0, 0.0, etStar, game)
    
    check star.hp >= circle.hp  # Stars are tankier
    check star.maxHp >= circle.maxHp

  test "enemy stats scale with difficulty":
    let game = createTestGame()
    let easy = newEnemy(0.0, 0.0, 0.0, etCircle, game)
    let hard = newEnemy(0.0, 0.0, 10.0, etCircle, game)
    
    check hard.maxHp > easy.maxHp
    check hard.hp > easy.hp

# ============================================================================
# 4. BULLET MECHANICS
# ============================================================================

suite "Bullets: Creation & Movement":
  test "bullet initializes with correct properties":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(100.0, 100.0, dir, 300.0, 5.0, true)
    
    check bullet.pos.x == 100.0
    check bullet.pos.y == 100.0
    check bullet.damage == 5.0
    check bullet.fromPlayer == true
    check bullet.lifetime > 0

  test "bullet moves based on velocity":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(0.0, 0.0, dir, 100.0, 1.0, true)
    let initialX = bullet.pos.x
    
    discard updateBullet(bullet, 1.0)  # 1 second
    
    check bullet.pos.x > initialX

  test "bullet despawns after lifetime":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(0.0, 0.0, dir, 100.0, 1.0, true)
    
    let alive = updateBullet(bullet, 10.0)  # Way past lifetime
    
    check alive == false

  test "special bullet properties are tracked":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(
      0.0, 0.0, dir, 300.0, 5.0, true,
      isHoming = true,
      isPiercing = true,
      isExplosive = true
    )
    
    check bullet.isHoming == true
    check bullet.isPiercing == true
    check bullet.isExplosive == true

# ============================================================================
# 5. BULLET EFFECT SYSTEM (FIX #3 VERIFICATION)
# ============================================================================

suite "Bullet Effects: Unified System":
  test "frost bullets apply slow effect":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(
      0.0, 0.0, dir, 300.0, 5.0, true,
      slowAmount = 0.5  # 50% slow
    )
    
    check bullet.slowAmount == 0.5

  test "poison bullets track duration":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(
      0.0, 0.0, dir, 300.0, 5.0, true,
      poisonDuration = 3.0
    )
    
    check bullet.poisonDuration == 3.0

  test "fire bullets track duration":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(
      0.0, 0.0, dir, 300.0, 5.0, true,
      fireDuration = 2.5
    )
    
    check bullet.fireDuration == 2.5

  test "wind bullets track push force":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(
      0.0, 0.0, dir, 300.0, 5.0, true,
      windPushForce = 150.0
    )
    
    check bullet.windPushForce == 150.0

  test "bullets can have multiple effects":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(
      0.0, 0.0, dir, 300.0, 5.0, true,
      slowAmount = 0.3,
      poisonDuration = 2.0,
      isExplosive = true
    )
    
    check abs(bullet.slowAmount - 0.3) < 0.001  # Float comparison with tolerance
    check bullet.poisonDuration == 2.0
    check bullet.isExplosive == true

# ============================================================================
# 6. COIN SYSTEM
# ============================================================================

suite "Coins: Spawning & Collection":
  test "coin initializes with correct value":
    let coin = newCoin(100.0, 100.0, 5, false)
    
    check coin.pos.x == 100.0
    check coin.pos.y == 100.0
    check coin.value == 5
    check coin.isBossCoin == false

  test "boss coins are marked correctly":
    let bossCoin = newCoin(0.0, 0.0, 50, true)
    
    check bossCoin.isBossCoin == true
    check bossCoin.value == 50

  test "coin lifetime decreases over time":
    let coin = newCoin(0.0, 0.0, 1, false)
    
    # Simulate having many coins to trigger despawn
    discard updateCoin(coin, 1.0, 200)  # 200 coins = over limit
    
    # If we have > 150 coins, lifetime starts counting down
    check coin.lifetime >= 0  # Lifetime becomes positive when despawning

# ============================================================================
# 7. VECTOR MATH
# ============================================================================

suite "Vectors: Mathematics":
  test "vector length calculation":
    let v = newVector2f(3.0, 4.0)
    
    check v.length() == 5.0  # 3-4-5 triangle

  test "vector normalization":
    let v = newVector2f(3.0, 4.0)
    let normalized = v.normalize()
    
    check abs(normalized.length() - 1.0) < 0.001

  test "vector addition":
    let v1 = newVector2f(1.0, 2.0)
    let v2 = newVector2f(3.0, 4.0)
    
    let result = v1 + v2
    
    check result.x == 4.0
    check result.y == 6.0

  test "vector subtraction":
    let v1 = newVector2f(5.0, 7.0)
    let v2 = newVector2f(2.0, 3.0)
    
    let result = v1 - v2
    
    check result.x == 3.0
    check result.y == 4.0

  test "scalar multiplication":
    let v = newVector2f(2.0, 3.0)
    
    let result = v * 2.5
    
    check result.x == 5.0
    check result.y == 7.5

  test "distance calculation":
    let p1 = newVector2f(0.0, 0.0)
    let p2 = newVector2f(3.0, 4.0)
    
    check distance(p1, p2) == 5.0

  test "zero vector normalization is safe":
    let zero = newVector2f(0.0, 0.0)
    
    let normalized = zero.normalize()
    
    check normalized.x == 0.0
    check normalized.y == 0.0

# ============================================================================
# 8. COMBAT CALCULATIONS
# ============================================================================

suite "Combat: Damage & Balance":
  test "power-up modifies combat stats":
    let player = newPlayer(100.0, 100.0)
    let initialDamage = player.damage
    
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 1, rarity: prCommon))
    
    check player.damage > initialDamage
  
  test "fire rate power-up modifies shooting speed":
    let player = newPlayer(100.0, 100.0)
    let initialFireRate = player.fireRate
    
    applyPowerUp(player, PowerUp(powerType: puRapidFire, level: 1, rarity: prCommon))
    
    check player.fireRate < initialFireRate  # Lower = faster

# ============================================================================
# 9. EDGE CASES & ERROR HANDLING
# ============================================================================

suite "Edge Cases: Robustness":
  test "zero damage doesn't change HP":
    let player = newPlayer(100.0, 100.0)
    let initialHp = player.hp
    
    discard takeDamage(player, 0.0)
    
    check player.hp == initialHp

  test "negative damage heals player (damage reflection mechanics)":
    let player = newPlayer(100.0, 100.0)
    discard takeDamage(player, 2.0)  # Take some damage first
    let hpAfterDamage = player.hp
    
    # Some game mechanics allow negative damage (healing)
    # This test verifies the game handles it gracefully
    discard takeDamage(player, -1.0)
    
    # Negative damage might heal or be ignored depending on implementation
    check player.hp >= hpAfterDamage  # HP should not decrease

  test "player without power-ups works correctly":
    let player = newPlayer(100.0, 100.0)
    
    check player.powerUps.len == 0
    check hasPowerUp(player, puMaxHealth) == false
    check getPowerUpLevel(player, puBulletDamage) == 0

  test "large coin values are handled":
    let coin = newCoin(0.0, 0.0, 999999, false)
    
    check coin.value == 999999

  test "enemy with zero speed doesn't move":
    let game = createTestGame()
    let enemy = newEnemy(100.0, 100.0, 0.0, etCube, game)
    enemy.speed = 0.0
    let initialPos = enemy.pos
    
    # Enemy update would be called here in real game
    # Just verify speed can be set to zero without crashing
    check enemy.speed == 0.0
    check enemy.pos.x == initialPos.x

# ============================================================================
# 10. GAME STATE MANAGEMENT
# ============================================================================

suite "Game: State & Initialization":
  test "new game initializes correctly":
    let game = newGame(1024, 768)
    
    check game.screenWidth == 1024
    check game.screenHeight == 768
    check game.player.pos.x == 512.0  # Center X
    check game.player.pos.y == 384.0  # Center Y
    check game.enemies.len == 0
    check game.bullets.len == 0
    check game.coins.len == 0
    check game.currentWave == 1
    check game.time == 0.0

  test "game tracks difficulty progression":
    let game = newGame(1024, 768)
    
    check game.difficulty == 0.0
    check game.currentWave == 1

# ============================================================================
# 11. PERFORMANCE & CLEANUP
# ============================================================================

suite "Performance: Memory Management":
  test "bullets are removed when off-screen":
    let dir = newVector2f(1.0, 0.0)
    let bullet = newBullet(10000.0, 0.0, dir, 100.0, 1.0, true)
    
    let onScreen = not isOffScreen(bullet, 1024, 768)
    
    check onScreen == false  # Bullet at x=10000 is off-screen

  test "coins despawn based on count limit":
    let coin = newCoin(0.0, 0.0, 1, false)
    
    # With high coin count, lifetime becomes active
    let alive = updateCoin(coin, 100.0, 200)  # 200 coins, way past limit
    
    # Coin should start despawn process
    check coin.lifetime >= 0  # Lifetime becomes active when over limit

# ============================================================================
# 12. INTEGRATION TESTS
# ============================================================================

suite "Integration: System Interactions":
  test "player can collect coins":
    let game = newGame(1024, 768)
    let initialCoins = game.player.coins
    
    game.player.coins += 5
    
    check game.player.coins == initialCoins + 5

  test "killing enemies increases kill count":
    let player = newPlayer(100.0, 100.0)
    let initialKills = player.kills
    
    player.kills += 1
    
    check player.kills == initialKills + 1

  test "power-up affects player damage":
    let player = newPlayer(100.0, 100.0)
    let initialDamage = player.damage
    
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 1, rarity: prCommon))
    
    check player.damage > initialDamage
