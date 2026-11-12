-- GENERATED FILE: do not edit. Built by tools/build_server_resource.py from the
-- upstream strpm-chat-relay 0.4.0 (server/upstream/strpm-chat-relay/main.lua) plus
-- server/sleeptogether/{logic,handler}.lua. Additions: the embedded Sleep Together
-- block (with an onUpdate registration) and a two-line hook in onChatMessage that
-- stops relaying handled sleeptogether.v1 envelopes. Edit those sources, not this output.

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

local HOURS_PREFIX = "STv2|HOURS|"
local UNTIL_PREFIX = "STv2|UNTIL|"
local STEP_PREFIX = "STv2|STEP|"
local DONE_PREFIX = "STv2|DONE|"
local MAX_REQUEST_LENGTH = 32
local MAX_ENVELOPE_LENGTH = 4096
local RATE_LIMIT_MS = 5000
local MAX_MILLI_HOURS = 24000
local EPSILON = 1e-6

-- Decimal digits only (any other byte, NUL included, rejects), non-empty,
-- value <= maxValue. Returns an integer or nil.
local function parse_number(digits, maxValue)
  if #digits == 0 then
    return nil
  end
  local value = 0
  for i = 1, #digits do
    local b = string.byte(digits, i)
    if b < 48 or b > 57 then
      return nil
    end
    value = value * 10 + (b - 48)
    if value > maxValue then
      return nil
    end
  end
  return value
end

-- Mirrors Protocol::ParseRequest. Returns "HOURS", 1..24 or "UNTIL", 0..23; else nil.
function logic.parse_request(text)
  if type(text) ~= "string" or #text > MAX_REQUEST_LENGTH then
    return nil
  end
  if string.sub(text, 1, #HOURS_PREFIX) == HOURS_PREFIX then
    local n = parse_number(string.sub(text, #HOURS_PREFIX + 1), 24)
    if n and n >= 1 then
      return "HOURS", n
    end
  elseif string.sub(text, 1, #UNTIL_PREFIX) == UNTIL_PREFIX then
    local h = parse_number(string.sub(text, #UNTIL_PREFIX + 1), 23)
    if h then
      return "UNTIL", h
    end
  end
  return nil
end

local function round(x)
  return math.floor(x + 0.5)
end

function logic.payload_step(milliHours)
  return STEP_PREFIX .. string.format("%d", round(milliHours))
end

function logic.payload_done(milliHours)
  return DONE_PREFIX .. string.format("%d", round(milliHours))
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

-- True when any |-separated token of the raw message is exactly
-- "channel=<channel>" or that text followed by a NUL byte. Order independent, so a duplicated channel= key cannot
-- hide our channel from us (the client bridge reads the first, the relay the
-- last). Never raises.
function logic.mentions_channel(message, channel)
  if type(message) ~= "string" or type(channel) ~= "string" then
    return false
  end
  local wanted = "channel=" .. channel
  local start = 1
  local len = #message
  while start <= len + 1 do
    local stop = string.find(message, "|", start, true) or (len + 1)
    -- Exactly our token, or our token followed by a NUL: a receiver that compares
    -- the channel as a C string stops at the NUL and sees our channel.
    local n = #wanted
    if stop - start >= n and string.sub(message, start, start + n - 1) == wanted then
      if stop - start == n or string.byte(message, start + n) == 0 then
        return true
      end
    end
    start = stop + 1
  end
  return false
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

local function hex_encode(text)
  return (string.gsub(text, ".", function(c)
    return string.format("%02X", string.byte(c))
  end))
end

-- The chat binding strips angle brackets and the field parser splits on | and =.
local function sanitise(name)
  return (string.gsub(tostring(name or ""), "[|<>=\r\n]", "_"))
end

-- Builds the relayed STRPM v2 envelope the client bridge accepts. The sender
-- connection id must be numeric and nonzero or the bridge drops the message.
function logic.build_envelope(channel, seq, msgid, senderConnectionId, senderPlayerId, senderName, payloadText, tick)
  return "STRPM|v2|msg=" .. tostring(msgid) ..
    "|seq=" .. string.format("%d", seq) ..
    "|channel=" .. channel ..
    "|target=all|flags=0|part=1|parts=1" ..
    "|payload=" .. hex_encode(payloadText) ..
    "|sender=" .. string.format("%d", senderConnectionId) ..
    "|senderPlayerId=" .. string.format("%d", senderPlayerId) ..
    "|senderName=" .. sanitise(senderName) ..
    "|serverTick=" .. string.format("%d", tick)
end

-- Mirrors Core::AdvanceMessage: whole hours, at least 1.
function logic.advance_message(name, hours)
  local n = 1
  if type(hours) == "number" and hours == hours and hours ~= math.huge and hours ~= -math.huge then
    n = math.max(1, round(math.min(math.max(hours, 0), MAX_MILLI_HOURS)))
  end
  return "[Sleep Together] " .. name .. " slept for " .. string.format("%d", n) ..
    (n == 1 and " hour." or " hours.")
end

function logic.deny_message()
  return "[Sleep Together] Only the party leader can advance time."
end

-- lastAdvanceMs may be nil (no advance yet). Busy beats rate limit.
function logic.decide(isLeader, playerCount, nowMs, lastAdvanceMs, busy)
  if not isLeader and playerCount ~= 1 then
    return { kind = "deny", reason = "not_leader" }
  end
  if busy then
    return { kind = "deny", reason = "busy" }
  end
  if lastAdvanceMs ~= nil and nowMs - lastAdvanceMs < RATE_LIMIT_MS then
    return { kind = "deny", reason = "rate_limited" }
  end
  return { kind = "advance" }
end

-- One game hour per real second. State is kept in integer milli-hours plus the
-- accumulated milli-seconds, so no float equality is needed on the totals.
function logic.new_session(totalHours)
  local total = 0
  if type(totalHours) == "number" and totalHours == totalHours and totalHours > 0 and totalHours ~= math.huge then
    total = math.min(round(totalHours * 1000), MAX_MILLI_HOURS)
  end
  return { remaining = total, accumulated = 0.0 }
end

function logic.session_tick(session, deltaSeconds)
  local steps = {}
  if session.remaining <= 0 then
    return steps, true
  end
  if type(deltaSeconds) ~= "number" or deltaSeconds ~= deltaSeconds
      or deltaSeconds <= 0 or deltaSeconds == math.huge then
    return steps, false
  end
  session.accumulated = session.accumulated + deltaSeconds * 1000
  while session.remaining > 0 do
    local step = math.min(1000, session.remaining)
    if session.accumulated + EPSILON < step then
      break
    end
    session.accumulated = session.accumulated - step
    session.remaining = session.remaining - step
    steps[#steps + 1] = step
  end
  if session.remaining <= 0 then
    session.accumulated = 0.0
    return steps, true
  end
  return steps, false
end

return logic

end)()
local SleepTogetherCalendar = (function()
  local ok, calendar = pcall(function() return CalendarService:get() end)
  if ok then return calendar end
  return nil
end)()
local SleepTogetherHandler, SleepTogetherTick = (function()
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
    -- Ours when ANY channel= token names us (the client bridge reads the first
    -- token, the relay's parser keeps the last), or the relay decoded us.
    local mentioned = logic.mentions_channel(message, CHANNEL)
    local relayed = type(fields) == "table" and fields["channel"] == CHANNEL
    if not mentioned and not relayed then
      return false
    end
    local ok, err = pcall(function()
      if not relayed then
        log("dropped forged envelope")
        return
      end
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

end)()(SleepTogetherLogic, gameServer, playerManager, SleepTogetherCalendar)
if SleepTogetherTick then addEventHandler("onUpdate", SleepTogetherTick) end


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
  local sleepOk, sleepHandled = pcall(SleepTogetherHandler, player, fields, message) -- Sleep Together
  if sleepOk and sleepHandled then return end

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
