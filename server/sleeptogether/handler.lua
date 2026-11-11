-- Sleep Together request handler. Embedded into the STRPM relay by
-- tools/build_server_resource.py and called by the relay for every validated
-- envelope, with the authenticated sender. Never calls cancelEvent (the relay
-- owns that) and never raises.

return function(logic, gameServer, playerManager)
  local CHANNEL = "sleeptogether.v1"
  local DEFAULT_TIME_SCALE = 20 -- STR default TimeModel.TimeScale
  local lastAdvanceMs = nil

  local function timeScale()
    local ok, value = pcall(function() return CalendarService:get():GetTimeScale() end)
    if ok and type(value) == "number" then
      return value
    end
    return DEFAULT_TIME_SCALE
  end

  local function handle(player, fields, message)
    if type(fields) ~= "table" or fields["channel"] ~= CHANNEL then
      return
    end
    local channel, payload = logic.decode_envelope(message)
    if channel ~= CHANNEL then
      return
    end

    local name = tostring(player:GetUsername())
    local hour = logic.parse_request(payload)
    -- GameServer:GetTick() is milliseconds (PartyService uses GetTick() + 10000
    -- as 10 seconds and + 60000 as 60 seconds).
    local now = gameServer:GetTick()
    local decision = logic.decide(
      player:IsPartyLeader(), #playerManager:GetAllPlayers(), hour, now, lastAdvanceMs)

    print("[SleepTogether] " .. name .. " -> " .. decision.kind ..
      (decision.reason and (" (" .. decision.reason .. ")") or ""))

    if decision.kind == "advance" then
      lastAdvanceMs = now
      gameServer:SetTime(decision.hour, 0, timeScale())
      gameServer:SendGlobalChatMessage(logic.advance_message(name, decision.hour))
    elseif decision.reason == "not_leader" then
      gameServer:SendChatMessage(player:GetConnectionId(), logic.deny_message())
    end
  end

  return function(player, fields, message)
    local ok, err = pcall(handle, player, fields, message)
    if not ok then
      print("[SleepTogether] Error: " .. tostring(err))
    end
  end
end
