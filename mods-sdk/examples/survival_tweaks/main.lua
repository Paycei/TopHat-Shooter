-- Survival Tweaks: changing an existing game mode with filters and vetoes.

hooks.on("survivalEvent", function(game, eventName)
  -- Returning true cancels the event.
  if eventName == "sekFirewallBreach" then
    mod.log("vetoed a Firewall Breach")
    return true
  end
end)

hooks.on("survivalSpawn", function(enemyType, game)
  -- Filters return a replacement, or nothing to keep the game's choice.
  if enemyType == "etThread" and math.random() < 0.15 then
    return "etDaemon"
  end
end)

hooks.on("xpValue", function(amount, enemy)
  if game:isMode("survival") then return amount * 2 end
end)
