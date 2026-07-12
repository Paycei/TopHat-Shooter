## Shared text-layout helpers for the OS-style UI windows.
## Leaf module: imports only raylib, safe to use from any ui/ module.

import raylib, strutils

type TextAlign* = enum
  taLeft, taCenter, taRight

proc bestFitFontSize*(text: string, maxWidth, preferredSize: int32,
                      minSize: int32 = 9): int32 =
  ## Shrink from preferredSize until `text` fits in `maxWidth` (or minSize).
  result = preferredSize
  if maxWidth <= 0:
    return
  while result > minSize and measureText(text, result) > maxWidth:
    dec result

proc drawTextFit*(text: string, x, y, maxWidth, fontSize: int32, color: Color,
                  minSize: int32 = 9, align: TextAlign = taLeft): int32 {.discardable.} =
  ## Draw `text` at the largest size that fits `maxWidth`; returns the size used.
  result = bestFitFontSize(text, maxWidth, fontSize, minSize)
  let textW = measureText(text, result)
  let drawX = case align
    of taLeft: x
    of taCenter: x + max(0'i32, (maxWidth - textW) div 2)
    of taRight: x + max(0'i32, maxWidth - textW)
  drawText(text, drawX, y, result, color)

proc drawCenteredTextFit*(text: string, x, y, maxWidth, fontSize: int32, color: Color,
                          minSize: int32 = 9): int32 {.discardable.} =
  drawTextFit(text, x, y, maxWidth, fontSize, color, minSize, taCenter)

proc wrapTextLines*(text: string, maxWidth, fontSize: int32): seq[string] =
  ## Greedy word-wrap to lines no wider than `maxWidth` at `fontSize`.
  let words = text.splitWhitespace()
  if words.len == 0:
    return @[]

  var currentLine = ""
  for word in words:
    let candidate = if currentLine.len == 0: word else: currentLine & " " & word
    if currentLine.len == 0 or measureText(candidate, fontSize) <= maxWidth:
      currentLine = candidate
    else:
      result.add(currentLine)
      currentLine = word

  if currentLine.len > 0:
    result.add(currentLine)

proc bestWrapFontSize*(text: string, maxWidth, preferredSize: int32,
                       maxLines: int, minSize: int32 = 9): int32 =
  ## Largest size at which the wrapped text needs at most `maxLines` lines.
  result = preferredSize
  if maxWidth <= 0:
    return
  while result > minSize:
    if wrapTextLines(text, maxWidth, result).len <= maxLines:
      return
    dec result
