import types, tables

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

  # Revisar si no existe el efecto O si el efecto actual ya está completamente terminado
  if not enemy.activeEffects.hasKey(effectType) or
     (not enemy.activeEffects[effectType].primary.isActive and
      enemy.activeEffects[effectType].primary.remainingDuration <= 0 and
      enemy.activeEffects[effectType].fallback.remainingDuration <= 0):
    # Nuevo efecto, crear o reinicializar completamente
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
    # Ya existe un efecto de este tipo y tiene duración o está activo
    let currentEffect = enemy.activeEffects[effectType]

    if damagePerSec > currentEffect.primary.damagePerSec:
      # El nuevo efecto es más fuerte, guardamos el actual como fallback
      var newActiveEffect = enemy.activeEffects[effectType]

      # Guardar el efecto actual como fallback (si tiene duración restante)
      if currentEffect.primary.remainingDuration > 0:
        newActiveEffect.fallback = EffectInstance(
          elementType: effectType,
          damagePerSec: currentEffect.primary.damagePerSec,
          remainingDuration: currentEffect.primary.remainingDuration,
          maxDuration: currentEffect.primary.maxDuration,
          isActive: false,
          source: currentEffect.primary.source
        )
      else:
        # El efecto anterior ya se acabó, no hay fallback
        newActiveEffect.fallback = nullEffect(effectType)

      # Aplicar el nuevo efecto como principal
      newActiveEffect.primary = EffectInstance(
        elementType: effectType,
        damagePerSec: damagePerSec,
        remainingDuration: duration,
        maxDuration: duration,
        isActive: true,
        source: source
      )

      enemy.activeEffects[effectType] = newActiveEffect
    elif damagePerSec == currentEffect.primary.damagePerSec and currentEffect.primary.isActive:
      # Mismo poder y primario está ACTIVO, extender duración
      var updated = enemy.activeEffects[effectType]
      # Si la nueva duración es mayor O si quiere refrescar, actualizar
      if duration > currentEffect.primary.remainingDuration:
        updated.primary.remainingDuration = duration
        updated.primary.maxDuration = duration
      enemy.activeEffects[effectType] = updated
    # Si es más débil que el actual activo, no hacemos nada (ignora el efecto débil)

proc updateEffects*(enemy: Enemy, dt: float32): float32 =
  ## Actualiza todos los efectos del enemigo y retorna el daño total a aplicar
  ## Retorna: daño total que debe aplicarse este frame

  var totalDamage: float32 = 0.0

  for elementType, activeEffect in enemy.activeEffects.mpairs:
    if activeEffect.primary.isActive and activeEffect.primary.remainingDuration > 0:
      # El efecto primario sigue activo
      totalDamage += activeEffect.primary.damagePerSec * dt
      activeEffect.primary.remainingDuration -= dt

      # Verificar si el primario se acabó
      if activeEffect.primary.remainingDuration <= 0:
        activeEffect.primary.remainingDuration = 0
        activeEffect.primary.isActive = false

        # Cambiar a fallback si existe
        if activeEffect.fallback.remainingDuration > 0:
          activeEffect.primary = activeEffect.fallback
          activeEffect.primary.isActive = true

          # Limpiar fallback
          activeEffect.fallback = nullEffect(elementType)

    # Asegurar que el fallback también se actualiza en tiempo (aunque no aplique daño)
    if activeEffect.fallback.remainingDuration > 0:
      activeEffect.fallback.remainingDuration -= dt
      if activeEffect.fallback.remainingDuration < 0:
        activeEffect.fallback.remainingDuration = 0

  return totalDamage

proc hasActiveEffect*(enemy: Enemy, elementType: ElementType): bool =
  ## Retorna true si hay un efecto activo de ese tipo
  if not enemy.activeEffects.hasKey(elementType):
    return false
  return enemy.activeEffects[elementType].primary.isActive
