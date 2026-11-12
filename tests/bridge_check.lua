-- Shared by tests/test_logic.lua and tests/test_handler.lua (loaded with dofile from the repo root).
-- client bridge reimplementation (STRPluginMessagingBridgeReceive.cpp AddFragment)
local function read_field(packet, key)
  local start = 1
  while start <= #packet + 1 do
    local stop = string.find(packet, "|", start, true) or (#packet + 1)
    local token = string.sub(packet, start, stop - 1)
    if #token > #key and string.sub(token, 1, #key) == key and string.sub(token, #key + 1, #key + 1) == "=" then
      return string.sub(token, #key + 2)
    end
    if stop == #packet + 1 then break end
    start = stop + 1
  end
  return nil
end
local function parse_unsigned(text)
  if text == nil or not string.match(text, "^%d+$") then return nil end
  return math.tointeger(tonumber(text))
end
local function hex_decode(text)
  if #text % 2 ~= 0 or string.find(text, "[^0-9A-Fa-f]") then return nil end
  return (string.gsub(text, "%x%x", function(h) return string.char(tonumber(h, 16)) end))
end
-- returns payload text, sender id; or nil when the bridge would drop it
local function bridge_accept(envelope)
  local f = {}
  for _, k in ipairs({ "msg", "channel", "sender", "seq", "flags", "part", "parts", "payload" }) do
    f[k] = read_field(envelope, k)
    if f[k] == nil then return nil end
  end
  local sender, seq, flags = parse_unsigned(f.sender), parse_unsigned(f.seq), parse_unsigned(f.flags)
  local part, parts = parse_unsigned(f.part), parse_unsigned(f.parts)
  if not (sender and seq and flags and part and parts) then return nil end
  if sender == 0 or part == 0 or parts == 0 or part > parts or f.channel == "" then return nil end
  local text = hex_decode(f.payload)
  if text == nil then return nil end
  return text, sender
end

return { read_field = read_field, bridge_accept = bridge_accept }
