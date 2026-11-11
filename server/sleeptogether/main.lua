-- Sleep Together server resource (Skyrim Together Reborn).
--
-- The client sends "STv1|SLEEP|<hour>" through the STRPM chat relay on channel
-- "sleeptogether.v1" with target "server". We validate the sender (party
-- leader, or the only connected player) and set the server time.
--
-- LOAD ORDER CAVEAT: onChatMessage handlers run in registration order and the
-- first one that calls cancelEvent stops the rest. The strpm-chat-relay
-- resource cancels every "STRPM|v2|" message, so THIS resource must load
-- BEFORE the relay. We never call cancelEvent ourselves (the relay does).
-- If our log line never appears, see the fallback in the task brief.

local CHANNEL = "sleeptogether.v1"
local DEFAULT_TIME_SCALE = 20 -- STR default TimeModel.TimeScale

-- logic.lua lives next to this file. The server sets package.path to "./?.lua"
-- (relative to the server working directory), so plain require cannot find it;
-- try the likely resource folder locations explicitly.
local function loadLogic()
  local candidates = {
    "resources/sleeptogether/logic.lua",
    "./resources/sleeptogether/logic.lua",
    "Data/resources/sleeptogether/logic.lua",
    "sleeptogether/logic.lua",
    "logic.lua",
  }
  for _, path in ipairs(candidates) do
    local chunk = loadfile(path)
    if chunk then
      return chunk()
    end
  end
  return nil
end

local logic = loadLogic()
if logic == nil then
  print("[SleepTogether] ERROR: could not find logic.lua; resource disabled")
  return
end

local gameServer = GameServer:get()
local playerManager = PlayerManager:get()
local lastAdvanceMs = nil

local function getPlayerByCharacter(entityId)
  for _, player in ipairs(playerManager:GetAllPlayers()) do
    if player:GetCharacter() == entityId then
      return player
    end
  end
  return nil
end

-- Verified in TiltedEvolution source: GameServer:GetTick() is milliseconds
-- (PartyService uses GetTick() + 10000 as "10 seconds" and + 60000 as "60
-- seconds"; CalendarService feeds tick deltas to DateTime::Update). The rate
-- limiter in logic.decide therefore takes it directly as ms.
local function nowMs()
  return gameServer:GetTick()
end

local function timeScale()
  -- CalendarService:GetTimeScale binding is unverified when called with self.
  local ok, value = pcall(function() return CalendarService:get():GetTimeScale() end)
  if ok and type(value) == "number" then
    return value
  end
  return DEFAULT_TIME_SCALE
end

local function handle(entityId, message)
  local channel, payload = logic.decode_envelope(message)
  if channel ~= CHANNEL then
    return
  end

  local player = getPlayerByCharacter(entityId)
  if player == nil then
    print("[SleepTogether] Request from unknown character " .. tostring(entityId))
    return
  end

  local hour = logic.parse_request(payload)
  local now = nowMs()
  local decision = logic.decide(
    player:IsPartyLeader(), #playerManager:GetAllPlayers(), hour, now, lastAdvanceMs)
  local name = tostring(player:GetUsername())

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

addEventHandler("onChatMessage", function(entityId, message)
  local ok, err = pcall(handle, entityId, message)
  if not ok then
    print("[SleepTogether] Error: " .. tostring(err))
  end
end)

print("[SleepTogether] Resource loaded")
