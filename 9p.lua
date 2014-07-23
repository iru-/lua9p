data = require "data"
dio  = require "data_io"
io   = require "io"

function perr(s) io.stderr:write(s .. "\n") end

-- Returns a 9P number in table format. Offset and size in bytes
function num9p(offset, size)
  return {offset*8, size*8, 'number', 'le'}
end

function putstr(to, s)
  -- XXX if an empty string is passed down, we segfault in setting p.s
  if #s > #to - 2 then return end

  local p = to:segment():layout{len = num9p(0, 2), s = {2, #s, 's'}}

  p.len = #s
  p.s = s
end

function getstr(from)
  local p = from:segment()
  local len = p:layout{len = num9p(0, 2)}.len
  return p:layout{str = {2, len, 's'}}.str
end


function version()
  local Xversion = data.layout{
                   size  = num9p(0, 4),
                   type  = num9p(4, 1), 
                   tag   = num9p(5, 2),
                   msize = num9p(7, 4),
  }

  local txbuf = data.new(19)
  txbuf:layout(Xversion)
  txbuf.size  = 19
  txbuf.type  = 100
  txbuf.tag   = 0
  txbuf.msize = 8192

  putstr(txbuf:segment(11), "9P2000")
  dio.write(txbuf, 0, txbuf.size)

  local rxbuf = data.new(8192)
  rxbuf:layout(Xversion)

  dio.read(rxbuf, 0, 4)
  dio.read(rxbuf, 4, rxbuf.size-4)
  return rxbuf.msize
end

function attach(uname, aname)
  local LTattach = data.layout{
                   size = num9p(0, 4),
                   type = num9p(4, 1),
                   tag  = num9p(5, 2),
                   fid  = num9p(7, 4),
                   afid = num9p(11, 4),
  }

  local LRattach = data.layout{
                   size  = num9p(0, 4),
                   type  = num9p(4, 1),
                   tag   = num9p(5, 2),
                   qtype = num9p(7, 1),
                   qvers = num9p(8, 4),
                   qpath = num9p(12, 8),
  }

  local tx = txbuf:segment()
  tx:layout(LTattach)
  tx.size = 15 + 2 + #uname + 2 + #aname 
  tx.type = 104
  tx.tag  = 0
  tx.fid  = 0
  tx.afid = -1
  putstr(tx:segment(15), uname)
  putstr(tx:segment(15 + 2 + #uname), aname)
  dio.write(tx, 0, tx.size)

  local rx = rxbuf:segment()
  rx:layout(LRattach)
  dio.read(rx, 0, 4)
  dio.read(rx, 4, rx.size-4)
end

function walk(fid, newfid, name)
  local LTwalk = data.layout{
                 size   = num9p(0, 4),
                 type   = num9p(4, 1),
                 tag    = num9p(5, 2),
                 fid    = num9p(7, 4),
                 nfid   = num9p(11, 4),
                 nwname = num9p(15, 2),
  }

  local LRwalk = data.layout{
                 size   = num9p(0, 4),
                 type   = num9p(4, 1),
                 tag    = num9p(5, 2),
                 nwqid  = num9p(7, 2),
  }

  local tx = txbuf:segment()
  tx:layout(LTwalk)

  -- #name == 0 clones the fid 
  tx.size   = 17 + (#name ~= 0 and 2 or 0) + #name
  tx.type   = 110
  tx.tag    = 0
  tx.fid    = fid
  tx.nfid   = newfid
  tx.nwname = (#name ~= 0 and 1 or 0) 
  putstr(tx:segment(17), name)
  dio.write(tx, 0, tx.size)

  local rx = rxbuf:segment()
  rx:layout(LRwalk)
  dio.read(rx, 0, 4)
  dio.read(rx, 4, rx.size-4)
end

function fidclone(fid, newfid)
  walk(fid, newfid, "")
end

function _test()
  msize = version()
  txbuf = data.new(msize)
  rxbuf = data.new(msize)
  attach("iru", "")
  walk(0, 1, "/tmp")
  fidclone(1, 2)
end

_test()
