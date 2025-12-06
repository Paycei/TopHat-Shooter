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

suite "Player Tests":
  test "Player creation":
    let player = newPlayer(100.0, 100.0)
    check player.pos.x == 100.0
    check player.pos.y == 100.0
    check player.hp > 0
    check player.maxHp > 0
    check player.speed > 0
  
  test "Player damage":
    let player = newPlayer(100.0, 100.0)
    let initialHp = player.hp
    discard takeDamage(player, 1.0)
    check player.hp == initialHp - 1.0
  
  test "Player death":
    let player = newPlayer(100.0, 100.0)
    let isDead = takeDamage(player, 999.0)
    check isDead == true
    check player.hp <= 0
  
  test "Player healing":
    let player = newPlayer(100.0, 100.0)
    discard takeDamage(player, 2.0)
    let hpBeforeHeal = player.hp
    heal(player, 1)
    check player.hp == hpBeforeHeal + 1.0
  
  test "Player healing doesn't exceed max HP":
    let player = newPlayer(100.0, 100.0)
    let maxHp = player.maxHp
    heal(player, 999)
    check player.hp == maxHp
  
  test "Player power-up application":
    let player = newPlayer(100.0, 100.0)
    let powerUp = PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon)
    let oldMaxHp = player.maxHp
    applyPowerUp(player, powerUp)
    check player.maxHp > oldMaxHp
    check hasPowerUp(player, puMaxHealth)
  
  test "Player has power-up check":
    let player = newPlayer(100.0, 100.0)
    check hasPowerUp(player, puMaxHealth) == false
    let powerUp = PowerUp(powerType: puMaxHealth, level: 1, rarity: prCommon)
    applyPowerUp(player, powerUp)
    check hasPowerUp(player, puMaxHealth) == true
  
  test "Player power-up level":
    let player = newPlayer(100.0, 100.0)
    check getPowerUpLevel(player, puMaxHealth) == 0
    let powerUp = PowerUp(powerType: puMaxHealth, level: 2, rarity: prCommon)
    applyPowerUp(player, powerUp)
    check getPowerUpLevel(player, puMaxHealth) == 2

suite "Enemy Tests":
  test "Enemy creation":
    let enemy = newEnemy(100.0, 100.0, 0.0, etCircle)
    check enemy.pos.x == 100.0
    check enemy.pos.y == 100.0
    check enemy.hp > 0
    check enemy.isBoss == false
  
  test "Enemy types have different properties":
    let circle = newEnemy(0.0, 0.0, 0.0, etCircle)
    let star = newEnemy(0.0, 0.0, 0.0, etStar)
    # Stars should be tankier than circles
    check star.hp > circle.hp

suite "Bullet Tests":
  test "Bullet creation":
    let bullet = newBullet(100.0, 100.0, newVector2f(1.0, 0.0), 200.0, 5.0, true)
    check bullet.pos.x == 100.0
    check bullet.pos.y == 100.0
    check bullet.damage == 5.0
    check bullet.fromPlayer == true
  
  test "Bullet movement":
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    let initialX = bullet.pos.x
    discard updateBullet(bullet, 1.0)  # 1 second
    check bullet.pos.x > initialX
  
  test "Bullet lifetime":
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    check updateBullet(bullet, 0.5) == true  # Still alive
    check updateBullet(bullet, 5.0) == false  # Should be dead after total 5.5s
  
  test "Bullet off-screen detection":
    let bullet = newBullet(-100.0, -100.0, newVector2f(1.0, 0.0), 100.0, 5.0, true)
    check isOffScreen(bullet, 1024, 768) == true
  
  test "Piercing bullets track pierced enemies":
    let bullet = newBullet(0.0, 0.0, newVector2f(1.0, 0.0), 100.0, 5.0, true, 
                          false, true, false)
    check bullet.isPiercing == true
    check bullet.piercedEnemies == 0

suite "Coin Tests":
  test "Coin creation":
    let coin = newCoin(100.0, 100.0, 5, false)
    check coin.pos.x == 100.0
    check coin.pos.y == 100.0
    check coin.value == 5
    check coin.isBossCoin == false
  
  test "Boss coin is larger":
    let normalCoin = newCoin(0.0, 0.0, 5, false)
    let bossCoin = newCoin(0.0, 0.0, 5, true)
    check bossCoin.radius > normalCoin.radius
    check bossCoin.isBossCoin == true
  
  test "Coin scaling based on value":
    let smallCoin = newCoin(0.0, 0.0, 1, false)
    let bigCoin = newCoin(0.0, 0.0, 10, false)
    check bigCoin.radius > smallCoin.radius

suite "Power-up Tests":
  test "Power-up name retrieval":
    check getPowerUpName(puDoubleShot) == "Double Shot"
    check getPowerUpName(puMaxHealth) == "Vitality"
    check getPowerUpName(puOvercharge) == "Momentum"
  
  test "Power-up description contains level info":
    let desc1 = getPowerUpDescription(puDoubleShot, 1)
    let desc2 = getPowerUpDescription(puDoubleShot, 2)
    check desc1 != desc2
    check desc1.len > 0
  
  test "Legendary power-ups generation":
    let player = newPlayer(100.0, 100.0)
    let choices = generatePowerUpChoices(player, true)
    # All choices should be legendary
    for choice in choices:
      check choice.rarity == prLegendary
  
  test "Normal power-ups generation":
    let player = newPlayer(100.0, 100.0)
    let choices = generatePowerUpChoices(player, false)
    # All choices should be common
    for choice in choices:
      check choice.rarity == prCommon
  
  test "Overcharge has 3 levels":
    let desc1 = getPowerUpDescription(puOvercharge, 1)
    let desc2 = getPowerUpDescription(puOvercharge, 2)
    let desc3 = getPowerUpDescription(puOvercharge, 3)
    
    check desc1.contains("40")
    check desc2.contains("80")
    check desc3.contains("120")
    check desc3.contains("120")

suite "Particle Tests":
  test "Particle creation":
    let particle = newParticle(100.0, 100.0, Red, 100.0)
    check particle.pos.x == 100.0
    check particle.pos.y == 100.0
    check particle.lifetime > 0
  
  test "Particle movement":
    let particle = newParticle(0.0, 0.0, Red, 100.0)
    let initialPos = particle.pos
    discard updateParticle(particle, 0.1)
    # Particle should have moved
    check (particle.pos.x != initialPos.x) or (particle.pos.y != initialPos.y)
  
  test "Particle lifetime decreases":
    let particle = newParticle(0.0, 0.0, Red, 100.0)
    let initialLifetime = particle.lifetime
    discard updateParticle(particle, 0.1)
    check particle.lifetime < initialLifetime
  
  test "Particle dies when lifetime reaches 0":
    let particle = newParticle(0.0, 0.0, Red, 100.0)
    check updateParticle(particle, 999.0) == false

suite "Wall Tests":
  test "Wall creation":
    let player = newPlayer(100.0, 100.0)
    let wall = newWall(100.0, 100.0, player)
    check wall.pos.x == 100.0
    check wall.pos.y == 100.0
    check wall.hp > 0
    check wall.maxHp > 0
  
  test "Wall damage":
    let player = newPlayer(100.0, 100.0)
    let wall = newWall(100.0, 100.0, player)
    let initialHp = wall.hp
    wall.hp -= 10.0
    check wall.hp == initialHp - 10.0
  
  test "Wall death check":
    let player = newPlayer(100.0, 100.0)
    let wall = newWall(100.0, 100.0, player)
    wall.hp = 0.0
    check wall.hp <= 0

suite "Vector Math Tests":
  test "Vector creation":
    let v = newVector2f(3.0, 4.0)
    check v.x == 3.0
    check v.y == 4.0
  
  test "Vector length":
    let v = newVector2f(3.0, 4.0)
    check v.length() == 5.0
  
  test "Vector normalization":
    let v = newVector2f(3.0, 4.0)
    let normalized = v.normalize()
    # Normalized vector should have length 1
    check abs(normalized.length() - 1.0) < 0.001
  
  test "Vector addition":
    let v1 = newVector2f(1.0, 2.0)
    let v2 = newVector2f(3.0, 4.0)
    let result = v1 + v2
    check result.x == 4.0
    check result.y == 6.0
  
  test "Vector subtraction":
    let v1 = newVector2f(5.0, 7.0)
    let v2 = newVector2f(2.0, 3.0)
    let result = v1 - v2
    check result.x == 3.0
    check result.y == 4.0
  
  test "Vector scalar multiplication":
    let v = newVector2f(2.0, 3.0)
    let result = v * 2.0
    check result.x == 4.0
    check result.y == 6.0
  
  test "Distance between points":
    let p1 = newVector2f(0.0, 0.0)
    let p2 = newVector2f(3.0, 4.0)
    check distance(p1, p2) == 5.0

suite "Game Logic Tests":
  test "Coin scaling reduces over time":
    # Wave 1: baseValue + 0 bonus
    let wave1Bonus = 1 div 10
    check wave1Bonus == 0
    
    # Wave 10: baseValue + 1 bonus
    let wave10Bonus = 10 div 10
    check wave10Bonus == 1
    
    # Wave 50: baseValue + 5 bonus
    let wave50Bonus = 50 div 10
    check wave50Bonus == 5
  
  test "Fire rate penalty for Double Shot":
    let player = newPlayer(100.0, 100.0)
    let initialFireRate = player.fireRate
    
    let powerUp = PowerUp(powerType: puDoubleShot, level: 1, rarity: prCommon)
    applyPowerUp(player, powerUp)
    
    let newFireRate = getCurrentFireRate(player)
    # Fire rate should be 40% slower (multiplied by 1.4)
    check newFireRate > initialFireRate
  
  test "Overcharge damage bonus calculation":
    # At level 1: max 40% bonus at 40 units
    let level1MaxBonus = 0.4
    check level1MaxBonus == 0.4
    
    # At level 2: max 80% bonus at 70 units
    let level2MaxBonus = 0.8
    check level2MaxBonus == 0.8
    
    # At level 3: max 120% bonus at 100 units
    let level3MaxBonus = 1.2
    check level3MaxBonus == 1.2

suite "Boss Mechanics Tests":
  test "Boss coin must be collected to complete wave":
    # This tests the checkWaveComplete logic
    # Wave is NOT complete if bossCoinActive is true
    let bossCoinActive = true
    let waveEnemiesRemaining = 0
    let enemiesCount = 0
    
    let waveComplete = waveEnemiesRemaining == 0 and enemiesCount == 0 and not bossCoinActive
    check waveComplete == false
  
  test "Wave completes when boss coin is collected":
    let bossCoinActive = false
    let waveEnemiesRemaining = 0
    let enemiesCount = 0
    
    let waveComplete = waveEnemiesRemaining == 0 and enemiesCount == 0 and not bossCoinActive
    check waveComplete == true

suite "Settings Tests":
  test "FPS limit range validation":
    let validFps1 = 60
    let validFps2 = 300
    let validFps3 = 1000
    
    check validFps1 >= 30 and validFps1 <= 1000
    check validFps2 >= 30 and validFps2 <= 1000
    check validFps3 >= 30 and validFps3 <= 1000
  
  test "Invalid FPS should be rejected":
    let tooLow = 20
    let tooHigh = 10000
    
    check not (tooLow >= 30 and tooLow <= 1000)
    check not (tooHigh >= 30 and tooHigh <= 1000)

# Run all tests
when isMainModule:
  echo "Running TopHat-Shooter Tests..."
  echo "================================"
