-- GENERATED FILE: do not edit. Built by tools/build_server_resource.py from the
-- upstream strpm-chat-relay 0.4.0 (server/upstream/strpm-chat-relay/main.lua) plus
-- server/sleeptogether/{logic,handler}.lua. Edit those sources, not this output.

-- STR Plugin Messaging chat relay for unmodified Skyrim Together servers.
--
-- This resource only handles server-side routing. The client bridge injects
-- STRPM envelopes into STR chat and consumes the relayed envelopes.

local PREFIX = "STRPM|v2|"
local IDENTITY_CHANNEL = "strpm.identity.v1"
local MAX_ENVELOPE_LENGTH = 4096
local MAX_CHANNEL_LENGTH = 96
local MAX_PARTS = 64
local FLAG_ALLOW_LOOPBACK = 4

local gameServer = GameServer:get()
local playerManager = PlayerManager:get()

-- Sleep Together (embedded; sources: server/sleeptogether/logic.lua, handler.lua)
local SleepTogetherLogic = (function()
-- Pure logic for the Sleep Together server resource. No game globals are used,
-- so tests/test_logic.lua can run it under a stock Lua interpreter.
-- Rules and strings mirror src/Core.cpp and src/Protocol.cpp exactly.

local logic = {}

local SLEEP_PREFIX = "STv1|SLEEP|"
local MAX_REQUEST_LENGTH = 32
local MAX_ENVELOPE_LENGTH = 4096
local RATE_LIMIT_MS = 5000

-- Mirrors Protocol::ParseSleepRequest. Leading zeros are accepted (within the
-- length cap); anything else that is not a plain ASCII number 0..23 is nil.
function logic.parse_request(text)
  if type(text) ~= "string" or #text > MAX_REQUEST_LENGTH then
    return nil
  end
  if string.sub(text, 1, #SLEEP_PREFIX) ~= SLEEP_PREFIX then
    return nil
  end
  local digits = string.sub(text, #SLEEP_PREFIX + 1)
  if #digits == 0 then
    return nil
  end
  local hour = 0
  for i = 1, #digits do
    local b = string.byte(digits, i)
    if b < 48 or b > 57 then
      return nil
    end
    hour = hour * 10 + (b - 48)
    if hour > 23 then
      return nil
    end
  end
  return hour
end

local function split_fields(envelope)
  local fields = {}
  for token in string.gmatch(envelope, "([^|]+)") do
    local sep = string.find(token, "=", 1, true)
    if sep then
      fields[string.sub(token, 1, sep - 1)] = string.sub(token, sep + 1)
    end
  end
  return fields
end

-- Returns channel, decoded payload; or nil for anything malformed or multi-part.
function logic.decode_envelope(message)
  if type(message) ~= "string" or #message > MAX_ENVELOPE_LENGTH then
    return nil
  end
  if string.sub(message, 1, 9) ~= "STRPM|v2|" then
    return nil
  end
  local fields = split_fields(message)
  local channel, payload = fields["channel"], fields["payload"]
  if channel == nil or channel == "" or payload == nil then
    return nil
  end
  if fields["part"] ~= "1" or fields["parts"] ~= "1" then
    return nil
  end
  if #payload % 2 ~= 0 or string.find(payload, "[^0-9A-Fa-f]") then
    return nil
  end
  local decoded = string.gsub(payload, "%x%x", function(h)
    return string.char(tonumber(h, 16))
  end)
  return channel, decoded
end

function logic.format_hour(hour)
  if hour < 0 then hour = 0 elseif hour > 23 then hour = 23 end
  return string.format("%02d:00", hour)
end

function logic.advance_message(leaderName, hour)
  return "[Sleep Together] " .. leaderName .. " slept. It is now " .. logic.format_hour(hour) .. "."
end

function logic.deny_message()
  return "[Sleep Together] Only the party leader can advance time."
end

-- lastAdvanceMs may be nil (no advance yet).
function logic.decide(isLeader, playerCount, hour, nowMs, lastAdvanceMs)
  if hour == nil then
    return { kind = "deny", reason = "bad_request" }
  end
  if not isLeader and playerCount ~= 1 then
    return { kind = "deny", reason = "not_leader" }
  end
  if lastAdvanceMs ~= nil and nowMs - lastAdvanceMs < RATE_LIMIT_MS then
    return { kind = "deny", reason = "rate_limited" }
  end
  return { kind = "advance", hour = hour }
end

return logic

end)()
local SleepTogetherHandler = (function()
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
    -- Count with ipairs exactly like the relay does; `#` on the sol2 container is unproven.
    local playerCount = 0
    for _ in ipairs(playerManager:GetAllPlayers()) do
      playerCount = playerCount + 1
    end
    local decision = logic.decide(
      player:IsPartyLeader(), playerCount, hour, now, lastAdvanceMs)

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

end)()(SleepTogetherLogic, gameServer, playerManager)


local function startsWith(value, prefix)
  return string.sub(value, 1, string.len(prefix)) == prefix
end

local function getPlayerByCharacter(entityId)
  local allPlayers = playerManager:GetAllPlayers()
  for _, player in ipairs(allPlayers) do
    if player:GetCharacter() == entityId then
      return player
    end
  end
  return nil
end

local function splitFields(envelope)
  local fields = {}
  for token in string.gmatch(envelope, "([^|]+)") do
    local separator = string.find(token, "=", 1, true)
    if separator then
      local key = string.sub(token, 1, separator - 1)
      local value = string.sub(token, separator + 1)
      fields[key] = value
    end
  end
  return fields
end

local function validUnsigned(value)
  return value ~= nil and string.match(value, "^%d+$") ~= nil
end

local function validChannel(value)
  return value ~= nil
    and string.len(value) > 0
    and string.len(value) <= MAX_CHANNEL_LENGTH
    and string.match(value, "^[A-Za-z0-9._%-]+$") ~= nil
end

local function safeField(value)
  local result = tostring(value or "")
  result = string.gsub(result, "[|\r\n]", "_")
  return result
end

local function flagIsSet(flags, flag)
  return math.floor(flags / flag) % 2 == 1
end

local function hexEncodeAscii(value)
  return (string.gsub(value, ".", function(character)
    return string.format("%02X", string.byte(character))
  end))
end

local function replacePayload(envelope, payloadHex)
  local replaced, count = string.gsub(
    envelope,
    "(|payload=)[0-9A-Fa-f]*",
    "%1" .. payloadHex,
    1)
  if count == 1 then
    return replaced
  end
  return envelope
end

local function validateEnvelope(fields)
  if fields["msg"] == nil or not validUnsigned(fields["seq"]) then
    return false, "missing msg/seq"
  end
  if not validChannel(fields["channel"]) then
    return false, "invalid channel"
  end
  if fields["payload"] == nil or string.match(fields["payload"], "^[0-9A-Fa-f]*$") == nil then
    return false, "invalid payload"
  end
  if not validUnsigned(fields["flags"]) then
    return false, "invalid flags"
  end
  if not validUnsigned(fields["part"]) or not validUnsigned(fields["parts"]) then
    return false, "invalid fragment metadata"
  end

  local part = tonumber(fields["part"])
  local parts = tonumber(fields["parts"])
  if part == nil or parts == nil or parts < 1 or parts > MAX_PARTS or part < 1 or part > parts then
    return false, "fragment out of range"
  end

  local target = fields["target"] or "all"
  if target ~= "all" and target ~= "server" and string.match(target, "^id:%d+$") == nil then
    return false, "invalid target"
  end

  return true, nil
end

local function relayToTarget(target, envelope, senderConnectionId, flags)
  local allowLoopback = flagIsSet(flags, FLAG_ALLOW_LOOPBACK)

  if target == nil or target == "" or target == "all" then
    local allPlayers = playerManager:GetAllPlayers()
    for _, player in ipairs(allPlayers) do
      local connectionId = player:GetConnectionId()
      if allowLoopback or connectionId ~= senderConnectionId then
        gameServer:SendChatMessage(connectionId, envelope)
      end
    end
    return true
  end

  local id = string.match(target, "^id:(%d+)$")
  if id ~= nil then
    local connectionId = tonumber(id)
    if allowLoopback or connectionId ~= senderConnectionId then
      gameServer:SendChatMessage(connectionId, envelope)
    end
    return true
  end

  if target == "server" then
    return true
  end

  return false
end

addEventHandler("onChatMessage", function(entityId, message)
  if type(message) ~= "string" or not startsWith(message, PREFIX) then
    return
  end

  cancelEvent("STRPM transport envelope")

  if string.len(message) > MAX_ENVELOPE_LENGTH then
    print("[STRPM] Dropped oversized envelope")
    return
  end

  local player = getPlayerByCharacter(entityId)
  if player == nil then
    print("[STRPM] Dropped envelope from unknown character " .. tostring(entityId))
    return
  end

  local fields = splitFields(message)
  local valid, reason = validateEnvelope(fields)
  if not valid then
    print("[STRPM] Dropped malformed envelope: " .. tostring(reason))
    return
  end

  local senderConnectionId = player:GetConnectionId()
  local senderPlayerId = player:GetId()
  local flags = tonumber(fields["flags"]) or 0
  pcall(SleepTogetherHandler, player, fields, message) -- Sleep Together

  -- Identity heartbeats originate with an empty payload. Replace that payload
  -- server-side with the authenticated STR PlayerId before relaying it. Peers
  -- can then consume ConnectionID + PlayerId through the normal deferred STRPM
  -- receive pipeline instead of depending on VEH observer ordering.
  if fields["channel"] == IDENTITY_CHANNEL then
    message = replacePayload(message, hexEncodeAscii(tostring(senderPlayerId)))
  end

  local relayEnvelope =
    message ..
    "|sender=" .. tostring(senderConnectionId) ..
    "|senderPlayerId=" .. tostring(senderPlayerId) ..
    "|senderName=" .. safeField(player:GetUsername()) ..
    "|serverTick=" .. tostring(gameServer:GetTick())

  if not relayToTarget(fields["target"], relayEnvelope, senderConnectionId, flags) then
    print("[STRPM] Dropped envelope with unsupported target")
  end
end)

print("[STRPM] Chat relay v4 loaded (authenticated identity payload enabled)")
