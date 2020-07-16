local data = require'data'
local np = require'9p'

local function perr(s) io.stderr:write(s) end
local function perrnl(s) perr(s .. "\n") end

local function _test()
  local msize, err = np.version()
  if err then
    perrnl(err)
    return
  end

  txbuf = data.new(msize)
  rxbuf = data.new(msize)

  local err, root = np.attach("iru", "")
  if err then
    perrnl(err)
    return
  end

  local f, g = np.newfid(), np.newfid()

  err = np.walk(root, f, "/tmp")
  if err then
    perrnl(err)
    return
  end

  err = np.walk(f, g)
  if err then
    perrnl(err)
    return
  end

  err = np.create(g, "file", 420, 1)
  if err then
    perrnl(err)
    return
  end

  local ftext = "this is a test\n"
  local buf = data.new(ftext)

  local err, n = np.write(g, 0, buf)
  if err then
    perrnl(err)
    return
  elseif n ~= #buf then
    perrnl("test expected to write " .. #buf .. " bytes but wrote " .. n)
    return
  end

  local err = np.clunk(g)
  if err then
    perrnl(err)
    return
  end

  local err = np.walk(root, g, "/tmp/.lua9p.non.existant..")
  if not err then
    perrnl("test: succeded in walking to non-existing file")
    return
  end

  local err = np.walk(root, g, "/tmp/file")
  if err then
    perrnl(err)
    return
  end

  err = np.open(g, 0)
  if err then
    perrnl(err)
    return
  end

  local err, st = np.stat(g)
  if err then
    perrnl(err)
    return
  end

  -- Remove last byte of the file
  st.length = st.length - 1
  err = np.wstat(g, st)
  if err then
    perrnl(err)
    return
  end

  err, buf = np.read(g, 0, st.length)
  if err then
    perrnl(err)
    return
  end

  err = np.remove(g)
  if err then
    perrnl(err)
    return
  end

  buf:layout{str = {0, #buf, 'string'}}

  -- The trailing \n was removed by wstat, we add it again to check the read
  if buf.str .. "\n" == ftext then
    perrnl("test ok")
  else
    perrnl("test failed")
  end

  np.clunk(f)
  np.clunk(root)
end

_test()
