-- Pure logic for the Sleep Together server resource. No game globals are used,
-- so tests/test_logic.lua can run it under a stock Lua interpreter.
-- Rules and strings mirror src/Core.cpp and src/Protocol.cpp exactly.

local logic = {}

local HOURS_PREFIX = "STv2|HOURS|"
local UNTIL_PREFIX = "STv2|UNTIL|"
local WAIT_PREFIX = "STv2|WAIT|"
local WAKE_TEXT = "STv2|WAKE"
local STOP_PREFIX = "STv2|STOP|"
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

-- Mirrors Protocol::ParseRequest. Returns "HOURS", 1..24; "UNTIL", 0..23; "WAIT", 1..24; or "WAKE", 0; else nil.
function logic.parse_request(text)
  if type(text) ~= "string" or #text > MAX_REQUEST_LENGTH then
    return nil
  end
  if text == WAKE_TEXT then
    return "WAKE", 0
  end
  if string.sub(text, 1, #WAIT_PREFIX) == WAIT_PREFIX then
    local n = parse_number(string.sub(text, #WAIT_PREFIX + 1), 24)
    if n and n >= 1 then
      return "WAIT", n
    end
  elseif string.sub(text, 1, #HOURS_PREFIX) == HOURS_PREFIX then
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

function logic.payload_stop(milliHours)
  return STOP_PREFIX .. string.format("%d", round(milliHours))
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

-- Mirrors Core::WaitMessage: whole hours, at least 1.
function logic.wait_message(name, hours)
  local n = 1
  if type(hours) == "number" and hours == hours and hours ~= math.huge and hours ~= -math.huge then
    n = math.max(1, round(math.min(math.max(hours, 0), MAX_MILLI_HOURS)))
  end
  return "[Sleep Together] " .. name .. " waited for " .. string.format("%d", n) ..
    (n == 1 and " hour." or " hours.")
end

-- Mirrors Core::WakeMessage. Claims no hours: only that the player woke up.
function logic.wake_message(name)
  return "[Sleep Together] " .. name .. " woke up early."
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

-- Milli-hours advanced so far by a handler session { state, total, ... } (integers). 0 for anything malformed.
function logic.session_elapsed(session)
  if type(session) ~= "table" or type(session.state) ~= "table" then
    return 0
  end
  local total, remaining = session.total, session.state.remaining
  if math.type(total) ~= "integer" or math.type(remaining) ~= "integer" then
    return 0
  end
  return math.max(0, math.min(total - remaining, MAX_MILLI_HOURS))
end

return logic
