-- Run from the repo root: lua tests/test_handler.lua  (no output, exit 0 on success)
package.path = "server/sleeptogether/?.lua;" .. package.path
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
  local pm = { GetAllPlayers = function() return players end }
  local player = {
    IsPartyLeader = function() return opts.leader end,
    GetUsername = function() return "Alice" end,
    GetConnectionId = function() return 77 end,
  }
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
-- malformed payload and wrong channel
do
  local calls, send = setup({ leader = true })
  assert(send("sleeptogether.v1", "STv1|SLEEP|99"))
  assert(send("sleeptogether.v1", "garbage"))
  assert(send("other.channel", "STv1|SLEEP|8"))
  assert(#calls.SetTime == 0 and #calls.Global == 0 and #calls.Chat == 0)
  local h = make_handler(logic, {}, {})
  assert(pcall(h, nil, nil, nil))
  assert(pcall(h, {}, {}, "STRPM|v2|"))
end
-- errors do not escape
do
  local calls, send = setup({ leader = true, settime_error = true })
  assert(send("sleeptogether.v1", "STv1|SLEEP|8"))
  local _, send2 = setup({ leader = true, scale_error = true })
  assert(send2("sleeptogether.v1", "STv1|SLEEP|8"))
  local c3, send3 = setup({ leader = true, scale_error = true })
  assert(send3("sleeptogether.v1", "STv1|SLEEP|8"))
  assert(c3.SetTime[1][3] == 20)
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
