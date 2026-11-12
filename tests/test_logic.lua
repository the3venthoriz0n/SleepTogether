-- Run from the repo root: lua tests/test_logic.lua  (no output, exit 0 on success)
package.path = "server/sleeptogether/?.lua;" .. package.path
local logic = require("logic")

-- request parsing: twins of the C++ ParseRequest vectors in tests/test_main.cpp
local function expect_req(text, kind, value)
  local k, v = logic.parse_request(text)
  assert(k == kind and v == value, tostring(text))
end
local function reject_req(text)
  assert(logic.parse_request(text) == nil, tostring(text))
end
expect_req("STv2|HOURS|1", "HOURS", 1)
expect_req("STv2|HOURS|24", "HOURS", 24)
expect_req("STv2|HOURS|07", "HOURS", 7)
expect_req("STv2|UNTIL|0", "UNTIL", 0)
expect_req("STv2|UNTIL|23", "UNTIL", 23)
for h = 1, 24 do expect_req("STv2|HOURS|" .. h, "HOURS", h) end
for h = 0, 23 do expect_req("STv2|UNTIL|" .. h, "UNTIL", h) end
for _, bad in ipairs({
  "STv2|HOURS|0", "STv2|HOURS|25", "STv2|UNTIL|24", "STv2|UNTIL|-1", "STv2|HOURS|",
  "STv2|HOURS|8x", "STv2|HOURS|+8", "STv2|HOURS|8 ", "STv1|SLEEP|8", "STv2|SLEEP|8",
  "STv2|hours|8", "", "STv2|HOURS|8\n", " STv2|HOURS|8", "STv2|UNTIL|8|",
  "STv2|HOURS|99999999999999999999", "STv2|HOURS|\xD9\xA8",
}) do
  reject_req(bad)
end
reject_req(string.rep("8", 5000))
reject_req("STv2|HOURS|" .. string.rep("0", 22) .. "8")  -- 34 characters
reject_req("STv2|HOURS|" .. string.rep("0", 21) .. "8")  -- 33 characters
expect_req("STv2|HOURS|" .. string.rep("0", 20) .. "8", "HOURS", 8)  -- 32 characters
reject_req("STv2|HOURS|8\0")
reject_req("STv2|HOURS|\0" .. "8")
reject_req("STv2|UNTIL|8\0")
reject_req(nil)
reject_req(8)

-- payloads
assert(logic.payload_step(1000) == "STv2|STEP|1000")
assert(logic.payload_done(18360) == "STv2|DONE|18360")
assert(logic.payload_step(1000.4) == "STv2|STEP|1000")
assert(logic.payload_step(999.6) == "STv2|STEP|1000")

-- envelopes (decode)
local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end
local function env(channel, payload, part, parts, extra)
  return "STRPM|v2|msg=abc|seq=1|channel=" .. channel .. "|payload=" .. payload ..
    "|flags=0|part=" .. part .. "|parts=" .. parts .. "|target=server" .. (extra or "")
end
local ch, pl = logic.decode_envelope(env("sleeptogether.v1", hex("STv2|HOURS|8"), 1, 1))
assert(ch == "sleeptogether.v1" and pl == "STv2|HOURS|8")
assert(logic.decode_envelope(env("sleeptogether.v1", hex("STv2|HOURS|8"), 1, 2)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", hex("STv2|HOURS|8"), 2, 2)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", "ABC", 1, 1)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", "ZZ", 1, 1)) == nil)
assert(logic.decode_envelope("STRPM|v2|msg=a|seq=1|payload=41|part=1|parts=1") == nil)
assert(logic.decode_envelope("STRPM|v2|msg=a|seq=1|channel=x") == nil)
assert(logic.decode_envelope("STRPM|v2|channel=x|payload=41|part=1") == nil)
assert(logic.decode_envelope("hello") == nil)
assert(logic.decode_envelope("") == nil)
assert(logic.decode_envelope(nil) == nil)
assert(logic.decode_envelope(string.rep("A", 5000)) == nil)
assert(logic.decode_envelope(env("sleeptogether.v1", hex("STv2|HOURS|8"), 1, 1) .. string.rep("x", 5000)) == nil)

local bridge = dofile("tests/bridge_check.lua")
local read_field, bridge_accept = bridge.read_field, bridge.bridge_accept

local built = logic.build_envelope("sleeptogether.v1", 7, "m1", 42, 9, "Alice", "STv2|STEP|1000", 123456)
assert(built == "STRPM|v2|msg=m1|seq=7|channel=sleeptogether.v1|target=all|flags=0|part=1|parts=1|payload="
  .. hex("STv2|STEP|1000") .. "|sender=42|senderPlayerId=9|senderName=Alice|serverTick=123456", built)
local btext, bsender = bridge_accept(built)
assert(btext == "STv2|STEP|1000" and bsender == 42)
local dch, dpl = logic.decode_envelope(built)
assert(dch == "sleeptogether.v1" and dpl == "STv2|STEP|1000")
-- the validator itself must reject bad input (sender 0, odd hex, missing sender)
assert(bridge_accept(logic.build_envelope("sleeptogether.v1", 7, "m1", 0, 9, "Alice", "x", 1)) == nil)
assert(bridge_accept((built:gsub("payload=%x+", "payload=ABC"))) == nil)
assert(bridge_accept((built:gsub("sender=42", "sender="))) == nil)
assert(logic.build_envelope("sleeptogether.v1", 7, "m2", 42, 9, "Alice", "x", 1)
  ~= logic.build_envelope("sleeptogether.v1", 7, "m1", 42, 9, "Alice", "x", 1))
local nasty = logic.build_envelope("sleeptogether.v1", 1, "m", 5, 6, "A|b=c<d>e\r\nf", "x", 1)
assert(string.find(nasty, "|senderName=A_b_c_d_e__f|serverTick=1", 1, true), nasty)
assert(not string.find(nasty, "[\r\n<>]"))
assert(read_field(nasty, "senderName") == "A_b_c_d_e__f")
assert(bridge_accept(nasty) == "x")

-- messages
assert(logic.format_hour == nil)
assert(logic.advance_message("Alice", 8) == "[Sleep Together] Alice slept for 8 hours.")
assert(logic.advance_message("Bob", 1) == "[Sleep Together] Bob slept for 1 hour.")
assert(logic.advance_message("Bob", 0.2) == "[Sleep Together] Bob slept for 1 hour.")
assert(logic.advance_message("Cy", 18.36) == "[Sleep Together] Cy slept for 18 hours.")
assert(logic.deny_message() == "[Sleep Together] Only the party leader can advance time.")

-- decisions: decide(isLeader, playerCount, nowMs, lastAdvanceMs, busy)
assert(logic.decide(true, 3, 10000, 0, false).kind == "advance")
assert(logic.decide(false, 3, 10000, 0, false).reason == "not_leader")
assert(logic.decide(false, 1, 10000, 0, false).kind == "advance")
assert(logic.decide(true, 3, 12000, 10000, false).reason == "rate_limited")
assert(logic.decide(true, 3, 15001, 10000, false).kind == "advance")
assert(logic.decide(true, 3, 20000, 0, true).reason == "busy")
assert(logic.decide(true, 3, 12000, 10000, true).reason == "busy")
assert(logic.decide(true, 3, 100, nil, false).kind == "advance")

-- session pacing (integer milli-hours)
local function same(a, ...)
  local e = { ... }
  assert(#a == #e, #a .. " steps")
  for i = 1, #e do assert(a[i] == e[i] and math.type(a[i]) == "integer", i) end
end
do
  local s = logic.new_session(3)
  local steps, fin = logic.session_tick(s, 0.5)
  same(steps); assert(fin == false)
  steps, fin = logic.session_tick(s, 0.5)
  same(steps, 1000); assert(fin == false)
  steps, fin = logic.session_tick(s, 2.0)
  same(steps, 1000, 1000); assert(fin == true)
  steps, fin = logic.session_tick(s, 5)
  same(steps); assert(fin == true)
end
do
  local s = logic.new_session(0.35)
  local steps, fin = logic.session_tick(s, 0.35)
  same(steps, 350); assert(fin == true)
end
do
  local s = logic.new_session(2)
  local steps, fin = logic.session_tick(s, 10)
  same(steps, 1000, 1000); assert(fin == true)
end
do
  local s = logic.new_session(2)
  for _, d in ipairs({ 0, -1, 0 / 0, math.huge, -math.huge }) do
    local steps, fin = logic.session_tick(s, d)
    same(steps); assert(fin == false)
  end
  same((logic.session_tick(s, 1)), 1000)
end
do -- many small ticks: total preserved, no float drift
  local s = logic.new_session(2.5)
  local sum, n, fin = 0, 0, false
  while not fin and n < 1000 do
    local steps
    steps, fin = logic.session_tick(s, 0.1)
    for _, v in ipairs(steps) do sum = sum + v end
    n = n + 1
  end
  assert(fin and sum == 2500 and n >= 25 and n <= 26, sum .. " " .. n)
end
do
  local s = logic.new_session(18.36)
  local steps, fin = logic.session_tick(s, 100)
  local sum = 0
  for _, v in ipairs(steps) do sum = sum + v end
  assert(fin and sum == 18360 and steps[#steps] == 360 and #steps == 19)
end
do
  local s = logic.new_session(0)
  local steps, fin = logic.session_tick(s, 1)
  same(steps); assert(fin == true)
end

-- mentions_channel
do
  local C = "sleeptogether.v1"
  local m = logic.mentions_channel
  assert(m("STRPM|v2|channel=sleeptogether.v1|x=1", C) == true)
  assert(m("channel=sleeptogether.v1", C) == true)
  assert(m("a=1|b=2|channel=sleeptogether.v1", C) == true)
  assert(m("channel=evil|channel=sleeptogether.v1", C) == true)
  assert(m("channel=sleeptogether.v1|channel=evil", C) == true)
  assert(m("channel=sleeptogether.v1x|a=b", C) == false)
  assert(m("xchannel=sleeptogether.v1", C) == false)
  assert(m("channel=sleeptogether.v", C) == false)
  assert(m("", C) == false)
  assert(m(nil, C) == false and m(42, C) == false and m({}, C) == false)
  assert(m("x", nil) == false)
  assert(m(string.rep("a", 5000), C) == false)
  assert(m(string.rep("a|", 5000), C) == false)
  assert(m(string.rep("a", 5000) .. "|channel=sleeptogether.v1", C) == true)
  assert(m("a\0b|channel=sleeptogether.v1\0|c", C) == true) -- C-string comparison stops at the NUL
  assert(m("channel=sleeptogether.v1\0zz", C) == true)
  assert(m("x=1|channel=sleeptogether.v1\0", C) == true)
  assert(m("channel=sleeptogether.v1x", C) == false)
  assert(m("channel=sleeptogether.v1 ", C) == false)
  assert(m("xchannel=sleeptogether.v1", C) == false)
  assert(m("channel=sleeptogether.v\0", C) == false)
  assert(m("channel=\0sleeptogether.v1", C) == false)
  assert(m("a\0b|channel=sleeptogether.v1|c\0", C) == true)
end
