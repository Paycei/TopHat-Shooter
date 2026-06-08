import raylib, math
import types, bullet_skins, bullet_shapes

## Boss ID -> bullet shape index. 0=circle, 1=diamond, 2=triangle, 3=star, 4=cross, 5=square
const bossBulletShapeTable = [
  0,  # 0: unused
  1,  # 1: Spiral Guardian    -> diamond
  3,  # 2: Summoner King      -> star
  2,  # 3: Meteor Striker     -> triangle
  4,  # 4: Laser Architect    -> cross
  1,  # 5: Void Dancer        -> diamond
  5,  # 6: Chain Reactor      -> square
  4,  # 7: Orbital Commander  -> cross
  2,  # 8: Berserker          -> triangle
  3,  # 9: Prism Architect    -> star
  5,  # 10: Timekeeper        -> square
  3,  # 11: Chaos Weaver      -> star
  4,  # 12: Omega Entity      -> cross
]

proc bossBulletShapeFor*(bossId: int): int =
  if bossId in 1..12: bossBulletShapeTable[bossId] else: 0

proc clampColorChannel(value: int): uint8 =
  uint8(clamp(value, 0, 255))

proc withAlpha(color: Color, alpha: int): Color =
  Color(r: color.r, g: color.g, b: color.b, a: clampColorChannel(alpha))

proc shiftColor(color: Color, delta: int, alpha: int = -1): Color =
  Color(
    r: clampColorChannel(color.r.int + delta),
    g: clampColorChannel(color.g.int + delta),
    b: clampColorChannel(color.b.int + delta),
    a: if alpha >= 0: clampColorChannel(alpha) else: color.a
  )

proc drawNgon(cx, cy, r: float32, n: int, rotation: float32, color: Color) =
  ## Draw a filled regular n-gon.
  for i in 0..<n:
    let a0 = rotation + i.float32 * PI * 2.0 / n.float32
    let a1 = rotation + (i + 1).float32 * PI * 2.0 / n.float32
    drawTriangle(
      Vector2(x: cx, y: cy),
      Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
      Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
      color)

proc drawNgonLines(cx, cy, r: float32, n: int, rotation: float32, color: Color, thick: float32 = 1.5) =
  for i in 0..<n:
    let a0 = rotation + i.float32 * PI * 2.0 / n.float32
    let a1 = rotation + (i + 1).float32 * PI * 2.0 / n.float32
    drawLine(
      Vector2(x: cx + cos(a0) * r, y: cy + sin(a0) * r),
      Vector2(x: cx + cos(a1) * r, y: cy + sin(a1) * r),
      thick, color)

proc drawBossCross(cx, cy, armRadius, halfWidth, rotation: float32, color: Color) =
  for arm in 0..1:
    let a = rotation + arm.float32 * PI / 2.0
    let ca = cos(a)
    let sa = sin(a)
    let px = Vector2(x: cx + ca * armRadius, y: cy + sa * armRadius)
    let nx = Vector2(x: cx - ca * armRadius, y: cy - sa * armRadius)
    let perp = Vector2(x: -sa * halfWidth, y: ca * halfWidth)
    drawTriangle(
      Vector2(x: px.x + perp.x, y: px.y + perp.y),
      Vector2(x: px.x - perp.x, y: px.y - perp.y),
      Vector2(x: nx.x + perp.x, y: nx.y + perp.y),
      color)
    drawTriangle(
      Vector2(x: nx.x + perp.x, y: nx.y + perp.y),
      Vector2(x: px.x - perp.x, y: px.y - perp.y),
      Vector2(x: nx.x - perp.x, y: nx.y - perp.y),
      color)

proc drawBossBulletTrail(bullet: Bullet, trailColor: Color) =
  if bullet.vel.length() <= 0:
    return

  let dir = bullet.vel.normalize()
  let lineStart = bullet.pos - dir * (bullet.radius + 11.0)
  drawLine(Vector2(x: lineStart.x, y: lineStart.y),
           Vector2(x: bullet.pos.x, y: bullet.pos.y), 3,
           withAlpha(trailColor, max(60, trailColor.a.int div 2)))

  for i in 0..2:
    let trailOffset = 8.0 + i.float32 * (bullet.radius + 2.0)
    let trailPos = bullet.pos - dir * trailOffset
    let trailRadius = max(1.6'f32, bullet.radius * (0.95 - i.float32 * 0.18))
    let trailAlpha = max(38, trailColor.a.int - i * 58)
    drawCircle(Vector2(x: trailPos.x, y: trailPos.y), trailRadius,
               withAlpha(trailColor, trailAlpha))

proc drawBossBulletShape*(bullet: Bullet, baseColor: Color, glowColor: Color, gameTime: float32) =
  ## Draw a boss bullet using its assigned shape, with rotation and glow.
  let cx = bullet.pos.x
  let cy = bullet.pos.y
  let r  = bullet.radius
  # Rotate based on game time for a lively spinning effect
  let spin = gameTime * 3.0
  let pulse = sin(gameTime * 9.0 + bullet.radius * 0.35) * 0.5 + 0.5
  let silhouetteColor = Color(r: 12, g: 5, b: 20, a: 220)
  let coreColor = shiftColor(baseColor, 80, 240)
  let rimColor = shiftColor(glowColor, 60, 230)
  let haloColor = withAlpha(glowColor, 100 + int(pulse * 40.0))
  let highlight = Color(r: 255, g: 255, b: 255, a: 220)

  # Shared draw helper for regular polygon bullet shapes (diamond, triangle, square).
  # All use the same layered structure; only sides, rotation, and a few scale tweaks differ.
  proc drawNgonBullet(sides: int, rot: float32, silhouetteR, glowPulse, coreScale: float32, glowAlpha: int) =
    drawNgon(cx, cy, silhouetteR, sides, rot, silhouetteColor)
    drawNgon(cx, cy, r + glowPulse, sides, rot, withAlpha(glowColor, glowAlpha))
    drawNgon(cx, cy, r, sides, rot, baseColor)
    drawNgon(cx, cy, r * coreScale, sides, rot, coreColor)
    drawNgonLines(cx, cy, r + 1.8, sides, rot, rimColor, 2.4)
    drawNgonLines(cx, cy, r + 4.8, sides, rot, haloColor, 1.7)
    drawNgonLines(cx, cy, r + 7.8, sides, rot, withAlpha(glowColor, 70), 1.0)
    drawCircle(Vector2(x: cx, y: cy), r * 0.24, highlight)

  case bullet.bossBulletShape
  of 1:  # Diamond (rotated square = 4-gon at 45°)
    drawNgonBullet(4, PI / 4.0 + spin, r + 6.5, 4.2 + pulse * 1.2, 0.56, 92)

  of 2:  # Triangle
    drawNgonBullet(3, -PI / 2.0 + spin * 0.7, r + 6.0, 4.0 + pulse * 1.1, 0.55, 92)

  of 5:  # Square (axis-aligned, slow rotation)
    drawNgonBullet(4, spin * 0.25, r + 6.2, 4.1 + pulse * 1.1, 0.55, 90)

  of 3:  # Star (two overlapping triangles, structurally distinct, kept explicit)
    let rot1 = -PI / 2.0 + spin * 0.5
    let rot2 = PI / 2.0 + spin * 0.5
    drawNgon(cx, cy, r + 6.0, 3, rot1, silhouetteColor)
    drawNgon(cx, cy, (r * 0.92) + 5.0, 3, rot2, silhouetteColor)
    drawNgon(cx, cy, r + 4.0 + pulse * 1.0, 3, rot1, withAlpha(glowColor, 88))
    drawNgon(cx, cy, r, 3, rot1, baseColor)
    drawNgon(cx, cy, r * 0.85, 3, rot2, coreColor)
    drawNgonLines(cx, cy, r + 1.8, 3, rot1, rimColor, 2.3)
    drawNgonLines(cx, cy, r + 1.6, 3, rot2, rimColor, 1.8)
    drawNgonLines(cx, cy, r + 5.0, 3, rot1, haloColor, 1.5)
    drawNgonLines(cx, cy, r + 5.0, 3, rot2, withAlpha(glowColor, 92), 1.2)
    drawCircle(Vector2(x: cx, y: cy), r * 0.24, Color(r: 255, g: 255, b: 255, a: 220))

  of 4:  # Cross / X
    let hw = r * 0.35  # half-width of each arm
    let rot = spin * 0.4
    drawBossCross(cx, cy, r + 3.8, hw + 2.2, rot, silhouetteColor)
    drawBossCross(cx, cy, r + 1.4, hw + 0.8, rot, withAlpha(glowColor, 90))
    # Draw two thick perpendicular lines as a cross using quads
    for arm in 0..1:
      let a = rot + arm.float32 * PI / 2.0
      let ca = cos(a); let sa = sin(a)
      let px = Vector2(x: cx + ca * r, y: cy + sa * r)
      let nx = Vector2(x: cx - ca * r, y: cy - sa * r)
      let perp = Vector2(x: -sa * hw, y: ca * hw)
      drawTriangle(
        Vector2(x: px.x + perp.x, y: px.y + perp.y),
        Vector2(x: px.x - perp.x, y: px.y - perp.y),
        Vector2(x: nx.x + perp.x, y: nx.y + perp.y),
        baseColor)
      drawTriangle(
        Vector2(x: nx.x + perp.x, y: nx.y + perp.y),
        Vector2(x: px.x - perp.x, y: px.y - perp.y),
        Vector2(x: nx.x - perp.x, y: nx.y - perp.y),
        baseColor)
    drawBossCross(cx, cy, r * 0.56, hw * 0.65, rot, coreColor)
    drawCircleLines(cx.int32, cy.int32, r + 3.5, rimColor)
    drawCircleLines(cx.int32, cy.int32, r + 6.5 + pulse, haloColor)
    drawCircleLines(cx.int32, cy.int32, r + 9.5, withAlpha(glowColor, 68))
    drawCircle(Vector2(x: cx, y: cy), r * 0.24, Color(r: 255, g: 255, b: 255, a: 220))

  else:  # Circle fallback
    drawCircle(Vector2(x: cx, y: cy), r + 6.0 + pulse, silhouetteColor)
    drawCircle(Vector2(x: cx, y: cy), r + 3.5 + pulse * 0.6, withAlpha(glowColor, 88))
    drawCircle(Vector2(x: cx, y: cy), r, baseColor)
    drawCircle(Vector2(x: cx, y: cy), r * 0.56, coreColor)
    drawCircleLines(cx.int32, cy.int32, r + 2, rimColor)
    drawCircleLines(cx.int32, cy.int32, r + 5 + pulse, haloColor)
    drawCircleLines(cx.int32, cy.int32, r + 8, withAlpha(glowColor, 70))
    drawCircle(Vector2(x: cx, y: cy), r * 0.22, Color(r: 255, g: 255, b: 255, a: 220))

const BASE_PLAYER_BULLET_RADIUS* = 5.0

proc newBullet*(x, y: float32, direction: Vector2f, speed, damage: float32, fromPlayer: bool = true,
                isHoming: bool = false, isPiercing: bool = false, isExplosive: bool = false,
                hasBounce: bool = false, canSplit: bool = false, slowAmount: float32 = 0,
                poisonDuration: float32 = 0, fireDuration: float32 = 0, windPushForce: float32 = 0,
                isPentagon: bool = false, isEcho: bool = false,
                isBossBullet: bool = false, isArcaneBullet: bool = false,
                sourceEnemyId: int = -1, sourceEnemyType: EnemyType = etCircle,
                isBonusFromMultiShot: bool = false, isBonusFromDoubleShot: bool = false,
                wasCrit: bool = false, isSpecialRound: bool = false,
                isFromWallTurret: bool = false, isFromRadialBurst: bool = false,
                isFromBulletSplit: bool = false, isRicochet: bool = false,
                isParried: bool = false,
                colorOverride: Color = Color(r: 0, g: 0, b: 0, a: 0),
                bulletSkin: int = 0, bulletId: int = 0, parentBulletId: int = -1,
                ownerPlayerIndex: int = -1, bossBulletShape: int = 0,
                bulletRadius: float32 = 0.0, bulletShape: int = 0): Bullet =
  # Faster projectiles across the board
  let finalSpeed = if fromPlayer: speed else: speed * 1.25  # Enemy bullets even faster

  result = Bullet(
    pos: newVector2f(x, y),
    vel: direction.normalize() * finalSpeed,
    radius: if fromPlayer: BASE_PLAYER_BULLET_RADIUS else: 6,
    damage: damage,
    fromPlayer: fromPlayer,
    lifetime: 4.0,  # Bullets despawn after 4 seconds (reduced from 5)
    isHoming: isHoming,
    isPiercing: isPiercing,
    isExplosive: isExplosive,
    piercedEnemies: 0,
    bounceCount: if hasBounce: 0 else: -1,
    hasSplit: not canSplit,
    slowAmount: slowAmount,  # Slow effect magnitude (0-1 range)
    poisonDuration: poisonDuration,  # Poison duration in seconds
    fireDuration: fireDuration,  # Fire duration in seconds
    windPushForce: windPushForce,  # Wind push force
    isPentagon: isPentagon,
    hitEnemies: @[],  # Initialize empty sequence
    sourceEnemyId: sourceEnemyId,  # Track which enemy shot this bullet
    sourceEnemyPos: newVector2f(x, y),  # Store the position where bullet was shot from
    sourceEnemyType: sourceEnemyType,  # Track enemy type for visual effects
    travelDistance: 0.0,  # Track distance for Overcharge
    isEcho: isEcho,  # Whether this is an echo trail bullet
    echoTrailTimer: 0.0,  # Timer for spawning echo trails
    echoHitEnemies: @[],  # Track echo damage per parent/enemy pair
    bulletId: bulletId,  # Unique ID for this bullet
    parentBulletId: parentBulletId,  # ID of parent bullet (for echo tracking)
    isBossBullet: isBossBullet,  # Mark boss bullets for glow effect
    bossBulletShape: bossBulletShape,  # Shape index for boss bullets
    isArcaneBullet: isArcaneBullet,  # Arcane bullet from arcane bullets power-up
    isBonusFromMultiShot: isBonusFromMultiShot,  # Bonus bullet from Multi-Shot
    isBonusFromDoubleShot: isBonusFromDoubleShot,  # Bonus bullet from Double Shot
    wasCrit: wasCrit,  # Whether this bullet was a critical hit
    isSpecialRound: isSpecialRound,  # Whether this is a special round
    isFromWallTurret: isFromWallTurret,  # Fired by a Wall Turret
    isFromRadialBurst: isFromRadialBurst,  # Fired by Radial Burst
    isFromBulletSplit: isFromBulletSplit,  # Created by Bullet Split
    isRicochet: isRicochet,  # Has already ricocheted
    isParried: isParried,  # Enemy bullet bounced back by Parry
    colorOverride: colorOverride,  # Custom bullet color (alpha=0 = use default)
    bulletSkin: bulletSkin,  # Bullet skin type
    bulletShape: bulletShape,  # Cosmetic bullet shape
    ownerPlayerIndex: ownerPlayerIndex  # For PvP: which player (0 or 1) shot this (-1 for non-PvP)
  )
  if bulletRadius > 0.0:
    result.radius = bulletRadius

proc updateBullet*(bullet: Bullet, dt: float32): bool =
  # Track distance traveled for Overcharge power-up
  let movement = bullet.vel * dt
  bullet.travelDistance += movement.length()

  bullet.pos = bullet.pos + movement
  bullet.lifetime -= dt
  return bullet.lifetime > 0

proc assignBulletId*(game: Game, bullet: Bullet) =
  ## Assign a unique ID to a bullet for parent-child tracking
  game.bulletIdCounter += 1
  bullet.bulletId = game.bulletIdCounter

proc drawBullet*(bullet: Bullet, hasOvercharge: bool = false, hasBloodBullets: bool = false, gameTime: float32 = 0.0) =
  # Get base color from bullet skin for player bullets
  var color: Color
  var glowColor: Color
  var trailColor: Color

  if bullet.fromPlayer and not bullet.isEcho:
    # Use bullet skin colors for player bullets
    let skinType = BulletSkinType(bullet.bulletSkin)
    let (primary, glow, trail) = getBulletSkinColors(skinType, gameTime)
    color = primary
    glowColor = glow
    trailColor = trail

    # Override color for special bullet types (these take priority over skin)
    if bullet.isSpecialRound:
      color = Color(r: 255, g: 215, b: 0, a: 255)  # Gold for special rounds
    elif hasBloodBullets:
      color = Color(r: 200, g: 50, b: 50, a: 255)  # Dark red for blood bullets
    elif bullet.isArcaneBullet:
      color = Color(r: 200, g: 100, b: 255, a: 255)  # Purple for arcane
  elif bullet.isEcho:
    # Echo bullets are semi-transparent and fade out
    let fadeAlpha = uint8((bullet.lifetime / 0.5) * 150.0)  # Fade based on remaining lifetime
    color = Color(r: 200, g: 200, b: 255, a: fadeAlpha)  # Ghost blue-white
    glowColor = Color(r: 200, g: 200, b: 255, a: fadeAlpha div 2)
    trailColor = Color(r: 180, g: 180, b: 255, a: fadeAlpha)
  else:
    # Enemy bullets - pink by default, special colors for specific enemy types
    if bullet.colorOverride.a > 0:
      # Custom color override (e.g. meteor bullets)
      color = bullet.colorOverride
      glowColor = Color(r: bullet.colorOverride.r, g: bullet.colorOverride.g,
                        b: bullet.colorOverride.b, a: 120)
      trailColor = bullet.colorOverride
    elif bullet.sourceEnemyType == etSniper:
      # Sniper bullets are bright red with glow
      color = Color(r: 255, g: 50, b: 50, a: 255)  # Bright red
      glowColor = Color(r: 255, g: 0, b: 0, a: 150)  # Red glow
      trailColor = Color(r: 220, g: 50, b: 50, a: 255)  # Red trail
    else:
      # Regular enemy bullets (including pentagon) are pink
      color = Pink
      glowColor = Color(r: 255, g: 100, b: 150, a: 100)
      trailColor = Pink

    if bullet.isBossBullet:
      if bullet.colorOverride.a > 0:
        glowColor = shiftColor(bullet.colorOverride, 55, 220)
        trailColor = withAlpha(shiftColor(bullet.colorOverride, 20), 235)
      else:
        color = Color(r: 255, g: 72, b: 190, a: 255)
        glowColor = Color(r: 255, g: 225, b: 245, a: 220)
        trailColor = Color(r: 255, g: 130, b: 215, a: 240)

  if bullet.isBossBullet:
    let warningPulse = sin(gameTime * 10.0 + bullet.radius * 0.25) * 0.5 + 0.5
    drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius + 6.5 + warningPulse * 1.4,
               Color(r: 10, g: 4, b: 22, a: 110))
    drawBossBulletTrail(bullet, trailColor)

  # Draw bullet trail for player bullets (showcases skin colors)
  # Reduce trail for explosive bullets to improve performance
  if bullet.fromPlayer and not bullet.isEcho and bullet.vel.length() > 0:
    let maxTrailSegments = if bullet.isExplosive: 2 else: 3  # Fewer trail segments for explosive
    for i in 0..maxTrailSegments:
      let trailOffset = (i.float32 + 1) * 5.0
      let trailPos = bullet.pos - bullet.vel.normalize() * trailOffset
      let trailRadius = bullet.radius * (1.0 - i.float32 * 0.15)
      let trailAlpha = uint8((1.0 - i.float32 * 0.25) * float32(trailColor.a))
      drawCircle(Vector2(x: trailPos.x, y: trailPos.y), trailRadius,
                Color(r: trailColor.r, g: trailColor.g, b: trailColor.b, a: trailAlpha))

  # Draw pentagon shape for pentagon bullets
  if bullet.isPentagon:
    # Draw pentagon shape
    let points = 5
    for i in 0..<points:
      let angle = i.float32 * PI * 2.0 / 5.0 - PI / 2.0  # Start from top
      let nextAngle = (i + 1).float32 * PI * 2.0 / 5.0 - PI / 2.0
      let x1 = bullet.pos.x + cos(angle) * bullet.radius
      let y1 = bullet.pos.y + sin(angle) * bullet.radius
      let x2 = bullet.pos.x + cos(nextAngle) * bullet.radius
      let y2 = bullet.pos.y + sin(nextAngle) * bullet.radius
      drawLine(Vector2(x: x1, y: y1), Vector2(x: x2, y: y2), 3, color)
    # Fill center
    drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius * 0.5, color)
  elif bullet.isBossBullet and bullet.bossBulletShape > 0:
    # Boss bullets with a unique shape shape + glow already handled together
    drawBossBulletShape(bullet, color, glowColor, gameTime)
  elif bullet.fromPlayer and not bullet.isEcho and bullet.bulletShape > 0:
    # Player cosmetic bullet shape
    let travelAngle = arctan2(bullet.vel.y, bullet.vel.x)
    drawPlayerBulletShape(bullet.pos, bullet.radius,
                          BulletShapeType(bullet.bulletShape), travelAngle,
                          color, glowColor)
  else:
    # Normal circle bullet
    drawCircle(Vector2(x: bullet.pos.x, y: bullet.pos.y), bullet.radius, color)

  # Blood bullets: Add dripping blood effect
  if hasBloodBullets and bullet.fromPlayer and not bullet.isEcho:
    # Create 2-3 blood drips trailing behind the bullet
    for i in 0..2:
      let dripOffset = i.float32 * 4.0 + 3.0
      # Calculate drip position behind bullet (opposite to velocity)
      let dripX = bullet.pos.x - bullet.vel.normalize().x * dripOffset
      let dripY = bullet.pos.y - bullet.vel.normalize().y * dripOffset + i.float32 * 2.0  # Slight fall effect
      let dripSize = bullet.radius * (0.5 - i.float32 * 0.1)  # Smaller drips behind
      let dripAlpha = uint8(180 - i * 50)  # Fade drips
      drawCircle(Vector2(x: dripX, y: dripY), dripSize,
                Color(r: 150, g: 30, b: 30, a: dripAlpha))
      # Add a darker blood dot below each drip for extra drippiness
      drawCircle(Vector2(x: dripX, y: dripY + dripSize * 0.5), dripSize * 0.4,
                Color(r: 100, g: 20, b: 20, a: dripAlpha))

  # Add glow effect
  if not bullet.fromPlayer:
    # Sniper bullets get strong red glow
    if bullet.sourceEnemyType == etSniper:
      # Multiple red glow rings for sniper bullets
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                     Color(r: 255, g: 80, b: 80, a: 180))
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 4,
                     Color(r: 255, g: 50, b: 50, a: 120))
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 6,
                     Color(r: 255, g: 20, b: 20, a: 60))
    # Boss bullets get a special strong glow effect
    elif bullet.isBossBullet:
      if bullet.bossBulletShape == 0:
        # Circle fallback, draw old-style glow rings
        drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 4,
                       Color(r: 255, g: 50, b: 150, a: 200))
        drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 7,
                       Color(r: 255, g: 100, b: 150, a: 120))
        drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 10,
                       Color(r: 255, g: 150, b: 180, a: 60))
      # shaped boss bullets already drew their glow inside drawBossBulletShape
    else:
      # Regular enemy bullets - standard pink glow
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                     Color(r: 255, g: 100, b: 150, a: 100))
  elif bullet.fromPlayer and not bullet.isEcho:
    # Player bullet skin glow effects
    # Draw multiple glow rings
    for i in 0..1:
      let glowRadius = bullet.radius + 2.0 + i.float32 * 2.0
      let glowAlpha = uint8(float32(glowColor.a) * (1.0 - i.float32 * 0.4))
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, glowRadius,
                     Color(r: glowColor.r, g: glowColor.g, b: glowColor.b, a: glowAlpha))

    # Add highlight to bullet
    drawCircle(Vector2(x: bullet.pos.x - 1.5, y: bullet.pos.y - 1.5), bullet.radius * 0.3,
              Color(r: 255, g: 255, b: 255, a: 120))

  # Legacy glow effects for power-up modified bullets
  if bullet.isExplosive:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 255, g: 150, b: 0, a: 150))
  if bullet.windPushForce > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 180, g: 220, b: 255, a: 150))
  if bullet.slowAmount > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 100, g: 150, b: 255, a: 150))
  if bullet.poisonDuration > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 50, g: 255, b: 50, a: 150))
  if bullet.fireDuration > 0:
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 255, g: 100, b: 30, a: 180))
  if bullet.isArcaneBullet:
    # Arcane bullet glow - purple arcane aura
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 200, g: 100, b: 255, a: 200))
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 4,
                   Color(r: 150, g: 50, b: 200, a: 100))

  # Special Round visual effect - golden glow with sparkles
  if bullet.isSpecialRound and bullet.fromPlayer:
    # Main golden glow
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 2,
                   Color(r: 255, g: 215, b: 0, a: 255))
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 4,
                   Color(r: 255, g: 200, b: 50, a: 180))
    drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, bullet.radius + 6,
                   Color(r: 255, g: 180, b: 100, a: 120))

  # Overcharge visual effect - ONLY if player has the power-up
  if hasOvercharge and bullet.fromPlayer and bullet.travelDistance > 0:
    # Calculate charge level based on distance (0.0 to 1.0)
    let chargeLevel = min(bullet.travelDistance / 2500.0, 1.0)  # Max at 2500 units

    if chargeLevel > 0.1:  # Only show glow when bullet has traveled some distance
      # Color shift: Yellow (low) -> Orange (mid) -> Red (high)
      let glowColor = if chargeLevel < 0.33:
        # Yellow to Orange
        let t = chargeLevel / 0.33
        Color(
          r: 255,
          g: uint8(255.0 - t * 100.0),  # 255 -> 155
          b: 0,
          a: uint8(100.0 + chargeLevel * 100.0)
        )
      elif chargeLevel < 0.66:
        # Orange to Red
        let t = (chargeLevel - 0.33) / 0.33
        Color(
          r: 255,
          g: uint8(155.0 - t * 155.0),  # 155 -> 0
          b: 0,
          a: uint8(100.0 + chargeLevel * 100.0)
        )
      else:
        # Deep Red (max charge)
        Color(
          r: 255,
          g: 0,
          b: 0,
          a: uint8(100.0 + chargeLevel * 100.0)
        )

      # Draw expanding glow rings
      let glowRadius = bullet.radius + 2 + chargeLevel * 4
      drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, glowRadius, glowColor)

      # Add a second, larger glow ring for high charge
      if chargeLevel > 0.5:
        let outerGlow = glowColor
        let outerRadius = glowRadius + 3
        drawCircleLines(bullet.pos.x.int32, bullet.pos.y.int32, outerRadius,
                       Color(r: outerGlow.r, g: outerGlow.g, b: outerGlow.b, a: outerGlow.a div 2))

proc isOffScreen*(bullet: Bullet, screenWidth, screenHeight: int32): bool =
  bullet.pos.x < -50 or bullet.pos.x > screenWidth.float32 + 50 or
  bullet.pos.y < -50 or bullet.pos.y > screenHeight.float32 + 50

proc checkBulletEnemyCollision*(bullet: Bullet, enemy: Enemy): bool =
  if not bullet.fromPlayer: return false
  distance(bullet.pos, enemy.pos) < bullet.radius + enemy.radius

proc checkBulletPlayerCollision*(bullet: Bullet, player: Player): bool =
  if bullet.fromPlayer: return false
  distance(bullet.pos, player.pos) < bullet.radius + player.radius

proc checkBulletWallCollision*(bullet: Bullet, wall: Wall): bool =
  if bullet.fromPlayer: return false # Player bullets pass through walls
  distance(bullet.pos, wall.pos) < bullet.radius + wall.radius

proc checkShieldCollision*(bullet: Bullet, shieldPos: Vector2f): bool =
  # Check if enemy bullet hits player's rotating shield
  if bullet.fromPlayer: return false
  distance(bullet.pos, shieldPos) < bullet.radius + 6

## Utility functions for bullet synergies and cloning

proc cloneBullet*(original: Bullet, newPos: Vector2f, newVel: Vector2f,
                  damageMultiplier: float32 = 1.0, speedMultiplier: float32 = 1.0,
                  radiusMultiplier: float32 = 1.0, preventSplit: bool = false): Bullet =
  ## Clone a bullet preserving ALL its properties for perfect synergy
  ## This ensures Split Shot, Echo, and other effects inherit all bullet modifiers
  result = newBullet(
    newPos.x, newPos.y, newVel.normalize(),
    original.vel.length() * speedMultiplier,
    original.damage * damageMultiplier,
    original.fromPlayer,
    original.isHoming,
    original.isPiercing,
    original.isExplosive,
    original.bounceCount >= 0,  # hasBounce
    not preventSplit,  # canSplit (inverse of preventSplit)
    original.slowAmount,
    original.poisonDuration,
    original.fireDuration,
    original.windPushForce,  # Preserve wind push force
    original.isPentagon,
    original.isEcho,
    original.isBossBullet,
    original.isArcaneBullet,  # Preserve arcane bullet property for split shots
    -1,  # sourceEnemyId
    original.sourceEnemyType,  # Preserve enemy type for visual effects
    false,  # isBonusFromMultiShot
    false,  # isBonusFromDoubleShot
    original.wasCrit,  # Preserve crit status
    original.isSpecialRound,  # Preserve special round status
    original.isFromWallTurret,  # Preserve wall turret origin
    original.isFromRadialBurst,  # Preserve radial burst origin
    original.isFromBulletSplit,  # Preserve split origin
    original.isRicochet,  # Preserve ricochet flag
    original.isParried,  # Preserve parry flag
    original.colorOverride,  # Preserve custom color
    original.bulletSkin,  # Preserve bullet skin
    0,  # bulletId (will be assigned later)
    -1,  # parentBulletId
    original.ownerPlayerIndex,  # Preserve owner for PvP
    original.bossBulletShape,  # Preserve boss bullet shape
    0.0,  # bulletRadius (use stored radius below)
    original.bulletShape   # Preserve cosmetic bullet shape
  )

  # Copy additional state that needs to be preserved
  result.radius = original.radius * radiusMultiplier
  result.travelDistance = original.travelDistance  # Preserve Overcharge progress
  result.bounceCount = original.bounceCount  # Preserve ricochet state
  result.piercedEnemies = original.piercedEnemies  # Preserve pierce state
  result.hasSplit = preventSplit or original.hasSplit  # Preserve split state

  # Copy hit enemies list for independent tracking
  for enemyIdx in original.hitEnemies:
    result.hitEnemies.add(enemyIdx)
  for enemyIdx in original.echoHitEnemies:
    result.echoHitEnemies.add(enemyIdx)

proc createSplitBullets*(game: Game, sourceBullet: Bullet, splitCount: int,
                        damageMultiplier: float32 = 0.5, speedMultiplier: float32 = 0.7) =
  ## Create damage-only split fragments.
  ## Split Shot creates extra hits, but child bullets should not become full
  ## carriers for piercing, ricochet, explosive, elemental, or other on-hit
  ## packages.

  # Get the original bullet's direction angle
  let baseAngle = arctan2(sourceBullet.vel.y, sourceBullet.vel.x)

  # Create spread based on number of splits
  # For 2 splits: -22.5° and +22.5° from original direction
  # For 3 splits: -30°, 0°, +30° from original direction
  # For 4 splits: -37.5°, -12.5°, +12.5°, +37.5° from original direction
  let spreadAngle = case splitCount
    of 2: PI / 8.0  # 22.5 degrees
    of 3: PI / 6.0  # 30 degrees
    of 4: PI / 4.8  # 37.5 degrees
    else: PI / 6.0

  for split in 0..<splitCount:
    # Calculate angle offset from center
    let offsetAngle = if splitCount == 2:
      # For 2 bullets: split left and right
      if split == 0: -spreadAngle else: spreadAngle
    else:
      # For 3+ bullets: distribute evenly with center bullet at original angle
      let halfCount = (splitCount - 1).float32 / 2.0
      (split.float32 - halfCount) * (spreadAngle * 2.0 / (splitCount - 1).float32)

    let finalAngle = baseAngle + offsetAngle
    let dir = newVector2f(cos(finalAngle), sin(finalAngle))
    let vel = dir * sourceBullet.vel.length() * speedMultiplier

    let splitBullet = cloneBullet(
      sourceBullet,
      sourceBullet.pos,
      vel,
      damageMultiplier,
      speedMultiplier,
      0.9,  # Slightly smaller radius
      true  # Prevent infinite splitting
    )
    splitBullet.isFromBulletSplit = true  # Mark for statistics tracking
    splitBullet.isPiercing = false
    splitBullet.isExplosive = false
    splitBullet.bounceCount = -1
    splitBullet.piercedEnemies = 0
    splitBullet.slowAmount = 0
    splitBullet.poisonDuration = 0
    splitBullet.fireDuration = 0
    splitBullet.windPushForce = 0
    splitBullet.isArcaneBullet = false
    splitBullet.isSpecialRound = false
    splitBullet.isRicochet = false

    game.bullets.add(splitBullet)

proc createRicochetBullet*(game: Game, sourceBullet: Bullet, targetPos: Vector2f,
                          damageMultiplier: float32 = 0.75) =
  ## Create a ricochet bullet that inherits ALL properties
  ## SYNERGY SYSTEM: Ricochet bullets can split, explode, poison, etc.
  let toTarget = (targetPos - sourceBullet.pos).normalize()
  let vel = toTarget * sourceBullet.vel.length()

  let ricochetBullet = cloneBullet(
    sourceBullet,
    sourceBullet.pos,
    vel,
    damageMultiplier,
    1.0,  # Same speed
    1.0,  # Same size
    false  # Can still split
  )

  # Increment bounce count for the new bullet
  ricochetBullet.bounceCount += 1
  ricochetBullet.isRicochet = true  # Mark for statistics tracking

  game.bullets.add(ricochetBullet)

proc createEchoBullet*(game: Game, sourceBullet: Bullet,
                      damageMultiplier: float32 = 0.4, speedMultiplier: float32 = 0.5,
                      lifetime: float32 = 0.35) =
  ## Create a damage-only echo trail bullet.
  ## Echoes inherit the source's current damage and visuals, but not recursive
  ## shot modifiers or on-hit effects.
  ## Echo bullets track their parent so they can be removed when parent hits.
  ## They also inherit the parent's hit history so piercing/ricochet bullets
  ## cannot echo-damage the same target repeatedly.
  let echoBullet = cloneBullet(
    sourceBullet,
    sourceBullet.pos,
    sourceBullet.vel,
    damageMultiplier,
    speedMultiplier,
    0.8,  # Slightly smaller
    true  # Echo trails must not split recursively
  )

  # Assign unique bullet ID and track parent
  game.bulletIdCounter += 1
  echoBullet.bulletId = game.bulletIdCounter
  echoBullet.parentBulletId = sourceBullet.bulletId

  # Make it an echo bullet with limited lifetime
  echoBullet.isEcho = true
  echoBullet.lifetime = lifetime

  # Echoes are extra damage, not extra applications of every shot modifier.
  echoBullet.isPiercing = false
  echoBullet.isExplosive = false
  echoBullet.bounceCount = -1
  echoBullet.piercedEnemies = 0
  echoBullet.hasSplit = true
  echoBullet.slowAmount = 0
  echoBullet.poisonDuration = 0
  echoBullet.fireDuration = 0
  echoBullet.windPushForce = 0
  echoBullet.isArcaneBullet = false
  echoBullet.isSpecialRound = false
  echoBullet.isBonusFromMultiShot = false
  echoBullet.isBonusFromDoubleShot = false
  echoBullet.isFromWallTurret = false
  echoBullet.isFromRadialBurst = false
  echoBullet.isFromBulletSplit = false
  echoBullet.isRicochet = false
  echoBullet.isParried = false
  echoBullet.isFromNova = false

  for enemyId in sourceBullet.echoHitEnemies:
    if enemyId notin echoBullet.hitEnemies:
      echoBullet.hitEnemies.add(enemyId)

  game.bullets.add(echoBullet)
