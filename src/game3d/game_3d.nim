## 3D Game Module
## Main 3D game loop, state management, and integration

import raylib, sequtils, random, math
import types_3d, engine_3d, player_3d, boss_3d
import ../types  # Import 2D types for Player integration
import ../localization

type
  Game3D* = object
    active*: bool
    won*: bool
    arena*: Arena3D
    camera*: FPSCamera
    player*: Player3D
    boss*: Boss3D
    projectiles*: seq[Projectile3D]
    damageNumbers*: seq[DamageNumber3D]
    timeElapsed*: float32
    paused*: bool

proc initGame3D*(bossId: int, player2D: Player): Game3D =
  let arena = generateArena("space", 500.0)
  let startPos = vec3(0, 15, 0)
  
  result.arena = arena
  result.camera = initCamera3D(startPos)
  result.player = newPlayer3D(startPos, player2D.hp)
  result.boss = getBoss3D(bossId)
  result.projectiles = @[]
  result.damageNumbers = @[]
  result.active = true
  result.won = false
  result.timeElapsed = 0.0
  result.paused = false

# DAMAGE NUMBERS

proc spawnDamageNumber3D(damageNumbers: var seq[DamageNumber3D], pos: Vector3f, damage: float32) =
  ## Create a new damage number at the given position
  let horizontalSpread = vec3(
    (rand(1.0) - 0.5) * 20.0,
    0,
    (rand(1.0) - 0.5) * 20.0
  )
  
  damageNumbers.add(DamageNumber3D(
    pos: pos,
    vel: vec3(horizontalSpread.x, 50.0, horizontalSpread.z),  # Float upward
    damage: damage,
    lifetime: 0,
    maxLifetime: 1.5,
    fromPlayer: true,
    isCritical: false
  ))

proc updateDamageNumbers(damageNumbers: var seq[DamageNumber3D], dt: float32) =
  ## Update all damage numbers and remove expired ones
  var i = 0
  while i < damageNumbers.len:
    var dmg = damageNumbers[i]
    
    # Apply gravity/deceleration
    dmg.vel.y -= 80.0 * dt
    dmg.pos = vec3(
      dmg.pos.x + dmg.vel.x * dt,
      dmg.pos.y + dmg.vel.y * dt,
      dmg.pos.z + dmg.vel.z * dt
    )
    
    # Horizontal damping
    dmg.vel.x *= pow(0.95, 60.0 * dt)
    dmg.vel.z *= pow(0.95, 60.0 * dt)
    
    dmg.lifetime += dt
    damageNumbers[i] = dmg
    
    # Remove if expired
    if dmg.lifetime >= dmg.maxLifetime:
      damageNumbers.delete(i)
    else:
      i += 1

proc drawDamageNumbers(damageNumbers: seq[DamageNumber3D], camera: FPSCamera) =
  ## Draw damage numbers in 3D space projected to 2D screen
  for dmg in damageNumbers:
    let progress = dmg.lifetime / dmg.maxLifetime
    let alpha = (1.0 - progress) * 255.0
    
    # Convert 3D position to screen position
    let screenPos = getWorldToScreen(
      Vector3(x: dmg.pos.x, y: dmg.pos.y, z: dmg.pos.z),
      Camera(
        position: Vector3(x: camera.position.x, y: camera.position.y, z: camera.position.z),
        target: Vector3(x: camera.target.x, y: camera.target.y, z: camera.target.z),
        up: Vector3(x: 0, y: 1, z: 0),
        fovy: camera.fovy,
        projection: CameraProjection.Perspective
      )
    )
    
    # Only draw if on screen
    if screenPos.x >= 0 and screenPos.x <= getScreenWidth().float32 and
       screenPos.y >= 0 and screenPos.y <= getScreenHeight().float32:
      
      let damageText = $int(dmg.damage)
      let fontSize: int32 = 24
      let color = Color(r: 255, g: 255, b: 100, a: alpha.uint8)
      
      # Draw with shadow for better visibility
      drawText(damageText, int32(screenPos.x) - 1, int32(screenPos.y) - 1, fontSize, Black)
      drawText(damageText, int32(screenPos.x), int32(screenPos.y), fontSize, color)

proc updateGame3D*(game: var Game3D, dt: float32) =
  # Handle pause toggle
  if isKeyPressed(KeyboardKey.Escape):
    game.paused = not game.paused
    if game.paused:
      enableCursor()
    else:
      disableCursor()
  
  if not game.active or game.paused:
    return
  
  game.timeElapsed += dt
  
  # Update camera
  let mouseDelta = getMouseDelta()
  updateCamera(game.camera, mouseDelta, 0.1)  # Reduced sensitivity for better control
  
  # Keep mouse centered to prevent hitting screen edges
  let centerX = getScreenWidth() div 2
  let centerY = getScreenHeight() div 2
  setMousePosition(centerX, centerY)
  
  # Update player
  updatePlayer(game.player, game.camera, game.arena.platforms, dt)
  updateWeapon(game.player, dt)
  
  # Shooting
  if isMouseButtonPressed(MouseButton.Left):
    discard fireWeapon(game.player, game.camera, game.projectiles)
  
  if isKeyPressed(KeyboardKey.R):
    reload(game.player)
  
  # Update platforms
  updatePlatforms(game.arena.platforms, dt)
  
  # Update boss (with arena for environment changes)
  updateBoss(game.boss, game.player, game.projectiles, game.arena, dt)
  
  # Update projectiles
  for proj in game.projectiles.mitems:
    if proj.active:
      proj.pos = proj.pos + proj.vel * dt
      proj.lifetime -= dt
      
      if proj.lifetime <= 0:
        proj.active = false
      
      # Check hits
      if proj.fromPlayer:
        let hitResult = takeBossDamage(game.boss, proj)
        if hitResult.hit:
          # Spawn damage number at hit position
          spawnDamageNumber3D(game.damageNumbers, hitResult.hitPos, hitResult.damageDealt)
          proj.active = false
      else:
        if distance(proj.pos, game.player.pos) < 5.0:
          game.player.health -= proj.damage
          proj.active = false
  
  # Remove dead projectiles
  game.projectiles.keepIf(proc(p: Projectile3D): bool = p.active)
  
  # Update damage numbers
  updateDamageNumbers(game.damageNumbers, dt)
  
  # Update camera position to follow player
  game.camera.position = game.player.pos + vec3(0, 2, 0)
  game.camera.target = game.camera.position + game.camera.getForward()
  
  # Check win/loss
  if game.player.health <= 0:
    game.active = false
    game.won = false
  elif game.boss.health <= 0:
    game.active = false
    game.won = true

proc renderGame3D*(game: Game3D) =
  # 3D rendering
  beginMode3D(
    Camera(
      position: Vector3(x: game.camera.position.x, y: game.camera.position.y, z: game.camera.position.z),
      target: Vector3(x: game.camera.target.x, y: game.camera.target.y, z: game.camera.target.z),
      up: Vector3(x: 0, y: 1, z: 0),
      fovy: game.camera.fovy,
      projection: CameraProjection.Perspective
    )
  )
  
  drawArena(game.arena)
  
  for platform in game.arena.platforms:
    drawPlatform(platform)
  
  # Draw gravity wells
  drawGravityWells(game.boss)
  
  drawBoss(game.boss)
  
  for proj in game.projectiles:
    if proj.active:
      drawProjectile(proj)
  
  endMode3D()
  
  # Draw satellite healthbars (in 2D overlay)
  drawSatelliteHealthbars(game.boss, game.camera)
  
  # Draw damage numbers (in 2D overlay)
  drawDamageNumbers(game.damageNumbers, game.camera)
  
  # 2D HUD
  drawRectangle(10, 10, 320, 150, fade(Black, 0.7))
  drawText(t(tkGame3DHp) & ": " & $int(game.player.health), 20, 20, 20, Red)
  drawText(t(tkGame3DAmmo) & ": " & $game.player.weapon.ammo & "/" & $game.player.weapon.maxAmmo, 20, 45, 20, Yellow)
  
  # Boss health bar
  let bossHpPercent = game.boss.health / game.boss.maxHealth
  drawText(t(tkGame3DBossHp) & ":", 20, 70, 18, White)
  drawRectangle(20, 92, 280, 20, Color(r: 50, g: 0, b: 0, a: 200))
  drawRectangle(20, 92, int32(280.0 * bossHpPercent), 20, Color(r: 255, g: 50, b: 50, a: 255))
  drawRectangleLines(20, 92, 280, 20, White)
  
  # Phase indicator with color
  let phaseColor = case game.boss.phase
    of 1: Gray
    of 2: Color(r: 150, g: 50, b: 200, a: 255)
    of 3: Color(r: 255, g: 0, b: 0, a: 255)
    else: White
  
  let phaseText = t(tkGame3DPhase) & " " & $game.boss.phase & "/3"
  drawText(phaseText, 20, 120, 20, phaseColor)
  
  # Satellite count (Phase 1 only)
  if game.boss.phase == 1:
    var activeSats = 0
    for sat in game.boss.satellites:
      if sat.active:
        activeSats += 1
    
    if activeSats > 0:
      drawText(t(tkGame3DSatellites) & ": " & $activeSats & " (" & t(tkGame3DDestroyAll) & ")", 20, 145, 16, Color(r: 255, g: 200, b: 50, a: 255))
  
  # Phase transition warning
  if game.boss.phaseTransitionTimer > 0:
    let warningText = t(tkGame3DPhaseTransition)
    let textWidth = measureText(warningText, 40)
    let flashAlpha = (sin(game.boss.phaseTransitionTimer * 10.0) * 0.5 + 0.5) * 255.0
    drawText(warningText, (getScreenWidth() - textWidth) div 2, 100, 40,
             fade(Color(r: 255, g: 255, b: 0, a: 255), flashAlpha / 255.0))
  
  # Crosshair
  let centerX = getScreenWidth() div 2
  let centerY = getScreenHeight() div 2
  drawCircleLines(centerX, centerY, 10, White)
  drawLine(centerX - 15, centerY, centerX + 15, centerY, White)
  drawLine(centerX, centerY - 15, centerX, centerY + 15, White)
  
  # Pause message
  if game.paused:
    let pauseText = t(tkGame3DPaused)
    let resumeText = t(tkGame3DPressEscResume)
    let textWidth1 = measureText(pauseText, 40)
    let textWidth2 = measureText(resumeText, 20)
    
    # Dark overlay
    drawRectangle(0, 0, getScreenWidth(), getScreenHeight(), fade(Black, 0.5))
    
    drawText(pauseText, centerX - textWidth1 div 2, centerY - 30, 40, White)
    drawText(resumeText, centerX - textWidth2 div 2, centerY + 20, 20, LightGray)
