## PvP Game Mode Logic
## Handles 1v1 player vs player combat

import raylib, types, player, bullet, wall, particle, particle_pool, sound, network/network_types, network/network, math, times, settings

const
  PVP_PLAYER_START_HP = 3.0  # Reduced HP for faster kills
  PVP_PLAYER_START_SPEED = 200.0
  PVP_PLAYER_START_DAMAGE = 1.0
  PVP_PLAYER_START_FIRE_RATE = 0.375
  PVP_PLAYER_START_BULLET_SPEED = 415.0
  PVP_PLAYER_START_COINS = 100
  PVP_PLAYER_START_WALLS = 3
  PVP_RESPAWN_TIME = 3.0
  PVP_KILL_LIMIT = 5  # First to 5 kills wins
  PVP_TIME_LIMIT = 180.0  # 3 minutes
  SNAPSHOT_RATE = 0.033  # 30 Hz (every 33ms)
  INPUT_SEND_RATE = 0.033  # 30 Hz - match snapshot rate to reduce reconciliation conflicts

type
  PvPGameState* = ref object
    networkManager*: NetworkManager
    localPlayerIndex*: int  # 0-15
    maxPlayers*: int  # Maximum number of players (2-16)
    players*: seq[Player]  # Dynamic player list
    bullets*: seq[Bullet]
    walls*: seq[Wall]
    particlePool*: ParticlePool
    serverTick*: int
    gameTime*: float32
    gameStarted*: bool
    gameOver*: bool
    winnerIndex*: int
    gameOverReason*: string  # Track why game ended
    inputBuffer*: seq[PlayerInput]
    lastSnapshotTime*: float32
    lastInputSendTime*: float32
    pendingInputs*: seq[tuple[tick: int, input: PlayerInput]]  # For reconciliation
    screenWidth*: int32
    screenHeight*: int32
    bulletIdCounter*: int  # Local bullet ID counter
    countdownTimer*: float32
    isCountingDown*: bool
    damageNumbers*: seq[DamageNumber]
    lastPingTime*: float32
    respawnTimers*: seq[float32]  # Respawn timers for each player
    lastInputs*: seq[PlayerInput]  # Store last input for each player (server processing)

proc getSpawnPosition(playerIndex, totalPlayers: int, screenWidth, screenHeight: float32): Vector2f =
  ## Calculate spawn position for a player based on their index
  ## Distributes players evenly around the screen
  if totalPlayers == 2:
    # Classic 1v1 positioning
    if playerIndex == 0:
      return newVector2f(screenWidth * 0.25, screenHeight * 0.5)
    else:
      return newVector2f(screenWidth * 0.75, screenHeight * 0.5)
  else:
    # Distribute players in a circle
    let angle = (playerIndex.float / totalPlayers.float) * 2.0 * PI
    let radius = min(screenWidth, screenHeight) * 0.35
    let centerX = screenWidth * 0.5
    let centerY = screenHeight * 0.5
    return newVector2f(
      centerX + cos(angle) * radius,
      centerY + sin(angle) * radius
    )

proc newPvPGameState*(screenWidth, screenHeight: int32, isHost: bool, maxPlayers: int, connectedPlayers: seq[tuple[index: int, skinType, bulletSkinType, shapeType, particleSkinType: int]]): PvPGameState =
  let emptyInput = PlayerInput(
    tick: 0,
    playerIndex: 0,
    moveDir: newVector2f(0, 0),
    shooting: false,
    mousePos: newVector2f(0, 0),
    placingWall: false,
    wallPos: newVector2f(0, 0),
    timestamp: 0
  )
  
  result = PvPGameState(
    networkManager: nil,  # Will be assigned from the window's network manager
    localPlayerIndex: if isHost: 0 else: -1,  # Will be set properly for clients
    maxPlayers: maxPlayers,
    players: @[],
    serverTick: 0,
    gameTime: 0,
    gameStarted: false,
    gameOver: false,
    winnerIndex: -1,
    gameOverReason: "",
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
    respawnTimers: @[],
    lastInputs: @[]
  )
  
  # Initialize player slots
  for i in 0..<maxPlayers:
    let spawnPos = getSpawnPosition(i, maxPlayers, screenWidth.float32, screenHeight.float32)
    let player = newPlayer(spawnPos.x, spawnPos.y)
    player.hp = PVP_PLAYER_START_HP
    player.maxHp = PVP_PLAYER_START_HP
    player.coins = PVP_PLAYER_START_COINS
    player.walls = PVP_PLAYER_START_WALLS
    player.damage = PVP_PLAYER_START_DAMAGE
    player.bulletSpeed = PVP_PLAYER_START_BULLET_SPEED
    player.fireRate = PVP_PLAYER_START_FIRE_RATE
    player.speed = PVP_PLAYER_START_SPEED
    
    # Set cosmetics for connected players
    var cosmeticsSet = false
    for connectedPlayer in connectedPlayers:
      if connectedPlayer.index == i:
        player.skinType = connectedPlayer.skinType
        player.bulletSkinType = connectedPlayer.bulletSkinType
        player.shapeType = connectedPlayer.shapeType
        player.particleSkinType = connectedPlayer.particleSkinType
        cosmeticsSet = true
        break
    
    # If no cosmetics were set and this is the local player (host), use global settings
    if not cosmeticsSet and isHost and i == 0:
      player.skinType = globalSettings.playerSkin
      player.bulletSkinType = globalSettings.bulletSkin
      player.shapeType = globalSettings.playerShape
      player.particleSkinType = globalSettings.particleEffect
    
    result.players.add(player)
    result.respawnTimers.add(0.0)
    result.lastInputs.add(emptyInput)
  
  result.bullets = @[]
  result.walls = @[]
  result.particlePool = newParticlePool(2000)

proc startCountdown*(pvp: PvPGameState) =
  pvp.isCountingDown = true
  pvp.countdownTimer = 3.0
  
  # Reset the receive timer to prevent false timeout from lobby waiting time
  pvp.networkManager.resetReceiveTimer()
  
  if pvp.networkManager.isHost():
    # Send game start packet
    var packet = Packet(kind: ptGameStart)
    packet.packetType = ptGameStart
    packet.tick = pvp.serverTick
    packet.timestamp = epochTime()
    packet.countdownTime = pvp.countdownTimer
    pvp.networkManager.sendPacket(packet)

proc capturePlayerInput*(pvp: PvPGameState): PlayerInput =
  var moveDir = newVector2f(0, 0)
  if isKeyDown(W): moveDir.y -= 1
  if isKeyDown(S): moveDir.y += 1
  if isKeyDown(A): moveDir.x -= 1
  if isKeyDown(D): moveDir.x += 1
  
  if moveDir.length() > 0:
    moveDir = moveDir.normalize()
  
  result = PlayerInput(
    tick: pvp.serverTick,
    playerIndex: pvp.localPlayerIndex,
    moveDir: moveDir,
    shooting: isMouseButtonDown(Left),
    mousePos: newVector2f(getMousePosition().x, getMousePosition().y),
    placingWall: isKeyPressed(E),
    wallPos: newVector2f(getMousePosition().x, getMousePosition().y),
    timestamp: epochTime()
  )

proc applyPlayerInput*(pvp: PvPGameState, playerIndex: int, input: PlayerInput, dt: float32) =
  ## Apply input to a player (used by both client and server)
  
  # Validate player index
  if playerIndex < 0 or playerIndex >= pvp.players.len:
    echo "[PVP ERROR] Invalid player index in applyPlayerInput: ", playerIndex
    return
  
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
  
  # Shooting - ALWAYS CREATE BULLET LOCALLY for immediate feedback
  if input.shooting and (pvp.gameTime - player.lastShot) >= player.fireRate:
    player.lastShot = pvp.gameTime
    
    # Create bullet with player-specific ID range to prevent collisions
    # Player 0 (host): IDs 0-999999, Player 1 (client): IDs 1000000-1999999
    let direction = (input.mousePos - player.pos).normalize()
    let bulletVel = direction * player.bulletSpeed
    let bulletId = playerIndex * 1000000 + pvp.bulletIdCounter
    
    let newBullet = Bullet(
      pos: player.pos + direction * (player.radius + 5),
      vel: bulletVel,
      radius: 7.5,  # Larger bullets for easier hits
      damage: player.damage,
      fromPlayer: true,
      lifetime: 0,
      isHoming: false,
      isPiercing: false,
      isExplosive: false,
      bulletId: bulletId,
      bulletSkin: player.bulletSkinType,
      ownerPlayerIndex: playerIndex  # CRITICAL: Track which player shot this bullet
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
        isHoming: newBullet.isHoming,
        bulletSkin: newBullet.bulletSkin
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
    for i in 0..<pvp.players.len:
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
    for playerIdx in 0..<pvp.players.len:
      let player = pvp.players[playerIdx]
      if player.hp <= 0 or player.invincibilityTimer > 0:
        continue
      
      # CRITICAL FIX: Prevent bullets from hitting their own shooter
      if bullet.ownerPlayerIndex == playerIdx:
        continue  # Skip collision check for the player who shot this bullet
      
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
            # Award kill to the bullet owner
            if bullet.ownerPlayerIndex >= 0 and bullet.ownerPlayerIndex < pvp.players.len:
              pvp.players[bullet.ownerPlayerIndex].kills += 1
            
            # Start respawn timer
            pvp.respawnTimers[playerIdx] = PVP_RESPAWN_TIME
            
            var deathPacket = Packet(kind: ptPlayerDeath)
            deathPacket.packetType = ptPlayerDeath
            deathPacket.tick = pvp.serverTick
            deathPacket.timestamp = epochTime()
            deathPacket.deadPlayerIndex = playerIdx
            pvp.networkManager.sendPacket(deathPacket)
            
            # Check win condition - find player with most kills
            var maxKills = 0
            var winningPlayerIdx = -1
            for checkIdx in 0..<pvp.players.len:
              if pvp.players[checkIdx].kills > maxKills:
                maxKills = pvp.players[checkIdx].kills
                winningPlayerIdx = checkIdx
            
            if maxKills >= PVP_KILL_LIMIT:
              pvp.gameOver = true
              pvp.winnerIndex = winningPlayerIdx
              pvp.gameOverReason = "Kill limit reached"
              
              var gameOverPacket = Packet(kind: ptGameOver)
              gameOverPacket.packetType = ptGameOver
              gameOverPacket.tick = pvp.serverTick
              gameOverPacket.timestamp = epochTime()
              gameOverPacket.winnerIndex = winningPlayerIdx
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
  for i in 0..<pvp.players.len:
    if pvp.players[i].hp <= 0 and pvp.respawnTimers[i] > 0:
      pvp.respawnTimers[i] -= dt
      if pvp.respawnTimers[i] <= 0:
        # Respawn player at their spawn position
        pvp.players[i].hp = PVP_PLAYER_START_HP
        pvp.players[i].pos = getSpawnPosition(i, pvp.players.len, pvp.screenWidth.float32, pvp.screenHeight.float32)
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
  
  # NOTE: Host's input is NOT applied here - it's already applied via prediction in main update
  # This ensures fairness: both host and client use the same predict->reconcile flow
  # Server simulation just processes all remote clients' inputs
  
  # Apply all clients' inputs (stored from network)
  for i in 0..<pvp.players.len:
    if i != pvp.localPlayerIndex and pvp.lastInputs[i].tick >= 0:
      applyPlayerInput(pvp, i, pvp.lastInputs[i], dt)
  
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
        fromPlayerIndex: bullet.ownerPlayerIndex,
        isPiercing: bullet.isPiercing,
        isExplosive: bullet.isExplosive,
        isHoming: bullet.isHoming,
        bulletSkin: bullet.bulletSkin
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
    
    # Build player states dynamically
    var playerStates: seq[PlayerStateNet] = @[]
    for i in 0..<pvp.players.len:
      playerStates.add(PlayerStateNet(
        playerIndex: i,
        isActive: pvp.players[i].hp > 0,  # Mark if player is alive
        pos: pvp.players[i].pos,
        vel: pvp.players[i].vel,
        hp: pvp.players[i].hp,
        maxHp: pvp.players[i].maxHp,
        coins: pvp.players[i].coins,
        kills: pvp.players[i].kills,
        walls: pvp.players[i].walls,
        damage: pvp.players[i].damage,
        speed: pvp.players[i].speed,
        invincibilityTimer: pvp.players[i].invincibilityTimer,
        skinType: pvp.players[i].skinType,
        bulletSkinType: pvp.players[i].bulletSkinType,
        shapeType: pvp.players[i].shapeType,
        particleSkinType: pvp.players[i].particleSkinType
      ))
    
    let gameState = NetworkGameState(
      tick: pvp.serverTick,
      timestamp: epochTime(),
      maxPlayers: pvp.maxPlayers,
      players: playerStates,
      bullets: bulletStates,
      walls: wallStates
    )
    
    var packet = Packet(kind: ptGameState)
    packet.packetType = ptGameState
    packet.tick = pvp.serverTick
    packet.timestamp = epochTime()
    packet.state = gameState
    
    pvp.networkManager.sendPacket(packet)
    
    # Host should also reconcile their own state for fairness
    # This ensures host experiences same prediction+reconciliation as client
    # Apply server state to host (inline reconciliation for simplicity)
    let localIdx = pvp.localPlayerIndex
    
    # Reconcile all other players fully (not local player)
    for i in 0..<pvp.players.len:
      if i != localIdx and i < gameState.players.len:
        pvp.players[i].pos = gameState.players[i].pos
        pvp.players[i].vel = gameState.players[i].vel
        pvp.players[i].hp = gameState.players[i].hp
        pvp.players[i].maxHp = gameState.players[i].maxHp
        pvp.players[i].coins = gameState.players[i].coins
        pvp.players[i].kills = gameState.players[i].kills
        pvp.players[i].walls = gameState.players[i].walls
        pvp.players[i].invincibilityTimer = gameState.players[i].invincibilityTimer
    
    # Reconcile host's own player - TRUST CLIENT PREDICTION
    # Even the host should trust their local prediction to maintain consistency
    if localIdx >= 0 and localIdx < gameState.players.len:
      let serverPos = gameState.players[localIdx].pos
      let clientPos = pvp.players[localIdx].pos
      let posDiff = sqrt((serverPos.x - clientPos.x) * (serverPos.x - clientPos.x) + 
                         (serverPos.y - clientPos.y) * (serverPos.y - clientPos.y))
      
      if posDiff > 150.0:
        # LARGE desync - snap immediately
        pvp.players[localIdx].pos = serverPos
      elif posDiff > 50.0:
        # MEDIUM desync - gentle interpolation
        let interpSpeed = 0.15
        pvp.players[localIdx].pos.x = pvp.players[localIdx].pos.x * (1.0 - interpSpeed) + serverPos.x * interpSpeed
        pvp.players[localIdx].pos.y = pvp.players[localIdx].pos.y * (1.0 - interpSpeed) + serverPos.y * interpSpeed
      # else: SMALL desync - trust prediction
      
      # Always update other host data from server
      pvp.players[localIdx].vel = gameState.players[localIdx].vel
      pvp.players[localIdx].hp = gameState.players[localIdx].hp
      pvp.players[localIdx].maxHp = gameState.players[localIdx].maxHp
      pvp.players[localIdx].coins = gameState.players[localIdx].coins
      pvp.players[localIdx].kills = gameState.players[localIdx].kills
      pvp.players[localIdx].walls = gameState.players[localIdx].walls
      pvp.players[localIdx].invincibilityTimer = gameState.players[localIdx].invincibilityTimer

proc updatePvPClient*(pvp: PvPGameState, dt: float32) =
  ## Client-side update (prediction + reconciliation)
  ## Input is now applied immediately in main updatePvP for responsive feel
  ## This function handles additional client-only updates
  pvp.gameTime += dt
  
  # Update bullets locally for smooth interpolation between server snapshots
  # Server will reconcile with authoritative state
  var i = 0
  while i < pvp.bullets.len:
    let bullet = pvp.bullets[i]
    bullet.pos = bullet.pos + bullet.vel * dt
    bullet.lifetime += dt
    
    # Remove if out of bounds or lifetime exceeded (will be reconciled by server)
    if bullet.pos.x < 0 or bullet.pos.x > pvp.screenWidth.float32 or
       bullet.pos.y < 0 or bullet.pos.y > pvp.screenHeight.float32 or
       bullet.lifetime > 5.0:
      pvp.bullets.delete(i)
      continue
    
    i += 1
  
  # Update particles locally
  updateParticlePool(pvp.particlePool, dt)

proc reconcileState*(pvp: PvPGameState, serverState: NetworkGameState) =
  ## Reconcile client state with authoritative server state
  ## Server is ALWAYS authoritative - client just renders smoothly
  
  # Sync client's server tick
  pvp.serverTick = serverState.tick
  
  let localIdx = pvp.localPlayerIndex
  
  # Update all remote players - full update from server
  for i in 0..<pvp.players.len:
    if i != localIdx:
      pvp.players[i].pos = serverState.players[i].pos
      pvp.players[i].vel = serverState.players[i].vel
      pvp.players[i].hp = serverState.players[i].hp
      pvp.players[i].maxHp = serverState.players[i].maxHp
      pvp.players[i].coins = serverState.players[i].coins
      pvp.players[i].kills = serverState.players[i].kills
      pvp.players[i].walls = serverState.players[i].walls
      pvp.players[i].invincibilityTimer = serverState.players[i].invincibilityTimer
      pvp.players[i].skinType = serverState.players[i].skinType
      pvp.players[i].bulletSkinType = serverState.players[i].bulletSkinType
      pvp.players[i].shapeType = serverState.players[i].shapeType
      pvp.players[i].particleSkinType = serverState.players[i].particleSkinType
  
  # Local player - TRUST CLIENT PREDICTION, only reconcile on large desyncs
  # The server state is always behind due to network latency, so we avoid
  # reconciling small differences to prevent stuttering/rubber-banding
  let serverPos = serverState.players[localIdx].pos
  let clientPos = pvp.players[localIdx].pos
  
  # Calculate position difference
  let posDiff = sqrt((serverPos.x - clientPos.x) * (serverPos.x - clientPos.x) + 
                     (serverPos.y - clientPos.y) * (serverPos.y - clientPos.y))
  
  if posDiff > 150.0:
    # LARGE desync (>150 pixels) - snap immediately to fix severe issues
    pvp.players[localIdx].pos = serverPos
  elif posDiff > 50.0:
    # MEDIUM desync (50-150 pixels) - gentle interpolation
    # This handles gradual drift without stuttering
    let interpSpeed = 0.15  # Slow, gentle correction
    pvp.players[localIdx].pos.x = pvp.players[localIdx].pos.x * (1.0 - interpSpeed) + serverPos.x * interpSpeed
    pvp.players[localIdx].pos.y = pvp.players[localIdx].pos.y * (1.0 - interpSpeed) + serverPos.y * interpSpeed
  # else: SMALL desync (<50 pixels) - trust client prediction completely
  # This prevents stuttering from normal network latency
  
  # Always update all other data from server
  pvp.players[localIdx].vel = serverState.players[localIdx].vel
  pvp.players[localIdx].hp = serverState.players[localIdx].hp
  pvp.players[localIdx].maxHp = serverState.players[localIdx].maxHp
  pvp.players[localIdx].coins = serverState.players[localIdx].coins
  pvp.players[localIdx].kills = serverState.players[localIdx].kills
  pvp.players[localIdx].walls = serverState.players[localIdx].walls
  pvp.players[localIdx].invincibilityTimer = serverState.players[localIdx].invincibilityTimer
  
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
      bulletId: bulletState.id,
      bulletSkin: bulletState.bulletSkin,
      ownerPlayerIndex: bulletState.fromPlayerIndex  # CRITICAL: Preserve owner from server
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
  # Create callback to provide host's cosmetics when accepting connections
  proc getHostCosmetics(): tuple[skinType, bulletSkinType, shapeType, particleSkinType: int] =
    return (
      skinType: pvp.players[0].skinType,
      bulletSkinType: pvp.players[0].bulletSkinType,
      shapeType: pvp.players[0].shapeType,
      particleSkinType: pvp.players[0].particleSkinType
    )
  
  let events = pvp.networkManager.pollEvents(getHostCosmetics)
  
  for event in events:
    case event.kind
    of neConnect:
      echo "[PVP] Player ", event.connectPlayerIndex, " connected"
      # Apply remote player's cosmetics
      let playerIdx = event.connectPlayerIndex
      if playerIdx >= 0 and playerIdx < pvp.players.len:
        pvp.players[playerIdx].skinType = event.remoteSkinType
        pvp.players[playerIdx].bulletSkinType = event.remoteBulletSkinType
        pvp.players[playerIdx].shapeType = event.remoteShapeType
        pvp.players[playerIdx].particleSkinType = event.remoteParticleSkinType
    
    of neReceive:
      case event.packet.packetType
      of ptGameStart:
        pvp.countdownTimer = event.packet.countdownTime
        pvp.isCountingDown = true
        # Client also needs to disable timeout during countdown
        pvp.networkManager.resetReceiveTimer()
      
      of ptPlayerInput:
        # Server receives client input - store it, don't apply immediately
        if pvp.networkManager.isHost():
          # Store the latest client input to apply in next server update
          let playerIndex = event.packet.input.playerIndex
          if playerIndex >= 0 and playerIndex < pvp.lastInputs.len:
            pvp.lastInputs[playerIndex] = event.packet.input
      
      of ptGameState:
        # Client receives server state
        if pvp.networkManager.isClient():
          reconcileState(pvp, event.packet.state)
      
      of ptBulletSpawn:
        # Spawn bullet from packet - check for duplicates first (client-side prediction)
        let bulletState = event.packet.bullet
        
        # Check if bullet already exists (client may have predicted it)
        var bulletExists = false
        for existingBullet in pvp.bullets:
          if existingBullet.bulletId == bulletState.id:
            bulletExists = true
            break
        
        # Only add if it doesn't exist (prevents duplicates from client prediction)
        if not bulletExists:
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
            bulletId: bulletState.id,
            bulletSkin: bulletState.bulletSkin,
            ownerPlayerIndex: bulletState.fromPlayerIndex  # CRITICAL: Preserve owner
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
        pvp.gameOverReason = event.packet.reason
        pvp.isCountingDown = false  # Stop countdown if it's running
        pvp.gameStarted = true  # Mark game as started so it can end properly
      
      else:
        discard
    
    of neDisconnect:
      echo "[PVP] Player ", event.disconnectPlayerIndex, " disconnected: ", event.reason
      
      # In multiplayer, handle player disconnection
      # For now, if ANY player disconnects, end the game
      # TODO: In future, could support continuing with remaining players
      pvp.gameOver = true
      pvp.isCountingDown = false  # Stop countdown if it's running
      pvp.gameStarted = true  # Mark game as started so it can end properly
      
      # Distinguish between graceful disconnect and timeout
      if event.reason == "Connection timeout":
        # Timeout - server is authoritative
        if pvp.networkManager.isHost():
          # Host wins on timeout (disconnected player loses)
          pvp.winnerIndex = pvp.localPlayerIndex
          pvp.gameOverReason = "Player " & $event.disconnectPlayerIndex & " disconnected"
          
          # Send game over packet to notify remaining clients
          var gameOverPacket = Packet(kind: ptGameOver)
          gameOverPacket.packetType = ptGameOver
          gameOverPacket.tick = pvp.serverTick
          gameOverPacket.timestamp = epochTime()
          gameOverPacket.winnerIndex = pvp.localPlayerIndex
          gameOverPacket.reason = "Player disconnected"
          pvp.networkManager.sendPacket(gameOverPacket)
        else:
          # Client lost connection (timeout) - they lose
          # Find a player who is still connected to be the winner
          pvp.winnerIndex = 0  # Default to host
          pvp.gameOverReason = "Connection lost"
      else:
        # Graceful disconnect (player sent ptDisconnect packet)
        # Whoever RECEIVES the disconnect packet continues/wins
        pvp.winnerIndex = pvp.localPlayerIndex
        pvp.gameOverReason = "Player forfeited"
    
    else:
      discard

proc updatePvP*(pvp: PvPGameState, dt: float32) =
  ## Main PvP update function
  
  # CRITICAL: Validate local player index
  if pvp.localPlayerIndex < 0 or pvp.localPlayerIndex >= pvp.players.len:
    echo "[PVP ERROR] Invalid local player index: ", pvp.localPlayerIndex, " (max: ", pvp.players.len - 1, ")"
    return
  
  # Handle network events FIRST
  handleNetworkEvents(pvp)
  
  # Update countdown
  if pvp.isCountingDown:
    pvp.gameTime += dt  # Update time FIRST
    pvp.countdownTimer -= dt
    if pvp.countdownTimer <= 0:
      pvp.isCountingDown = false
      pvp.gameStarted = true
      # Re-enable timeout check now that countdown is over
      pvp.networkManager.enableTimeoutCheck()
    
    # During countdown, send periodic pings to keep connection alive
    if pvp.gameTime - pvp.lastPingTime >= 1.0:
      pvp.lastPingTime = pvp.gameTime
      pvp.networkManager.sendPing(pvp.serverTick)
    
    return  # Don't process game logic during countdown
  
  if pvp.gameOver:
    return
  
  # Capture input every frame
  let input = capturePlayerInput(pvp)

  # Server will reconcile with authoritative state for both players
  applyPlayerInput(pvp, pvp.localPlayerIndex, input, dt)
  
  # Send input to server at regular rate
  if pvp.gameTime - pvp.lastInputSendTime >= INPUT_SEND_RATE:
    pvp.lastInputSendTime = pvp.gameTime
    
    # Store local player's input for server processing
    if pvp.localPlayerIndex >= 0 and pvp.localPlayerIndex < pvp.lastInputs.len:
      pvp.lastInputs[pvp.localPlayerIndex] = input
    
    # Send to server if client
    if pvp.networkManager.isClient():
      var packet = Packet(kind: ptPlayerInput)
      packet.packetType = ptPlayerInput
      packet.tick = pvp.serverTick
      packet.timestamp = epochTime()
      packet.input = input
      pvp.networkManager.sendPacket(packet)
  
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
  
  # Draw bullets with skin support
  for bullet in pvp.bullets:
    drawBullet(bullet, false, false, pvp.gameTime)
  
  # Draw players with cosmetics
  for i in 0..<pvp.maxPlayers:
    if i >= pvp.players.len:
      break
    let player = pvp.players[i]
    if player.hp <= 0:
      # Show respawn timer if player is dead
      if i < pvp.respawnTimers.len and pvp.respawnTimers[i] > 0:
        let respawnText = "Respawning in " & $(pvp.respawnTimers[i].int + 1) & "..."
        let textWidth = measureText(respawnText, 20)
        let screenCenterX = pvp.screenWidth div 2
        let yPos = if i == pvp.localPlayerIndex: pvp.screenHeight - 100 else: 100
        drawText(respawnText, screenCenterX - textWidth div 2, yPos.int32, 20,
                if i == pvp.localPlayerIndex: Color(r: 100, g: 200, b: 255, a: 255)
                else: Color(r: 255, g: 100, b: 100, a: 255))
      continue

    # Draw player using their cosmetics
    drawPlayer(player)
    
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
  # Score - show all connected players
  var scoreText = ""
  for i in 0..<pvp.players.len:
    if scoreText.len > 0:
      scoreText &= " | "
    scoreText &= "P" & $(i + 1) & ": " & $pvp.players[i].kills

  # Center the text based on its length (rough approximation)
  let scoreX = max(10, pvp.screenWidth div 2 - (scoreText.len * 4))
  drawText(scoreText, scoreX.int32, 10, 20, White)
  
  # Time
  let timeRemaining = PVP_TIME_LIMIT - pvp.gameTime
  let minutes = (timeRemaining / 60).int
  let seconds = (timeRemaining.int mod 60)
  let timeText = $minutes & ":" & (if seconds < 10: "0" else: "") & $seconds
  drawText(timeText, pvp.screenWidth div 2 - 30, 35, 20, White)
  
  # Latency
  if pvp.networkManager.isClient():
    # Clamp latency to prevent int overflow (float32 -> int conversion can overflow)
    let pingValue = min(pvp.networkManager.getLatency(), 9999.0).int
    let latencyText = "Ping: " & $pingValue & "ms"
    drawText(latencyText, 10, 10, 20, Yellow)
  
  # Countdown overlay (don't show if game is over)
  if pvp.isCountingDown and not pvp.gameOver:
    let countdownValue = max(pvp.countdownTimer, 0.0).int + 1
    let countdownText = if countdownValue > 0: $countdownValue else: "FIGHT!"
    let textWidth = measureText(countdownText, 80)
    
    drawRectangle(0, 0, pvp.screenWidth, pvp.screenHeight, 
                 Color(r: 0, g: 0, b: 0, a: 150))
    drawText(countdownText, 
            pvp.screenWidth div 2 - textWidth div 2,
            pvp.screenHeight div 2 - 40,
            80, Yellow)
    
    # Draw arrow pointing to local player with "YOU" label
    let localPlayer = pvp.players[pvp.localPlayerIndex]
    let arrowColor = Color(r: 100, g: 255, b: 100, a: 255)  # Bright green
    
    # Animated bouncing arrow
    let bounceOffset = sin(pvp.gameTime * 5) * 10
    let arrowY = localPlayer.pos.y - localPlayer.radius - 50 + bounceOffset
    
    # Draw "YOU" text above arrow
    let youText = "YOU"
    let youWidth = measureText(youText, 30)
    drawText(youText, 
            localPlayer.pos.x.int32 - youWidth div 2,
            (arrowY - 40).int32,
            30, arrowColor)
    
    # Draw downward pointing arrow (triangle)
    let arrowSize = 20.0
    let arrowTipX = localPlayer.pos.x
    let arrowTipY = arrowY + arrowSize
    let arrowLeftX = localPlayer.pos.x - arrowSize * 0.6
    let arrowRightX = localPlayer.pos.x + arrowSize * 0.6
    let arrowTopY = arrowY
    
    drawTriangle(
      Vector2(x: arrowTipX, y: arrowTipY),      # Bottom tip
      Vector2(x: arrowLeftX, y: arrowTopY),     # Top left
      Vector2(x: arrowRightX, y: arrowTopY),    # Top right
      arrowColor
    )
    
    # Draw arrow outline for better visibility
    drawTriangleLines(
      Vector2(x: arrowTipX, y: arrowTipY),
      Vector2(x: arrowLeftX, y: arrowTopY),
      Vector2(x: arrowRightX, y: arrowTopY),
      White
    )
  
  # Game over overlay
  if pvp.gameOver:
    # Determine main message based on game over reason
    let winnerText = case pvp.gameOverReason
      of "Opponent disconnected":
        "OPPONENT DISCONNECTED - YOU WIN!"
      of "Connection lost":
        "CONNECTION LOST - YOU LOSE!"
      of "Opponent forfeited":
        "OPPONENT FORFEITED - YOU WIN!"
      else:
        if pvp.winnerIndex == pvp.localPlayerIndex:
          "YOU WIN!"
        elif pvp.winnerIndex == -1:
          "DRAW!"
        else:
          "YOU LOSE!"
    
    let textSize: int32 = if pvp.gameOverReason in ["Opponent disconnected", "Connection lost", "Opponent forfeited"]: 40 else: 60
    let textWidth = measureText(winnerText, textSize)
    
    # Determine color based on win/loss
    let textColor = if pvp.winnerIndex == pvp.localPlayerIndex:
      Green
    elif pvp.winnerIndex == -1:
      Yellow
    else:
      Red
    
    drawRectangle(0, 0, pvp.screenWidth, pvp.screenHeight,
                 Color(r: 0, g: 0, b: 0, a: 200))
    drawText(winnerText,
            pvp.screenWidth div 2 - textWidth div 2,
            pvp.screenHeight div 2 - 60,
            textSize,
            textColor)
    
    # Show final scores for all players
    var scoreText = "Final Scores - "
    for i in 0..<pvp.players.len:
      if i > 0:
        scoreText &= " | "
      if i == pvp.localPlayerIndex:
        scoreText &= "You: " & $pvp.players[i].kills
      else:
        scoreText &= "P" & $i & ": " & $pvp.players[i].kills
    
    let scoreWidth = measureText(scoreText, 24)
    drawText(scoreText,
            pvp.screenWidth div 2 - scoreWidth div 2,
            pvp.screenHeight div 2 + 10,
            24, White)
    
    let returnText = "Press ESC to return to menu"
    let returnWidth = measureText(returnText, 20)
    drawText(returnText,
            pvp.screenWidth div 2 - returnWidth div 2,
            pvp.screenHeight div 2 + 50,
            20, White)
