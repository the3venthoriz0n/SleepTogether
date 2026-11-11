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
