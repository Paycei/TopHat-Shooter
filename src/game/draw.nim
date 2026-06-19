proc drawBossPhaseHud(game: Game, enemy: Enemy, topY: int32 = 10): int32 =
  let bossDef = getBossDefinition(enemy.bossDefinitionID)
  let phaseCount = max(1, max(bossDef.phases.len, enemy.bossPhaseHpPools.len))
  let currentPhase = clamp(enemy.currentPhaseIndex, 0, phaseCount - 1)
  # Only reveal the boss's full phase layout once the player has beaten it before;
  # otherwise show bars up to the current phase and don't spoil what's coming.
  let revealAll = hasDefeatedBoss(globalStats, enemy.bossDefinitionID)
  let visiblePhases = if revealAll: phaseCount else: currentPhase + 1

  let rowH = 13'i32
  let headerH = 38'i32
  let panelW = min(520'i32, max(340'i32, game.screenWidth - 80'i32))
  let panelH = headerH + rowH * visiblePhases.int32 + 11'i32
  let panelX = game.screenWidth div 2 - panelW div 2
  let panelY = topY
  let activeColor =
    if currentPhase < bossDef.phases.len: bossDef.phases[currentPhase].color
    else: enemy.color

  drawRectangle(panelX + 3, panelY + 4, panelW, panelH, Color(r: 0, g: 0, b: 0, a: 110))
  drawRectangle(panelX, panelY, panelW, panelH, Color(r: 8, g: 12, b: 19, a: 232))
  drawRectangle(panelX, panelY, panelW, 3, activeColor)
  drawRectangleLines(Rectangle(x: panelX.float32, y: panelY.float32,
                               width: panelW.float32, height: panelH.float32),
                     1, withAlpha(activeColor, 210))

  let threatName = getEnemyProcessName(enemy)
  drawText(t(tkBossThreatCritical), panelX + 11, panelY + 7, 8, withAlpha(activeColor, 240))
  drawText(threatName, panelX + 11, panelY + 17, 13, Color(r: 238, g: 245, b: 255, a: 255))

  let phaseName =
    if currentPhase < bossDef.phases.len:
      bossDef.phases[currentPhase].name
    else:
      t(tkBossThreatPhaseName) & " " & $(currentPhase + 1)
  let phaseCountLabel = if revealAll: $phaseCount else: "?"
  let phaseText = t(tkBossThreatPhaseHeader) & " " & $(currentPhase + 1) & "/" & phaseCountLabel & " :: " & phaseName
  let phaseTextW = measureText(phaseText, 10)
  drawText(phaseText, panelX + panelW - phaseTextW - 11, panelY + 9, 10, withAlpha(activeColor, 240))

  let hpText = formatHealthDisplay(enemy.hp) & " / " & formatHealthDisplay(enemy.maxHp)
  let hpTextW = measureText(hpText, 10)
  drawText(hpText, panelX + panelW - hpTextW - 11, panelY + 23, 10, Color(r: 210, g: 225, b: 240, a: 255))

  let barX = panelX + 12
  let barW = panelW - 24
  var y = panelY + headerH - 4
  for i in 0..<visiblePhases:
    let phaseColor =
      if i < bossDef.phases.len: bossDef.phases[i].color
      else: enemy.color
    let phaseMax = bossPhaseMaxHp(enemy, i, phaseCount)
    let fillPct =
      if i < currentPhase:
        1.0'f32
      elif i == currentPhase:
        clamp(enemy.hp / max(enemy.maxHp, 0.01'f32), 0.0'f32, 1.0'f32)
      else:
        0.0'f32
    let fillW = int32(barW.float32 * fillPct)
    let rowAlpha =
      if i < currentPhase: 150
      elif i == currentPhase: 255
      else: 85
    let rowBg = if i == currentPhase:
      Color(r: 24, g: 30, b: 42, a: 230)
    else:
      Color(r: 12, g: 17, b: 25, a: 210)

    drawRectangle(barX, y, barW, 9, rowBg)
    if fillW > 0:
      drawRectangleGradientH(barX, y, fillW, 9,
                             withAlpha(phaseColor, rowAlpha),
                             Color(r: min(255, phaseColor.r.int + 70).uint8,
                                   g: min(255, phaseColor.g.int + 70).uint8,
                                   b: min(255, phaseColor.b.int + 70).uint8,
                                   a: rowAlpha.uint8))
      drawRectangle(barX, y, fillW, 2, Color(r: 255, g: 255, b: 255, a: uint8(rowAlpha div 4)))

    let label = "P" & $(i + 1)
    drawText(label, barX + 4, y + 1, 8,
             if i == currentPhase: White else: withAlpha(phaseColor, rowAlpha))

    if i < currentPhase:
      drawText(t(tkBossThreatBreached), barX + barW - 52, y + 1, 8, Color(r: 255, g: 190, b: 110, a: 180))
    elif i > currentPhase:
      drawText(t(tkBossThreatLocked), barX + barW - 40, y + 1, 8, Color(r: 120, g: 140, b: 160, a: 160))
    else:
      let poolText = formatHealthDisplay(enemy.hp) & "/" & formatHealthDisplay(phaseMax)
      let poolTextW = measureText(poolText, 8)
      drawText(poolText, barX + barW - poolTextW - 6, y + 1, 8, White)

    drawRectangleLines(Rectangle(x: barX.float32, y: y.float32,
                                 width: barW.float32, height: 9.0'f32),
                       1, withAlpha(phaseColor, rowAlpha))
    y += rowH

  if enemy.invulnerabilityTimer > 0:
    let shieldPct = clamp(enemy.invulnerabilityTimer / BOSS_PHASE_INVULNERABILITY_DURATION, 0.0'f32, 1.0'f32)
    let shieldText = "PHASE FIREWALL " & formatFloat(enemy.invulnerabilityTimer, ffDecimal, 1) & "s"
    let shieldW = measureText(shieldText, 10) + 16
    let shieldX = panelX + panelW div 2 - shieldW div 2
    let shieldY = panelY + panelH - 15
    drawRectangle(shieldX, shieldY, shieldW, 12, Color(r: 5, g: 15, b: 24, a: 235))
    drawRectangle(shieldX, shieldY, int32(shieldW.float32 * shieldPct), 12, withAlpha(activeColor, 125))
    drawRectangleLines(Rectangle(x: shieldX.float32, y: shieldY.float32,
                                 width: shieldW.float32, height: 12.0'f32),
                       1, withAlpha(activeColor, 255))
    drawText(shieldText, shieldX + 8, shieldY + 2, 10, White)

  return panelY + panelH + 6

proc drawGame*(game: Game) =
  # Profiling counterpart to updateGame: smoothed wall-clock ms spent drawing.
  # (game is a ref, so mutating this field through the non-var binding is fine.)
  let perfStart = getTime()
  defer: game.perfDrawMs = game.perfDrawMs * 0.9'f32 +
                           float32((getTime() - perfStart) * 1000.0) * 0.1'f32
  # Calculate screen shake offset
  var shakeOffsetX: float32 = 0
  var shakeOffsetY: float32 = 0

  let shakeOffset = getShakeOffset(game.dopamine.screenShake)
  shakeOffsetX = shakeOffset.x
  shakeOffsetY = shakeOffset.y

  if shakeOffsetX != 0 or shakeOffsetY != 0:
    pushMatrix()
    translatef(shakeOffsetX, shakeOffsetY, 0.0'f32)

  # Update and draw OS-style background
  let dt = getFrameTime()
  updateOSBackground(game.osBackground, dt, game.player.hp, game.player.maxHp,
                     game.bossWaveManager.isBossActive(),
                     game.screenWidth, game.screenHeight)
  let showArenaVignette = globalSettings == nil or globalSettings.showArenaVignette
  let bgAccent = if game.mode == gmRoguelite and game.rogueliteRun != nil and
                    game.rogueliteRun.floor != nil:
    themeAccent(game.rogueliteRun.floor.theme)
  else:
    Color(r: 0, g: 0, b: 0, a: 0)
  drawOSBackground(game.osBackground, game.screenWidth, game.screenHeight,
                   showArenaVignette, bgAccent)

  # Draw background particles first
  drawParticlePoolLayer(game.particlePool, plBackground)

  # Draw lightning bolt arcs (chain lightning visuals, short-lived)
  drawLightningBolts(game)

  # Draw attack warnings (before everything else so they're visible)
  if globalSettings == nil or globalSettings.showHints:
    for warning in game.attackWarnings:
      drawAttackWarning(warning)

  # Draw lasers (after warnings, before walls for visual layering)
  for laser in game.lasers:
    drawLaser(laser)

  # Draw meteorites (show both warning and falling meteorites)
  for meteorite in game.meteorites:
    if meteorite.warningTimer > 0:
      # Draw warning indicator at target position (flashing)
      let warningAlpha = if (meteorite.warningTimer * 6.0).int mod 2 == 0: uint8(200) else: uint8(100)
      drawCircleLines(meteorite.targetPos.x.int32, meteorite.targetPos.y.int32, meteorite.radius,
                     Color(r: 255, g: 100, b: 0, a: warningAlpha))
      drawCircleLines(meteorite.targetPos.x.int32, meteorite.targetPos.y.int32, meteorite.radius + 5,
                     Color(r: 255, g: 50, b: 0, a: warningAlpha div 2))
    else:
      # Draw falling meteorite
      drawCircle(Vector2(x: meteorite.pos.x, y: meteorite.pos.y), meteorite.radius,
                Color(r: 255, g: 100, b: 0, a: 255))
      # Add fiery glow effect
      drawCircleLines(meteorite.pos.x.int32, meteorite.pos.y.int32, meteorite.radius + 3,
                     Color(r: 255, g: 150, b: 0, a: 200))
      drawCircleLines(meteorite.pos.x.int32, meteorite.pos.y.int32, meteorite.radius + 6,
                     Color(r: 255, g: 200, b: 50, a: 100))

  # Draw walls
  for wall in game.walls:
    drawWall(wall, game.player)

  # Draw coins
  for coin in game.coins:
    drawCoin(coin)

  # Draw consumables
  for consumable in game.consumables:
    drawConsumable(consumable)

  # Draw bullets
  let hasOvercharge = hasPowerUp(game.player, puOvercharge)
  let hasBloodBullets = hasPowerUp(game.player, puBloodBullets)
  for bullet in game.bullets:
    drawBullet(bullet, hasOvercharge, hasBloodBullets, game.time)

  # Draw enemies
  for enemy in game.enemies:
    # Draw elite aura first (so it appears behind the enemy)
    if enemy.isElite:
      drawEliteAura(enemy, game.time)
    drawEnemy(enemy)
    if enemy.isBoss:
      drawBossWeakPoints(enemy, globalSettings == nil or globalSettings.showHints)
      #  Vulnerability window: bold expanding rings so the player never misses it 
      if enemy.weakPoint.exposedTimer > 0:
        let vt   = enemy.weakPoint.exposedTimer
        let vmax = enemy.weakPoint.exposureDuration
        # vpct: 1.0 when window just opened, 0.0 when about to close
        let vpct = clamp(vt / max(vmax, 0.001'f32), 0.0'f32, 1.0'f32)
        let vp   = sin(game.time * 9.0) * 0.5 + 0.5
        let va   = uint8(clamp(140.0 + vp * 115.0, 0.0, 255.0))
        let vr1  = enemy.radius + 18.0 + vp * 7.0
        let vr2  = enemy.radius + 30.0 + vp * 9.0
        # Fixed dot-count arc: all N dots placed evenly, only the first
        # floor(vpct*N) are lit no while-loop overshoot, no clipping.
        const ARC_DOTS = 32
        let litDots = int(vpct * ARC_DOTS.float32 + 0.5)  # round, never clips short
        let arcR    = enemy.radius + 38.0
        for k in 0..<ARC_DOTS:
          let angle = k.float32 / ARC_DOTS.float32 * PI * 2.0 - PI * 0.5
          let ax = enemy.pos.x + cos(angle) * arcR
          let ay = enemy.pos.y + sin(angle) * arcR
          let dotAlpha = if k < litDots:
            uint8(clamp(vpct * 220.0, 60.0, 220.0))
          else:
            uint8(30)   # dim ghost so full circle shape is always readable
          drawCircle(Vector2(x: ax, y: ay), 3.0,
                     Color(r: 255, g: 235, b: 80, a: dotAlpha))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, vr1,
                        Color(r: 255, g: 235, b: 80, a: va))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, vr2,
                        Color(r: 255, g: 255, b: 200, a: uint8(va.int div 3)))

      # Enrage aura: red spikes that thicken as the boss is left to stall.
      if enemy.bossEnrageLevel > 0.05'f32:
        let elv  = clamp(enemy.bossEnrageLevel / ENRAGE_MAX, 0.0'f32, 1.0'f32)
        let ep   = sin(game.time * 14.0) * 0.5 + 0.5
        let er   = enemy.radius + 6.0 + ep * 6.0
        let ea   = uint8(clamp(70.0 + elv * 160.0, 0.0, 255.0))
        for s in 0..<12:
          let a = game.time * 3.0 + s.float32 * PI / 6.0
          drawLine(Vector2(x: enemy.pos.x + cos(a) * er, y: enemy.pos.y + sin(a) * er),
                   Vector2(x: enemy.pos.x + cos(a) * (er + 8.0 + elv * 14.0),
                           y: enemy.pos.y + sin(a) * (er + 8.0 + elv * 14.0)),
                   1.5'f32 + elv * 1.5'f32, Color(r: 255, g: 50, b: 30, a: ea))

      # Adds-gate seal: amber lock ring telling the player to clear the adds first.
      if enemy.addsGateActive and enemy.weakPoint.exposedTimer <= 0:
        let sp = sin(game.time * 4.0) * 0.5 + 0.5
        let sa = uint8(clamp(110.0 + sp * 110.0, 0.0, 255.0))
        let sr = enemy.radius + 14.0 + sp * 4.0
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, sr,
                        Color(r: 255, g: 180, b: 40, a: sa))
        drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, sr + 5.0,
                        Color(r: 255, g: 140, b: 20, a: uint8(sa.int div 2)))
        if globalSettings == nil or globalSettings.showHints:
          let gt = "SEALED \xE2\x80\x94 CLEAR ADDS"
          drawText(gt, enemy.pos.x.int32 - measureText(gt, 10) div 2,
                   (enemy.pos.y - enemy.radius - 26.0).int32, 10,
                   Color(r: 255, g: 200, b: 90, a: 235))

      # Overload shield: rotating cyan hex shell that bounces body shots back.
      if enemy.reflectShieldActive:
        let pp  = sin(game.time * 8.0) * 0.5 + 0.5
        let shRad = enemy.radius + 16.0 + pp * 5.0
        let sha = uint8(clamp(150.0 + pp * 95.0, 0.0, 255.0))
        let spin = game.time * 1.4
        var prev = Vector2(x: enemy.pos.x + cos(spin) * shRad, y: enemy.pos.y + sin(spin) * shRad)
        for v in 1..6:
          let a = spin + v.float32 * PI / 3.0
          let cur = Vector2(x: enemy.pos.x + cos(a) * shRad, y: enemy.pos.y + sin(a) * shRad)
          drawLine(prev, cur, 3.0'f32, Color(r: 90, g: 200, b: 255, a: sha))
          prev = cur
        drawCircle(Vector2(x: enemy.pos.x, y: enemy.pos.y), shRad,
                   Color(r: 90, g: 200, b: 255, a: uint8(sha.int div 8)))
        if globalSettings == nil or globalSettings.showHints:
          let st = "OVERLOAD \xE2\x80\x94 HOLD FIRE"
          drawText(st, enemy.pos.x.int32 - measureText(st, 10) div 2,
                   (enemy.pos.y - enemy.radius - 26.0).int32, 10,
                   Color(r: 150, g: 220, b: 255, a: 235))

    # Draw OS-style enemy labels above each enemy
    drawEnemyLabel(enemy, showHealthBar = true, enabled = globalSettings.showEnemyLabels)

    # Draw warning indicators for elite/boss enemies
    if globalSettings == nil or globalSettings.showHints:
      drawEnemyWarningIndicator(enemy)

    # Draw boss satellites
    if enemy.isBoss and enemy.satellites.len > 0:
      # Orbit trail rings, one per unique radius
      for idx, sat in enemy.satellites:
        if idx mod 2 == 0:
          drawCircleLines(enemy.pos.x.int32, enemy.pos.y.int32, sat.radius,
                         Color(r: 100, g: 150, b: 255, a: 25))

      #  Objective indicators 
      let satIsObjective = enemy.weakPoint.enabled and
                           enemy.weakPoint.kind == bwoSatelliteSet and
                           enemy.weakPoint.exposedTimer <= 0 and
                           enemy.weakPoint.cooldownTimer <= 0

      # Draw each satellite as a detailed space-station miniature
      for sat in enemy.satellites:
        let sx = sat.pos.x
        let sy = sat.pos.y
        let t  = game.time

        # Whether this satellite is charging its laser
        let charging  = sat.laserActive and sat.laserChargeTime < 1.5
        let firing    = sat.laserActive and sat.laserChargeTime >= 1.5

        # Pulse and glow drivers
        let pulse     = sin(t * 5.0 + sat.angle * 3.0) * 0.5 + 0.5   # 0..1, per-satellite phase
        let fastPulse = sin(t * 12.0 + sat.angle * 4.0) * 0.5 + 0.5

        # Color scheme: cool blue normally, hot red/orange when charging, white burst when firing
        let coreColor =
          if firing:    Color(r: 255, g: 255, b: 255, a: 255)
          elif charging:Color(r: 255, g: uint8(60  + pulse * 100), b: 30,  a: 255)
          else:         Color(r: 60,  g: uint8(160 + pulse * 60),  b: 255, a: 255)

        let glowColor =
          if firing:    Color(r: 255, g: 220, b: 120, a: 160)
          elif charging:Color(r: 255, g: 80,  b: 0,   a: uint8(100 + fastPulse * 120))
          else:         Color(r: 80,  g: 140, b: 255, a: uint8(60  + pulse * 80))

        let panelColor =
          if firing:    Color(r: 220, g: 220, b: 255, a: 255)
          elif charging:Color(r: 255, g: 200, b: 80,  a: 255)
          else:         Color(r: 100, g: 180, b: 255, a: 220)

        let rimColor  = Color(r: 200, g: 220, b: 255, a: 200)

        #  outer glow halo
        let glowR = 22.0 + pulse * 5.0 + (if charging: fastPulse * 8.0 else: 0.0)
        drawCircle(Vector2(x: sx, y: sy), glowR,
                   Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: uint8(glowColor.a.int div 3)))
        drawCircleLines(sx.int32, sy.int32, glowR,
                   Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: glowColor.a))

        #  rotating outer shield ring
        let shieldAngle = t * (if sat.rotationSpeed > 0: 2.2 else: -2.2) + sat.angle
        for k in 0..5:
          let ra = shieldAngle + k.float32 * (PI / 3.0)
          let ax = sx + cos(ra) * 15.0
          let ay = sy + sin(ra) * 15.0
          drawCircle(Vector2(x: ax, y: ay), 2.5,
                     Color(r: coreColor.r, g: coreColor.g, b: coreColor.b, a: uint8(160 + pulse * 80)))

        #  hexagonal body outline
        let bodyAngle = t * 0.4 * (if sat.rotationSpeed >= 0: 1.0 else: -1.0) + sat.angle * 0.3
        for k in 0..5:
          let a0 = bodyAngle + k.float32       * (PI / 3.0)
          let a1 = bodyAngle + (k + 1).float32 * (PI / 3.0)
          let bx0 = sx + cos(a0) * 11.0;  let by0 = sy + sin(a0) * 11.0
          let bx1 = sx + cos(a1) * 11.0;  let by1 = sy + sin(a1) * 11.0
          drawLine(Vector2(x: bx0, y: by0), Vector2(x: bx1, y: by1), 2.5, rimColor)

        #  solar panel wings
        # Two rigid arms extending perpendicular to the current orbit tangent
        let tangentAngle = sat.angle + PI / 2.0  # tangent to orbit direction
        for side in [-1.0, 1.0]:
          let armAngle = tangentAngle + (if side > 0: 0.0 else: PI)
          let panelDist = 14.0
          let panelW    = 10.0
          let panelH    = 5.0
          # Arm strut
          let armTipX = sx + cos(armAngle) * panelDist
          let armTipY = sy + sin(armAngle) * panelDist
          drawLine(Vector2(x: sx + cos(armAngle) * 5.0,  y: sy + sin(armAngle) * 5.0),
                   Vector2(x: armTipX, y: armTipY), 2.0,
                   Color(r: 180, g: 200, b: 220, a: 200))
          # Panel rectangle (4 corners)
          let perpX = cos(armAngle + PI / 2.0) * panelW
          let perpY = sin(armAngle + PI / 2.0) * panelW
          let fwdX  = cos(armAngle) * panelH
          let fwdY  = sin(armAngle) * panelH
          let p0 = Vector2(x: armTipX + perpX + fwdX, y: armTipY + perpY + fwdY)
          let p1 = Vector2(x: armTipX - perpX + fwdX, y: armTipY - perpY + fwdY)
          let p2 = Vector2(x: armTipX - perpX - fwdX, y: armTipY - perpY - fwdY)
          let p3 = Vector2(x: armTipX + perpX - fwdX, y: armTipY + perpY - fwdY)
          drawLine(p0, p1, 2.0, panelColor)
          drawLine(p1, p2, 2.0, panelColor)
          drawLine(p2, p3, 2.0, panelColor)
          drawLine(p3, p0, 2.0, panelColor)
          # Panel centre stripe (solar cell division)
          let midA = Vector2(x: (p0.x + p3.x) * 0.5, y: (p0.y + p3.y) * 0.5)
          let midB = Vector2(x: (p1.x + p2.x) * 0.5, y: (p1.y + p2.y) * 0.5)
          drawLine(midA, midB, 1.0, Color(r: 120, g: 200, b: 255, a: 160))

        #  core filled circle
        drawCircle(Vector2(x: sx, y: sy), 9.0, coreColor)

        #  lens flare dot
        let lensR = 3.5 + (if firing: fastPulse * 4.0 else: pulse * 1.5)
        drawCircle(Vector2(x: sx, y: sy), lensR,
                   Color(r: 255, g: 255, b: 255, a: uint8(200 + fastPulse * 55)))

        #  charging / firing effects
        if charging:
          # Spinning danger chevrons
          let chevAngle = t * 6.0 + sat.angle
          for k in 0..2:
            let ca = chevAngle + k.float32 * (PI * 2.0 / 3.0)
            let cx0 = sx + cos(ca) * 18.0
            let cy0 = sy + sin(ca) * 18.0
            let cx1 = sx + cos(ca + 0.4) * 13.0
            let cy1 = sy + sin(ca + 0.4) * 13.0
            let cx2 = sx + cos(ca - 0.4) * 13.0
            let cy2 = sy + sin(ca - 0.4) * 13.0
            drawLine(Vector2(x: cx0, y: cy0), Vector2(x: cx1, y: cy1), 2.0,
                     Color(r: 255, g: 80, b: 0, a: uint8(180 + fastPulse * 75)))
            drawLine(Vector2(x: cx0, y: cy0), Vector2(x: cx2, y: cy2), 2.0,
                     Color(r: 255, g: 80, b: 0, a: uint8(180 + fastPulse * 75)))

          # Expanding charge ring
          let chargeProgress = sat.laserChargeTime / 1.5
          let chargeRingR = 9.0 + chargeProgress * 24.0
          drawCircleLines(sx.int32, sy.int32, chargeRingR,
                          Color(r: 255, g: uint8(200 - chargeProgress * 150), b: 0,
                                a: uint8(220 - chargeProgress * 120)))

        elif firing:
          # Rapid concentric flash rings
          for k in 0..2:
            let flashR = 8.0 + k.float32 * 7.0 + fastPulse * 5.0
            drawCircleLines(sx.int32, sy.int32, flashR,
                            Color(r: 255, g: 220, b: 120, a: uint8(180 - k * 50)))

        #  target crosshair on the locked player position
        if charging:
          let targetSize = 16.0
          let tAlpha = uint8(140 + fastPulse * 115)
          let tColor = Color(r: 255, g: 60, b: 30, a: tAlpha)
          # + crosshair
          drawLine(Vector2(x: sat.laserTarget.x - targetSize, y: sat.laserTarget.y),
                   Vector2(x: sat.laserTarget.x + targetSize, y: sat.laserTarget.y), 2.0, tColor)
          drawLine(Vector2(x: sat.laserTarget.x, y: sat.laserTarget.y - targetSize),
                   Vector2(x: sat.laserTarget.x, y: sat.laserTarget.y + targetSize), 2.0, tColor)
          # Inner dot
          drawCircle(Vector2(x: sat.laserTarget.x, y: sat.laserTarget.y), 3.5,
                     Color(r: 255, g: 255, b: 255, a: tAlpha))
          # Outer pulsing ring
          drawCircleLines(sat.laserTarget.x.int32, sat.laserTarget.y.int32,
                          targetSize + fastPulse * 6.0, tColor)

        #  Objective diamond: show when satellite is a shoot-to-destroy target 
        if satIsObjective:
          let dp  = sin(game.time * 6.0 + sat.angle * 2.0) * 0.5 + 0.5
          let da  = uint8(clamp(160.0 + dp * 95.0, 0.0, 255.0))
          let ds  = 9.0 + dp * 3.0   # diamond half-size
          let dcol = Color(r: 255, g: 220, b: 60, a: da)
          drawLine(Vector2(x: sx,      y: sy - ds), Vector2(x: sx + ds, y: sy     ), 2.0, dcol)
          drawLine(Vector2(x: sx + ds, y: sy     ), Vector2(x: sx,      y: sy + ds), 2.0, dcol)
          drawLine(Vector2(x: sx,      y: sy + ds), Vector2(x: sx - ds, y: sy     ), 2.0, dcol)
          drawLine(Vector2(x: sx - ds, y: sy     ), Vector2(x: sx,      y: sy - ds), 2.0, dcol)

  let playerVisible = game.state != gsDeathSequence

  # Draw Gravity Well visual effect
  if playerVisible and hasPowerUp(game.player, puGravityWell):
    let pullRadius = 300.0  # Matches actual gameplay pull radius

    # Draw swirling vortex rings
    for ring in 1..4:
      let ringRadius = pullRadius * (ring.float32 / 4.0)
      let alpha = uint8(60 - ring * 10)
      let rotationOffset = (game.time * (ring.float32 * 0.5)).float32

      # Draw spiral dots around each ring
      for i in 0..15:
        let angle = (i.float32 / 16.0) * PI * 2.0 + rotationOffset
        let x = game.player.pos.x + cos(angle) * ringRadius
        let y = game.player.pos.y + sin(angle) * ringRadius
        drawCircle(Vector2(x: x, y: y), 3, Color(r: 75, g: 0, b: 130, a: alpha))

    # Draw outer boundary, 3-pass so the pull limit is always clearly visible
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius + 4.0,
                   Color(r: 138, g: 43, b: 226, a: 55))
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius + 2.0,
                   Color(r: 138, g: 43, b: 226, a: 90))
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius,
                   Color(r: 170, g: 80, b: 255, a: 220))
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, pullRadius - 2.5,
                   Color(r: 200, g: 140, b: 255, a: 110))

  # UNIFIED AURA RENDERING
  # Draw all active aura effects using the unified aura system
  const AURA_TYPES = [puSlowField, puFireAura, puLightningAura, puPoisonAura, puWindAura, puArcaneAura, puBloodAura]
  if playerVisible:
    for auraType in AURA_TYPES:
      if hasPowerUp(game.player, auraType):
        let level = getPowerUpLevel(game.player, auraType)
        let config = getAuraConfig(auraType, level)
        drawAuraEffect(game.player.pos, config, game.time)

  # Draw player
  if playerVisible:
    drawPlayer(game.player)

  # Foreground particles, such as player muzzle bursts, render over the player.
  drawParticlePoolLayer(game.particlePool, plForeground)

  if game.player.lastDamageEvent == deDamage:
    # Re-use osBackground.alertLevel as a proxy for recent-damage intensity.
    # We clamp it to [0,1]; the existing alert system already fades it naturally.
    game.osBackground.alertLevel = min(game.osBackground.alertLevel + 0.5, 1.0)
    game.player.lastDamageEvent = deNone

  let showLowHealthVignette = globalSettings == nil or globalSettings.showLowHealthVignette
  if showLowHealthVignette and game.osBackground.lowHealthVignetteLevel > 0:
    let lowHpLevel = game.osBackground.lowHealthVignetteLevel
    let beatWave = max(0.0, sin(game.time * (3.4 + lowHpLevel * 1.6)))
    let beatScale = 1.0 + beatWave * (0.06 + lowHpLevel * 0.10)
    let lowHpMaxAlpha = lowHpLevel * 62.0 * beatScale
    let maxInset = 140.0 * (1.0 + beatWave * (0.03 + lowHpLevel * 0.04))
    for band in 0..7:
      let bandT = band.float32 / 7.0
      let inset = int32(bandT * maxInset)
      let bandAlpha = uint8(lowHpMaxAlpha * (1.0 - bandT) * 0.85)
      if bandAlpha == 0:
        continue

      let bandRect = Rectangle(
        x: inset.float32,
        y: inset.float32,
        width: max(0, game.screenWidth - inset * 2).float32,
        height: max(0, game.screenHeight - inset * 2).float32
      )
      drawRectangleLines(bandRect, 3, Color(r: 255, g: 0, b: 0, a: bandAlpha))

  # Full-screen red vignette when alertLevel > 0
  if game.osBackground.alertLevel > 0:
    let vigAlpha = uint8(game.osBackground.alertLevel * 92)
    let vW: int32 = 160
    drawRectangleGradientH(0, 0, vW, game.screenHeight,
      Color(r: 255, g: 0, b: 0, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientH(game.screenWidth - vW, 0, vW, game.screenHeight,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 255, g: 0, b: 0, a: vigAlpha))
    drawRectangleGradientV(0, 0, game.screenWidth, vW,
      Color(r: 255, g: 0, b: 0, a: vigAlpha), Color(r: 0, g: 0, b: 0, a: 0))
    drawRectangleGradientV(0, game.screenHeight - vW, game.screenWidth, vW,
      Color(r: 0, g: 0, b: 0, a: 0), Color(r: 255, g: 0, b: 0, a: vigAlpha))

  # Dungeon layer: doors, pedestals, shop terminal, room-transition fade
  if game.mode == gmRoguelite:
    drawDungeonOverlay(game)

  # Draw damage numbers (on top of everything except UI)
  for damageNum in game.damageNumbers:
    drawDamageNumber(damageNum)
  for currencyIndicator in game.currencyIndicators:
    drawCurrencyIndicator(currencyIndicator)
  for perkIndicator in game.perkIndicators:
    drawPerkIndicator(perkIndicator)

  # Update OS-style HUD
  updateOSHUD(game.osHUD, dt)

  # Draw unified combined HUD panel (top-left, almost touching top)
  drawCombinedHUDPanel(game, 10, 2)

  if game.recentPowerUpTimer > 0.0:
    drawRecentPowerUpInstall(game)
    if game.state notin {gsShop, gsPowerUpSelect}:
      game.recentPowerUpTimer = max(0.0'f32, game.recentPowerUpTimer - dt)

  # Draw action log (notifications)
  drawActionLog(game.osHUD, game.screenWidth, game.screenHeight)

  # Kill streak system removed - now only combo system is used
  if globalSettings == nil or globalSettings.showHints:
    drawCombo(game.dopamine.comboSystem, game.screenWidth, game.screenHeight, game.dopamine.currentTime)
    drawMicroRewards(game.dopamine.microRewards)

  # Wave start banner (slides in from top for first 1.5s of each wave).
  # Roguelite rooms reuse the wave machinery but have no wave number (currentWave
  # stays pinned at 1), so the generic banner would flash "WAVE 1" on every room.
  if game.waveInProgress and game.mode != gmRoguelite:
    let waveAge = game.time - game.waveStartTime
    let isBossNext = game.wavesUntilBoss == 0
    if globalSettings == nil or globalSettings.showHints:
      drawWaveStartBanner(game.currentWave, waveAge, game.screenWidth, game.screenHeight, isBossNext)

  drawWaveCelebration(game.dopamine.waveCelebration, game.screenWidth, game.screenHeight)
  drawBossIntroduction(game.dopamine.bossIntro, game.screenWidth, game.screenHeight)
  drawAchievementPopup(game.dopamine.achievements, game.screenWidth, game.screenHeight)

  if game.comebackBonusActive:
    let pulse = (sin(game.time * 2.5) * 0.15 + 0.85).float32
    let alpha = uint8(clamp(pulse * 230.0, 0.0, 255.0))
    let cbLabel = t(tkComebackBonusActive) & " (" & t(tkComebackBonusUntil) & " " & $game.comebackEndWave & ")"
    let cbFontSize: int32 = 13
    let cbW = measureText(cbLabel, cbFontSize)
    let cbX = game.screenWidth div 2 - cbW div 2
    let cbY: int32 = 6
    drawRectangle(cbX - 6, cbY - 2, cbW + 12, cbFontSize + 6, Color(r: 0, g: 0, b: 0, a: uint8(clamp(pulse * 140.0, 0.0, 255.0))))
    drawText(cbLabel, cbX, cbY, cbFontSize, Color(r: 80, g: 220, b: 100, a: alpha))

  # Boss entrance warning: flashing "!" on the screen edge the boss is entering from
  if game.bossWaveManager.isBossActive():
    # Avoid drawing over the wave banner when it's visible (suppressed in roguelite)
    let bannerVisible = if game.waveInProgress and game.mode != gmRoguelite: (game.time - game.waveStartTime) < 1.5 else: false

    # Helper: draw a minimal warning, just an exclamation with a soft circular background
    proc drawSimpleWarning(xCenter, yCenter: int32, timeFactor: float32) =
      let pulse = (sin(game.time * 6.0) + 1.0) * 0.5
      let alphaF = clamp(0.5 + pulse * 0.5, 0.0, 1.0) * timeFactor
      let bgAlpha = uint8(clamp(alphaF * 200.0, 0.0, 255.0))
      let ringAlpha = uint8(max(0, (bgAlpha.int div 3).int))
      # Soft filled circle
      drawCircle(Vector2(x: xCenter.float32, y: yCenter.float32), 36.0, Color(r: 255, g: 60, b: 60, a: bgAlpha))
      # Subtle outer ring
      drawCircleLines(xCenter, yCenter, 44.0, Color(r: 255, g: 60, b: 60, a: ringAlpha))
      # Exclamation mark
      let excFont: int32 = 44
      let excW = measureText("!", excFont)
      drawText("!", xCenter - excW div 2, yCenter - excFont div 2, excFont, Color(r: 255, g: 60, b: 60, a: 255))

    # If a boss is scheduled but not yet added, show its warning using pending data
    if game.pendingBoss != nil and game.pendingBossTimer > 0:
      let enemy = game.pendingBoss
      let sh = game.screenHeight.float32
      let fromTop    = enemy.startPos.y < 0
      let fromBottom = enemy.startPos.y > sh
      let fromLeft   = enemy.startPos.x < 0

      let pillW: int32 = 62
      let pillH: int32 = 62
      let pad:   int32 = 10
      var pillX, pillY: int32

      if fromTop:
        pillX = game.screenWidth div 2 - pillW div 2
        if bannerVisible:
          let bannerH: int32 = 44
          pillY = bannerH + pad + 6
        else:
          pillY = pad
      elif fromBottom:
        pillX = game.screenWidth div 2 - pillW div 2
        pillY = game.screenHeight - pillH - pad
      elif fromLeft:
        pillX = pad
        pillY = game.screenHeight div 2 - pillH div 2
      else:
        pillX = game.screenWidth - pillW - pad
        pillY = game.screenHeight div 2 - pillH div 2

      let cx = pillX + pillW div 2
      let cy = pillY + pillH div 2
      let timeFactor = clamp(1.0 - (game.pendingBossTimer / 0.2), 0.0, 1.0)
      drawSimpleWarning(cx, cy, timeFactor.float32)
    else:
      for enemy in game.enemies:
        if enemy.isBoss and enemy.entranceTimer > 0:
          let sh = game.screenHeight.float32
          let fromTop    = enemy.startPos.y < 0
          let fromBottom = enemy.startPos.y > sh
          let fromLeft   = enemy.startPos.x < 0

          let pillW: int32 = 62
          let pillH: int32 = 62
          let pad:   int32 = 10
          var pillX, pillY: int32

          if fromTop:
            pillX = game.screenWidth div 2 - pillW div 2
            if bannerVisible:
              let bannerH: int32 = 44
              pillY = bannerH + pad + 6
            else:
              pillY = pad
          elif fromBottom:
            pillX = game.screenWidth div 2 - pillW div 2
            pillY = game.screenHeight - pillH - pad
          elif fromLeft:
            pillX = pad
            pillY = game.screenHeight div 2 - pillH div 2
          else:
            pillX = game.screenWidth - pillW - pad
            pillY = game.screenHeight div 2 - pillH div 2

          let cx = pillX + pillW div 2
          let cy = pillY + pillH div 2
          # Entrance progress (used to modulate intensity)
          let entranceProg = clamp(1.0 - (enemy.entranceTimer / 2.0), 0.0, 1.0)
          drawSimpleWarning(cx, cy, (0.6 + 0.4 * entranceProg).float32)
          break

  # Boss phase health bars (top of screen), stacked downward up to 3.
  # Sandbox spawns bosses straight into game.enemies without arming the
  # bossWaveManager, so allow the HUD there too based on the enemy itself.
  if game.bossWaveManager.isBossActive() or isSandboxMode(game.mode):
    var nextBossBarY = 10'i32
    var bossBarCount = 0
    for enemy in game.enemies:
      if enemy.isBoss and enemy.entranceTimer <= 0:
        nextBossBarY = drawBossPhaseHud(game, enemy, nextBossBarY)
        bossBarCount += 1
        if bossBarCount >= 3:
          break

  # Time survival mode - show wave indicator (only for time survival)
  if isTimeSurvivalMode(game.mode):
    drawSurvivalHUD(game, game.screenWidth, game.screenHeight)

  # Combined HUD panel already shows all info, no need for separate panels

  # OS-Style Debug Panel (right side, touching right edge) - controlled by showDebugStats setting
  if globalSettings != nil and globalSettings.showDebugStats:
    drawDebugPanel(game, game.screenWidth, 2)

  # Compact Q ability cooldown strip replaces the old legendary cooldown window.
  drawLegendaryPowerUpsPanel(game, game.screenWidth.int32, game.screenHeight.int32)

  # Instructions only for non-legendary keys, hidden when the shop overlay is active
  if game.state != gsShop:
    if game.wallPlacementMode and game.player.walls > 0:
      # Placement mode: range ring + ghost wall at cursor
      let mousePos = getVirtualMousePosition()
      let cursorPos = newVector2f(mousePos.x, mousePos.y)
      let inRange = distance(cursorPos, game.player.pos) <= 250.0
      let validPos = isValidWallPlacement(cursorPos, game.player.pos, game.walls, game.enemies, 25)
      let canPlace = inRange and validPos

      # Faint range indicator around the player
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, 250.0,
                      Color(r: 180, g: 180, b: 255, a: 55))

      # Ghost wall circle at cursor: green = valid, red = blocked
      let ghostFill = if canPlace: Color(r: 80, g: 200, b: 80, a: 90)
                      else: Color(r: 200, g: 60, b: 60, a: 90)
      let ghostEdge = if canPlace: Color(r: 80, g: 255, b: 80, a: 200)
                      else: Color(r: 255, g: 60, b: 60, a: 200)
      drawCircle(Vector2(x: cursorPos.x, y: cursorPos.y), 25, ghostFill)
      drawCircleLines(cursorPos.x.int32, cursorPos.y.int32, 25, ghostEdge)

      # Status text at bottom
      let hintText = "[Release E] Place Wall  (" & $game.player.walls & " remaining)"
      let hintW = measureText(hintText, 16)
      drawText(hintText, game.screenWidth div 2 - hintW div 2,
               game.screenHeight - 25, 16, Color(r: 180, g: 230, b: 180, a: 255))
    else:
      drawText(t(tkGameInstructionsWall),
               game.screenWidth div 2 - 100, game.screenHeight - 25, 16, LightGray)

  # End 2D camera mode if screen shake was applied
  if shakeOffsetX != 0 or shakeOffsetY != 0:
    popMatrix()

proc drawDeathSequenceOverlay*(game: Game) =
  let timer = game.deathSequenceTimer
  let impactFlash = max(0.0'f32, 1.0'f32 - timer / 0.28'f32)
  if impactFlash > 0:
    drawRectangle(0, 0, game.screenWidth, game.screenHeight,
                  Color(r: 255, g: 242, b: 205, a: uint8(impactFlash * 145.0'f32)))
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y),
               46.0'f32 + (1.0'f32 - impactFlash) * 130.0'f32,
               Color(r: 255, g: 190, b: 80, a: uint8(impactFlash * 155.0'f32)))

  let ringProgress = clamp(timer / 0.72'f32, 0.0'f32, 1.0'f32)
  let ringAlpha = uint8((1.0'f32 - ringProgress) * 185.0'f32)
  if ringAlpha > 0:
    for i in 0..2:
      let ringRadius = game.player.radius + 34.0'f32 + ringProgress * (145.0'f32 + i.float32 * 78.0'f32)
      drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, ringRadius,
                      Color(r: 255, g: 215, b: 120, a: uint8(ringAlpha.int div (i + 1))))

  let slowPulseAlpha = uint8(max(0.0'f32, (1.0'f32 - timer / DEATH_SLOW_DURATION)) * 110.0'f32)
  if slowPulseAlpha > 0:
    let ringRadius = game.player.radius + 28.0'f32 + timer * 68.0'f32
    drawCircleLines(game.player.pos.x.int32, game.player.pos.y.int32, ringRadius,
                    Color(r: 255, g: 65, b: 65, a: slowPulseAlpha))
    drawCircle(Vector2(x: game.player.pos.x, y: game.player.pos.y), game.player.radius + 5.0'f32,
               Color(r: 255, g: 35, b: 35, a: uint8(slowPulseAlpha div 3)))

  let vignetteAlpha = uint8(min(120.0'f32, 55.0'f32 + game.deathSequenceFadeAlpha * 65.0'f32))
  let edgeW: int32 = 190
  drawRectangleGradientH(0, 0, edgeW, game.screenHeight,
    Color(r: 125, g: 0, b: 0, a: vignetteAlpha), Color(r: 0, g: 0, b: 0, a: 0))
  drawRectangleGradientH(game.screenWidth - edgeW, 0, edgeW, game.screenHeight,
    Color(r: 0, g: 0, b: 0, a: 0), Color(r: 125, g: 0, b: 0, a: vignetteAlpha))
  drawRectangleGradientV(0, 0, game.screenWidth, edgeW,
    Color(r: 125, g: 0, b: 0, a: vignetteAlpha), Color(r: 0, g: 0, b: 0, a: 0))
  drawRectangleGradientV(0, game.screenHeight - edgeW, game.screenWidth, edgeW,
    Color(r: 0, g: 0, b: 0, a: 0), Color(r: 125, g: 0, b: 0, a: vignetteAlpha))

  if game.deathSequenceFadeAlpha > 0:
    drawRectangle(0, 0, game.screenWidth, game.screenHeight,
                  Color(r: 0, g: 0, b: 0, a: uint8(game.deathSequenceFadeAlpha * 255.0'f32)))

proc drawGameOver*(game: Game) =
  # Use the new OS-style system crash screen
  drawSystemCrash(game, game.selectedGameOverButton)

proc drawVictory*(game: Game) =
  # OS-style "system secured" congratulations screen (wave-60 final boss cleared)
  drawSystemSecured(game, game.selectedVictoryButton)

proc drawWaveTransition*(game: Game) =
  # Draw the game in background
  drawGame(game)

  # Dark overlay
  drawRectangle(0, 0, game.screenWidth, game.screenHeight, Color(r: 0, g: 0, b: 0, a: 180))

  # Title
  drawText(t(tkGameGetReady), game.screenWidth div 2 - 120, game.screenHeight div 2 - 80, 50, Yellow)

  # Boss wave notification with wave number
  let bossWaveText = t(tkGameBossWavePrefix) & $(game.currentWave + 1)
  let bossTextWidth = measureText(bossWaveText, 35)
  drawText(bossWaveText, game.screenWidth div 2 - bossTextWidth div 2, game.screenHeight div 2, 35, Red)

  drawText(t(tkGameIncoming), game.screenWidth div 2 - 75, game.screenHeight div 2 + 40, 30, Orange)

  drawText(t(tkGamePressEnterToStart), game.screenWidth div 2 - 130, game.screenHeight - 80, 20, LightGray)
