local data = require'data'
local np = require'9p'

local socket = require'socket'
local tcp = assert(socket.tcp())

if (#arg ~= 2) then
  error("Usage: lua " .. arg[0] .. " tcp!host!port <walk_path>")
end

local np_addr = {}
for token in arg[1]:gmatch("[^!]+") do
	table.insert(np_addr, token)
end

if (#np_addr ~= 3) then
  error("Bad 9p fileserver address, usage: lua " .. arg[0] .. " tcp!host!port <walk_path>")
end


print("Connecting to " .. np_addr[1] .. "!" .. np_addr[2] .. "!" .. np_addr[3])
local s, err = tcp:connect(np_addr[2], tonumber(np_addr[3]))
if not s then error(err) end

local conn = np.newconn(function (size)
    local size, err = tcp:receive(size)
    if err then error(err) end
    return size
  end,
  function (buf) tcp:send(buf) end)

conn:attach("iru", "")
local f, g = conn:newfid(), conn:newfid()

print("Walking on " .. arg[2])

conn:walk(conn.rootfid, f, arg[2])
conn:clone(f, g)

local st = conn:stat(g)

conn:clunk(f)
conn:clunk(conn.rootfid)
print("Ok")
