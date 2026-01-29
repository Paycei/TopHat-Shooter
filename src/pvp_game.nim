## PvP Game Mode Logic
## Handles 1v1 player vs player combat

import raylib, types, player, bullet, wall, particle, particle_pool, sound, network_types, network, math, random, times

const
  PVP_PLAYER_START_HP = 5.0  # Lower HP for faster PvP matches
  PVP_PLAYER_START_COINS = 100
  PVP_PLAYER_START_WALLS = 3
  PVP_RESPAWN_TIME = 3.0
  PVP_KILL_LIMIT = 5  # First to 5 kills wins
  PVP_TIME_LIMIT = 300.0  # 5 minutes
  SNAPSHOT_RATE = 0.033  # 30 Hz (every 33ms)
  INPUT_SEND_RATE = 0.016  # 60 Hz (every 16ms)

type
  PvPGameState* = ref object
    networkManager*: NetworkManager
    localPlayerIndex*: int  # 0 or 1
    remotePlayerIndex*: int
    players*: array[2, Player]
    bullets*: seq[Bullet]
    walls*: seq[Wall]
    particlePool*: ParticlePool
    serverTick*: int
    gameTime*: float32
    gameStarted*: bool
    gameOver*: bool
    winnerIndex*: int
    inputBuffer*: seq[PlayerInput]
    lastSnapshotTime*: float32
    lastInputSendTime*: float32
    pendingInputs*: seq[tuple[tick: int, input: PlayerInput]]  # For reconciliation
    screenWidth*: int32
    screenHeight*: int32
    bulletIdCounter*: int
    countdownTimer*: float32
    isCountingDown*: bool
    damageNumbers*: seq[DamageNumber]
    lastPingTime*: float32
    respawnTimers*: array[2, float32]  # Respawn timers for each player
    lastHostInput*: PlayerInput  # Store host's last input for server processing

proc newPvPGameState*(screenWidth, screenHeight: int32, isHost: bool): PvPGameState =
  result = PvPGameState(
    networkManager: newNetworkManager(),
    localPlayerIndex: if isHost: 0 else: 1,
    remotePlayerIndex: if isHost: 1 else: 0,
    serverTick: 0,
    gameTime: 0,
    gameStarted: false,
    gameOver: false,
    winnerIndex: -1,
    inputBuffer: @[],
    lastSnapshotTime: 0,
    lastInputSendTime: 0,
    pendingInputs: @[],
    screenWidth: screenWidth,
    screenHeight: screenHeight,
    bulletIdCounter: 0,
    countdownTimer: 0,
    isCountingDown: false,
    damageNumbers: @[],
    lastPingTime: 0,
    respawnTimers: [0.0, 0.0],
    lastHostInput: PlayerInput(tick: 0, moveDir: newVector2f(0, 0), shooting: false, 
                               mousePos: newVector2f(0, 0), placingWall: false, 
                               wallPos: newVector2f(0, 0), timestamp: 0)
  )
  
  # Initialize players at opposite corners
  result.players[0] = newPlayer(screenWidth.float32 * 0.25, screenHeight.float32 * 0.5)
  result.players[0].hp = PVP_PLAYER_START_HP
  result.players[0].maxHp = PVP_PLAYER_START_HP
  result.players[0].coins = PVP_PLAYER_START_COINS
  result.players[0].walls = PVP_PLAYER_START_WALLS
  
  result.players[1] = newPlayer(screenWidth.float32 * 0.75, screenHeight.float32 * 0.5)
  result.players[1].hp = PVP_PLAYER_START_HP
  result.players[1].maxHp = PVP_PLAYER_START_HP
  result.players[1].coins = PVP_PLAYER_START_COINS
  result.players[1].walls = PVP_PLAYER_START_WALLS
  
  result.bullets = @[]
  result.walls = @[]
  result.particlePool = newParticlePool(2000)

proc startCountdown*(pvp: PvPGameState) =
  pvp.isCountingDown = true
  pvp.countdownTimer = 3.0
  
  if pvp.networkManager.isHost():
    # Send game start packet
    var packet = Packet(kind: ptGameStart)
    packet.packetType = ptGameStart
    packet.tick = pvp.serverTick
    packet.timestamp = epochTime()
    packet.countdownTime = pvp.countdownTimer
    pvp.networkManager.sendPacket(packet)

proc capturePlayerInput*(pvp: PvPGameState): PlayerInput =
  ## Capture local player input
  let localPlayer = pvp.players[pvp.localPlayerIndex]
  
  var moveDir = newVector2f(0, 0)
  if isKeyDown(W): moveDir.y -= 1
  if isKeyDown(S): moveDir.y += 1
  if isKeyDown(A): moveDir.x -= 1
  if isKeyDown(D): moveDir.x += 1
  
  if moveDir.length() > 0:
    moveDir = moveDir.normalize()
  
  result = PlayerInput(
    tick: pvp.serverTick,
    moveDir: moveDir,
    shooting: isMouseButtonDown(Left),
    mousePos: newVector2f(getMousePosition().x, getMousePosition().y),
    placingWall: isKeyPressed(E),
    wallPos: newVector2f(getMousePosition().x, getMousePosition().y),
    timestamp: epochTime()
  )

proc applyPlayerInput*(pvp: PvPGameState, playerIndex: int, input: PlayerInput, dt: float32) =
  ## Apply input to a player (used by both client and server)
  let player = pvp.players[playerIndex]
  
  # Don't process input if player is dead
  if player.hp <= 0:
    return
  
  # Movement
  if input.moveDir.length() > 0:
    player.vel = input.moveDir * player.speed
    let nextPos = player.pos + player.vel * dt
    
    # Check wall collisions
    var canMove = true
    for wall in pvp.walls:
      if checkPlayerWallCollision(nextPos, player.radius, wall):
        canMove = false
        break
    
    if canMove:
      player.pos = nextPos
    
    # Clamp to screen
    player.pos.x = clamp(player.pos.x, player.radius, pvp.screenWidth.float32 - player.radius)
    player.pos.y = clamp(player.pos.y, player.radius, pvp.screenHeight.float32 - player.radius)
  
  # Shooting
  if input.shooting and (pvp.gameTime - player.lastShot) >= player.fireRate:
    player.lastShot = pvp.gameTime
    
    # Create bullet
    let direction = (input.mousePos - player.pos).normalize()
    let bulletVel = direction * player.bulletSpeed
    
    let newBullet = Bullet(
      pos: player.pos + direction * (player.radius + 5),
      vel: bulletVel,
      radius: 5,
      damage: player.damage,
      fromPlayer: true,
      lifetime: 0,
      isHoming: false,
      isPiercing: false,
      isExplosive: false,
      bulletId: pvp.bulletIdCounter,
      bulletSkin: player.bulletSkinType
    )
    
    pvp.bulletIdCounter += 1
    pvp.bullets.add(newBullet)
    
    playSound(stShoot)
    
    # If host, broadcast bullet spawn
    if pvp.networkManager.isHost():
      let bulletState = BulletStateNet(
        id: newBullet.bulletId,
        pos: newBullet.pos,
        vel: newBullet.vel,
        radius: newBullet.radius,
        damage: newBullet.damage,
        fromPlayerIndex: playerIndex,
        isPiercing: newBullet.isPiercing,
        isExplosive: newBullet.isExplosive,
        isHoming: newBullet.isHoming
      )
      
      var packet = Packet(kind: ptBulletSpawn)
      packet.packetType = ptBulletSpawn
      packet.tick = pvp.serverTick
      packet.timestamp = epochTime()
      packet.bullet = bulletState
      pvp.networkManager.sendPacket(packet)
  
  # Wall placement
  if input.placingWall and player.walls > 0:
    # Check if valid placement (not too close to players)
    var validPlacement = true
    for i in 0..1:
      if distance(input.wallPos, pvp.players[i].pos) < 50:
        validPlacement = false
        break
    
    if validPlacement:
      let newWall = Wall(
        pos: input.wallPos,
        radius: 25,
        hp: 30,
        maxHp: 30,
        duration: 999,
        shootTimer: 0
      )
      
      pvp.walls.add(newWall)
      player.walls -= 1
      
      spawnExplosionPooled(pvp.particlePool, input.wallPos.x, input.wallPos.y, Brown, 15)
      playSound(stPowerUp)
      
      # If host, broadcast wall placement
      if pvp.networkManager.isHost():
        let wallState = WallStateNet(
          pos: newWall.pos,
          radius: newWall.radius,
          hp: newWall.hp,
          maxHp: newWall.maxHp,
          ownerIndex: playerIndex
        )
        
        var packet = Packet(kind: ptWallPlace)
        packet.packetType = ptWallPlace
        packet.tick = pvp.serverTick
        packet.timestamp = epochTime()
        packet.wall = wallState
        pvp.networkManager.sendPacket(packet)

proc updateBullets*(pvp: PvPGameState, dt: float32) =
  ## Update bullets (server-side authoritative)
  var i = 0
  while i < pvp.bullets.len:
    let bullet = pvp.bullets[i]
    bullet.pos = bullet.pos + bullet.vel * dt
    bullet.lifetime += dt
    
    # Remove if out of bounds or lifetime exceeded
    if bullet.pos.x < 0 or bullet.pos.x > pvp.screenWidth.float32 or
       bullet.pos.y < 0 or bullet.pos.y > pvp.screenHeight.float32 or
       bullet.lifetime > 5.0:
      
      if pvp.networkManager.isHost():
        var packet = Packet(kind: ptBulletDestroy)
        packet.packetType = ptBulletDestroy
        packet.tick = pvp.serverTick
        packet.timestamp = epochTime()
        packet.bulletId = bullet.bulletId
        pvp.networkManager.sendPacket(packet)
      
      pvp.bullets.delete(i)
      continue
    
    # Check player collisions
    for playerIdx in 0..1:
      let player = pvp.players[playerIdx]
      if player.hp <= 0 or player.invincibilityTimer > 0:
        continue
      
      if distance(bullet.pos, player.pos) < (bullet.radius + player.radius):
        # Hit player
        if pvp.networkManager.isHost():
          player.hp -= bullet.damage
          
          # Send damage packet
          var packet = Packet(kind: ptPlayerDamage)
          packet.packetType = ptPlayerDamage
          packet.tick = pvp.serverTick
          packet.timestamp = epochTime()
          packet.damagedPlayerIndex = playerIdx
          packet.damageAmount = bullet.damage
          packet.newHp = player.hp
          pvp.networkManager.sendPacket(packet)
          
          # Check for death
          if player.hp <= 0:
            let otherPlayerIdx = 1 - playerIdx
            pvp.players[otherPlayerIdx].kills += 1
            
            # Start respawn timer
            pvp.respawnTimers[playerIdx] = PVP_RESPAWN_TIME
            
            var deathPacket = Packet(kind: ptPlayerDeath)
            deathPacket.packetType = ptPlayerDeath
            deathPacket.tick = pvp.serverTick
            deathPacket.timestamp = epochTime()
            deathPacket.deadPlayerIndex = playerIdx
            pvp.networkManager.sendPacket(deathPacket)
            
            # Check win condition
            if pvp.players[otherPlayerIdx].kills >= PVP_KILL_LIMIT:
              pvp.gameOver = true
              pvp.winnerIndex = otherPlayerIdx
              
              var gameOverPacket = Packet(kind: ptGameOver)
              gameOverPacket.packetType = ptGameOver
              gameOverPacket.tick = pvp.serverTick
              gameOverPacket.timestamp = epochTime()
              gameOverPacket.winnerIndex = otherPlayerIdx
              gameOverPacket.reason = "Kill limit reached"
              pvp.networkManager.sendPacket(gameOverPacket)
        
        spawnExplosionPooled(pvp.particlePool, bullet.pos.x, bullet.pos.y, Red, 10)
        playSound(stPlayerHit)
        
        pvp.bullets.delete(i)
        i -= 1
        break
    
    # Check wall collisions
    var hitWall = false
    var wallIdx = 0
    while wallIdx < pvp.walls.len:
      let wall = pvp.walls[wallIdx]
      if distance(bullet.pos, wall.pos) < (bullet.radius + wall.radius):
        if pvp.networkManager.isHost():
          wall.hp -= bullet.damage
          
          if wall.hp <= 0:
            var packet = Packet(kind: ptWallDestroy)
            packet.packetType = ptWallDestroy
            packet.tick = pvp.serverTick
            packet.timestamp = epochTime()
            packet.wallIndex = wallIdx
            pvp.networkManager.sendPacket(packet)
            pvp.walls.delete(wallIdx)
          else:
            wallIdx += 1
        
        hitWall = true
        break
      wallIdx += 1
    
    if hitWall:
      pvp.bullets.delete(i)
      continue
    
    i += 1
proc updatePvPServer*(pvp: PvPGameState, dt: float32) =
  ## Server-side update (host only)
  pvp.serverTick += 1
  pvp.gameTime += dt
  
  # Update respawn timers
  for i in 0..1:
    if pvp.players[i].hp <= 0 and pvp.respawnTimers[i] > 0:
      pvp.respawnTimers[i] -= dt
      if pvp.respawnTimers[i] <= 0:
        # Respawn player
        pvp.players[i].hp = PVP_PLAYER_START_HP
        if i == 0:
          pvp.players[i].pos = newVector2f(pvp.screenWidth.float32 * 0.25, pvp.screenHeight.float32 * 0.5)
        else:
          pvp.players[i].pos = newVector2f(pvp.screenWidth.float32 * 0.75, pvp.screenHeight.float32 * 0.5)
        pvp.players[i].invincibilityTimer = 2.0  # 2 seconds of invincibility after respawn
        
        # Send respawn packet
        var respawnPacket = Packet(kind: ptPlayerDamage)  # Reuse damage packet to update HP
        respawnPacket.packetType = ptPlayerDamage
        respawnPacket.tick = pvp.serverTick
        respawnPacket.timestamp = epochTime()
        respawnPacket.damagedPlayerIndex = i
        respawnPacket.damageAmount = 0
        respawnPacket.newHp = PVP_PLAYER_START_HP
        pvp.networkManager.sendPacket(respawnPacket)
  
  # Update timers
  for player in pvp.players:
    if player.invincibilityTimer > 0:
      player.invincibilityTimer -= dt
  
  # Apply host's own input (stored from last capture)
  if pvp.lastHostInput.tick > 0:
    applyPlayerInput(pvp, pvp.localPlayerIndex, pvp.lastHostInput, dt)
  
  # Update bullets
  updateBullets(pvp, dt)
  
  # Update particles
  updateParticlePool(pvp.particlePool, dt)
  
  # Send game state snapshot at fixed rate
  if pvp.gameTime - pvp.lastSnapshotTime >= SNAPSHOT_RATE:
    pvp.lastSnapshotTime = pvp.gameTime
    
    # Build state snapshot
    var bulletStates: seq[BulletStateNet] = @[]
    for bullet in pvp.bullets:
      bulletStates.add(BulletStateNet(
        id: bullet.bulletId,
        pos: bullet.pos,
        vel: bullet.vel,
        radius: bullet.radius,
        damage: bullet.damage,
        fromPlayerIndex: if bullet.fromPlayer: pvp.localPlayerIndex else: pvp.remotePlayerIndex,
        isPiercing: bullet.isPiercing,
        isExplosive: bullet.isExplosive,
        isHoming: bullet.isHoming
      ))
    
    var wallStates: seq[WallStateNet] = @[]
    for wall in pvp.walls:
      wallStates.add(WallStateNet(
        pos: wall.pos,
        radius: wall.radius,
        hp: wall.hp,
        maxHp: wall.maxHp,
        ownerIndex: 0  # Track owner if needed
      ))
    
    let gameState = NetworkGameState(
      tick: pvp.serverTick,
      timestamp: epochTime(),
      players: [
        PlayerStateNet(
          pos: pvp.players[0].pos,
          vel: pvp.players[0].vel,
          hp: pvp.players[0].hp,
          maxHp: pvp.players[0].maxHp,
          coins: pvp.players[0].coins,
          kills: pvp.players[0].kills,
          walls: pvp.players[0].walls,
          damage: pvp.players[0].damage,
          speed: pvp.players[0].speed,
          invincibilityTimer: pvp.players[0].invincibilityTimer
        ),
        PlayerStateNet(
          pos: pvp.players[1].pos,
          vel: pvp.players[1].vel,
          hp: pvp.players[1].hp,
          maxHp: pvp.players[1].maxHp,
          coins: pvp.players[1].coins,
          kills: pvp.players[1].kills,
          walls: pvp.players[1].walls,
          damage: pvp.players[1].damage,
          speed: pvp.players[1].speed,
          invincibilityTimer: pvp.players[1].invincibilityTimer
        )
      ],
      bullets: bulletStates,
      walls: wallStates
    )
    
    var packet = Packet(kind: ptGameState)
    packet.packetType = ptGameState
    packet.tick = pvp.serverTick
    packet.timestamp = epochTime()
    packet.state = gameState
    
    pvp.networkManager.sendPacket(packet)

proc updatePvPClient*(pvp: PvPGameState, dt: float32) =
  ## Client-side update (prediction + reconciliation)
  pvp.gameTime += dt
  
  # Apply client-side prediction for local player
  let localPlayer = pvp.players[pvp.localPlayerIndex]
  updatePlayer(localPlayer, dt, pvp.screenWidth, pvp.screenHeight, pvp.walls)
  
  # Update particles locally
  updateParticlePool(pvp.particlePool, dt)

proc reconcileState*(pvp: PvPGameState, serverState: NetworkGameState) =
  ## Reconcile client state with authoritative server state
  # Update both players from server
  pvp.players[0].pos = serverState.players[0].pos
  pvp.players[0].vel = serverState.players[0].vel
  pvp.players[0].hp = serverState.players[0].hp
  pvp.players[0].maxHp = serverState.players[0].maxHp
  pvp.players[0].coins = serverState.players[0].coins
  pvp.players[0].kills = serverState.players[0].kills
  pvp.players[0].walls = serverState.players[0].walls
  
  pvp.players[1].pos = serverState.players[1].pos
  pvp.players[1].vel = serverState.players[1].vel
  pvp.players[1].hp = serverState.players[1].hp
  pvp.players[1].maxHp = serverState.players[1].maxHp
  pvp.players[1].coins = serverState.players[1].coins
  pvp.players[1].kills = serverState.players[1].kills
  pvp.players[1].walls = serverState.players[1].walls
  
  # Update bullets from server
  pvp.bullets = @[]
  for bulletState in serverState.bullets:
    let bullet = Bullet(
      pos: bulletState.pos,
      vel: bulletState.vel,
      radius: bulletState.radius,
      damage: bulletState.damage,
      fromPlayer: true,
      lifetime: 0,
      isHoming: bulletState.isHoming,
      isPiercing: bulletState.isPiercing,
      isExplosive: bulletState.isExplosive,
      bulletId: bulletState.id
    )
    pvp.bullets.add(bullet)
  
  # Update walls from server
  pvp.walls = @[]
  for wallState in serverState.walls:
    let wall = Wall(
      pos: wallState.pos,
      radius: wallState.radius,
      hp: wallState.hp,
      maxHp: wallState.maxHp,
      duration: 999,
      shootTimer: 0
    )
    pvp.walls.add(wall)

proc handleNetworkEvents*(pvp: PvPGameState) =
  ## Process all network events
  let events = pvp.networkManager.pollEvents()
  
  for event in events:
    case event.kind
    of neConnect:
      echo "[PVP] Connected to opponent"
    
    of neReceive:
      case event.packet.packetType
      of ptGameStart:
        pvp.countdownTimer = event.packet.countdownTime
        pvp.isCountingDown = true
      
      of ptPlayerInput:
        # Server receives client input
        if pvp.networkManager.isHost():
          applyPlayerInput(pvp, pvp.remotePlayerIndex, event.packet.input, 1.0/60.0)
      
      of ptGameState:
        # Client receives server state
        if pvp.networkManager.isClient():
          reconcileState(pvp, event.packet.state)
      
      of ptBulletSpawn:
        # Spawn bullet from packet
        let bulletState = event.packet.bullet
        let bullet = Bullet(
          pos: bulletState.pos,
          vel: bulletState.vel,
          radius: bulletState.radius,
          damage: bulletState.damage,
          fromPlayer: true,
          lifetime: 0,
          isHoming: bulletState.isHoming,
          isPiercing: bulletState.isPiercing,
          isExplosive: bulletState.isExplosive,
          bulletId: bulletState.id
        )
        pvp.bullets.add(bullet)
      
      of ptBulletDestroy:
        # Remove bullet
        var i = 0
        while i < pvp.bullets.len:
          if pvp.bullets[i].bulletId == event.packet.bulletId:
            pvp.bullets.delete(i)
            break
          i += 1
      
      of ptPlayerDamage:
        let playerIdx = event.packet.damagedPlayerIndex
        pvp.players[playerIdx].hp = event.packet.newHp
        
        # Spawn damage number
        let damageNum = DamageNumber(
          pos: pvp.players[playerIdx].pos,
          vel: newVector2f(0, -50),
          damage: event.packet.damageAmount,
          lifetime: 0,
          maxLifetime: 1.0,
          fromPlayer: false,
          isCritical: false,
          damageType: dtDefault
        )
        pvp.damageNumbers.add(damageNum)
      
      of ptPlayerDeath:
        let playerIdx = event.packet.deadPlayerIndex
        pvp.players[playerIdx].hp = 0
        spawnExplosionPooled(pvp.particlePool, pvp.players[playerIdx].pos.x, 
                            pvp.players[playerIdx].pos.y, Red, 30)
      
      of ptWallPlace:
        let wallState = event.packet.wall
        let wall = Wall(
          pos: wallState.pos,
          radius: wallState.radius,
          hp: wallState.hp,
          maxHp: wallState.maxHp,
          duration: 999,
          shootTimer: 0
        )
        pvp.walls.add(wall)
      
      of ptWallDestroy:
        if event.packet.wallIndex < pvp.walls.len:
          pvp.walls.delete(event.packet.wallIndex)
      
      of ptGameOver:
        pvp.gameOver = true
        pvp.winnerIndex = event.packet.winnerIndex
      
      else:
        discard
    
    of neDisconnect:
      echo "[PVP] Opponent disconnected: ", event.reason
      pvp.gameOver = true
      pvp.winnerIndex = pvp.localPlayerIndex  # Win by default
    
    else:
      discard

proc updatePvP*(pvp: PvPGameState, dt: float32) =
  ## Main PvP update function
  # Handle network events
  handleNetworkEvents(pvp)
  
  # Update countdown
  if pvp.isCountingDown:
    pvp.countdownTimer -= dt
    if pvp.countdownTimer <= 0:
      pvp.isCountingDown = false
      pvp.gameStarted = true
  
  if not pvp.gameStarted or pvp.gameOver:
    return
  
  # Capture and send local input
  if pvp.gameTime - pvp.lastInputSendTime >= INPUT_SEND_RATE:
    pvp.lastInputSendTime = pvp.gameTime
    
    let input = capturePlayerInput(pvp)
    
    # Store host input for server processing
    if pvp.networkManager.isHost():
      pvp.lastHostInput = input
    
    # Apply input locally (prediction)
    applyPlayerInput(pvp, pvp.localPlayerIndex, input, dt)
    
    # Send to server if client
    if pvp.networkManager.isClient():
      var packet = Packet(kind: ptPlayerInput)
      packet.packetType = ptPlayerInput
      packet.tick = pvp.serverTick
      packet.timestamp = epochTime()
      packet.input = input
      pvp.networkManager.sendPacket(packet)
    
    # Store for reconciliation
    pvp.pendingInputs.add((pvp.serverTick, input))
  
  # Update based on role
  if pvp.networkManager.isHost():
    updatePvPServer(pvp, dt)
  else:
    updatePvPClient(pvp, dt)
  
  # Update damage numbers
  var i = 0
  while i < pvp.damageNumbers.len:
    let dn = pvp.damageNumbers[i]
    dn.lifetime += dt
    dn.pos = dn.pos + dn.vel * dt
    dn.vel.y += 100 * dt  # Gravity
    
    if dn.lifetime >= dn.maxLifetime:
      pvp.damageNumbers.delete(i)
    else:
      i += 1
  
  # Send periodic pings
  if pvp.gameTime - pvp.lastPingTime >= 1.0:
    pvp.lastPingTime = pvp.gameTime
    pvp.networkManager.sendPing(pvp.serverTick)

proc drawPvP*(pvp: PvPGameState) =
  ## Draw PvP game state
  clearBackground(Color(r: 20, g: 20, b: 30, a: 255))
  
  # Draw arena bounds
  drawRectangleLines(
    Rectangle(x: 0, y: 0, width: pvp.screenWidth.float32, height: pvp.screenHeight.float32),
    2, Color(r: 100, g: 100, b: 150, a: 255)
  )
  
  # Draw walls
  for wall in pvp.walls:
    let healthPercent = wall.hp / wall.maxHp
    let wallColor = Color(
      r: uint8(100 + (1.0 - healthPercent) * 155),
      g: uint8(70 * healthPercent),
      b: 50,
      a: 255
    )
    drawCircle(Vector2(x: wall.pos.x, y: wall.pos.y), wall.radius, wallColor)
    drawCircleLines(wall.pos.x.int32, wall.pos.y.int32, wall.radius, Brown)
  
  # Draw bullets
  for bullet in pvp.bullets:
    drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius, Yellow)
  
  # Draw players
  for i in 0..1:
    let player = pvp.players[i]
    if player.hp <= 0:
      # Show respawn timer if player is dead
      if pvp.respawnTimers[i] > 0:
        let respawnText = "Respawning in " & $(pvp.respawnTimers[i].int + 1) & "..."
        let textWidth = measureText(respawnText, 20)
        let screenCenterX = pvp.screenWidth div 2
        let yPos = if i == pvp.localPlayerIndex: pvp.screenHeight - 100 else: 100
        drawText(respawnText, screenCenterX - textWidth div 2, yPos.int32, 20, 
                if i == pvp.localPlayerIndex: Color(r: 100, g: 200, b: 255, a: 255) 
                else: Color(r: 255, g: 100, b: 100, a: 255))
      continue
    
    # Player color based on index
    let playerColor = if i == pvp.localPlayerIndex:
      Color(r: 100, g: 200, b: 255, a: 255)  # Blue for local
    else:
      Color(r: 255, g: 100, b: 100, a: 255)  # Red for remote
    
    # Apply invincibility flashing
    let flashAlpha = if player.invincibilityTimer > 0:
      if (player.invincibilityTimer * 10).int mod 2 == 0: 255'u8 else: 100'u8
    else:
      255'u8
    
    let finalColor = Color(r: playerColor.r, g: playerColor.g, b: playerColor.b, a: flashAlpha)
    
    drawCircle(Vector2(x: player.pos.x, y: player.pos.y), player.radius, finalColor)
    drawCircleLines(player.pos.x.int32, player.pos.y.int32, player.radius, White)
    
    # Health bar
    let barWidth = 50.0
    let barHeight = 5.0
    let healthPercent = player.hp / player.maxHp
    
    drawRectangle(
      player.pos.x.int32 - (barWidth / 2).int32,
      (player.pos.y - player.radius - 15).int32,
      barWidth.int32,
      barHeight.int32,
      Color(r: 50, g: 50, b: 50, a: 255)
    )
    
    drawRectangle(
      player.pos.x.int32 - (barWidth / 2).int32,
      (player.pos.y - player.radius - 15).int32,
      (barWidth * healthPercent).int32,
      barHeight.int32,
      if healthPercent > 0.5: Green else: Red
    )
  
  # Draw particles
  drawParticlePool(pvp.particlePool)
  
  # Draw damage numbers
  for dn in pvp.damageNumbers:
    let alpha = uint8((1.0 - dn.lifetime / dn.maxLifetime) * 255)
    let textColor = Color(r: 255, g: 255, b: 100, a: alpha)
    let damageText = $dn.damage.int
    drawText(damageText, dn.pos.x.int32 - 10, dn.pos.y.int32, 20, textColor)
  
  # Draw HUD
  # Score
  let scoreText = "P1: " & $pvp.players[0].kills & " | P2: " & $pvp.players[1].kills
  drawText(scoreText, pvp.screenWidth div 2 - 60, 10, 20, White)
  
  # Time
  let timeRemaining = PVP_TIME_LIMIT - pvp.gameTime
  let minutes = (timeRemaining / 60).int
  let seconds = (timeRemaining.int mod 60)
  let timeText = $minutes & ":" & (if seconds < 10: "0" else: "") & $seconds
  drawText(timeText, pvp.screenWidth div 2 - 30, 35, 20, White)
  
  # Latency
  if pvp.networkManager.isClient():
    let latencyText = "Ping: " & $pvp.networkManager.getLatency().int & "ms"
    drawText(latencyText, 10, 10, 20, Yellow)
  
  # Countdown overlay
  if pvp.isCountingDown:
    let countdownValue = max(pvp.countdownTimer, 0.0).int + 1
    let countdownText = if countdownValue > 0: $countdownValue else: "FIGHT!"
    let textWidth = measureText(countdownText, 80)
    
    drawRectangle(0, 0, pvp.screenWidth, pvp.screenHeight, 
                 Color(r: 0, g: 0, b: 0, a: 150))
    drawText(countdownText, 
            pvp.screenWidth div 2 - textWidth div 2,
            pvp.screenHeight div 2 - 40,
            80, Yellow)
  
  # Game over overlay
  if pvp.gameOver:
    let winnerText = if pvp.winnerIndex == pvp.localPlayerIndex:
      "YOU WIN!"
    elif pvp.winnerIndex == -1:
      "DRAW!"
    else:
      "YOU LOSE!"
    
    let textWidth = measureText(winnerText, 60)
    
    drawRectangle(0, 0, pvp.screenWidth, pvp.screenHeight,
                 Color(r: 0, g: 0, b: 0, a: 200))
    drawText(winnerText,
            pvp.screenWidth div 2 - textWidth div 2,
            pvp.screenHeight div 2 - 30,
            60,
            if pvp.winnerIndex == pvp.localPlayerIndex: Green else: Red)
    
    let returnText = "Press ESC to return to menu"
    let returnWidth = measureText(returnText, 20)
    drawText(returnText,
            pvp.screenWidth div 2 - returnWidth div 2,
            pvp.screenHeight div 2 + 50,
            20, White)
