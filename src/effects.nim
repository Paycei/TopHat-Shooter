import types

proc nullEffect(et: ElementType): EffectInstance =
  ## Returns a zeroed-out inactive EffectInstance for the given element type.
  EffectInstance(elementType: et, damagePerSec: 0.0, remainingDuration: 0.0,
                 maxDuration: 0.0, isActive: false, source: "")

# Sistema de gestión de efectos con fallback
# Previene stacking de efectos iguales pero permite fallback a efecto de menor poder

proc applyEffect*(enemy: Enemy, effectType: ElementType, damagePerSec: float32,
                  duration: float32, source: string) =
  ## Aplica un efecto al enemigo. Si ya existe uno del mismo tipo:
  ## - Si el nuevo es más fuerte (mayor dps), lo reemplaza y guarda el anterior como fallback
  ## - Si el actual está INACTIVO/terminado, aplica el nuevo igual
  ## - Si es igual o más débil pero el actual está activo, ignora

  let cur = enemy.activeEffects[effectType]

  # Apply fresh when slot is completely idle
  if not cur.primary.isActive and
     cur.primary.remainingDuration <= 0 and
     cur.fallback.remainingDuration <= 0:
    enemy.activeEffects[effectType] = ActiveEffect(
      primary: EffectInstance(
        elementType: effectType,
        damagePerSec: damagePerSec,
        remainingDuration: duration,
        maxDuration: duration,
        isActive: true,
        source: source
      ),
      fallback: nullEffect(effectType)
    )
  else:
    # Slot has an active or pending effect
    if damagePerSec > cur.primary.damagePerSec:
      # Stronger — push current to fallback if it still has duration
      var updated = enemy.activeEffects[effectType]
      updated.fallback =
        if cur.primary.remainingDuration > 0:
          EffectInstance(
            elementType: effectType,
            damagePerSec: cur.primary.damagePerSec,
            remainingDuration: cur.primary.remainingDuration,
            maxDuration: cur.primary.maxDuration,
            isActive: false,
            source: cur.primary.source
          )
        else:
          nullEffect(effectType)
      updated.primary = EffectInstance(
        elementType: effectType,
        damagePerSec: damagePerSec,
        remainingDuration: duration,
        maxDuration: duration,
        isActive: true,
        source: source
      )
      enemy.activeEffects[effectType] = updated
    elif damagePerSec == cur.primary.damagePerSec and cur.primary.isActive:
      # Same power and still active — extend if incoming duration is longer
      if duration > cur.primary.remainingDuration:
        var updated = enemy.activeEffects[effectType]
        updated.primary.remainingDuration = duration
        updated.primary.maxDuration = duration
        enemy.activeEffects[effectType] = updated
    # Weaker than active primary — ignore

proc updateEffects*(enemy: Enemy, dt: float32): float32 =
  ## Actualiza todos los efectos del enemigo y retorna el daño total a aplicar
  ## Retorna: daño total que debe aplicarse este frame

  var totalDamage: float32 = 0.0

  for elementType in ElementType:
    var ae = enemy.activeEffects[elementType]
    if ae.primary.isActive and ae.primary.remainingDuration > 0:
      totalDamage += ae.primary.damagePerSec * dt
      ae.primary.remainingDuration -= dt

      if ae.primary.remainingDuration <= 0:
        ae.primary.remainingDuration = 0
        ae.primary.isActive = false

        # Promote fallback if it has remaining duration
        if ae.fallback.remainingDuration > 0:
          ae.primary = ae.fallback
          ae.primary.isActive = true
          ae.fallback = nullEffect(elementType)

    # Tick fallback duration regardless
    if ae.fallback.remainingDuration > 0:
      ae.fallback.remainingDuration -= dt
      if ae.fallback.remainingDuration < 0:
        ae.fallback.remainingDuration = 0

    enemy.activeEffects[elementType] = ae

  return totalDamage

proc hasActiveEffect*(enemy: Enemy, elementType: ElementType): bool =
  ## Retorna true si hay un efecto activo de ese tipo
  enemy.activeEffects[elementType].primary.isActive
