-- SPDX-License-Identifier: MIT
-- Copyright (c) 2014-2020 Iruatã Martins dos Santos Souza

local data = require'data'
local np = require'9p'

local conn = np.newconn(io.read,
  function (buf)
    io.write(buf)
    io.output():flush()
  end)

conn:attach("iru", "")

local f, g = conn:newfid(), conn:newfid()

conn:walk(conn.rootfid, f, "/tmp")
conn:clone(f, g)

conn:create(g, "file", 420, 1)

local ftext = "this is a test\n"
local buf = data.new(ftext)

local n = conn:write(g, 0, buf)
if n ~= #buf then
  error("test: expected to write " .. #buf .. " bytes but wrote " .. n)
end

conn:clunk(g)

if pcall(np.walk, conn, conn.rootfid, g,
         "/tmp/.lua9p.non.existant..") ~= false then
  error("test: succeeded when shouldn't (walking to non-existing file)")
end

conn:walk(conn.rootfid, g, "/tmp/file")
conn:open(g, 0)

local st = conn:stat(g)
-- Remove last byte of the file
st.length = st.length - 1

conn:wstat(g, st)

buf = conn:read(g, 0, st.length)

conn:remove(g)

buf:layout{str = {0, #buf, 'string'}}

-- The trailing \n was removed by wstat, we add it again to check the read
if buf.str .. "\n" == ftext then
  io.stderr:write("test ok\n")
else
  error("test failed")
end

conn:clunk(f)
conn:clunk(conn.rootfid)
