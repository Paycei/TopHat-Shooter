## 3D Game Module
## Main 3D game loop, state management, and integration

import raylib, sequtils
import types_3d, engine_3d, player_3d, boss_3d
import ../types  # Import 2D types for Player integration

type
  Game3D* = object
    active*: bool
    won*: bool
    
    arena*: Arena3D
    camera*: FPSCamera
    player*: Player3D
    boss*: Boss3D
    projectiles*: seq[Projectile3D]
    
    timeElapsed*: float32
    paused*: bool

# ===== INIT =====

proc initGame3D*(bossId: int, player2D: Player): Game3D =
  let arena = generateArena("space", 500.0)
  let startPos = vec3(0, 15, 0)
  
  result.arena = arena
  result.camera = initCamera3D(startPos)
  result.player = newPlayer3D(startPos, player2D.hp)
  result.boss = getBoss3D(bossId)
  result.projectiles = @[]
  result.active = true
  result.won = false
  result.timeElapsed = 0.0
  result.paused = false

# ===== UPDATE =====

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
  
  # Update boss
  updateBoss(game.boss, game.player, game.projectiles, dt)
  
  # Update projectiles
  for proj in game.projectiles.mitems:
    if proj.active:
      proj.pos = proj.pos + proj.vel * dt
      proj.lifetime -= dt
      
      if proj.lifetime <= 0:
        proj.active = false
      
      # Check hits
      if proj.fromPlayer:
        if takeBossDamage(game.boss, proj):
          proj.active = false
      else:
        if distance(proj.pos, game.player.pos) < 5.0:
          game.player.health -= proj.damage
          proj.active = false
  
  # Remove dead projectiles
  game.projectiles.keepIf(proc(p: Projectile3D): bool = p.active)
  
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

# ===== RENDER =====

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
  
  drawBoss(game.boss)
  
  for proj in game.projectiles:
    if proj.active:
      drawProjectile(proj)
  
  endMode3D()
  
  # 2D HUD
  drawRectangle(10, 10, 300, 120, fade(Black, 0.7))
  drawText("HP: " & $int(game.player.health), 20, 20, 20, Red)
  drawText("Ammo: " & $game.player.weapon.ammo & "/" & $game.player.weapon.maxAmmo, 20, 45, 20, Yellow)
  drawText("Boss: " & $int(game.boss.health), 20, 70, 20, Purple)
  
  # Phase indicator and satellite count
  let phaseText = "Phase: " & $game.boss.phase
  drawText(phaseText, 20, 95, 20, Orange)
  
  # Count active satellites
  var activeSats = 0
  for sat in game.boss.satellites:
    if sat.active:
      activeSats += 1
  drawText("Satellites: " & $activeSats, 20, 115, 16, Color(r: 150, g: 100, b: 255, a: 255))
  
  # Crosshair
  let centerX = getScreenWidth() div 2
  let centerY = getScreenHeight() div 2
  drawCircleLines(centerX, centerY, 10, White)
  drawLine(centerX - 15, centerY, centerX + 15, centerY, White)
  drawLine(centerX, centerY - 15, centerX, centerY + 15, White)
  
  # Pause message
  if game.paused:
    let pauseText = "PAUSED"
    let resumeText = "Press ESC to resume"
    let textWidth1 = measureText(pauseText, 40)
    let textWidth2 = measureText(resumeText, 20)
    
    # Dark overlay
    drawRectangle(0, 0, getScreenWidth(), getScreenHeight(), fade(Black, 0.5))
    
    drawText(pauseText, centerX - textWidth1 div 2, centerY - 30, 40, White)
    drawText(resumeText, centerX - textWidth2 div 2, centerY + 20, 20, LightGray)
