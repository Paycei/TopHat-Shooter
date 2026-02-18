## PvP Game Mode Logic
## Handles multiplayer player vs player combat with optional team support

import raylib, types, player, bullet, wall, particle, particle_pool, sound, network/network_types, network/network, math, times, settings, strutils, localization

const
  PVP_PLAYER_START_HP = 3.0  # Reduced HP for faster kills
  PVP_PLAYER_START_SPEED = 200.0
  PVP_PLAYER_START_DAMAGE = 1.0
  PVP_PLAYER_START_FIRE_RATE = 0.375
  PVP_PLAYER_START_BULLET_SPEED = 425.0
  PVP_PLAYER_START_COINS = 100
  PVP_PLAYER_START_WALLS = 3
  PVP_RESPAWN_TIME = 3.0
  PVP_KILL_LIMIT* = 5  # First to 5 kills wins (individual or team)
  PVP_TIME_LIMIT = 180.0  # 3 minutes
  SNAPSHOT_RATE = 0.033  # 30 Hz (every 33ms)
  INPUT_SEND_RATE = 0.033  # 30 Hz - match snapshot rate to reduce reconciliation conflicts

type
  TeamScore* = object
    kills*: int
    deaths*: int
  
  # Interpolation state for remote players
  PlayerInterpState = object
    prevPos*: Vector2f
    targetPos*: Vector2f
    prevVel*: Vector2f
    targetVel*: Vector2f
    prevTime*: float32
    targetTime*: float32
    hasData*: bool
  
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
    winnerTeam*: PvPTeam  # Winning team for team-based mode
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
    playerConnected*: seq[bool]   # Whether each player slot is still connected
    lastInputs*: seq[PlayerInput]  # Store last input for each player (server processing)
    playerNicknames*: seq[string]  # Display nicknames, indexed by player index
    teamsEnabled*: bool  # Whether team-based gameplay is enabled
    playerTeamAssignments*: seq[int]  # Team assignment per player (0-3)
    teamScores*: array[PvPTeam, TeamScore]  # Track scores per team
    # Client-side interpolation for remote players
    playerInterpStates*: seq[PlayerInterpState]  # Interpolation state per player
    interpDelay*: float32  # Render delay for interpolation (in seconds)
    interpolationEnabled*: bool  # Whether interpolation is enabled
    recentlyDestroyedBullets*: seq[int]  # Recently destroyed bullet IDs (to prevent snapshot resurrection)
    config*: PvPConfig                  # Host-configurable game settings

proc getTeamName*(team: PvPTeam): string =
  ## Get the display name for a team
  case team
  of ptRed:
    return t(tkPvPTeamRed)
  of ptBlue:
    return t(tkPvPTeamBlue)
  of ptGreen:
    return t(tkPvPTeamGreen)
  of ptYellow:
    return t(tkPvPTeamYellow)
  of ptOrange:
    return t(tkPvPTeamOrange)
  of ptPurple:
    return t(tkPvPTeamPurple)
  of ptNone:
    return t(tkPvPTeamNone)

proc getTeamColor*(team: PvPTeam): Color =
  ## Get the display color for a team
  case team
  of ptRed:
    return Color(r: 255, g: 60, b: 60, a: 255)
  of ptBlue:
    return Color(r: 60, g: 120, b: 255, a: 255)
  of ptGreen:
    return Color(r: 60, g: 255, b: 120, a: 255)
  of ptYellow:
    return Color(r: 255, g: 220, b: 60, a: 255)
  of ptOrange:
    return Color(r: 255, g: 165, b: 0, a: 255)
  of ptPurple:
    return Color(r: 200, g: 100, b: 255, a: 255)
  of ptNone:
    return White

proc assignPlayerToTeam*(playerIndex: int, maxPlayers: int, teamsEnabled: bool): PvPTeam =
  ## Assign a player to a team based on their index
  if not teamsEnabled:
    return ptNone

  # For 2-4 players: 2 teams (Red vs Blue)
  # For 5-8 players: 2 teams (Red vs Blue) with more per team
  # For 9-12 players: 3 teams (Red vs Blue vs Green)
  # For 13-16 players: 4 teams (Red vs Blue vs Green vs Yellow)
  # For 17+ players: could add 5-6 teams but games are likely smaller

  if maxPlayers <= 8:
    # 2 teams
    if playerIndex mod 2 == 0:
      return ptRed
    else:
      return ptBlue
  elif maxPlayers <= 12:
    # 3 teams
    case playerIndex mod 3
    of 0: return ptRed
    of 1: return ptBlue
    else: return ptGreen
  else:
    # 4 teams for default assignment
    case playerIndex mod 4
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    else: return ptYellow

proc assignPlayerToTeamByCount*(playerIndex: int, teamCount: int): PvPTeam =
  ## Assign a player to a team based on the desired number of teams (2-6)
  case teamCount
  of 2:
    if playerIndex mod 2 == 0:
      return ptRed
    else:
      return ptBlue
  of 3:
    case playerIndex mod 3
    of 0: return ptRed
    of 1: return ptBlue
    else: return ptGreen
  of 4:
    case playerIndex mod 4
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    else: return ptYellow
  of 5:
    case playerIndex mod 5
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    of 3: return ptYellow
    else: return ptOrange
  of 6:
    case playerIndex mod 6
    of 0: return ptRed
    of 1: return ptBlue
    of 2: return ptGreen
    of 3: return ptYellow
    of 4: return ptOrange
    else: return ptPurple
  else:
    return ptNone

proc getTeamSpawnPosition(playerIndex: int, team: PvPTeam, totalPlayers: int, screenWidth, screenHeight: float32): Vector2f =
  ## Calculate spawn position for a player based on their team
  ## Teams spawn grouped together in different quadrants
  
  let centerX = screenWidth * 0.5
  let centerY = screenHeight * 0.5
  let spawnRadius = min(screenWidth, screenHeight) * 0.35
  
  case team
  of ptNone:
    # Free-for-all: distribute evenly around circle
    let angle = (playerIndex.float / totalPlayers.float) * 2.0 * PI
    return newVector2f(
      centerX + cos(angle) * spawnRadius,
      centerY + sin(angle) * spawnRadius
    )
  
  of ptRed:
    # Left side
    let teamOffset = (playerIndex div 2).float * 80.0  # Vertical spacing between teammates
    return newVector2f(
      screenWidth * 0.15,
      centerY + teamOffset - 80.0
    )
  
  of ptBlue:
    # Right side
    let teamOffset = (playerIndex div 2).float * 80.0
    return newVector2f(
      screenWidth * 0.85,
      centerY + teamOffset - 80.0
    )
  
  of ptGreen:
    # Top side
    let teamOffset = (playerIndex div 3).float * 80.0
    return newVector2f(
      centerX + teamOffset - 80.0,
      screenHeight * 0.15
    )
  
  of ptYellow:
    # Bottom side
    let teamOffset = (playerIndex div 4).float * 80.0
    return newVector2f(
      centerX + teamOffset - 80.0,
      screenHeight * 0.85
    )

  of ptOrange:
    # Top-left side
    let teamOffset = (playerIndex div 5).float * 80.0
    return newVector2f(
      screenWidth * 0.25,
      screenHeight * 0.15 + teamOffset
    )

  of ptPurple:
    # Top-right side
    let teamOffset = (playerIndex div 6).float * 80.0
    return newVector2f(
      screenWidth * 0.75,
      screenHeight * 0.15 + teamOffset
    )

proc getSpawnPosition(playerIndex, totalPlayers: int, screenWidth, screenHeight: float32): Vector2f =
  ## Calculate spawn position for a player based on their index (free-for-all)
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

proc newPvPGameState*(screenWidth, screenHeight: int32, isHost: bool, maxPlayers: int, connectedPlayers: seq[tuple[index: int, skinType, bulletSkinType, shapeType, particleSkinType: int, nickname: string]], teamsEnabled: bool = false, playerTeamAssignments: seq[int] = @[], interpolationEnabled: bool = true, config: PvPConfig = defaultPvPConfig()): PvPGameState =
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
    winnerTeam: ptNone,
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
    playerConnected: @[],
    lastInputs: @[],
    playerNicknames: @[],
    teamsEnabled: teamsEnabled,
    playerTeamAssignments: playerTeamAssignments,
    # Initialize interpolation
    playerInterpStates: @[],
    interpDelay: 0.067,  # 67ms interpolation delay (~2 snapshots at 30Hz) - reduced for less latency
    interpolationEnabled: interpolationEnabled,
    recentlyDestroyedBullets: @[],  # Track bullets destroyed to prevent snapshot resurrection
    config: config
  )

  # Initialize team scores
  for team in PvPTeam:
    result.teamScores[team] = TeamScore(kills: 0, deaths: 0)

  # Initialize player slots
  for i in 0..<maxPlayers:
    # Use manual team assignments if provided, otherwise use automatic assignment
    let team = if teamsEnabled and playerTeamAssignments.len > i:
      PvPTeam(playerTeamAssignments[i])
    else:
      assignPlayerToTeam(i, maxPlayers, teamsEnabled)
    
    # Get spawn position based on team mode
    let spawnPos = if teamsEnabled:
      getTeamSpawnPosition(i, team, maxPlayers, screenWidth.float32, screenHeight.float32)
    else:
      getSpawnPosition(i, maxPlayers, screenWidth.float32, screenHeight.float32)
    
    let player = newPlayer(spawnPos.x, spawnPos.y)
    player.hp = config.startHp
    player.maxHp = config.startHp
    player.coins = config.startCoins
    player.walls = config.startWalls
    player.damage = config.startDamage
    player.bulletSpeed = config.bulletSpeed
    player.fireRate = config.fireRate
    player.speed = config.startSpeed
    player.teamId = team
    
    # Set cosmetics and nickname for connected players
    var cosmeticsSet = false
    var playerNick = "P" & $(i + 1)  # fallback
    for connectedPlayer in connectedPlayers:
      if connectedPlayer.index == i:
        player.skinType = connectedPlayer.skinType
        player.bulletSkinType = connectedPlayer.bulletSkinType
        player.shapeType = connectedPlayer.shapeType
        player.particleSkinType = connectedPlayer.particleSkinType
        if connectedPlayer.nickname.len > 0:
          playerNick = connectedPlayer.nickname
        cosmeticsSet = true
        break

    # If no cosmetics were set and this is the local player (host), use global settings
    if not cosmeticsSet and isHost and i == 0:
      player.skinType = globalSettings.playerSkin
      player.bulletSkinType = globalSettings.bulletSkin
      player.shapeType = globalSettings.playerShape
      player.particleSkinType = globalSettings.particleEffect
      playerNick = globalSettings.pvpNickname

    result.players.add(player)
    result.respawnTimers.add(0.0)
    result.playerConnected.add(true)
    result.lastInputs.add(emptyInput)
    result.playerNicknames.add(playerNick)
    
    # Initialize interpolation state for this player
    result.playerInterpStates.add(PlayerInterpState(
      prevPos: player.pos,
      targetPos: player.pos,
      prevVel: newVector2f(0, 0),
      targetVel: newVector2f(0, 0),
      prevTime: 0,
      targetTime: 0,
      hasData: false
    ))
  
  result.bullets = @[]
  result.walls = @[]
  result.particlePool = newParticlePool(2000)

proc startCountdown*(pvp: PvPGameState) =
  pvp.isCountingDown = true
  pvp.countdownTimer = 3.0
  
  # Reset the receive timer to prevent false timeout from lobby waiting time
  pvp.networkManager.resetReceiveTimer()
  
  if pvp.networkManager.isHost():
    # Build team assignments array to send to clients
    var teamAssignments: seq[int] = @[]
    for i in 0..<pvp.maxPlayers:
      teamAssignments.add(pvp.players[i].teamId.ord)
    
    # Build connected players list to send to clients
    var gameConnectedPlayers: seq[ConnectedPlayerInfo] = @[]
    for i in 0..<pvp.maxPlayers:
      gameConnectedPlayers.add((
        index: i,
        skinType: pvp.players[i].skinType,
        bulletSkinType: pvp.players[i].bulletSkinType,
        shapeType: pvp.players[i].shapeType,
        particleSkinType: pvp.players[i].particleSkinType,
        nickname: pvp.playerNicknames[i]
      ))
    
    # Send game start packet with team information and game config
    var packet = newPacket(ptGameStart, pvp.serverTick)
    packet.countdownTime = pvp.countdownTimer
    packet.teamsEnabled = pvp.teamsEnabled
    packet.teamAssignments = teamAssignments
    packet.gameConnectedPlayers = gameConnectedPlayers
    packet.pvpConfig = pvp.config
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

proc areTeammates*(pvp: PvPGameState, playerIdx1, playerIdx2: int): bool =
  ## Check if two players are on the same team
  if not pvp.teamsEnabled:
    return false
  if playerIdx1 < 0 or playerIdx1 >= pvp.players.len:
    return false
  if playerIdx2 < 0 or playerIdx2 >= pvp.players.len:
    return false
  if pvp.players[playerIdx1].teamId == ptNone:
    return false
  return pvp.players[playerIdx1].teamId == pvp.players[playerIdx2].teamId

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
  
  # Shooting - Only create bullets on the server (host)
  # Clients will receive bullets via ptBulletSpawn packets
  if input.shooting and (pvp.gameTime - player.lastShot) >= player.fireRate:
    player.lastShot = pvp.gameTime
    
    # Only the host (server) creates and broadcasts bullets
    if pvp.networkManager.isHost():
      # Create bullet with player-specific ID range to prevent collisions
      # Player 0 (host): IDs 0-999999, Player 1 (client): IDs 1000000-1999999
      let direction = (input.mousePos - player.pos).normalize()
      let bulletVel = direction * player.bulletSpeed
      let bulletId = playerIndex * 1000000 + pvp.bulletIdCounter
      
      let newBullet = Bullet(
        pos: player.pos + direction * (player.radius + 5),
        vel: bulletVel,
        radius: pvp.config.bulletRadius,
        damage: player.damage,
        fromPlayer: true,
        lifetime: 0,
        isHoming: false,
        isPiercing: false,
        isExplosive: false,
        bulletId: bulletId,
        bulletSkin: player.bulletSkinType,
        ownerPlayerIndex: playerIndex
      )
      
      pvp.bulletIdCounter += 1
      pvp.bullets.add(newBullet)
      
      playSound(stShoot)
      
      # Broadcast bullet spawn to all clients
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
      
      var packet = newPacket(ptBulletSpawn, pvp.serverTick)
      packet.bullet = bulletState
      pvp.networkManager.sendPacket(packet)
    else:
      # Client: just play sound for local feedback
      playSound(stShoot)
  
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
        
        var packet = newPacket(ptWallPlace, pvp.serverTick)
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
        var packet = newPacket(ptBulletDestroy, pvp.serverTick)
        packet.bulletId = bullet.bulletId
        pvp.networkManager.sendPacket(packet)
      
      pvp.bullets.delete(i)
      continue
    
    # Check player collisions with FRIENDLY FIRE PREVENTION
    for playerIdx in 0..<pvp.players.len:
      let player = pvp.players[playerIdx]
      if player.hp <= 0 or player.invincibilityTimer > 0:
        continue
      
      # Prevent bullets from hitting their own shooter
      if bullet.ownerPlayerIndex == playerIdx:
        continue  # Skip collision check for the player who shot this bullet
      
      # PREVENT FRIENDLY FIRE IN TEAM MODE
      if pvp.teamsEnabled and areTeammates(pvp, bullet.ownerPlayerIndex, playerIdx):
        continue  # Skip collision check for teammates
      
      if distance(bullet.pos, player.pos) < (bullet.radius + player.radius):
        # Hit player
        if pvp.networkManager.isHost():
          player.hp -= bullet.damage
          
          # Send damage packet
          var packet = newPacket(ptPlayerDamage, pvp.serverTick)
          packet.damagedPlayerIndex = playerIdx
          packet.damageAmount = bullet.damage
          packet.newHp = player.hp
          pvp.networkManager.sendPacket(packet)
          
          # Check for death
          if player.hp <= 0:
            # Award kill to the bullet owner
            if bullet.ownerPlayerIndex >= 0 and bullet.ownerPlayerIndex < pvp.players.len:
              pvp.players[bullet.ownerPlayerIndex].kills += 1
              
              # Update team scores
              if pvp.teamsEnabled:
                let killerTeam = pvp.players[bullet.ownerPlayerIndex].teamId
                let victimTeam = player.teamId
                if killerTeam != ptNone:
                  pvp.teamScores[killerTeam].kills += 1
                if victimTeam != ptNone:
                  pvp.teamScores[victimTeam].deaths += 1
            
            # Start respawn timer
            pvp.respawnTimers[playerIdx] = pvp.config.respawnTime
            
            var deathPacket = newPacket(ptPlayerDeath, pvp.serverTick)
            deathPacket.deadPlayerIndex = playerIdx
            pvp.networkManager.sendPacket(deathPacket)
            
            # Check win condition
            if pvp.teamsEnabled:
              # Team mode: check if any team reached kill limit
              var winningTeam = ptNone
              var maxTeamKills = 0
              for team in [ptRed, ptBlue, ptGreen, ptYellow, ptOrange, ptPurple]:
                if pvp.teamScores[team].kills > maxTeamKills:
                  maxTeamKills = pvp.teamScores[team].kills
                  winningTeam = team
              
              if maxTeamKills >= pvp.config.killLimit:
                pvp.gameOver = true
                pvp.winnerTeam = winningTeam
                pvp.winnerIndex = -1  # No individual winner in team mode
                pvp.gameOverReason = "Kill limit reached"
                
                var gameOverPacket = newPacket(ptGameOver, pvp.serverTick)
                gameOverPacket.winnerIndex = -1
                gameOverPacket.reason = "Team " & getTeamName(winningTeam) & " wins!"
                pvp.networkManager.sendPacket(gameOverPacket)
            else:
              # Free-for-all mode: check individual kills
              var maxKills = 0
              var winningPlayerIdx = -1
              for checkIdx in 0..<pvp.players.len:
                if pvp.players[checkIdx].kills > maxKills:
                  maxKills = pvp.players[checkIdx].kills
                  winningPlayerIdx = checkIdx
              
              if maxKills >= pvp.config.killLimit:
                pvp.gameOver = true
                pvp.winnerIndex = winningPlayerIdx
                pvp.gameOverReason = "Kill limit reached"
                
                var gameOverPacket = newPacket(ptGameOver, pvp.serverTick)
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
            var packet = newPacket(ptWallDestroy, pvp.serverTick)
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

  # NOTE: Host does NOT use interpolation for display - host is the server with authoritative state
  # Only clients interpolate remote players to smooth network latency

  # Update respawn timers
  for i in 0..<pvp.players.len:
    # Disconnected players never respawn
    if i < pvp.playerConnected.len and not pvp.playerConnected[i]: continue
    if pvp.players[i].hp <= 0 and pvp.respawnTimers[i] > 0:
      pvp.respawnTimers[i] -= dt
      if pvp.respawnTimers[i] <= 0:
        # Respawn player at their spawn position (team-aware)
        pvp.players[i].hp = pvp.config.startHp
        pvp.players[i].pos = if pvp.teamsEnabled:
          getTeamSpawnPosition(i, pvp.players[i].teamId, pvp.players.len, pvp.screenWidth.float32, pvp.screenHeight.float32)
        else:
          getSpawnPosition(i, pvp.players.len, pvp.screenWidth.float32, pvp.screenHeight.float32)
        pvp.players[i].invincibilityTimer = 2.0  # 2 seconds of invincibility after respawn
        
        # Send respawn packet
        var respawnPacket = newPacket(ptPlayerDamage, pvp.serverTick)
        respawnPacket.damagedPlayerIndex = i
        respawnPacket.damageAmount = 0
        respawnPacket.newHp = pvp.config.startHp
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
    if i < pvp.playerConnected.len and not pvp.playerConnected[i]: continue
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
      let snap_nick = if i < pvp.playerNicknames.len: pvp.playerNicknames[i] else: "P" & $(i + 1)
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
        fireRate: pvp.players[i].fireRate,
        bulletSpeed: pvp.players[i].bulletSpeed,
        invincibilityTimer: pvp.players[i].invincibilityTimer,
        teamId: pvp.players[i].teamId.ord,  # Send as int
        skinType: pvp.players[i].skinType,
        bulletSkinType: pvp.players[i].bulletSkinType,
        shapeType: pvp.players[i].shapeType,
        particleSkinType: pvp.players[i].particleSkinType,
        nickname: snap_nick
      ))
    
    let gameState = NetworkGameState(
      tick: pvp.serverTick,
      timestamp: pvp.gameTime,
      maxPlayers: pvp.maxPlayers,
      players: playerStates,
      bullets: bulletStates,
      walls: wallStates
    )
    
    var packet = newPacket(ptGameState, pvp.serverTick)
    packet.state = gameState
    pvp.networkManager.sendPacket(packet)
    
    # Host should also reconcile their own state for fairness
    # This ensures host experiences same prediction+reconciliation as client
    # Apply server state to host (inline reconciliation for simplicity)
    let localIdx = pvp.localPlayerIndex
    
    # Update interpolation states for all remote players (clients)
    for i in 0..<pvp.players.len:
      if i != localIdx and i < gameState.players.len and i < pvp.playerInterpStates.len:
        let interpState = addr pvp.playerInterpStates[i]
        
        # Move current target to previous
        if interpState.hasData:
          interpState.prevPos = interpState.targetPos
          interpState.prevVel = interpState.targetVel
          interpState.prevTime = interpState.targetTime
        else:
          # First snapshot - initialize with current position
          interpState.prevPos = gameState.players[i].pos
          interpState.prevVel = gameState.players[i].vel
          interpState.prevTime = gameState.timestamp
        
        # Set new target from game state
        interpState.targetPos = gameState.players[i].pos
        interpState.targetVel = gameState.players[i].vel
        interpState.targetTime = gameState.timestamp
        interpState.hasData = true
        
        # Update non-positional data immediately
        pvp.players[i].vel = gameState.players[i].vel
        pvp.players[i].hp = gameState.players[i].hp
        pvp.players[i].maxHp = gameState.players[i].maxHp
        pvp.players[i].coins = gameState.players[i].coins
        pvp.players[i].kills = gameState.players[i].kills
        pvp.players[i].walls = gameState.players[i].walls
        pvp.players[i].damage = gameState.players[i].damage
        pvp.players[i].speed = gameState.players[i].speed
        pvp.players[i].fireRate = gameState.players[i].fireRate
        pvp.players[i].bulletSpeed = gameState.players[i].bulletSpeed
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
      pvp.players[localIdx].damage = gameState.players[localIdx].damage
      pvp.players[localIdx].speed = gameState.players[localIdx].speed
      pvp.players[localIdx].fireRate = gameState.players[localIdx].fireRate
      pvp.players[localIdx].bulletSpeed = gameState.players[localIdx].bulletSpeed
      pvp.players[localIdx].invincibilityTimer = gameState.players[localIdx].invincibilityTimer

proc updatePvPClient*(pvp: PvPGameState, dt: float32) =
  ## Client-side update (prediction + reconciliation)
  ## Input is now applied immediately in main updatePvP for responsive feel
  ## This function handles additional client-only updates
  pvp.gameTime += dt

  # Update interpolation for remote players (only if enabled)
  if pvp.interpolationEnabled:
    let renderTime = pvp.gameTime - pvp.interpDelay

    for i in 0..<pvp.players.len:
      if i == pvp.localPlayerIndex:
        continue  # Skip local player (uses prediction)

      if i >= pvp.playerInterpStates.len:
        continue

      let interpState = addr pvp.playerInterpStates[i]

      if not interpState.hasData:
        continue  # No interpolation data yet

      # Calculate interpolation factor between prev and target
      let timeDiff = interpState.targetTime - interpState.prevTime
      if timeDiff <= 0:
        # Invalid time diff, just use target
        pvp.players[i].pos = interpState.targetPos
        continue

      let t = (renderTime - interpState.prevTime) / timeDiff

      if t < 0:
        # Render time is before prev, use prev
        pvp.players[i].pos = interpState.prevPos
      elif t > 1.0:
        # Render time is after target, use target (no extrapolation to avoid jitter)
        pvp.players[i].pos = interpState.targetPos
      else:
        # Interpolate between prev and target
        pvp.players[i].pos.x = interpState.prevPos.x + (interpState.targetPos.x - interpState.prevPos.x) * t
        pvp.players[i].pos.y = interpState.prevPos.y + (interpState.targetPos.y - interpState.prevPos.y) * t
  
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

    # Client-side collision detection: check if remote bullets hit players or walls
    # This provides immediate visual feedback without waiting for server reconciliation
    var shouldRemove = false

    # Check collision with all players (not just local player)
    for playerIdx in 0..<pvp.players.len:
      let player = pvp.players[playerIdx]
      if player.hp <= 0 or bullet.ownerPlayerIndex == playerIdx:
        continue  # Skip dead players and the shooter

      if distance(bullet.pos, player.pos) < (bullet.radius + player.radius):
        shouldRemove = true
        break

    # Check collision with walls
    if not shouldRemove:
      for wall in pvp.walls:
        if distance(bullet.pos, wall.pos) < (bullet.radius + wall.radius):
          shouldRemove = true
          break

    if shouldRemove:
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
  
  # Update all remote players - use interpolation instead of direct snap
  for i in 0..<pvp.players.len:
    if i != localIdx:
      # Update interpolation state for this remote player
      if i < pvp.playerInterpStates.len:
        let interpState = addr pvp.playerInterpStates[i]
        
        # Move current target to previous
        if interpState.hasData:
          interpState.prevPos = interpState.targetPos
          interpState.prevVel = interpState.targetVel
          interpState.prevTime = interpState.targetTime
        else:
          # First snapshot - initialize with current position
          interpState.prevPos = serverState.players[i].pos
          interpState.prevVel = serverState.players[i].vel
          interpState.prevTime = serverState.timestamp
        
        # Set new target from server
        interpState.targetPos = serverState.players[i].pos
        interpState.targetVel = serverState.players[i].vel
        interpState.targetTime = serverState.timestamp
        interpState.hasData = true
      
      # Update non-positional data immediately (no interpolation needed)
      pvp.players[i].vel = serverState.players[i].vel
      pvp.players[i].hp = serverState.players[i].hp
      pvp.players[i].maxHp = serverState.players[i].maxHp
      pvp.players[i].coins = serverState.players[i].coins
      pvp.players[i].kills = serverState.players[i].kills
      pvp.players[i].walls = serverState.players[i].walls
      pvp.players[i].damage = serverState.players[i].damage
      pvp.players[i].speed = serverState.players[i].speed
      pvp.players[i].fireRate = serverState.players[i].fireRate
      pvp.players[i].bulletSpeed = serverState.players[i].bulletSpeed
      pvp.players[i].invincibilityTimer = serverState.players[i].invincibilityTimer
      pvp.players[i].skinType = serverState.players[i].skinType
      pvp.players[i].bulletSkinType = serverState.players[i].bulletSkinType
      pvp.players[i].shapeType = serverState.players[i].shapeType
      pvp.players[i].particleSkinType = serverState.players[i].particleSkinType
      pvp.players[i].teamId = PvPTeam(serverState.players[i].teamId)  # Sync team
      # Sync nickname if server provides it and we don't have it yet
      if serverState.players[i].nickname.len > 0:
        while pvp.playerNicknames.len <= i:
          pvp.playerNicknames.add("P" & $(pvp.playerNicknames.len + 1))
        if pvp.playerNicknames[i].len == 0 or pvp.playerNicknames[i] == "P" & $(i + 1):
          pvp.playerNicknames[i] = serverState.players[i].nickname
  
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
  pvp.players[localIdx].damage = serverState.players[localIdx].damage
  pvp.players[localIdx].speed = serverState.players[localIdx].speed
  pvp.players[localIdx].fireRate = serverState.players[localIdx].fireRate
  pvp.players[localIdx].bulletSpeed = serverState.players[localIdx].bulletSpeed
  pvp.players[localIdx].invincibilityTimer = serverState.players[localIdx].invincibilityTimer
  pvp.players[localIdx].teamId = PvPTeam(serverState.players[localIdx].teamId)
  
  # Update bullets from server, preserving locally-predicted bullets.
  #
  # The server snapshot is always a few frames behind the client due to network
  # latency.  If we blindly replace pvp.bullets with the snapshot contents, any
  # bullet the local player fired in the last RTT/2 ms gets destroyed for one
  # frame and then reappears — producing the visible "laggy start" stutter.
  #
  # Strategy:
  #   1. Collect the set of bullet IDs that the server knows about.
  #   2. Keep any locally-owned predicted bullet that the server hasn't yet
  #      acknowledged (its ID is absent from the snapshot).
  #   3. Add/update everything the server knows about.
  #
  # "Locally-owned" means ownerPlayerIndex == localIdx, which is the only
  # player whose bullets the client predicts.  Remote bullets are always
  # authoritative from the server.

  # Step 1 – build the set of server-known IDs
  var serverBulletIds: seq[int] = @[]
  for bulletState in serverState.bullets:
    serverBulletIds.add(bulletState.id)

  # Step 2 – keep predicted bullets not yet in the snapshot
  var predictedBullets: seq[Bullet] = @[]
  for existingBullet in pvp.bullets:
    if existingBullet.ownerPlayerIndex == localIdx and
       existingBullet.bulletId notin serverBulletIds:
      predictedBullets.add(existingBullet)

  # Step 3 – rebuild from server state, then append surviving predictions
  pvp.bullets = @[]
  for bulletState in serverState.bullets:
    # Skip bullets that were recently destroyed (to prevent snapshot resurrection)
    if bulletState.id in pvp.recentlyDestroyedBullets:
      continue

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
      ownerPlayerIndex: bulletState.fromPlayerIndex  # Preserve owner from server
    )
    pvp.bullets.add(bullet)

  for predictedBullet in predictedBullets:
    pvp.bullets.add(predictedBullet)

  # Clear recently destroyed bullets after reconciling (they're old now)
  pvp.recentlyDestroyedBullets = @[]
  
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
  
  # Recalculate team scores from player data
  if pvp.teamsEnabled:
    for team in PvPTeam:
      pvp.teamScores[team] = TeamScore(kills: 0, deaths: 0)
    
    for i in 0..<pvp.players.len:
      let team = pvp.players[i].teamId
      if team != ptNone:
        pvp.teamScores[team].kills += pvp.players[i].kills

proc connectedPlayerCount*(pvp: PvPGameState): int =
  ## Count how many players are still connected (not disconnected)
  for i in 0..<pvp.players.len:
    if i < pvp.playerConnected.len and pvp.playerConnected[i]:
      result += 1

proc connectedTeams*(pvp: PvPGameState): seq[PvPTeam] =
  ## Return list of teams that still have at least one connected player
  for i in 0..<pvp.players.len:
    if i < pvp.playerConnected.len and pvp.playerConnected[i]:
      let team = pvp.players[i].teamId
      if team != ptNone and team notin result:
        result.add(team)

proc disconnectPlayer*(pvp: PvPGameState, playerIndex: int) =
  ## Remove a player from active play without ending the game.
  ## Returns true if the game should now end (only one side remains).
  if playerIndex < 0 or playerIndex >= pvp.players.len: return
  pvp.playerConnected[playerIndex] = false
  pvp.players[playerIndex].hp = 0
  pvp.respawnTimers[playerIndex] = 0  # Stop any pending respawn
  echo "[PVP] Player ", playerIndex, " removed from active play"

proc checkLastSideStanding*(pvp: PvPGameState): bool =
  ## Returns true if the game should end because only one side remains.
  if pvp.teamsEnabled:
    return pvp.connectedTeams().len <= 1
  else:
    return pvp.connectedPlayerCount() <= 1

proc handleDisconnect*(pvp: PvPGameState, disconnectedIndex: int, reason: string) =
  ## Handle a player disconnecting - either end the game (2-player) or
  ## remove them and continue (3+ player).

  # If game is already over, don't change the end screen reason
  if pvp.gameOver:
    return

  let wasTimeout = reason == "Connection timeout"

  pvp.disconnectPlayer(disconnectedIndex)

  # In a 2-player game there's no one left to play against — end immediately.
  if pvp.maxPlayers <= 2:
    pvp.gameOver = true
    pvp.isCountingDown = false
    pvp.gameStarted = true
    if wasTimeout:
      if pvp.networkManager.isHost():
        pvp.winnerIndex = pvp.localPlayerIndex
        pvp.gameOverReason = "Player " & $disconnectedIndex & " disconnected"
        var pkt = newPacket(ptGameOver, pvp.serverTick)
        pkt.winnerIndex = pvp.localPlayerIndex
        pkt.reason = "Player disconnected"
        pvp.networkManager.sendPacket(pkt)
      else:
        pvp.winnerIndex = 0
        pvp.gameOverReason = "Connection lost"
    else:
      pvp.winnerIndex = pvp.localPlayerIndex
      pvp.gameOverReason = "Player forfeited"
    return

  # 3+ player game: check if a winner has emerged now that someone left.
  if pvp.checkLastSideStanding():
    pvp.gameOver = true
    pvp.isCountingDown = false
    pvp.gameStarted = true

    if pvp.teamsEnabled:
      let remaining = pvp.connectedTeams()
      pvp.winnerTeam = if remaining.len == 1: remaining[0] else: ptNone
      pvp.winnerIndex = -1
      pvp.gameOverReason = if remaining.len == 1: $pvp.winnerTeam & " team wins!" else: "Draw"
    else:
      # Find the last connected player
      var lastPlayer = -1
      for i in 0..<pvp.players.len:
        if i < pvp.playerConnected.len and pvp.playerConnected[i]:
          lastPlayer = i
          break
      pvp.winnerIndex = lastPlayer
      pvp.gameOverReason = "Last player standing"

    if pvp.networkManager.isHost():
      var pkt = newPacket(ptGameOver, pvp.serverTick)
      pkt.winnerIndex = pvp.winnerIndex
      pkt.reason = pvp.gameOverReason
      pvp.networkManager.sendPacket(pkt)
  else:
    # Game continues — log who dropped out
    let nick = if disconnectedIndex < pvp.playerNicknames.len:
      pvp.playerNicknames[disconnectedIndex] else: "Player " & $disconnectedIndex
    echo "[PVP] ", nick, " dropped out — game continues with ",
         pvp.connectedPlayerCount(), " players remaining"

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
      case event.packet.kind
      of ptGameStart:
        pvp.countdownTimer = event.packet.countdownTime
        pvp.isCountingDown = true
        # Client also needs to disable timeout during countdown
        pvp.networkManager.resetReceiveTimer()
        
        # Apply team settings from host
        pvp.teamsEnabled = event.packet.teamsEnabled
        
        # Apply team assignments from host to all players
        if pvp.teamsEnabled and event.packet.teamAssignments.len > 0:
          echo "[PVP CLIENT] Receiving team assignments from host"
          for i in 0..<min(pvp.players.len, event.packet.teamAssignments.len):
            let teamId = PvPTeam(event.packet.teamAssignments[i])
            pvp.players[i].teamId = teamId
            
            # Update spawn position based on team
            pvp.players[i].pos = getTeamSpawnPosition(i, teamId, pvp.maxPlayers,
                                                      pvp.screenWidth.float32, pvp.screenHeight.float32)
          
          echo "[PVP CLIENT] Applied team assignments - Teams enabled: ", pvp.teamsEnabled
      
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
            ownerPlayerIndex: bulletState.fromPlayerIndex  # Preserve owner
          )
          pvp.bullets.add(bullet)
      
      of ptBulletDestroy:
        # Remove bullet and track it as recently destroyed
        var i = 0
        while i < pvp.bullets.len:
          if pvp.bullets[i].bulletId == event.packet.bulletId:
            # Track this bullet as destroyed to prevent snapshot resurrection
            if event.packet.bulletId notin pvp.recentlyDestroyedBullets:
              pvp.recentlyDestroyedBullets.add(event.packet.bulletId)
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

        # Extract team info from reason if team mode
        if pvp.teamsEnabled and "Team" in event.packet.reason:
          # Parse team from reason string
          if "Red" in event.packet.reason:
            pvp.winnerTeam = ptRed
          elif "Blue" in event.packet.reason:
            pvp.winnerTeam = ptBlue
          elif "Green" in event.packet.reason:
            pvp.winnerTeam = ptGreen
          elif "Yellow" in event.packet.reason:
            pvp.winnerTeam = ptYellow
          elif "Orange" in event.packet.reason:
            pvp.winnerTeam = ptOrange
          elif "Purple" in event.packet.reason:
            pvp.winnerTeam = ptPurple
      
      else:
        discard
    
    of neDisconnect:
      echo "[PVP] Player ", event.disconnectPlayerIndex, " disconnected: ", event.reason
      handleDisconnect(pvp, event.disconnectPlayerIndex, event.reason)
    
    else:
      discard

proc updatePvP*(pvp: PvPGameState, dt: float32) =
  ## Main PvP update function
  
  # Validate local player index
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
      var packet = newPacket(ptPlayerInput, pvp.serverTick)
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
  
  # Draw players with cosmetics and TEAM COLORS
  for i in 0..<pvp.maxPlayers:
    if i >= pvp.players.len:
      break
    let player = pvp.players[i]
    if player.hp <= 0:
      let isDisconnected = i < pvp.playerConnected.len and not pvp.playerConnected[i]
      if isDisconnected:
        # Show disconnected label for this player's position only to local player
        if i == pvp.localPlayerIndex:
          let msg = "You disconnected"
          let w = measureText(msg, 20)
          drawText(msg, pvp.screenWidth div 2 - w div 2,
                  pvp.screenHeight - 100, 20, Color(r: 255, g: 80, b: 80, a: 255))
      elif i < pvp.respawnTimers.len and pvp.respawnTimers[i] > 0:
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
    
    # Draw team indicator ring if teams enabled
    if pvp.teamsEnabled and player.teamId != ptNone:
      let teamColor = getTeamColor(player.teamId)
      drawCircleLines(player.pos.x.int32, player.pos.y.int32, player.radius + 5, teamColor)

    # Draw nickname above player with team color
    if i < pvp.playerNicknames.len and pvp.playerNicknames[i].len > 0:
      let nick = pvp.playerNicknames[i]
      let nickSize: int32 = 14
      let nickW = measureText(nick, nickSize)
      let nickX = player.pos.x.int32 - nickW div 2
      let nickY = (player.pos.y - player.radius - 26).int32
      
      # Use team color for nickname if teams enabled
      let nickColor = if pvp.teamsEnabled and player.teamId != ptNone:
        getTeamColor(player.teamId)
      elif i == pvp.localPlayerIndex:
        Color(r: 100, g: 255, b: 100, a: 220)
      else:
        Color(r: 255, g: 200, b: 100, a: 220)
      
      drawText(nick, nickX, nickY, nickSize, nickColor)

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
  
  # Draw HUD - TEAM MODE or FREE-FOR-ALL
  if pvp.teamsEnabled:
    # Team mode: Show team scores
    # First, determine which teams have players assigned
    var activeTeams: seq[PvPTeam] = @[]
    for i in 0..<pvp.players.len:
      let team = pvp.players[i].teamId
      if team != ptNone and team notin activeTeams:
        activeTeams.add(team)
    
    # Build scoreboard showing all active teams
    var scoreText = ""
    for team in activeTeams:
      if scoreText.len > 0:
        scoreText &= "  |  "
      scoreText &= $team & ": " & $pvp.teamScores[team].kills
    
    let scoreX = max(10, pvp.screenWidth div 2 - (scoreText.len * 3))
    drawText(scoreText, scoreX.int32, 10, 20, White)
  else:
    # Free-for-all: Show individual scores
    var scoreText = ""
    for i in 0..<pvp.players.len:
      if scoreText.len > 0:
        scoreText &= " | "
      let displayName = if i < pvp.playerNicknames.len and pvp.playerNicknames[i].len > 0:
        pvp.playerNicknames[i]
      else:
        "P" & $(i + 1)
      let disconnected = i < pvp.playerConnected.len and not pvp.playerConnected[i]
      scoreText &= displayName & ": " & $pvp.players[i].kills &
                   (if disconnected: " (left)" else: "")

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
    
    # Use team color if teams enabled, otherwise bright green
    let arrowColor = if pvp.teamsEnabled and localPlayer.teamId != ptNone:
      getTeamColor(localPlayer.teamId)
    else:
      Color(r: 100, g: 255, b: 100, a: 255)  # Bright green
    
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
    var winnerText = ""
    
    if pvp.teamsEnabled and pvp.winnerTeam != ptNone:
      # Team victory
      let localTeam = pvp.players[pvp.localPlayerIndex].teamId
      if localTeam == pvp.winnerTeam:
        winnerText = "YOUR TEAM WINS!"
      else:
        winnerText = getTeamName(pvp.winnerTeam) & " TEAM WINS!"
    else:
      # Individual victory or disconnect
      winnerText = case pvp.gameOverReason
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
    
    let textSize: int32 = if pvp.teamsEnabled: 50 else:
      (if pvp.gameOverReason in ["Opponent disconnected", "Connection lost", "Opponent forfeited"]: 40 else: 60)
    let textWidth = measureText(winnerText, textSize)
    
    # Determine color based on win/loss
    let textColor = if pvp.teamsEnabled and pvp.winnerTeam != ptNone:
      if pvp.players[pvp.localPlayerIndex].teamId == pvp.winnerTeam:
        Green
      else:
        Red
    else:
      if pvp.winnerIndex == pvp.localPlayerIndex:
        Green
      elif pvp.winnerIndex == -1:
        Yellow
      else:
        Red
    
    drawRectangle(0, 0, pvp.screenWidth, pvp.screenHeight,
                 Color(r: 0, g: 0, b: 0, a: 200))
    drawText(winnerText,
            pvp.screenWidth div 2 - textWidth div 2,
            pvp.screenHeight div 2 - 100,
            textSize,
            textColor)
    
    # Show game over reason (if meaningful)
    if pvp.gameOverReason.len > 0 and pvp.gameOverReason notin ["", "Kill limit reached"]:
      let reasonSize: int32 = 20
      let reasonWidth = measureText(pvp.gameOverReason, reasonSize)
      drawText(pvp.gameOverReason,
              pvp.screenWidth div 2 - reasonWidth div 2,
              pvp.screenHeight div 2 - 40,
              reasonSize,
              Color(r: 200, g: 200, b: 200, a: 255))
    
    # Show final scores
    var scoreText = "Final Scores - "
    if pvp.teamsEnabled:
      # Determine which teams have players assigned
      var activeTeams: seq[PvPTeam] = @[]
      for i in 0..<pvp.players.len:
        let team = pvp.players[i].teamId
        if team != ptNone and team notin activeTeams:
          activeTeams.add(team)
      
      # Show ALL active teams (even with 0 score)
      for team in activeTeams:
        if scoreText.len > 15:  # More than just "Final Scores - "
          scoreText &= " | "
        let teamColor = getTeamColor(team)
        scoreText &= $team & ": " & $pvp.teamScores[team].kills
    else:
      for i in 0..<pvp.players.len:
        if i > 0:
          scoreText &= " | "
        if i == pvp.localPlayerIndex:
          scoreText &= "You: " & $pvp.players[i].kills
        else:
          # Use nickname if available, otherwise fall back to P# format
          let displayName = if i < pvp.playerNicknames.len and pvp.playerNicknames[i].len > 0:
            pvp.playerNicknames[i]
          else:
            "P" & $i
          scoreText &= displayName & ": " & $pvp.players[i].kills
    
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
