import raylib

var
  currentRenderScale = 1.0'f32
  currentRenderOffsetX = 0.0'f32
  currentRenderOffsetY = 0.0'f32
  currentVirtualWidth = 1024.0'f32
  currentVirtualHeight = 768.0'f32

proc updateRenderInputTransform*(scale, offsetX, offsetY: float32,
                                 virtualWidth, virtualHeight: int32) =
  currentRenderScale = max(scale, 0.0001'f32)
  currentRenderOffsetX = offsetX
  currentRenderOffsetY = offsetY
  currentVirtualWidth = virtualWidth.float32
  currentVirtualHeight = virtualHeight.float32

proc getVirtualMousePosition*(): Vector2 =
  let screenPos = getMousePosition()
  result.x = (screenPos.x - currentRenderOffsetX) / currentRenderScale
  result.y = (screenPos.y - currentRenderOffsetY) / currentRenderScale
  result.x = clamp(result.x, 0.0'f32, currentVirtualWidth)
  result.y = clamp(result.y, 0.0'f32, currentVirtualHeight)
