# Changelog - Sistema de Guardado y Estadísticas

## Cambios Realizados

### 📁 Nuevos Archivos

1. **`src/save_system.nim`** - Sistema completo de guardado
   - Funciones para obtener rutas de AppData multiplataforma
   - Serialización/deserialización JSON para settings
   - Guardado y carga de estadísticas
   - Manejo robusto de errores con try-catch

2. **`src/statistics.nim`** - Sistema de estadísticas
   - Tipos `Statistics` y `GameModeStats`
   - Trackeo separado para Wave Mode y Time Survival
   - Cálculo de promedios y récords
   - Función `formatTime` para mostrar tiempo legible
   - Función `updateStats` para actualizar al terminar partida

3. **`SAVE_SYSTEM.md`** - Documentación completa
   - Explicación detallada del sistema
   - Ubicaciones de archivos por plataforma
   - Ejemplos de JSON
   - Guía para desarrolladores

4. **`stats.example.json`** - Ejemplo de archivo de estadísticas
5. **`settings.example.json`** - Ejemplo de archivo de configuraciones (actualizado)

### 🔧 Archivos Modificados

#### `src/save_system.nim` (completo rewrite)
- Cambiada ubicación de guardado de `.` a `%APPDATA%\TopHat\Shooter\`
- Soporte multiplataforma (Windows/macOS/Linux)
- Agregado manejo de estadísticas


#### `src/settings.nim`
- Agregado `import save_system`
- Carga automática de settings en `initSettings()`
- Guardado automático al cambiar cualquier setting:
  - FPS limit (al presionar Enter)
  - Volumen (al soltar slider)
  - Checkboxes (fullscreen, showFPS, mouseSupport, showCursorInMenus)

#### `src/main.nim`
- Agregado `import save_system, statistics`
- Inicialización y carga de estadísticas al inicio
- Nueva variable `statsSavedThisGame` para evitar guardado múltiple
- Guardado automático de estadísticas en Game Over (solo sin cheats)
- Reset del flag al iniciar nueva partida
- Nuevo estado `gsStatistics` con pantalla de estadísticas
- Nueva opción "Statistics" en menú principal (ahora son 6 opciones)
- Función `drawStatistics()` para mostrar stats detalladas
- Ajustes en navegación del menú (mod 6 en lugar de mod 5)

#### `src/types.nim`
- Agregado `gsStatistics` al enum `GameState`

#### `.gitignore`
- Agregado `stats.json` para no commitear estadísticas personales

### ✨ Nuevas Características

#### Sistema de Guardado en AppData
- **Ubicación multiplataforma**: 
  - Windows: `%APPDATA%\TopHat\Shooter\`
  - macOS: `~/Library/Application Support/TopHat/Shooter/`
  - Linux: `~/.local/share/TopHat/Shooter/`
