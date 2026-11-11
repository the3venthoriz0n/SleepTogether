-- Run from the repo root: lua tests/test_handler.lua  (no output, exit 0 on success)
package.path = "server/sleeptogether/?.lua;" .. package.path
local printed = {}
print = function(...) printed[#printed + 1] = table.concat({ ... }, " ") end
local function error_logged()
  for _, l in ipairs(printed) do
    if l:find("[SleepTogether] Error", 1, true) then return true end
  end
  return false
end
local function reset_log() printed = {} end

local logic = dofile("server/sleeptogether/logic.lua")
local make_handler = dofile("server/sleeptogether/handler.lua")

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

local function setup(opts)
  opts = opts or {}
  local calls = { SetTime = {}, Global = {}, Chat = {} }
  local tick = 10000
  local gs = {
    GetTick = function() return tick end,
    SetTime = function(_, h, m, s)
      if opts.settime_error then error("boom") end
      calls.SetTime[#calls.SetTime + 1] = { h, m, s }
    end,
    SendGlobalChatMessage = function(_, t) calls.Global[#calls.Global + 1] = t end,
    SendChatMessage = function(_, id, t) calls.Chat[#calls.Chat + 1] = { id, t } end,
  }
  local players = {}
  for i = 1, opts.count or 3 do players[i] = {} end
  if opts.hidden_len then
    local real = players
    players = setmetatable({}, {
      __index = function(_, i) return real[i] end,
      __len = function() return 0 end,
    })
  end
  local pm = { GetAllPlayers = function() return players end }
  local player = {
    IsPartyLeader = function()
      if opts.leader_error then error("leader boom") end
      return opts.leader
    end,
    GetUsername = function() return "Alice" end,
    GetConnectionId = function() return 77 end,
  }
  if opts.nil_player then player = nil end
  CalendarService = {
    get = function()
      return { GetTimeScale = function()
        if opts.scale_error then error("no scale") end
        return 30
      end }
    end,
  }
  local handler = make_handler(logic, gs, pm)
  local function send(channel, payload)
    local m = env(channel, payload)
    reset_log()
    return pcall(handler, player, fields_of(m), m)
  end
  return calls, send, function(t) tick = t end
end

-- leader advances
do
  local calls, send = setup({ leader = true })
  assert(send("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(#calls.SetTime == 1 and calls.SetTime[1][1] == 8 and calls.SetTime[1][2] == 0 and calls.SetTime[1][3] == 30)
  assert(calls.Global[1] == "[Sleep Together] Alice slept. It is now 08:00.")
  assert(#calls.Chat == 0)
end
-- non-leader denied
do
  local calls, send = setup({ leader = false })
  assert(send("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(#calls.SetTime == 0 and #calls.Global == 0)
  assert(calls.Chat[1][1] == 77 and calls.Chat[1][2] == "[Sleep Together] Only the party leader can advance time.")
end
-- solo non-leader advances
do
  local calls, send = setup({ leader = false, count = 1 })
  assert(send("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(#calls.SetTime == 1)
end
-- rate limited
do
  local calls, send, set_tick = setup({ leader = true })
  assert(send("sleeptogether.v1", "STv1|SLEEP|8"))
  set_tick(12000)
  assert(send("sleeptogether.v1", "STv1|SLEEP|9"))
  assert(#calls.SetTime == 1 and #calls.Global == 1)
  set_tick(15001)
  assert(send("sleeptogether.v1", "STv1|SLEEP|9"))
  assert(#calls.SetTime == 2)
end
-- solo player counted via ipairs (plain table, and table whose # is 0)
do
  local calls, send = setup({ leader = false, count = 1, hidden_len = true })
  assert(send("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(#calls.SetTime == 1 and not error_logged())
  local calls2, send2 = setup({ leader = false, count = 2, hidden_len = true })
  assert(send2("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(#calls2.SetTime == 0 and #calls2.Chat == 1)
end
-- malformed payload and wrong channel are deliberately ignored, not crashes
do
  local calls, send = setup({ leader = true })
  for _, case in ipairs({
    { "sleeptogether.v1", "STv1|SLEEP|99" },
    { "sleeptogether.v1", "garbage" },
    { "other.channel", "STv1|SLEEP|8" },
  }) do
    assert(send(case[1], case[2]))
    assert(not error_logged(), "ignored input must not log an Error")
  end
  assert(#calls.SetTime == 0 and #calls.Global == 0 and #calls.Chat == 0)
  local h = make_handler(logic, {}, {})
  reset_log()
  assert(pcall(h, {}, {}, "STRPM|v2|"))
  assert(pcall(h, nil, nil, nil))
  assert(not error_logged())
end
-- injected faults: logged, no escape, correct outcome
do
  local calls, send = setup({ leader = true, settime_error = true })
  assert(send("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(error_logged())
  assert(#calls.SetTime == 0 and #calls.Global == 0, "no global message when SetTime throws")

  local c2, send2 = setup({ nil_player = true })
  assert(send2("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(error_logged())
  assert(#c2.SetTime == 0 and #c2.Global == 0 and #c2.Chat == 0)

  local c3, send3 = setup({ leader_error = true })
  assert(send3("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(error_logged())
  assert(#c3.SetTime == 0 and #c3.Global == 0 and #c3.Chat == 0)

  local c4, send4 = setup({ leader = true, scale_error = true })
  assert(send4("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(not error_logged(), "scale failure falls back silently")
  assert(c4.SetTime[1][3] == 20 and #c4.Global == 1)
end

-- build
local py = os.getenv("PYTHON") or "python"
assert(os.execute(py .. " -I tools/build_server_resource.py"), "build script failed")
assert(loadfile("package/Server/strpm-chat-relay/main.lua"))
local f = assert(io.open("package/Server/strpm-chat-relay/main.lua", "rb"))
local text = f:read("a"); f:close()
local a = assert(text:find("local playerManager = PlayerManager:get()", 1, true))
local b = assert(text:find("local SleepTogetherHandler", 1, true))
local c = assert(text:find("pcall(SleepTogetherHandler, player, fields, message)", 1, true))
local d = assert(text:find("relayToTarget(fields", 1, true))
assert(a < b and b < c and c < d)
assert(text:find("GENERATED", 1, true))
