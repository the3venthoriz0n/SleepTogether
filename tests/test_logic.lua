-- Run from the repo root: lua tests/test_logic.lua  (no output, exit 0 on success)
package.path = "server/sleeptogether/?.lua;" .. package.path
local logic = require("logic")

local P = "STv1|SLEEP|"
assert(logic.parse_request(P .. "8") == 8)
assert(logic.parse_request(P .. "0") == 0)
assert(logic.parse_request(P .. "23") == 23)
assert(logic.parse_request(P .. "08") == 8)
for h = 0, 23 do
  assert(logic.parse_request(P .. tostring(h)) == h)
end
for _, bad in ipairs({
  "STv1|SLEEP|24", "STv1|SLEEP|-1", "STv1|SLEEP|", "STv1|SLEEP|8x",
  "STv2|SLEEP|8", "", "STv1|SLEEP|08 ", "hello", "STv1|SLEEP|+8",
  " STv1|SLEEP|8", "STv1|SLEEP|8\n", "STv1|SLEEP|8|", "stv1|SLEEP|8",
  "STv1|SLEEP|99999999999999999999", "STv1|SLEEP|\xD9\xA8",
  "STv1|SLEEP|8\0", "STv1|SLEEP|\0" .. "8",
  string.rep("8", 5000),
  P .. string.rep("0", 21) .. "8",
  P .. string.rep("0", 22),
}) do
  assert(logic.parse_request(bad) == nil, bad)
end
assert(logic.parse_request(P .. string.rep("0", 20) .. "8") == 8)
assert(logic.parse_request(nil) == nil)
assert(logic.parse_request(8) == nil)

-- envelopes
local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end
local function env(channel, payload, part, parts, extra)
  return "STRPM|v2|msg=abc|seq=1|channel=" .. channel .. "|payload=" .. payload ..
    "|flags=0|part=" .. part .. "|parts=" .. parts .. "|target=server" .. (extra or "")
end
local ch, pl = logic.decode_envelope(env("sleeptogether.v1", hex("STv1|SLEEP|8"), 1, 1))
assert(ch == "sleeptogether.v1" and pl == "STv1|SLEEP|8")
assert(logic.decode_envelope(env("sleeptogether.v1", hex("STv1|SLEEP|8"), 1, 2)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", hex("STv1|SLEEP|8"), 2, 2)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", "ABC", 1, 1)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", "ZZ", 1, 1)) == nil)
assert(logic.decode_envelope("STRPM|v2|msg=a|seq=1|payload=41|part=1|parts=1") == nil)
assert(logic.decode_envelope("STRPM|v2|msg=a|seq=1|channel=x") == nil)
assert(logic.decode_envelope("STRPM|v2|channel=x|payload=41|part=1") == nil)
assert(logic.decode_envelope("hello") == nil)
assert(logic.decode_envelope("") == nil)
assert(logic.decode_envelope(nil) == nil)
assert(logic.decode_envelope(string.rep("A", 5000)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", hex("STv1|SLEEP|8"), 1, 1) .. string.rep("x", 5000)) == nil)

-- messages
assert(logic.format_hour(8) == "08:00")
assert(logic.format_hour(0) == "00:00")
assert(logic.format_hour(23) == "23:00")
assert(logic.advance_message("Alice", 8) == "[Sleep Together] Alice slept. It is now 08:00.")
assert(logic.deny_message() == "[Sleep Together] Only the party leader can advance time.")

-- decisions
assert(logic.decide(true, 3, 8, 10000, 0).kind == "advance")
assert(logic.decide(true, 3, 8, 10000, 0).hour == 8)
assert(logic.decide(false, 3, 8, 10000, 0).reason == "not_leader")
assert(logic.decide(false, 1, 8, 10000, 0).kind == "advance")
assert(logic.decide(true, 3, nil, 10000, 0).reason == "bad_request")
assert(logic.decide(true, 3, 8, 12000, 10000).reason == "rate_limited")
assert(logic.decide(true, 3, 8, 15001, 10000).kind == "advance")
assert(logic.decide(true, 3, 8, 100, nil).kind == "advance")
