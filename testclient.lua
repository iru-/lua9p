local data = require'data'
local np = require'9p'

local msize = np.version()
txbuf = data.new(msize)

local root = np.attach("iru", "")
local f, g = np.newfid(), np.newfid()

np.walk(root, f, "/tmp")
np.walk(f, g)

np.create(g, "file", 420, 1)

local ftext = "this is a test\n"
local buf = data.new(ftext)

local n = np.write(g, 0, buf)
if n ~= #buf then
  error("test: expected to write " .. #buf .. " bytes but wrote " .. n)
end

np.clunk(g)

if pcall(np.walk, root, g, "/tmp/.lua9p.non.existant..") ~= false then
  error("test: succeeded when shouldn't (walking to non-existing file)")
end

np.walk(root, g, "/tmp/file")
np.open(g, 0)

local st = np.stat(g)

-- Remove last byte of the file
st.length = st.length - 1
np.wstat(g, st)

buf = np.read(g, 0, st.length)

np.remove(g)

buf:layout{str = {0, #buf, 'string'}}

-- The trailing \n was removed by wstat, we add it again to check the read
if buf.str .. "\n" == ftext then
  io.stderr:write("test ok\n")
else
  error("test failed")
end

np.clunk(f)
np.clunk(root)
