-- Sleep Together request handler and session driver. Embedded into the STRPM
-- relay by tools/build_server_resource.py. The relay calls `handle` for every
-- validated envelope with the authenticated sender, and the server calls `tick`
-- from the onUpdate event (argument: seconds since the last update). Never calls
-- cancelEvent (the relay owns that) and never raises.
--
-- Returns two functions: handle(player, fields, message) -> true when the
-- envelope is on our channel (handled, must not be relayed), false otherwise;
-- and tick(deltaSeconds).

return function(logic, gameServer, playerManager, calendar)
  local CHANNEL = "sleeptogether.v1"
  local lastAdvanceMs = nil
  local session = nil -- { state, total, connId, playerId, name }
  local counter = 0

  local function log(text)
    print("[SleepTogether] " .. text)
  end

  local function now_ms()
    local ok, value = pcall(function() return gameServer:GetTick() end)
    if ok and type(value) == "number" then
      return value
    end
    return 0
  end

  local function player_count()
    -- Count with ipairs exactly like the relay does; `#` on the sol2 container is unproven.
    local count = 0
    for _ in ipairs(playerManager:GetAllPlayers()) do
      count = count + 1
    end
    return count
  end

  local function broadcast(payloadText)
    counter = counter + 1
    local envelope = logic.build_envelope(
      CHANNEL, counter, "sleeptogether-" .. counter,
      session.connId, session.playerId, session.name, payloadText, now_ms())
    local ok, players = pcall(function() return playerManager:GetAllPlayers() end)
    if not ok then
      log("Error: could not list players: " .. tostring(players))
      return
    end
    for _, player in ipairs(players) do
      local sent, err = pcall(function()
        gameServer:SendChatMessage(player:GetConnectionId(), envelope)
      end)
      if not sent then
        log("Error: send failed: " .. tostring(err))
      end
    end
  end

  local function hours_for(kind, value)
    if kind == "HOURS" then
      return value
    end
    local ok, hours = pcall(function() return calendar:HoursUntil(value) end)
    if not ok then
      log("Error: HoursUntil failed: " .. tostring(hours))
      return nil
    end
    if type(hours) ~= "number" or hours ~= hours or hours <= 0 or hours > 24 then
      log("ignoring UNTIL " .. tostring(value) .. ": bad hour span " .. tostring(hours))
      return nil
    end
    return hours
  end

  local function handle_request(player, payload)
    local kind, value = logic.parse_request(payload)
    if kind == nil then
      log("ignored a non-request payload on " .. CHANNEL)
      return
    end

    local leaderOk, isLeader = pcall(function() return player:IsPartyLeader() end)
    isLeader = leaderOk and isLeader == true
    local now = now_ms()
    local decision = logic.decide(isLeader, player_count(), now, lastAdvanceMs, session ~= nil)

    if decision.kind ~= "advance" then
      if decision.reason == "not_leader" then
        log("deny (not_leader)")
        gameServer:SendChatMessage(player:GetConnectionId(), logic.deny_message())
      else
        log("ignored request (" .. tostring(decision.reason) .. ")")
      end
      return
    end

    local hours = hours_for(kind, value)
    if hours == nil then
      return
    end
    local connId = player:GetConnectionId()
    local playerId = player:GetId()
    local name = tostring(player:GetUsername())
    local state = logic.new_session(hours)

    session = { state = state, total = state.remaining, connId = connId, playerId = playerId, name = name }
    lastAdvanceMs = now
    log(name .. " sleeps for " .. string.format("%g", hours) .. " h")
  end

  local function handle(player, fields, message)
    if type(fields) ~= "table" or fields["channel"] ~= CHANNEL then
      return false
    end
    local ok, err = pcall(function()
      local channel, payload = logic.decode_envelope(message)
      if channel ~= CHANNEL then
        log("ignored undecodable envelope on " .. CHANNEL)
        return
      end
      handle_request(player, payload)
    end)
    if not ok then
      log("Error: " .. tostring(err))
    end
    return true
  end

  local function run_tick(deltaSeconds)
    local steps, finished = logic.session_tick(session.state, deltaSeconds)
    for _, step in ipairs(steps) do
      local ok, advanced = pcall(function() return calendar:AdvanceHours(step / 1000) end)
      if not ok or advanced == false or advanced == nil then
        log("Error: AdvanceHours failed: " .. tostring(advanced))
        session = nil
        return
      end
      broadcast(logic.payload_step(step))
    end
    if finished then
      broadcast(logic.payload_done(session.total))
      local name, total = session.name, session.total
      session = nil
      local ok, err = pcall(function()
        gameServer:SendGlobalChatMessage(logic.advance_message(name, total / 1000))
      end)
      if not ok then
        log("Error: chat message failed: " .. tostring(err))
      end
    end
  end

  local function tick(deltaSeconds)
    if session == nil then
      return
    end
    local ok, err = pcall(run_tick, deltaSeconds)
    if not ok then
      log("Error: " .. tostring(err))
      session = nil
    end
  end

  return handle, tick
end
