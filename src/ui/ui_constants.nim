## UI Constants
## Centralized constants for UI display settings

import math

# BALANCE DISPLAY MULTIPLIER
# This multiplier is applied to ALL health and damage values shown in the UI
const BALANCE_MULTIPLIER* = 100

proc formatHealthDisplay*(value: float32): string =
  ## Format health/damage value for display: multiply by 100 and round to nearest integer
  ## Example: 2.46 -> "246", 3.0 -> "300", 1.234 -> "123", 1.235 -> "124"
  let scaled = value * 100.0
  # Round to nearest integer
  result = $round(scaled).int
