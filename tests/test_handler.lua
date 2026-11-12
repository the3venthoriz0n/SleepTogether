-- Run from the repo root: lua tests/test_handler.lua  (no output, exit 0 on success)
package.path = "server/sleeptogether/?.lua;" .. package.path
local printed = {}
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
local function logged(needle)
  for _, l in ipairs(printed) do
    if l:find(needle, 1, true) then return true end
  end
  return false
end
local function error_logged() return logged("[SleepTogether] Error") end
local function reset_log() printed = {} end

local logic = dofile("server/sleeptogether/logic.lua")
local make_handler = dofile("server/sleeptogether/handler.lua")
local bridge = dofile("tests/bridge_check.lua")

local CHANNEL = "sleeptogether.v1"

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02X", c:byte()) end))
end
local function env(channel, payload)
  return "STRPM|v2|msg=a|seq=1|channel=" .. channel .. "|payload=" .. hex(payload) ..
    "|flags=0|part=1|parts=1|target=server"
end
local function fields_of(message)
  local f = {}
  for token in message:gmatch("([^|]+)") do
    local s = token:find("=", 1, true)
    if s then f[token:sub(1, s - 1)] = token:sub(s + 1) end
  end
  return f
end

-- opts: leader (sender is leader), count (players online), conn_error (index of a
-- player whose GetConnectionId raises), advance ("false" | "error" | nil),
-- until_value / until_error
local function setup(opts)
  opts = opts or {}
  local calls = { Advance = {}, Until = {}, Global = {}, Chat = {} }
  local tick = 10000
  local gs = {
    GetTick = function() return tick end,
    SendGlobalChatMessage = function(_, t) calls.Global[#calls.Global + 1] = t end,
    SendChatMessage = function(_, id, t) calls.Chat[#calls.Chat + 1] = { id, t } end,
  }
  local names = { "Alice", "Bob", "Cy", "Dee" }
  local players = {}
  for i = 1, opts.count or 3 do
    players[i] = {
      GetConnectionId = function()
        if opts.conn_error == i then error("conn boom") end
        return 77 + i - 1
      end,
      GetId = function() return 5 + i - 1 end,
      GetUsername = function() return names[i] end,
      IsPartyLeader = function() return i == 1 end,
    }
  end
  local sender = players[1]
  if not opts.leader then
    sender = players[opts.count == 1 and 1 or 2]
    if opts.count == 1 then
      sender.IsPartyLeader = function() return false end
    end
  end
  local pm = { GetAllPlayers = function() return players end }
  local calendar
  calendar = {
    AdvanceHours = function(self, h)
      assert(self == calendar, "AdvanceHours must be called with ':'")
      calls.Advance[#calls.Advance + 1] = h
      if opts.advance == "error" then error("advance boom") end
      return opts.advance ~= "false"
    end,
    HoursUntil = function(self, h)
      assert(self == calendar, "HoursUntil must be called with ':'")
      calls.Until[#calls.Until + 1] = h
      if opts.until_error then error("until boom") end
      if opts.until_value ~= nil then return opts.until_value end
      return 18.36
    end,
  }
  local handle, step = make_handler(logic, gs, pm, calendar)
  assert(type(handle) == "function" and type(step) == "function")
  local function send(channel, payload, who)
    local m = env(channel, payload)
    reset_log()
    return pcall(handle, who or sender, fields_of(m), m)
  end
  local function ticks(n, dt)
    for _ = 1, n do
      local ok = pcall(step, dt)
      assert(ok, "tick must not raise")
    end
  end
  return {
    calls = calls, send = send, handle = handle, step = step, ticks = ticks,
    set_tick = function(t) tick = t end, players = players, pm = pm, gs = gs,
    set_players = function(list) players = list; pm.GetAllPlayers = function() return list end end,
  }
end

local function sent_true(ok, handled) return ok and handled == true end

-- Collect the payloads delivered to each connection, verifying bridge rules.
local function delivered(calls, from_index)
  local per = {}
  local seen_msgs, seen_seq = {}, {}
  for i = from_index or 1, #calls.Chat do
    local conn, text = calls.Chat[i][1], calls.Chat[i][2]
    local payload, sender = bridge.bridge_accept(text)
    assert(payload, "bridge must accept: " .. text)
    assert(sender == 77, "sender must be the leader connection id")
    local msg = bridge.read_field(text, "msg")
    assert(not seen_msgs[msg .. "@" .. conn], "msg unique per message")
    seen_msgs[msg .. "@" .. conn] = true
    per[conn] = per[conn] or {}
    per[conn][#per[conn] + 1] = payload
    seen_seq[#seen_seq + 1] = bridge.read_field(text, "seq")
  end
  return per
end

-- leader HOURS 3
do
  local t = setup({ leader = true })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|3")))
  assert(#t.calls.Advance == 0, "no advance at request time")
  assert(#t.calls.Chat == 0 and #t.calls.Global == 0)
  assert(logged("[SleepTogether] Alice sleeps for 3 h"), "start log line")
  t.ticks(1, 1.0)
  assert(#t.calls.Advance == 1 and t.calls.Advance[1] == 1.0)
  assert(#t.calls.Chat == 3)
  t.ticks(1, 1.0)
  assert(#t.calls.Advance == 2 and #t.calls.Chat == 6 and #t.calls.Global == 0, "no DONE before the last step")
  t.ticks(1, 1.0)
  assert(#t.calls.Advance == 3)
  for _, h in ipairs(t.calls.Advance) do assert(h == 1.0) end
  -- the last step is followed by DONE and the global chat in the same tick
  assert(#t.calls.Global == 1 and t.calls.Global[1] == "[Sleep Together] Alice slept for 3 hours.")
  local per = delivered(t.calls)
  for _, conn in ipairs({ 77, 78, 79 }) do
    assert(per[conn] and #per[conn] == 4, "conn " .. conn)
    for i = 1, 3 do assert(per[conn][i] == "STv2|STEP|1000") end
    assert(per[conn][4] == "STv2|DONE|3000", conn)
  end
  -- finished: more ticks do nothing
  local n = #t.calls.Chat
  t.ticks(3, 1.0)
  assert(#t.calls.Chat == n and #t.calls.Advance == 3 and #t.calls.Global == 1)
  assert(not error_logged())
end

-- DONE can arrive in the same tick as the last step, and msg ids are unique
do
  local t = setup({ leader = true, count = 2 })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|2")))
  t.ticks(1, 5.0)
  assert(#t.calls.Advance == 2 and #t.calls.Global == 1)
  assert(#t.calls.Chat == 6)
  -- one envelope per message, sent to every player: the msg id is unique per
  -- message (what the bridge keys on, with the sender) and per recipient
  local perConn, distinct = {}, {}
  for _, c in ipairs(t.calls.Chat) do
    local m = bridge.read_field(c[2], "msg")
    perConn[c[1]] = perConn[c[1]] or {}
    assert(not perConn[c[1]][m], "duplicate msg " .. m .. " for conn " .. c[1])
    perConn[c[1]][m] = true
    distinct[m] = true
  end
  local n = 0
  for _ in pairs(distinct) do n = n + 1 end
  assert(n == 3, "STEP, STEP and DONE use three distinct msg ids")
  delivered(t.calls)
end

-- UNTIL 8 with 18.36 hours to go
do
  local t = setup({ leader = true, until_value = 18.36 })
  assert(sent_true(t.send(CHANNEL, "STv2|UNTIL|8")))
  assert(#t.calls.Until == 1 and t.calls.Until[1] == 8)
  t.ticks(18, 1.0)
  assert(#t.calls.Advance == 18 and #t.calls.Global == 0)
  t.ticks(1, 0.36)
  assert(#t.calls.Advance == 19 and t.calls.Advance[19] == 0.36)
  assert(#t.calls.Global == 1 and t.calls.Global[1] == "[Sleep Together] Alice slept for 18 hours.")
  local per = delivered(t.calls)
  assert(per[77][19] == "STv2|STEP|360" and per[77][20] == "STv2|DONE|18360" and #per[77] == 20)
  assert(per[77][1] == "STv2|STEP|1000")
end

-- non-leader with two players is denied
do
  local t = setup({ leader = false, count = 2 })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|3")))
  assert(#t.calls.Chat == 1 and t.calls.Chat[1][1] == 78)
  assert(t.calls.Chat[1][2] == "[Sleep Together] Only the party leader can advance time.")
  t.ticks(3, 1.0)
  assert(#t.calls.Advance == 0 and #t.calls.Until == 0 and #t.calls.Global == 0 and #t.calls.Chat == 1)
end

-- solo non-leader is allowed
do
  local t = setup({ leader = false, count = 1 })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|2")))
  t.ticks(2, 1.0)
  assert(#t.calls.Advance == 2 and #t.calls.Global == 1)
  assert(not error_logged())
end

-- a second request during a session is ignored (busy), but handled
do
  local t = setup({ leader = true })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|3")))
  t.ticks(1, 1.0)
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|10")))
  assert(logged("busy"))
  assert(#t.calls.Chat == 3, "no extra output")
  t.ticks(2, 1.0)
  assert(#t.calls.Advance == 3 and #t.calls.Global == 1, "still one session of 3 hours")
  t.ticks(1, 1.0)
  assert(#t.calls.Advance == 3)
end

-- a non-leader asking during a session still gets the deny message, not busy
do
  local t = setup({ leader = true })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|3")))
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|3", t.players[2])))
  assert(#t.calls.Chat == 1 and t.calls.Chat[1][1] == 78)
end

-- rate limit after the session ended
do
  local t = setup({ leader = true })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|1")))
  t.ticks(2, 1.0)
  assert(#t.calls.Global == 1)
  t.set_tick(12000)
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|1")))
  assert(logged("rate"))
  t.ticks(3, 1.0)
  assert(#t.calls.Advance == 1 and #t.calls.Global == 1)
  t.set_tick(15001)
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|1")))
  t.ticks(2, 1.0)
  assert(#t.calls.Advance == 2 and #t.calls.Global == 2)
end

-- forged STEP/DONE and other payloads from a client are ignored but handled
do
  local t = setup({ leader = true })
  for _, p in ipairs({ "STv2|STEP|1000", "STv2|DONE|1000", "STv1|SLEEP|8", "hello" }) do
    assert(sent_true(t.send(CHANNEL, p)), p)
    assert(not error_logged())
  end
  t.ticks(3, 1.0)
  assert(#t.calls.Advance == 0 and #t.calls.Until == 0 and #t.calls.Chat == 0 and #t.calls.Global == 0)
  -- and they do not take the rate limit slot
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|1")))
  t.ticks(1, 1.0)
  assert(#t.calls.Advance == 1)
end

-- wrong channel: not handled, nothing done
do
  local t = setup({ leader = true })
  local ok, handled = t.send("other.channel", "STv2|HOURS|3")
  assert(ok and handled == false)
  t.ticks(3, 1.0)
  assert(#t.calls.Advance == 0 and #t.calls.Chat == 0 and #t.calls.Global == 0)
  -- unparseable input for a foreign channel and bad arguments must not raise
  local h = t.handle
  for _, args in ipairs({ { nil, nil, nil }, { {}, {}, "STRPM|v2|" }, { {}, "x", 1 } }) do
    local ok2, r = pcall(h, args[1], args[2], args[3])
    assert(ok2 and r == false)
  end
end

-- our channel but undecodable message still returns true
do
  local t = setup({ leader = true })
  local p = { channel = CHANNEL }
  for _, m in ipairs({ "garbage", "STRPM|v2|channel=" .. CHANNEL .. "|payload=ABC|part=1|parts=1" }) do
    reset_log()
    local ok, handled = pcall(t.handle, t.players[1], p, m)
    assert(ok and handled == true)
  end
  assert(#t.calls.Advance == 0 and #t.calls.Chat == 0)
end

-- malformed payloads
do
  local t = setup({ leader = true })
  for _, payload in ipairs({
    "garbage", "STv2|HOURS|0", "STv2|HOURS|25", "STv2|UNTIL|24", "", "STv2|HOURS|8\0",
    string.rep("A", 5000),
  }) do
    assert(sent_true(t.send(CHANNEL, payload)))
    assert(not error_logged(), "no Error line for malformed payloads")
  end
  -- odd-length hex and NUL byte inside the raw message
  for _, m in ipairs({
    "STRPM|v2|msg=a|seq=1|channel=" .. CHANNEL .. "|payload=ABC|flags=0|part=1|parts=1|target=server",
    "STRPM|v2|msg=a|seq=1|channel=" .. CHANNEL .. "|payload=\0|flags=0|part=1|parts=1|target=server",
    "STRPM|v2|msg=a|seq=1|channel=" .. CHANNEL .. "|payload=" .. string.rep("41", 2500) ..
      "|flags=0|part=1|parts=1|target=server",
  }) do
    reset_log()
    local ok, handled = pcall(t.handle, t.players[1], fields_of(m), m)
    assert(ok and handled == true)
    assert(not error_logged())
  end
  t.ticks(3, 1.0)
  assert(#t.calls.Advance == 0 and #t.calls.Until == 0 and #t.calls.Chat == 0 and #t.calls.Global == 0)
end

-- AdvanceHours failure ends the session without DONE
for _, mode in ipairs({ "false", "error" }) do
  local t = setup({ leader = true, advance = mode })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|3")))
  reset_log()
  t.ticks(1, 1.0)
  assert(error_logged(), mode)
  assert(#t.calls.Advance == 1 and #t.calls.Chat == 0 and #t.calls.Global == 0)
  t.ticks(3, 1.0)
  assert(#t.calls.Advance == 1 and #t.calls.Chat == 0 and #t.calls.Global == 0, "session ended")
  -- the session is over, so a request after the rate limit starts a new one
  t.set_tick(20000)
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|1")))
  assert(not logged("busy"))
end

-- HoursUntil raising, -1, 0, nil, non-number or > 24 starts nothing
for _, case in ipairs({
  { until_error = true }, { until_value = -1 }, { until_value = 0 },
  { until_value = "x" }, { until_value = 25 },
}) do
  case.leader = true
  local t = setup(case)
  assert(sent_true(t.send(CHANNEL, "STv2|UNTIL|8")))
  assert(logged("[SleepTogether]"), "logged")
  t.ticks(3, 1.0)
  assert(#t.calls.Advance == 0 and #t.calls.Chat == 0 and #t.calls.Global == 0)
  -- no rate-limit slot was taken: an immediate valid request works
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|1")))
  t.ticks(1, 1.0)
  assert(#t.calls.Advance == 1)
end

-- a player whose GetConnectionId raises does not stop the others
do
  local t = setup({ leader = true, conn_error = 2 })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|2")))
  t.ticks(1, 1.0)
  assert(#t.calls.Chat == 2, "players 1 and 3 receive the step")
  assert(t.calls.Chat[1][1] == 77 and t.calls.Chat[2][1] == 79)
  t.ticks(1, 1.0)
  assert(#t.calls.Global == 1)
  assert(#t.calls.Chat == 6)
end

-- tick(0), tick(-1), tick with no session do nothing
do
  local t = setup({ leader = true })
  t.ticks(2, 1.0)
  assert(#t.calls.Advance == 0 and #t.calls.Chat == 0)
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|2")))
  t.ticks(1, 0)
  t.ticks(1, -1)
  assert(pcall(t.step))
  assert(pcall(t.step, nil))
  assert(pcall(t.step, "x"))
  assert(#t.calls.Advance == 0 and #t.calls.Chat == 0 and #t.calls.Global == 0)
  t.ticks(2, 1.0)
  assert(#t.calls.Advance == 2 and #t.calls.Global == 1)
end

-- the session continues after the leader leaves
do
  local t = setup({ leader = true })
  assert(sent_true(t.send(CHANNEL, "STv2|HOURS|3")))
  t.ticks(1, 1.0)
  t.set_players({ t.players[2], t.players[3] })
  t.ticks(2, 1.0)
  assert(#t.calls.Advance == 3 and #t.calls.Global == 1)
  assert(t.calls.Global[1] == "[Sleep Together] Alice slept for 3 hours.")
  local last = t.calls.Chat[#t.calls.Chat]
  assert(bridge.bridge_accept(last[2]) == "STv2|DONE|3000")
  local _, sender = bridge.bridge_accept(last[2])
  assert(sender == 77)
end

-- other faults never escape handle
do
  local t = setup({ leader = true })
  local ok, handled = pcall(t.handle, nil, { channel = CHANNEL }, env(CHANNEL, "STv2|HOURS|2"))
  assert(ok and handled == true and error_logged())
  local broken = { IsPartyLeader = function() error("leader boom") end,
    GetUsername = function() return "X" end, GetConnectionId = function() return 1 end,
    GetId = function() return 1 end }
  reset_log()
  ok, handled = pcall(t.handle, broken, { channel = CHANNEL }, env(CHANNEL, "STv2|HOURS|2"))
  assert(ok and handled == true)
  assert(#t.calls.Advance == 0)
  t.ticks(2, 1.0)
  assert(#t.calls.Advance == 0, "failed leader check starts nothing")
end

-- build
local py = os.getenv("PYTHON") or "python"
local OUT = "package/Server/strpm-chat-relay/main.lua"
local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("a"); f:close()
  return (s:gsub("\r\n", "\n"))
end
assert(os.execute(py .. " -I tools/build_server_resource.py >nul"), "build script failed")
assert(loadfile(OUT))
local text = slurp(OUT)
-- reproducible
assert(os.execute(py .. " -I tools/build_server_resource.py >nul"), "second build failed")
assert(slurp(OUT) == text, "build output must be byte-reproducible")

local a = assert(text:find("local playerManager = PlayerManager:get()", 1, true))
local factory = assert(text:find("SleepTogetherLogic, gameServer, playerManager", 1, true))
local reg = assert(text:find('addEventHandler("onUpdate", SleepTogetherTick)', 1, true))
local hookOk = assert(text:find("local sleepOk, sleepHandled = pcall(SleepTogetherHandler, player, fields, message)", 1, true))
local hookRet = assert(text:find("if sleepOk and sleepHandled then return end", 1, true))
local flagsLine = assert(text:find('local flags = tonumber(fields["flags"]) or 0', 1, true))
local relay = assert(text:find("relayToTarget(fields", 1, true))
assert(a < factory and factory < reg)
assert(flagsLine < hookOk and hookOk < hookRet and hookRet < relay)
assert(text:find("if SleepTogetherTick then", 1, true))
assert(text:find("GENERATED", 1, true))
do
  local embedStart = assert(text:find("-- Sleep Together (embedded", 1, true))
  local embedEnd = assert(text:find("SleepTogetherTick) end", embedStart, true))
  assert(not text:sub(embedStart, embedEnd):find("cancelEvent(", 1, true), "our code must not cancel events")
end

-- generated text == upstream + header + embed block + hook lines only
local upstream = slurp("server/upstream/strpm-chat-relay/main.lua")
local function remove_once(s, from, to_marker, to_len)
  local i = assert(s:find(from, 1, true), from)
  local j = assert(s:find(to_marker, i, true), to_marker)
  j = j + (to_len or #to_marker)
  assert(not s:find(from, i + 1, true), "block occurs twice")
  return s:sub(1, i - 1) .. s:sub(j)
end
local rest = text
local hdr_end = assert(rest:find("\n\n", 1, true))
assert(rest:sub(1, 20) == "-- GENERATED FILE: d")
rest = rest:sub(hdr_end + 2)
rest = remove_once(rest, "\n-- Sleep Together (embedded", "SleepTogetherTick) end\n\n")
local hook = "  local sleepOk, sleepHandled = pcall(SleepTogetherHandler, player, fields, message) -- Sleep Together\n" ..
  "  if sleepOk and sleepHandled then return end\n"
rest = remove_once(rest, hook, hook)
assert(rest == upstream, "generated file must be upstream plus only the known blocks")
-- and, as an order check, every upstream line appears in order
do
  local pos = 1
  for line in (upstream):gmatch("([^\n]*)\n") do
    local s, e = text:find(line .. "\n", pos, true)
    assert(s, "upstream line missing/out of order: " .. line)
    pos = e + 1
  end
end
