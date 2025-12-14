type
  Settings* = ref object
    fpsLimit*: int32
    volume*: float32
    musicVolume*: float32
    inputBuffer*: string
    editingFPS*: bool
    fullscreen*: bool
    showFPS*: bool  # New setting to show FPS counter
    mouseSupport*: bool  # Enable mouse support in menus (always works in-game and settings)
    showCursorInMenus*: bool  # Show cursor in menus when mouseSupport is disabled
