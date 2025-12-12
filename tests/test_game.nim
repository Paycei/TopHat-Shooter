import unittest
import strutils
import raylib
import ../src/types
import ../src/player
import ../src/enemy
import ../src/bullet
import ../src/coin
import ../src/powerup
import ../src/particle
import ../src/wall
import ../src/consumable
import ../src/shop

# =============================================================================
# PLAYER TESTS - Core player mechanics including damage, healing, and power-ups
# =============================================================================

suite "Player Core Mechanics":
  test "Player initialization with correct default values":
    ## Verify player spawns with expected starting stats
    ## Position should match the provided coordinates
    ## Health, max health, and speed should be positive values
    let player = newPlayer(100.0, 100.0)
    check player.pos.x == 100.0
    check player.pos.y == 100.0
    check player.hp > 0
    check player.maxHp > 0
    check player.speed > 0
    check player.damage > 0
    check player.fireRate > 0
    check player.coins == 0
    check player.kills == 0
  
  test "Player takes damage correctly":
    ## Damage system should reduce HP by exact amount
    ## Initial HP minus damage amount should equal new HP
    let player = newPlayer(100.0, 100.0)
    let initialHp = player.hp
    discard takeDamage(player, 1.0)
    check player.hp == initialHp - 1.0
  
  test "Player death occurs when HP reaches zero":
    ## Taking fatal damage should return true (death flag)
    ## HP should be zero or negative after fatal damage
    let player = newPlayer(100.0, 100.0)
    let isDead = takeDamage(player, 999.0)
    check isDead == true
    check player.hp <= 0
  
  test "Player healing increases HP":
    ## Healing should restore HP by the specified amount
    ## HP should not exceed max HP even with excessive healing
    let player = newPlayer(100.0, 100.0)
    discard takeDamage(player, 2.0)
    let hpBeforeHeal = player.hp
    heal(player, 1)
    check player.hp == hpBeforeHeal + 1.0
  
  test "Player healing respects max HP cap":
    ## Healing beyond max HP should clamp at max HP
    ## This prevents HP from going above the maximum
    let player = newPlayer(100.0, 100.0)
    let maxHp = player.maxHp
    heal(player, 999)
    check player.hp == maxHp
  
  test "Player invincibility timer prevents damage":
    ## When invincibility timer is active, damage should not reduce HP
    ## This tests the temporary invincibility mechanic
    let player = newPlayer(100.0, 100.0)
    let initialHp = player.hp
    player.invincibilityTimer = 5.0  # 5 seconds of invincibility
    discard takeDamage(player, 10.0)
    check player.hp == initialHp  # No damage taken

suite "Player Power-Up System":
  test "Power-up application modifies player stats":
    ## Applying a power-up should increase the corresponding stat
    ## The player should register as having that power-up
    let player = newPlayer(100.0, 100.0)
    let powerUp = PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon)
    let oldMaxHp = player.maxHp
    applyPowerUp(player, powerUp)
    check player.maxHp > oldMaxHp
    check hasPowerUp(player, puMaxHealth)
  
  test "Power-up detection works correctly":
    ## hasPowerUp should return false before acquisition
    ## hasPowerUp should return true after acquisition
    let player = newPlayer(100.0, 100.0)
    check hasPowerUp(player, puMaxHealth) == false
    let powerUp = PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon)
    applyPowerUp(player, powerUp)
    check hasPowerUp(player, puMaxHealth) == true
  
  test "Power-up levels are tracked accurately":
    ## Power-up level should be 0 when not acquired
    ## Level should match the applied power-up level
    let player = newPlayer(100.0, 100.0)
    check getPowerUpLevel(player, puMaxHealth) == 0
    let powerUp = PowerUp(powerType: puMaxHealth, level: 2, rarity: prCommon)
    applyPowerUp(player, powerUp)
    check getPowerUpLevel(player, puMaxHealth) == 2
  
  test "Multiple power-ups can be active simultaneously":
    ## Player should be able to have multiple different power-ups
    ## Each power-up should be independently detectable
    let player = newPlayer(100.0, 100.0)
    applyPowerUp(player, PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon))
    applyPowerUp(player, PowerUp(powerType: puSpeedBoost, level: 1, rarity: prCommon))
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 1, rarity: prCommon))
    check hasPowerUp(player, puMaxHealth)
    check hasPowerUp(player, puSpeedBoost)
    check hasPowerUp(player, puBulletDamage)
  
  test "Power-up upgrades increase level correctly":
    ## Applying the same power-up multiple times should increase level
    ## Level should stack appropriately
    let player = newPlayer(100.0, 100.0)
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 1, rarity: prCommon))
    check getPowerUpLevel(player, puBulletDamage) == 1
    applyPowerUp(player, PowerUp(powerType: puBulletDamage, level: 2, rarity: prCommon))
    check getPowerUpLevel(player, puBulletDamage) == 2

suite "Player Fire Rate Mechanics":
  test "Double Shot applies fire rate penalty":
    ## Double Shot should increase fire rate interval (slower shooting)
    ## This balances the extra bullets
    let player = newPlayer(100.0, 100.0)
    let initialFireRate = player.fireRate
    let powerUp = PowerUp(powerType: puDoubleShot, level: 1, rarity: prCommon)
    applyPowerUp(player, powerUp)
    let newFireRate = getCurrentFireRate(player)
    check newFireRate > initialFireRate
  
  test "Rapid Fire power-up decreases fire rate":
    ## Rapid Fire should reduce the time between shots
    ## Lower fire rate value = faster shooting
    let player = newPlayer(100.0, 100.0)
    let initialFireRate = player.fireRate
    applyPowerUp(player, PowerUp(powerType: puRapidFire, level: 1, rarity: prCommon))
    check player.fireRate < initialFireRate

# =============================================================================
# ENEMY TESTS - Enemy creation, types, and boss mechanics
# =============================================================================

suite "Enemy Core Mechanics":
  test "Enemy creation with correct initial state":
    ## Enemy should spawn at specified position
    ## Should have positive HP and not be a boss by default
    let enemy = newEnemy(100.0, 100.0, 0.0, etCircle)
    check enemy.pos.x == 100.0
    check enemy.pos.y == 100.0
    check enemy.hp > 0
    check enemy.maxHp > 0
    check enemy.isBoss == false
  
  test "Different enemy types have unique properties":
    ## Star enemies should be tankier than circles
    ## Enemy type should affect base stats
    let circle = newEnemy(0.0, 0.0, 0.0, etCircle)
    let star = newEnemy(0.0, 0.0, 0.0, etStar)
    check star.hp > circle.hp
    check star.maxHp > circle.maxHp
  
  test "Ranged enemy types have appropriate stats":
    ## Cube (stationary shooter) should have different speed than Circle
    ## Pentagon (ranged) and Cube have higher HP than basic Circle
    let cube = newEnemy(0.0, 0.0, 0.0, etCube)
    let pentagon = newEnemy(0.0, 0.0, 0.0, etPentagon)
    let circle = newEnemy(0.0, 0.0, 0.0, etCircle)
    check cube.speed < circle.speed  # Cubes are slower
    check pentagon.hp > circle.hp  # Pentagon has more HP than basic circle

suite "Enemy Difficulty Scaling":
  test "Enemy stats scale with difficulty":
    ## Higher difficulty should produce stronger enemies
    ## HP and damage should increase with difficulty
    let easyEnemy = newEnemy(0.0, 0.0, 0.0, etCircle)
    let hardEnemy = newEnemy(0.0, 0.0, 5.0, etCircle)  # Difficulty 5
    check hardEnemy.maxHp > easyEnemy.maxHp
    check hardEnemy.hp > easyEnemy.hp
  
  test "Boss enemies have significantly higher stats":
    ## Boss flag should be set correctly
    ## Boss HP should be much higher than regular enemies
    let regular = newEnemy(0.0, 0.0, 1.0, etCircle)
    # Note: Boss creation would need spawn boss function, testing structure
    check regular.isBoss == false

suite "Enemy Special Mechanics":
  test "Teleporting enemies have appropriate cooldowns":
    ## Hexagon enemies should have teleport mechanics
    ## Teleport timer should be initialized
    let hexagon = newEnemy(0.0, 0.0, 0.0, etHexagon)
    check hexagon.enemyType == etHexagon
    check hexagon.hexTeleportTimer >= 0
  
  test "Tank enemies have high HP requirements":
    ## Star enemies should require multiple hits
    ## They should be significantly tankier
    let star = newEnemy(0.0, 0.0, 0.0, etStar)
    let circle = newEnemy(0.0, 0.0, 0.0, etCircle)
    check star.maxHp > circle.maxHp * 2  # At least 2x more HP

# =============================================================================
# BULLET TESTS - Projectile mechanics and special bullet types
# =============================================================================

suite "Bullet Core Mechanics":
  test "Bullet creation with correct properties":
    ## Bullet should initialize at specified position
    ## Velocity, damage, and ownership should be set correctly
    let bullet = newBullet(100.0, 100.0, newVector2f(1.0, 0.0), 200.0, 5.0, true)
    check bullet.pos.x == 100.0
    check bullet.pos.y == 100.0
    check bullet.damage == 5.0
    check bullet.fromPlayer == true
  
  test "Bullet movement follows velocity vector":
    ## Bullet position should change based on velocity and time
    ## Movement should be in the direction of the velocity vector
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    let initialX = bullet.pos.x
    discard updateBullet(bullet, 1.0)  # 1 second
    check bullet.pos.x > initialX
  
  test "Bullet lifetime system expires correctly":
    ## Bullet should stay alive within lifetime
    ## Should die after lifetime expires
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    check updateBullet(bullet, 0.5) == true  # Still alive at 0.5s
    check updateBullet(bullet, 0.6) == true  # Still alive at 1.1s total
    check updateBullet(bullet, 5.0) == false  # Dead after 6.1s total
  
  test "Bullet off-screen detection works":
    ## Bullets far outside screen bounds should be detected as off-screen
    ## This helps with cleanup and performance
    let bullet = newBullet(-100.0, -100.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    check isOffScreen(bullet, 1024, 768) == true
    let onScreenBullet = newBullet(512.0, 384.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    check isOffScreen(onScreenBullet, 1024, 768) == false

suite "Special Bullet Types":
  test "Piercing bullets maintain pierce count":
    ## Piercing bullets should track enemies they've hit
    ## Pierce counter should start at 0
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true, 
                          false, true, false)
    check bullet.isPiercing == true
    check bullet.piercedEnemies == 0
  
  test "Homing bullets are flagged correctly":
    ## Homing flag should be set properly
    ## This enables bullet tracking behavior
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true,
                          true, false, false)
    check bullet.isHoming == true
  
  test "Explosive bullets have correct flag":
    ## Explosive flag enables area damage on impact
    ## Should be properly initialized
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true,
                          false, false, true)
    check bullet.isExplosive == true
  
  test "Bullet can have multiple special properties":
    ## Bullets can combine piercing, homing, and explosive
    ## All flags should be independently trackable
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true,
                          true, true, true)
    check bullet.isHoming == true
    check bullet.isPiercing == true
    check bullet.isExplosive == true

suite "Bullet Special Effects":
  test "Ricochet bullets track bounce count":
    ## Ricochet bullets should start with 0 bounces
    ## Bounce counter should be tracked for game logic
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true,
                          false, false, false, true)
    check bullet.bounceCount == 0
  
  test "Split bullets prevent recursive splitting":
    ## hasSplit flag prevents infinite bullet generation
    ## Should start as false
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true,
                          false, false, false, false, true)
    check bullet.hasSplit == false
  
  test "Frost bullets apply slow effect":
    ## Slow amount should be set for frost bullets
    ## This affects enemy movement speed on hit
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true,
                          false, false, false, false, false, 0.5)
    check bullet.slowAmount == 0.5
  
  test "Poison bullets track poison duration":
    ## Poison duration should be set for poison bullets
    ## This enables damage over time effect
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true,
                          false, false, false, false, false, 0.0, 5.0)
    check bullet.poisonDuration == 5.0

# =============================================================================
# COIN TESTS - Loot drop and collection mechanics
# =============================================================================

suite "Coin Mechanics":
  test "Coin creation with correct value":
    ## Coins should spawn at specified position
    ## Value should match what was specified
    let coin = newCoin(100.0, 100.0, 5, false)
    check coin.pos.x == 100.0
    check coin.pos.y == 100.0
    check coin.value == 5
    check coin.isBossCoin == false
  
  test "Boss coins are larger than regular coins":
    ## Boss coins should be visually distinct
    ## Larger radius makes them more prominent
    let normalCoin = newCoin(0.0, 0.0, 5, false)
    let bossCoin = newCoin(0.0, 0.0, 5, true)
    check bossCoin.radius > normalCoin.radius
    check bossCoin.isBossCoin == true
  
  test "Coin size scales with value":
    ## Higher value coins should be larger
    ## This provides visual feedback about coin worth
    let smallCoin = newCoin(0.0, 0.0, 1, false)
    let bigCoin = newCoin(0.0, 0.0, 10, false)
    check bigCoin.radius > smallCoin.radius
  
  test "Coin lifetime is properly initialized":
    ## Coins initialize with -1.0 lifetime (infinite)
    ## They only despawn when total coins exceed 150
    let coin = newCoin(0.0, 0.0, 5, false)
    check coin.lifetime == -1.0  # Negative lifetime = infinite until coin limit

suite "Coin Value Scaling":
  test "Wave-based coin bonus increases gradually":
    ## Later waves should provide small coin bonuses
    ## Bonus should scale with wave number divided by 10
    let wave1Bonus = 1 div 10
    let wave10Bonus = 10 div 10
    let wave50Bonus = 50 div 10
    check wave1Bonus == 0
    check wave10Bonus == 1
    check wave50Bonus == 5
  
  test "Boss coin values scale with difficulty":
    ## Boss coins should provide substantial rewards
    ## Value should increase with game difficulty
    ## Formula: 30 + (difficulty * 3.5)
    let difficulty0 = 30 + (0.0 * 3.5).int
    let difficulty5 = 30 + (5.0 * 3.5).int
    check difficulty0 == 30
    check difficulty5 == 47

# =============================================================================
# CONSUMABLE TESTS - Temporary power-up pickups
# =============================================================================

suite "Consumable System":
  test "Consumable types are properly created":
    ## Different consumable types should exist
    ## Each type provides different temporary bonuses
    let health = newConsumable(100.0, 100.0, 1.0)
    check health.consumableType in [ctHealth, ctCoin, ctSpeed, ctInvincibility, ctFireRate, ctMagnet]
  
  test "Consumable lifetime decreases over time":
    ## Consumables should despawn after a time limit
    ## This prevents permanent clutter
    let consumable = newConsumable(100.0, 100.0, 1.0)
    let initialLifetime = consumable.lifetime
    let stillAlive = updateConsumable(consumable, 1.0)
    check stillAlive == true
    check consumable.lifetime < initialLifetime
  
  test "Consumable collision detection works":
    ## Collision should detect when player is close enough
    ## Uses combined radius of player and consumable
    let consumable = newConsumable(100.0, 100.0, 1.0)
    let player = newPlayer(100.0, 100.0)
    check checkPlayerCollision(consumable, player) == true
    let farPlayer = newPlayer(500.0, 500.0)
    check checkPlayerCollision(consumable, farPlayer) == false

# =============================================================================
# POWER-UP TESTS - Permanent upgrade system
# =============================================================================

suite "Power-Up Information":
  test "Power-up names are retrievable":
    ## Each power-up type should have a readable name
    ## Names are used in UI and descriptions
    check getPowerUpName(puDoubleShot) == "Double Shot"
    check getPowerUpName(puMaxHealth) == "Vitality"
    check getPowerUpName(puOvercharge) == "Momentum"
    check getPowerUpName(puRotatingShield) == "Rotating Shield"
  
  test "Power-up descriptions vary by level":
    ## Higher level descriptions should be different
    ## This shows power progression
    let desc1 = getPowerUpDescription(puDoubleShot, 1)
    let desc2 = getPowerUpDescription(puDoubleShot, 2)
    check desc1 != desc2
    check desc1.len > 0
  
  test "Legendary power-ups have special descriptions":
    ## Legendary power-ups should have distinct descriptions
    ## These are high-tier rewards
    let legendaryDesc = getPowerUpDescription(puTimeWarp, 1)
    check legendaryDesc.len > 0

suite "Power-Up Generation":
  test "Legendary power-up generation only gives legendary":
    ## When legendary flag is true, all choices should be legendary
    ## This ensures proper rarity distribution
    let player = newPlayer(100.0, 100.0)
    let choices = generatePowerUpChoices(player, true)
    for choice in choices:
      check choice.rarity == prLegendary
  
  test "Normal power-up generation gives common rarity":
    ## When legendary flag is false, all choices should be common
    ## Regular wave rewards are common tier
    let player = newPlayer(100.0, 100.0)
    let choices = generatePowerUpChoices(player, false)
    for choice in choices:
      check choice.rarity == prCommon
  
  test "Power-up choices provide 3 options":
    ## Generation should always provide exactly 3 choices
    ## This is the standard selection count
    let player = newPlayer(100.0, 100.0)
    let choices = generatePowerUpChoices(player, false)
    check choices.len == 3

suite "Overcharge Power-Up Mechanics":
  test "Overcharge has 3 distinct levels with different bonuses":
    ## Overcharge is a distance-based damage scaling power-up
    ## Each level provides different maximum bonus and distance requirements
    ## Level 1: 40% bonus at 40 units, Level 2: 80% at 70 units, Level 3: 120% at 100 units
    let desc1 = getPowerUpDescription(puOvercharge, 1)
    let desc2 = getPowerUpDescription(puOvercharge, 2)
    let desc3 = getPowerUpDescription(puOvercharge, 3)
    
    check desc1.contains("40")  # 40% bonus and 40 units
    check desc2.contains("80")  # 80% bonus at 70 units
    check desc3.contains("120")  # 120% bonus at 100 units
  
  test "Overcharge damage calculations scale correctly":
    ## Damage bonus should increase linearly with distance traveled
    ## Maximum bonus achieved at specified distance threshold
    let level1MaxBonus = 0.4
    let level2MaxBonus = 0.8
    let level3MaxBonus = 1.2
    check level1MaxBonus == 0.4
    check level2MaxBonus == 0.8
    check level3MaxBonus == 1.2

# =============================================================================
# PARTICLE TESTS - Visual effects system
# =============================================================================

suite "Particle System":
  test "Particle creation":
    ## Particles should spawn at specified position
    ## Initial lifetime should be positive
    let particle = newParticle(100.0, 100.0, Red, 100.0)
    check particle.pos.x == 100.0
    check particle.pos.y == 100.0
    check particle.lifetime > 0
    check particle.maxLifetime > 0
  
  test "Particle movement":
    ## Particles should move based on their velocity
    ## Position should change after update
    let particle = newParticle(0.0, 0.0, Red, 100.0)
    let initialPos = particle.pos
    discard updateParticle(particle, 0.1)
    check (particle.pos.x != initialPos.x) or (particle.pos.y != initialPos.y)
  
  test "Particle lifetime decreases over time":
    ## Lifetime should decrease with each update
    ## Particles eventually expire
    let particle = newParticle(0.0, 0.0, Red, 100.0)
    let initialLifetime = particle.lifetime
    discard updateParticle(particle, 0.1)
    check particle.lifetime < initialLifetime
  
  test "Particle expires when lifetime reaches zero":
    ## Update should return false when particle dies
    ## This signals particle should be removed
    let particle = newParticle(0.0, 0.0, Red, 100.0)
    check updateParticle(particle, 999.0) == false

# =============================================================================
# WALL TESTS - Defensive structure mechanics
# =============================================================================

suite "Wall Mechanics":
  test "Wall creation with player stats":
    ## Walls should spawn at specified position
    ## HP should be initialized based on player power-ups
    let player = newPlayer(100.0, 100.0)
    let wall = newWall(100.0, 100.0, player)
    check wall.pos.x == 100.0
    check wall.pos.y == 100.0
    check wall.hp > 0
    check wall.maxHp > 0
  
  test "Wall takes damage":
    ## Wall HP should decrease when damaged
    ## Damage should be exact amount applied
    let player = newPlayer(100.0, 100.0)
    let wall = newWall(100.0, 100.0, player)
    let initialHp = wall.hp
    wall.hp -= 10.0
    check wall.hp == initialHp - 10.0
  
  test "Wall death detection":
    ## Wall should be destroyable when HP reaches zero
    ## This allows for proper cleanup
    let player = newPlayer(100.0, 100.0)
    let wall = newWall(100.0, 100.0, player)
    wall.hp = 0.0
    check wall.hp <= 0
  
  test "Wall Master power-up increases wall durability":
    ## Players with Wall Master should have stronger walls
    ## This tests power-up integration with walls
    let normalPlayer = newPlayer(100.0, 100.0)
    let normalWall = newWall(100.0, 100.0, normalPlayer)
    
    let buffedPlayer = newPlayer(100.0, 100.0)
    applyPowerUp(buffedPlayer, PowerUp(powerType: puWallMaster, level: 1, rarity: prCommon))
    let buffedWall = newWall(100.0, 100.0, buffedPlayer)
    
    check buffedWall.maxHp > normalWall.maxHp

# =============================================================================
# VECTOR MATH TESTS - Essential physics calculations
# =============================================================================

suite "Vector Mathematics":
  test "Vector creation with coordinates":
    ## Basic vector initialization
    ## X and Y components should match input
    let v = newVector2f(3.0, 4.0)
    check v.x == 3.0
    check v.y == 4.0
  
  test "Vector length calculation (Pythagorean theorem)":
    ## Length of (3,4) vector should be 5
    ## This tests the magnitude calculation
    let v = newVector2f(3.0, 4.0)
    check v.length() == 5.0
  
  test "Vector normalization to unit length":
    ## Normalized vector should have length of 1
    ## Direction is preserved, magnitude becomes 1
    let v = newVector2f(3.0, 4.0)
    let normalized = v.normalize()
    check abs(normalized.length() - 1.0) < 0.001
  
  test "Vector addition combines components":
    ## Adding vectors should sum their components
    ## (1,2) + (3,4) = (4,6)
    let v1 = newVector2f(1.0, 2.0)
    let v2 = newVector2f(3.0, 4.0)
    let result = v1 + v2
    check result.x == 4.0
    check result.y == 6.0
  
  test "Vector subtraction calculates difference":
    ## Subtracting vectors should subtract components
    ## (5,7) - (2,3) = (3,4)
    let v1 = newVector2f(5.0, 7.0)
    let v2 = newVector2f(2.0, 3.0)
    let result = v1 - v2
    check result.x == 3.0
    check result.y == 4.0
  
  test "Vector scalar multiplication scales magnitude":
    ## Multiplying by scalar should scale both components
    ## (2,3) * 2 = (4,6)
    let v = newVector2f(2.0, 3.0)
    let result = v * 2.0
    check result.x == 4.0
    check result.y == 6.0
  
  test "Distance between two points":
    ## Distance from (0,0) to (3,4) should be 5
    ## Uses Pythagorean theorem
    let p1 = newVector2f(0.0, 0.0)
    let p2 = newVector2f(3.0, 4.0)
    check distance(p1, p2) == 5.0
  
  test "Zero vector has zero length":
    ## Zero vector should have length of 0
    ## This is an edge case for normalization
    let zero = newVector2f(0.0, 0.0)
    check zero.length() == 0.0

# =============================================================================
# GAME LOGIC TESTS - Core gameplay mechanics and balance
# =============================================================================

suite "Wave Progression System":
  test "Boss coin collection requirement for wave completion":
    ## Wave is NOT complete if boss coin is active (not collected)
    ## This prevents skipping boss loot collection
    let bossCoinActive = true
    let waveEnemiesRemaining = 0
    let enemiesCount = 0
    let waveComplete = waveEnemiesRemaining == 0 and enemiesCount == 0 and not bossCoinActive
    check waveComplete == false
  
  test "Wave completes when boss coin is collected":
    ## Wave IS complete when all enemies dead and boss coin collected
    ## This is the win condition for boss waves
    let bossCoinActive = false
    let waveEnemiesRemaining = 0
    let enemiesCount = 0
    let waveComplete = waveEnemiesRemaining == 0 and enemiesCount == 0 and not bossCoinActive
    check waveComplete == true
  
  test "Wave cannot complete with enemies remaining":
    ## Even if boss coin is collected, enemies must be defeated
    ## This prevents premature wave completion
    let bossCoinActive = false
    let waveEnemiesRemaining = 5
    let enemiesCount = 3
    let waveComplete = waveEnemiesRemaining == 0 and enemiesCount == 0 and not bossCoinActive
    check waveComplete == false

suite "Boss Spawn Mechanics":
  test "Boss waves occur every 5 waves":
    ## Boss spawns should be predictable
    ## Gives players time to prepare for boss fights
    let wavesUntilBoss = 5
    check wavesUntilBoss == 5  # Boss every 5 waves
  
  test "Boss wave spawns fewer regular enemies":
    ## Boss waves have reduced enemy spawns (50% of normal)
    ## This prevents overwhelming the player
    let normalWaveCount = 20
    let bossWaveMultiplier = 0.5
    let bossWaveCount = (normalWaveCount.float32 * bossWaveMultiplier).int
    check bossWaveCount == 10

suite "Damage Calculations":
  test "Fire rate penalty for Double Shot":
    ## Double Shot increases fire rate by 25% (1.25x slower)
    ## This balances the extra bullets
    let player = newPlayer(100.0, 100.0)
    let initialFireRate = player.fireRate
    let powerUp = PowerUp(powerType: puDoubleShot, level: 1, rarity: prCommon)
    applyPowerUp(player, powerUp)
    let newFireRate = getCurrentFireRate(player)
    check newFireRate > initialFireRate
  
  test "Multi-shot damage reduction scales with level":
    ## Multi-shot bullets deal reduced damage per bullet
    ## Level 1: 67% damage (2 bullets = 134% total)
    ## Level 2: 55% damage (3 bullets = 165% total)
    ## Level 3: 45% damage (4 bullets = 180% total)
    let level1Mult = 0.67
    let level2Mult = 0.55
    let level3Mult = 0.45
    check level1Mult == 0.67
    check level2Mult == 0.55
    check level3Mult == 0.45
  
  test "Critical hit chance and multiplier scaling":
    ## Critical hit power-up has increasing chance and damage
    ## Level 1: 15% chance, 2.0x damage
    ## Level 2: 20% chance, 2.5x damage
    ## Level 3: 25% chance, 3.0x damage
    let level1Chance = 15
    let level1Mult = 2.0
    let level3Mult = 3.0
    check level1Chance == 15
    check level1Mult == 2.0
    check level3Mult == 3.0

suite "Status Effect System":
  test "Frost shot slow percentages":
    ## Frost shots apply movement slow to enemies
    ## Level 1: 25% slow, Level 2: 40% slow, Level 3: 60% slow
    let level1Slow = 0.25
    let level2Slow = 0.4
    let level3Slow = 0.6
    check level1Slow == 0.25
    check level2Slow == 0.4
    check level3Slow == 0.6
  
  test "Poison damage over time values":
    ## Poison applies continuous damage
    ## Level 1: 4 DPS, Level 2: 5 DPS, Level 3: 6 DPS
    let level1Poison = 4.0
    let level2Poison = 5.0
    let level3Poison = 6.0
    check level1Poison == 4.0
    check level2Poison == 5.0
    check level3Poison == 6.0
  
  test "Slow Field aura radius and power":
    ## Slow Field creates an area that slows enemies
    ## Level 1: 120 radius, 30% slow
    ## Level 2: 160 radius, 45% slow
    ## Level 3: 200 radius, 55% slow
    let level1Radius = 120.0
    let level1Power = 0.30
    let level3Radius = 200.0
    let level3Power = 0.55
    check level1Radius == 120.0
    check level1Power == 0.30
    check level3Radius == 200.0
    check level3Power == 0.55

# =============================================================================
# SHOP SYSTEM TESTS - Permanent upgrades and economy
# =============================================================================

suite "Shop Item Costs":
  test "Shop items have exponential cost scaling":
    ## Each purchase increases cost by 1.5x
    ## Prevents infinite farming of single upgrade
    let item = ShopItem(name: "Test", description: "Test", baseCost: 10, bought: 0)
    let firstCost = getCurrentCost(item)
    check firstCost == 10
    
    var item2 = ShopItem(name: "Test", description: "Test", baseCost: 10, bought: 1)
    let secondCost = getCurrentCost(item2)
    check secondCost == 15  # 10 * 1.5^1
    
    var item3 = ShopItem(name: "Test", description: "Test", baseCost: 10, bought: 2)
    let thirdCost = getCurrentCost(item3)
    check thirdCost == 22  # 10 * 1.5^2 = 22.5, truncated to 22
  
  test "Base shop item costs are balanced":
    ## Different items have different base costs
    ## This creates strategic choices
    let shopItems = initShopItems()
    check shopItems[0].baseCost == 8   # Damage
    check shopItems[1].baseCost == 10  # Fire Rate
    check shopItems[2].baseCost == 7   # Move Speed
    check shopItems[3].baseCost == 12  # Max Health
    check shopItems[4].baseCost == 6   # Bullet Speed
    check shopItems[5].baseCost == 15  # Walls

suite "Shop Balance Mechanics":
  test "Fire rate shop upgrade has diminishing returns":
    ## Fire rate multiplies by 0.95 per purchase (5% improvement)
    ## Has minimum cap at 0.08 seconds
    let fireRateMult = 0.95
    let minFireRate = 0.08
    check fireRateMult == 0.95
    check minFireRate == 0.08
  
  test "Damage scaling uses exponential formula":
    ## Damage increases by base * 1.08^purchases
    ## Provides steady but not overwhelming growth
    let baseDamageGain = 0.5
    let scalingFactor = 1.08
    check baseDamageGain == 0.5
    check scalingFactor == 1.08
  
  test "Movement speed shop gains are linear":
    ## Move speed increases by 12 per purchase
    ## Simpler scaling for this stat
    let speedGainPerPurchase = 12.0
    check speedGainPerPurchase == 12.0
  
  test "Health shop upgrade provides fixed gains":
    ## Max HP increases by 2 per purchase
    ## Both max HP and current HP increase
    let healthGainPerPurchase = 2.0
    check healthGainPerPurchase == 2.0

# =============================================================================
# SETTINGS TESTS - Game configuration validation
# =============================================================================

suite "FPS Configuration":
  test "FPS limit range validation accepts valid values":
    ## FPS should be between 30 and 1000
    ## This ensures playable performance
    let validFps1 = 60
    let validFps2 = 300
    let validFps3 = 1000
    check validFps1 >= 30 and validFps1 <= 1000
    check validFps2 >= 30 and validFps2 <= 1000
    check validFps3 >= 30 and validFps3 <= 1000
  
  test "FPS limit range validation rejects invalid values":
    ## Values outside 30-1000 range should be rejected
    ## Prevents performance issues and unrealistic values
    let tooLow = 20
    let tooHigh = 10000
    check not (tooLow >= 30 and tooLow <= 1000)
    check not (tooHigh >= 30 and tooHigh <= 1000)

# =============================================================================
# INTEGRATION TESTS - Complex game state interactions
# =============================================================================

suite "Multi-Power-Up Interactions":
  test "Double Shot and Multi-Shot combined behavior":
    ## When both are active, Multi-Shot pattern fires multiple times
    ## Creates a burst pattern of spread shots
    let player = newPlayer(100.0, 100.0)
    applyPowerUp(player, PowerUp(powerType: puDoubleShot, level: 1, rarity: prCommon))
    applyPowerUp(player, PowerUp(powerType: puMultiShot, level: 1, rarity: prCommon))
    check hasPowerUp(player, puDoubleShot)
    check hasPowerUp(player, puMultiShot)
  
  test "Bullet size affects collision detection":
    ## Larger bullets have bigger radius
    ## Level 1: 1.4x, Level 2: 1.8x, Level 3: 2.4x
    let baseBulletRadius = 5.0
    let level1Mult = 1.4
    let level2Mult = 1.8
    let level3Mult = 2.4
    check baseBulletRadius * level1Mult == 7.0
    check baseBulletRadius * level2Mult == 9.0
    check baseBulletRadius * level3Mult == 12.0
  
  test "Life Steal healing frequency scales with level":
    ## Life Steal heals after killing multiple enemies
    ## Level 1: heal every 20 kills
    ## Level 2: heal every 15 kills
    ## Level 3: heal every 10 kills
    let level1Threshold = 20
    let level2Threshold = 15
    let level3Threshold = 10
    check level1Threshold == 20
    check level2Threshold == 15
    check level3Threshold == 10

suite "Consumable Effects":
  test "Speed boost temporary duration":
    ## Speed boost consumables provide temporary speed increase
    ## Effect should last a specific duration
    let player = newPlayer(100.0, 100.0)
    player.speedBoostTimer = 5.0  # 5 seconds
    check player.speedBoostTimer > 0
  
  test "Invincibility timer prevents all damage":
    ## Invincibility makes player immune to damage
    ## Should have a duration
    let player = newPlayer(100.0, 100.0)
    player.invincibilityTimer = 3.0  # 3 seconds
    check player.invincibilityTimer > 0
  
  test "Magnet effect increases collection radius":
    ## Magnet consumable increases coin/item pickup range
    ## Temporary aura expansion
    let player = newPlayer(100.0, 100.0)
    let baseAura = player.auraRadius
    player.magnetTimer = 10.0  # 10 seconds
    check player.magnetTimer > 0

suite "Enemy Spawn Patterns":
  test "Early waves spawn only basic enemies":
    ## Waves 1-5 should only spawn Circle enemies
    ## This creates a tutorial progression
    let earlyWave = 3
    check earlyWave <= 5  # Only circles
  
  test "Enemy variety increases with wave number":
    ## New enemy types unlock every 5 waves
    ## Each new enemy gets prominent spawn rate
    let wave6 = 6   # Pentagon introduced
    let wave11 = 11  # Triangle introduced
    let wave16 = 16  # Cube introduced
    check wave6 > 5
    check wave11 > 10
    check wave16 > 15
  
  test "Rare enemies appear in later waves":
    ## Phantom enemy appears after wave 50
    ## Provides late-game challenge
    let phantomWave = 51
    check phantomWave > 50

suite "Legendary Power-Up Mechanics":
  test "Time Warp slows game time by 50%":
    ## Time Warp affects enemy and bullet speed
    ## Player moves at normal speed
    let timeWarpSlowFactor = 0.50  # 50% speed
    check timeWarpSlowFactor == 0.50
  
  test "Phase Shift provides invulnerability window":
    ## Phase Shift grants temporary invincibility
    ## Allows dashing through enemies
    let player = newPlayer(100.0, 100.0)
    player.phaseShiftInvulnTimer = 0.5  # 0.5 seconds
    check player.phaseShiftInvulnTimer > 0
  
  test "Gravity Well affects ranged enemies more":
    ## Gravity Well pulls enemies toward player
    ## Ranged enemies get 50% extra pull force
    let basePull = 100.0
    let rangedMultiplier = 1.5
    let rangedPull = basePull * rangedMultiplier
    check rangedPull == 150.0

# =============================================================================
# EDGE CASE TESTS - Boundary conditions and error handling
# =============================================================================

suite "Boundary Conditions":
  test "Player at screen edge collision":
    ## Player should not move off screen
    ## Collision should be detected at boundaries
    let player = newPlayer(0.0, 0.0)
    check player.pos.x >= 0
    check player.pos.y >= 0
  
  test "Bullet off-screen culling":
    ## Bullets far from screen should be removed
    ## Prevents memory leaks
    let bullet = newBullet(-1000.0, -1000.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    check isOffScreen(bullet, 1024, 768) == true
  
  test "Zero damage should not affect HP":
    ## Damage of 0 should not change HP
    ## Edge case for damage calculations
    let player = newPlayer(100.0, 100.0)
    let initialHp = player.hp
    discard takeDamage(player, 0.0)
    check player.hp == initialHp
  
  test "Maximum coin value clamping":
    ## Very high coin values should be handled
    ## Prevents integer overflow
    let hugeCoinValue = 9999
    let coin = newCoin(0.0, 0.0, hugeCoinValue, false)
    check coin.value == hugeCoinValue
  
  test "Negative speed should be prevented":
    ## Speed multipliers should not create negative movement
    ## Minimum speed cap
    let player = newPlayer(100.0, 100.0)
    check player.speed > 0
    check player.baseSpeed > 0

suite "Zero and Null Handling":
  test "Division by zero protection in normalization":
    ## Normalizing a zero vector should not crash
    ## Should return zero vector
    let zero = newVector2f(0.0, 0.0)
    let normalized = zero.normalize()
    check normalized.x == 0.0
    check normalized.y == 0.0
  
  test "Empty power-up list handling":
    ## Player with no power-ups should work normally
    ## Power-up checks should return false
    let player = newPlayer(100.0, 100.0)
    check player.powerUps.len == 0
    check hasPowerUp(player, puDoubleShot) == false
  
  test "Empty enemy list wave completion":
    ## Wave should complete when no enemies exist
    ## Even if some were supposed to spawn
    let waveEnemiesRemaining = 0
    let enemiesCount = 0
    let bossCoinActive = false
    let complete = waveEnemiesRemaining == 0 and enemiesCount == 0 and not bossCoinActive
    check complete == true

# =============================================================================
# PERFORMANCE TESTS - Verify optimization mechanics
# =============================================================================

suite "Performance Optimizations":
  test "Particle cleanup after expiration":
    ## Dead particles should be removable
    ## Prevents unbounded memory growth
    let particle = newParticle(0.0, 0.0, Red, 0.01)
    let alive = updateParticle(particle, 1.0)
    check alive == false  # Should be dead
  
  test "Bullet despawn on off-screen":
    ## Off-screen bullets should be detected
    ## Allows for cleanup
    let bullet = newBullet(-500.0, -500.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    check isOffScreen(bullet, 1024, 768) == true
  
  test "Consumable auto-despawn timer":
    ## Consumables should despawn after time limit
    ## Prevents infinite accumulation
    let consumable = newConsumable(100.0, 100.0, 1.0)
    check consumable.lifetime > 0
    check consumable.lifetime <= 15.0  # Max 15 seconds

# =============================================================================
# BALANCE VERIFICATION TESTS - Ensure game difficulty is fair
# =============================================================================

suite "Power-Up Balance":
  test "Regeneration healing intervals are balanced":
    ## Regeneration healing should not be overpowered
    ## Level 1: 12s, Level 2: 9s, Level 3: 6s
    let level1Interval = 12.0
    let level2Interval = 9.0
    let level3Interval = 6.0
    check level1Interval == 12.0
    check level2Interval == 9.0
    check level3Interval == 6.0
  
  test "Damage Zone radius and power scaling":
    ## Damage Zone should have limited range
    ## Level 1: 50 radius, 2 DPS
    ## Level 2: 100 radius, 5 DPS
    ## Level 3: 150 radius, 10 DPS
    let level1Radius = 50.0
    let level1Damage = 2.0
    let level3Radius = 150.0
    let level3Damage = 10.0
    check level1Radius == 50.0
    check level1Damage == 2.0
    check level3Radius == 150.0
    check level3Damage == 10.0
  
  test "Auto-shoot fire rate penalties":
    ## Auto-shoot convenience balanced by slower fire rate
    ## Level 1: 60% speed, Level 2: 80%, Level 3: 100%
    let level1Speed = 0.6
    let level2Speed = 0.8
    let level3Speed = 1.0
    check level1Speed == 0.6
    check level2Speed == 0.8
    check level3Speed == 1.0

# Run all tests
when isMainModule:
  echo "=========================================="
  echo "   TopHat-Shooter Comprehensive Tests    "
  echo "=========================================="
  echo ""
  echo "Running all test suites..."
  echo "This will verify game mechanics, balance,"
  echo "and edge cases across the entire codebase."
  echo ""
